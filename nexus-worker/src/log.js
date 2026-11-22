// Structured logging with an allow-list. Question text, tokens, raw IP addresses and
// installation IDs can never be logged, because only these keys are ever written.
const ALLOWED = new Set(['evt', 'rid', 'route', 'method', 'status', 'ms', 'code', 'env', 'iidh', 'plan', 'level', 'detail']);

export function logEvent(fields) {
  const out = { t: new Date().toISOString() };
  for (const [k, v] of Object.entries(fields)) {
    if (!ALLOWED.has(k)) continue;
    out[k] = typeof v === 'string' ? v.slice(0, 120) : v;
  }
  console.log(JSON.stringify(out));
}
