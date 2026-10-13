const os = require('node:os');
const { version: packageVersion } = require('./package.json');

function createIdentity({ env = process.env, hostname = os.hostname(), version = packageVersion } = {}) {
  return {
    service: 'photo-service',
    version: `v${version}`,
    revision: env.APP_REVISION || 'local',
    hostname,
    pod: env.POD_NAME || hostname,
    podUid: env.POD_UID || 'local',
    environment: env.APP_ENV || 'local',
  };
}

module.exports = { createIdentity };
