const express = require('express');
const { createIdentity } = require('./identity');
const path = require('node:path');
const { readFileSync } = require('node:fs');
const { analyze, duplicates, similar, MAX_BYTES } = require('./photos');
const { createAuth } = require('./auth');

function createApp(options = {}) {
  const app = express();
  const identity = createIdentity(options);
  app.locals.identity = identity;
  const database = options.database;
  const basePath = (options.basePath ?? (options.env || process.env).APP_BASE_PATH ?? '').replace(/\/$/, '');
  if (basePath && !/^\/[a-zA-Z0-9/_-]+$/.test(basePath)) throw new Error('Invalid APP_BASE_PATH');
  if ((options.env || process.env).AUTH_TRUST_PROXY === 'true') app.set('trust proxy', 1);
  const auth = createAuth({ database, basePath, env: options.env || process.env, config: options.auth });
  const html = readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf8')
    .replace('<base href="/">', `<base href="${basePath}/">`);
  let uploads = 0;

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

  app.use((_req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'same-origin');
    res.set('Content-Security-Policy', "default-src 'self'; img-src 'self' blob:; style-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'");
    next();
  });
  app.get('/api/info', (_req, res) => res.json(identity));
  // Preserve the JSON identity used by the first two milestones' curl checks.
  app.get('/', (req, res) => {
    if (!req.accepts('html') || !String(req.get('accept') || '').includes('text/html')) return res.json({ ...identity, photos: [] });
    res.type('html').send(html);
  });
  app.get('/index.html', (_req, res) => res.type('html').send(html));
  app.use(express.static(path.join(__dirname, 'public'), { index: false }));
  app.get('/whoami', (_req, res) => res.type('text/plain').send(`${identity.pod}\n`));
  app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));
  app.get('/readyz', async (_req, res) => {
    try { if (!database) throw new Error('No database'); await database.ready(); res.json({ status: 'ok' }); }
    catch { res.status(503).json({ error: 'Base de données indisponible.' }); }
  });
  app.use('/api', (req, res, next) => {
    if (!database) return res.status(503).json({ error: 'Base de données indisponible.' });
    if (['POST', 'PATCH', 'DELETE'].includes(req.method) && req.get('origin')) {
      try { if (new URL(req.get('origin')).host !== req.get('host')) return res.status(403).json({ error: 'Origine non autorisée.' }); }
      catch { return res.status(403).json({ error: 'Origine non autorisée.' }); }
    }
    next();
  });
  app.get('/api/auth/session', auth.status);
  app.post('/api/auth/login', auth.sameOrigin, express.json({ limit: '2kb' }), auth.login);
  app.post('/api/auth/logout', auth.requireWrite, auth.logout);
  // All library mutations are protected before parsing upload bodies or invoking SQL.
  app.use('/api', (req, res, next) => ['GET', 'HEAD', 'OPTIONS'].includes(req.method)
    ? next() : auth.requireWrite(req, res, next));
  const list = async () => {
    const photos = await database.list();
    if (photos.length > 2000) throw Object.assign(new Error('Cette version prend en charge 2 000 photos maximum. Réduis la bibliothèque avant une nouvelle analyse.'), { status: 409 });
    return photos;
  };
  app.get('/api/photos', async (_req, res) => res.json({ photos: await list() }));
  app.get('/api/stats', async (_req, res) => res.json(await database.stats()));
  app.get('/api/duplicates', async (_req, res) => res.json({ groups: duplicates(await list()) }));
  app.get('/api/similar', async (_req, res) => res.json({ pairs: similar(await list()) }));
  app.post('/api/photos', (req, res, next) => {
    if (uploads >= 2) return res.status(429).json({ error: 'Deux imports sont en cours. Réessaie dans quelques secondes.' });
    uploads++;
    let released = false;
    const release = () => { if (!released) { uploads--; released = true; } };
    res.once('finish', release); res.once('close', release);
    next();
  }, express.raw({ type: ['image/jpeg', 'image/png', 'image/webp'], limit: MAX_BYTES }), async (req, res) => {
    if ((await database.stats()).count >= 2000) return res.status(409).json({ error: 'Limite de 2 000 photos atteinte.' });
    let filename;
    try { filename = decodeURIComponent(req.get('x-filename') || 'photo'); }
    catch { return res.status(400).json({ error: 'Nom de fichier invalide.' }); }
    const photo = await analyze(req.body, filename);
    res.status(201).json(await database.insert(photo));
  });
  app.param('id', (req, res, next, id) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
    ? next() : res.status(400).json({ error: 'Identifiant de photo invalide.' }));
  app.get('/api/photos/:id/image', async (req, res) => {
    const thumbnail = req.query.thumbnail === '1';
    const photo = await database.image(req.params.id, thumbnail);
    if (!photo) return res.status(404).json({ error: 'Photo introuvable.' });
    res.type(thumbnail ? 'image/webp' : photo.mime_type).send(photo.data);
  });
  app.get('/api/photos/:id/download', async (req, res) => {
    const photo = await database.image(req.params.id, false);
    if (!photo) return res.status(404).json({ error: 'Photo introuvable.' });
    res.attachment(photo.filename).type(photo.mime_type).send(photo.data);
  });
  app.patch('/api/photos/:id', express.json({ limit: '8kb' }), async (req, res) => {
    const { title, description = '' } = req.body || {};
    if (typeof title !== 'string' || !title.trim() || title.trim().length > 200 || typeof description !== 'string' || description.length > 1000)
      return res.status(400).json({ error: 'Titre requis (200 caractères maximum), description de 1 000 caractères maximum.' });
    const photo = await database.update(req.params.id, title.trim(), description);
    if (!photo) return res.status(404).json({ error: 'Photo introuvable.' });
    res.json(photo);
  });
  app.delete('/api/photos/:id', async (req, res) => {
    if (!await database.delete(req.params.id)) return res.status(404).json({ error: 'Photo introuvable.' });
    res.status(204).end();
  });
  app.use((error, _req, res, _next) => {
    const status = error.type === 'entity.too.large' ? 413 : error.status || 500;
    if (status >= 500) console.error(JSON.stringify({ event: 'request_failed', code: error.code || 'unknown' }));
    res.status(status).json({ error: status === 413 ? 'La limite est de 10 Mo par photo.' : status >= 500 ? 'Service indisponible. Réessaie dans quelques instants.' : error.message });
  });

  if (!basePath) return app;
  const mounted = express();
  mounted.disable('x-powered-by');
  mounted.locals.identity = identity;
  mounted.use(basePath, app);
  return mounted;
}

module.exports = { createApp };
