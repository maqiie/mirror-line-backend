#!/usr/bin/env node
// Fake MetaTrader terminals that talk to the Rails API exactly like CopierMaster / CopierSlave do.
// Use it to test the dashboard + backend without MetaTrader.
//
//   node tools/simulate_eas.mjs --master=<master token> --slaves=<token1>,<token2> [--url=http://127.0.0.1:3000] [--auto=true]
//
// The master opens and closes random trades every ~10 s (--auto=false to stop that). Followers copy them.
// Orders and closes you send from the dashboard are executed by these fake terminals too.

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')));
const BASE = (args.url ?? 'http://127.0.0.1:3000').replace(/\/$/, '');
const AUTO = args.auto !== 'false';
if (!args.master) {
  console.error('usage: node tools/simulate_eas.mjs --master=<token> --slaves=<tok1,tok2> [--url=...] [--auto=false]');
  process.exit(1);
}

const SYMBOLS = {
  EURUSD: { p: 1.0842, step: 0.0001, contract: 100000 },
  GBPUSD: { p: 1.2951, step: 0.0001, contract: 100000 },
  USDJPY: { p: 151.82, step: 0.01, contract: 1000 },
  XAUUSD: { p: 2652.4, step: 0.1, contract: 100 },
  US30: { p: 42810, step: 1, contract: 1 },
};
const base = (s) => s.replace(/[^A-Z0-9].*$/, '');
const rnd = (a, b) => a + Math.random() * (b - a);
const r2 = (x) => Math.round(x * 100) / 100;
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

let ticketSeq = 5_000_000 + Math.floor(Math.random() * 1e6);

class Terminal {
  constructor(name, token, role, balance) {
    Object.assign(this, { name, token, role, balance, positions: [], keyToTicket: new Map(), lastId: 0, seq: 0 });
  }

