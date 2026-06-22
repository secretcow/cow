// Persistenter Spieler-Store (Profil = Wallet + Statistiken), identifiziert ueber
// den stabilen Spieler-Token. Zwei austauschbare Backends:
//   1) Upstash Redis (REST)  -> aktiv, wenn UPSTASH_REDIS_REST_URL + _TOKEN gesetzt
//      sind. Ueberlebt Render-Neustarts (geteilter Server-Speicher).
//   2) JSON-Datei (Fallback) -> lokal persistent, auf Render fluechtig. Gut zum
//      Entwickeln ohne externe DB.
// Die High-Level-API ist backend-unabhaengig und komplett async.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const STARTING_WALLET = Number(process.env.STARTING_WALLET ?? 10000);
const REFILL_TO = Number(process.env.WALLET_REFILL ?? 1000);

const UPSTASH_URL = process.env.UPSTASH_REDIS_REST_URL || '';
const UPSTASH_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN || '';

const PKEY = (token) => `kp:p:${token}`; // Profil-Schluessel
const LB_KEY = 'kp:lb:matches'; // Sorted Set: score=matchesWon, member=token

function defaultProfile(token, name) {
  return {
    token,
    name: name || 'Spieler',
    wallet: STARTING_WALLET,
    matchesWon: 0,
    handsPlayed: 0,
    handsWon: 0,
    biggestPot: 0,
    createdAt: Date.now(),
  };
}

// Verhindert dauerhaftes Aussperren: ein leeres Wallet wird auf ein Grundguthaben
// aufgefuellt (Spass-Chips, kein echtes Geld). Wird nur beim Laden angewandt,
// nicht bei gezielten Abbuchungen (sonst wuerde der Cash-Game-Buy-in sofort
// wieder aufgefuellt).
function refillIfBroke(p) {
  if (!(p.wallet > 0)) p.wallet = REFILL_TO;
  return p;
}

// ---------------- Upstash-REST-Backend ----------------
async function upstash(cmd) {
  const res = await fetch(UPSTASH_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${UPSTASH_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(cmd),
  });
  if (!res.ok) throw new Error(`Upstash ${res.status}`);
  const j = await res.json();
  return j.result;
}

const upstashBackend = {
  async getProfile(token) {
    const raw = await upstash(['GET', PKEY(token)]);
    return raw ? JSON.parse(raw) : null;
  },
  async putProfile(p) {
    await upstash(['SET', PKEY(p.token), JSON.stringify(p)]);
    await upstash(['ZADD', LB_KEY, String(p.matchesWon || 0), p.token]);
  },
  async getLeaderboard(limit) {
    const flat = (await upstash(['ZREVRANGE', LB_KEY, '0', String(limit - 1)])) || [];
    if (!flat.length) return [];
    const raws = (await upstash(['MGET', ...flat.map(PKEY)])) || [];
    return raws.map((r) => (r ? JSON.parse(r) : null)).filter(Boolean);
  },
};

// ---------------- Datei-Backend (Fallback) ----------------
class FileBackend {
  constructor(path) {
    this.path = path;
    this.data = {};
    this.saveTimer = null;
    try {
      this.data = JSON.parse(fs.readFileSync(path, 'utf8')) || {};
    } catch {
      this.data = {};
    }
  }
  scheduleSave() {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      try {
        fs.mkdirSync(dirname(this.path), { recursive: true });
        fs.writeFileSync(this.path, JSON.stringify(this.data));
      } catch (e) {
        console.error('Store-Speicherfehler:', e.message);
      }
    }, 300);
    this.saveTimer.unref?.();
  }
  async getProfile(token) {
    return this.data[token] ? { ...this.data[token] } : null;
  }
  async putProfile(p) {
    this.data[p.token] = { ...p };
    this.scheduleSave();
  }
  async getLeaderboard(limit) {
    return Object.values(this.data)
      .slice()
      .sort((a, b) => (b.matchesWon || 0) - (a.matchesWon || 0))
      .slice(0, limit)
      .map((p) => ({ ...p }));
  }
}

const usingUpstash = !!(UPSTASH_URL && UPSTASH_TOKEN);
const backend = usingUpstash
  ? upstashBackend
  : new FileBackend(process.env.DATA_FILE || join(__dirname, '..', 'data', 'profiles.json'));

export const storeInfo = {
  backend: usingUpstash ? 'upstash' : 'file',
  startingWallet: STARTING_WALLET,
  refillTo: REFILL_TO,
};

// ---------------- High-Level-API ----------------

// Laedt (oder erzeugt) ein Profil, aktualisiert optional den Namen und fuellt ein
// leeres Wallet auf. Persistiert anschliessend.
export async function loadProfile(token, name) {
  if (!token) return defaultProfile('', name);
  let p;
  try {
    p = await backend.getProfile(token);
  } catch (e) {
    console.error('Store-Ladefehler:', e.message);
    p = null;
  }
  if (!p) p = defaultProfile(token, name);
  if (name) p.name = name;
  refillIfBroke(p);
  try {
    await backend.putProfile(p);
  } catch (e) {
    console.error('Store-Schreibfehler:', e.message);
  }
  return p;
}

// Veraendert das Wallet um delta (Buy-in negativ, Cash-out positiv). Kein
// Auto-Refill – ein leeres Wallet darf nach einem Buy-in 0 sein. Clamp >= 0.
export async function adjustWallet(token, delta, name) {
  const p = (await safeGet(token)) || defaultProfile(token, name);
  if (name) p.name = name;
  p.wallet = Math.max(0, Math.round((p.wallet || 0) + delta));
  await safePut(p);
  return p;
}

export async function recordMatchWin(token, name) {
  const p = (await safeGet(token)) || defaultProfile(token, name);
  if (name) p.name = name;
  p.matchesWon = (p.matchesWon || 0) + 1;
  await safePut(p);
  return p;
}

export async function recordHandWin(token, name, potSize) {
  const p = (await safeGet(token)) || defaultProfile(token, name);
  if (name) p.name = name;
  p.handsWon = (p.handsWon || 0) + 1;
  if (potSize > (p.biggestPot || 0)) p.biggestPot = potSize;
  await safePut(p);
  return p;
}

// Schreibt die Hand-Statistik fuer einen Teilnehmer in EINEM Schreibvorgang:
// jede gespielte Hand zaehlt; gewonnene Haende erhoehen handsWon und ggf.
// biggestPot. Gibt das aktualisierte Profil zurueck.
export async function recordHandStats(token, name, { won = false, potSize = 0 } = {}) {
  const p = (await safeGet(token)) || defaultProfile(token, name);
  if (name) p.name = name;
  p.handsPlayed = (p.handsPlayed || 0) + 1;
  if (won) {
    p.handsWon = (p.handsWon || 0) + 1;
    if (potSize > (p.biggestPot || 0)) p.biggestPot = potSize;
  }
  await safePut(p);
  return p;
}

export async function getLeaderboard(limit = 10) {
  let rows = [];
  try {
    rows = await backend.getLeaderboard(limit);
  } catch (e) {
    console.error('Leaderboard-Fehler:', e.message);
  }
  return rows.map((p) => ({
    name: p.name || 'Spieler',
    matchesWon: p.matchesWon || 0,
    handsWon: p.handsWon || 0,
    wallet: p.wallet || 0,
  }));
}

async function safeGet(token) {
  try {
    return await backend.getProfile(token);
  } catch (e) {
    console.error('Store-Ladefehler:', e.message);
    return null;
  }
}
async function safePut(p) {
  try {
    await backend.putProfile(p);
  } catch (e) {
    console.error('Store-Schreibfehler:', e.message);
  }
}
