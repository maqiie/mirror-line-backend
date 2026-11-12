module Api
  module V1
    class TradingAccountsController < BaseController
      before_action :set_account, only: %i[update destroy regenerate_token guards]

      # POST -> { account, token }. The raw EA token is returned ONCE; only its SHA256 is stored.
      def create
        account = current_user.trading_accounts.create!(params.permit(:name, :platform, :role, :login, :broker, :server))
        render json: { account: account.as_api, token: account.raw_token }, status: :created
      end

      # PATCH { paused }
      def update
        @account.update!(params.permit(:paused, :name, :broker, :server, :kill_switch))
        render json: @account.as_api
      end

      def destroy
        @account.destroy!
        head :no_content
      end

      def regenerate_token
        render json: { token: @account.rotate_token! }
      end

      # PUT { max_lot, max_open, daily_loss_pct, min_margin_level, max_spread }
      def guards
        values = params.permit(*TradingAccount::GUARD_KEYS).to_h.transform_values { |v| Float(v) }
        @account.update!(guards: values)
        render json: @account.effective_guards
      rescue ArgumentError, TypeError
        render json: { error: "Limits must be numbers" }, status: :unprocessable_entity
      end

      private

      def set_account
        @account = current_user.trading_accounts.find(params[:id])
      end
    end
  end
end
