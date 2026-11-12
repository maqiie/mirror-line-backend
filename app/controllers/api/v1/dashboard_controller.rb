module Api
  module V1
    class DashboardController < BaseController
      # GET /api/v1/dashboard  - the snapshot the React app polls every 3 seconds
      def show
        render json: DashboardSnapshot.new(current_user).call
      end
    end
  end
end
