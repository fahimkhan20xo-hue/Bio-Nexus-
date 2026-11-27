// Workers AI models Nexus may use, with their prices in NEURONS per million tokens.
// Source: developers.cloudflare.com/workers-ai/platform/pricing (page "Last updated Nov 18, 2026").
// Prices and model lists change. Re-check this table before every release.
//
// Cloudflare's free allowance is 10,000 neurons per day for the whole ACCOUNT, and requests above it fail
// (no automatic billing on the Free plan). Our own budget numbers in the Durable Object are self-imposed
// limits below that.

export const MODEL_RATES = {
  '@cf/google/gemma-4-26b-a4b-it': { in: 9091, out: 27273 },
  '@cf/qwen/qwen3-30b-a3b-fp8': { in: 4625, out: 30475 },
  '@cf/zai-org/glm-4.7-flash': { in: 5500, out: 36400 },
};

// Extra request options some models need (for example to stop long hidden "thinking" that would cost neurons).
export const MODEL_OPTIONS = {
  '@cf/qwen/qwen3-30b-a3b-fp8': { chat_template_kwargs: { enable_thinking: false } },
};

export const DEFAULT_EVAL_MODELS = Object.keys(MODEL_RATES);

/** Cost of one call in neurons, rounded up. Throws for a model we have no price for (never guess a price). */
export function neuronsFor(model, usage) {
  const rate = MODEL_RATES[model];
  if (!rate) throw new Error(`no price known for ${model}`);
  const input = Math.max(0, usage.in || 0);
  const output = Math.max(0, usage.out || 0);
  return Math.ceil((input * rate.in + output * rate.out) / 1_000_000);
}
