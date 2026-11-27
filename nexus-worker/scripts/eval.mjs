// Runs the evaluation questions through every candidate model on the STAGING Worker and writes a report
// a human can grade. Nothing here decides which model wins.
//   EVAL_KEY=... node scripts/eval.mjs <baseUrl> [--out dir] [--models a,b] [--limit n]
import fs from 'node:fs';
import path from 'node:path';
import { DEFAULT_EVAL_MODELS } from '../src/models.js';

const args = process.argv.slice(2);
const base = args[0];
const opt = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : def;
};
const key = process.env.EVAL_KEY;
if (!base || !key) {
  console.error('usage: EVAL_KEY=... node scripts/eval.mjs <baseUrl> [--out dir] [--models a,b] [--limit n]');
  process.exit(2);
}
const outDir = opt('out', 'eval-out');
const models = (opt('models', '') || '').split(',').filter(Boolean);
const useModels = models.length ? models : DEFAULT_EVAL_MODELS;
const limit = Number(opt('limit', '0')) || 0;
const questions = JSON.parse(fs.readFileSync(new URL('../eval/questions.bn.json', import.meta.url), 'utf-8')).questions.slice(0, limit || undefined);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function ask(model, q) {
  for (let attempt = 0; attempt < 6; attempt++) {
    let res;
    try {
      res = await fetch(base.replace(/\/+$/, '') + '/v1/_eval/run', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-eval-key': key },
        body: JSON.stringify({ model, question: q.question, lang: 'bn' }),
      });
    } catch (e) {
      await sleep(3000);
      continue;
    }
    const text = await res.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {
      // not JSON
    }
    if (res.status === 200 && json && json.ok) return { ok: true, ...json };
    // 404 right after deploy: the temporary key is not live yet. 429/503: wait as told.
    if (res.status === 404 || res.status === 429 || res.status === 503) {
      const wait = Math.min(Number(res.headers.get('retry-after')) || 4, 20) * 1000;
      if (json && json.error && ['ai_unavailable', 'rate_limited'].includes(json.error.code) && res.status === 503 && attempt >= 2) {
        return { ok: false, error: `${res.status} ${json.error.code}: ${json.error.message}` };
      }
      await sleep(wait);
      continue;
    }
    return { ok: false, error: `${res.status} ${json && json.error ? json.error.code + ': ' + json.error.message : text.slice(0, 120)}` };
  }
  return { ok: false, error: 'no answer after retries' };
}

function bengaliRatio(s) {
  const letters = [...s].filter((c) => /\p{L}/u.test(c));
  if (!letters.length) return 0;
  return letters.filter((c) => /[\u0980-\u09FF]/.test(c)).length / letters.length;
}

fs.mkdirSync(outDir, { recursive: true });
const results = [];
for (const q of questions) {
  for (const model of useModels) {
    process.stdout.write(`Q${q.id} ${model} ... `);
    const r = await ask(model, q);
    const rec = { id: q.id, model, ...r };
    if (r.ok) {
      rec.bnRatio = Number(bengaliRatio(r.answer).toFixed(2));
      rec.chars = r.answer.length;
      console.log(`${r.ms} ms, ${r.neurons} neurons${r.finish === 'length' ? ' (cut off)' : ''}`);
    } else console.log(`ERROR ${r.error}`);
    results.push(rec);
    await sleep(300);
  }
}
fs.writeFileSync(path.join(outDir, 'results.json'), JSON.stringify(results, null, 1));

// ---- summary table (numbers only) ----
const rows = useModels.map((model) => {
  const mine = results.filter((r) => r.model === model);
  const good = mine.filter((r) => r.ok);
  const avg = (f) => (good.length ? good.reduce((s, r) => s + f(r), 0) / good.length : 0);
  const avgN = avg((r) => r.neurons);
  const bnQs = good.filter((r) => questions.find((q) => q.id === r.id && q.topic !== 'english'));
  return {
    model,
    answered: `${good.length}/${mine.length}`,
    errors: mine.length - good.length,
    avgMs: Math.round(avg((r) => r.ms)),
    avgNeurons: Number(avgN.toFixed(1)),
    totalNeurons: good.reduce((s, r) => s + r.neurons, 0),
    answersPerDay: avgN ? Math.floor(7200 / avgN) : 0,
    avgChars: Math.round(avg((r) => r.chars)),
    cutOff: good.filter((r) => r.finish === 'length').length,
    lowBengali: bnQs.filter((r) => r.bnRatio < 0.4).length,
    estimated: good.filter((r) => r.usageEstimated).length,
  };
});
let summary = '# Model evaluation: numbers only\n\n';
summary += 'These are measurements, not quality. **Quality is graded by a person** in `report.md`.\n\n';
summary += '| model | answered | errors | avg ms | avg neurons | total neurons | answers/day at 7200 | avg chars | cut off | low Bengali | usage estimated |\n|---|---|---|---|---|---|---|---|---|---|---|\n';
for (const r of rows) {
  summary += `| ${r.model} | ${r.answered} | ${r.errors} | ${r.avgMs} | ${r.avgNeurons} | ${r.totalNeurons} | ${r.answersPerDay} | ${r.avgChars} | ${r.cutOff} | ${r.lowBengali} | ${r.estimated} |\n`;
}
summary += '\n"low Bengali" = answers to Bengali-language questions with under 40% Bengali letters. "answers/day" is a rough estimate of how many such answers fit in 7200 neurons (80% of a 9000 budget).\n';
fs.writeFileSync(path.join(outDir, 'summary.md'), summary);

// ---- the report to grade ----
let report = '# Model evaluation report (to be graded by a person)\n\nGrade each answer. Do not trust the numbers for quality.\n\n';
report += 'Scale 1-5. **Accuracy**: scientifically correct. **Bengali**: natural, correct Bengali. **Terms**: English scientific terms used correctly. **Hallucination**: Y if it invented anything.\n\n';
for (const q of questions) {
  report += `---\n\n## Q${q.id} [${q.topic}]\n\n**${q.question}**\n\n`;
  if (q.expect) report += `_Expected behaviour:_ ${q.expect}\n\n`;
  for (const model of useModels) {
    const r = results.find((x) => x.id === q.id && x.model === model);
    report += `### ${model}\n\n`;
    if (!r || !r.ok) {
      report += `ERROR: ${r ? r.error : 'missing'}\n\n`;
    } else {
      report += `${r.answer}\n\n`;
      report += `_${r.ms} ms, ${r.neurons} neurons, ${r.chars} characters, Bengali letters ${Math.round(r.bnRatio * 100)}%${r.finish === 'length' ? ', CUT OFF' : ''}${r.usageEstimated ? ', usage estimated' : ''}_\n\n`;
    }
    report += 'Grade: Accuracy __ / Bengali __ / Terms __ / Hallucination __ \n\n';
  }
}
fs.writeFileSync(path.join(outDir, 'report.md'), report);
console.log('\n' + summary);
