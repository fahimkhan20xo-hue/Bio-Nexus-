import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

// The workflow lives outside nexus-worker/. These tests read it as text, so no extra library is needed.
const file = new URL('../../.github/workflows/nexus-worker.yml', import.meta.url);
const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf-8') : null;
const skip = text === null ? 'the workflow file is not next to this folder' : false;

function jobs() {
  const out = {};
  let name = null;
  let inJobs = false;
  for (const line of text.split('\n')) {
    if (/^jobs:\s*$/.test(line)) {
      inJobs = true;
      continue;
    }
    const m = inJobs && /^  ([a-z0-9-]+):\s*$/.exec(line);
    if (m) {
      name = m[1];
      out[name] = [];
    } else if (name) out[name].push(line);
  }
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.join('\n')]));
}

test('workflow: a failing command in front of "| tee" fails the step (pipefail)', { skip }, () => {
  for (const [name, block] of Object.entries(jobs())) {
    if (!block.includes('| tee')) continue;
    assert.match(block, /shell: bash/, `job ${name} pipes into tee, so it must run with "shell: bash" (which turns on pipefail)`);
    const lines = block.split('\n');
    lines.forEach((line, i) => {
      if (line.includes('smoke.mjs') && line.includes('| tee')) {
        assert.match(lines[i - 1], /set -o pipefail/, `job ${name}: the smoke test line needs "set -o pipefail" right above it`);
      }
    });
  }
});

test('workflow: nothing deploys by itself (a push only runs the tests)', { skip }, () => {
  const j = jobs();
  for (const name of ['deploy-staging', 'deploy-production', 'recreate-secrets']) {
    const cond = /^    if: (.*)$/m.exec(j[name]);
    assert.ok(cond, `job ${name} must have an if: condition`);
    assert.doesNotMatch(cond[1], /event_name == 'push'/, `job ${name} must never run on a push`);
    assert.match(cond[1], /inputs\.action/, `job ${name} must require a manual action`);
  }
  assert.match(/^    if: (.*)$/m.exec(j['deploy-production'])[1], /deploy-production/);
});

test('workflow: the unzip step cannot touch anything outside nexus-worker/', { skip }, () => {
  assert.match(text, /grep -v '\^nexus-worker\/'/);
});
