require "test_helper"

class FanOutTest < ActiveSupport::TestCase
  def build_user
    User.create!(
      email: "fanout-#{SecureRandom.hex(6)}@example.com",
      password: "test-password-123"
    )
  end

  def build_account(user:, name:, role:, login:, equity: nil, online: false, max_lot: 5)
    TradingAccount.create!(
      user: user,
      name: name,
      role: role,
      login: login,
      equity: equity,
      last_seen_at: online ? Time.current : nil,
      guards: { "max_lot" => max_lot }
    )
  end

  def build_event(master:, event_type:, ticket:)
    TradeEvent.create!(
      trading_account: master,
      event_type: event_type,
      master_ticket: ticket,
      symbol: "EURUSD",
      side: "buy",
      volume: "0.50",
      idempotency_key: SecureRandom.uuid
    )
  end

  def build_auto_link(user:, master:, slave:)
    CopyLink.create!(
      user: user,
      master_account: master,
      slave_account: slave,
      lot_mode: "equity_auto",
      lot_value: "0.01"
    )
  end

  test "sizes each slave independently and sends fixed lots to the EA" do
    user = build_user
    master = build_account(user: user, name: "Master", role: "master", login: 1001)
    small = build_account(
      user: user, name: "Small", role: "slave", login: 1002,
      equity: 500, online: true
    )
    large = build_account(
      user: user, name: "Large", role: "slave", login: 1003,
      equity: 1_000, online: true
    )

    build_auto_link(user: user, master: master, slave: small)
    build_auto_link(user: user, master: master, slave: large)

    event = build_event(master: master, event_type: "open", ticket: 7001)
    FanOut.call(event)

    small_command = Command.find_by!(trading_account: small, trade_event: event)
    large_command = Command.find_by!(trading_account: large, trade_event: event)

    assert_equal BigDecimal("0.05"), small_command.volume
    assert_equal BigDecimal("0.05"), small_command.lot_value
    assert_equal "fixed", small_command.lot_mode

    assert_equal BigDecimal("0.10"), large_command.volume
    assert_equal BigDecimal("0.10"), large_command.lot_value
    assert_equal "fixed", large_command.lot_mode

    assert_equal BigDecimal("0.05"), small_command.trade_mapping.volume
    assert_equal BigDecimal("0.10"), large_command.trade_mapping.volume
  end

  test "pending order fill reuses the originally calculated volume" do
    user = build_user
    master = build_account(user: user, name: "Master", role: "master", login: 2001)
    slave = build_account(
      user: user, name: "Slave", role: "slave", login: 2002,
      equity: 500, online: true
    )
    link = build_auto_link(user: user, master: master, slave: slave)

    pending_event = build_event(master: master, event_type: "pending_place", ticket: 8001)
    FanOut.call(pending_event)

    mapping = TradeMapping.find_by!(copy_link: link, master_ticket: 8001)
    assert_equal BigDecimal("0.05"), mapping.volume

    slave.update!(equity: 2_000)

    fill_event = build_event(master: master, event_type: "open", ticket: 8001)
    FanOut.call(fill_event)

    mapping.reload
    fill_command = Command.find_by!(trading_account: slave, trade_event: fill_event)

    assert_equal "open_requested", mapping.state
    assert_equal BigDecimal("0.05"), mapping.volume
    assert_equal BigDecimal("0.05"), fill_command.volume
    assert_equal BigDecimal("0.05"), fill_command.lot_value
    assert_equal "fixed", fill_command.lot_mode
  end

  test "skips automatic sizing for a stale slave without creating a mapping" do
    user = build_user
    master = build_account(user: user, name: "Master", role: "master", login: 3001)
    slave = build_account(
      user: user, name: "Slave", role: "slave", login: 3002,
      equity: 500, online: false
    )
    build_auto_link(user: user, master: master, slave: slave)

    event = build_event(master: master, event_type: "open", ticket: 9001)
    FanOut.call(event)

    command = Command.find_by!(trading_account: slave, trade_event: event)

    assert_equal "skipped", command.status
    assert_match(/automatic lot sizing failed/, command.result_message)
    assert_nil command.trade_mapping
    assert_not TradeMapping.exists?(trading_account: slave, master_ticket: 9001)
  end

  test "does not copy a fill as a market trade when its pending placement was skipped" do
    user = build_user
    master = build_account(user: user, name: "Master", role: "master", login: 4001)
    slave = build_account(
      user: user, name: "Slave", role: "slave", login: 4002,
      equity: 500, online: false
    )
    build_auto_link(user: user, master: master, slave: slave)

    pending_event = build_event(master: master, event_type: "pending_place", ticket: 10001)
    FanOut.call(pending_event)

    skipped_command = Command.find_by!(trading_account: slave, trade_event: pending_event)
    assert_equal "skipped", skipped_command.status
    assert_nil skipped_command.trade_mapping

    slave.update!(last_seen_at: Time.current)

    fill_event = build_event(master: master, event_type: "open", ticket: 10001)
    FanOut.call(fill_event)

    assert_not Command.exists?(trading_account: slave, trade_event: fill_event)
    assert_not TradeMapping.exists?(trading_account: slave, master_ticket: 10001)
  end
end
