# Model evaluation (Phase 3B, step 1)

Goal: compare the candidate models on 30 Bengali HSC Biology questions, then choose a default **together**, from evidence.
No model is assumed to be the winner. AI stays **disabled** for the public `/v1/ask` route throughout.

## Candidates (chosen from Cloudflare's catalog, pricing page "Last updated Nov 18, 2026")
| model | why it is on the list | neurons per million tokens (in / out) |
|---|---|---|
| `@cf/google/gemma-4-26b-a4b-it` | Google open model, strong general ability | 9,091 / 27,273 |
| `@cf/qwen/qwen3-30b-a3b-fp8` | Cloudflare lists explicit multilingual support | 4,625 / 30,475 |
| `@cf/zai-org/glm-4.7-flash` | Cloudflare lists "100+ languages", cheap | 5,500 / 36,400 |

Left out on purpose: Llama 3.3 / Llama 4 (Bengali not among their officially supported languages; 70B is also very expensive here),
Mistral Small 3.1, SEA-LION (South-East Asian languages), models that need a signup form or a paid plan.
Possible later experiment: answer in English with the best model, then translate with `@cf/ai4bharat/indictrans2-en-indic-1B`.

## How to run
1. Actions → "Nexus API (Cloudflare Worker)" → Run workflow → **`run-eval-staging`**.
2. It deploys staging, makes a **temporary** key, asks every question to every model (about 90 calls), then **deletes the key**.
3. Open the run → **Summary** (numbers) and download the artifact **`model-evaluation`**: `report.md` (answers to grade), `summary.md`, `results.json`.

## How the grading works
`report.md` shows each question with each model's answer, side by side, and a line to fill:
**Accuracy / Bengali / Terms (1-5) and Hallucination (Y/N)**. Six questions are traps: a false premise, a request for a made-up citation,
a non-existent species, an off-topic question, a Banglish question, an English question. A good model corrects, admits ignorance or declines politely.
The numbers (speed, neurons, cut-off answers, share of Bengali letters) say nothing about **correctness**. A person has to judge that.
The questions are **my draft**: edit `eval/questions.bn.json` to match the real syllabus before relying on the result.

## Before you run it
- Nothing runs by itself. The evaluation starts only when you choose `run-eval-staging` and press Run workflow.
- The questions are a **draft**, not syllabus-approved. Check them against your syllabus first.
- Do **not** run it on a day when AI is live in production: the 10,000-neuron allowance is shared by the whole Cloudflare account, and our counters are per Worker, so the real cap could be reached before either counter notices.

## Budget safety
- Each call reserves from the shared daily budget and is charged its real cost. The evaluation may use at most 50% of the day's budget (`EVAL_BUDGET_PCT`).
- Cloudflare's free allowance (10,000 neurons per day) is shared by the **whole account**, staging and production together.
- If answers are long (Bengali uses many tokens), the later questions may be refused with `ai_unavailable`. The report shows them as errors: run again after 00:00 UTC, or use `--limit` / `--models`.
- A call that fails, times out or returns something unreadable is **charged as an uncertain cost** (80 units by default, `UNCERTAIN_CHARGE_UNITS`), because Cloudflare may still run and bill it after we stop waiting; we cannot cancel a call. Only a call that provably never started is given back.
- So a broken model cannot cost more than the budget: repeated failures simply use the evaluation share up and the route stops with `ai_unavailable`.
