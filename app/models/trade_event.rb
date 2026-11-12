class TradeEvent < ApplicationRecord
  TYPES = %w[open add close partial_close modify pending_place pending_modify pending_delete].freeze
  SIDES = %w[buy sell buy_limit sell_limit buy_stop sell_stop].freeze

  belongs_to :trading_account
  has_many :commands, dependent: :nullify

  # Uniqueness of [account, idempotency_key] is enforced by the DB index (race-free).
  validates :event_type, inclusion: { in: TYPES }
  validates :side, inclusion: { in: SIDES }
  validates :master_ticket, presence: true
  validates :symbol, presence: true, format: { with: /\A[\w.\-#+]{1,32}\z/ }
  validates :idempotency_key, presence: true, length: { maximum: 100 }

  def as_api
    {
      id: id, account_id: trading_account_id, event_type: event_type, master_ticket: master_ticket,
      symbol: symbol, side: side, volume: volume&.to_f, price: price&.to_f, sl: sl&.to_f, tp: tp&.to_f,
      event_time: event_time, received_at: created_at
    }
  end
end
