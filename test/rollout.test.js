const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, readFile, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { measureRollout } = require('../scripts/measure-rollout');

for (const outage of [false, true]) {
  test(`rollout records HTTP continuity and ${outage ? 'rejects an interruption' : 'checks the new revision'}`, async () => {
    const directory = await mkdtemp(path.join(os.tmpdir(), 'photo-rollout-'));
    let revision = 'old';
    let interrupt = false;
    try {
      const request = async pathname => ({ statusCode: interrupt ? 503 : 200,
        payload: pathname === '/api/info' ? { environment: 'prod', revision } : { count: 0 } });
      const command = async args => {
        if (args[0] === 'apply') {
          interrupt = outage;
          await new Promise(resolve => setTimeout(resolve, 15));
          interrupt = false;
          revision = 'new';
        }
      };
      const evidence = path.join(directory, 'evidence.json');
      const rollout = measureRollout({ manifest: 'fixture.json', evidence, expectedRevision: 'new', request, command, intervalMs: 1 });
      if (outage) await assert.rejects(rollout, /failed HTTP requests/);
      else assert.equal((await rollout).passed, true);
      const result = JSON.parse(await readFile(evidence, 'utf8'));
      assert.equal(result.passed, !outage);
      assert.ok(result.requests >= 4);
      assert.deepEqual(result.observedRevisions, ['old', 'new']);
    } finally { await rm(directory, { recursive: true, force: true }); }
  });
}

test('rollout preserves failure evidence when the Kubernetes operation fails', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'photo-rollout-'));
  try {
    const evidence = path.join(directory, 'evidence.json');
    await assert.rejects(measureRollout({ manifest: 'fixture.json', evidence, expectedRevision: 'new', intervalMs: 1,
      request: async pathname => ({ statusCode: 200, payload: pathname === '/api/info' ? { environment: 'prod', revision: 'old' } : { count: 0 } }),
      command: async () => { throw new Error('apply failed'); },
    }), /apply failed/);
    assert.equal(JSON.parse(await readFile(evidence, 'utf8')).passed, false);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
