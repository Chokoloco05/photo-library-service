const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../app');

let server;
let baseUrl;
before(async () => {
  server = createApp({
    hostname: 'host-http', version: '1.2.3',
    env: { POD_NAME: 'pod-http', POD_UID: 'http-uid', APP_ENV: 'test', APP_REVISION: 'commit-123' },
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  if (server) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
});

test('GET / exposes the deployed version, revision and serving Pod', async () => {
  const response = await fetch(baseUrl);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /application\/json/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const body = await response.json();
  assert.equal(body.version, 'v1.2.3');
  assert.equal(body.revision, 'commit-123');
  assert.equal(body.pod, 'pod-http');
  assert.equal(body.environment, 'test');
  assert.deepEqual(body.photos, []);
});

test('health endpoint returns HTTP 200 without external dependencies', async () => {
  const response = await fetch(`${baseUrl}/healthz`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('readiness and library explicitly fail when the database is unavailable', async () => {
  assert.equal((await fetch(`${baseUrl}/readyz`)).status, 503);
  assert.equal((await fetch(`${baseUrl}/api/photos`)).status, 503);
});

test('whoami has one Pod name per line for balancing demonstrations', async () => {
  const response = await fetch(`${baseUrl}/whoami`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/plain/);
  assert.equal(await response.text(), 'pod-http\n');
});

test('unknown routes and unsupported writes are rejected', async () => {
  assert.equal((await fetch(`${baseUrl}/missing`)).status, 404);
  assert.equal((await fetch(baseUrl, { method: 'POST' })).status, 404);
});
