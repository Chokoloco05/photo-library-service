const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const { once } = require('node:events');
const { Pool } = require('pg');
const { createClient } = require('redis');
const { createDatabase } = require('../database');
const { createApp } = require('../app');
const { createCache } = require('../cache');
const { hashPassword } = require('../auth');
const { fixture } = require('./fixtures');

test('Redis shares cached reads across application instances and invalidates committed changes during outages', {
  skip: (!process.env.TEST_DATABASE_URL || !process.env.TEST_REDIS_URL) && 'Set PostgreSQL and Redis integration URLs',
}, async () => {
  const schema = `cache_test_${randomBytes(6).toString('hex')}`;
  const admin = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const database = createDatabase({ connectionString: process.env.TEST_DATABASE_URL, options: `-c search_path=${schema}` });
  const clients = [createClient({ url: process.env.TEST_REDIS_URL }), createClient({ url: process.env.TEST_REDIS_URL })];
  const caches = clients.map(client => createCache({ client, env: { APP_ENV: schema } }));
  const servers = [];
  try {
    await admin.query(`CREATE SCHEMA ${schema}`);
    await database.migrate();
    await Promise.all(clients.map(client => client.connect()));
    const password = 'cache-integration-only-2026';
    const auth = { username: 'admin', passwordHash: await hashPassword(password), localHttp: true };
    let listReads = 0;
    const list = database.list;
    database.list = async () => { listReads++; return list(); };
    for (const cache of caches) {
      const server = createApp({ database, cache, auth }).listen(0, '127.0.0.1');
      servers.push(server); await once(server, 'listening');
    }
    const [left, right] = servers.map(server => `http://127.0.0.1:${server.address().port}`);
    assert.deepEqual(await (await fetch(`${left}/api/photos`)).json(), { photos: [] });
    assert.deepEqual(await (await fetch(`${right}/api/photos`)).json(), { photos: [] });
    assert.equal(listReads, 1);
    assert.equal(caches[1].stats.hit, 1);
    const login = await fetch(`${right}/api/auth/login`, { method: 'POST', headers: { Origin: right, 'Content-Type': 'application/json' }, body: JSON.stringify({ username: 'admin', password }) });
    assert.equal(login.status, 200);
    const headers = { Origin: right, Cookie: login.headers.get('set-cookie').split(';')[0], 'X-CSRF-Token': (await login.json()).csrfToken };
    const image = await fixture();
    const initialRevision = await database.revision();
    const upload = await fetch(`${right}/api/photos`, { method: 'POST', headers: { ...headers, 'Content-Type': 'image/png', 'X-Filename': 'cache.png' }, body: image });
    assert.equal(upload.status, 201);
    const photo = await upload.json();
    assert.notEqual(await database.revision(), initialRevision);
    assert.equal((await (await fetch(`${left}/api/photos`)).json()).photos.length, 1);
    assert.equal(listReads, 2);
    assert.equal((await (await fetch(`${left}/api/stats`)).json()).count, 1);
    assert.equal((await fetch(`${right}/api/photos/${photo.id}`, { method: 'PATCH', headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify({ title: 'fresh title' }) })).status, 200);
    assert.equal((await (await fetch(`${left}/api/photos`)).json()).photos[0].title, 'fresh title');

    clients[1].destroy();
    assert.equal((await fetch(`${right}/api/photos/${photo.id}`, { method: 'DELETE', headers })).status, 204);
    assert.deepEqual(await (await fetch(`${right}/api/photos`)).json(), { photos: [] });
    assert.deepEqual(await (await fetch(`${left}/api/photos`)).json(), { photos: [] });
    assert.equal((await (await fetch(`${left}/api/stats`)).json()).count, 0);
    const expiring = createCache({ client: clients[0], env: { APP_ENV: schema }, ttlSeconds: 1 });
    assert.equal(await expiring.read('expiry', () => database.revision(), async () => 1), 1);
    await new Promise(resolve => setTimeout(resolve, 1100));
    assert.equal(await expiring.read('expiry', () => database.revision(), async () => 2), 2);
  } finally {
    await Promise.all(servers.map(server => new Promise(resolve => server.close(resolve))));
    for (const client of clients) if (client.isOpen) client.destroy();
    await database.close();
    await admin.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await admin.end();
  }
});
