require "test_helper"

class ApiV1PositionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "positions-#{SecureRandom.hex(6)}@example.com",
      password: "SecurePassword123!",
      email_verified_at: Time.current
    )

    _session, @access_token, = UserSession.issue!(user: @user)

    @account = TradingAccount.create!(
      user: @user,
      name: "Master",
      role: "master",
      login: SecureRandom.random_number(1_000_000) + 1,
      guards: { "max_lot" => 5 }
    )

    @broker_ticket = 123456
    @account.update!(
      positions: [{
        "t" => @broker_ticket,
        "s" => "EURUSD",
        "d" => "buy",
        "v" => 0.1,
        "sl" => 1.0800,
        "tp" => 1.1000
      }]
    )

    @dashboard_ticket = DashboardSnapshot.encode_ticket(@account.id, @broker_ticket)
    @headers = { "Authorization" => "Bearer #{@access_token}" }
  end

  test "creates a direct-ticket SL/TP modification command" do
    post "/api/v1/positions/#{@dashboard_ticket}/modify",
      params: { sl: "1.0850", tp: "1.1050" },
      headers: @headers,
      as: :json

    assert_response :accepted

    command = Command.find_by!(trading_account: @account)
    assert_equal "modify_ticket", command.action
    assert_equal @broker_ticket, command.target_ticket
    assert_equal BigDecimal("1.0850"), command.sl
    assert_equal BigDecimal("1.1050"), command.tp
  end

  test "blank SL clears it while omitted TP retains its current value" do
    post "/api/v1/positions/#{@dashboard_ticket}/modify",
      params: { sl: "" },
      headers: @headers,
      as: :json

    assert_response :accepted

    command = Command.find_by!(trading_account: @account)
    assert_equal BigDecimal("0"), command.sl
    assert_equal BigDecimal("1.1000"), command.tp
  end

  test "rejects negative stop values" do
    post "/api/v1/positions/#{@dashboard_ticket}/modify",
      params: { sl: "-1" },
      headers: @headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal 0, Command.where(trading_account: @account).count
  end

  test "cannot modify a position belonging to another user" do
    other_user = User.create!(
      email: "other-positions-#{SecureRandom.hex(6)}@example.com",
      password: "SecurePassword123!",
      email_verified_at: Time.current
    )

    other_account = TradingAccount.create!(
      user: other_user,
      name: "Other Master",
      role: "master",
      login: SecureRandom.random_number(1_000_000) + 1,
      guards: { "max_lot" => 5 }
    )

    foreign_ticket = DashboardSnapshot.encode_ticket(other_account.id, @broker_ticket)

    post "/api/v1/positions/#{foreign_ticket}/modify",
      params: { sl: "1.0850", tp: "1.1050" },
      headers: @headers,
      as: :json

    assert_response :not_found
    assert_equal 0, Command.where(trading_account: other_account).count
  end
end
