// Test helpers: a real SQLite database (node:sqlite) behind the same interface the Durable Object uses.
import { DatabaseSync } from 'node:sqlite';
import { QuotaStore } from '../src/store.js';

export function makeSql() {
  const db = new DatabaseSync(':memory:');
  const sql = {
    exec(q, ...p) {
      const stmt = db.prepare(q);
      if (/^\s*select/i.test(q)) {
        const rows = stmt.all(...p);
        return { toArray: () => rows };
      }
      stmt.run(...p);
      return { toArray: () => [] };
    },
  };
  const tx = (fn) => {
    db.exec('BEGIN');
    try {
      const r = fn();
      db.exec('COMMIT');
      return r;
    } catch (e) {
      db.exec('ROLLBACK');
      throw e;
    }
  };
  return { db, sql, tx };
}

export function makeStore() {
  const { db, sql, tx } = makeSql();
  const store = new QuotaStore(sql, tx);
  store.init();
  return { store, db };
}

export const TOKEN_SECRET = 'test-token-secret-0123456789abcdef0123456789';
export const IP_SALT = 'test-ip-salt-0123456789abcdef0123456789abcdef';

/** A Worker environment whose QUOTA binding runs the real store, like the Durable Object does (one at a time). */
export function makeEnv(overrides = {}, hooks = {}) {
  const { store } = makeStore();
  let queue = Promise.resolve();
  const stub = new Proxy(
    {},
    {
      get: (_, method) => (arg) => {
        // a Durable Object runs one call at a time
        const run = queue.then(async () => {
          if (hooks.fail) throw new Error('simulated Durable Object failure');
          if (hooks.delayMs) await new Promise((r) => setTimeout(r, hooks.delayMs));
          return store[method](arg);
        });
        queue = run.catch(() => {});
        return run;
      },
    },
  );
  return {
    ENVIRONMENT: 'staging',
    TOKEN_SECRET,
    IP_SALT,
    QUOTA: { idFromName: (n) => n, get: () => stub },
    ...overrides,
    _store: store,
  };
}

export function req(path, { method = 'GET', body, headers = {}, rawBody, ip = '203.0.113.7' } = {}) {
  const h = new Headers({ 'cf-connecting-ip': ip, ...headers });
  let b;
  if (rawBody !== undefined) b = rawBody;
  else if (body !== undefined) {
    b = JSON.stringify(body);
    if (!h.has('content-type')) h.set('content-type', 'application/json');
  }
  return new Request(`https://nexus.test${path}`, { method, headers: h, body: b });
}

export const uuid4 = () => crypto.randomUUID();

export function signed(token, nowMs, extra = {}) {
  return {
    authorization: `Bearer ${token}`,
    'x-request-id': crypto.randomUUID(),
    'x-timestamp': String(Math.floor(nowMs / 1000)),
    ...extra,
  };
}
