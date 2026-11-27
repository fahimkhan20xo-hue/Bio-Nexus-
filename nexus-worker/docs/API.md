# Nexus API reference (Phase 3A)

Base URL: `https://nexus-api.<your-subdomain>.workers.dev` (staging: `nexus-api-staging`). All paths start with `/v1`.
All bodies are JSON (`Content-Type: application/json`). There is no CORS: only the app is meant to call this.

## Identity
There are no user accounts. Each installation makes a random version-4 UUID once, keeps it on the phone,
and calls `register`. It gets a **token** (valid 30 days) and sends it as `Authorization: Bearer <token>`.
The token proves "the server issued this to some installation". It does **not** prove who a person is,
and anyone can register many installations, which is why limits also exist per IP and for the whole service.
When a token expires or is refused with `401`, register again with the same installation ID.

For `POST` calls that spend or could spend budget (`/v1/ask`, `/v1/_test/reserve`) also send:
- `X-Request-Id`: a new UUID for every request. Each is accepted once (replay protection).
- `X-Timestamp`: Unix seconds. Must be within 5 minutes of the server (`serverTime` in `/v1/health` helps with a wrong phone clock).

## Endpoints

### `GET /v1/health`
No authentication. `200 {"ok":true,"service":"nexus-api","apiVersion":"3A.1","environment":"production","aiEnabled":false,"serverTime":1790000000,"requestId":"..."}`

### `POST /v1/register`
```json
{ "installId": "7c1e0f6e-5f0a-4d3e-9c2b-1b2a3c4d5e6f", "app": { "version": "1.1.0", "build": 91 } }
```
`200 {"ok":true,"token":"...","expiresAt":1792592000,"plan":"free","limits":{"dailyPerInstall":15},"serverTime":...}`

### `GET /v1/quota` (token)
`200 {"ok":true,"plan":"free","dailyLimit":15,"used":2,"remaining":13,"resetsInSec":41000,"global":"ok","aiEnabled":false,"serverTime":...}`
`global` is `ok`, `throttled` or `exhausted`. Budget numbers are never exposed. Days reset at 00:00 UTC.

### `POST /v1/ask` (token + replay headers)
```json
{ "question": "Why are mitochondria the powerhouse of the cell?", "lang": "en", "screen": "SpeciesPage",
  "species": { "scientific": "Panthera leo", "common": "Lion", "description": "..." },
  "history": [ { "role": "user", "text": "..." }, { "role": "assistant", "text": "..." } ] }
```
Limits: `question` 1-600 characters, `lang` en|bn|ja, `screen` 40 characters of `A-Za-z0-9_.:-`, at most 4 history items of 400 characters,
species text fields 60-80 characters and `description` 400. Unknown fields are refused. Body at most 16 KB.
**Phase 3A:** after validation this returns `503 ai_disabled`. Nothing is reserved or spent.

### `POST /v1/_test/reserve` and `/v1/_test/settle` (staging only; `404` in production)
`reserve {"units":40}` gives `{"reservationId":"..."}`. `settle {"reservationId":"...","action":"commit"|"release","actualUnits":12}`.
They run the real quota rules without any AI, which is how the limits are tested.

### `POST /v1/_eval/run` (staging only, temporary `X-Eval-Key`; `404` everywhere else)
Used only by the model evaluation. Body `{"model":"@cf/...","question":"...","lang":"bn"}`. Returns the answer, token usage and neuron cost.
It exists only while the deploy workflow's evaluation run is active (the key is created for the run and deleted after it).

## Errors
```json
{ "ok": false, "error": { "code": "daily_limit_reached", "message": "...", "retryAfterSec": 41000 }, "requestId": "..." }
```
`Retry-After` is also sent when a retry makes sense. Messages are safe to show; never rely on their wording, use `code`.

| HTTP | code | meaning |
|---|---|---|
| 400 | `invalid_request`, `invalid_json`, `clock_skew` | bad input or phone clock |
| 401 | `unauthorized` | no / bad / expired token: register again |
| 404 | `not_found`, `unknown_reservation` | |
| 405 | `method_not_allowed` | |
| 409 | `replay_detected`, `already_settled` | |
| 413 | `payload_too_large` | |
| 415 | `unsupported_media_type` | |
| 429 | `rate_limited`, `register_limited`, `daily_limit_reached`, `too_many_concurrent` | wait, see `retryAfterSec` |
| 500 | `internal_error`, `server_misconfigured` | |
| 501 | `not_implemented` | AI turned on before Phase 3B exists |
| 503 | `ai_disabled`, `ai_unavailable`, `service_unavailable`, `busy` | AI off or budget used up: **use the offline Nexus** |

## Default limits (change in `wrangler.toml`)
| | default |
|---|---|
| AI requests per installation per day (free) | 15 |
| One request in flight per installation | 1 |
| Requests per IP per minute | 120 |
| AI requests per IP per day | 300 |
| New installations per IP per day / in total per day | 40 / 5000 |
| Global daily budget (units = Workers AI neurons) | 9000; new free requests stop at 80% |
| Request id memory / reservation timeout | 15 min / 90 s |

## What is logged
Only: time, request id, route, method, status, duration, environment, a short hash of the installation, plan and error code.
Never: the question, species text, the token, the raw IP address or the installation ID.
