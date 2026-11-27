// All quota, rate-limit and budget rules, written against a tiny SQL interface so the exact same code
// runs inside the Durable Object (SQLite storage) and in the local tests (node:sqlite).
//
//   sql.exec(query, ...bindings) -> { toArray(): object[] }      (same shape as ctx.storage.sql)
//   tx(fn)                       -> runs fn atomically            (ctx.storage.transactionSync in the DO)
//
// One Durable Object holds everything, so every decision is atomic: two requests can never
// both take the last unit of budget. Rows are tiny and cleaned up regularly.

export const DAY_MS = 86_400_000;
export const MINUTE_MS = 60_000;
export const dayOf = (ms) => Math.floor(ms / DAY_MS);
const secsToNextDay = (now) => Math.max(1, Math.ceil((DAY_MS - (now % DAY_MS)) / 1000));
const secsToNextMinute = (now) => Math.max(1, Math.ceil((MINUTE_MS - (now % MINUTE_MS)) / 1000));

const SCHEMA = [
  'CREATE TABLE IF NOT EXISTS budget(day INTEGER PRIMARY KEY, used INTEGER NOT NULL DEFAULT 0, reserved INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS reservations(id TEXT PRIMARY KEY, iid TEXT NOT NULL, day INTEGER NOT NULL, units INTEGER NOT NULL, created INTEGER NOT NULL, state TEXT NOT NULL)',
  'CREATE INDEX IF NOT EXISTS res_iid_state ON reservations(iid, state)',
  'CREATE INDEX IF NOT EXISTS res_state_created ON reservations(state, created)',
  'CREATE TABLE IF NOT EXISTS install_day(iid TEXT NOT NULL, day INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(iid, day))',
  'CREATE TABLE IF NOT EXISTS counters(name TEXT NOT NULL, win INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 0, exp INTEGER NOT NULL, PRIMARY KEY(name, win))',
  'CREATE INDEX IF NOT EXISTS counters_exp ON counters(exp)',
  'CREATE TABLE IF NOT EXISTS seen_rid(rid TEXT PRIMARY KEY, ts INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS seen_ts ON seen_rid(ts)',
  // Plans are written only by future SERVER-SIDE subscription verification. Nothing in the API writes here.
  'CREATE TABLE IF NOT EXISTS entitlements(iid TEXT PRIMARY KEY, plan TEXT NOT NULL, expires INTEGER)',
];

const deny = (code, extra = {}) => ({ ok: false, code, ...extra });

export class QuotaStore {
  constructor(sql, tx) {
    this.sql = sql;
    this.tx = tx;
  }

  init() {
    for (const stmt of SCHEMA) this.sql.exec(stmt);
  }

  _rows(q, ...p) {
    return this.sql.exec(q, ...p).toArray();
  }

  _run(q, ...p) {
    this.sql.exec(q, ...p);
  }

  /** Adds 1 to a counter and returns the new value. */
  _incr(name, win, expMs) {
    this._run(
      'INSERT INTO counters(name, win, count, exp) VALUES(?, ?, 1, ?) ON CONFLICT(name, win) DO UPDATE SET count = count + 1',
      name,
      win,
      expMs,
    );
    return this._rows('SELECT count FROM counters WHERE name = ? AND win = ?', name, win)[0].count;
  }

  _budgetRow(day, create) {
    if (create) this._run('INSERT OR IGNORE INTO budget(day) VALUES(?)', day);
    const r = this._rows('SELECT used, reserved FROM budget WHERE day = ?', day)[0];
    return r || { used: 0, reserved: 0 };
  }

  _planFor(iid, now, plans) {
    const r = this._rows('SELECT plan FROM entitlements WHERE iid = ? AND (expires IS NULL OR expires > ?)', iid, now)[0];
    const name = r && Object.prototype.hasOwnProperty.call(plans, r.plan) ? r.plan : 'free';
    return { name, ...plans[name] };
  }

  /**
   * Reservations that never finished (the Worker died, the model hung...) are closed after the TTL.
   * They are counted as USED: we cannot know whether the model ran, so the budget fails safe.
   */
  _expireStale(now, ttlSec) {
    const stale = this._rows("SELECT id, day, units FROM reservations WHERE state = 'held' AND created < ?", now - ttlSec * 1000);
    for (const r of stale) {
      this._run("UPDATE reservations SET state = 'expired' WHERE id = ?", r.id);
      this._run('UPDATE budget SET reserved = MAX(0, reserved - ?), used = used + ? WHERE day = ?', r.units, r.units, r.day);
    }
    return stale.length;
  }

