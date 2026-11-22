// The Worker's request handling. It has no Cloudflare-only imports, so the tests run it directly in Node.
import { ApiError, errorResponse, json, ok, readJsonLimited } from './http.js';
import { ConfigError, loadConfig, storeConfig } from './config.js';
import { logEvent } from './log.js';
import { shortHash, signToken, verifyToken } from './token.js';
import { checkReplayHeaders, validateAsk, validateKeys, validateRegister } from './validate.js';

export const API_VERSION = '3A.1';

// ---------- helpers ----------

/** IPv6 addresses are cut to their /64 network, because one device can rotate through that whole range. */
export function normalizeIp(ip) {
  if (!ip) return 'unknown';
  const v = ip.trim().toLowerCase();
  if (!v.includes(':')) return v;
  const [head, tail] = v.split('::');
  const h = head ? head.split(':') : [];
  const t = tail === undefined ? [] : tail ? tail.split(':') : [];
  const zeros = tail === undefined ? 0 : Math.max(0, 8 - h.length - t.length);
  const groups = [...h, ...Array(zeros).fill('0'), ...t].slice(0, 8);
  return groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, '')).join(':') + '::/64';
}

async function ipHashOf(request, env) {
  return shortHash(env.IP_SALT, normalizeIp(request.headers.get('cf-connecting-ip')), 12);
}

function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout')), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/** Talks to the Durable Object. Any failure means "reject the request" (fail closed). */
async function callQuota(env, cfg, fn) {
  try {
    const stub = env.QUOTA.get(env.QUOTA.idFromName('global'));
    return await withTimeout(Promise.resolve().then(() => fn(stub)), cfg.doTimeoutMs);
  } catch (e) {
    logEvent({ evt: 'quota_unavailable', level: 'error', detail: String((e && e.message) || e) });
    throw new ApiError(503, 'service_unavailable', 'The AI service is busy right now. Nexus keeps working offline.', { retryAfterSec: 30 });
  }
}

const DENY = {
  ip_rate_limited: [429, 'rate_limited', 'Too many requests from this network. Please wait a moment.'],
  ip_daily_limit: [429, 'rate_limited', 'Too many requests from this network today.'],
  register_limited: [429, 'register_limited', 'Too many new installations from this network today.'],
  register_busy: [503, 'busy', 'The service is busy. Please try again later.'],
  replay: [409, 'replay_detected', 'This request was already received.'],
  install_quota_exhausted: [429, 'daily_limit_reached', 'You have used all of today\'s AI answers.'],
  too_many_concurrent: [429, 'too_many_concurrent', 'Please wait for your previous question to finish.'],
  budget_throttled: [503, 'ai_unavailable', 'AI answers are paused for today. Nexus keeps working offline.'],
  budget_exhausted: [503, 'ai_unavailable', 'AI answers are paused for today. Nexus keeps working offline.'],
  budget_unverifiable: [503, 'ai_unavailable', 'AI answers are unavailable right now. Nexus keeps working offline.'],
  unknown_reservation: [404, 'unknown_reservation', 'That reservation does not exist.'],
  already_settled: [409, 'already_settled', 'That reservation is already finished.'],
  invalid_action: [400, 'invalid_request', 'The action is not valid.'],
};

function denyToError(d) {
  const [status, code, message] = DENY[d.code] || [500, 'internal_error', 'Something went wrong on our side.'];
  const extra = {};
  if (Number.isFinite(d.retryAfterSec)) extra.retryAfterSec = d.retryAfterSec;
  return new ApiError(status, code, message, extra);
}

async function authenticate(request, env, nowSec) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer ([A-Za-z0-9_.-]+)$/.exec(h);
  if (!m) throw new ApiError(401, 'unauthorized', 'Register this installation first.');
  const payload = await verifyToken(env.TOKEN_SECRET, m[1], nowSec);
  if (!payload) throw new ApiError(401, 'unauthorized', 'Your session is not valid. Register again.');
  return { iid: payload.iid, iidh: await shortHash(env.TOKEN_SECRET, payload.iid, 4) };
}

