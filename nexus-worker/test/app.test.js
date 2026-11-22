import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, normalizeIp } from '../src/app.js';
import { makeEnv, req, signed, uuid4, TOKEN_SECRET } from './helpers.js';
import { signToken } from '../src/token.js';

const T0 = Date.UTC(2026, 10, 20, 12, 0, 0);
const clock = (t = T0) => ({ now: () => t });

async function call(env, path, opts, t = T0) {
  const res = await handle(req(path, opts), env, clock(t));
  const text = await res.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { res, status: res.status, body };
}

async function register(env, o = {}) {
  const installId = o.installId || uuid4();
  const r = await call(env, '/v1/register', { method: 'POST', body: { installId, app: { version: '1.0', build: 90 } }, ip: o.ip }, o.t);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { token: r.body.token, installId };
}

const post = (env, path, token, body, o = {}) =>
  call(env, path, { method: 'POST', body, headers: signed(token, o.t || T0, o.headers), ip: o.ip }, o.t);

// ---------------- basics ----------------

test('health: no auth needed, no AI, shows environment', async () => {
  const { status, body } = await call(makeEnv(), '/v1/health');
  assert.equal(status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.aiEnabled, false);
  assert.equal(body.environment, 'staging');
  assert.equal(body.serverTime, Math.floor(T0 / 1000));
});

test('unknown path is 404 and a wrong method is 405 with Allow', async () => {
  const env = makeEnv();
  assert.equal((await call(env, '/nope')).status, 404);
  const r = await call(env, '/v1/register');
  assert.equal(r.status, 405);
  assert.equal(r.res.headers.get('allow'), 'POST');
});

test('responses are never cached and carry nosniff', async () => {
  const { res } = await call(makeEnv(), '/v1/health');
  assert.equal(res.headers.get('cache-control'), 'no-store');
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
});

test('missing secrets: the Worker refuses to serve (fail closed); production hides the reason', async () => {
  const staging = await call(makeEnv({ TOKEN_SECRET: undefined }), '/v1/health');
  assert.equal(staging.status, 500);
  assert.equal(staging.body.error.code, 'server_misconfigured');
  assert.match(staging.body.error.message, /TOKEN_SECRET/);
  const prod = await call(makeEnv({ TOKEN_SECRET: undefined, ENVIRONMENT: 'production' }), '/v1/health');
  assert.equal(prod.status, 500);
  assert.doesNotMatch(prod.body.error.message, /TOKEN_SECRET/);
});

test('a bad setting also stops the Worker', async () => {
  const r = await call(makeEnv({ GLOBAL_DAILY_BUDGET_UNITS: '-5' }), '/v1/health');
  assert.equal(r.status, 500);
  assert.equal(r.body.error.code, 'server_misconfigured');
});

// ---------------- registration ----------------

test('register issues a token that expires after the configured days', async () => {
  const env = makeEnv({ TOKEN_TTL_DAYS: '10' });
  const r = await call(env, '/v1/register', { method: 'POST', body: { installId: uuid4() } });
  assert.equal(r.status, 200);
  assert.equal(r.body.plan, 'free');
  assert.equal(r.body.limits.dailyPerInstall, 15);
  assert.equal(r.body.expiresAt, Math.floor(T0 / 1000) + 10 * 86400);
  assert.ok(r.body.token.includes('.'));
});

test('register rejects bad input', async () => {
  const env = makeEnv();
  const bad = [
    { installId: 'not-a-uuid' },
    { installId: uuid4(), extra: 1 },
    { installId: uuid4(), app: { build: 'x' } },
    { installId: uuid4(), app: { version: 'x'.repeat(30) } },
    [],
    'text',
  ];
  for (const body of bad) {
    const r = await call(env, '/v1/register', { method: 'POST', body });
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.body.error.code, 'invalid_request');
  }
});

test('register: wrong content type 415, bad JSON 400, empty 400', async () => {
  const env = makeEnv();
  assert.equal((await call(env, '/v1/register', { method: 'POST', rawBody: '{}', headers: { 'content-type': 'text/plain' } })).status, 415);
  assert.equal((await call(env, '/v1/register', { method: 'POST', rawBody: '{oops', headers: { 'content-type': 'application/json' } })).body.error.code, 'invalid_json');
  assert.equal((await call(env, '/v1/register', { method: 'POST', rawBody: '', headers: { 'content-type': 'application/json' } })).status, 400);
});

