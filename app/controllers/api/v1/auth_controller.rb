module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_user!, only: %i[register verify_email resend_verification login refresh forgot_password reset_password]

      # POST /api/v1/auth/register
      def register
        unless RateLimitCounter.allow_request?(
          key: "registration-ip:#{request.remote_ip}",
          limit: 10,
          period: 1.hour
        )
          return render json: { error: "too many registration attempts" },
                        status: :too_many_requests
        end

        user = User.new(
          email: params[:email],
          password: params[:password]
        )

        unless user.save
          return render json: {
            error: "validation failed",
            details: user.errors.to_hash
          }, status: :unprocessable_entity
        end

        record, raw_token = EmailVerificationToken.issue!(user: user)

        begin
          EmailVerificationMailer.verification_email(
            user: user,
            token: raw_token
          ).deliver_now
        rescue StandardError => e
          record.update_column(:used_at, Time.current)
          Rails.logger.error("Email verification delivery failed: #{e.class}")

          return render json: {
            error: "verification email could not be sent; please try again"
          }, status: :service_unavailable
        end

        render json: {
          message: "Registration successful. Check your email to verify your account."
        }, status: :created
      rescue ActiveRecord::RecordNotUnique
        render json: {
          error: "email has already been taken"
        }, status: :unprocessable_entity
      end

      # GET /api/v1/auth/verify-email?token=...
      def verify_email
        record = EmailVerificationToken.find_usable(params[:token].to_s)

        unless record
          return render json: {
            error: "invalid or expired verification token"
          }, status: :unprocessable_entity
        end

        verified = record.with_lock do
          record.reload

          unless record.used_at.nil? && record.expires_at.future?
            next false
          end

          now = Time.current
          user = record.user

          record.update!(used_at: now)
          user.update!(email_verified_at: now) unless user.email_verified?

          user.email_verification_tokens
              .where(used_at: nil)
              .where.not(id: record.id)
              .update_all(used_at: now, updated_at: now)

          true
        end

        unless verified
          return render json: {
            error: "invalid or expired verification token"
          }, status: :unprocessable_entity
        end

        render json: {
          message: "Email verified successfully. You can now log in."
        }, status: :ok
      end

      # POST /api/v1/auth/verification/resend
      def resend_verification
        generic_response = {
          message: "If an unverified account exists for that email, verification instructions will be sent."
        }

        ip_allowed = RateLimitCounter.allow_request?(
          key: "verification-resend-ip:#{request.remote_ip}",
          limit: 10,
          period: 1.hour
        )

        email = params[:email].to_s.strip.downcase

        email_allowed = if email.present?
          RateLimitCounter.allow_request?(
            key: "verification-resend-email:#{email}",
            limit: 3,
            period: 1.hour
          )
        else
          false
        end

        if ip_allowed && email_allowed
          user = User.find_by(email: email)

          if user && !user.email_verified?
            record, raw_token = EmailVerificationToken.issue!(user: user)

            begin
              EmailVerificationMailer.verification_email(
                user: user,
                token: raw_token
              ).deliver_now
            rescue StandardError => e
              record.update_column(:used_at, Time.current)
              Rails.logger.error("Email verification delivery failed: #{e.class}")
            end
          end
        end

        render json: generic_response, status: :ok
      end

      # POST /api/v1/session
      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: params[:email].to_s.strip.downcase)

        unless user&.authenticate(params[:password].to_s)
          return render json: {
            error: "invalid credentials"
          }, status: :unauthorized
        end

        unless user.email_verified?
          return render json: {
            error: "email not verified"
          }, status: :forbidden
        end

        _session, access_token, refresh_token = UserSession.issue!(
          user: user,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render json: {
          token: access_token,
          refresh_token: refresh_token,
          expires_in: UserSession::ACCESS_TOKEN_TTL.to_i,
          refresh_expires_in: UserSession::REFRESH_TOKEN_TTL.to_i,
          user: {
            id: user.id,
            email: user.email
          }
        }
      end

      # POST /api/v1/auth/refresh
      def refresh
        result = UserSession.rotate_refresh_token!(
          params[:refresh_token].to_s
        )

        unless result
          return render json: {
            error: "invalid or expired refresh token"
          }, status: :unauthorized
        end

        _session, access_token, refresh_token = result

        render json: {
          token: access_token,
          refresh_token: refresh_token,
          expires_in: UserSession::ACCESS_TOKEN_TTL.to_i,
          refresh_expires_in: UserSession::REFRESH_TOKEN_TTL.to_i
        }
      end

      # POST /api/v1/auth/password/forgot
      def forgot_password
        generic_response = {
          message: "If an account exists for that email, password reset instructions will be sent."
        }

        ip_allowed = RateLimitCounter.allow_request?(
          key: "password-reset-ip:#{request.remote_ip}",
          limit: 10,
          period: 1.hour
        )

        email = params[:email].to_s.strip.downcase

        email_allowed = if email.present?
          RateLimitCounter.allow_request?(
            key: "password-reset-email:#{email}",
            limit: 3,
            period: 1.hour
          )
        else
          false
        end

        if ip_allowed && email_allowed
          user = User.find_by(email: email)

          if user
            _record, raw_token = PasswordResetToken.issue!(user: user)

            begin
              PasswordResetMailer.reset_email(
                user: user,
                token: raw_token
              ).deliver_now
            rescue StandardError => e
              _record.update_column(:used_at, Time.current)

              Rails.logger.error(
                "Password reset email delivery failed: #{e.class}"
              )
            end
          end
        end

        render json: generic_response, status: :ok
      end

      # POST /api/v1/auth/password/reset
      def reset_password
        record = PasswordResetToken.find_usable(
          params[:token].to_s
        )

        unless record
          return render json: {
            error: "invalid or expired password reset token"
          }, status: :unprocessable_entity
        end

        new_password = params[:new_password].to_s
        confirmation = params[:password_confirmation].to_s

        unless new_password == confirmation
          return render json: {
            error: "password confirmation does not match"
          }, status: :unprocessable_entity
        end

        result = record.with_lock do
          record.reload

          unless record.used_at.nil? && record.expires_at.future?
            next false
          end

          user = record.user
          now = Time.current

          user.update!(password: new_password)

          record.update!(used_at: now)

          user.user_sessions
              .where(revoked_at: nil)
              .update_all(
                revoked_at: now,
                updated_at: now
              )

          user.password_reset_tokens
              .where(used_at: nil)
              .where.not(id: record.id)
              .update_all(
                used_at: now,
                updated_at: now
              )

          true
        end

        unless result
          return render json: {
            error: "invalid or expired password reset token"
          }, status: :unprocessable_entity
        end

        render json: {
          message: "password reset successfully; please log in again"
        }, status: :ok
      end

      # GET /api/v1/sessions
      def sessions
        records = current_user.user_sessions.order(created_at: :desc)

        render json: {
          sessions: records.map do |record|
            {
              id: record.id,
              ip_address: record.ip_address,
              user_agent: record.user_agent,
              created_at: record.created_at,
              last_used_at: record.last_used_at,
              access_expires_at: record.access_expires_at,
              refresh_expires_at: record.refresh_expires_at,
              revoked_at: record.revoked_at,
              active: record.revoked_at.nil? && record.refresh_expires_at.future?,
              is_current: record.id == current_session.id
            }
          end
        }
      end

      # DELETE /api/v1/sessions/:id
      def revoke_session
        record = current_user.user_sessions.find(params[:id])
        record.revoke!

        render json: {
          message: "session revoked successfully"
        }
      end

      # DELETE /api/v1/sessions
      def revoke_all_sessions
        current_user.user_sessions
                    .where(revoked_at: nil)
                    .update_all(revoked_at: Time.current, updated_at: Time.current)

        render json: {
          message: "all sessions revoked successfully"
        }
      end

      # PATCH /api/v1/password/change
      def change_password
        unless current_user.authenticate(params[:current_password].to_s)
          return render json: {
            error: "current password is incorrect"
          }, status: :unauthorized
        end

        new_password = params[:new_password].to_s
        confirmation = params[:password_confirmation].to_s

        unless new_password == confirmation
          return render json: {
            error: "password confirmation does not match"
          }, status: :unprocessable_entity
        end

        User.transaction do
          current_user.update!(password: new_password)

          current_user.user_sessions
                      .where(revoked_at: nil)
                      .update_all(
                        revoked_at: Time.current,
                        updated_at: Time.current
                      )
        end

        render json: {
          message: "password changed successfully; please log in again"
        }, status: :ok
      end

      # DELETE /api/v1/session
      def logout
        current_session.revoke!

        render json: {
          message: "logged out successfully"
        }
      end
    end
  end
end
