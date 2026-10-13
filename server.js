const { createApp } = require('./app');

const app = createApp();
const port = Number(process.env.PORT || 3000);
const server = app.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({ event: 'listening', port, ...app.locals.identity }));
});

process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
});
