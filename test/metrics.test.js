const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const { createApp } = require('../app');
const { createMetricsServer } = require('../metrics');

test('internal metrics preserve public routes, normalize photo IDs and track database availability', async () => {
  let databaseAvailable = true;
  const database = {
    ready: async () => { if (!databaseAvailable) throw new Error('offline'); },
    image: async () => undefined,
  };
  const app = createApp({ database, basePath: '/test', env: { APP_ENV: 'test', POD_NAME: 'metrics-test-pod' } });
  const publicServer = app.listen(0, '127.0.0.1');
  const internalServer = createMetricsServer(app.locals.metrics).listen(0, '127.0.0.1');
  await Promise.all([once(publicServer, 'listening'), once(internalServer, 'listening')]);
  const publicUrl = `http://127.0.0.1:${publicServer.address().port}/test`;
  const internalUrl = `http://127.0.0.1:${internalServer.address().port}/metrics`;
  try {
    assert.equal((await fetch(`${publicUrl}/metrics`)).status, 404);
    const ids = [randomUUID(), randomUUID()];
    for (const id of ids) assert.equal((await fetch(`${publicUrl}/api/photos/${id}/image`)).status, 404);
    assert.equal((await fetch(`${publicUrl}/unknown-user-path?password=never-a-label`)).status, 404);
    const response = await fetch(internalUrl);
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.match(text, /photo_http_requests_total\{[^}]*route="\/api\/photos\/:id\/image"[^}]*\} 2/);
    assert.match(text, /photo_database_up\{[^}]*\} 1/);
    assert.match(text, /photo_process_resident_memory_bytes/);
    assert.match(text, /photo_http_request_duration_seconds_bucket/);
    assert.match(text, /photo_http_requests_active\{[^}]*\} 0/);
    for (const value of [...ids, 'unknown-user-path', 'never-a-label']) assert.equal(text.includes(value), false);
    databaseAvailable = false;
    assert.match(await (await fetch(internalUrl)).text(), /photo_database_up\{[^}]*\} 0/);
    const other = createApp({ env: { APP_ENV: 'dev', POD_NAME: 'another-pod' } });
    const counter = await other.locals.metrics.registry.getSingleMetric('photo_http_requests_total').get();
    assert.equal(counter.values.length, 0);
  } finally {
    await Promise.all([publicServer, internalServer].map(server => new Promise(resolve => server.close(resolve))));
  }
});
