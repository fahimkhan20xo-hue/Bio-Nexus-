import test from 'node:test';
import assert from 'node:assert/strict';
import { signToken, verifyToken, shortHash } from '../src/token.js';
import { validateAsk, validateRegister, checkReplayHeaders } from '../src/validate.js';
import { loadConfig } from '../src/config.js';
import { makeEnv, TOKEN_SECRET } from './helpers.js';

test('token: round trip, tamper, expiry', async () => {
  const p = { v: 1, iid: 'abc', iat: 1000, exp: 2000 };
  const t = await signToken(TOKEN_SECRET, p);
  assert.deepEqual(await verifyToken(TOKEN_SECRET, t, 1500), p);
  assert.equal(await verifyToken(TOKEN_SECRET, t, 2000), null);
  assert.equal(await verifyToken('x'.repeat(40), t, 1500), null);
  const [body, sig] = t.split('.');
  const evil = btoa(JSON.stringify({ v: 1, iid: 'abc', iat: 1000, exp: 9999999999 })).replace(/=+$/, '');
  assert.equal(await verifyToken(TOKEN_SECRET, `${evil}.${sig}`, 1500), null);
  assert.equal(await verifyToken(TOKEN_SECRET, `${body}.`, 1500), null);
  assert.equal(await verifyToken(TOKEN_SECRET, 'a.b.c', 1500), null);
  assert.equal(await verifyToken(TOKEN_SECRET, 'x'.repeat(700), 1500), null);
  assert.equal(await verifyToken(TOKEN_SECRET, 42, 1500), null);
});

test('shortHash is stable, secret-dependent and does not reveal the value', async () => {
  const a = await shortHash(TOKEN_SECRET, '203.0.113.7');
  assert.equal(a, await shortHash(TOKEN_SECRET, '203.0.113.7'));
  assert.notEqual(a, await shortHash('y'.repeat(40), '203.0.113.7'));
  assert.equal(a.length, 24);
  assert.ok(!a.includes('203'));
});

test('validateAsk: cleans control characters, counts characters, keeps Bengali', () => {
  const v = validateAsk({ question: '  \u0000হ্যালো\u0007 world  ', lang: 'bn', screen: 'SpeciesPage', species: { scientific: 'Panthera leo', description: 'x'.repeat(400) } });
  assert.equal(v.question, 'হ্যালো world');
  assert.equal(v.lang, 'bn');
  assert.throws(() => validateAsk({ question: 'a', species: { description: 'x'.repeat(401) } }));
  assert.throws(() => validateAsk({ question: 'a', species: { hacked: 'x' } }));
  assert.throws(() => validateAsk({ question: 'a', screen: 'bad screen!' }));
  assert.throws(() => validateAsk({ question: 'a', history: [{ role: 'system', text: 'x' }] }));
  assert.throws(() => validateAsk({ question: 'a', history: [{ role: 'user', text: 'x'.repeat(401) }] }));
  assert.throws(() => validateAsk(null));
  assert.throws(() => validateAsk({ question: 5 }));
});

test('validateRegister accepts only version-4 UUIDs', () => {
  assert.ok(validateRegister({ installId: crypto.randomUUID() }));
  assert.throws(() => validateRegister({ installId: '00000000-0000-1000-8000-000000000000' }));
  assert.throws(() => validateRegister({ installId: 'x'.repeat(36) }));
});

test('checkReplayHeaders', () => {
  const h = (o) => new Headers(o);
  const now = 1_800_000_000;
  const rid = crypto.randomUUID();
  assert.equal(checkReplayHeaders(h({ 'x-request-id': rid, 'x-timestamp': String(now) }), now, 300).rid, rid);
  assert.throws(() => checkReplayHeaders(h({ 'x-request-id': 'nope', 'x-timestamp': String(now) }), now, 300));
  assert.throws(() => checkReplayHeaders(h({ 'x-request-id': rid, 'x-timestamp': 'abc' }), now, 300));
  assert.throws(() => checkReplayHeaders(h({ 'x-request-id': rid, 'x-timestamp': String(now + 301) }), now, 300));
});

test('config defaults match the agreed policy: 15 per day, 80% soft stop', () => {
  const c = loadConfig(makeEnv());
  assert.equal(c.plans.free.daily, 15);
  assert.equal(c.plans.free.softPct, 0.8);
  assert.equal(c.aiEnabled, false);
  assert.equal(c.dailyBudget, 9000);
  assert.throws(() => loadConfig(makeEnv({ RESERVE_UNITS_PER_REQUEST: '500', MAX_UNITS_PER_REQUEST: '100' })));
  assert.throws(() => loadConfig(makeEnv({ ENVIRONMENT: 'prod' })));
  assert.throws(() => loadConfig(makeEnv({ IP_SALT: 'short' })));
});
