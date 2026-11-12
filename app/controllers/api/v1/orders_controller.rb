module Api
  module V1
    class OrdersController < BaseController
      # POST /api/v1/orders { account_ids, symbol, side, volume, sl, tp }
      #
      # If the master is among the selected accounts, followers that actively copy that master
      # are NOT sent a second, direct order: they receive the master's trade through their link
      # (with their own lot sizing). Followers without an active link get the order directly.
      def create
        ids = Array(params.require(:account_ids)).map(&:to_i).uniq
        accounts = current_user.trading_accounts.where(id: ids).to_a
        raise ActiveRecord::RecordNotFound if accounts.empty? || accounts.size != ids.size

        lot_mode = params[:lot_mode].presence || "fixed"
        lot_value = params[:lot_value].presence || (lot_mode == "fixed" ? params[:volume] : nil)

        unless %w[fixed risk_pct].include?(lot_mode)
          return render json: {
            error: "Website orders support only fixed and risk_pct sizing."
          }, status: :unprocessable_entity
        end

        fixed_value = params[:volume].presence || lot_value

        if lot_value.blank? || lot_value.to_d <= 0
          return render json: { error: "A valid lot_value is required." }, status: :unprocessable_entity
        end

        if lot_mode == "risk_pct" && lot_value.to_d > 100
          return render json: { error: "Risk percentage cannot exceed 100%." }, status: :unprocessable_entity
        end

        master_ids = accounts.select(&:master?).map(&:id)
        covered = accounts.select { |a| a.slave? && a.slave_links.active.where(master_account_id: master_ids).exists? }
        direct_accounts = accounts - covered

        # A selected master always receives a fixed-lot website order.
        # Its linked followers use their own CopyLink sizing configuration.
        if lot_mode != "fixed" && direct_accounts.any?(&:master?)
          return render json: {
            error: "Master accounts require fixed volume. Configure risk percentage on each follower copy link."
          }, status: :unprocessable_entity
        end

        batch = SecureRandom.hex(6)

        commands = direct_accounts.map do |account|
          account_mode = account.master? ? "fixed" : lot_mode
          account_value = account.master? ? fixed_value : lot_value

          ManualTrade.open(
            account: account,
            symbol: params[:symbol],
            side: params[:side],
            lot_value: account_value,
            lot_mode: account_mode,
            sl: params[:sl],
            tp: params[:tp],
            batch_key: batch
          )
        end

        render json: {
          sent: commands.size,
          copied_via_link: covered.map(&:id),
          commands: commands.map(&:as_api)
        }, status: :created
      rescue ManualTrade::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
