require "test_helper"

class ApiV1OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "orders-#{SecureRandom.hex(6)}@example.com",
      password: "SecurePassword123!",
      email_verified_at: Time.current
    )

    _session, @access_token, = UserSession.issue!(user: @user)

    @account = TradingAccount.create!(
      user: @user,
      name: "Auto Slave",
      role: "slave",
      login: SecureRandom.random_number(1_000_000) + 1,
      equity: 500,
      last_seen_at: Time.current,
      guards: { "max_lot" => 5 }
    )
  end

  test "creates an equity auto website order using the slave equity" do
    post "/api/v1/orders",
      params: {
        account_ids: [@account.id],
        symbol: "EURUSD",
        side: "buy",
        lot_mode: "equity_auto"
      },
      headers: { "Authorization" => "Bearer #{@access_token}" },
      as: :json

    assert_response :created

    body = response.parsed_body
    assert_equal 1, body["sent"]

    command = Command.find_by!(trading_account: @account)

    assert_equal "open", command.action
    assert_equal "fixed", command.lot_mode
    assert_equal BigDecimal("0.05"), command.volume
    assert_equal BigDecimal("0.05"), command.lot_value
    assert_equal BigDecimal("0.05"), command.trade_mapping.volume
  end

  test "returns unprocessable entity when auto sizing cannot use a stale account" do
    @account.update!(last_seen_at: 31.seconds.ago)

    post "/api/v1/orders",
      params: {
        account_ids: [@account.id],
        symbol: "EURUSD",
        side: "buy",
        lot_mode: "equity_auto"
      },
      headers: { "Authorization" => "Bearer #{@access_token}" },
      as: :json

    assert_response :unprocessable_entity
    assert_match(/offline or heartbeat is stale/, response.parsed_body["error"])
    assert_equal 0, Command.where(trading_account: @account).count
    assert_equal 0, TradeMapping.where(trading_account: @account).count
  end

  test "creates all four pending website order types" do
    %w[buy_limit sell_limit buy_stop sell_stop].each do |side|
      post "/api/v1/orders",
        params: {
          account_ids: [@account.id],
          symbol: "EURUSD",
          side: side,
          volume: 0.1,
          price: 1.085
        },
        headers: { "Authorization" => "Bearer #{@access_token}" },
        as: :json

      assert_response :created, "Expected #{side} to be accepted"
      command = Command.where(trading_account: @account).order(:id).last

      assert_equal "pending_place", command.action
      assert_equal side, command.side
      assert_equal BigDecimal("1.085"), command.price
      assert_equal "pending_requested", command.trade_mapping.state
    end
  end

  test "rejects pending website orders without a valid entry price" do
    [nil, "", "0", "-1"].each do |price|
      post "/api/v1/orders",
        params: {
          account_ids: [@account.id],
          symbol: "EURUSD",
          side: "buy_limit",
          volume: 0.1,
          price: price
        },
        headers: { "Authorization" => "Bearer #{@access_token}" },
        as: :json

      assert_response :unprocessable_entity
    end

    assert_equal 0, Command.where(trading_account: @account).count
    assert_equal 0, TradeMapping.where(trading_account: @account).count
  end

end
