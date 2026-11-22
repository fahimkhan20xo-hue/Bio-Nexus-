// The Durable Object (SQLite-backed). The Worker talks to it through RPC methods.
// This file imports "cloudflare:workers", so it is not loaded by the Node tests; the logic lives in store.js.
import { DurableObject } from 'cloudflare:workers';
import { QuotaStore } from './store.js';

const CLEANUP_EVERY_MS = 6 * 3600 * 1000;

export class QuotaDO extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.store = new QuotaStore(ctx.storage.sql, (fn) => ctx.storage.transactionSync(fn));
    ctx.blockConcurrencyWhile(async () => {
      this.store.init();
      if ((await ctx.storage.getAlarm()) === null) await ctx.storage.setAlarm(Date.now() + CLEANUP_EVERY_MS);
    });
  }

  async registerGate(p) {
    return this.store.registerGate(p);
  }

  async ipGate(p) {
    return this.store.ipGate(p);
  }

  async admit(p) {
    return this.store.admit(p);
  }

  async settle(p) {
    return this.store.settle(p);
  }

  async status(p) {
    return this.store.status(p);
  }

  async alarm() {
    // plain data only: the limits are re-read from the env on every request, cleanup needs just a few
    this.store.cleanup(Date.now(), { reservationTtlSec: 90, ridTtlSec: 900 });
    await this.ctx.storage.setAlarm(Date.now() + CLEANUP_EVERY_MS);
  }
}
