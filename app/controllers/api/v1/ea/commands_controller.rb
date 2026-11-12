module Api
  module V1
    module Ea
      class CommandsController < BaseController
        # GET /api/v1/commands/pending?limit=20   (either EA)
        # Plain text, one pipe-separated command per line, ascending id. Empty body = nothing to do.
        def pending
          limit = params.fetch(:limit, 20).to_i.clamp(1, 50)
          render plain: Command.claim_for(current_account, limit).map(&:to_wire).join("\n")
        end

        # POST /api/v1/commands/:id/ack   (either EA)
        def ack
          command = current_account.commands.find(params[:id])
          AckProcessor.call(
            command,
            status: params[:status], message: params[:message], slave_ticket: params[:slave_ticket],
            volume: params[:volume], price: params[:price]
          )
          head :ok
        rescue ActiveRecord::RecordNotFound
          head :not_found
        end
      end
    end
  end
end
