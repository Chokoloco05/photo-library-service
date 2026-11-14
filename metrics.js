const http = require('node:http');
const { Registry, Counter, Gauge, Histogram, collectDefaultMetrics } = require('@prometheus-io/client');

const routes = new Set([
  '/', '/index.html', '/api/info', '/whoami', '/healthz', '/readyz',
  '/api/auth/session', '/api/auth/login', '/api/auth/logout',
  '/api/photos', '/api/photos/:id', '/api/photos/:id/image', '/api/photos/:id/download',
  '/api/stats', '/api/duplicates', '/api/similar',
]);
const assets = new Set(['/style.css', '/library.js', '/favicon.ico']);

function routeLabel(path) {
  const normalized = path.replace(/^\/api\/photos\/[^/]+/, '/api/photos/:id');
  if (routes.has(normalized)) return normalized;
  return assets.has(path) ? 'static' : 'unmatched';
}

function createMetrics(identity, database) {
  const registry = new Registry();
  registry.setDefaultLabels({ environment: identity.environment, pod: identity.pod });
  collectDefaultMetrics({ register: registry, prefix: 'photo_' });
  const requests = new Counter({
    name: 'photo_http_requests_total',
    help: 'Completed HTTP requests, with 499 for a connection closed before completion.',
    labelNames: ['method', 'route', 'status_code'], registers: [registry],
  });
  const duration = new Histogram({
    name: 'photo_http_request_duration_seconds', help: 'HTTP request duration in seconds.',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10], registers: [registry],
  });
  const active = new Gauge({
    name: 'photo_http_requests_active', help: 'HTTP requests currently in progress.', registers: [registry],
  });
  active.set(0);
  new Gauge({
    name: 'photo_app_info', help: 'Application version and source revision.',
    labelNames: ['version', 'revision'], registers: [registry],
  }).set({ version: identity.version, revision: identity.revision }, 1);
  new Gauge({
    name: 'photo_database_up', help: 'Whether this instance can query PostgreSQL within two seconds.',
    registers: [registry],
    async collect() {
      let timer;
      try {
        if (!database) throw new Error('Database unavailable');
        await Promise.race([
          database.ready(),
          new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error('Database check timeout')), 2000);
            timer.unref();
          }),
        ]);
        this.set(1);
      } catch {
        this.set(0);
      } finally {
        clearTimeout(timer);
      }
    },
  });

  function middleware(req, res, next) {
    const started = process.hrtime.bigint();
    const route = routeLabel(req.path);
    const method = ['GET', 'HEAD', 'POST', 'PATCH', 'DELETE', 'PUT', 'OPTIONS'].includes(req.method) ? req.method : 'OTHER';
    let recorded = false;
    active.inc();
    function record(status) {
      if (recorded) return;
      recorded = true;
      const labels = { method, route, status_code: String(status) };
      requests.inc(labels);
      duration.observe(labels, Number(process.hrtime.bigint() - started) / 1e9);
      active.dec();
    }
    res.once('finish', () => record(res.statusCode));
    res.once('close', () => record(res.writableFinished ? res.statusCode : 499));
    next();
  }
  return { registry, middleware };
}

function createMetricsServer(metrics) {
  return http.createServer(async (req, res) => {
    if (req.method !== 'GET' || req.url !== '/metrics') {
      res.writeHead(404).end();
      return;
    }
    try {
      const body = await metrics.registry.metrics();
      res.writeHead(200, { 'Content-Type': metrics.registry.contentType, 'Cache-Control': 'no-store' }).end(body);
    } catch {
      res.writeHead(503).end('Metrics unavailable');
    }
  });
}

module.exports = { createMetrics, createMetricsServer };
