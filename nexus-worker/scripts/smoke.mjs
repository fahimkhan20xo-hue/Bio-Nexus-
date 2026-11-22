// Contract test against a RUNNING Nexus API (the deployed Worker in CI, or the local server).
//   node scripts/smoke.mjs <baseUrl> <staging|production>
// Exit code 1 if anything is wrong, with a clear list of what failed.
const [base, mode = 'staging'] = process.argv.slice(2);
if (!base) {
  console.error('usage: node scripts/smoke.mjs <baseUrl> <staging|production>');
  process.exit(2);
}
const url = (p) => base.replace(/\/+$/, '') + p;
const results = [];
function check(name, cond, detail = '') {
  results.push({ name, ok: !!cond, detail });
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${cond ? '' : '  ' + detail}`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function call(path, { method = 'GET', body, headers = {}, raw, contentType } = {}) {
  const h = { ...headers };
  let b = raw;
  if (body !== undefined) {
    b = JSON.stringify(body);
    h['content-type'] = 'application/json';
  }
  if (contentType) h['content-type'] = contentType;
  const res = await fetch(url(path), { method, headers: h, body: b });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // not JSON
  }
  return { status: res.status, json, headers: res.headers, text };
}

const signed = (token) => ({
  authorization: `Bearer ${token}`,
  'x-request-id': crypto.randomUUID(),
  'x-timestamp': String(Math.floor(Date.now() / 1000)),
});

// 1. health (a fresh deployment may need a few seconds to be reachable)
let health = null;
for (let i = 0; i < 12; i++) {
  try {
    health = await call('/v1/health');
    if (health.status === 200) break;
  } catch {
    // not reachable yet
  }
  await sleep(4000);
}
check('health answers 200', health && health.status === 200, health ? `${health.status} ${health.text.slice(0, 200)}` : 'no answer');
if (!health || health.status !== 200) {
  console.log('\nThe Worker is not healthy. If it says server_misconfigured, the secrets are missing: run the workflow action "recreate-secrets-<env>".');
  process.exit(1);
}
check('health says ok:true and the right environment', health.json.ok === true && health.json.environment === mode, JSON.stringify(health.json));
check('AI is disabled in Phase 3A', health.json.aiEnabled === false);

// 2. registration
const installId = crypto.randomUUID();
const reg = await call('/v1/register', { method: 'POST', body: { installId, app: { version: 'smoke', build: 0 } } });
check('register returns a token', reg.status === 200 && typeof reg.json?.token === 'string', `${reg.status} ${reg.text.slice(0, 200)}`);
const token = reg.json?.token;
check('free plan allows 15 per day', reg.json?.limits?.dailyPerInstall === 15);

// 3. quota
const q = await call('/v1/quota', { headers: { authorization: `Bearer ${token}` } });
check('quota shows 15 remaining', q.status === 200 && q.json?.remaining === 15, q.text.slice(0, 200));
check('quota shows only a coarse global state, no budget numbers', q.json && ['ok', 'throttled', 'exhausted'].includes(q.json.global) && !JSON.stringify(q.json).match(/budget|reserved/i));

// 4. ask: validated, but no AI yet
const ask = await call('/v1/ask', { method: 'POST', body: { question: 'What is a cell?', lang: 'en' }, headers: signed(token) });
check('ask answers 503 ai_disabled', ask.status === 503 && ask.json?.error?.code === 'ai_disabled', `${ask.status} ${ask.text.slice(0, 200)}`);

// 5. things that must be refused
check('no token is 401', (await call('/v1/quota')).status === 401);
check('forged token is 401', (await call('/v1/quota', { headers: { authorization: 'Bearer abc.def' } })).status === 401);
check('bad installId is 400', (await call('/v1/register', { method: 'POST', body: { installId: 'nope' } })).status === 400);
check('unknown field is 400', (await call('/v1/register', { method: 'POST', body: { installId: crypto.randomUUID(), x: 1 } })).status === 400);
check('wrong content type is 415', (await call('/v1/register', { method: 'POST', raw: '{}', contentType: 'text/plain' })).status === 415);
check('oversized body is 413', (await call('/v1/register', { method: 'POST', body: { installId: crypto.randomUUID(), pad: 'x'.repeat(5000) } })).status === 413);
check('unknown route is 404', (await call('/v1/nothing')).status === 404);
check('wrong method is 405', (await call('/v1/register')).status === 405);
const noHdr = await call('/v1/ask', { method: 'POST', body: { question: 'hi' }, headers: { authorization: `Bearer ${token}` } });
check('ask without replay headers is 400', noHdr.status === 400);

// 6. staging only: the real quota machinery, without AI
if (mode === 'staging') {
  const rid = crypto.randomUUID();
  const h = { ...signed(token), 'x-request-id': rid };
  const r1 = await call('/v1/_test/reserve', { method: 'POST', body: { units: 10 }, headers: h });
  check('test reserve works', r1.status === 200 && r1.json?.reservationId, `${r1.status} ${r1.text.slice(0, 200)}`);
  const r2 = await call('/v1/_test/reserve', { method: 'POST', body: { units: 10 }, headers: { ...signed(token), 'x-request-id': rid } });
  check('replayed request id is 409', r2.status === 409, `${r2.status}`);
  const r3 = await call('/v1/_test/reserve', { method: 'POST', body: { units: 10 }, headers: signed(token) });
  check('second request in flight is 429', r3.status === 429, `${r3.status}`);
  const s = await call('/v1/_test/settle', { method: 'POST', body: { reservationId: r1.json?.reservationId, action: 'release' }, headers: { authorization: `Bearer ${token}` } });
  check('release works', s.status === 200, `${s.status}`);
  const q2 = await call('/v1/quota', { headers: { authorization: `Bearer ${token}` } });
  check('released request is given back', q2.json?.remaining === 15, q2.text.slice(0, 200));
} else {
  const t = await call('/v1/_test/reserve', { method: 'POST', body: {}, headers: signed(token) });
  check('test endpoints do not exist in production', t.status === 404, `${t.status}`);
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
