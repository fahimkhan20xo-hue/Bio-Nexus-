import test from 'node:test';
import assert from 'node:assert/strict';
import { makeStore } from './helpers.js';
import { DAY_MS } from '../src/store.js';

const plans = {
  free: { daily: 3, softPct: 0.8 },
  premium: { daily: 6, softPct: 0.9 },
  institution: { daily: 9, softPct: 0.95 },
};
const cfg = {
  ipReqPerMin: 1000,
  regPerIpDay: 3,
  regGlobalPerDay: 5,
  aiPerIpDay: 1000,
  dailyBudget: 1000,
  maxUnits: 120,
  reservationTtlSec: 90,
  maxInflight: 1,
  ridTtlSec: 900,
  plans,
};
const T0 = Date.UTC(2026, 10, 20, 12, 0, 0);
const base = { iid: 'inst-1', ipHash: 'ip-1', now: T0, units: 40, cfg };
const rid = () => crypto.randomUUID();

function admit(store, o = {}) {
  return store.admit({ ...base, rid: rid(), ...o });
}
function settle(store, id, action, o = {}) {
  return store.settle({ reservationId: id, iid: base.iid, action, now: T0, cfg, ...o });
}

test('a request reserves budget and counts against the installation', () => {
  const { store } = makeStore();
  const r = admit(store);
  assert.equal(r.ok, true);
  assert.equal(r.remaining, 2);
  assert.equal(r.plan, 'free');
});

test('per-installation daily limit: the 4th request is refused, with the time until reset', () => {
  const { store } = makeStore();
  for (let i = 0; i < 3; i++) {
    const r = admit(store);
    assert.equal(r.ok, true, `request ${i + 1}`);
    assert.equal(settle(store, r.reservationId, 'commit').ok, true);
  }
  const r = admit(store);
  assert.equal(r.ok, false);
  assert.equal(r.code, 'install_quota_exhausted');
  assert.ok(r.retryAfterSec > 0 && r.retryAfterSec <= 86400);
});

test('the limit resets on the next UTC day', () => {
  const { store } = makeStore();
  for (let i = 0; i < 3; i++) {
    const r = admit(store);
    settle(store, r.reservationId, 'commit');
  }
  assert.equal(admit(store).code, 'install_quota_exhausted');
  const tomorrow = admit(store, { now: T0 + DAY_MS });
  assert.equal(tomorrow.ok, true);
});

test('release gives the request back to the installation and the budget back to everyone', () => {
  const { store } = makeStore();
  const a = admit(store);
  assert.equal(settle(store, a.reservationId, 'release').ok, true);
  const s = store.status({ iid: base.iid, ipHash: 'ip-1', now: T0, cfg });
  assert.equal(s.used, 0);
  assert.equal(s.remaining, 3);
});

test('commit charges the ACTUAL units, and never more than maxUnits', () => {
  const { store, db } = makeStore();
  const a = admit(store);
  assert.equal(settle(store, a.reservationId, 'commit', { actualUnits: 12 }).charged, 12);
  const b = admit(store, { iid: 'inst-2' });
  assert.equal(store.settle({ reservationId: b.reservationId, iid: 'inst-2', action: 'commit', actualUnits: 99999, now: T0, cfg }).charged, 120);
  const row = db.prepare('SELECT used, reserved FROM budget').get();
  assert.equal(row.used, 132);
  assert.equal(row.reserved, 0);
});

test('a reservation can be settled only once, and only by its owner', () => {
  const { store } = makeStore();
  const a = admit(store);
  assert.equal(store.settle({ reservationId: a.reservationId, iid: 'someone-else', action: 'commit', now: T0, cfg }).code, 'unknown_reservation');
  assert.equal(settle(store, a.reservationId, 'commit').ok, true);
  assert.equal(settle(store, a.reservationId, 'commit').code, 'already_settled');
  assert.equal(settle(store, a.reservationId, 'release').code, 'already_settled');
});

test('replay: the same request id is accepted once', () => {
  const { store } = makeStore();
  const id = rid();
  const a = admit(store, { rid: id });
  assert.equal(a.ok, true);
  settle(store, a.reservationId, 'commit');
  assert.equal(admit(store, { rid: id }).code, 'replay');
});

test('concurrency: only one reservation may be in flight per installation', () => {
  const { store } = makeStore();
  assert.equal(admit(store).ok, true);
  assert.equal(admit(store).code, 'too_many_concurrent');
});

test('budget: free plan stops at 80%, and the hard cap is never reserved past', () => {
  const { store, db } = makeStore();
  let granted = 0;
  for (let i = 0; i < 50; i++) {
    const r = admit(store, { iid: `inst-${i}` });
    if (r.ok) {
      granted++;
      settle(store, r.reservationId, 'commit', { iid: `inst-${i}`, actualUnits: 40 });
    } else {
      assert.equal(r.code, 'budget_throttled');
    }
  }
  assert.equal(granted, 20); // 20 x 40 = 800 = 80% of 1000
  assert.equal(db.prepare('SELECT used FROM budget').get().used, 800);
});