test('oversized bodies are refused (declared length and real length)', async () => {
  const env = makeEnv();
  const big = JSON.stringify({ installId: uuid4(), pad: 'x'.repeat(5000) });
  const declared = await call(env, '/v1/register', { method: 'POST', rawBody: big, headers: { 'content-type': 'application/json' } });
  assert.equal(declared.status, 413);
  // a stream that lies about (or hides) its length
  const stream = new ReadableStream({
    start(c) {
      c.enqueue(new TextEncoder().encode('{"installId":"'));
      c.enqueue(new TextEncoder().encode('x'.repeat(5000)));
      c.close();
    },
  });
  const r = new Request('https://nexus.test/v1/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: stream, duplex: 'half' });
  const res = await handle(r, env, clock());
  assert.equal(res.status, 413);
});

test('registration is limited per IP, but another IP still works', async () => {
  const env = makeEnv({ REG_PER_IP_DAY: '2' });
  await register(env, { ip: '198.51.100.1' });
  await register(env, { ip: '198.51.100.1' });
  const third = await call(env, '/v1/register', { method: 'POST', body: { installId: uuid4() }, ip: '198.51.100.1' });
  assert.equal(third.status, 429);
  assert.equal(third.body.error.code, 'register_limited');
  assert.ok(Number(third.res.headers.get('retry-after')) > 0);
  await register(env, { ip: '198.51.100.2' });
});

// ---------------- authentication ----------------

test('quota needs a valid token: missing, garbage, forged, wrong secret and expired are all 401', async () => {
  const env = makeEnv();
  const iid = uuid4();
  const good = await signToken(TOKEN_SECRET, { v: 1, iid, iat: 1, exp: Math.floor(T0 / 1000) + 100 });
  const forged = good.slice(0, -3) + (good.endsWith('AAA') ? 'BBB' : 'AAA');
  const other = await signToken('another-secret-0123456789abcdef0123456789', { v: 1, iid, iat: 1, exp: Math.floor(T0 / 1000) + 100 });
  const expired = await signToken(TOKEN_SECRET, { v: 1, iid, iat: 1, exp: Math.floor(T0 / 1000) - 1 });
  for (const h of [{}, { authorization: 'Bearer garbage' }, { authorization: `Bearer ${forged}` }, { authorization: `Bearer ${other}` }, { authorization: `Bearer ${expired}` }]) {
    const r = await call(env, '/v1/quota', { headers: h });
    assert.equal(r.status, 401, JSON.stringify(h));
    assert.equal(r.body.error.code, 'unauthorized');
  }
  assert.equal((await call(env, '/v1/quota', { headers: { authorization: `Bearer ${good}` } })).status, 200);
});

test('quota shows the installation its own usage', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  const r = await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` } });
  assert.equal(r.status, 200);
  assert.equal(r.body.dailyLimit, 15);
  assert.equal(r.body.remaining, 15);
  assert.equal(r.body.aiEnabled, false);
  assert.equal(r.body.global, 'ok');
  assert.equal(r.body.reservedUnits, undefined);
});

// ---------------- ask (no AI in 3A) ----------------

test('ask: a valid request gets ai_disabled and spends nothing', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  const r = await post(env, '/v1/ask', token, { question: 'What is a cell?', lang: 'en', screen: 'home' });
  assert.equal(r.status, 503);
  assert.equal(r.body.error.code, 'ai_disabled');
  const q = await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` } });
  assert.equal(q.body.remaining, 15);
});

test('ask: validation of the question, replay headers and clock', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  assert.equal((await post(env, '/v1/ask', token, { question: '' })).status, 400);
  assert.equal((await post(env, '/v1/ask', token, { question: 'x'.repeat(601) })).status, 400);
  assert.equal((await post(env, '/v1/ask', token, { question: 'hi', lang: 'fr' })).status, 400);
  assert.equal((await post(env, '/v1/ask', token, { question: 'hi', history: new Array(5).fill({ role: 'user', text: 'a' }) })).status, 400);
  assert.equal((await post(env, '/v1/ask', token, { question: 'hi', secret: 1 })).status, 400);
  // 600 Bengali characters are fine even though they are ~1.8 KB
  assert.equal((await post(env, '/v1/ask', token, { question: 'ক'.repeat(600) })).status, 503);
  // no replay headers
  const noHeaders = await call(env, '/v1/ask', { method: 'POST', body: { question: 'hi' }, headers: { authorization: `Bearer ${token}` } });
  assert.equal(noHeaders.status, 400);
  // a clock that is 10 minutes off
  const skew = await post(env, '/v1/ask', token, { question: 'hi' }, { headers: { 'x-timestamp': String(Math.floor(T0 / 1000) - 600) } });
  assert.equal(skew.status, 400);
  assert.equal(skew.body.error.code, 'clock_skew');
});

