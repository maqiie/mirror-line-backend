# Turns one master TradeEvent into Commands for every linked slave.
#
# Runs inline inside the events request (not in a background job) on purpose:
# the master sends events one at a time and waits for each response, so inline
# fan-out guarantees an "open" is always processed before the "close" that follows it.
class FanOut
  LOCK_NAMESPACE = 7_301

  def self.call(event, only_link: nil) = new(event, only_link: only_link).call

  def initialize(event, only_link: nil)
    @event = event
    @master = event.trading_account
    @only_link = only_link   # set when replaying a missed open for a single link
  end

  def call
    ApplicationRecord.transaction do
      lock_master
      links.each { |link| handle(link) }
    end
  end

  private

  def lock_master
    key = (@master.id % 2_147_483_647).to_i
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{key})")
  end

  def links
    scope = @master.master_links.includes(:slave_account)
    scope = scope.where(id: @only_link.id) if @only_link
    scope
  end

  def handle(link)
    case @event.event_type
    when "open", "pending_place"
      open_trade(link)
    when "add", "close", "partial_close", "modify"
      follow_up(link, TradeMapping::HOLDING_STATES)
    when "pending_modify", "pending_delete"
      follow_up(link, TradeMapping::PENDING_STATES)
    end
  end

  # New trades only flow through active links. Follow-ups (close/modify/...) always
  # flow for trades that were already copied, so a paused link never strands a position.
  def open_trade(link)
    return unless link.active?
    return if @event.event_type == "pending_place" && !link.copy_pending?

    slave = link.slave_account

    ApplicationRecord.transaction(requires_new: true) do
      if (reason = block_reason(link, slave))
        create_command(link, nil, status: "skipped", message: reason)   # audit trail only
        next
      end

      mapping = TradeMapping.active.find_by(copy_link_id: link.id, master_ticket: @event.master_ticket)
      if mapping.nil?
        mapping = TradeMapping.create!(
          trading_account: slave, copy_link: link, master_ticket: @event.master_ticket,
          symbol: @event.symbol, side: @event.side, volume: @event.volume,
          state: @event.event_type == "pending_place" ? "pending_requested" : "open_requested"
        )
      elsif @event.event_type == "open" && TradeMapping::PENDING_STATES.include?(mapping.state)
        mapping.update!(state: "open_requested")   # the master's pending order just filled
      else
        next                                       # duplicate, already copied
      end

      create_command(link, mapping)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def follow_up(link, states)
    mapping = TradeMapping.where(copy_link_id: link.id, master_ticket: @event.master_ticket, state: states)
                          .order(:id).last
    return unless mapping   # never copied (link created later, or the open was skipped)

    create_command(link, mapping)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def block_reason(link, slave)
    return "copying is paused" if @master.user.copier_paused
    return "slave kill switch is on" if slave.kill_switch
    return "slave is paused" if slave.paused
    return "symbol #{@event.symbol} not in link whitelist" unless link.allows_symbol?(@event.symbol)
    return "pending orders are not copied in reverse mode" if @event.event_type == "pending_place" && link.reverse
    nil
  end

  def create_command(link, mapping, status: "pending", message: nil)
    Command.create!(
      trading_account: link.slave_account,
      trade_event: (@only_link ? nil : @event),   # replays must not collide with the original event row
      copy_link: link,
      trade_mapping: mapping,
      action: @event.event_type,
      status: status,
      result_message: message,
      symbol: @event.symbol,
      side: @event.side,
      volume: @event.volume,
      price: @event.price,
      sl: @event.sl,
      tp: @event.tp,
      lot_mode: link.lot_mode,
      lot_value: link.lot_value,
      master_balance: @event.master_balance,
      reverse: link.reverse,
      max_slippage: link.max_slippage,
      symbol_suffix: link.symbol_suffix,
      ratio: ratio
    )
  end

  def ratio
    return 0 unless @event.event_type == "partial_close"
    prev = @event.prev_volume.to_d
    prev.positive? ? [@event.volume.to_d / prev, 1].min : 0
  end
end