// ---------- routes ----------

async function health(ctx) {
  const { cfg, nowSec, rid } = ctx;
  return ok(
    { service: 'nexus-api', apiVersion: API_VERSION, environment: cfg.environment, aiEnabled: cfg.aiEnabled, serverTime: nowSec },
    rid,
  );
}

async function register(ctx) {
  const { request, env, cfg, now, nowSec, rid } = ctx;
  const body = validateRegister(await readJsonLimited(request, cfg.maxBodyRegister));
  const ipHash = await ipHashOf(request, env);
  const gate = await callQuota(env, cfg, (q) => q.registerGate({ ipHash, now, cfg: storeConfig(cfg) }));
  if (!gate.ok) throw denyToError(gate);
  const exp = nowSec + Math.floor(cfg.tokenTtlDays * 86400);
  const token = await signToken(env.TOKEN_SECRET, { v: 1, iid: body.installId, iat: nowSec, exp });
  ctx.iidh = await shortHash(env.TOKEN_SECRET, body.installId, 4);
  return ok(
    { token, expiresAt: exp, plan: 'free', limits: { dailyPerInstall: cfg.plans.free.daily }, serverTime: nowSec },
    rid,
  );
}

async function quota(ctx) {
  const { request, env, cfg, now, nowSec, rid } = ctx;
  const auth = await authenticate(request, env, nowSec);
  ctx.iidh = auth.iidh;
  const ipHash = await ipHashOf(request, env);
  const s = await callQuota(env, cfg, (q) => q.status({ iid: auth.iid, ipHash, now, cfg: storeConfig(cfg) }));
  if (!s.ok) throw denyToError(s);
  const { ok: _ok, ...rest } = s;
  ctx.plan = s.plan;
  return ok({ ...rest, aiEnabled: cfg.aiEnabled, serverTime: nowSec }, rid);
}

async function ask(ctx) {
  const { request, env, cfg, now, nowSec } = ctx;
  const auth = await authenticate(request, env, nowSec);
  ctx.iidh = auth.iidh;
  checkReplayHeaders(request.headers, nowSec, cfg.tsSkewSec);
  validateAsk(await readJsonLimited(request, cfg.maxBodyAsk));
  const ipHash = await ipHashOf(request, env);
  // Phase 3A: no AI. The request is fully checked, but nothing is reserved or spent.
  const gate = await callQuota(env, cfg, (q) => q.ipGate({ ipHash, now, cfg: storeConfig(cfg) }));
  if (!gate.ok) throw denyToError(gate);
  if (!cfg.aiEnabled) {
    throw new ApiError(503, 'ai_disabled', 'AI answers are not available yet. Nexus keeps working offline.');
  }
  // AI_ENABLED=true before Phase 3B exists is a configuration mistake: refuse rather than guess.
  throw new ApiError(501, 'not_implemented', 'AI answers are not implemented in this version.');
}

function stagingOnly(cfg) {
  if (cfg.environment === 'production') throw new ApiError(404, 'not_found', 'Not found.');
}

/** Staging only: reserve budget without any AI, so quota, replay and concurrency can be tested for real. */
async function testReserve(ctx) {
  const { request, env, cfg, now, nowSec, rid } = ctx;
  stagingOnly(cfg);
  const auth = await authenticate(request, env, nowSec);
  ctx.iidh = auth.iidh;
  const { rid: clientRid } = checkReplayHeaders(request.headers, nowSec, cfg.tsSkewSec);
  const body = validateKeys(await readJsonLimited(request, cfg.maxBodyRegister), ['units']);
  const units = body.units === undefined ? cfg.reserveUnits : body.units;
  const ipHash = await ipHashOf(request, env);
  const r = await callQuota(env, cfg, (q) => q.admit({ iid: auth.iid, ipHash, rid: clientRid, now, units, cfg: storeConfig(cfg) }));
  if (!r.ok) throw denyToError(r);
  ctx.plan = r.plan;
  return ok({ reservationId: r.reservationId, units: r.units, remaining: r.remaining, dailyLimit: r.dailyLimit }, rid);
}