  _ipRate(ipHash, now, cfg) {
    const n = this._incr(`req:ip:${ipHash}`, Math.floor(now / MINUTE_MS), now + 2 * MINUTE_MS);
    if (n > cfg.ipReqPerMin) return deny('ip_rate_limited', { retryAfterSec: secsToNextMinute(now) });
    return null;
  }

  /** Registration: per-IP and global limits on how many new installation tokens can be issued. */
  registerGate({ ipHash, now, cfg }) {
    return this.tx(() => {
      const rate = this._ipRate(ipHash, now, cfg);
      if (rate) return rate;
      const day = dayOf(now);
      const exp = now + 2 * DAY_MS;
      if (this._incr(`reg:ip:${ipHash}`, day, exp) > cfg.regPerIpDay) {
        return deny('register_limited', { retryAfterSec: secsToNextDay(now) });
      }
      if (this._incr('reg:all', day, exp) > cfg.regGlobalPerDay) {
        return deny('register_busy', { retryAfterSec: secsToNextDay(now) });
      }
      return { ok: true };
    });
  }

  /** Cheap gate used by endpoints that do not spend budget. */
  ipGate({ ipHash, now, cfg }) {
    return this.tx(() => this._ipRate(ipHash, now, cfg) || { ok: true });
  }

  /**
   * Reserve budget for one AI request. Everything below happens atomically.
   * Order matters: cheap rejections first, and the budget check last.
   */
  admit({ iid, ipHash, rid, now, units, cfg }) {
    return this.tx(() => {
      const day = dayOf(now);
      this._expireStale(now, cfg.reservationTtlSec);

      const rate = this._ipRate(ipHash, now, cfg);
      if (rate) return rate;

      // replay protection: every request id is accepted once
      this._run('DELETE FROM seen_rid WHERE ts < ?', now - cfg.ridTtlSec * 1000);
      if (this._rows('SELECT 1 AS x FROM seen_rid WHERE rid = ?', rid).length > 0) return deny('replay');
      this._run('INSERT INTO seen_rid(rid, ts) VALUES(?, ?)', rid, now);

      if (this._incr(`ai:ip:${ipHash}`, day, now + 2 * DAY_MS) > cfg.aiPerIpDay) {
        return deny('ip_daily_limit', { retryAfterSec: secsToNextDay(now) });
      }

      const plan = this._planFor(iid, now, cfg.plans);
      const used = (this._rows('SELECT count FROM install_day WHERE iid = ? AND day = ?', iid, day)[0] || { count: 0 }).count;
      if (used >= plan.daily) {
        return deny('install_quota_exhausted', { retryAfterSec: secsToNextDay(now), plan: plan.name, dailyLimit: plan.daily });
      }

      const inflight = this._rows("SELECT COUNT(*) AS n FROM reservations WHERE iid = ? AND state = 'held'", iid)[0].n;
      if (inflight >= cfg.maxInflight) return deny('too_many_concurrent', { retryAfterSec: 5 });

      // global budget: fail closed if anything about the numbers is wrong
      if (!(cfg.dailyBudget > 0) || !Number.isInteger(units) || units <= 0 || units > cfg.maxUnits) {
        return deny('budget_unverifiable');
      }
      const b = this._budgetRow(day, true);
      if (b.used >= cfg.dailyBudget) return deny('budget_exhausted', { retryAfterSec: secsToNextDay(now) });
      const soft = Math.floor(cfg.dailyBudget * plan.softPct);
      if (b.used + b.reserved + units > soft) return deny('budget_throttled', { retryAfterSec: secsToNextDay(now) });

      const id = crypto.randomUUID();
      this._run("INSERT INTO reservations(id, iid, day, units, created, state) VALUES(?, ?, ?, ?, ?, 'held')", id, iid, day, units, now);
      this._run('UPDATE budget SET reserved = reserved + ? WHERE day = ?', units, day);
      this._run(
        'INSERT INTO install_day(iid, day, count) VALUES(?, ?, 1) ON CONFLICT(iid, day) DO UPDATE SET count = count + 1',
        iid,
        day,
      );
      return { ok: true, reservationId: id, units, plan: plan.name, dailyLimit: plan.daily, remaining: plan.daily - (used + 1) };
    });
  }

