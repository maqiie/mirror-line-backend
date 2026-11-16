require "test_helper"

class UserSessionRefreshTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "refresh-token-test@example.com",
      password: "SecurePassword123!"
    )

    @session, = UserSession.issue!(user: @user)

    @token = @session.refresh_tokens.first
  end

  test "is usable when unconsumed and not expired" do
    assert @token.usable?
  end

  test "is not usable after being consumed" do
    assert @token.consume!

    @token.reload
    assert_not @token.usable?
  end

  test "cannot consume the same token twice" do
    assert @token.consume!
    assert_not @token.consume!
  end

  test "cannot consume an expired token" do
    @token.update_column(:expires_at, 1.minute.ago)

    assert_not @token.consume!
    assert_nil @token.reload.consumed_at
  end

  test "cannot consume an already consumed token" do
    @token.update_column(:consumed_at, Time.current)

    assert_not @token.consume!
  end
end
