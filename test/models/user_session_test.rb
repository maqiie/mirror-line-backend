require "test_helper"

class UserSessionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "session-test@example.com",
      password: "SecurePassword123!"
    )
  end

  test "issues a session with hashed access and refresh tokens" do
    session, access_token, refresh_token =
      UserSession.issue!(user: @user)

    assert session.persisted?
    assert access_token.present?
    assert refresh_token.present?

    assert_equal UserSession.digest(access_token), session.access_token_digest
    assert_equal UserSession.digest(refresh_token), session.refresh_token_digest

    assert_not_equal access_token, session.access_token_digest
    assert_not_equal refresh_token, session.refresh_token_digest

    assert_equal 1, session.refresh_tokens.count
  end

  test "rotates a valid refresh token" do
    session, old_access, old_refresh =
      UserSession.issue!(user: @user)

    result = UserSession.rotate_refresh_token!(old_refresh)

    assert result.present?

    rotated_session, new_access, new_refresh = result

    assert_equal session.id, rotated_session.id
    assert_not_equal old_access, new_access
    assert_not_equal old_refresh, new_refresh

    old_record = session.refresh_tokens.find_by!(
      token_digest: UserSession.digest(old_refresh)
    )

    new_record = session.refresh_tokens.find_by!(
      token_digest: UserSession.digest(new_refresh)
    )

    assert old_record.consumed_at.present?
    assert new_record.usable?
    assert_equal 2, session.refresh_tokens.count
  end

  test "rejects reuse of a consumed refresh token and revokes its session" do
    session, _access, old_refresh =
      UserSession.issue!(user: @user)

    first_rotation = UserSession.rotate_refresh_token!(old_refresh)
    assert first_rotation.present?

    replay = UserSession.rotate_refresh_token!(old_refresh)

    assert_nil replay
    assert session.reload.revoked_at.present?
    assert_not session.refresh_valid?
  end

  test "rejects an unknown refresh token" do
    assert_nil UserSession.rotate_refresh_token!("invalid-refresh-token")
  end

  test "rejects a blank refresh token" do
    assert_nil UserSession.rotate_refresh_token!("")
    assert_nil UserSession.rotate_refresh_token!(nil)
  end

  test "rejects an expired refresh token" do
    session, _access, refresh_token =
      UserSession.issue!(user: @user)

    record = session.refresh_tokens.find_by!(
      token_digest: UserSession.digest(refresh_token)
    )

    record.update!(expires_at: 1.minute.ago)
    session.update!(refresh_expires_at: 1.minute.ago)

    assert_nil UserSession.rotate_refresh_token!(refresh_token)
  end

  test "rejects access tokens from revoked sessions" do
    session, access_token, _refresh =
      UserSession.issue!(user: @user)

    assert_equal session, UserSession.find_active_by_access_token(access_token)

    session.revoke!

    assert_nil UserSession.find_active_by_access_token(access_token)
  end

  test "rejects expired access tokens" do
    session, access_token, _refresh =
      UserSession.issue!(user: @user)

    session.update!(access_expires_at: 1.minute.ago)

    assert_nil UserSession.find_active_by_access_token(access_token)
  end
end
