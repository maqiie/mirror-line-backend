module Api
  module V1
    # Base for dashboard endpoints.
    # Auth: Authorization: Bearer <session access token>
    class BaseController < ActionController::API
      before_action :authenticate_user!
      before_action :set_no_store_header

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not found" }, status: :not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: {
          error: e.record.errors.full_messages.to_sentence
        }, status: :unprocessable_entity
      end

      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end

      rescue_from ManualTrade::Error do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_no_store_header
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"
      end

      attr_reader :current_user, :current_session

      def authenticate_user!
        token = request.authorization.to_s[/\ABearer (.+)\z/, 1]

        @current_session = UserSession.find_active_by_access_token(token)
        @current_user = @current_session&.user

        unless @current_user
          return render json: {
            error: "unauthorized"
          }, status: :unauthorized
        end

        if @current_session.last_used_at.nil? ||
           @current_session.last_used_at < 1.minute.ago
          @current_session.update_column(:last_used_at, Time.current)
        end
      end

      def limit_param(default = 100, max = 500)
        params.fetch(:limit, default).to_i.clamp(1, max)
      end
    end
  end
end
