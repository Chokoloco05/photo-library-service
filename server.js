const { createApp } = require('./app');
const { createDatabase } = require('./database');
const { createMetricsServer } = require('./metrics');

const database = createDatabase();
const app = createApp({ database });
const port = Number(process.env.PORT || 3000);
let server;
let metricsServer;
async function start() {
  await database.migrate();
  metricsServer = createMetricsServer(app.locals.metrics);
  await new Promise((resolve, reject) => {
    metricsServer.once('error', reject);
    metricsServer.listen(Number(process.env.METRICS_PORT || 9090), '0.0.0.0', resolve);
  });
  server = app.listen(port, '0.0.0.0', () => {
    console.log(JSON.stringify({ event: 'listening', port, ...app.locals.identity }));
  });
}
start().catch(async error => {
  console.error(JSON.stringify({ event: 'startup_failed', code: error.code || 'unknown' }));
  if (metricsServer) metricsServer.close();
  await database.close(); process.exitCode = 1;
});

process.on('SIGTERM', async () => {
  setTimeout(() => process.exit(1), 10000).unref();
  await Promise.all([server, metricsServer].filter(Boolean).map(listener =>
    new Promise(resolve => listener.close(resolve))));
  await database.close();
  process.exit(0);
});
