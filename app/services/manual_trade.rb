# Trades placed from the dashboard rather than copied from a master.
# Both account roles can receive them: a slave EA opens a standalone trade; a master EA
# opens a trade that its own events then copy to the followers.
class ManualTrade
  class Error < StandardError; end

  SYMBOL_FORMAT = /\A[\w.\-#+]{1,32}\z/

  def self.open(account:, symbol:, side:, lot_value:, lot_mode: "fixed", sl: nil, tp: nil, batch_key: SecureRandom.hex(6))
    raise Error, "account is paused or its kill switch is on" unless account.accepting_trades?
    raise Error, "invalid symbol" unless symbol.to_s.match?(SYMBOL_FORMAT)
    raise Error, "side must be buy or sell" unless %w[buy sell].include?(side.to_s)
    raise Error, "lot_mode must be fixed or risk_pct" unless %w[fixed risk_pct].include?(lot_mode.to_s)
    raise Error, "lot size must be greater than 0" unless lot_value.to_d.positive?
    raise Error, "risk mode needs a stop loss" if lot_mode.to_s == "risk_pct" && sl.blank?
    raise Error, "risk percentage cannot exceed 100%" if lot_mode.to_s == "risk_pct" && lot_value.to_d > 100
    raise Error, "master accounts accept fixed lots only" if account.master? && lot_mode.to_s != "fixed"

    fixed = lot_mode.to_s == "fixed"
    link = account.slave? ? account.slave_links.order(:id).first : nil
    attrs = {
      trading_account: account, action: "open", symbol: symbol, side: side, batch_key: batch_key,
      volume: fixed ? lot_value : 0, price: 0, sl: sl.presence || 0, tp: tp.presence || 0,
      lot_mode: lot_mode, lot_value: lot_value, master_balance: 0,
      max_slippage: link&.max_slippage, symbol_suffix: link&.symbol_suffix.to_s
    }

    TradeMapping.transaction do
      if account.slave?
        attrs[:trade_mapping] = TradeMapping.create!(
          trading_account: account, symbol: symbol, side: side, state: "open_requested",
          volume: fixed ? lot_value : nil
        )
      end
      Command.create!(attrs)
    end
  end

  # Close one broker position by its raw ticket (what the dashboard's "x" button does).
  def self.close_ticket(account, ticket, symbol: nil, side: nil, volume: nil, batch_key: SecureRandom.hex(6))
    Command.create!(
      trading_account: account, action: "close_ticket", target_ticket: ticket.to_i,
      symbol: symbol.to_s, side: side.to_s, volume: volume || 0, batch_key: batch_key
    )
  end

  def self.close_mapping(mapping)
    raise Error, "trade is not open" unless mapping.holding?
    mapping.enqueue_close! || raise(Error, "a close is already in progress")
  end

  def self.close_all(account)
    Command.create!(trading_account: account, action: "close_all", symbol: "", side: "")
  end
end