  /**
   * Reserve budget for an internal caller (the staging evaluation): only the global budget is checked,
   * against softPct of the daily budget. Settle it with settle() like any other reservation.
   */
  reserveBudget({ iid, units, now, cfg, softPct }) {
    return this.tx(() => {
      const day = dayOf(now);
      this._expireStale(now, cfg.reservationTtlSec);
      if (!(cfg.dailyBudget > 0) || !Number.isInteger(units) || units <= 0 || units > cfg.maxUnits || !(softPct > 0 && softPct <= 1)) {
        return deny('budget_unverifiable');
      }
      const b = this._budgetRow(day, true);
      if (b.used >= cfg.dailyBudget) return deny('budget_exhausted', { retryAfterSec: secsToNextDay(now) });
      if (b.used + b.reserved + units > Math.floor(cfg.dailyBudget * softPct)) return deny('budget_throttled', { retryAfterSec: secsToNextDay(now) });
      const id = crypto.randomUUID();
      this._run("INSERT INTO reservations(id, iid, day, units, created, state) VALUES(?, ?, ?, ?, ?, 'held')", id, iid, day, units, now);
      this._run('UPDATE budget SET reserved = reserved + ? WHERE day = ?', units, day);
      return { ok: true, reservationId: id, units };
    });
  }

  /**
   * Finish a reservation.
   *  commit: the model ran; charge the ACTUAL units (clamped to maxUnits).
   *  release: the model did not run; give the budget and the request back.
   */
  settle({ reservationId, iid, action, actualUnits, now, cfg }) {
    return this.tx(() => {
      const r = this._rows('SELECT id, iid, day, units, state FROM reservations WHERE id = ? AND iid = ?', reservationId, iid)[0];
      if (!r) return deny('unknown_reservation');
      if (r.state !== 'held') return deny('already_settled', { state: r.state });
      if (action === 'commit') {
        const wanted = Number.isFinite(actualUnits) ? Math.round(actualUnits) : r.units;
        const actual = Math.min(Math.max(wanted, 0), cfg.maxUnits);
        this._run('UPDATE budget SET reserved = MAX(0, reserved - ?), used = used + ? WHERE day = ?', r.units, actual, r.day);
        this._run("UPDATE reservations SET state = 'committed' WHERE id = ?", r.id);
        return { ok: true, charged: actual };
      }
      if (action === 'release') {
        this._run('UPDATE budget SET reserved = MAX(0, reserved - ?) WHERE day = ?', r.units, r.day);
        this._run('UPDATE install_day SET count = MAX(0, count - 1) WHERE iid = ? AND day = ?', r.iid, r.day);
        this._run("UPDATE reservations SET state = 'released' WHERE id = ?", r.id);
        return { ok: true, charged: 0 };
      }
      return deny('invalid_action');
    });
  }

  /** What the app may know: its own usage, and only a coarse state for the shared budget. */
  status({ iid, ipHash, now, cfg }) {
    return this.tx(() => {
      const rate = this._ipRate(ipHash, now, cfg);
      if (rate) return rate;
      this._expireStale(now, cfg.reservationTtlSec);
      const day = dayOf(now);
      const plan = this._planFor(iid, now, cfg.plans);
      const used = (this._rows('SELECT count FROM install_day WHERE iid = ? AND day = ?', iid, day)[0] || { count: 0 }).count;
      const b = this._budgetRow(day, false);
      let global = 'ok';
      if (b.used >= cfg.dailyBudget) global = 'exhausted';
      else if (b.used + b.reserved >= Math.floor(cfg.dailyBudget * plan.softPct)) global = 'throttled';
      return {
        ok: true,
        plan: plan.name,
        dailyLimit: plan.daily,
        used,
        remaining: Math.max(0, plan.daily - used),
        resetsInSec: secsToNextDay(now),
        global,
      };
    });
  }

  /** Removes old rows. Called by a Durable Object alarm. */
  cleanup(now, cfg) {
    return this.tx(() => {
      const day = dayOf(now);
      this._expireStale(now, cfg.reservationTtlSec);
      this._run('DELETE FROM counters WHERE exp < ?', now);
      this._run('DELETE FROM seen_rid WHERE ts < ?', now - cfg.ridTtlSec * 1000);
      this._run('DELETE FROM install_day WHERE day < ?', day - 3);
      this._run('DELETE FROM budget WHERE day < ?', day - 30);
      this._run("DELETE FROM reservations WHERE state != 'held' AND created < ?", now - 3 * DAY_MS);
      this._run('DELETE FROM entitlements WHERE expires IS NOT NULL AND expires < ?', now);
      return { ok: true };
    });
  }
}
