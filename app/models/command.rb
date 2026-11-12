class Command < ApplicationRecord
  ACTIONS = %w[open add close partial_close modify pending_place pending_modify pending_delete close_all close_ticket].freeze
  STATUSES = %w[pending sent executed skipped failed expired].freeze
  FINAL_STATUSES = %w[executed skipped failed expired].freeze
  OPENING_ACTIONS = %w[open add pending_place].freeze

  REDELIVER_AFTER = 5.seconds   # un-acked commands are re-sent after this
  MAX_ATTEMPTS = 6

  belongs_to :trading_account
  belongs_to :trade_event, optional: true
  belongs_to :copy_link, optional: true
  belongs_to :trade_mapping, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :status, inclusion: { in: STATUSES }
  validates :lot_mode, inclusion: { in: CopyLink::LOT_MODES }, allow_nil: true

  scope :in_flight, -> { where(status: %w[pending sent]) }

  def final?   = FINAL_STATUSES.include?(status)
  def opening? = OPENING_ACTIONS.include?(action)

  # Hands the next batch to a slave EA, strictly in id order.
  #
  # Ordering matters: the EA remembers the highest id it processed and treats lower
  # ids as duplicates. So while an earlier command is "in flight" (sent, not yet
  # acked, inside the redelivery window) nothing after it is released.
  def self.claim_for(account, limit = 20)
    transaction do
      base = where(trading_account_id: account.id)
      blocker = base.where(status: "sent").where("sent_at >= ?", REDELIVER_AFTER.ago).minimum(:id)

      scope = base.where(status: %w[pending sent])
                  .where("sent_at IS NULL OR sent_at < ?", REDELIVER_AFTER.ago)
                  .where("attempts < ?", MAX_ATTEMPTS)
      scope = scope.where("id < ?", blocker) if blocker

      rows = scope.order(:id).limit(limit).lock("FOR UPDATE SKIP LOCKED").to_a
      now = Time.current
      rows.each { |c| c.update_columns(status: "sent", sent_at: now, attempts: c.attempts + 1) }
      rows
    end
  end

  # One pipe-separated line, 17 fields. The EAs parse exactly this layout:
  # id|action|key|symbol|side|volume|price|sl|tp|lot_mode|lot_value|master_balance|reverse|ratio|created_epoch|max_slippage|symbol_suffix
  # `key` is the trade-mapping id, except for close_ticket where it is the raw broker ticket.
  def to_wire
    key = action == "close_ticket" ? target_ticket.to_i : trade_mapping_id.to_i
    [
      id, action, key, clean(symbol), clean(side),
      num(volume), num(price), num(sl), num(tp),
      clean(lot_mode), num(lot_value), num(master_balance),
      reverse ? 1 : 0, num(ratio), created_at.to_i,
      max_slippage.to_i, clean(symbol_suffix)
    ].join("|")
  end

  def as_api
    {
      id: id, account_id: trading_account_id, action: action, status: status, symbol: symbol,
      side: side, volume: volume&.to_f, slave_ticket: slave_ticket, result_message: result_message,
      mapping_id: trade_mapping_id, event_id: trade_event_id, attempts: attempts,
      created_at: created_at, acked_at: acked_at
    }
  end

  private

  def num(v) = (v || 0).to_d.to_s("F")
  def clean(s) = s.to_s.delete("|\r\n")
end
