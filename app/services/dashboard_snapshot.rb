# Builds the single JSON document the Mirrorline dashboard polls every 3 seconds:
#   { accounts, links, positions, events, equity, guards, copier, market }
# Field names match mirrorline-web/src/lib/demo.js exactly.
class DashboardSnapshot
  # Broker tickets are only unique per account, but the dashboard identifies a position by
  # one number. We expose  account_id * 10^12 + broker_ticket  and decode it on the way back.
  TICKET_SPACE = 10**12
  EVENT_LIMIT = 60
  DASHBOARD_EVENT_ID_BASE = 1_000_000_000   # keeps numeric ids of dashboard orders apart from master event ids
  EQUITY_DAYS = 90

  def self.encode_ticket(account_id, ticket) = account_id.to_i * TICKET_SPACE + ticket.to_i
  def self.decode_ticket(number)
    n = number.to_i
    [n / TICKET_SPACE, n % TICKET_SPACE]
  end

  def initialize(user)
    @user = user
    @accounts = user.trading_accounts.order(:id).to_a
  end

  def call
    {
      accounts: @accounts.map(&:as_api),
      links: @user.copy_links.order(:id).map(&:as_api),
      positions: positions,
      events: events,
      equity: equity,
      guards: guards,
      copier: { paused: @user.copier_paused },
      market: market
    }
  end

  private

  def ids = @accounts.map(&:id)

  def guards
    @accounts.select(&:slave?).to_h { |a| [a.id, a.effective_guards] }
  end

  # ---- positions: every open position each EA reported in its last heartbeat ----
  def positions
    keys = @accounts.select(&:slave?).flat_map { |a| Array(a.copies).map { |c| c["m"].to_i } }
    mappings = TradeMapping.where(id: keys).includes(:copy_link).index_by(&:id)

    @accounts.flat_map do |a|
      held = a.slave? ? Array(a.copies).index_by { |c| c["s"].to_i } : {}
      Array(a.positions).map do |p|
        mapping = held[p["t"].to_i] && mappings[held[p["t"].to_i]["m"].to_i]
        master_ticket = (mapping&.copy_link && mapping.master_ticket) ? self.class.encode_ticket(mapping.copy_link.master_account_id, mapping.master_ticket) : nil
        {
          ticket: self.class.encode_ticket(a.id, p["t"]),
          account_id: a.id,
          master_ticket: master_ticket,
          symbol: p["s"],
          side: p["d"],
          volume: p["v"].to_f,
          open_price: p["o"].to_f,
          price: p["p"].to_f,
          sl: p["sl"].to_f.zero? ? nil : p["sl"].to_f,
          tp: p["tp"].to_f.zero? ? nil : p["tp"].to_f,
          profit: p["pr"].to_f,
          opened_at: (p["at"].to_i.positive? ? Time.at(p["at"].to_i).utc : (a.last_snapshot_at || Time.current)).iso8601
        }
      end
    end
  end

  # ---- market: watched-symbol quotes from the EAs (master wins), gaps filled from positions ----
  def market
    out = {}
    @accounts.sort_by { |a| a.master? ? 1 : 0 }.each { |a| a.quotes.to_h.each { |s, v| out[s] = v.to_f if v.to_f.positive? } }
    @accounts.each { |a| Array(a.positions).each { |p| out[p["s"]] ||= p["p"].to_f } }
    out
  end

  # ---- events: master trades (with per-follower results) + dashboard-originated orders ----
  def events
    master_ids = @accounts.select(&:master?).map(&:id)
    from_master = TradeEvent.where(trading_account_id: master_ids).order(id: :desc).limit(EVENT_LIMIT).includes(:commands).map { |e| master_event(e) }

    manual = Command.where(trading_account_id: ids, trade_event_id: nil, copy_link_id: nil, action: %w[open close_ticket])
                    .where.not(batch_key: nil).order(id: :desc).limit(EVENT_LIMIT * 3).to_a.group_by(&:batch_key)
    from_dashboard = manual.values.first(EVENT_LIMIT).map { |cmds| dashboard_event(cmds) }

    # newest first; ties (same millisecond) fall back to the numeric id so the order is stable
    (from_master + from_dashboard)
      .sort_by { |e| [Time.iso8601(e[:at]), e[:id]] }.reverse.first(EVENT_LIMIT)
  end

  def event_type(action)
    case action
    when "open", "add", "pending_place" then "open"
    when "close", "partial_close", "pending_delete", "close_ticket" then "close"
    else "modify"
    end
  end

  def master_event(e)
    {
      id: e.id, type: event_type(e.event_type), symbol: e.symbol,
      side: e.side.to_s.sub(/_(limit|stop)\z/, ""), volume: e.volume.to_f,
      at: e.created_at.iso8601(3), profit: e.profit&.to_f, source: "master",
      results: e.commands.sort_by(&:id).map { |c| result(c) }
    }
  end

  def dashboard_event(cmds)
    first = cmds.min_by(&:id)
    {
      id: DASHBOARD_EVENT_ID_BASE + first.id, type: event_type(first.action), symbol: first.symbol, side: first.side,
      volume: first.volume.to_f, at: first.created_at.iso8601(3), profit: nil, source: "dashboard",
      account_id: first.trading_account_id,
      results: cmds.sort_by(&:id).map { |c| result(c) }
    }
  end

  def result(c)
    status = case c.status
             when "executed" then "executed"
             when "failed", "expired" then "failed"
             else "skipped"
             end
    latency = (c.status == "executed" && c.acked_at) ? ((c.acked_at - c.created_at) * 1000).round : 0
    note = c.status.in?(%w[pending sent]) ? "Waiting for the account" : c.result_message.to_s
    { slave_id: c.trading_account_id, volume: (c.executed_volume || c.volume).to_f, status: status, latency_ms: latency, note: note }
  end

  # ---- equity: combined equity per day for 90 days, carrying each account's last value forward ----
  def equity
    since = EQUITY_DAYS.days.ago.beginning_of_day
    rows = EquitySample.where(trading_account_id: ids).where("at >= ?", since).order(:at).pluck(:trading_account_id, :at, :equity)

    last_by_day = Hash.new { |h, k| h[k] = {} } # day => { account_id => equity }
    rows.each { |aid, at, eq| last_by_day[at.utc.to_date][aid] = eq.to_f }

    series = []
    carry = {}
    (since.utc.to_date..Time.current.utc.to_date).each do |day|
      carry.merge!(last_by_day[day]) if last_by_day.key?(day)
      next if carry.empty?
      series << { t: day.to_time.utc.to_i * 1000, v: carry.values.sum.round(2) }
    end

    now_total = @accounts.sum { |a| a.equity.to_f }.round(2)
    series << { t: (Time.current.to_f * 1000).to_i, v: now_total }
    series.unshift({ t: series.first[:t] - 86_400_000, v: series.first[:v] }) if series.size < 2
    series
  end
end
