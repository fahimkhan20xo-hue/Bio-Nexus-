import { ApiError } from './http.js';

const UUID4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_ANY = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SCREEN = /^[A-Za-z0-9_.:-]{1,40}$/;
const LANGS = new Set(['en', 'bn', 'ja']);
// control characters except tab and newline
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;

function bad(msg) {
  return new ApiError(400, 'invalid_request', msg);
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function onlyKeys(obj, allowed, where) {
  for (const k of Object.keys(obj)) {
    if (!allowed.includes(k)) throw bad(`Unknown field "${k.slice(0, 30)}" in ${where}.`);
  }
}

function text(v, name, min, max) {
  if (typeof v !== 'string') throw bad(`"${name}" must be text.`);
  const clean = v.replace(CONTROL, '').trim();
  const len = [...clean].length; // count characters, not UTF-16 units (Bengali, emoji)
  if (len < min) throw bad(`"${name}" is too short.`);
  if (len > max) throw bad(`"${name}" is too long (max ${max} characters).`);
  return clean;
}

export function isUuid(v) {
  return typeof v === 'string' && UUID_ANY.test(v);
}

export function validateRegister(body) {
  if (!isPlainObject(body)) throw bad('The body must be a JSON object.');
  onlyKeys(body, ['installId', 'app'], 'the request');
  if (typeof body.installId !== 'string' || !UUID4.test(body.installId)) {
    throw bad('"installId" must be a random version-4 UUID.');
  }
  const out = { installId: body.installId.toLowerCase(), app: { version: '', build: 0 } };
  if (body.app !== undefined) {
    if (!isPlainObject(body.app)) throw bad('"app" must be an object.');
    onlyKeys(body.app, ['version', 'build'], '"app"');
    if (body.app.version !== undefined) out.app.version = text(body.app.version, 'app.version', 0, 24);
    if (body.app.build !== undefined) {
      if (!Number.isInteger(body.app.build) || body.app.build < 0 || body.app.build > 10_000_000) {
        throw bad('"app.build" must be a whole number.');
      }
      out.app.build = body.app.build;
    }
  }
  return out;
}

const SPECIES_FIELDS = {
  scientific: 80,
  common: 80,
  bangla: 80,
  kingdom: 60,
  phylum: 60,
  klass: 60,
  order: 60,
  family: 60,
  genus: 60,
  description: 400,
};

export function validateAsk(body) {
  if (!isPlainObject(body)) throw bad('The body must be a JSON object.');
  onlyKeys(body, ['question', 'lang', 'screen', 'species', 'history'], 'the request');
  const out = {
    question: text(body.question, 'question', 1, 600),
    lang: 'en',
    screen: '',
    species: null,
    history: [],
  };
  if (body.lang !== undefined) {
    if (!LANGS.has(body.lang)) throw bad('"lang" must be en, bn or ja.');
    out.lang = body.lang;
  }
  if (body.screen !== undefined) {
    if (typeof body.screen !== 'string' || !SCREEN.test(body.screen)) throw bad('"screen" is not valid.');
    out.screen = body.screen;
  }
  if (body.species !== undefined && body.species !== null) {
    if (!isPlainObject(body.species)) throw bad('"species" must be an object.');
    onlyKeys(body.species, Object.keys(SPECIES_FIELDS), '"species"');
    const s = {};
    for (const [k, max] of Object.entries(SPECIES_FIELDS)) {
      if (body.species[k] !== undefined) s[k] = text(body.species[k], `species.${k}`, 0, max);
    }
    out.species = s;
  }
  if (body.history !== undefined) {
    if (!Array.isArray(body.history) || body.history.length > 4) throw bad('"history" can hold at most 4 messages.');
    out.history = body.history.map((m, i) => {
      if (!isPlainObject(m)) throw bad(`history[${i}] must be an object.`);
      onlyKeys(m, ['role', 'text'], `history[${i}]`);
      if (m.role !== 'user' && m.role !== 'assistant') throw bad(`history[${i}].role must be user or assistant.`);
      return { role: m.role, text: text(m.text, `history[${i}].text`, 1, 400) };
    });
  }
  return out;
}

/** Staging-only test endpoints: allow only the listed keys. */
export function validateKeys(body, allowKeys) {
  if (!isPlainObject(body)) throw bad('The body must be a JSON object.');
  onlyKeys(body, allowKeys, 'the request');
  return body;
}

export function checkReplayHeaders(headers, nowSec, skewSec) {
  const rid = headers.get('x-request-id') || '';
  if (!UUID_ANY.test(rid)) throw new ApiError(400, 'invalid_request', 'X-Request-Id must be a UUID.');
  const tsRaw = headers.get('x-timestamp') || '';
  if (!/^\d{9,11}$/.test(tsRaw)) throw new ApiError(400, 'invalid_request', 'X-Timestamp must be Unix seconds.');
  const ts = Number(tsRaw);
  if (Math.abs(nowSec - ts) > skewSec) {
    throw new ApiError(400, 'clock_skew', 'Your device clock differs too much from the server. See /v1/health for the server time.');
  }
  return { rid: rid.toLowerCase(), ts };
}

/** Staging evaluation: one question for one model. */
export function validateEval(body) {
  if (!isPlainObject(body)) throw bad('The body must be a JSON object.');
  onlyKeys(body, ['model', 'question', 'lang'], 'the request');
  if (typeof body.model !== 'string' || body.model.length > 80) throw bad('"model" is not valid.');
  const out = { model: body.model, question: text(body.question, 'question', 1, 600), lang: 'en' };
  if (body.lang !== undefined) {
    if (!LANGS.has(body.lang)) throw bad('"lang" must be en, bn or ja.');
    out.lang = body.lang;
  }
  return out;
}
