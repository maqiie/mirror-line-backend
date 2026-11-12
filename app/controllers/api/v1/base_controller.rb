module Api
  module V1
    # Base for dashboard endpoints. Auth: Authorization: Bearer <token from /auth/login>
    class BaseController < ActionController::API
      before_action :authenticate_user!

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not found" }, status: :not_found
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
      rescue_from ActionController::ParameterMissing do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end
      rescue_from ManualTrade::Error do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      attr_reader :current_user

      def authenticate_user!
        token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        @current_user = token && User.find_by_token_for(:api, token)
        render json: { error: "unauthorized" }, status: :unauthorized unless @current_user
      end

      def limit_param(default = 100, max = 500)
        params.fetch(:limit, default).to_i.clamp(1, max)
      end
    end
  end
end
