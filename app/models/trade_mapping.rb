# One row per trade copied (or manually placed) on a slave.
# Its id is sent to the slave EA as the "ticket key", so the EA can always find
# its own copy again, even when two masters use the same ticket number.
class TradeMapping < ApplicationRecord
  STATES = %w[pending_requested pending open_requested open closed failed].freeze
  ACTIVE_STATES  = %w[pending_requested pending open_requested open].freeze
  HOLDING_STATES = %w[open_requested open].freeze
  PENDING_STATES = %w[pending_requested pending].freeze

  belongs_to :trading_account
  belongs_to :copy_link, optional: true
  has_many :commands, dependent: :nullify

  validates :state, inclusion: { in: STATES }

  scope :active,  -> { where(state: ACTIVE_STATES) }
  scope :holding, -> { where(state: HOLDING_STATES) }

  def holding? = HOLDING_STATES.include?(state)

  # Queue a close for this trade unless one is already in flight.
  def enqueue_close!
    return nil if commands.where(action: "close", status: %w[pending sent]).exists?
    commands.create!(
      trading_account: trading_account, copy_link: copy_link, action: "close",
      symbol: symbol, side: side, volume: volume || 0
    )
  end

  def as_api
    {
      id: id, account_id: trading_account_id, copy_link_id: copy_link_id,
      master_ticket: master_ticket, slave_ticket: slave_ticket, symbol: symbol, side: side,
      volume: volume&.to_f, state: state, opened_at: opened_at, closed_at: closed_at,
      close_reason: close_reason, manual: copy_link_id.nil?
    }
  end
end