async function testSettle(ctx) {
  const { request, env, cfg, now, nowSec, rid } = ctx;
  stagingOnly(cfg);
  const auth = await authenticate(request, env, nowSec);
  ctx.iidh = auth.iidh;
  const body = validateKeys(await readJsonLimited(request, cfg.maxBodyRegister), ['reservationId', 'action', 'actualUnits']);
  if (typeof body.reservationId !== 'string' || body.reservationId.length > 64) {
    throw new ApiError(400, 'invalid_request', '"reservationId" is not valid.');
  }
  const r = await callQuota(env, cfg, (q) =>
    q.settle({ reservationId: body.reservationId, iid: auth.iid, action: body.action, actualUnits: body.actualUnits, now, cfg: storeConfig(cfg) }),
  );
  if (!r.ok) throw denyToError(r);
  return ok({ charged: r.charged }, rid);
}

const ROUTES = {
  '/v1/health': { GET: health },
  '/v1/register': { POST: register },
  '/v1/quota': { GET: quota },
  '/v1/ask': { POST: ask },
  '/v1/_test/reserve': { POST: testReserve },
  '/v1/_test/settle': { POST: testSettle },
};

// ---------- entry ----------

/**
 * @param {Request} request
 * @param {object} env Worker bindings, variables and secrets
 * @param {{ now?: () => number }} [opts] a clock, so tests can control time
 */
export async function handle(request, env, opts = {}) {
  const clock = opts.now || Date.now;
  const started = clock();
  const rid = crypto.randomUUID();
  const url = new URL(request.url);
  const path = url.pathname.length > 1 ? url.pathname.replace(/\/+$/, '') : url.pathname;
  const ctx = { request, env, rid, now: started, nowSec: Math.floor(started / 1000), cfg: null, iidh: undefined, plan: undefined };
  let status = 500;
  let code;
  try {
    try {
      ctx.cfg = loadConfig(env);
    } catch (e) {
      if (e instanceof ConfigError) {
        logEvent({ evt: 'config_error', level: 'error', detail: e.message, env: env.ENVIRONMENT });
        // Setup details are shown only outside production.
        const detail = env.ENVIRONMENT === 'production' || env.ENVIRONMENT === undefined ? undefined : e.message;
        return finish(errorResponse(new ApiError(500, 'server_misconfigured', detail ? `Server is not configured: ${detail}` : 'The service is not available.'), rid));
      }
      throw e;
    }
    const route = ROUTES[path];
    if (!route) throw new ApiError(404, 'not_found', 'Not found.');
    const fn = route[request.method];
    if (!fn) {
      const err = new ApiError(405, 'method_not_allowed', 'Method not allowed.');
      const res = errorResponse(err, rid);
      res.headers.set('Allow', Object.keys(route).join(', '));
      return finish(res);
    }
    return finish(await fn(ctx));
  } catch (e) {
    let err = e;
    if (!(e instanceof ApiError)) {
      logEvent({ evt: 'unhandled', level: 'error', detail: String((e && e.message) || e) });
      err = new ApiError(500, 'internal_error', 'Something went wrong on our side.');
    }
    return finish(errorResponse(err, rid));
  }

  function finish(res) {
    status = res.status;
    if (!res.ok) {
      // the error code is in the JSON body; keep the log free of body content
      code = res.headers.get('x-error-code') || undefined;
    }
    logEvent({
      evt: 'request',
      rid,
      route: ROUTES[path] ? path : 'unknown',
      method: request.method,
      status,
      ms: clock() - started,
      env: ctx.cfg ? ctx.cfg.environment : env.ENVIRONMENT,
      iidh: ctx.iidh,
      plan: ctx.plan,
      code,
    });
    return res;
  }
}

export { json };
