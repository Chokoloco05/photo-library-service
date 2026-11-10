const { randomBytes, createHash, scrypt, timingSafeEqual } = require('node:crypto');
const { promisify } = require('node:util');
const derive = promisify(scrypt);
const digest = value => createHash('sha256').update(value).digest('hex');
const HASH_PATTERN = /^scrypt\$65536\$8\$2\$([a-f0-9]{32})\$([a-f0-9]{128})$/;
const TTL = 8 * 60 * 60;

async function hashPassword(password) {
  if (typeof password !== 'string' || password.length < 14 || Buffer.byteLength(password) > 256)
    throw new Error('Le mot de passe doit contenir au moins 14 caractères et au plus 256 octets.');
  const salt = randomBytes(16).toString('hex');
  const key = await derive(password, salt, 64, { N: 65536, r: 8, p: 2, maxmem: 96 * 1024 * 1024 });
  return `scrypt$65536$8$2$${salt}$${key.toString('hex')}`;
}
async function verifyPassword(password, encoded) {
  const match = HASH_PATTERN.exec(encoded || '');
  if (!match || typeof password !== 'string' || Buffer.byteLength(password) > 256) return false;
  const actual = await derive(password, match[1], 64, { N: 65536, r: 8, p: 2, maxmem: 96 * 1024 * 1024 });
  return timingSafeEqual(actual, Buffer.from(match[2], 'hex'));
}
function createAuth({ database, basePath, env = process.env, config = {} }) {
  const username = config.username ?? env.AUTH_ADMIN_USER ?? '';
  const passwordHash = config.passwordHash ?? env.AUTH_ADMIN_PASSWORD_HASH ?? '';
  const configured = /^[a-zA-Z0-9_.-]{1,64}$/.test(username) && HASH_PATTERN.test(passwordHash);
  const credentialId = digest(`${username}:${passwordHash}`);
  const localHttp = config.localHttp ?? env.AUTH_ALLOW_LOCAL_HTTP === 'true';
  const demoHttp = config.demoHttp ?? env.AUTH_ALLOW_DEMO_HTTP === 'true';
  const publicOrigin = config.publicOrigin ?? env.AUTH_PUBLIC_ORIGIN ?? '';
  if (publicOrigin && new URL(publicOrigin).origin !== publicOrigin) throw new Error('Invalid AUTH_PUBLIC_ORIGIN');
  if (publicOrigin && !publicOrigin.startsWith('https://') && !(demoHttp && publicOrigin.startsWith('http://')))
    throw new Error('HTTP requires explicit demo mode');
  const name = `clair_${basePath.replace(/\W/g, '_') || 'prod'}_session`;
  const path = basePath || '/';
  let verifying = false;
  const isLocal = req => localHttp && /^(localhost|127\.0\.0\.1|\[::1\]|[a-z0-9-]+\.localhost)$/.test(req.hostname);
  const isDemo = req => demoHttp && publicOrigin.startsWith('http://') && `${req.protocol}://${req.get('host')}` === publicOrigin;
  const transport = req => req.secure || isLocal(req) || isDemo(req);
  function sameOrigin(req, res, next) {
    const expected = publicOrigin || `${req.secure ? 'https' : 'http'}://${req.get('host')}`;
    if (req.get('origin') !== expected || req.get('sec-fetch-site') === 'cross-site')
      return res.status(403).json({ error: 'Origine non autorisée.' });
    next();
  }
  const token = req => {
    const cookies = (req.get('cookie') || '').split(';').map(value => value.trim().split('='));
    const values = cookies.filter(([key]) => key === name);
    return values.length === 1 && /^[a-f0-9]{64}$/.test(values[0][1] || '') ? values[0][1] : '';
  };
  const cookieOptions = req => ({ httpOnly: true, secure: req.secure || !(isLocal(req) || isDemo(req)), sameSite: 'strict', path });
  async function session(req) {
    const value = token(req);
    if (!configured || !value || !transport(req)) return null;
    return database.authSession(digest(value), credentialId);
  }
  async function status(req, res) {
    const current = await session(req);
    res.json({ authenticated: !!current, username: current ? username : null,
      csrfToken: current?.csrf_token || null, configured, loginAllowed: configured && transport(req), demoHttp: isDemo(req) });
  }
  async function login(req, res) {
    if (!configured) return res.status(503).json({ error: 'Compte administrateur non configuré. La bibliothèque reste en lecture seule.' });
    if (!transport(req)) return res.status(426).json({ error: 'Une connexion HTTPS est nécessaire pour se connecter.' });
    const { username: supplied, password } = req.body || {};
    if (typeof supplied !== 'string' || typeof password !== 'string' || supplied.length > 64 || Buffer.byteLength(password) > 256)
      return res.status(400).json({ error: 'Identifiants invalides.' });
    if (verifying) return res.status(429).set('Retry-After', '2').json({ error: 'Connexion en cours. Réessaie dans quelques secondes.' });
    // One shared budget per account and fixed 15-minute window, across every replica.
    const window = Math.floor(Date.now() / 900000);
    if (!await database.authAttempt(`${credentialId}:${window}`))
      return res.status(429).set('Retry-After', '900').json({ error: 'Trop de tentatives. Réessaie dans 15 minutes.' });
    verifying = true;
    let valid;
    try { valid = await verifyPassword(password, passwordHash); } finally { verifying = false; }
    if (!valid || supplied !== username) return res.status(401).json({ error: 'Identifiant ou mot de passe incorrect.' });
    const value = randomBytes(32).toString('hex'), csrf = randomBytes(32).toString('hex');
    // Replace this browser's previous session instead of keeping a fixed session ID.
    if (token(req)) await database.authDelete(digest(token(req)));
    await database.authCreate(digest(value), csrf, credentialId, TTL);
    res.cookie(name, value, { ...cookieOptions(req), maxAge: TTL * 1000 });
    res.json({ authenticated: true, username, csrfToken: csrf, configured: true, loginAllowed: true, demoHttp: isDemo(req) });
  }
  async function requireWrite(req, res, next) {
    const current = await session(req);
    if (!current) return res.status(401).json({ error: 'Connecte-toi pour ajouter, modifier ou supprimer des photos.' });
    if (!req.get('x-csrf-token') || req.get('x-csrf-token') !== current.csrf_token)
      return res.status(403).json({ error: 'Session invalide. Actualise la page puis réessaie.' });
    sameOrigin(req, res, next);
  }
  async function logout(req, res) {
    await database.authDelete(digest(token(req)));
    res.clearCookie(name, cookieOptions(req));
    res.status(204).end();
  }
  return { status, login, logout, requireWrite, sameOrigin };
}
module.exports = { createAuth, hashPassword, verifyPassword };