  async http(method, path, body) {
    const res = await fetch(BASE + path, {
      method,
      headers: { 'Content-Type': 'application/json', 'X-Account-Token': this.token },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (!res.ok && res.status !== 409) throw new Error(`${this.name} ${method} ${path} -> ${res.status} ${text.slice(0, 200)}`);
    return text;
  }

  price(sym, side) {
    const m = SYMBOLS[base(sym)];
    return side === 'buy' ? m.p : m.p + m.step * 1.2; // crude spread
  }
  profit(p) {
    const m = SYMBOLS[base(p.s)];
    return r2((m.p - p.o) * (p.d === 'buy' ? 1 : -1) * p.v * m.contract);
  }
  get equity() { return r2(this.balance + this.positions.reduce((t, p) => t + this.profit(p), 0)); }

  snapshotPositions() {
    return this.positions.map((p) => ({ t: p.t, s: p.s, d: p.d, v: p.v, o: p.o, p: SYMBOLS[base(p.s)].p, sl: p.sl ?? 0, tp: p.tp ?? 0, pr: this.profit(p), at: p.at }));
  }

  async heartbeat() {
    const quotes = Object.fromEntries(Object.entries(SYMBOLS).map(([k, m]) => [k, m.p]));
    const body = { role: this.role, balance: this.balance, equity: this.equity, margin_level: 1200, positions: this.snapshotPositions(), quotes, outbox: 0 };
    if (this.role === 'master') body.open_tickets = this.positions.map((p) => p.t);
    else body.copies = [...this.keyToTicket].filter(([, t]) => this.positions.some((p) => p.t === t)).map(([m, s]) => ({ m, s, v: this.positions.find((p) => p.t === s).v, p: 0 }));
    const reply = await this.http('POST', '/api/v1/heartbeat', body);
    this.flags = Object.fromEntries(reply.split('\n').filter(Boolean).map((l) => l.split('|')));
  }

  async emit(type, p, extra = {}) {
    const body = { idempotency_key: `${this.token.slice(-6)}-${++this.seq}-${Date.now()}`, event_type: type, master_ticket: p.t, symbol: p.s, side: p.d, volume: extra.volume ?? p.v, prev_volume: extra.prev ?? 0, price: p.o, sl: p.sl ?? 0, tp: p.tp ?? 0, master_balance: this.balance, event_time: Math.floor(Date.now() / 1000), ...extra.fields };
    await this.http('POST', '/api/v1/events', body);
  }

  openPosition({ sym, side, vol, sl, tp }) {
    const p = { t: ++ticketSeq, s: sym, d: side, v: vol, o: this.price(sym, side), sl, tp, at: Math.floor(Date.now() / 1000) };
    this.positions.push(p);
    return p;
  }
  async closePosition(p, { report = true } = {}) {
    const pr = this.profit(p);
    this.balance = r2(this.balance + pr);
    this.positions = this.positions.filter((x) => x !== p);
    if (this.role === 'master' && report) await this.emit('close', p, { fields: { profit: pr } });
    return pr;
  }

  async poll() {
    const text = await this.http('GET', '/api/v1/commands/pending?limit=20');
    for (const line of text.split('\n').filter(Boolean)) {
      const f = line.split('|');
      const c = { id: +f[0], action: f[1], key: +f[2], symbol: f[3], side: f[4], volume: +f[5], price: +f[6], sl: +f[7] || null, tp: +f[8] || null, lotMode: f[9], lotValue: +f[10], mBalance: +f[11], reverse: f[12] === '1', ratio: +f[13], created: +f[14], suffix: f[16] ?? '' };
      let res;
      if (c.id <= this.lastId) res = { status: 'skipped', message: 'already processed' };
      else { res = await this.execute(c); this.lastId = c.id; }
      await this.http('POST', `/api/v1/commands/${c.id}/ack`, res);
      log(`${this.name.padEnd(8)} ${c.action.padEnd(13)} ${c.symbol.padEnd(7)} -> ${res.status}${res.message ? ` (${res.message})` : ''}`);
    }
  }

  lotFor(c) {
    let v;
    switch (c.lotMode) {
      case 'fixed': v = c.lotValue; break;
      case 'multiplier': v = c.volume * c.lotValue; break;
      case 'balance_ratio': v = c.volume * (this.balance / (c.mBalance || this.balance)) * c.lotValue; break;
      case 'risk_pct': v = c.sl ? (this.balance * c.lotValue) / 100 / (Math.abs(this.price(c.symbol, c.side) - c.sl) * SYMBOLS[base(c.symbol)].contract) : null; break;
      default: v = null;
    }
    return v == null ? 0 : Math.floor(v * 100) / 100;
  }

  async execute(c) {
    if (c.action === 'open') {
      if (c.key && this.keyToTicket.has(c.key) && this.positions.some((p) => p.t === this.keyToTicket.get(c.key))) return { status: 'skipped', message: 'already copied' };
      if (this.flags?.KILL === '1' || this.flags?.PAUSE === '1') return { status: 'skipped', message: 'account paused' };
      if (Date.now() / 1000 - c.created > 60) return { status: 'skipped', message: 'stale command' };
      const vol = this.lotFor(c);
      if (vol < 0.01) return { status: 'skipped', message: 'lot below broker minimum' };
      const side = c.reverse ? (c.side === 'buy' ? 'sell' : 'buy') : c.side;
      const [sl, tp] = c.reverse ? [c.tp, c.sl] : [c.sl, c.tp];
      const p = this.openPosition({ sym: c.symbol + c.suffix, side, vol, sl, tp });
      if (c.key) this.keyToTicket.set(c.key, p.t);
      if (this.role === 'master') await this.emit('open', p);
      return { status: 'executed', slave_ticket: p.t, volume: vol, price: p.o };
    }
    if (c.action === 'close' || c.action === 'close_ticket') {
      const ticket = c.action === 'close' ? this.keyToTicket.get(c.key) : c.key;
      const p = this.positions.find((x) => x.t === ticket);
      if (!p) return { status: 'skipped', message: 'no open copy (already closed?)' };
      await this.closePosition(p);
      this.keyToTicket.delete(c.key);
      return { status: 'executed', slave_ticket: ticket, volume: p.v, price: p.o };
    }
    if (c.action === 'close_all') {
      for (const p of [...this.positions]) await this.closePosition(p);
      return { status: 'executed', message: 'closed all' };
    }
    if (c.action === 'partial_close') {
      const p = this.positions.find((x) => x.t === this.keyToTicket.get(c.key));
      if (!p) return { status: 'skipped', message: 'no open copy' };
      p.v = Math.max(0.01, Math.round(p.v * (1 - c.ratio) * 100) / 100);
      return { status: 'executed', slave_ticket: p.t };
    }
    if (c.action === 'modify') {
      const p = this.positions.find((x) => x.t === this.keyToTicket.get(c.key));
      if (!p) return { status: 'skipped', message: 'no open copy' };
      [p.sl, p.tp] = c.reverse ? [c.tp, c.sl] : [c.sl, c.tp];
      return { status: 'executed', slave_ticket: p.t };
    }
    return { status: 'skipped', message: `unsupported ${c.action}` };
  }

  // master only: a trader clicking in MetaTrader
  async autoTrade() {
    if (this.positions.length < 4 && (this.positions.length < 1 || Math.random() < 0.6)) {
      const sym = pick(Object.keys(SYMBOLS)); const m = SYMBOLS[sym]; const side = pick(['buy', 'sell']); const dir = side === 'buy' ? 1 : -1;
      const p = this.openPosition({ sym, side, vol: pick([0.2, 0.5, 1.0]), sl: +(m.p - dir * m.step * 40).toFixed(5), tp: +(m.p + dir * m.step * 80).toFixed(5) });
      await this.emit('open', p);
      log(`${this.name.padEnd(8)} opened ${side} ${p.v} ${sym}`);
    } else {
      const p = pick(this.positions);
      const pr = await this.closePosition(p);
      log(`${this.name.padEnd(8)} closed ${p.d} ${p.v} ${p.s} (${pr >= 0 ? '+' : ''}${pr})`);
    }
  }
}

const master = new Terminal('Master', args.master, 'master', 25000);
const slaves = (args.slaves ?? '').split(',').filter(Boolean).map((t, i) => new Terminal(`Slave ${i + 1}`, t, 'slave', 10000 * (i + 1)));
const all = [master, ...slaves];

let tick = 0;
async function loop() {
  tick++;
  for (const m of Object.values(SYMBOLS)) m.p = +(m.p + rnd(-3, 3) * m.step).toFixed(5);
  for (const t of all) {
    try {
      await t.poll();
      if (tick % 2 === 1) await t.heartbeat();
    } catch (e) { log('ERR', e.message); }
  }
  if (AUTO && tick % 10 === 5) await master.autoTrade().catch((e) => log('ERR', e.message));
}
log(`simulating ${all.length} terminals against ${BASE} (auto trades ${AUTO ? 'on' : 'off'}). Ctrl+C to stop.`);
setInterval(loop, 1000);
