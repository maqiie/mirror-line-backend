# Records a slave's result for a command and moves the matching TradeMapping
# through its state machine. The first final result wins; later acks are ignored.
class AckProcessor
  FINAL = Command::FINAL_STATUSES

  def self.call(command, **result) = new(command, **result).call

  def initialize(command, status:, message: nil, slave_ticket: nil, volume: nil, price: nil)
    @command = command
    @status = FINAL.include?(status.to_s) ? status.to_s : "failed"
    @message = message.to_s.truncate(500)
    @slave_ticket = slave_ticket.to_i.positive? ? slave_ticket.to_i : nil
    @volume = volume
    @price = price
  end

  def call
    Command.transaction do
      @command.lock!
      unless @command.final?
        @command.update!(
          status: @status, result_message: @message, slave_ticket: @slave_ticket,
          executed_volume: @volume, executed_price: @price, acked_at: Time.current
        )
        update_mapping if @command.trade_mapping_id
      end
    end
    @command
  end

  private

  def ok? = @status == "executed"

  def update_mapping
    # The EA answers "already processed" when a command is re-delivered after its first
    # ack was lost. We cannot know the original outcome, so leave the mapping to the
    # reconciler, which compares against what the slave actually holds.
    return if @message == "already processed"

    m = @command.trade_mapping
    return unless m
    m.lock!

    case @command.action
    when "open"
      if ok? || @message.include?("already copied")
        mark_open(m)
      elsif m.state == "open_requested"
        mark_failed(m)
      end
    when "pending_place"
      if ok?
        m.update!(state: "pending", slave_ticket: @slave_ticket)
      elsif m.state == "pending_requested"
        mark_failed(m)
      end
    when "close"
      mark_closed(m, "closed") if ok? || @message.include?("no open copy")
    when "pending_delete"
      mark_closed(m, "pending_deleted") if ok? || @message.include?("no pending copy") || @message.include?("no longer exists")
    end
  end

  def mark_open(m)
    m.update!(state: "open", slave_ticket: @slave_ticket || m.slave_ticket,
              opened_at: m.opened_at || Time.current, closed_at: nil, close_reason: nil)
  end

  def mark_closed(m, reason)
    m.update!(state: "closed", closed_at: Time.current, close_reason: reason)
  end

  def mark_failed(m)
    m.update!(state: "failed", closed_at: Time.current, close_reason: failure_reason)
  end

  def failure_reason
    return "expired" if @status == "expired"
    return "no_ack" if @message == "no_ack"
    "open_failed: #{@message}".truncate(200)
  end
end
