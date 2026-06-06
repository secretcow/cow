// Test fuer den Datei-Backend-Store (ohne externe DB). Nutzt eine temporaere
// Datei via DATA_FILE und prueft Wallet, Refill, Match-Wins und Leaderboard.
import fs from 'node:fs';
import os from 'node:os';
import { join } from 'node:path';

const tmp = join(os.tmpdir(), `kp-store-test-${Date.now()}.json`);
process.env.DATA_FILE = tmp;
process.env.STARTING_WALLET = '10000';
process.env.WALLET_REFILL = '1000';

const store = await import('./store.js');

let pass = 0;
let fail = 0;
const assert = (n, c) => {
  if (c) pass++;
  else {
    fail++;
    console.error('FAIL:', n);
  }
};

// Backend-Auswahl
assert('Datei-Backend aktiv', store.storeInfo.backend === 'file');

// Neues Profil bekommt Start-Wallet
const a = await store.loadProfile('tokA', 'Anna');
assert('neues Profil Start-Wallet', a.wallet === 10000);
assert('neues Profil Name', a.name === 'Anna');
assert('neues Profil 0 Matches', a.matchesWon === 0);

// Wallet abbuchen (Buy-in) – kein Auto-Refill
const a2 = await store.adjustWallet('tokA', -10000, 'Anna');
assert('Wallet auf 0 nach Buy-in', a2.wallet === 0);

// Erneutes Laden fuellt leeres Wallet auf
const a3 = await store.loadProfile('tokA', 'Anna');
assert('Refill bei leerem Wallet', a3.wallet === 1000);

// Cash-out addiert zurueck
const a4 = await store.adjustWallet('tokA', 500, 'Anna');
assert('Cash-out addiert', a4.wallet === 1500);

// Match-Wins zaehlen
await store.recordMatchWin('tokA', 'Anna');
await store.recordMatchWin('tokA', 'Anna');
await store.loadProfile('tokB', 'Ben');
await store.recordMatchWin('tokB', 'Ben');

const lb = await store.getLeaderboard(10);
assert('Leaderboard hat 2 Eintraege', lb.length === 2);
assert('Anna fuehrt mit 2 Matches', lb[0].name === 'Anna' && lb[0].matchesWon === 2);
assert('Ben zweiter mit 1 Match', lb[1].name === 'Ben' && lb[1].matchesWon === 1);

// Persistenz: Datei wurde geschrieben (debounced -> kurz warten)
await new Promise((r) => setTimeout(r, 400));
assert('Datei existiert', fs.existsSync(tmp));
const onDisk = JSON.parse(fs.readFileSync(tmp, 'utf8'));
assert('Datei enthaelt tokA', !!onDisk.tokA);

// Aufraeumen
try {
  fs.unlinkSync(tmp);
} catch {}

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
