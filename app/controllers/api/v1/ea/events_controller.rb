module Api
  module V1
    module Ea
      class EventsController < BaseController
        # POST /api/v1/events   (master EA)
        # 201 stored + fanned out, 409 duplicate (EA treats as success), 422 invalid (EA drops it).
        # Event and fan-out share one transaction: if fan-out fails the event rolls back,
        # so the EA's retry is processed again instead of being rejected as a duplicate.
        def create
          return unless require_role!("master")

          attrs = event_params.to_h
          attrs[:event_time] = Time.at(attrs[:event_time].to_i).utc if attrs[:event_time].present?
          event = current_account.trade_events.new(attrs.merge(payload: attrs.except(:event_time)))

          ApplicationRecord.transaction do
            event.save!
            FanOut.call(event)
          end

          render json: { id: event.id }, status: :created
        rescue ActiveRecord::RecordNotUnique
          render json: { status: "duplicate" }, status: :conflict
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
        end

        private

        def event_params
          params.permit(
            :idempotency_key, :event_type, :master_ticket, :symbol, :side, :volume, :prev_volume,
            :price, :sl, :tp, :master_balance, :master_equity, :event_time, :platform, :profit
          )
        end
      end
    end
  end
end