test('budget: a premium plan may use more of the budget than free (prepared for later)', () => {
  const { store, db } = makeStore();
  db.prepare("INSERT INTO entitlements(iid, plan, expires) VALUES('vip', 'premium', NULL)").run();
  for (let i = 0; i < 20; i++) {
    const r = admit(store, { iid: `inst-${i}` });
    settle(store, r.reservationId, 'commit', { iid: `inst-${i}`, actualUnits: 40 });
  }
  assert.equal(admit(store, { iid: 'inst-free' }).code, 'budget_throttled');
  const vip = admit(store, { iid: 'vip' });
  assert.equal(vip.ok, true);
  assert.equal(vip.plan, 'premium');
});

test('budget: when used reaches the cap, even a premium plan is refused', () => {
  const { store, db } = makeStore();
  db.prepare("INSERT INTO entitlements(iid, plan, expires) VALUES('vip', 'premium', NULL)").run();
  store.init();
  db.prepare('INSERT INTO budget(day, used, reserved) VALUES(?, 1000, 0)').run(Math.floor(T0 / DAY_MS));
  assert.equal(admit(store, { iid: 'vip' }).code, 'budget_exhausted');
});

test('an expired entitlement falls back to free', () => {
  const { store, db } = makeStore();
  db.prepare("INSERT INTO entitlements(iid, plan, expires) VALUES('old', 'premium', ?)").run(T0 - 1000);
  assert.equal(admit(store, { iid: 'old' }).plan, 'free');
});

test('fail closed: a missing or broken budget refuses the request', () => {
  const { store } = makeStore();
  assert.equal(admit(store, { cfg: { ...cfg, dailyBudget: 0 } }).code, 'budget_unverifiable');
  assert.equal(admit(store, { iid: 'a', units: 0 }).code, 'budget_unverifiable');
  assert.equal(admit(store, { iid: 'b', units: 99999 }).code, 'budget_unverifiable');
  assert.equal(admit(store, { iid: 'c', units: 1.5 }).code, 'budget_unverifiable');
});

test('an interrupted request is closed after the TTL and counted as USED (the budget fails safe)', () => {
  const { store, db } = makeStore();
  const a = admit(store);
  assert.equal(a.ok, true);
  const later = T0 + 91_000;
  const s = store.status({ iid: base.iid, ipHash: 'ip-1', now: later, cfg });
  assert.equal(s.ok, true);
  const b = db.prepare('SELECT used, reserved FROM budget').get();
  assert.equal(b.used, 40);
  assert.equal(b.reserved, 0);
  assert.equal(settle(store, a.reservationId, 'commit', { now: later }).code, 'already_settled');
  // the slot is free again, so the installation is not stuck
  assert.equal(admit(store, { now: later }).ok, true);
});

test('per-IP request rate: refused above the limit, resets next minute', () => {
  const { store } = makeStore();
  const c = { ...cfg, ipReqPerMin: 3 };
  for (let i = 0; i < 3; i++) assert.equal(store.ipGate({ ipHash: 'x', now: T0, cfg: c }).ok, true);
  const r = store.ipGate({ ipHash: 'x', now: T0, cfg: c });
  assert.equal(r.code, 'ip_rate_limited');
  assert.ok(r.retryAfterSec >= 1 && r.retryAfterSec <= 60);
  assert.equal(store.ipGate({ ipHash: 'x', now: T0 + 61_000, cfg: c }).ok, true);
  assert.equal(store.ipGate({ ipHash: 'other', now: T0, cfg: c }).ok, true);
});

test('registration limits: per IP and global', () => {
  const { store } = makeStore();
  for (let i = 0; i < 3; i++) assert.equal(store.registerGate({ ipHash: 'ip-a', now: T0, cfg }).ok, true);
  assert.equal(store.registerGate({ ipHash: 'ip-a', now: T0, cfg }).code, 'register_limited');
  assert.equal(store.registerGate({ ipHash: 'ip-b', now: T0, cfg }).ok, true);
  assert.equal(store.registerGate({ ipHash: 'ip-c', now: T0, cfg }).ok, true);
  assert.equal(store.registerGate({ ipHash: 'ip-d', now: T0, cfg }).code, 'register_busy'); // 5 per day in total
});

test('status shows only a coarse global state, never budget numbers', () => {
  const { store } = makeStore();
  const s = store.status({ iid: 'i', ipHash: 'p', now: T0, cfg });
  assert.deepEqual(Object.keys(s).sort(), ['dailyLimit', 'global', 'ok', 'plan', 'remaining', 'resetsInSec', 'used']);
  assert.equal(s.global, 'ok');
});

test('a failure inside a transaction rolls everything back', () => {
  const { store, db } = makeStore();
  assert.throws(() =>
    store.tx(() => {
      store._run("INSERT INTO seen_rid(rid, ts) VALUES('x', 1)");
      throw new Error('boom');
    }),
  );
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM seen_rid').get().n, 0);
});

test('cleanup removes old rows and keeps today', () => {
  const { store, db } = makeStore();
  const a = admit(store);
  settle(store, a.reservationId, 'commit');
  const later = T0 + 5 * DAY_MS;
  store.cleanup(later, cfg);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM install_day').get().n, 0);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM reservations').get().n, 0);
  const b = admit(store, { now: later });
  assert.equal(b.ok, true);
});
