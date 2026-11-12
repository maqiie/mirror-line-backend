class TradingAccount < ApplicationRecord
  PLATFORMS = %w[mt4 mt5].freeze
  ROLES = %w[master slave].freeze
  ONLINE_WINDOW = 30.seconds
  DEFAULT_GUARDS = { "max_lot" => 5.0, "max_open" => 10, "daily_loss_pct" => 5.0,
                     "min_margin_level" => 150.0, "max_spread" => 30 }.freeze
  GUARD_KEYS = DEFAULT_GUARDS.keys.freeze

  belongs_to :user

  has_many :trade_events, dependent: :destroy            # events this account produced (master)
  has_many :commands, dependent: :destroy                # commands addressed to this account (slave)
  has_many :trade_mappings, dependent: :destroy          # copied trades living on this account (slave)
  has_many :equity_samples, dependent: :delete_all
  has_many :master_links, class_name: "CopyLink", foreign_key: :master_account_id,
           inverse_of: :master_account, dependent: :destroy
  has_many :slave_links, class_name: "CopyLink", foreign_key: :slave_account_id,
           inverse_of: :slave_account, dependent: :destroy

  validates :name, presence: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :role, inclusion: { in: ROLES }
  validates :login, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :login, uniqueness: { scope: %i[user_id server] }

  validate :guards_are_valid

  scope :masters, -> { where(role: "master") }
  scope :slaves,  -> { where(role: "slave") }

  # Present only on the instance that just generated it. Show it once, never store it.
  attr_reader :raw_token

  before_validation :generate_token, on: :create

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.authenticate_token(raw)
    return nil if raw.blank?
    find_by(token_digest: digest(raw))
  end

  def rotate_token!
    generate_token
    save!
    raw_token
  end

  def master? = role == "master"
  def slave?  = role == "slave"
  def online? = last_seen_at.present? && last_seen_at > ONLINE_WINDOW.ago
  def accepting_trades? = !kill_switch && !paused

  def open_ticket_set = Array(open_tickets).map(&:to_i).to_set

  # { mapping_id => {"m"=>..,"s"=>..,"v"=>..,"p"=>..} } from the slave's last heartbeat
  def copies_by_key
    Array(copies).each_with_object({}) { |c, h| h[c["m"].to_i] = c }
  end

  def effective_guards = DEFAULT_GUARDS.merge(guards.to_h.slice(*GUARD_KEYS))

  # Called from heartbeats; keeps the equity chart light (one point per 5 minutes).
  def record_equity_sample!(every: 5.minutes)
    return if equity.nil?
    return if last_equity_sample_at && last_equity_sample_at > every.ago
    equity_samples.create!(at: Time.current, equity: equity)
    update_column(:last_equity_sample_at, Time.current)
  end

  # Shape the dashboard expects (see mirrorline-web/src/lib/demo.js)
  def as_api
    {
      id: id, name: name, platform: platform, role: role, login: login.to_s,
      broker: broker.to_s, server: server.to_s, status: online? ? "online" : "offline",
      paused: paused, kill_switch: kill_switch, balance: balance.to_f, equity: equity.to_f,
      last_seen_at: last_seen_at
    }
  end

  private

  def guards_are_valid
    bad = guards.to_h.reject { |k, v| GUARD_KEYS.include?(k) && v.is_a?(Numeric) && v >= 0 }
    errors.add(:guards, "must be non-negative numbers (#{GUARD_KEYS.join(', ')})") if bad.any?
  end

  def generate_token
    @raw_token = "tc_#{SecureRandom.urlsafe_base64(32)}"
    self.token_digest = self.class.digest(@raw_token)
  end
end
