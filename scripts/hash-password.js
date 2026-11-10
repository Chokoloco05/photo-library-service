// Input is JSON on stdin, never a password argument or a persisted plaintext file.
const { readFileSync } = require('node:fs');
const { hashPassword } = require('../auth');
hashPassword(JSON.parse(readFileSync(0, 'utf8')).password)
  .then(hash => process.stdout.write(hash))
  .catch(() => { console.error('Mot de passe invalide : au moins 14 caractères, au plus 256 octets.'); process.exitCode = 1; });
