# Triggered (throttled) from heartbeats. Repairs drift between master, DB and slave.
class ReconcileJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 1

  def perform(account_id)
    account = TradingAccount.find_by(id: account_id)
    return unless account

    if account.slave?
      SlaveSweep.call(account)
      account.slave_links.includes(:master_account, :slave_account).find_each { |l| Reconciler.call(l) }
    else
      account.master_links.includes(:master_account, :slave_account).find_each { |l| Reconciler.call(l) }
    end
  end
end