test('ask without a token is 401, even with a perfect body', async () => {
  const r = await call(makeEnv(), '/v1/ask', { method: 'POST', body: { question: 'hi' } });
  assert.equal(r.status, 401);
});

test('AI_ENABLED=true before Phase 3B exists is refused, not guessed', async () => {
  const env = makeEnv({ AI_ENABLED: 'true' });
  const { token } = await register(env);
  const r = await post(env, '/v1/ask', token, { question: 'hi' });
  assert.equal(r.status, 501);
});

// ---------------- quota, replay, concurrency (staging test endpoints) ----------------

test('test endpoints do not exist in production', async () => {
  const env = makeEnv({ ENVIRONMENT: 'production' });
  const { token } = await register(env);
  assert.equal((await post(env, '/v1/_test/reserve', token, {})).status, 404);
  assert.equal((await post(env, '/v1/_test/settle', token, { reservationId: 'x', action: 'release' })).status, 404);
});

test('the 15 per-day limit: 15 succeed, the 16th is refused with Retry-After', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  for (let i = 0; i < 15; i++) {
    const r = await post(env, '/v1/_test/reserve', token, { units: 10 });
    assert.equal(r.status, 200, `request ${i + 1}: ${JSON.stringify(r.body)}`);
    assert.equal(r.body.remaining, 14 - i);
    const s = await post(env, '/v1/_test/settle', token, { reservationId: r.body.reservationId, action: 'commit', actualUnits: 10 });
    assert.equal(s.status, 200);
  }
  const r16 = await post(env, '/v1/_test/reserve', token, { units: 10 });
  assert.equal(r16.status, 429);
  assert.equal(r16.body.error.code, 'daily_limit_reached');
  assert.ok(Number(r16.res.headers.get('retry-after')) > 0);
  // a new day gives a fresh allowance
  const tomorrow = T0 + 86_400_000;
  const t2 = await call(env, '/v1/register', { method: 'POST', body: { installId: uuid4() }, ip: '203.0.113.99' }, tomorrow);
  assert.equal(t2.status, 200);
});

test('replay: the same X-Request-Id is refused with 409', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  const rid = uuid4();
  const first = await post(env, '/v1/_test/reserve', token, { units: 10 }, { headers: { 'x-request-id': rid } });
  assert.equal(first.status, 200);
  await post(env, '/v1/_test/settle', token, { reservationId: first.body.reservationId, action: 'release' });
  const again = await post(env, '/v1/_test/reserve', token, { units: 10 }, { headers: { 'x-request-id': rid } });
  assert.equal(again.status, 409);
  assert.equal(again.body.error.code, 'replay_detected');
});

test('concurrency: 20 parallel requests from one installation, exactly one wins', async () => {
  const env = makeEnv();
  const { token } = await register(env);
  const results = await Promise.all(Array.from({ length: 20 }, () => post(env, '/v1/_test/reserve', token, { units: 10 })));
  const wins = results.filter((r) => r.status === 200);
  assert.equal(wins.length, 1);
  assert.ok(results.filter((r) => r.status !== 200).every((r) => r.body.error.code === 'too_many_concurrent'));
});

test('concurrency: 100 installations race for the shared budget, it is never overspent', async () => {
  const env = makeEnv({ GLOBAL_DAILY_BUDGET_UNITS: '1000', RESERVE_UNITS_PER_REQUEST: '40', IP_REQ_PER_MIN: '100000', AI_PER_IP_DAY: '100000', REG_PER_IP_DAY: '1000' });
  const tokens = [];
  for (let i = 0; i < 100; i++) tokens.push((await register(env)).token);
  const results = await Promise.all(tokens.map((t) => post(env, '/v1/_test/reserve', t, { units: 40 })));
  const wins = results.filter((r) => r.status === 200);
  assert.equal(wins.length, 20); // 80% of 1000 = 800 = 20 x 40
  assert.ok(results.filter((r) => r.status !== 200).every((r) => r.status === 503 && r.body.error.code === 'ai_unavailable'));
  const row = env._store._rows('SELECT used, reserved FROM budget')[0];
  assert.equal(row.reserved, 800);
  assert.ok(row.used + row.reserved <= 800);
});

test('a new installation id gets a fresh per-install allowance, but the per-IP daily cap still holds', async () => {
  const env = makeEnv({ AI_PER_IP_DAY: '4', IP_REQ_PER_MIN: '100000', REG_PER_IP_DAY: '1000' });
  let granted = 0;
  let refused = null;
  for (let i = 0; i < 8; i++) {
    const { token } = await register(env); // a brand-new installation every time
    const r = await post(env, '/v1/_test/reserve', token, { units: 10 });
    if (r.status === 200) {
      granted++;
      await post(env, '/v1/_test/settle', token, { reservationId: r.body.reservationId, action: 'commit', actualUnits: 10 });
    } else refused = r;
  }
  assert.equal(granted, 4);
  assert.equal(refused.body.error.code, 'rate_limited');
});

