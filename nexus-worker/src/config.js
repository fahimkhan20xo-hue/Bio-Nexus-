// Reads settings from the Worker's environment (wrangler.toml [vars] and secrets).
// Anything missing or out of range stops the Worker from serving (fail closed).

import { DEFAULT_EVAL_MODELS, MODEL_RATES } from './models.js';

export class ConfigError extends Error {}

const ENVIRONMENTS = new Set(['production', 'staging', 'development']);

function num(env, name, def, min, max) {
  const raw = env[name];
  if (raw === undefined || raw === '') return def;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < min || n > max) throw new ConfigError(`${name} is out of range`);
  return n;
}

function plan(env, prefix, defDaily, defSoft) {
  return {
    daily: Math.floor(num(env, `${prefix}_DAILY_PER_INSTALL`, defDaily, 1, 10000)),
    softPct: num(env, `${prefix}_SOFT_PCT`, defSoft, 0.05, 1),
  };
}

export function loadConfig(env) {
  const environment = env.ENVIRONMENT === undefined ? 'production' : env.ENVIRONMENT;
  if (!ENVIRONMENTS.has(environment)) throw new ConfigError('ENVIRONMENT is not valid');
  for (const secret of ['TOKEN_SECRET', 'IP_SALT']) {
    if (typeof env[secret] !== 'string' || env[secret].length < 32) {
      throw new ConfigError(`${secret} is missing or too short`);
    }
  }
  if (!env.QUOTA || typeof env.QUOTA.idFromName !== 'function') throw new ConfigError('QUOTA binding is missing');

  const reserveUnits = Math.floor(num(env, 'RESERVE_UNITS_PER_REQUEST', 40, 1, 100000));
  const maxUnits = Math.floor(num(env, 'MAX_UNITS_PER_REQUEST', 120, 1, 100000));
  if (reserveUnits > maxUnits) throw new ConfigError('RESERVE_UNITS_PER_REQUEST is above MAX_UNITS_PER_REQUEST');
  if (Math.floor(num(env, 'UNCERTAIN_CHARGE_UNITS', 80, 1, 100000)) > maxUnits) throw new ConfigError('UNCERTAIN_CHARGE_UNITS is above MAX_UNITS_PER_REQUEST');

  return {
    environment,
    aiEnabled: env.AI_ENABLED === 'true', // stays false in Phase 3A
    tokenTtlDays: num(env, 'TOKEN_TTL_DAYS', 30, 1, 365),
    tsSkewSec: num(env, 'TS_SKEW_SEC', 300, 30, 3600),
    maxBodyRegister: num(env, 'MAX_BODY_BYTES_REGISTER', 1024, 256, 8192),
    maxBodyAsk: num(env, 'MAX_BODY_BYTES_ASK', 16384, 1024, 65536),
    // Per-IP limits are deliberately generous: many phone users share one IP (carrier NAT).
    ipReqPerMin: num(env, 'IP_REQ_PER_MIN', 120, 10, 100000),
    regPerIpDay: num(env, 'REG_PER_IP_DAY', 40, 1, 100000),
    regGlobalPerDay: num(env, 'REG_GLOBAL_PER_DAY', 5000, 10, 10000000),
    aiPerIpDay: num(env, 'AI_PER_IP_DAY', 300, 1, 1000000),
    dailyBudget: Math.floor(num(env, 'GLOBAL_DAILY_BUDGET_UNITS', 9000, 1, 100000000)),
    reserveUnits,
    maxUnits,
    reservationTtlSec: num(env, 'RESERVATION_TTL_SEC', 90, 10, 900),
    maxInflight: Math.floor(num(env, 'MAX_INFLIGHT_PER_INSTALL', 1, 1, 10)),
    ridTtlSec: num(env, 'RID_TTL_SEC', 900, 60, 86400),
    doTimeoutMs: num(env, 'DO_TIMEOUT_MS', 3000, 200, 15000),
    // AI (used by the staging evaluation route today, by /v1/ask in Phase 3B)
    aiTimeoutMs: num(env, 'AI_TIMEOUT_MS', 25000, 2000, 60000),
    maxAnswerTokens: Math.floor(num(env, 'MAX_ANSWER_TOKENS', 450, 50, 2000)),
    evalBudgetPct: num(env, 'EVAL_BUDGET_PCT', 0.5, 0.05, 1),
    // What a call that timed out or failed halfway is charged: it may still have run and been billed.
    uncertainChargeUnits: Math.floor(num(env, 'UNCERTAIN_CHARGE_UNITS', 80, 1, 100000)),
    evalModels: evalModels(env),
    // Only "free" can be issued today. The others are prepared for future server-side verified plans.
    plans: {
      free: plan(env, 'FREE', 15, 0.8),
      premium: plan(env, 'PREMIUM', 60, 0.9),
      institution: plan(env, 'INSTITUTION', 200, 0.95),
    },
  };
}

function evalModels(env) {
  const raw = env.EVAL_MODELS;
  const list = raw === undefined || raw === '' ? DEFAULT_EVAL_MODELS : String(raw).split(',').map((m) => m.trim()).filter(Boolean);
  for (const m of list) {
    // never call a model whose price we do not know: its cost could not be budgeted
    if (!Object.prototype.hasOwnProperty.call(MODEL_RATES, m)) throw new ConfigError(`EVAL_MODELS has a model without a known price: ${m.slice(0, 60)}`);
  }
  if (list.length === 0 || list.length > 6) throw new ConfigError('EVAL_MODELS must list 1 to 6 models');
  return list;
}

/** The part of the config the quota store needs (plain data, safe to send to the Durable Object). */
export function storeConfig(cfg) {
  return {
    ipReqPerMin: cfg.ipReqPerMin,
    regPerIpDay: cfg.regPerIpDay,
    regGlobalPerDay: cfg.regGlobalPerDay,
    aiPerIpDay: cfg.aiPerIpDay,
    dailyBudget: cfg.dailyBudget,
    maxUnits: cfg.maxUnits,
    reservationTtlSec: cfg.reservationTtlSec,
    maxInflight: cfg.maxInflight,
    ridTtlSec: cfg.ridTtlSec,
    plans: cfg.plans,
  };
}
