const http = require('node:http');
const { spawn } = require('node:child_process');
const { writeFile, mkdir } = require('node:fs/promises');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');

function probe(pathname) {
  return new Promise((resolve, reject) => {
    const request = http.get({ hostname: '127.0.0.1', port: 80, path: pathname,
      headers: { Host: 'prod.localhost', Connection: 'close' } }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('error', reject);
      response.on('end', () => {
        try { resolve({ statusCode: response.statusCode, payload: JSON.parse(Buffer.concat(chunks)) }); }
        catch { reject(new Error(`HTTP ${response.statusCode}, invalid JSON`)); }
      });
    });
    request.setTimeout(2000, () => request.destroy(new Error('HTTP timeout')));
    request.on('error', reject);
  });
}

function runCommand(args) {
  return new Promise((resolve, reject) => {
    const child = spawn('kubectl', ['--context', 'docker-desktop', '-n', 'prod', ...args], {
      stdio: 'inherit', windowsHide: true,
    });
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`kubectl exited with ${code}`)));
  });
}

async function measureRollout({ manifest, evidence, expectedRevision, command = runCommand, request = probe, intervalMs = 200 }) {
  const started = Date.now();
  const result = { startedAtUtc: new Date(started).toISOString(), expectedRevision,
    requests: 0, errors: 0, maxLatencyMs: 0, observedRevisions: [], failures: [] };
  const revisions = new Set();
  let lastInfo;
  async function sample() {
    for (const pathname of ['/api/info', '/readyz']) {
      const before = Date.now();
      result.requests++;
      try {
        const response = await request(pathname);
        if (response.statusCode !== 200) throw new Error(`HTTP ${response.statusCode}`);
        if (pathname === '/api/info') {
          if (response.payload.environment !== 'prod' || typeof response.payload.revision !== 'string') throw new Error('Invalid Production identity');
          lastInfo = response.payload;
          revisions.add(lastInfo.revision);
        } else if (response.payload.status !== 'ok') throw new Error('Database readiness failed');
      } catch (error) {
        result.errors++;
        if (result.failures.length < 20) result.failures.push({ path: pathname, message: error.message });
      }
      result.maxLatencyMs = Math.max(result.maxLatencyMs, Date.now() - before);
    }
  }
  let running = true;
  let monitoring;
  let failure;
  try {
    await sample();
    if (result.errors) throw new Error('Production baseline is unavailable');
    monitoring = (async () => {
      while (running) { await sample(); await delay(intervalMs); }
    })();
    await command(['apply', '-f', manifest, '--request-timeout=20s']);
    await command(['rollout', 'status', 'deployment/photo-service', '--timeout=300s']);
    for (let attempt = 0; attempt < 15; attempt++) {
      await sample();
      if (lastInfo?.revision === expectedRevision) break;
      await delay(2000);
    }
    if (lastInfo?.revision !== expectedRevision) throw new Error('Production did not converge to the validated revision');
  } catch (error) { failure = error; }
  finally {
    running = false;
    await monitoring;
    result.observedRevisions = [...revisions];
    result.durationSeconds = (Date.now() - started) / 1000;
    result.passed = !failure && result.errors === 0;
    if (failure) result.failure = failure.message;
    await mkdir(path.dirname(evidence), { recursive: true });
    await writeFile(evidence, JSON.stringify(result, null, 2) + '\n');
  }
  if (failure) throw failure;
  if (result.errors) throw new Error(`Rollout recorded ${result.errors} failed HTTP requests`);
  return result;
}

if (require.main === module) {
  const [manifest, evidence, expectedRevision] = process.argv.slice(2);
  if (!manifest || !evidence || !/^([a-f0-9]{40}|local-\d{14})$/.test(expectedRevision || '')) {
    console.error('Expected manifest path, evidence path and revision.');
    process.exitCode = 1;
  } else measureRollout({ manifest, evidence, expectedRevision }).then(result => {
    console.log(`Production rollout: ${result.requests} HTTP requests, ${result.errors} errors.`);
  }).catch(error => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { measureRollout };
