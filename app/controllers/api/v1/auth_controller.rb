module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_user!

      # POST /api/v1/auth/login  { email, password }
      # Add rack-attack in front of this in production to throttle guessing.
      def login
        user = User.find_by(email: params[:email].to_s.strip.downcase)
        if user&.authenticate(params[:password].to_s)
          render json: {
            token: user.generate_token_for(:api),
            expires_in: 12.hours.to_i,
            user: { id: user.id, email: user.email }
          }
        else
          render json: { error: "invalid credentials" }, status: :unauthorized
        end
      end
    end
  end
end
