module Api
  module V1
    class AuditController < BaseController
      # GET /api/v1/audit/events?account_id=
      def events
        scope = TradeEvent.where(trading_account_id: current_user.trading_accounts.masters.select(:id))
        scope = scope.where(trading_account_id: params[:account_id]) if params[:account_id].present?
        render json: scope.order(id: :desc).limit(limit_param).map(&:as_api)
      end

      # GET /api/v1/audit/commands?status=failed&account_id=
      def commands
        scope = Command.where(trading_account_id: current_user.trading_accounts.select(:id))
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(trading_account_id: params[:account_id]) if params[:account_id].present?
        render json: scope.order(id: :desc).limit(limit_param).map(&:as_api)
      end
    end
  end
end
