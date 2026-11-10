const { Pool } = require('pg');
const { readdir, readFile } = require('node:fs/promises');
const path = require('node:path');

const columns = 'id, filename, title, description, mime_type, size_bytes, width, height, sha256, visual_hash, created_at';

async function migrate(pool) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Transaction-scoped lock serializes migrations across application replicas.
    await client.query('SELECT pg_advisory_xact_lock(726041)');
    await client.query('CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
    const directory = path.join(__dirname, 'migrations');
    const files = (await readdir(directory)).filter(name => /^\d+[-\w]*\.sql$/.test(name)).sort();
    for (const file of files) {
      if ((await client.query('SELECT 1 FROM schema_migrations WHERE version=$1', [file])).rowCount) continue;
      await client.query(await readFile(path.join(directory, file), 'utf8'));
      await client.query('INSERT INTO schema_migrations(version) VALUES ($1)', [file]);
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

function createDatabase(config = {}) {
  const pool = new Pool({
    max: 5, connectionTimeoutMillis: 5000, idleTimeoutMillis: 10000,
    ...(process.env.DATABASE_URL ? { connectionString: process.env.DATABASE_URL } : {}), ...config,
  });
  pool.on('error', () => console.error('Idle database connection failed.'));
  return {
    pool,
    migrate: () => migrate(pool),
    close: () => pool.end(),
    ready: async () => { await pool.query('SELECT 1'); },
    authSession: async (hash, credential) => (await pool.query(
      'SELECT csrf_token FROM auth_sessions WHERE token_hash=$1 AND credential_id=$2 AND expires_at>now()', [hash, credential])).rows[0],
    authDelete: async hash => { await pool.query('DELETE FROM auth_sessions WHERE token_hash=$1', [hash]); },
    authCreate: async (hash, csrf, credential, seconds) => {
      await pool.query('DELETE FROM auth_sessions WHERE expires_at<=now() OR credential_id<>$1', [credential]);
      await pool.query('INSERT INTO auth_sessions(token_hash,csrf_token,credential_id,expires_at) VALUES ($1,$2,$3,now()+$4*interval \'1 second\')', [hash, csrf, credential, seconds]);
    },
    authAttempt: async bucket => {
      await pool.query('DELETE FROM auth_attempts WHERE expires_at<=now()');
      const result = await pool.query('INSERT INTO auth_attempts(bucket) VALUES ($1) ON CONFLICT(bucket) DO UPDATE SET attempts=auth_attempts.attempts+1 RETURNING attempts', [bucket]);
      return result.rows[0].attempts <= 10;
    },
    list: async () => (await pool.query(`SELECT ${columns} FROM photos ORDER BY created_at DESC, id LIMIT 2001`)).rows,
    insert: async photo => {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query('SELECT pg_advisory_xact_lock(726042)');
        const count = (await client.query('SELECT count(*)::integer AS count FROM photos')).rows[0].count;
        if (count >= 2000) throw Object.assign(new Error('Limite de 2 000 photos atteinte.'), { status: 409 });
        const result = await client.query(`INSERT INTO photos
          (id,filename,title,mime_type,size_bytes,width,height,sha256,visual_hash,original,thumbnail)
          VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING ${columns}`,
        [photo.id, photo.filename, photo.title, photo.mime_type, photo.size_bytes, photo.width, photo.height,
          photo.sha256, photo.visual_hash, photo.original, photo.thumbnail]);
        await client.query('COMMIT'); return result.rows[0];
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    },
    image: async (id, thumbnail) => (await pool.query(
      `SELECT ${thumbnail ? 'thumbnail' : 'original'} AS data, mime_type, filename FROM photos WHERE id=$1`, [id])).rows[0],
    update: async (id, title, description) => (await pool.query(
      `UPDATE photos SET title=$2, description=$3 WHERE id=$1 RETURNING ${columns}`, [id, title, description])).rows[0],
    delete: async id => (await pool.query('DELETE FROM photos WHERE id=$1 RETURNING id', [id])).rowCount > 0,
    stats: async () => (await pool.query(`SELECT count(*)::integer AS count,
      coalesce(sum(size_bytes),0)::double precision AS bytes,
      (SELECT coalesce(sum(total-largest),0)::double precision FROM
        (SELECT sum(size_bytes) AS total, max(size_bytes) AS largest FROM photos GROUP BY sha256 HAVING count(*)>1) d) AS reclaimable_bytes
      FROM photos`)).rows[0],
  };
}
module.exports = { createDatabase, migrate };
