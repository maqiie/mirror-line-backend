module Api
  module V1
    class PositionsController < BaseController
      # POST /api/v1/positions/:ticket/close
      # :ticket is the dashboard's composite id (account_id * 10^12 + broker ticket).
      # Closing a master position closes it on the master; the followers then close their copies
      # through the normal event flow.
      def close
        account_id, ticket = DashboardSnapshot.decode_ticket(params[:ticket])
        account = current_user.trading_accounts.find(account_id)
        pos = Array(account.positions).find { |p| p["t"].to_i == ticket }
        raise ActiveRecord::RecordNotFound unless pos

        cmd = ManualTrade.close_ticket(account, ticket, symbol: pos["s"], side: pos["d"], volume: pos["v"])
        render json: cmd.as_api, status: :accepted
      end

      # POST /api/v1/positions/close_all  { account_id? }   (no account_id = every account)
      def close_all
        accounts = params[:account_id].present? ? [current_user.trading_accounts.find(params[:account_id])] : current_user.trading_accounts.to_a
        render json: accounts.map { |a| ManualTrade.close_all(a).as_api }, status: :accepted
      end
    end
  end
end
