// A local stand-in for Cloudflare, for development and for testing the smoke script.
// Same Worker code, same quota rules, real SQLite, but in memory. Nothing here is used in production.
import http from 'node:http';
import { handle } from '../src/app.js';
import { makeEnv } from '../test/helpers.js';

const port = Number(process.env.PORT || 8788);
const env = makeEnv({ ENVIRONMENT: process.env.ENVIRONMENT || 'staging' });
if (process.env.FAKE_AI && process.env.EVAL_KEY) {
  // a stand-in model, only for testing the evaluation script on a computer
  env.EVAL_KEY = process.env.EVAL_KEY;
  env.AI = {
    run: async (model, input) => ({
      choices: [{ message: { content: `নমুনা উত্তর (sample) for: ${input.messages.at(-1).content.slice(0, 30)}` }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 300 + model.length, completion_tokens: 200 },
    }),
  };
}

http
  .createServer(async (nodeReq, nodeRes) => {
    const chunks = [];
    for await (const c of nodeReq) chunks.push(c);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const headers = new Headers();
    for (const [k, v] of Object.entries(nodeReq.headers)) if (typeof v === 'string') headers.set(k, v);
    const request = new Request(`http://127.0.0.1:${port}${nodeReq.url}`, {
      method: nodeReq.method,
      headers,
      body: body && nodeReq.method !== 'GET' && nodeReq.method !== 'HEAD' ? body : undefined,
    });
    const res = await handle(request, env);
    nodeRes.writeHead(res.status, Object.fromEntries(res.headers));
    nodeRes.end(Buffer.from(await res.arrayBuffer()));
  })
  .listen(port, '127.0.0.1', () => console.error(`Nexus API (local) on http://127.0.0.1:${port}`));
