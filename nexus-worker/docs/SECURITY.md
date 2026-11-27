# Security notes and test report (Phase 3A)

## What is protected, and how
| Risk | Control |
|---|---|
| Secrets in the app / repo | None exist there. `TOKEN_SECRET` and `IP_SALT` are random, created by the deploy job straight into Cloudflare, never printed. The Cloudflare API token lives only in GitHub Actions Secrets. |
| Forged or tampered tokens | HMAC-SHA256, checked with the constant-time `crypto.subtle.verify`; expiry enforced; garbage and oversized tokens refused. |
| Spending too much | One atomic budget in a Durable Object (SQLite transactions). Reserve first, charge actual usage after. Free plan stops at 80%, hard stop at 100%. Anything unverifiable is refused. No code path can bill: the plan is the Cloudflare Free plan. |
| One installation draining the budget | 15 requests per day, one in flight at a time. |
| Many fake installations | Per-IP caps on registration (40/day) and AI (300/day), a global registration cap (5000/day), and the global budget. |
| Replay | Each `X-Request-Id` accepted once for 15 minutes, plus a ±5 minute timestamp window. |
| Bad or huge input | Strict schema (unknown fields refused), character limits that count Bengali correctly, body cap enforced on the stream (not only `Content-Length`). |
| Leaks in errors and logs | Fixed safe messages, no stack traces. Logging uses an allow-list: no question, token, raw IP or installation ID can be written. IPs are stored only as a salted hash (IPv6 cut to /64). |
| Premium abuse (future) | The app cannot choose a plan. Plans come only from a table nothing in the API writes. |
| Curated database | Not reachable from the backend at all. |

## Phase 3B, step 1 (evaluation only): what changed in the security picture
- The public `/v1/ask` still never reaches a model (a test proves it: the model is not called while `AI_ENABLED` is false).
- The AI binding exists in **staging only**. Production has no binding, no evaluation route and no key.
- The evaluation route needs a secret `EVAL_KEY` that exists only during an evaluation run (compared in constant time; 40 wrong-key attempts never call the model).
- Only models with a known price may be configured. A model call can never run without first reserving budget. A call that fails or times out is charged as an uncertain cost, never refunded.
- Nothing deploys by itself: pushes only run tests (guarded by tests).
- Neither question, answer nor key is logged (tested).
- **New limitation:** Cloudflare's 10,000-neuron allowance is per account, but our budget counter is per Worker. Staging and production count separately, so the real cap can be reached first. A refused model call is handled (nothing charged, 503, offline Nexus keeps working).

## Known limitations (no hiding)
1. **An installation ID is not an identity.** Anyone can make new ones. The real brakes are per-IP limits and the global budget. Worst case an attacker uses up the day's free AI budget: AI answers pause until midnight UTC and the offline Nexus keeps working. No money is lost.
2. **Sideloaded APKs cannot be attested** (no Play Integrity guarantee), so a determined attacker can copy the app's protocol. Accepted, and bounded by (1).
3. **Per-IP limits are loose** because many phones share one IP (carrier NAT). A shared IP could be blocked by one heavy user; the limits are settings you can tune.
4. **One Durable Object is a ceiling** (about 1,000 requests/s). Far above current needs.
5. **Free-tier numbers can change.** Re-check Cloudflare's limits before launch. I did not verify the Durable Objects free allowance.
6. Cleanup of old rows runs every 6 hours by an alarm; a short window of stale rows is harmless.

## Test report
Run: Node v22.23.4, real SQLite (`node:sqlite`), the real Worker code, in the build sandbox. **82 tests, 82 passed, 0 failed** (54 for Phase 3A, 28 for Phase 3B step 1, after the audit fixes; see AUDIT_RESPONSE.md).
On real Cloudflare (run by the owner): the staging deployment checks, **22/22 passed**.
Then the deployment smoke script against a local server running the same code: **staging 22/22, production 18/18.**

| Phase 3C item | Status |
|---|---|
| Invalid requests | **Executed** (bad JSON, wrong type, unknown fields, bad UUID, bad limits) |
| Oversized requests | **Executed** (declared length and a stream that hides its length) |
| Concurrent requests | **Executed locally**: 20 parallel from one installation (1 wins); 100 installations race for the budget (exactly the allowed number win, never overspent) |
| Installation ID changes | **Executed**: new IDs get a fresh allowance but the per-IP daily cap still holds |
| IP-based rate limits | **Executed** (429, `Retry-After`, other IPs unaffected) |
| Replay attempts | **Executed** (same request id 409; clock skew 400) |
| Quota exhaustion | **Executed** (15 per day, 16th refused; daily reset; 80% stop; premium share; hard cap) |
| Durable Object failure / slowness | **Simulated** (error and timeout give 503, fail closed, no leaks) |
| Worker downtime | **Not tested** (needs the real platform) |
| Unexpected API responses | Not applicable yet (no AI) |
| Unauthorized configuration changes | **Reviewed only**: there is no admin endpoint; config changes only through deploys; secrets only in Cloudflare |
| Secret exposure in the APK | Not applicable: the app is unchanged in this phase |

**Not yet verified, because it needs real Cloudflare:** the deploy itself, the Durable Object under real concurrency, real latency, and the free-tier behaviour. The deploy workflow runs the same checks against the deployed staging Worker; until you run it and it is green, treat Phase 3A as *implemented and locally tested, not yet deployment-verified*.

## Acceptance criteria (Phase 3A)
| Criterion | Status |
|---|---|
| Implementation executed | Locally yes; on Cloudflare **pending** |
| Relevant tests passed | Local: yes (54/54, 22/22, 18/18). Deployed: pending |
| Build and deployment verified | **Pending** (needs your Cloudflare credentials) |
| Security limitations documented | Yes (above) |
| No regression of offline features | Yes: no Flutter file was changed in this phase |
| Failures visible and safe | Yes (tested) |
