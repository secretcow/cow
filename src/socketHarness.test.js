// Test-Harness: startet einen frischen Server (eigener Port, Datei-Backend,
// grosse Zug-Uhr, Keepalive aus) und fuehrt die Socket-E2E-Tests dagegen aus.
// Killt den Server am Ende. Wird von `npm test` aufgerufen, damit die Server-
// Plumbing-Tests (Reconnect, Side Pots, Emotes, Historie, Zuschauer) automatisch
// mitlaufen, ohne dass manuell ein Server gestartet werden muss.
import { spawn, spawnSync } from 'node:child_process';
import os from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const PORT = 3199;
const URL = `http://localhost:${PORT}`;
const dataFile = join(os.tmpdir(), `kp-e2e-${process.pid}.json`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitReady(tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(URL);
      if (res && (res.ok || res.status)) return true;
    } catch {}
    await sleep(100);
  }
  return false;
}

const TESTS = ['socket.test.js', 'socketMulti.test.js', 'socketFeatures.test.js'];

const srv = spawn('node', ['server.js'], {
  cwd: ROOT,
  // Grosse Zug-Uhr (keine versehentlichen Auto-Folds) und nahezu sofortiger
  // All-In-Run-out (Tests sollen nicht sekundenlang auf die Sweat-Animation
  // warten); eigener Port + Datei-Backend isolieren den Lauf.
  env: {
    ...process.env,
    PORT: String(PORT),
    DATA_FILE: dataFile,
    TURN_MS: '8000',
    RUNOUT_START_MS: '20',
    RUNOUT_STEP_MS: '20',
    RUNOUT_RIVER_MS: '20',
    KEEPALIVE_URL: '',
  },
  stdio: 'ignore',
});

(async () => {
  let failed = 0;
  try {
    if (!(await waitReady())) {
      console.error('FAIL: Test-Server nicht erreichbar auf', URL);
      failed = 1;
      return;
    }
    for (const t of TESTS) {
      console.log(`\n=== ${t} ===`);
      const r = spawnSync('node', [join('src', t)], {
        cwd: ROOT,
        env: { ...process.env, KP_TEST_URL: URL },
        stdio: 'inherit',
      });
      if (r.status !== 0) failed++;
    }
  } finally {
    srv.kill('SIGKILL');
    try {
      fs.unlinkSync(dataFile);
    } catch {}
  }
  process.exit(failed === 0 ? 0 : 1);
})();
