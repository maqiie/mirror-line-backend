module Api
  module V1
    module Ea
      # Base for endpoints called by the MT4/MT5 Expert Advisors.
      # Auth: header X-Account-Token (the raw token shown once when the account was created).
      class BaseController < ActionController::API
        before_action :authenticate_account!

        rescue_from ActionController::ParameterMissing do |e|
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        attr_reader :current_account

        def authenticate_account!
          @current_account = TradingAccount.authenticate_token(request.headers["X-Account-Token"])
          return render(json: { error: "invalid token" }, status: :unauthorized) unless @current_account

          # liveness only; throttled so a 4/s poll does not become 4 writes/s
          if @current_account.last_seen_at.nil? || @current_account.last_seen_at < 3.seconds.ago
            @current_account.update_column(:last_seen_at, Time.current)
          end
        end

        def require_role!(role)
          return true if current_account.role == role
          render json: { error: "this token belongs to a #{current_account.role} account" }, status: :forbidden
          false
        end
      end
    end
  end
end
