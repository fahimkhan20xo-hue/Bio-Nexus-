# Nexus API (Phase 3A): backend foundation, no AI

A small Cloudflare Worker plus one SQLite-backed Durable Object. It gives BioNexus a safe place to
ask for AI answers later (Phase 3B), without any secret in the app and without any chance of
unplanned spending. **Phase 3A has no AI at all.** It only builds and tests the machinery around it.

BioNexus stays a complete offline app. If this backend is down, slow or out of budget, nothing in the
app depends on it.

## What it does now
| | |
|---|---|
| `GET /v1/health` | is the service up |
| `POST /v1/register` | gives an installation an anonymous signed token |
| `GET /v1/quota` | the installation's own daily usage, plus a coarse "global" state |
| `POST /v1/ask` | fully checks the request, then answers `503 ai_disabled` (no AI yet) |
| `POST /v1/_test/*` | **staging only**: reserve / settle budget without AI, so quota, replay and concurrency can be tested for real |

Full details: [docs/API.md](docs/API.md). Security notes and test report: [docs/SECURITY.md](docs/SECURITY.md).
Setting it up from a phone: [docs/DEPLOY.md](docs/DEPLOY.md).

## Files
```
src/app.js        routes, authentication, error handling (no Cloudflare-only imports, so tests run it in Node)
src/store.js      ALL quota / rate-limit / budget rules (SQL), shared by the Durable Object and the tests
src/quota_do.js   the Durable Object (thin wrapper around store.js)
src/index.js      Worker entry
src/config.js     settings with limits; a bad setting stops the Worker (fail closed)
src/validate.js   strict request validation        src/token.js   HMAC tokens
src/http.js       responses, size-limited body reader   src/log.js   allow-list logging
test/             54 tests, real SQLite             scripts/      smoke test, local server, secret creation
wrangler.toml     Cloudflare config (production + staging)
```

## Run the tests (any computer with Node 22)
```
cd nexus-worker && npm test
```
`npm run dev:local` starts the same code locally; `npm run smoke:local` then runs the deployment checks against it.

## Design decisions (and why)
- **One Durable Object holds everything.** Each decision (replay, per-IP, per-installation, global budget) is one
  atomic transaction, so two requests can never both take the last unit of budget. The price: one object is a
  throughput ceiling (about 1,000 requests per second is Cloudflare's soft limit per object). Far above what BioNexus needs;
  the path to scale is to shard by installation and keep a small global-budget object.
- **Fail closed.** Any doubt (bad config, Durable Object error or timeout, unverifiable numbers) rejects the AI request.
- **Interrupted requests are charged as used.** A reservation that is never finished (Worker crash, model hang) is closed
  after 90 s and counted as spent, because we cannot know whether the model ran.
- **Budget stages.** At 80% of the daily budget new free-plan AI requests stop. In-flight requests may still finish.
  At 100% nothing is reserved at all. Premium and institution plans are prepared (they may use a higher share, 90% and 95%)
  but nothing can create them yet: plans are read only from a table that only future server-side verification may write.
- **Per-IP limits are generous on purpose.** Mobile carriers put many people behind one IP address, so strict per-IP limits
  would block real users. The strong protections are the daily per-installation limit and the global budget.
- **Plain JavaScript, no runtime dependencies.** Fewer things to break in CI; `wrangler` is the only dev dependency.
