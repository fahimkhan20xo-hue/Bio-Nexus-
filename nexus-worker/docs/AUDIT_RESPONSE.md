# Response to the Phase 3B step 1 audit

Each point was checked against the real files, not taken on trust.

| # | Audit said | Finding | Action |
|---|---|---|---|
| 1 | `eval.mjs ... \| tee` has no pipefail, so a failed evaluation could look green | **Partly right.** The evaluation step already used `shell: bash` (pipefail on), so that step was fine. But the two **smoke-test steps** (staging and production) had no `shell:`, so they ran without pipefail and a failing smoke test would have been hidden by `tee`. That also means "deploy green" was weaker evidence than I said earlier. The 22/22 result is still real, because the full PASS list was seen. | Every job now defaults to `shell: bash`, every pipe has an explicit `set -o pipefail`, and `test/workflow.test.js` fails if either is removed (checked by putting the bug back: the test fails). |
| 2 | A timeout releases the reservation, but the model may still run and be billed | **Right**, and it also applied to unreadable answers. | Any call that started and then failed, timed out or returned garbage is **charged as uncertain** (80 units). Only a call that provably never started is released. 6 new tests, including repeated failures that exhaust the budget instead of exceeding it. |
| 3 | A push by the install job could start a staging deploy | **Wrong about the cause**: GitHub does not start workflows for pushes made with the built-in `GITHUB_TOKEN`. **Right about the risk**: uploading the workflow file yourself is a normal push and would have deployed staging, which breaks the rule "no deployment without permission". | Push now runs **only the tests**. Staging deploy, production deploy, the evaluation and secret changes are manual actions only. 2 tests guard this (mutation-checked). |
| + | The 10,000-neuron allowance is per account, our counter per Worker | Already documented; sharpened. | EVAL.md: never run an evaluation on a day AI is live in production. |
| + | Consent must also mention history and species context | **Right.** | Added to both languages in CONSENT_DRAFT.md. |
| + | The 30 questions are not syllabus-approved | **Right**, and they were never claimed to be. | Said explicitly in the file and EVAL.md. The owner must check them. |

Result: 82 tests, 82 passed. Real Cloudflare behaviour of this step is **still unverified**: no deploy or evaluation has been run.
