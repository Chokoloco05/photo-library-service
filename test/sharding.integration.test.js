const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const { readFile } = require('node:fs/promises');
const path = require('node:path');
const { Pool } = require('pg');
const { once } = require('node:events');
const { createDatabase, migrate } = require('../database');
const { createApp } = require('../app');
const { hashPassword } = require('../auth');
const { analyze } = require('../photos');
const { fixture } = require('./fixtures');

test('hash sharding preserves legacy photos, cross-shard operations, migrations and the shared size limit', {
  skip: !process.env.TEST_DATABASE_URL && 'Set TEST_DATABASE_URL for PostgreSQL integration',
}, async () => {
  const suffix = randomBytes(6).toString('hex');
  const coordinatorName = `sharding_test_${suffix}`;
  const workerName = `sharding_worker_${suffix}`;
  const connection = new URL(process.env.TEST_DATABASE_URL);
  const admin = new Pool({ connectionString: connection.href });
  const coordinatorUrl = new URL(connection); coordinatorUrl.pathname = `/${coordinatorName}`;
  const workerUrl = new URL(connection); workerUrl.pathname = `/${workerName}`;
  let database, worker;
  try {
    await admin.query(`CREATE DATABASE ${coordinatorName}`);
    await admin.query(`CREATE DATABASE ${workerName}`);
    database = createDatabase({ connectionString: coordinatorUrl.href, shardConnectionString: workerUrl.href });
    worker = new Pool({ connectionString: workerUrl.href });
    await database.migrate(); await migrate(worker);
    const photo = await analyze(await fixture(), 'legacy.png');
    const ids = Array.from({ length: 8 }, (_, i) => `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`);
    for (const id of ids) await database.insert({ ...photo, id });

    await database.pool.query('CREATE EXTENSION postgres_fdw');
    await database.pool.query(`CREATE SERVER photo_shard_1 FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '127.0.0.1',port '5432',dbname '${workerName}')`);
    const mapping = (await database.pool.query("SELECT format('CREATE USER MAPPING FOR CURRENT_USER SERVER photo_shard_1 OPTIONS(user %L,password %L)', $1::text,$2::text) AS sql",
      [decodeURIComponent(connection.username), decodeURIComponent(connection.password)])).rows[0].sql;
    await database.pool.query(mapping);
    const sql = (await readFile(path.join(__dirname, '../scripts/postgres/enable-sharding.sql'), 'utf8'))
      .split('\n').filter(line => !line.startsWith('\\') && !line.includes('\\gexec')).join('\n');
    await database.pool.query(sql);
    await database.pool.query(sql); // Re-running the installation preserves the data.
    const localCount = Number((await database.pool.query('SELECT count(*) FROM photos_shard_0')).rows[0].count);
    const remoteCount = Number((await worker.query('SELECT count(*) FROM photos')).rows[0].count);
    assert.ok(localCount > 0 && remoteCount > 0);
    assert.equal(localCount + remoteCount, ids.length);
    assert.equal((await database.list()).length, ids.length);
    for (const id of ids) assert.deepEqual((await database.image(id, false)).data, photo.original);
    const stats = await database.stats();
    assert.equal(stats.count, ids.length);
    assert.equal(stats.reclaimable_bytes, (ids.length - 1) * photo.size_bytes);

    // A pending additive migration must run remotely before the coordinator.
    await worker.query('ALTER TABLE photos DROP COLUMN description');
    await worker.query("DELETE FROM schema_migrations WHERE version='002-description.sql'");
    await database.migrate();
    await database.ready();
    const password = 'sharding-integration-only-2026';
    const server = createApp({ database, auth: { username: 'admin', passwordHash: await hashPassword(password), localHttp: true } }).listen(0, '127.0.0.1');
    await once(server, 'listening');
    const base = `http://127.0.0.1:${server.address().port}`;
    try {
      const session = await fetch(`${base}/api/auth/login`, { method: 'POST', headers: { Origin: base, 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: 'admin', password }) });
      assert.equal(session.status, 200);
      const headers = { Origin: base, Cookie: session.headers.get('set-cookie').split(';')[0], 'X-CSRF-Token': (await session.json()).csrfToken };
      const upload = await fetch(`${base}/api/photos`, { method: 'POST', headers: { ...headers, 'Content-Type': 'image/png', 'X-Filename': 'sharded.png' }, body: photo.original });
      assert.equal(upload.status, 201);
      const uploaded = await upload.json();
      assert.deepEqual(Buffer.from(await (await fetch(`${base}/api/photos/${uploaded.id}/download`)).arrayBuffer()), photo.original);
      assert.equal((await fetch(`${base}/readyz`)).status, 200);
      assert.equal((await fetch(`${base}/api/photos/${uploaded.id}`, { method: 'DELETE', headers })).status, 204);
    } finally { await new Promise(resolve => server.close(resolve)); }
    await worker.query('ALTER TABLE photos RENAME TO photos_unavailable');
    try { await assert.rejects(database.ready()); }
    finally { await worker.query('ALTER TABLE photos_unavailable RENAME TO photos'); }
    for (const id of ids) {
      assert.equal((await database.update(id, 'updated', 'across shards')).description, 'across shards');
      assert.equal(await database.delete(id), true);
      assert.equal(await database.image(id, false), undefined);
    }
    assert.equal((await database.stats()).count, 0);

    await database.pool.query(`INSERT INTO photos(id,filename,title,mime_type,size_bytes,width,height,sha256,visual_hash,original,thumbnail)
      SELECT md5(i::text)::uuid,'limit.png','limit','image/png',1,1,1,repeat('a',64),repeat('b',16),decode('01','hex'),decode('01','hex')
      FROM generate_series(1,1999) i`);
    const results = await Promise.allSettled([database.insert({ ...photo, id: 'ffffffff-0000-4000-8000-000000000001' }),
      database.insert({ ...photo, id: 'ffffffff-0000-4000-8000-000000000002' })]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.find(result => result.status === 'rejected').reason.status, 409);
    assert.equal((await database.stats()).count, 2000);
  } finally {
    await Promise.all([database?.close(), worker?.end()]);
    await admin.query(`DROP DATABASE IF EXISTS ${coordinatorName} WITH (FORCE)`);
    await admin.query(`DROP DATABASE IF EXISTS ${workerName} WITH (FORCE)`);
    await admin.end();
  }
});
