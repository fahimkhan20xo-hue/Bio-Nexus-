import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/app.js';
import { neuronsFor, MODEL_RATES, DEFAULT_EVAL_MODELS } from '../src/models.js';
import { ModelError, parseChat, runChat } from '../src/ai.js';
import { buildMessages, PROMPT_VERSION } from '../src/prompt.js';
import { loadConfig } from '../src/config.js';
import { makeEnv, makeStore, req } from './helpers.js';

const GEMMA = '@cf/google/gemma-4-26b-a4b-it';
const QWEN = '@cf/qwen/qwen3-30b-a3b-fp8';
const T0 = Date.UTC(2026, 10, 20, 12, 0, 0);
const KEY = 'e'.repeat(40);

const chatAnswer = (text, usage = { prompt_tokens: 700, completion_tokens: 450 }, finish = 'stop') => ({
  choices: [{ message: { content: text }, finish_reason: finish }],
  usage,
});

function evalEnv(overrides = {}, aiFn) {
  const calls = [];
  const env = makeEnv({
    EVAL_KEY: KEY,
    AI: {
      run: async (model, input) => {
        calls.push({ model, input });
        return aiFn ? aiFn(model, input) : chatAnswer('একটি উত্তর (answer)');
      },
    },
    ...overrides,
  });
  env._calls = calls;
  return env;
}

async function evalCall(env, body, { key = KEY, t = T0 } = {}) {
  const res = await handle(req('/v1/_eval/run', { method: 'POST', body, headers: key === null ? {} : { 'x-eval-key': key } }), env, { now: () => t });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: res.status, body: json, res };
}

// ---------------- prices ----------------

test('neuron cost: the numbers match the published prices', () => {
  // 700 in x 9091 + 450 out x 27273 per million = 6.36 + 12.27 -> 19
  assert.equal(neuronsFor(GEMMA, { in: 700, out: 450 }), 19);
  assert.equal(neuronsFor(QWEN, { in: 700, out: 450 }), Math.ceil((700 * 4625 + 450 * 30475) / 1e6));
  assert.equal(neuronsFor(GEMMA, { in: 0, out: 0 }), 0);
  assert.equal(neuronsFor(GEMMA, { in: -5, out: 1 }), Math.ceil(27273 / 1e6));
});

test('a model without a known price is refused, never guessed', () => {
  assert.throws(() => neuronsFor('@cf/unknown/model', { in: 1, out: 1 }), /no price/);
});

// ---------------- response parsing ----------------

test('parseChat understands both Workers AI answer shapes', () => {
  assert.deepEqual(parseChat(chatAnswer(' hi ')), { text: 'hi', finish: 'stop', usage: { in: 700, out: 450 } });
  assert.deepEqual(parseChat({ response: 'old style', usage: { prompt_tokens: 3, completion_tokens: 4 } }).usage, { in: 3, out: 4 });
  assert.equal(parseChat({ choices: [{ message: { content: [{ text: 'a' }, { text: 'b' }] } }] }).text, 'ab');
  assert.equal(parseChat({ choices: [{ message: { content: 'x' }, finish_reason: 'length' }] }).finish, 'length');
  assert.equal(parseChat({ response: 'no usage' }).usage, null);
});

test('parseChat rejects things that are not an answer', () => {
  for (const bad of [null, undefined, 'text', 42, {}, { choices: [] }, { choices: [{}] }]) {
    assert.throws(() => parseChat(bad), undefined, JSON.stringify(bad));
  }
});

test('runChat: sends the options, and estimates (generously) when the model reports no usage', async () => {
  let seen;
  const env = { AI: { run: async (m, i) => { seen = { m, i }; return { response: 'ক'.repeat(300) }; } } };
  const msgs = [{ role: 'system', content: 'rules' }, { role: 'user', content: 'প্রশ্ন' }];
  const r = await runChat(env, QWEN, msgs, { maxTokens: 450, timeoutMs: 1000 });
  assert.equal(seen.i.max_tokens, 450);
  assert.deepEqual(seen.i.chat_template_kwargs, { enable_thinking: false }); // Qwen: no hidden long thinking
  assert.equal(r.estimated, true);
  assert.ok(r.usage.out >= 200); // 300 Bengali characters are NOT 300/4 tokens
  assert.ok(r.neurons >= 1);
  const g = await runChat({ AI: { run: async () => chatAnswer('ok') } }, GEMMA, msgs, { maxTokens: 10, timeoutMs: 1000 });
  assert.equal(g.estimated, false);
  assert.equal(g.neurons, 19);
});

