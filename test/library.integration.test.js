const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomBytes } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const path = require('node:path');
const { Pool } = require('pg');
const { createApp } = require('../app');
const { createDatabase } = require('../database');
const { fixture } = require('./fixtures');
const { hashPassword } = require('../auth');

test('PostgreSQL migrations and shared library lifecycle across two application instances', {
  skip: !process.env.TEST_DATABASE_URL && 'Set TEST_DATABASE_URL to run the real PostgreSQL integration test',
}, async t => {
  const schema = `photo_test_${randomBytes(6).toString('hex')}`;
  const admin = new Pool({ connectionString: process.env.TEST_DATABASE_URL });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const config = { connectionString: process.env.TEST_DATABASE_URL, options: `-c search_path=${schema}` };
  const database = createDatabase(config), otherDatabase = createDatabase(config);
  const servers = [];
  try {
    const password = 'integration-only-password-2026';
    const auth = { username: 'admin', passwordHash: await hashPassword(password), localHttp: true };
    // Simulate an existing v1 database containing a photo before migration 002.
    await database.pool.query('CREATE TABLE schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
    await database.pool.query(await readFile(path.join(__dirname, '../migrations/001-library.sql'), 'utf8'));
    await database.pool.query("INSERT INTO schema_migrations(version) VALUES ('001-library.sql')");
    const { analyze } = require('../photos');
    const legacy = await analyze(await fixture(), 'avant-migration.png');
    await database.pool.query('INSERT INTO photos(id,filename,title,mime_type,size_bytes,width,height,sha256,visual_hash,original,thumbnail) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
      [legacy.id, legacy.filename, legacy.title, legacy.mime_type, legacy.size_bytes, legacy.width, legacy.height, legacy.sha256, legacy.visual_hash, legacy.original, legacy.thumbnail]);
    await Promise.all([database.migrate(), otherDatabase.migrate()]);
    assert.equal((await database.pool.query('SELECT * FROM schema_migrations')).rowCount, 5);
    const expiryIndexes = await database.pool.query(`SELECT indexname FROM pg_indexes
      WHERE schemaname=$1 AND indexname IN ('auth_sessions_expires_at_idx','auth_attempts_expires_at_idx')`, [schema]);
    assert.equal(expiryIndexes.rowCount, 2);
    const migrated = (await otherDatabase.list())[0];
    assert.equal(migrated.id, legacy.id); assert.equal(migrated.description, '');
    assert.deepEqual((await otherDatabase.image(legacy.id, false)).data, legacy.original);
    await database.delete(legacy.id);
    for (const [index, store] of [database, otherDatabase].entries()) {
      const server = createApp({ database: store, auth, basePath: index ? '/test' : '' }).listen(0, '127.0.0.1'); servers.push(server); await once(server, 'listening');
    }
    const [base, other] = servers.map((server, index) => `http://127.0.0.1:${server.address().port}${index ? '/test' : ''}`);
    const sessions = new Map();
    for (const url of [base, other]) {
      const login = await global.fetch(`${url}/api/auth/login`, { method: 'POST', headers: {
        Origin: new URL(url).origin, 'Content-Type': 'application/json',
      }, body: JSON.stringify({ username: 'admin', password }) });
      assert.equal(login.status, 200);
      assert.match(login.headers.get('set-cookie'), /HttpOnly/);
      assert.match(login.headers.get('set-cookie'), /SameSite=Strict/);
      if (url === other) assert.match(login.headers.get('set-cookie'), /Path=\/test/);
      sessions.set(url, { Cookie: login.headers.get('set-cookie').split(';')[0],
        'X-CSRF-Token': (await login.json()).csrfToken, Origin: new URL(url).origin });
    }
    const fetch = (url, options = {}) => global.fetch(url, { ...options,
      headers: { ...sessions.get(url.startsWith(other) ? other : base), ...options.headers } });
    await t.test('separate login and dashboard protect pages and all library reads including mounted environments', async () => {
      for (const url of [base, other]) {
        const prefix = new URL(url).pathname.replace(/\/$/, '');
        for (const route of ['/', '/dashboard', '/index.html']) {
          const response = await global.fetch(`${url}${route}`, { headers: { Accept: 'text/html' }, redirect: 'manual' });
          assert.equal(response.status, 302);
          assert.equal(response.headers.get('location'), `${prefix}/login`);
        }
        const page = await global.fetch(`${url}/login`);
        assert.equal(page.status, 200);
        const html = await page.text();
        assert.match(html, /id="login-form"/);
        assert.doesNotMatch(html, /id="results"/);
        for (const route of ['/api/photos','/api/stats','/api/duplicates','/api/similar',
          '/api/photos/11111111-1111-4111-8111-111111111111/image',
          '/api/photos/11111111-1111-4111-8111-111111111111/download']) {
          assert.equal((await global.fetch(`${url}${route}`)).status, 401);
          assert.equal((await global.fetch(`${url}${route}`, { method: 'HEAD' })).status, 401);
        }
        assert.equal((await fetch(`${url}/dashboard`)).status, 200);
        const loggedIn = await fetch(`${url}/login`, { redirect: 'manual' });
        assert.equal(loggedIn.headers.get('location'), `${prefix}/dashboard`);
      }
    });
    await t.test('blocks anonymous writes, shares sessions across replicas and revokes logout', async () => {
      for (const method of ['POST', 'PATCH', 'DELETE']) {
        const route = method === 'POST' ? '/api/photos' : '/api/photos/11111111-1111-4111-8111-111111111111';
        assert.equal((await global.fetch(`${base}${route}`, { method })).status, 401);
      }
      const peer = createApp({ database: otherDatabase, auth, basePath: '/test' }).listen(0, '127.0.0.1');
      servers.push(peer); await once(peer, 'listening');
      const peerUrl = `http://127.0.0.1:${peer.address().port}/test`;
      let response = await global.fetch(`${peerUrl}/api/auth/session`, { headers: { Cookie: sessions.get(other).Cookie } });
      assert.equal((await response.json()).authenticated, true);
      response = await global.fetch(`${other}/api/photos`, { method: 'POST', headers: { Cookie: sessions.get(other).Cookie } });
      assert.equal(response.status, 403); // No CSRF token.
      const temporary = await global.fetch(`${peerUrl}/api/auth/login`, { method: 'POST', headers: {
        Origin: new URL(peerUrl).origin, 'Content-Type': 'application/json',
      }, body: JSON.stringify({ username: 'admin', password }) });
      const cookie = temporary.headers.get('set-cookie').split(';')[0];
      const csrf = (await temporary.json()).csrfToken;
      assert.equal((await global.fetch(`${other}/api/auth/logout`, { method: 'POST', headers: {
        Cookie: cookie, Origin: new URL(other).origin, 'X-CSRF-Token': csrf,
      } })).status, 204);
      assert.equal((await (await global.fetch(`${peerUrl}/api/auth/session`, { headers: { Cookie: cookie } })).json()).authenticated, false);
      const stored = await database.pool.query('SELECT token_hash FROM auth_sessions');
      assert.ok(stored.rows.every(row => !sessions.get(base).Cookie.endsWith(row.token_hash)));
    });
    await t.test('rejects forged, expired and cross-environment sessions and limits attempts across replicas', async () => {
      const cookie = sessions.get(base).Cookie;
      const anonymous = await global.fetch(`${base}/api/auth/session`, { headers: { Cookie: cookie.replace(/=[a-f0-9]+$/, '=' + '0'.repeat(64)) } });
      assert.equal((await anonymous.json()).authenticated, false);
      // A root cookie cannot authenticate the /test application (distinct name).
      assert.equal((await (await global.fetch(`${other}/api/auth/session`, { headers: { Cookie: cookie } })).json()).authenticated, false);
      const { createHash } = require('node:crypto');
      const hash = createHash('sha256').update(cookie.split('=')[1]).digest('hex');
      await database.pool.query("UPDATE auth_sessions SET expires_at=now()-interval '1 second' WHERE token_hash=$1", [hash]);
      assert.equal((await (await global.fetch(`${base}/api/auth/session`, { headers: { Cookie: cookie } })).json()).authenticated, false);
      await database.pool.query("UPDATE auth_sessions SET expires_at=now()+interval '1 hour' WHERE token_hash=$1", [hash]);
      assert.equal(await otherDatabase.authSession(hash, 'changed-password-fingerprint'), undefined);
      const attempts = await Promise.all(Array.from({ length: 12 }, (_, i) =>
        (i % 2 ? database : otherDatabase).authAttempt('shared-test-budget')));
      assert.equal(attempts.filter(Boolean).length, 10);
    });
    await t.test('shared admin works in explicit HTTP demo mode only on its configured school origin', async () => {
      const origin = 'http://team5.laboinfo-ecam.be';
      const demo = createApp({ database: otherDatabase, basePath: '/test',
        auth: { ...auth, localHttp: false, demoHttp: true, publicOrigin: origin } }).listen(0, '127.0.0.1');
      servers.push(demo); await once(demo, 'listening');
      const url = `http://127.0.0.1:${demo.address().port}/test`;
      // node:http preserves the virtual Host header; fetch may replace it with the URL host.
      const request = (suffix, options = {}) => new Promise((resolve, reject) => {
        const outgoing = require('node:http').request(url + suffix, options, response => {
          const chunks = [];
          response.on('data', chunk => chunks.push(chunk));
          response.on('end', () => resolve({ status: response.statusCode,
            headers: new Headers(Object.fromEntries(Object.entries(response.headers).map(([key, value]) => [key, Array.isArray(value) ? value.join(', ') : value]))),
            json: async () => JSON.parse(Buffer.concat(chunks).toString()),
          }));
        });
        outgoing.on('error', reject); outgoing.end(options.body);
      });
      const headers = { Host: 'team5.laboinfo-ecam.be', Origin: origin, 'Content-Type': 'application/json' };
      const login = await request('/api/auth/login', { method: 'POST', headers,
        body: JSON.stringify({ username: 'admin', password }) });
      assert.equal(login.status, 200);
      assert.doesNotMatch(login.headers.get('set-cookie'), /; Secure/);
      assert.match(login.headers.get('set-cookie'), /HttpOnly/);
      const cookie = login.headers.get('set-cookie').split(';')[0];
      const result = await login.json();
      assert.equal(result.demoHttp, true);
      const state = await request('/api/auth/session', { headers: { Host: headers.Host, Cookie: cookie } });
      assert.equal((await state.json()).authenticated, true);
      assert.equal((await request('/api/photos', { method: 'POST', headers })).status, 401);
      assert.equal((await request('/api/photos', { method: 'POST', headers: { ...headers, Cookie: cookie } })).status, 403);
      assert.equal((await request('/api/auth/login', { method: 'POST', headers: { ...headers, Host: 'untrusted.example', Origin: 'http://untrusted.example' },
        body: JSON.stringify({ username: 'admin', password }) })).status, 403);
      const upload = await request('/api/photos', { method: 'POST', headers: {
        Host: headers.Host, Origin: origin, Cookie: cookie, 'X-CSRF-Token': result.csrfToken, 'Content-Type': 'image/png',
      }, body: await fixture() });
      assert.equal(upload.status, 201);
      const photo = await upload.json();
      assert.equal((await request(`/api/photos/${photo.id}`, { method: 'DELETE', headers: {
        Host: headers.Host, Origin: origin, Cookie: cookie, 'X-CSRF-Token': result.csrfToken,
      } })).status, 204);
    });
    const input = await fixture();
    const upload = async (url, name = 'photo.png', content = input) => fetch(`${url}/api/photos`, {
      method: 'POST', headers: { 'Content-Type': 'image/png', 'X-Filename': encodeURIComponent(name) }, body: content,
    });
    let first, second;
    await t.test('serves the real browser interface and reports database readiness', async () => {
      const response = await fetch(base, { headers: { Accept: 'text/html' } });
      assert.match(response.headers.get('content-type'), /text\/html/);
      assert.match(await response.text(), /Gardez l’essentiel/);
      assert.equal((await fetch(`${base}/readyz`)).status, 200);
    });
    await t.test('isolates prefixed UI, assets and API routes for a shared school domain', async () => {
      const response = await fetch(other, { headers: { Accept: 'text/html' } });
      const html = await response.text();
      assert.match(html, /<base href="\/test\/">/);
      assert.match(html, /href="style.css"/);
      assert.equal((await fetch(`${other}/style.css`)).status, 200);
      assert.equal((await fetch(`${other}/api/info`)).status, 200);
      assert.equal((await fetch(other.replace('/test', '') + '/api/info')).status, 404);
    });
    await t.test('imports exact copies and a recompressed variant through different replicas', async () => {
      let response = await upload(base, 'voyage.png'); assert.equal(response.status, 201); first = await response.json();
      response = await upload(other, 'voyage-copie.png'); assert.equal(response.status, 201); second = await response.json();
      response = await upload(base, 'version.jpg', await fixture('jpeg')); assert.equal(response.status, 201);
      assert.equal((await response.json()).mime_type, 'image/jpeg'); // Real bytes determine the stored type.
      const photos = (await (await fetch(`${other}/api/photos`)).json()).photos;
      assert.equal(photos.length, 3);
      assert.equal(photos[0].description, ''); // Migration 002 default.
      const stats = await (await fetch(`${base}/api/stats`)).json();
      assert.equal(stats.count, 3); assert.equal(stats.reclaimable_bytes, input.length);
      const groups = (await (await fetch(`${other}/api/duplicates`)).json()).groups;
      assert.equal(groups.length, 1); assert.equal(groups[0].photos.length, 2);
      const pairs = (await (await fetch(`${base}/api/similar`)).json()).pairs;
      assert.equal(pairs.length, 2);
    });
    await t.test('original download is byte-for-byte identical across replicas', async () => {
      const response = await fetch(`${other}/api/photos/${first.id}/download`);
      assert.equal(response.status, 200);
      assert.match(response.headers.get('content-disposition'), /attachment/);
      assert.deepEqual(Buffer.from(await response.arrayBuffer()), input);
      const thumbnail = await fetch(`${base}/api/photos/${first.id}/image?thumbnail=1`);
      assert.equal(thumbnail.headers.get('content-type'), 'image/webp');
    });
    await t.test('persists edits through the second schema migration', async () => {
      const response = await fetch(`${base}/api/photos/${first.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title: "L'été <script>", description: 'Une description conservée dans PostgreSQL.' }) });
      assert.equal(response.status, 200);
      const photos = (await (await fetch(`${other}/api/photos`)).json()).photos;
      assert.equal(photos.find(p => p.id === first.id).description, 'Une description conservée dans PostgreSQL.');
      assert.equal((await database.pool.query('SELECT description FROM photos WHERE id=$1', [first.id])).rows[0].description, 'Une description conservée dans PostgreSQL.');
    });
    await t.test('rejects invalid images, IDs, edits and foreign-origin writes', async () => {
      assert.equal((await upload(base, 'bad.png', Buffer.from('invalid'))).status, 415);
      assert.equal((await fetch(`${base}/api/photos/not-a-uuid/image`)).status, 400);
      assert.equal((await fetch(`${base}/api/photos/00000000-0000-0000-0000-000000000000/image`)).status, 404);
      assert.equal((await fetch(`${base}/api/photos/${first.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: '{broken' })).status, 400);
      assert.equal((await fetch(`${base}/api/photos/${first.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title: '' }) })).status, 400);
      assert.equal((await fetch(`${base}/api/photos/${first.id}`, { method: 'DELETE', headers: { Origin: 'https://untrusted.example' } })).status, 403);
    });
    await t.test('deleting a copy recalculates savings and keeps the original', async () => {
      assert.equal((await fetch(`${other}/api/photos/${second.id}`, { method: 'DELETE' })).status, 204);
      assert.equal((await fetch(`${base}/api/photos/${second.id}/image`)).status, 404);
      const stats = await (await fetch(`${base}/api/stats`)).json();
      assert.equal(stats.count, 2); assert.equal(stats.reclaimable_bytes, 0);
      assert.equal((await fetch(`${other}/api/photos/${first.id}/image`)).status, 200);
      await database.migrate(); // Re-running migrations preserves existing data.
      assert.equal((await database.stats()).count, 2);
    });
  } finally {
    for (const server of servers) await new Promise(resolve => server.close(resolve));
    await Promise.all([database.close(), otherDatabase.close()]);
    // Only the randomly allocated schema belonging to this test is removed.
    await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end();
  }
});
