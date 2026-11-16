require "test_helper"

class EquityAutoLotSizerTest < ActiveSupport::TestCase
  def build_account(equity:, role: "slave", last_seen_at: Time.current, guards: {})
    TradingAccount.new(
      role: role,
      equity: equity,
      last_seen_at: last_seen_at,
      guards: { "max_lot" => 1_000 }.merge(guards)
    )
  end

  test "calculates the expected lot sizes from equity" do
    {
      50 => "0.01",
      100 => "0.01",
      200 => "0.02",
      500 => "0.05",
      1_000 => "0.10",
      5_000 => "0.50",
      10_000 => "1.00",
      100_000 => "10.00",
      1_000_000 => "100.00"
    }.each do |equity, expected|
      account = build_account(equity: equity)

      assert_equal BigDecimal(expected), EquityAutoLotSizer.call(account),
        "Expected #{equity} equity to produce #{expected} lots"
    end
  end

  test "rounds down to the previous 100 dollar equity step" do
    account = build_account(equity: 199.99)

    assert_equal BigDecimal("0.01"), EquityAutoLotSizer.call(account)
  end

  test "rejects missing or non-positive equity" do
    [nil, 0, -100].each do |equity|
      account = build_account(equity: equity)

      assert_raises(EquityAutoLotSizer::Error) do
        EquityAutoLotSizer.call(account)
      end
    end
  end

  test "rejects offline accounts" do
    account = build_account(equity: 500, last_seen_at: 31.seconds.ago)

    error = assert_raises(EquityAutoLotSizer::Error) do
      EquityAutoLotSizer.call(account)
    end

    assert_equal "slave account is offline or heartbeat is stale", error.message
  end

  test "rejects master accounts" do
    account = build_account(equity: 500, role: "master")

    assert_raises(EquityAutoLotSizer::Error) do
      EquityAutoLotSizer.call(account)
    end
  end

  test "rejects calculated lots above the account max_lot guard" do
    account = build_account(equity: 1_000, guards: { "max_lot" => 0.05 })

    error = assert_raises(EquityAutoLotSizer::Error) do
      EquityAutoLotSizer.call(account)
    end

    assert_match(/exceeds max_lot/, error.message)
  end
end