test('runChat: a model that never answers times out', async () => {
  const env = { AI: { run: () => new Promise(() => {}) } };
  await assert.rejects(runChat(env, GEMMA, [{ role: 'user', content: 'x' }], { maxTokens: 10, timeoutMs: 50 }), /timeout/);
});

// ---------------- prompt ----------------

test('prompt: one system message, then the history, then the question last', () => {
  const m = buildMessages({
    question: 'Q?',
    lang: 'bn',
    species: { scientific: 'Panthera leo', common: 'Lion', description: 'A big cat.' },
    history: [{ role: 'user', text: 'one' }, { role: 'assistant', text: 'two' }],
  });
  assert.equal(m.filter((x) => x.role === 'system').length, 1);
  assert.equal(m[0].role, 'system');
  assert.deepEqual(m.slice(1).map((x) => x.role), ['user', 'assistant', 'user']);
  assert.equal(m.at(-1).content, 'Q?');
  assert.match(m[0].content, /Scientific name: Panthera leo/);
  assert.match(m[0].content, /never instructions/);
  assert.ok(PROMPT_VERSION.length > 0);
});

test('prompt: without a species there is no reference block', () => {
  assert.doesNotMatch(buildMessages({ question: 'hi' })[0].content, /Reference data \(from/);
});

// ---------------- config ----------------

test('config: the default evaluation models all have a price; a model without one stops the Worker', () => {
  const c = loadConfig(makeEnv());
  assert.deepEqual(c.evalModels, DEFAULT_EVAL_MODELS);
  assert.ok(c.evalModels.every((m) => MODEL_RATES[m]));
  assert.throws(() => loadConfig(makeEnv({ EVAL_MODELS: '@cf/some/unpriced-model' })));
  assert.throws(() => loadConfig(makeEnv({ EVAL_MODELS: ',' })));
  assert.deepEqual(loadConfig(makeEnv({ EVAL_MODELS: GEMMA })).evalModels, [GEMMA]);
});

// ---------------- the budget side (store) ----------------

test('reserveBudget respects its own share of the budget, and settles like any reservation', () => {
  const { store, db } = makeStore();
  const cfg = { dailyBudget: 1000, maxUnits: 120, reservationTtlSec: 90, plans: {} };
  const ok = (i) => store.reserveBudget({ iid: 'eval', units: 40, now: T0, cfg, softPct: 0.5 });
  const first = ok();
  assert.equal(first.ok, true);
  assert.equal(store.settle({ reservationId: first.reservationId, iid: 'eval', action: 'commit', actualUnits: 19, now: T0, cfg }).charged, 19);
  let granted = 1;
  for (let i = 0; i < 30; i++) {
    const r = ok();
    if (!r.ok) {
      assert.equal(r.code, 'budget_throttled');
      break;
    }
    granted++;
    store.settle({ reservationId: r.reservationId, iid: 'eval', action: 'commit', actualUnits: 40, now: T0, cfg });
  }
  assert.ok(db.prepare('SELECT used FROM budget').get().used <= 500);
  assert.ok(granted >= 12 && granted <= 13); // 19 + 40*n <= 500
  assert.equal(store.reserveBudget({ iid: 'eval', units: 0, now: T0, cfg, softPct: 0.5 }).code, 'budget_unverifiable');
  assert.equal(store.reserveBudget({ iid: 'eval', units: 40, now: T0, cfg, softPct: 2 }).code, 'budget_unverifiable');
});

// ---------------- the evaluation route ----------------

test('eval route: there is no such thing in production', async () => {
  const env = evalEnv({ ENVIRONMENT: 'production' });
  assert.equal((await evalCall(env, { model: GEMMA, question: 'hi' })).status, 404);
  assert.equal(env._calls.length, 0);
});

test('eval route: without EVAL_KEY configured it does not exist, with a wrong key it is refused', async () => {
  assert.equal((await evalCall(evalEnv({ EVAL_KEY: undefined }), { model: GEMMA, question: 'hi' })).status, 404);
  assert.equal((await evalCall(evalEnv({ EVAL_KEY: 'short' }), { model: GEMMA, question: 'hi' }, { key: 'short' })).status, 404);
  const env = evalEnv();
  for (const key of [null, '', 'x', 'e'.repeat(39), 'e'.repeat(41), 'f'.repeat(40)]) {
    const r = await evalCall(env, { model: GEMMA, question: 'hi' }, { key });
    assert.equal(r.status, 401, `key ${String(key).slice(0, 5)}`);
  }
  assert.equal(env._calls.length, 0, 'the model must never be called with a wrong key');
});

test('eval route: a good call returns the answer and charges the real cost', async () => {
  const env = evalEnv();
  const r = await evalCall(env, { model: GEMMA, question: 'কোষ কী?', lang: 'bn' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.answer, 'একটি উত্তর (answer)');
  assert.equal(r.body.neurons, 19);
  assert.equal(r.body.usageEstimated, false);
  assert.equal(r.body.promptVersion, PROMPT_VERSION);
  const row = env._store._rows('SELECT used, reserved FROM budget')[0];
  assert.equal(row.used, 19);
  assert.equal(row.reserved, 0);
  assert.equal(env._calls[0].model, GEMMA);
  assert.equal(env._calls[0].input.messages.at(-1).content, 'কোষ কী?');
  assert.equal(env._calls[0].input.max_tokens, 450);
});

test('eval route: only listed models, valid input only', async () => {
  const env = evalEnv();
  assert.equal((await evalCall(env, { model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast', question: 'hi' })).status, 400);
  assert.equal((await evalCall(env, { model: GEMMA, question: '' })).status, 400);
  assert.equal((await evalCall(env, { model: GEMMA, question: 'x'.repeat(601) })).status, 400);
  assert.equal((await evalCall(env, { model: GEMMA, question: 'hi', extra: 1 })).status, 400);
  assert.equal((await evalCall(evalEnv({ EVAL_MODELS: GEMMA }), { model: QWEN, question: 'hi' })).body.error.code, 'model_not_allowed');
  assert.equal(env._calls.length, 0);
});

test('eval route: without the AI binding it is refused cleanly', async () => {
  const env = evalEnv({ AI: undefined });
  const r = await evalCall(env, { model: GEMMA, question: 'hi' });
  assert.equal(r.status, 503);
});

test('eval route: a failed call is charged as UNCERTAIN (we cannot know it did not run), and nothing leaks', async () => {
  const env = evalEnv({}, () => {
    throw new Error('internal GPU error 0xDEAD');
  });
  const r = await evalCall(env, { model: GEMMA, question: 'hi' });
  assert.equal(r.status, 502);
  assert.equal(r.body.error.code, 'model_error');
  assert.doesNotMatch(JSON.stringify(r.body), /GPU|0xDEAD/);
  const row = env._store._rows('SELECT used, reserved FROM budget')[0];
  assert.equal(row.used, 80); // UNCERTAIN_CHARGE_UNITS, not zero
  assert.equal(row.reserved, 0);
});

test('eval route: a TIMEOUT is charged too, because the model may keep running and be billed', async () => {
  const env = evalEnv({ AI_TIMEOUT_MS: '2000' }, () => new Promise(() => {}));
  const r = await evalCall(env, { model: GEMMA, question: 'hi' });
  assert.equal(r.status, 502);
  const row = env._store._rows('SELECT used, reserved FROM budget')[0];
  assert.equal(row.used, 80);
  assert.equal(row.reserved, 0);
});

test('eval route: an unreadable answer is charged too (the model did run)', async () => {
  const env = evalEnv({}, () => ({ weird: true }));
  assert.equal((await evalCall(env, { model: GEMMA, question: 'hi' })).status, 502);
  assert.equal(env._store._rows('SELECT used FROM budget')[0].used, 80);
});

test('eval route: repeated failures use the budget up, so a broken model cannot cost more than the budget', async () => {
  const env = evalEnv({ GLOBAL_DAILY_BUDGET_UNITS: '1000', EVAL_BUDGET_PCT: '0.5' }, () => {
    throw new Error('down');
  });
  let refused = null;
  for (let i = 0; i < 20; i++) {
    const r = await evalCall(env, { model: GEMMA, question: `q${i}` });
    if (r.status !== 502) {
      refused = r;
      break;
    }
  }
  assert.ok(refused, 'the budget must stop further calls');
  assert.equal(refused.body.error.code, 'ai_unavailable');
  assert.ok(env._store._rows('SELECT used, reserved FROM budget')[0].used <= 500);
});

test('runChat marks failures: a started call may have run, a call that never started did not', async () => {
  const msgs = [{ role: 'user', content: 'x' }];
  await assert.rejects(runChat({ AI: { run: () => new Promise(() => {}) } }, GEMMA, msgs, { maxTokens: 5, timeoutMs: 30 }), (e) => e instanceof ModelError && e.modelMayHaveRun === true);
  await assert.rejects(runChat({ AI: { run: async () => { throw new Error('x'); } } }, GEMMA, msgs, { maxTokens: 5, timeoutMs: 1000 }), (e) => e.modelMayHaveRun === true);
  await assert.rejects(runChat({ AI: { run: async () => ({ nope: 1 }) } }, GEMMA, msgs, { maxTokens: 5, timeoutMs: 1000 }), (e) => e.modelMayHaveRun === true);
  await assert.rejects(runChat({ AI: {} }, GEMMA, msgs, { maxTokens: 5, timeoutMs: 1000 }), (e) => e.modelMayHaveRun === false);
  await assert.rejects(runChat({}, GEMMA, msgs, { maxTokens: 5, timeoutMs: 1000 }), (e) => e.modelMayHaveRun === false);
});

test('config: the uncertain charge cannot exceed the per-call maximum', () => {
  assert.throws(() => loadConfig(makeEnv({ UNCERTAIN_CHARGE_UNITS: '500', MAX_UNITS_PER_REQUEST: '120' })));
  assert.equal(loadConfig(makeEnv()).uncertainChargeUnits, 80);
});

test('eval route: usage the model did not report is estimated and marked', async () => {
  const env = evalEnv({}, () => ({ response: 'উত্তর' }));
  const r = await evalCall(env, { model: GEMMA, question: 'hi' });
  assert.equal(r.status, 200);
  assert.equal(r.body.usageEstimated, true);
  assert.ok(r.body.neurons >= 1);
});

test('eval route: it stops at its share of the daily budget, so real users keep theirs', async () => {
  const env = evalEnv({ GLOBAL_DAILY_BUDGET_UNITS: '500', EVAL_BUDGET_PCT: '0.5', RESERVE_UNITS_PER_REQUEST: '40' }, () => chatAnswer('x', { prompt_tokens: 100, completion_tokens: 1000 }));
  let ok = 0;
  let last;
  for (let i = 0; i < 20; i++) {
    last = await evalCall(env, { model: GEMMA, question: `q${i}` });
    if (last.status === 200) ok++;
    else break;
  }
  assert.ok(ok >= 1 && ok < 20);
  assert.equal(last.status, 503);
  assert.equal(last.body.error.code, 'ai_unavailable');
  const row = env._store._rows('SELECT used, reserved FROM budget')[0];
  assert.ok(row.used + row.reserved <= 250 + 120, 'never far past the evaluation share');
});

test('eval route: the question, the answer and the key never appear in logs', async () => {
  const lines = [];
  const original = console.log;
  console.log = (...a) => lines.push(a.join(' '));
  try {
    const env = evalEnv({}, () => chatAnswer('SECRET-ANSWER-TEXT'));
    await evalCall(env, { model: GEMMA, question: 'SECRET-QUESTION-TEXT' });
    await evalCall(env, { model: GEMMA, question: 'q' }, { key: 'wrong-key-value' });
    const all = lines.join('\n');
    assert.ok(lines.length >= 2);
    assert.doesNotMatch(all, /SECRET-QUESTION-TEXT|SECRET-ANSWER-TEXT/);
    assert.ok(!all.includes(KEY));
    assert.ok(!all.includes('wrong-key-value'));
  } finally {
    console.log = original;
  }
});

test('the AI is still switched off for the public ask route', async () => {
  const env = evalEnv();
  const reg = await handle(req('/v1/register', { method: 'POST', body: { installId: crypto.randomUUID() } }), env, { now: () => T0 });
  const token = (await reg.json()).token;
  const res = await handle(
    req('/v1/ask', {
      method: 'POST',
      body: { question: 'hi' },
      headers: { authorization: `Bearer ${token}`, 'x-request-id': crypto.randomUUID(), 'x-timestamp': String(Math.floor(T0 / 1000)) },
    }),
    env,
    { now: () => T0 },
  );
  assert.equal(res.status, 503);
  assert.equal((await res.json()).error.code, 'ai_disabled');
  assert.equal(env._calls.length, 0, 'ask must not reach the model while AI is disabled');
});
