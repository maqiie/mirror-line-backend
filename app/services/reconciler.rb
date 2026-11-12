# Master-side reconciliation for one copy link:
#   * orphans: master closed a trade but the slave still holds it -> close it
#   * missed opens (opt-in per link): master holds a trade that was never copied -> copy it
class Reconciler
  FRESH  = 45.seconds
  SETTLE = 8.seconds

  def self.call(link) = new(link).call

  def initialize(link)
    @link = link
    @master = link.master_account
    @slave = link.slave_account
  end

  def call
    return unless fresh?(@master) && fresh?(@slave)
    close_orphans
    copy_missed_opens if @link.active? && @link.copy_missed_opens?
  end

  private

  def fresh?(account) = account.last_snapshot_at.present? && account.last_snapshot_at > FRESH.ago
  def settled?(mapping, account) = mapping.updated_at < account.last_snapshot_at - SETTLE

  def close_orphans
    copies = @slave.copies_by_key
    master_open = @master.open_ticket_set

    TradeMapping.where(copy_link_id: @link.id, state: TradeMapping::HOLDING_STATES).find_each do |m|
      next unless copies.key?(m.id)                       # slave does not hold it
      next if master_open.include?(m.master_ticket.to_i)  # master still holds it
      next unless settled?(m, @master)                    # master snapshot predates the trade
      m.enqueue_close!
    end
  end

  def copy_missed_opens
    mapped = TradeMapping.where(copy_link_id: @link.id).pluck(:master_ticket).compact.to_set
    (@master.open_ticket_set - mapped).each do |ticket|
      event = @master.trade_events.where(master_ticket: ticket, event_type: "open").order(:id).last
      FanOut.call(event, only_link: @link) if event
    end
  end
end
