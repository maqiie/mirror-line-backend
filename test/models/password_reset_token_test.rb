require "test_helper"

class PasswordResetTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "password-reset-test@example.com",
      password: "SecurePassword123!"
    )
  end

  test "issues a random token and stores only its digest" do
    record, raw_token = PasswordResetToken.issue!(user: @user)

    assert raw_token.present?
    assert_equal 64, record.token_digest.length
    assert_equal PasswordResetToken.digest(raw_token), record.token_digest
    assert_not_equal raw_token, record.token_digest
    assert record.expires_at.future?
  end

  test "finds a valid unused token" do
    record, raw_token = PasswordResetToken.issue!(user: @user)

    assert_equal record, PasswordResetToken.find_usable(raw_token)
  end

  test "rejects an unknown token" do
    assert_nil PasswordResetToken.find_usable("unknown-token")
  end

  test "rejects a used token" do
    record, raw_token = PasswordResetToken.issue!(user: @user)
    record.update!(used_at: Time.current)

    assert_nil PasswordResetToken.find_usable(raw_token)
  end

  test "rejects an expired token" do
    record, raw_token = PasswordResetToken.issue!(user: @user)
    record.update!(expires_at: 1.minute.ago)

    assert_nil PasswordResetToken.find_usable(raw_token)
    assert_not record.consume!
  end

  test "consumes a token only once" do
    record, raw_token = PasswordResetToken.issue!(user: @user)

    assert record.consume!
    assert_not record.consume!
    assert_nil PasswordResetToken.find_usable(raw_token)
  end
end
