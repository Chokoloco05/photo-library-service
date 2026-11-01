const { createApp } = require('./app');
const { createDatabase } = require('./database');

const database = createDatabase();
const app = createApp({ database });
const port = Number(process.env.PORT || 3000);
let server;
async function start() {
  await database.migrate();
  server = app.listen(port, '0.0.0.0', () => {
    console.log(JSON.stringify({ event: 'listening', port, ...app.locals.identity }));
  });
}
start().catch(async error => {
  console.error(JSON.stringify({ event: 'startup_failed', code: error.code || 'unknown' }));
  await database.close(); process.exitCode = 1;
});

process.on('SIGTERM', () => {
  if (server) server.close(async () => { await database.close(); process.exit(0); });
  else database.close().finally(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
});
