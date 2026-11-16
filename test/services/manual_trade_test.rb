require "test_helper"

class ManualTradeTest < ActiveSupport::TestCase
  def build_user
    User.create!(
      email: "manual-trade-#{SecureRandom.hex(6)}@example.com",
      password: "test-password-123"
    )
  end

  def build_slave(user:, equity:, online: true, max_lot: 5)
    TradingAccount.create!(
      user: user,
      name: "Slave",
      role: "slave",
      login: SecureRandom.random_number(1_000_000) + 1,
      equity: equity,
      last_seen_at: online ? Time.current : nil,
      guards: { "max_lot" => max_lot }
    )
  end

  test "creates a manual trade using calculated equity auto volume" do
    user = build_user
    account = build_slave(user: user, equity: 500)

    command = ManualTrade.open(
      account: account,
      symbol: "EURUSD",
      side: "buy",
      lot_value: nil,
      lot_mode: "equity_auto"
    )

    assert_equal "open", command.action
    assert_equal "fixed", command.lot_mode
    assert_equal BigDecimal("0.05"), command.volume
    assert_equal BigDecimal("0.05"), command.lot_value

    mapping = command.trade_mapping
    assert mapping.present?
    assert_equal BigDecimal("0.05"), mapping.volume
    assert_equal "open_requested", mapping.state
  end

  test "rejects equity auto trade for an offline slave without creating records" do
    user = build_user
    account = build_slave(user: user, equity: 500, online: false)

    assert_raises(ManualTrade::Error) do
      ManualTrade.open(
        account: account,
        symbol: "EURUSD",
        side: "buy",
        lot_value: nil,
        lot_mode: "equity_auto"
      )
    end

    assert_equal 0, Command.where(trading_account: account).count
    assert_equal 0, TradeMapping.where(trading_account: account).count
  end

  test "rejects calculated volume above the account max lot" do
    user = build_user
    account = build_slave(user: user, equity: 500, max_lot: 0.02)

    error = assert_raises(ManualTrade::Error) do
      ManualTrade.open(
        account: account,
        symbol: "EURUSD",
        side: "buy",
        lot_value: nil,
        lot_mode: "equity_auto"
      )
    end

    assert_match(/exceeds max_lot/, error.message)
    assert_equal 0, Command.where(trading_account: account).count
    assert_equal 0, TradeMapping.where(trading_account: account).count
  end

  test "creates pending orders with entry price and pending mapping state" do
    %w[buy_limit sell_limit buy_stop sell_stop].each do |side|
      user = build_user
      account = build_slave(user: user, equity: 500)

      command = ManualTrade.open(
        account: account,
        symbol: "EURUSD",
        side: side,
        lot_value: 0.1,
        entry_price: 1.085
      )

      assert_equal "pending_place", command.action
      assert_equal side, command.side
      assert_equal BigDecimal("1.085"), command.price
      assert_equal BigDecimal("0.1"), command.volume
      assert_equal "pending_requested", command.trade_mapping.state
    end
  end

  test "rejects pending orders without a valid entry price" do
    user = build_user
    account = build_slave(user: user, equity: 500)

    [nil, "", "0", "-1"].each do |price|
      assert_raises(ManualTrade::Error) do
        ManualTrade.open(
          account: account,
          symbol: "EURUSD",
          side: "buy_limit",
          lot_value: 0.1,
          entry_price: price
        )
      end
    end

    assert_equal 0, Command.where(trading_account: account).count
    assert_equal 0, TradeMapping.where(trading_account: account).count
  end

end
