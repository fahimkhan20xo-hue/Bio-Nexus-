// Calls a Workers AI chat model and turns its answer into one safe, simple shape.
import { MODEL_OPTIONS, neuronsFor } from './models.js';

function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('model timeout')), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Workers AI answers in two shapes: OpenAI-style { choices: [...] } or { response: "..." }.
 * Returns { text, finish, usage: {in, out} | null }.
 */
export function parseChat(raw) {
  if (!raw || typeof raw !== 'object') throw new Error('empty model response');
  let text = '';
  let finish = 'stop';
  const choice = Array.isArray(raw.choices) ? raw.choices[0] : null;
  if (choice && choice.message) {
    const c = choice.message.content;
    text = typeof c === 'string' ? c : Array.isArray(c) ? c.map((p) => (typeof p === 'string' ? p : p && p.text) || '').join('') : '';
    finish = choice.finish_reason || 'stop';
  } else if (typeof raw.response === 'string') {
    text = raw.response;
  } else {
    throw new Error('unknown model response shape');
  }
  const u = raw.usage;
  const usage =
    u && Number.isFinite(u.prompt_tokens) && Number.isFinite(u.completion_tokens) ? { in: u.prompt_tokens, out: u.completion_tokens } : null;
  return { text: text.trim(), finish, usage };
}

/**
 * A model call that failed. modelMayHaveRun tells the budget what to do:
 *  true  = the call started, so Cloudflare may have run (and billed) it: a timeout, a rejection, an unreadable answer.
 *          We cannot cancel a call, so this is charged as an uncertain cost.
 *  false = it provably never started.
 */
export class ModelError extends Error {
  constructor(message, modelMayHaveRun) {
    super(message);
    this.modelMayHaveRun = modelMayHaveRun;
  }
}

/**
 * Runs one chat completion. When the model reports no token usage we estimate it from the text,
 * generously (Bengali needs many tokens per character), and say so, because budget must fail safe.
 * Any failure after the call started is a ModelError with modelMayHaveRun = true.
 */
export async function runChat(env, model, messages, { maxTokens, temperature = 0.3, timeoutMs }) {
  if (!env.AI || typeof env.AI.run !== 'function') throw new ModelError('AI binding is missing', false);
  const started = Date.now();
  const input = { messages, max_tokens: maxTokens, temperature, ...(MODEL_OPTIONS[model] || {}) };
  try {
    const raw = await withTimeout(env.AI.run(model, input), timeoutMs);
    const parsed = parseChat(raw);
    let estimated = false;
    let usage = parsed.usage;
    if (!usage) {
      estimated = true;
      const promptChars = messages.reduce((n, m) => n + m.content.length, 0);
      usage = { in: Math.ceil(promptChars / 1.5), out: Math.ceil(parsed.text.length / 1.5) };
    }
    return {
      text: parsed.text,
      finish: parsed.finish,
      usage,
      estimated,
      neurons: neuronsFor(model, usage),
      ms: Date.now() - started,
    };
  } catch (e) {
    throw new ModelError(String((e && e.message) || e), true);
  }
}
