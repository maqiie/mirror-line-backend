# Trades placed from the dashboard rather than copied from a master.
# Both account roles can receive them: a slave EA opens a standalone trade; a master EA
# opens a trade that its own events then copy to the followers.
class ManualTrade
  class Error < StandardError; end

  SYMBOL_FORMAT = /\A[\w.\-#+]{1,32}\z/

  def self.open(account:, symbol:, side:, lot_value:, lot_mode: "fixed", sl: nil, tp: nil, entry_price: nil, batch_key: SecureRandom.hex(6))
    raise Error, "account is paused or its kill switch is on" unless account.accepting_trades?
    raise Error, "invalid symbol" unless symbol.to_s.match?(SYMBOL_FORMAT)

    market_sides = %w[buy sell]
    pending_sides = %w[buy_limit sell_limit buy_stop sell_stop]
    raise Error, "unsupported order side" unless (market_sides + pending_sides).include?(side.to_s)

    pending = pending_sides.include?(side.to_s)
    if pending && (!entry_price.present? || !entry_price.to_d.positive?)
      raise Error, "pending orders require a valid entry price"
    end
    mode = lot_mode.to_s
    raise Error, "unsupported lot_mode" unless %w[fixed risk_pct equity_auto].include?(mode)
    raise Error, "lot size must be greater than 0" if mode != "equity_auto" && !lot_value.to_d.positive?
    raise Error, "risk mode needs a stop loss" if mode == "risk_pct" && sl.blank?
    raise Error, "risk percentage cannot exceed 100%" if mode == "risk_pct" && lot_value.to_d > 100
    raise Error, "master accounts accept fixed lots only" if account.master? && mode != "fixed"

    calculated_volume =
      if mode == "equity_auto"
        begin
          EquityAutoLotSizer.call(account)
        rescue EquityAutoLotSizer::Error => e
          raise Error, e.message
        end
      end
    command_mode = mode == "equity_auto" ? "fixed" : mode
    command_value = mode == "equity_auto" ? calculated_volume : lot_value
    fixed = command_mode == "fixed"

    link = account.slave? ? account.slave_links.order(:id).first : nil
    attrs = {
      trading_account: account, action: pending ? "pending_place" : "open",
      symbol: symbol, side: side, batch_key: batch_key,
      volume: fixed ? command_value : 0, price: pending ? entry_price : 0,
      sl: sl.presence || 0, tp: tp.presence || 0,
      lot_mode: command_mode, lot_value: command_value, master_balance: 0,
      max_slippage: link&.max_slippage, symbol_suffix: link&.symbol_suffix.to_s
    }

    TradeMapping.transaction do
      if account.slave?
        attrs[:trade_mapping] = TradeMapping.create!(
          trading_account: account, symbol: symbol, side: side,
          state: pending ? "pending_requested" : "open_requested",
          volume: fixed ? command_value : nil
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
