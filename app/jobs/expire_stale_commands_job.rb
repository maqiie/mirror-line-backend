# Runs every minute (see config/initializers/sidekiq.rb).
#   * opening commands nobody executed within 60s are expired (a late entry is a bad entry)
#   * commands re-sent too many times with no ack are failed
#   * anything still undelivered after a day is dropped
# Close/modify commands are NOT expired early: an offline slave must still close
# its trades when it comes back.
class ExpireStaleCommandsJob
  include Sidekiq::Job

  OPEN_TTL = 60.seconds
  HARD_TTL = 24.hours

  def perform
    Command.in_flight.where(action: Command::OPENING_ACTIONS).where("created_at < ?", OPEN_TTL.ago).find_each do |c|
      AckProcessor.call(c, status: "expired", message: "not executed in time")
    end

    Command.where(status: "sent").where("attempts >= ?", Command::MAX_ATTEMPTS)
           .where("sent_at < ?", Command::REDELIVER_AFTER.ago).find_each do |c|
      AckProcessor.call(c, status: "failed", message: "no_ack")
    end

    Command.in_flight.where("created_at < ?", HARD_TTL.ago).find_each do |c|
      AckProcessor.call(c, status: "expired", message: "undelivered for 24h")
    end
  end
end
