module Api
  module V1
    class CopyLinksController < BaseController
      before_action :set_link, only: %i[update destroy]

      def create
        link = current_user.copy_links.new(link_params)
        link.master_account = current_user.trading_accounts.find(params.require(:master_id))
        link.slave_account  = current_user.trading_accounts.find(params.require(:slave_id))
        link.save!
        render json: link.as_api, status: :created
      end

      # The dashboard sends the whole link back; master/slave never change after creation.
      def update
        @link.update!(link_params)
        render json: @link.as_api
      end

      def destroy
        @link.destroy!
        head :no_content
      end

      private

      def set_link
        @link = current_user.copy_links.find(params[:id])
      end

      def link_params
        params.permit(:lot_mode, :lot_value, :reverse, :active, :max_slippage, :symbol_suffix,
                      :copy_pending, :copy_missed_opens, symbols: [])
      end
    end
  end
end
