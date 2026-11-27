# Setting up and deploying from a phone

Everything runs in GitHub Actions. You need no computer. The account owner must meet Cloudflare's own account
requirements: check them yourself on cloudflare.com. I could not confirm from here whether a payment card is asked
for. The Free plan is built to refuse over-limit requests instead of charging.

## One-time setup
1. Create a free account at **cloudflare.com** and sign in.
2. In the dashboard open **Workers & Pages**. The first time, Cloudflare asks you to choose a **workers.dev subdomain**. Choose one.
3. Copy your **Account ID** (shown on the Workers & Pages overview page, usually on the right).
4. Create an API token: **My Profile → API Tokens → Create Token → "Edit Cloudflare Workers" template**, choose your account, create it and copy it once.
5. In GitHub, open the BioNexus repository → **Settings → Secrets and variables → Actions → New repository secret** and add:
   - `CLOUDFLARE_API_TOKEN` = the token
   - `CLOUDFLARE_ACCOUNT_ID` = the account id

   (Dashboard screens change over time. If a name differs, look for the closest one.)
6. Add the files to the repository:
   - Upload `nexus-worker.zip` to the **root** of the repository (Add file → Upload files).
   - Upload `nexus-worker.yml` into `.github/workflows/` (same way you uploaded `android-apk.yml`).
   - Replace `.github/workflows/android-apk.yml` with the new one (it now ignores changes under `nexus-worker/`).
7. **Actions → "Nexus API (Cloudflare Worker)" → Run workflow → `install-from-zip`.** It unpacks the zip into `nexus-worker/` and commits it.
8. Run it again with **`test-only`**. Green means all tests passed.
9. Run it with **`deploy-staging`**. It deploys `nexus-api-staging`, creates the two secrets **inside Cloudflare** (random values that are never printed
   and never stored in GitHub), then runs 22 checks against the real deployed Worker. The URL and results are in the run summary.

No token or secret is ever in the app, the repository or the logs.

## Production
Only when staging is green and you are happy: run **`deploy-production`**. It repeats the tests, deploys `nexus-api`, creates its own separate
secrets, and runs the production checks (18). Staging and production have separate storage and separate secrets.

## Everyday use
- **Nothing deploys by itself.** A push, or uploading the workflow file, only runs the tests. Deploying staging, deploying production, running the model evaluation and replacing secrets each need you to press **Run workflow** with that action. (The unpack step's own commit does not start other workflows: GitHub does not run workflows for pushes made with the built-in token.)
- Edit limits in `nexus-worker/wrangler.toml`, then run `test-only`, then `deploy-staging` when you decide to.
- **`recreate-secrets-staging|production`** replaces the secrets. Every installation then registers again by itself (the app must handle `401`).
- If the credentials are missing, a deploy fails with a clear message.

## If something fails
| Message | Meaning |
|---|---|
| "You need to register a workers.dev subdomain" | do setup step 2 |
| "Authentication error" / 10000 | the token is wrong or lacks Workers permissions: recreate it with the template |
| `server_misconfigured` in the smoke test | secrets are missing: run `recreate-secrets-staging` |
| smoke test cannot reach the Worker | wait a minute and rerun; check the URL in the deploy log |
| Durable Object / migration error | tell me the exact text; the config uses `new_sqlite_classes` (SQLite-backed objects) |

Not verified from my side: the exact current Cloudflare dashboard wording, and the Durable Objects free-tier numbers. Check the limits page before relying on them.
