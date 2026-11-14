const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createCache } = require('../cache');

function memoryClient() {
  const client = new EventEmitter();
  const values = new Map();
  client.isReady = true;
  client.get = async key => values.get(key) ?? null;
  client.set = async (key, value) => { values.set(key, value); };
  return client;
}

test('cache revisions prevent an old in-flight read from replacing newer library results', async () => {
  const cache = createCache({ client: memoryClient() });
  let revision = 'before';
  let finishOldRead;
  const old = cache.read('photos', async () => revision, () => new Promise(resolve => { finishOldRead = resolve; }));
  while (!finishOldRead) await new Promise(resolve => setImmediate(resolve));
  revision = 'after';
  assert.deepEqual(await cache.read('photos', async () => revision, async () => ['new']), ['new']);
  finishOldRead(['old']);
  await old;
  assert.deepEqual(await cache.read('photos', async () => revision, async () => assert.fail('Expected a cache hit')), ['new']);
});

test('cache bypasses outages, rejects corrupt entries and bounds stalled commands', async () => {
  const client = memoryClient();
  const cache = createCache({ client, timeoutMs: 15 });
  client.get = async () => '{broken-json';
  assert.equal(await cache.read('stats', async () => 'version', async () => 42), 42);
  client.get = () => new Promise(() => {});
  // Keep the test alive while the implementation's unref'ed deadline runs.
  const keepAlive = setInterval(() => {}, 1000);
  try { assert.equal(await cache.read('stats', async () => 'version', async () => 43), 43); }
  finally { clearInterval(keepAlive); }
  client.isReady = false;
  assert.equal(await cache.read('stats', () => assert.fail('Offline cache must bypass version lookup'), async () => 44), 44);
  assert.equal(cache.stats.error, 2);
  assert.equal(cache.stats.bypass, 3);
});
