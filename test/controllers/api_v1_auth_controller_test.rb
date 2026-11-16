require "test_helper"
require "minitest/mock"

class ApiV1AuthControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  setup do
    @user = User.create!(
      email: "auth-controller-test@example.com",
      password: "SecurePassword123!",
      email_verified_at: Time.current
    )
  end

  test "logs in and returns access and refresh tokens" do
    post "/api/v1/session",
      params: {
        email: "AUTH-CONTROLLER-TEST@example.com",
        password: "SecurePassword123!"
      },
      as: :json

    assert_response :success

    body = response.parsed_body

    assert body["token"].present?
    assert body["refresh_token"].present?
    assert_equal 900, body["expires_in"]
    assert_equal 2_592_000, body["refresh_expires_in"]
    assert_equal @user.id, body.dig("user", "id")
    assert_equal @user.email, body.dig("user", "email")
  end

  test "rejects invalid login credentials" do
    post "/api/v1/session",
      params: {
        email: @user.email,
        password: "wrong-password"
      },
      as: :json

    assert_response :unauthorized
    assert_equal "invalid credentials", response.parsed_body["error"]
  end

  test "rotates a valid refresh token" do
    _session, access_token, refresh_token =
      UserSession.issue!(user: @user)

    post "/api/v1/auth/refresh",
      params: { refresh_token: refresh_token },
      as: :json

    assert_response :success

    body = response.parsed_body

    assert body["token"].present?
    assert body["refresh_token"].present?
    assert_not_equal access_token, body["token"]
    assert_not_equal refresh_token, body["refresh_token"]
  end

  test "rejects refresh token replay" do
    session, _access_token, refresh_token =
      UserSession.issue!(user: @user)

    post "/api/v1/auth/refresh",
      params: { refresh_token: refresh_token },
      as: :json

    assert_response :success

    post "/api/v1/auth/refresh",
      params: { refresh_token: refresh_token },
      as: :json

    assert_response :unauthorized
    assert session.reload.revoked_at.present?
  end

  test "logs out and revokes the current session" do
    session, access_token, = UserSession.issue!(user: @user)

    delete "/api/v1/session",
      headers: { "Authorization" => "Bearer #{access_token}" }

    assert_response :success
    assert session.reload.revoked_at.present?

    get "/api/v1/dashboard",
      headers: { "Authorization" => "Bearer #{access_token}" }

    assert_response :unauthorized
  end

  test "rejects password change with incorrect current password" do
    session, access_token, = UserSession.issue!(user: @user)

    patch "/api/v1/password/change",
      params: {
        current_password: "wrong-password",
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "AnotherSecurePassword456!"
      },
      headers: { "Authorization" => "Bearer #{access_token}" },
      as: :json

    assert_response :unauthorized
    assert @user.reload.authenticate("SecurePassword123!")
    assert_nil session.reload.revoked_at
  end

  test "rejects password change when confirmation does not match" do
    session, access_token, = UserSession.issue!(user: @user)

    patch "/api/v1/password/change",
      params: {
        current_password: "SecurePassword123!",
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "DifferentSecurePassword456!"
      },
      headers: { "Authorization" => "Bearer #{access_token}" },
      as: :json

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("SecurePassword123!")
    assert_nil session.reload.revoked_at
  end

  test "rejects password change when new password is too short" do
    session, access_token, = UserSession.issue!(user: @user)

    patch "/api/v1/password/change",
      params: {
        current_password: "SecurePassword123!",
        new_password: "short",
        password_confirmation: "short"
      },
      headers: { "Authorization" => "Bearer #{access_token}" },
      as: :json

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("SecurePassword123!")
    assert_nil session.reload.revoked_at
  end

  test "changes password and revokes all sessions" do
    _first_session, access_token, = UserSession.issue!(user: @user)
    second_session, = UserSession.issue!(user: @user)

    patch "/api/v1/password/change",
      params: {
        current_password: "SecurePassword123!",
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "AnotherSecurePassword456!"
      },
      headers: { "Authorization" => "Bearer #{access_token}" },
      as: :json

    assert_response :success
    assert @user.reload.authenticate("AnotherSecurePassword456!")
    assert_not @user.authenticate("SecurePassword123!")
    assert @user.user_sessions.where(revoked_at: nil).none?
    assert second_session.reload.revoked_at.present?
  end

  test "forgot password returns the same generic response for an existing account" do
    assert_emails 1 do
      post "/api/v1/auth/password/forgot",
        params: { email: @user.email },
        as: :json
    end

    assert_response :success
    assert_equal(
      "If an account exists for that email, password reset instructions will be sent.",
      response.parsed_body["message"]
    )

    email = ActionMailer::Base.deliveries.last
    assert_equal [@user.email], email.to
    assert_equal "Reset your Mirrorline password", email.subject

    token = @user.password_reset_tokens.last
    assert token.present?
    assert_equal 64, token.token_digest.length
    assert_not_includes response.body, token.token_digest
  end

  test "invalidates reset token when email delivery fails" do
    failing_email = Object.new
    failing_email.define_singleton_method(:deliver_now) do
      raise StandardError, "simulated delivery failure"
    end

    PasswordResetMailer.stub(:reset_email, failing_email) do
      post "/api/v1/auth/password/forgot",
        params: { email: @user.email },
        as: :json
    end

    assert_response :success

    token = @user.password_reset_tokens.order(:created_at).last
    assert token.present?
    assert token.used_at.present?
  end

  test "forgot password returns the same generic response for an unknown account" do
    assert_no_emails do
      post "/api/v1/auth/password/forgot",
        params: { email: "unknown-account@example.com" },
        as: :json
    end

    assert_response :success
    assert_equal(
      "If an account exists for that email, password reset instructions will be sent.",
      response.parsed_body["message"]
    )
  end

  test "forgot password limits requests per email without revealing account existence" do
    3.times do
      post "/api/v1/auth/password/forgot",
        params: { email: @user.email },
        as: :json

      assert_response :success
    end

    assert_no_emails do
      post "/api/v1/auth/password/forgot",
        params: { email: @user.email },
        as: :json
    end

    assert_response :success
    assert_equal 3, ActionMailer::Base.deliveries.count
  end

  test "forgot password limits requests per IP" do
    10.times do |index|
      post "/api/v1/auth/password/forgot",
        params: { email: "unknown-#{index}@example.com" },
        as: :json

      assert_response :success
    end

    assert_no_emails do
      post "/api/v1/auth/password/forgot",
        params: { email: @user.email },
        as: :json
    end

    assert_response :success
    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  test "resets password and revokes sessions and other reset tokens" do
    first_session, access_token, = UserSession.issue!(user: @user)
    second_session, = UserSession.issue!(user: @user)

    reset_record, raw_token = PasswordResetToken.issue!(user: @user)
    other_record, = PasswordResetToken.issue!(user: @user)

    post "/api/v1/auth/password/reset",
      params: {
        token: raw_token,
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "AnotherSecurePassword456!"
      },
      as: :json

    assert_response :success
    assert @user.reload.authenticate("AnotherSecurePassword456!")
    assert_not @user.authenticate("SecurePassword123!")
    assert reset_record.reload.used_at.present?
    assert other_record.reload.used_at.present?
    assert first_session.reload.revoked_at.present?
    assert second_session.reload.revoked_at.present?

    get "/api/v1/dashboard",
      headers: { "Authorization" => "Bearer #{access_token}" }

    assert_response :unauthorized
  end

  test "rejects password reset token replay" do
    _record, raw_token = PasswordResetToken.issue!(user: @user)

    params = {
      token: raw_token,
      new_password: "AnotherSecurePassword456!",
      password_confirmation: "AnotherSecurePassword456!"
    }

    post "/api/v1/auth/password/reset", params: params, as: :json
    assert_response :success

    post "/api/v1/auth/password/reset", params: params, as: :json
    assert_response :unprocessable_entity
  end

  test "rejects expired password reset tokens" do
    record, raw_token = PasswordResetToken.issue!(user: @user)
    record.update!(expires_at: 1.minute.ago)

    post "/api/v1/auth/password/reset",
      params: {
        token: raw_token,
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "AnotherSecurePassword456!"
      },
      as: :json

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("SecurePassword123!")
  end

  test "rejects password reset when confirmation does not match" do
    _record, raw_token = PasswordResetToken.issue!(user: @user)

    post "/api/v1/auth/password/reset",
      params: {
        token: raw_token,
        new_password: "AnotherSecurePassword456!",
        password_confirmation: "DifferentSecurePassword456!"
      },
      as: :json

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("SecurePassword123!")
  end

  test "rejects password reset when the new password is too short" do
    _record, raw_token = PasswordResetToken.issue!(user: @user)

    post "/api/v1/auth/password/reset",
      params: {
        token: raw_token,
        new_password: "short",
        password_confirmation: "short"
      },
      as: :json

    assert_response :unprocessable_entity
    assert @user.reload.authenticate("SecurePassword123!")
  end


  test "registers a new unverified user and sends verification email" do
    assert_emails 1 do
      post "/api/v1/auth/register",
        params: {
          email: "new-registration@example.com",
          password: "SecurePassword123!"
        },
        as: :json
    end

    assert_response :created

    user = User.find_by!(email: "new-registration@example.com")
    assert_not user.email_verified?

    record = user.email_verification_tokens.last
    assert record.present?
    assert_equal 64, record.token_digest.length

    email = ActionMailer::Base.deliveries.last
    assert_equal [user.email], email.to
    assert_equal "Verify your Mirrorline email address", email.subject
    email_content = [
      email.text_part&.body&.decoded,
      email.html_part&.body&.decoded
    ].compact.join("\\n")

    assert_includes email_content, "verify-email?token="
    assert_not_includes response.body, record.token_digest
  end

  test "blocks login until email is verified" do
    user = User.create!(
      email: "unverified-login@example.com",
      password: "SecurePassword123!"
    )

    post "/api/v1/session",
      params: {
        email: user.email,
        password: "SecurePassword123!"
      },
      as: :json

    assert_response :forbidden
    assert_equal "email not verified", response.parsed_body["error"]
    assert user.user_sessions.none?
  end

  test "verifies email and rejects reuse of verification token" do
    user = User.create!(
      email: "verify-account@example.com",
      password: "SecurePassword123!"
    )
    record, raw_token = EmailVerificationToken.issue!(user: user)

    get "/api/v1/auth/verify-email",
      params: { token: raw_token }

    assert_response :success
    assert user.reload.email_verified?
    assert record.reload.used_at.present?

    get "/api/v1/auth/verify-email",
      params: { token: raw_token }

    assert_response :unprocessable_entity
  end

  test "resends verification email without revealing account existence" do
    user = User.create!(
      email: "resend-verification@example.com",
      password: "SecurePassword123!"
    )

    assert_emails 1 do
      post "/api/v1/auth/verification/resend",
        params: { email: user.email },
        as: :json
    end

    assert_response :success
    assert_equal(
      "If an unverified account exists for that email, verification instructions will be sent.",
      response.parsed_body["message"]
    )
    assert user.email_verification_tokens.where(used_at: nil).exists?

    assert_no_emails do
      post "/api/v1/auth/verification/resend",
        params: { email: "unknown-verification@example.com" },
        as: :json
    end

    assert_response :success
    assert_equal(
      "If an unverified account exists for that email, verification instructions will be sent.",
      response.parsed_body["message"]
    )
  end

end
