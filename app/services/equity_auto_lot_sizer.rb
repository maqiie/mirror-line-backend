class EquityAutoLotSizer
  MIN_LOT = BigDecimal("0.01")
  EQUITY_PER_LOT_STEP = BigDecimal("100")
  LOT_INCREMENT = BigDecimal("0.01")

  class Error < StandardError; end

  def self.call(account)
    new(account).call
  end

  def initialize(account)
    @account = account
  end

  def call
    raise Error, "automatic sizing is only available for slave accounts" unless @account.slave?
    raise Error, "slave account is offline or heartbeat is stale" unless @account.online?

    equity = @account.equity&.to_d
    raise Error, "slave equity is missing or invalid" unless equity&.positive?

    steps = (equity / EQUITY_PER_LOT_STEP).floor
    lots = [MIN_LOT, steps * LOT_INCREMENT].max

    max_lot = @account.effective_guards.fetch("max_lot").to_d
    raise Error, "calculated lot size #{lots.to_s('F')} exceeds max_lot #{max_lot.to_s('F')}" if lots > max_lot

    lots
  end
end
