const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../app');
const { hashPassword, verifyPassword } = require('../auth');

test('passwords are salted and verified with scrypt', async () => {
  const password = 'a-test-password-only-2026';
  const left = await hashPassword(password), right = await hashPassword(password);
  assert.notEqual(left, right);
  assert.equal(await verifyPassword(password, left), true);
  assert.equal(await verifyPassword('a-wrong-password-only', left), false);
  assert.equal(await verifyPassword(password, 'invalid'), false);
  await assert.rejects(hashPassword('too-short'));
});

test('HTTP origin requires explicit demo opt-in', () => {
  assert.throws(() => createApp({ auth: { publicOrigin: 'http://team5.laboinfo-ecam.be' } }), /explicit demo/);
});

test('authentication denies insecure remote login, forged origins and excessive attempts', async () => {
  const password = 'a-test-password-only-2026', hash = await hashPassword(password);
  const database = {
    list: async () => [], stats: async () => ({ count: 0 }),
    authAttempt: async () => false,
  };
  const server = createApp({ database, auth: { username: 'admin', passwordHash: hash } }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = headers => fetch(`${base}/api/auth/login`, { method: 'POST', headers: {
    Origin: base, 'Content-Type': 'application/json', ...headers,
  }, body: JSON.stringify({ username: 'admin', password }) });
  try {
    assert.equal((await request({})).status, 426);
    assert.equal((await request({ Origin: 'https://attacker.invalid' })).status, 403);
    assert.equal((await request({ 'X-Forwarded-Proto': 'https' })).status, 426);
    assert.equal((await (await fetch(`${base}/api/auth/session`)).json()).loginAllowed, false);
    assert.equal((await fetch(`${base}/api/photos`, { method: 'POST' })).status, 401);
  } finally { await new Promise(resolve => server.close(resolve)); }
  const local = createApp({ database, auth: { username: 'admin', passwordHash: hash, localHttp: true } }).listen(0, '127.0.0.1');
  await once(local, 'listening');
  try {
    const url = `http://127.0.0.1:${local.address().port}`;
    const response = await fetch(`${url}/api/auth/login`, { method: 'POST', headers: { Origin: url, 'Content-Type': 'application/json' }, body: JSON.stringify({ username: 'admin', password }) });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get('set-cookie'), null);
  } finally { await new Promise(resolve => local.close(resolve)); }
});

test('missing administrator configuration leaves reads public and denies mutations', async () => {
  const server = createApp({ database: { list: async () => [] }, env: {} }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/api/photos`)).status, 200);
    assert.equal((await fetch(`${base}/api/photos`, { method: 'POST' })).status, 401);
    const session = await (await fetch(`${base}/api/auth/session`)).json();
    assert.equal(session.configured, false);
    assert.equal(session.authenticated, false);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
