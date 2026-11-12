class CopyLink < ApplicationRecord
  LOT_MODES = %w[fixed multiplier balance_ratio risk_pct].freeze

  belongs_to :user
  belongs_to :master_account, class_name: "TradingAccount"
  belongs_to :slave_account,  class_name: "TradingAccount"
  has_many :trade_mappings, dependent: :nullify
  has_many :commands, dependent: :nullify

  validates :lot_mode, inclusion: { in: LOT_MODES }
  validates :lot_value, numericality: { greater_than: 0 }
  validates :lot_value, numericality: { less_than_or_equal_to: 100 }, if: -> { lot_mode == "risk_pct" }
  validates :max_slippage, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000 }
  validates :symbol_suffix, length: { maximum: 16 }, format: { with: /\A[\w.\-#+]*\z/ }
  validates :slave_account_id, uniqueness: { scope: :master_account_id }
  validate :accounts_are_valid

  before_validation :normalize_symbols

  scope :active, -> { where(active: true) }

  def allows_symbol?(sym)
    symbols.blank? || symbols.include?(sym.to_s.upcase)
  end

  # Shape the dashboard expects (see mirrorline-web/src/lib/demo.js)
  def as_api
    {
      id: id, master_id: master_account_id, slave_id: slave_account_id, lot_mode: lot_mode,
      lot_value: lot_value.to_f, reverse: reverse, max_slippage: max_slippage,
      symbol_suffix: symbol_suffix, active: active,
      copy_pending: copy_pending, copy_missed_opens: copy_missed_opens, symbols: symbols
    }
  end

  private

  def normalize_symbols
    self.symbols = Array(symbols).map { |s| s.to_s.strip.upcase }.reject(&:blank?).uniq
  end

  def accounts_are_valid
    return if master_account.nil? || slave_account.nil?
    errors.add(:master_account, "must have the master role") unless master_account.master?
    errors.add(:slave_account, "must have the slave role") unless slave_account.slave?
    if user_id && (master_account.user_id != user_id || slave_account.user_id != user_id)
      errors.add(:base, "both accounts must belong to you")
    end
  end
end
