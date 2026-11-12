module Api
  module V1
    class CopierController < BaseController
      # PUT /api/v1/copier { paused }  - global switch: new master trades stop reaching followers.
      # Never closes anything; closes and SL/TP changes for trades already copied still flow.
      def update
        current_user.update!(copier_paused: ActiveModel::Type::Boolean.new.cast(params[:paused]) || false)
        render json: { paused: current_user.copier_paused }
      end
    end
  end
end
