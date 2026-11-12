// Runs the dashboard's REAL api.js against a live Rails server and checks every response
// against the shapes the UI was built on (demo.seed()). Run with the backend up and seeded:
//   EMAIL=admin@example.com PASSWORD=change-me-please npx vitest run
import { describe, it, expect, beforeAll } from 'vitest';
import * as api from './lib/api';
import * as demo from './lib/demo';

const EMAIL = process.env.EMAIL ?? 'admin@example.com';
const PASSWORD = process.env.PASSWORD ?? 'change-me-please';
const type = (v) => (v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v);

// every key the UI reads from the demo object must exist on the live object, with the same type
// (null is accepted where the demo has a number/string: optional values such as sl/tp/profit)
function expectShape(live, ref, path) {
  for (const [k, rv] of Object.entries(ref)) {
    expect(live, `${path} is missing "${k}"`).toHaveProperty(k);
    const lt = type(live[k]);
    const rt = type(rv);
    if (lt !== 'null' && rt !== 'null') expect(lt, `${path}.${k}: ${lt} vs demo ${rt}`).toBe(rt);
  }
}

let snap;
const seed = demo.seed();

beforeAll(async () => {
  const { token } = await api.login(EMAIL, PASSWORD);
  api.setToken(token);
  snap = await api.snapshot();
});

describe('login', () => {
  it('rejects a wrong password with a readable message', async () => {
    api.setToken(null);
    await expect(api.login(EMAIL, 'wrong-password')).rejects.toThrow(/invalid credentials/i);
    const { token } = await api.login(EMAIL, PASSWORD);
    api.setToken(token);
  });
});

describe('snapshot shape matches demo.seed()', () => {
  it('has the top-level keys', () => {
    for (const k of Object.keys(seed)) expect(snap, `snapshot missing "${k}"`).toHaveProperty(k);
  });
  it('accounts', () => { expect(snap.accounts.length).toBeGreaterThan(0); snap.accounts.forEach((a, i) => expectShape(a, seed.accounts[0], `accounts[${i}]`)); });
  it('links', () => { expect(snap.links.length).toBeGreaterThan(0); snap.links.forEach((l, i) => expectShape(l, seed.links[0], `links[${i}]`)); });
  it('positions', () => { snap.positions.forEach((p, i) => expectShape(p, seed.positions[0], `positions[${i}]`)); });
  it('events and per-follower results', () => {
    snap.events.forEach((e, i) => {
      expectShape(e, seed.events[0], `events[${i}]`);
      e.results.forEach((r, j) => expectShape(r, seed.events[0].results[0], `events[${i}].results[${j}]`));
    });
  });
  it('equity series has points the chart can draw', () => {
    expect(snap.equity.length).toBeGreaterThanOrEqual(2);
    snap.equity.forEach((p, i) => expectShape(p, seed.equity[0], `equity[${i}]`));
  });
  it('guards are keyed by follower id with all five limits', () => {
    const followers = snap.accounts.filter((a) => a.role === 'slave');
    followers.forEach((a) => expectShape(snap.guards[a.id], Object.values(seed.guards)[0], `guards[${a.id}]`));
  });
  it('copier and market', () => {
    expect(typeof snap.copier.paused).toBe('boolean');
    expect(typeof snap.market).toBe('object');
  });
  it('every position and event points at accounts that exist', () => {
    const ids = new Set(snap.accounts.map((a) => a.id));
    snap.positions.forEach((p) => expect(ids.has(p.account_id)).toBe(true));
    snap.events.forEach((e) => e.results.forEach((r) => expect(ids.has(r.slave_id)).toBe(true)));
  });
});

