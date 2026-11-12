module Api
  module V1
    module Ea
      class HeartbeatsController < BaseController
        RECONCILE_EVERY = 15.seconds
        MAX_POSITIONS = 100

        # POST /api/v1/heartbeat   (both roles)
        # Stores the account's state, every open position and a few quotes, then answers
        # with control lines, one per line:   KILL|0   PAUSE|0   GUARDS|max_lot=5.0;max_open=10;...
        def create
          attrs = {
            last_seen_at: Time.current,
            last_snapshot_at: Time.current,
            balance: params[:balance],
            equity: params[:equity],
            margin_level: params[:margin_level],
            outbox_size: params[:outbox].to_i,
            daily_halt: ActiveModel::Type::Boolean.new.cast(params[:daily_halt]) || false,
            positions: normalized_positions,
            quotes: normalized_quotes
          }

          if current_account.master?
            attrs[:open_tickets] = Array(params[:open_tickets]).map(&:to_i)
            attrs[:pending_tickets] = Array(params[:pending_tickets]).map(&:to_i)
          else
            attrs[:copies] = normalized_copies
          end

          current_account.update!(attrs)
          current_account.record_equity_sample!
          schedule_reconcile

          render plain: control_lines
        end

        private

        def control_lines
          lines = ["KILL|#{current_account.kill_switch ? 1 : 0}", "PAUSE|#{current_account.paused ? 1 : 0}"]
          if current_account.slave?
            lines << "GUARDS|" + current_account.effective_guards.map { |k, v| "#{k}=#{v}" }.join(";")
          end
          lines.join("\n") + "\n"
        end

        def normalized_copies
          raw = params.permit(copies: %i[m s v p])[:copies]
          Array(raw).map { |c| { "m" => c[:m].to_i, "s" => c[:s].to_i, "v" => c[:v].to_f, "p" => c[:p].to_f } }
        end

        # t=ticket s=symbol d=side v=volume o=open price p=current price pr=profit at=open time (epoch)
        def normalized_positions
          raw = params.permit(positions: %i[t s d v o p sl tp pr at])[:positions]
          Array(raw).first(MAX_POSITIONS).map do |x|
            { "t" => x[:t].to_i, "s" => x[:s].to_s.first(32), "d" => (x[:d].to_s == "sell" ? "sell" : "buy"),
              "v" => x[:v].to_f, "o" => x[:o].to_f, "p" => x[:p].to_f, "sl" => x[:sl].to_f, "tp" => x[:tp].to_f,
              "pr" => x[:pr].to_f, "at" => x[:at].to_i }
          end
        end

        def normalized_quotes
          raw = params.permit(quotes: {})[:quotes]
          raw.to_h.first(20).to_h { |k, v| [k.to_s.first(32), v.to_f] }
        end

        def schedule_reconcile
          last = current_account.last_reconciled_at
          return unless last.nil? || last < RECONCILE_EVERY.ago

          current_account.update_column(:last_reconciled_at, Time.current)
          ReconcileJob.perform_async(current_account.id)
        rescue StandardError => e
          Rails.logger.warn("[copier] could not enqueue reconcile: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
