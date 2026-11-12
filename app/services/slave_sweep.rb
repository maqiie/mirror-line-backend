# Compares what the DB believes a slave holds with what the slave EA reports in
# its heartbeat, and repairs the difference. A mapping is only judged once the
# slave's snapshot is newer than the mapping's last change (so in-flight trades
# are never mistaken for missing ones).
class SlaveSweep
  FRESH  = 45.seconds
  SETTLE = 8.seconds
  REVIVABLE_REASONS = %w[expired no_ack].freeze

  def self.call(slave) = new(slave).call

  def initialize(slave)
    @slave = slave
  end

  def call
    return unless fresh?
    copies = @slave.copies_by_key

    reconcile_open_mappings(copies)
    reconcile_dead_mappings(copies)
  end

  private

  def fresh? = @slave.last_snapshot_at.present? && @slave.last_snapshot_at > FRESH.ago

  def settled?(mapping) = mapping.updated_at < @slave.last_snapshot_at - SETTLE

  # DB says open, slave says otherwise (or confirms it).
  def reconcile_open_mappings(copies)
    TradeMapping.where(trading_account_id: @slave.id, state: TradeMapping::HOLDING_STATES).find_each do |m|
      held = copies[m.id]
      if held
        sync(m, held)
      elsif settled?(m) && !m.commands.in_flight.exists?
        if m.state == "open"
          m.update!(state: "closed", closed_at: Time.current, close_reason: "closed_on_slave")
        else
          m.update!(state: "failed", closed_at: Time.current, close_reason: "never_opened")
        end
      end
    end
  end

  # DB says closed/failed, slave still holds it: either an ack was lost (revive)
  # or it is a zombie that must be closed.
  def reconcile_dead_mappings(copies)
    return if copies.empty?
    TradeMapping.where(trading_account_id: @slave.id, id: copies.keys, state: %w[closed failed]).find_each do |m|
      next unless settled?(m)
      if revivable?(m)
        m.update!(state: "open", slave_ticket: copies[m.id]["s"].to_i, closed_at: nil, close_reason: nil)
      else
        m.enqueue_close!
      end
    end
  end

  def revivable?(m)
    return false unless m.state == "failed" && REVIVABLE_REASONS.include?(m.close_reason)
    return true if m.copy_link.nil?   # manual trade
    m.copy_link.master_account.open_ticket_set.include?(m.master_ticket.to_i)
  end

  def sync(m, held)
    ticket = held["s"].to_i
    return if m.state == "open" && m.slave_ticket == ticket
    m.update!(state: "open", slave_ticket: ticket, opened_at: m.opened_at || Time.current)
  end
end
