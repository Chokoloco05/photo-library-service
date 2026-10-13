const express = require('express');
const { createIdentity } = require('./identity');

function createApp(options = {}) {
  const app = express();
  const identity = createIdentity(options);
  app.locals.identity = identity;

  app.disable('x-powered-by');
  app.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    res.on('finish', () => {
      if (req.path !== '/healthz') {
        console.log(JSON.stringify({
          pod: identity.pod, revision: identity.revision, method: req.method,
          path: req.path, status: res.statusCode,
        }));
      }
    });
    next();
  });

  app.get('/', (_req, res) => res.json({
    ...identity,
    photos: [{ id: 'demo-1', title: 'Photo de démonstration (mock)' }],
  }));
  app.get('/whoami', (_req, res) => res.type('text/plain').send(`${identity.pod}\n`));
  app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

  return app;
}

module.exports = { createApp };
