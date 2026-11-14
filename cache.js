const { createClient } = require('redis');

function createCache({ env = process.env, client, ttlSeconds = 15, timeoutMs = 200 } = {}) {
  const enabled = Boolean(client || env.REDIS_HOST || env.REDIS_URL);
  const connection = client || (enabled ? createClient({
    url: env.REDIS_URL,
    password: env.REDIS_PASSWORD,
    socket: { host: env.REDIS_HOST, connectTimeout: 500, reconnectStrategy: retries => Math.min(100 * (retries + 1), 2000) },
    disableOfflineQueue: true,
    commandsQueueMaxLength: 100,
  }) : undefined);
  const stats = { hit: 0, miss: 0, error: 0, bypass: 0 };
  const prefix = `photo:${env.APP_ENV || 'dev'}:v1`;
  if (connection) {
    connection.on('error', () => {}); // Request fallback and metrics report cache availability.
    if (!client) connection.connect().catch(() => {});
  }

  async function bounded(operation) {
    let timer;
    try {
      return await Promise.race([operation, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('Cache timeout')), timeoutMs);
        timer.unref();
      })]);
    } finally { clearTimeout(timer); }
  }
  return {
    stats,
    isReady: () => Boolean(connection?.isReady),
    close: () => { if (connection?.isOpen) connection.destroy(); },
    async read(key, revision, load) {
      if (!connection?.isReady) { stats.bypass++; return load(); }
      const version = await revision();
      const cacheKey = `${prefix}:${version}:${key}`;
      try {
        const value = await bounded(connection.get(cacheKey));
        if (value !== null) {
          const result = JSON.parse(value);
          stats.hit++;
          return result;
        }
      } catch {
        stats.error++;
        stats.bypass++;
        return load();
      }
      stats.miss++;
      const value = await load();
      try { await bounded(connection.set(cacheKey, JSON.stringify(value), { EX: ttlSeconds })); }
      catch { stats.error++; }
      return value;
    },
  };
}

module.exports = { createCache };