describe('actions the UI performs', () => {
  const uniq = Date.now() % 1_000_000;
  let acct, link;

  it('createAccount returns { account, token } and shows up in the snapshot', async () => {
    const r = await api.createAccount({ name: 'Contract test', platform: 'mt5', login: String(900000 + uniq), broker: 'Test', server: 'Test-Srv', role: 'slave' });
    expect(r.token).toMatch(/^tc_/);
    acct = r.account;
    expectShape(acct, seed.accounts[0], 'created account');
    expect((await api.snapshot()).accounts.some((a) => a.id === acct.id)).toBe(true);
  });

  it('a duplicate account is rejected with a readable message', async () => {
    await expect(api.createAccount({ name: 'dup', platform: 'mt5', login: String(acct.login), broker: 'Test', server: 'Test-Srv', role: 'slave' })).rejects.toThrow(/taken|already|unique/i);
  });

  it('saveLink creates, then edits, then removeLink deletes', async () => {
    const master = snap.accounts.find((a) => a.role === 'master');
    link = await api.saveLink({ master_id: master.id, slave_id: acct.id, lot_mode: 'risk_pct', lot_value: 1, reverse: false, max_slippage: 20, symbol_suffix: '' });
    expectShape(link, seed.links[0], 'created link');
    const edited = await api.saveLink({ ...link, lot_mode: 'balance_ratio', lot_value: 1.5, reverse: true, symbol_suffix: '.m' });
    expect([edited.lot_mode, edited.lot_value, edited.reverse, edited.symbol_suffix]).toEqual(['balance_ratio', 1.5, true, '.m']);
    await expect(api.saveLink({ ...link, lot_mode: 'martingale' })).rejects.toThrow(/lot mode/i);
    expect(await api.removeLink(link.id)).toBeNull();
  });

  it('setAccountPaused toggles the follower', async () => {
    expect((await api.setAccountPaused(acct.id, true)).paused).toBe(true);
    expect((await api.setAccountPaused(acct.id, false)).paused).toBe(false);
  });

  it('saveGuards stores the five limits and rejects nonsense', async () => {
    await api.saveGuards(acct.id, { max_lot: 2, max_open: 4, daily_loss_pct: 3, min_margin_level: 200, max_spread: 25 });
    expect((await api.snapshot()).guards[acct.id].max_lot).toBe(2);
    await expect(api.saveGuards(acct.id, { max_lot: 'abc', max_open: 4, daily_loss_pct: 3, min_margin_level: 200, max_spread: 25 })).rejects.toThrow(/numbers/i);
  });

  it('regenerateToken returns a new EA token', async () => {
    expect((await api.regenerateToken(acct.id)).token).toMatch(/^tc_/);
  });

  it('placeOrder accepts the order ticket payload', async () => {
    await api.setAccountPaused(acct.id, false);
    const r = await api.placeOrder({ account_ids: [acct.id], symbol: 'EURUSD', side: 'buy', volume: 0.1, sl: null, tp: null });
    expect(r.sent).toBe(1);
    await expect(api.placeOrder({ account_ids: [acct.id], symbol: 'EUR USD', side: 'buy', volume: 0.1 })).rejects.toThrow(/symbol/i);
    await expect(api.placeOrder({ account_ids: [acct.id], symbol: 'EURUSD', side: 'buy', volume: 0 })).rejects.toThrow(/lot/i);
  });

  it('closeAll for one account and for everyone', async () => {
    expect(await api.closeAll(acct.id)).toBeTruthy();
    expect(await api.closeAll(null)).toBeTruthy();
  });

  it('closePosition on an unknown ticket is a clean error, not a crash', async () => {
    await expect(api.closePosition(acct.id * 10 ** 12 + 12345)).rejects.toThrow(/not found/i);
  });

  it('setCopierPaused flips the global switch both ways', async () => {
    expect((await api.setCopierPaused(true)).paused).toBe(true);
    expect((await api.snapshot()).copier.paused).toBe(true);
    expect((await api.setCopierPaused(false)).paused).toBe(false);
  });

  it('removeAccount returns 204 and the account disappears', async () => {
    expect(await api.removeAccount(acct.id)).toBeNull();
    expect((await api.snapshot()).accounts.some((a) => a.id === acct.id)).toBe(false);
  });
});