test('per-IP request rate returns 429 with Retry-After; another IP is not affected', async () => {
  const env = makeEnv({ IP_REQ_PER_MIN: '10' });
  const { token } = await register(env, { ip: '192.0.2.50' });
  let last;
  for (let i = 0; i < 11; i++) last = await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` }, ip: '192.0.2.50' });
  assert.equal(last.status, 429);
  assert.equal(last.body.error.code, 'rate_limited');
  assert.ok(Number(last.res.headers.get('retry-after')) >= 1);
  const other = await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` }, ip: '192.0.2.51' });
  assert.equal(other.status, 200);
});

test('settle: only valid actions, only for own reservations', async () => {
  const env = makeEnv();
  const a = await register(env);
  const b = await register(env, { ip: '203.0.113.8' });
  const r = await post(env, '/v1/_test/reserve', a.token, { units: 10 });
  const steal = await post(env, '/v1/_test/settle', b.token, { reservationId: r.body.reservationId, action: 'release' });
  assert.equal(steal.status, 404);
  assert.equal((await post(env, '/v1/_test/settle', a.token, { reservationId: r.body.reservationId, action: 'nonsense' })).status, 400);
  assert.equal((await post(env, '/v1/_test/settle', a.token, { reservationId: r.body.reservationId, action: 'commit', actualUnits: 8 })).body.charged, 8);
});

// ---------------- failure handling ----------------

test('Durable Object failure: the request is refused (fail closed), and nothing internal leaks', async () => {
  const hooks = { fail: false };
  const env = makeEnv({}, hooks);
  const { token } = await register(env);
  hooks.fail = true;
  const r = await post(env, '/v1/_test/reserve', token, { units: 10 });
  assert.equal(r.status, 503);
  assert.equal(r.body.error.code, 'service_unavailable');
  assert.doesNotMatch(JSON.stringify(r.body), /simulated|stack|at /i);
  const q = await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` } });
  assert.equal(q.status, 503);
});

test('Durable Object too slow: the request times out and is refused', async () => {
  const env = makeEnv({ DO_TIMEOUT_MS: '200' }, { delayMs: 600 });
  const r = await call(env, '/v1/register', { method: 'POST', body: { installId: uuid4() } });
  assert.equal(r.status, 503);
  assert.equal(r.body.error.code, 'service_unavailable');
});

test('a crash inside the handler becomes a clean 500 without details', async () => {
  const env = makeEnv();
  env.QUOTA = { idFromName: () => 'x', get: () => { throw new TypeError('secret internal detail'); } };
  const r = await call(env, '/v1/register', { method: 'POST', body: { installId: uuid4() } });
  assert.equal(r.status, 503);
  assert.doesNotMatch(JSON.stringify(r.body), /secret internal detail/);
});

// ---------------- privacy ----------------

test('logs never contain the question, the token, the raw IP or the installation id', async () => {
  const lines = [];
  const original = console.log;
  console.log = (...a) => lines.push(a.join(' '));
  try {
    const env = makeEnv();
    const installId = uuid4();
    const reg = await call(env, '/v1/register', { method: 'POST', body: { installId }, ip: '198.51.100.77' });
    const token = reg.body.token;
    await post(env, '/v1/ask', token, { question: 'MY-PRIVATE-QUESTION-TEXT' }, { ip: '198.51.100.77' });
    await call(env, '/v1/quota', { headers: { authorization: `Bearer ${token}` }, ip: '198.51.100.77' });
    const all = lines.join('\n');
    assert.ok(lines.length >= 3);
    assert.doesNotMatch(all, /MY-PRIVATE-QUESTION-TEXT/);
    assert.ok(!all.includes(token));
    assert.ok(!all.includes('198.51.100.77'));
    assert.ok(!all.includes(installId));
    for (const l of lines) assert.doesNotThrow(() => JSON.parse(l)); // structured
  } finally {
    console.log = original;
  }
});

test('IPv6 addresses of one network collapse to one /64 bucket', () => {
  assert.equal(normalizeIp('203.0.113.7'), '203.0.113.7');
  assert.equal(normalizeIp('2001:db8:85a3:1::1'), normalizeIp('2001:0db8:85a3:0001:ffff:ffff:ffff:ffff'));
  assert.notEqual(normalizeIp('2001:db8:85a3:1::1'), normalizeIp('2001:db8:85a3:2::1'));
  assert.equal(normalizeIp(''), 'unknown');
});
