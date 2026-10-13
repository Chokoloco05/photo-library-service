const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createIdentity } = require('../identity');
const { version } = require('../package.json');

test('local execution works without Kubernetes environment variables', () => {
  const result = createIdentity({ env: {}, hostname: 'my-laptop' });
  assert.equal(result.pod, 'my-laptop');
  assert.equal(result.podUid, 'local');
  assert.equal(result.environment, 'local');
  assert.equal(result.revision, 'local');
  assert.equal(result.version, `v${version}`);
});

test('Kubernetes identity takes precedence over the container hostname', () => {
  const result = createIdentity({
    hostname: 'container-host', version: '2.3.4',
    env: { POD_NAME: 'photo-pod-abc', POD_UID: 'uid-42', APP_ENV: 'test', APP_REVISION: 'abc123' },
  });
  assert.equal(result.hostname, 'container-host');
  assert.equal(result.pod, 'photo-pod-abc');
  assert.equal(result.podUid, 'uid-42');
  assert.equal(result.environment, 'test');
  assert.equal(result.revision, 'abc123');
  assert.equal(result.version, 'v2.3.4');
});

test('empty optional environment values use local fallbacks', () => {
  const result = createIdentity({
    hostname: 'fallback', env: { POD_NAME: '', POD_UID: '', APP_ENV: '', APP_REVISION: '' },
  });
  assert.equal(result.pod, 'fallback');
  assert.equal(result.podUid, 'local');
  assert.equal(result.environment, 'local');
  assert.equal(result.revision, 'local');
});

test('application instances cannot leak identity between environments', () => {
  const env = { POD_NAME: 'pod-a', APP_ENV: 'dev' };
  const first = createIdentity({ env });
  env.POD_NAME = 'pod-b';
  env.APP_ENV = 'test';
  const second = createIdentity({ env });
  assert.equal(first.pod, 'pod-a');
  assert.equal(first.environment, 'dev');
  assert.equal(second.pod, 'pod-b');
  assert.equal(second.environment, 'test');
});
