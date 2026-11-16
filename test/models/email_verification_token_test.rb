require "test_helper"

class EmailVerificationTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "email-verification-test@example.com",
      password: "SecurePassword123!"
    )
  end

  test "issues a random token and stores only its digest" do
    record, raw_token = EmailVerificationToken.issue!(user: @user)

    assert raw_token.present?
    assert_equal 64, record.token_digest.length
    assert_equal EmailVerificationToken.digest(raw_token), record.token_digest
    assert_not_equal raw_token, record.token_digest
    assert record.expires_at.future?
  end

  test "finds a valid unused token" do
    record, raw_token = EmailVerificationToken.issue!(user: @user)

    assert_equal record, EmailVerificationToken.find_usable(raw_token)
  end

  test "rejects an unknown token" do
    assert_nil EmailVerificationToken.find_usable("unknown-token")
  end

  test "rejects a used token" do
    record, raw_token = EmailVerificationToken.issue!(user: @user)
    record.update!(used_at: Time.current)

    assert_nil EmailVerificationToken.find_usable(raw_token)
  end

  test "rejects an expired token" do
    record, raw_token = EmailVerificationToken.issue!(user: @user)
    record.update!(expires_at: 1.minute.ago)

    assert_nil EmailVerificationToken.find_usable(raw_token)
    assert_not record.consume!
  end

  test "consumes a token only once" do
    record, raw_token = EmailVerificationToken.issue!(user: @user)

    assert record.consume!
    assert_not record.consume!
    assert_nil EmailVerificationToken.find_usable(raw_token)
  end

  test "issuing a new token invalidates previous unused tokens" do
    old_record, old_token = EmailVerificationToken.issue!(user: @user)
    new_record, new_token = EmailVerificationToken.issue!(user: @user)

    assert_not old_record.reload.used_at.nil?
    assert_nil EmailVerificationToken.find_usable(old_token)
    assert_equal new_record, EmailVerificationToken.find_usable(new_token)
  end
end
