module Api
  module V1
    class MappingsController < BaseController
      # GET /api/v1/mappings?state=open&account_id=3   (default: all active trades)
      def index
        scope = TradeMapping.where(trading_account_id: current_user.trading_accounts.select(:id))
        scope = params[:state].present? ? scope.where(state: params[:state]) : scope.active
        scope = scope.where(trading_account_id: params[:account_id]) if params[:account_id].present?
        render json: scope.order(id: :desc).limit(limit_param).map(&:as_api)
      end

      # POST /api/v1/mappings/:id/close   close one copied trade on one slave
      def close
        mapping = TradeMapping.where(trading_account_id: current_user.trading_accounts.select(:id)).find(params[:id])
        render json: ManualTrade.close_mapping(mapping).as_api, status: :accepted
      end
    end
  end
end
