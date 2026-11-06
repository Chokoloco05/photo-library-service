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
    // Simulate an existing v1 database containing a photo before migration 002.
    await database.pool.query('CREATE TABLE schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
    await database.pool.query(await readFile(path.join(__dirname, '../migrations/001-library.sql'), 'utf8'));
    await database.pool.query("INSERT INTO schema_migrations(version) VALUES ('001-library.sql')");
    const { analyze } = require('../photos');
    const legacy = await analyze(await fixture(), 'avant-migration.png');
    await database.pool.query('INSERT INTO photos(id,filename,title,mime_type,size_bytes,width,height,sha256,visual_hash,original,thumbnail) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
      [legacy.id, legacy.filename, legacy.title, legacy.mime_type, legacy.size_bytes, legacy.width, legacy.height, legacy.sha256, legacy.visual_hash, legacy.original, legacy.thumbnail]);
    await Promise.all([database.migrate(), otherDatabase.migrate()]);
    assert.equal((await database.pool.query('SELECT * FROM schema_migrations')).rowCount, 2);
    const migrated = (await otherDatabase.list())[0];
    assert.equal(migrated.id, legacy.id); assert.equal(migrated.description, '');
    assert.deepEqual((await otherDatabase.image(legacy.id, false)).data, legacy.original);
    await database.delete(legacy.id);
    for (const [index, store] of [database, otherDatabase].entries()) {
      const server = createApp({ database: store, basePath: index ? '/test' : '' }).listen(0, '127.0.0.1'); servers.push(server); await once(server, 'listening');
    }
    const [base, other] = servers.map((server, index) => `http://127.0.0.1:${server.address().port}${index ? '/test' : ''}`);
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
