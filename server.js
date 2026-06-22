import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Table } from './src/poker.js';
import {
  loadProfile,
  adjustWallet,
  recordMatchWin,
  recordHandStats,
  getLeaderboard,
  storeInfo,
} from './src/store.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

const app = express();
app.use(express.static(join(__dirname, 'public')));

const httpServer = createServer(app);
const io = new Server(httpServer, {
  // Toleranter bei kurzen Netzaussetzern (Mobilfunk, WLAN-Wechsel): erst nach
  // 60 s ohne Pong gilt die Verbindung als tot statt nach den Default-20 s.
  pingInterval: 25000,
  pingTimeout: 60000,
  // Stellt die Session nach einem kurzen Verbindungsabriss transparent wieder
  // her und liefert verpasste Events nach – der Spieler bemerkt das Flackern oft
  // gar nicht und bleibt im selben Raum/Sitz.
  connectionStateRecovery: {
    maxDisconnectionDuration: 2 * 60 * 1000,
    skipMiddlewares: true,
  },
});

// Ring-Puffer der letzten Fehler – fuer schnelle Ferndiagnose ueber /healthz,
// ohne ins Hoster-Dashboard zu muessen. Zentrale Stelle fuer alle Fehlerpfade.
const recentErrors = [];
const MAX_RECENT_ERRORS = 25;
let errorCount = 0;
function logError(label, e) {
  errorCount += 1;
  const message = e?.stack || e?.message || String(e);
  recentErrors.push({ ts: new Date().toISOString(), label, message: message.slice(0, 600) });
  if (recentErrors.length > MAX_RECENT_ERRORS) recentErrors.shift();
  console.error(`[${label}]`, message);
}

// Letztes Sicherheitsnetz: Ein einzelner Bug (z. B. in der Engine, in einem
// Timer-Callback oder einer vergessenen Promise) darf NIE den ganzen Prozess
// killen – sonst fliegen ALLE Tische gleichzeitig raus ("Spiel abgestuerzt").
// Stattdessen loggen und weiterlaufen; der betroffene Tisch erholt sich beim
// naechsten Event oder wird per TTL aufgeraeumt.
process.on('uncaughtException', (e) => logError('uncaughtException', e));
process.on('unhandledRejection', (e) => logError('unhandledRejection', e));

// Wrapper fuer Socket-Handler: faengt synchrone Fehler UND abgelehnte Promises
// pro Event ab, damit der Fehler eines Spielers nicht die anderen am Tisch
// (oder den ganzen Server) mitreisst.
function guard(label, fn) {
  return (...args) => {
    try {
      const r = fn(...args);
      if (r && typeof r.then === 'function') {
        r.catch((e) => logError(`handler:${label}`, e));
      }
      return r;
    } catch (e) {
      logError(`handler:${label}`, e);
    }
  };
}

// Health-Endpoint fuer Uptime-Checks / Keepalive + schnelle Ferndiagnose.
app.get('/healthz', (_req, res) => {
  let players = 0;
  let connected = 0;
  let tablesRunning = 0;
  for (const room of rooms.values()) {
    players += room.players.length;
    connected += room.players.filter((p) => p.connected).length;
    if (room.table) tablesRunning += 1;
  }
  const mem = process.memoryUsage();
  res.json({
    ok: true,
    uptime: Math.round(process.uptime()),
    store: storeInfo.backend,
    rooms: rooms.size,
    tablesRunning,
    players,
    connected,
    rssMB: Math.round(mem.rss / 1048576),
    heapMB: Math.round(mem.heapUsed / 1048576),
    errorCount,
    recentErrors,
  });
});

// Leaderboard (Top-Spieler nach gewonnenen Matches).
app.get('/api/leaderboard', async (_req, res) => {
  try {
    res.json({ ok: true, top: await getLeaderboard(10) });
  } catch {
    res.json({ ok: false, top: [] });
  }
});

// Eigenes Profil (Wallet + Stats) anhand des Tokens.
app.get('/api/profile', async (req, res) => {
  const token = (req.query.token || '').toString();
  if (!token) return res.json({ ok: false });
  const p = await loadProfile(token);
  res.json({ ok: true, profile: publicProfile(p) });
});

/**
 * Raum: { code, players: Seat[], table, cleanupTimer }
 * Seat: { token, name, socketId, connected }
 * Spieler werden ueber einen stabilen Token identifiziert (nicht die socket.id),
 * damit ein Reconnect denselben Sitzplatz wiederfindet.
 */
const rooms = new Map();
const ROOM_TTL_MS = Number(process.env.ROOM_TTL_MS ?? 10 * 60 * 1000); // Raum nach 10 Min. ohne Verbindung loeschen
// All-In-"Sweat": Karten kommen langsam und einzeln rein (TV-Poker-Spannung).
const RUNOUT_START_MS = Number(process.env.RUNOUT_START_MS ?? 1800); // Pause, um die aufgedeckten Hände zu lesen
const RUNOUT_STEP_MS = Number(process.env.RUNOUT_STEP_MS ?? 1200); // Takt pro Gemeinschaftskarte
const RUNOUT_RIVER_MS = Number(process.env.RUNOUT_RIVER_MS ?? 2400); // extra Spannung vor der letzten Karte
const CHAT_HISTORY = 60; // gespeicherte Chat-Nachrichten pro Raum
// Schonfrist, bevor ein getrennter Spieler, der am Zug ist, automatisch
// checkt/foldet. Verhindert, dass die Hand bei Verbindungsverlust ewig haengt,
// gibt aber Zeit fuer einen kurzen Reconnect.
const DISCONNECT_GRACE_MS = Number(process.env.DISCONNECT_GRACE_MS ?? 30000);
// Bedenkzeit fuer verbundene Spieler am Zug. Laeuft die Zeit ab, wird automatisch
// gecheckt (sonst gefoldet) – verhindert, dass ein Tisch ewig auf jemanden wartet.
// Grosszuegig gewaehlt (Freundesrunde); per Env anpassbar, 0 schaltet es ab.
const TURN_MS = Number(process.env.TURN_MS ?? 40000);

function makeCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code;
  do {
    code = Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
  } while (rooms.has(code));
  return code;
}

function cleanName(name) {
  const n = (name || '').toString().trim().slice(0, 16);
  return n || 'Spieler';
}

function clampMaxPlayers(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return 6;
  return Math.max(2, Math.min(6, n));
}

const STACK_PRESETS = [500, 1000, 2000, 5000];
function clampStack(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return 1000;
  // Auf das naechstgelegene Preset einrasten (Lobby bietet feste Stufen an).
  return STACK_PRESETS.reduce((best, p) => (Math.abs(p - n) < Math.abs(best - n) ? p : best), 1000);
}

const LEVEL_HANDS_PRESETS = [4, 6, 8, 10];
function clampLevelHands(v) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return 6;
  return LEVEL_HANDS_PRESETS.reduce((best, p) => (Math.abs(p - n) < Math.abs(best - n) ? p : best), 6);
}

function lobbyState(room, forToken) {
  const connectedCount = room.players.filter((p) => p.connected).length;
  return {
    code: room.code,
    maxPlayers: room.maxPlayers,
    flush: room.flush,
    startingStack: room.startingStack,
    tournament: room.tournament,
    levelHands: room.levelHands,
    cash: room.cash,
    started: !!room.table,
    players: room.players.map((p, i) => ({
      name: p.name,
      connected: p.connected,
      isHost: i === 0,
    })),
    youAreHost: room.players[0]?.token === forToken,
    canStart: !room.table && connectedCount >= 2,
  };
}

function broadcast(room) {
  const now = Date.now();
  const turnMsLeft =
    room.turnDeadline && room.table && room.table.toAct !== null
      ? Math.max(0, room.turnDeadline - now)
      : null;
  for (const p of room.players) {
    if (!p.connected) continue;
    if (room.table) {
      const v = room.table.view(p.token);
      // Zug-Uhr fuer den Countdown-Ring (nur fuer den Spieler am Zug relevant).
      v.turnMsLeft = turnMsLeft;
      v.turnTotalMs = turnMsLeft != null ? room.turnTotalMs || null : null;
      io.to(p.socketId).emit('state', v);
    }
    // Das Lobby-Paket (Roster/Einstellungen) aendert sich waehrend einer Hand
    // praktisch nie – nur senden, wenn sich der Inhalt ODER der Socket (Reconnect)
    // geaendert hat. Spart bei jeder Poker-Aktion ein redundantes Paket pro Spieler.
    const lob = lobbyState(room, p.token);
    const json = JSON.stringify(lob);
    const c = p._lobbyCache;
    if (!c || c.socketId !== p.socketId || c.json !== json) {
      p._lobbyCache = { socketId: p.socketId, json };
      io.to(p.socketId).emit('lobby', lob);
    }
  }
  recordHandIfOver(room);
  checkMatchOver(room);
}

function publicProfile(p) {
  return {
    name: p.name,
    wallet: p.wallet || 0,
    matchesWon: p.matchesWon || 0,
    handsPlayed: p.handsPlayed || 0,
    handsWon: p.handsWon || 0,
    biggestPot: p.biggestPot || 0,
  };
}

// Laedt das Profil (Wallet+Stats) und schickt es an den Socket.
async function sendProfile(socket, token, name) {
  if (!token) return;
  try {
    const p = await loadProfile(token, name);
    socket.emit('profile', publicProfile(p));
  } catch (e) {
    logError('sendProfile', e);
  }
}

// ---------------- Cash-Game: Buy-in / Cash-out ----------------

// Bucht den Buy-in vom Wallet ab. Prueft vorher die Deckung. Markiert den Sitz
// als eingekauft, damit der Cash-out spaeter weiss, dass Chips zurueckgehen.
async function takeBuyIn(seat, amount) {
  if (!(amount > 0)) return { ok: true };
  const p = await loadProfile(seat.token, seat.name);
  if ((p.wallet || 0) < amount) return { error: 'Nicht genug Guthaben fuer den Buy-in.' };
  await adjustWallet(seat.token, -amount, seat.name);
  seat.boughtIn = true;
  seat.buyIn = amount;
  seat.cashedOut = false;
  return { ok: true };
}

// Schreibt die aktuellen Chips eines Sitzes zurueck aufs Wallet (genau einmal).
// Vor Spielstart ist das der gezahlte Buy-in, danach der aktuelle Engine-Stack.
function cashOutSeat(room, seat) {
  if (!room.cash || !seat.boughtIn || seat.cashedOut) return;
  seat.cashedOut = true;
  const chips = room.table ? room.table.stackOf(seat.token) : seat.buyIn || 0;
  if (room.table) {
    const pl = room.table.players.find((p) => p.id === seat.token);
    if (pl) pl.stack = 0; // Chips verlassen den Tisch
  }
  if (chips > 0) {
    adjustWallet(seat.token, chips, seat.name).catch((e) =>
      console.error('cashOut:', e.message)
    );
  }
}

// Raum endgueltig schliessen: im Cash-Game alle verbliebenen Chips auszahlen.
function destroyRoom(room) {
  if (room.cash) for (const seat of room.players) cashOutSeat(room, seat);
  cancelCleanup(room);
  if (room.autoActTimer) {
    clearTimeout(room.autoActTimer);
    room.autoActTimer = null;
  }
  if (room.runoutTimer) {
    clearTimeout(room.runoutTimer);
    room.runoutTimer = null;
  }
  rooms.delete(room.code);
}

// Erkennt das Ende einer Hand und schreibt jedem Teilnehmer genau einmal die
// Hand-Statistik gut (gespielt; Gewinner zusaetzlich gewonnen + groesster Pot).
// Die Teilnehmer werden beim Austeilen festgehalten (room.handParticipants).
function recordHandIfOver(room) {
  const t = room.table;
  if (!t || t.stage !== 'handover' || room.handRecorded || !t.result) return;
  room.handRecorded = true;
  const winners = new Set(t.result.winners || []);
  const pot = t.result.pot || 0;
  for (const part of room.handParticipants || []) {
    const won = winners.has(part.seat);
    recordHandStats(part.token, part.name, { won, potSize: won ? pot : 0 })
      .then((p) => {
        // Aktualisierte Statistik live an den (verbundenen) Spieler schicken.
        const seat = room.players.find((x) => x.token === part.token);
        if (seat?.connected && seat.socketId) {
          io.to(seat.socketId).emit('profile', publicProfile(p));
        }
      })
      .catch((e) => console.error('recordHandStats:', e.message));
  }
}

// Erkennt den Uebergang zu "Match beendet" und schreibt den Sieg dem Gewinner
// genau einmal gut (Token == Engine-Spieler-Id). Reset passiert bei rematch.
function checkMatchOver(room) {
  if (!room.table?.matchOver || room.matchRecorded) return;
  room.matchRecorded = true;
  const winnerToken = room.table.matchWinnerId;
  const seat = room.players.find((p) => p.token === winnerToken);
  if (winnerToken) {
    recordMatchWin(winnerToken, seat?.name).catch((e) =>
      console.error('recordMatchWin:', e.message)
    );
  }
}

function cancelCleanup(room) {
  if (room.cleanupTimer) {
    clearTimeout(room.cleanupTimer);
    room.cleanupTimer = null;
  }
}

function maybeScheduleCleanup(room) {
  if (room.players.every((p) => !p.connected)) {
    cancelCleanup(room);
    room.cleanupTimer = setTimeout(() => destroyRoom(room), ROOM_TTL_MS);
  }
}

function seatBySocket(room, socketId) {
  return room?.players.find((p) => p.socketId === socketId) || null;
}

function sendChatHistory(socket, room) {
  if (room.chat?.length) socket.emit('chatHistory', room.chat);
}

io.on('connection', (socket) => {
  socket.data.code = null;

  // Registriert einen Spiel-Event-Handler, der pro Event abgesichert ist
  // (siehe guard): wirft die Engine bei einem ungueltigen Zug o. ae., bleibt
  // der Server stehen statt den Prozess zu beenden.
  const onSafe = (ev, fn) => socket.on(ev, guard(ev, fn));

  onSafe('createRoom', async ({ name, token, maxPlayers, flush, startingStack, tournament, levelHands, cash }, cb) => {
    if (!token) return cb?.({ error: 'Kein Spieler-Token.' });
    const code = makeCode();
    const isCash = !!cash;
    const stack = clampStack(startingStack);
    const host = { token, name: cleanName(name), socketId: socket.id, connected: true };
    if (isCash) {
      const buy = await takeBuyIn(host, stack);
      if (buy.error) return cb?.({ error: buy.error });
    }
    const room = {
      code,
      maxPlayers: clampMaxPlayers(maxPlayers),
      flush: !!flush,
      startingStack: stack,
      cash: isCash,
      tournament: !isCash && !!tournament,
      levelHands: clampLevelHands(levelHands),
      players: [host],
      table: null,
      cleanupTimer: null,
      runoutTimer: null,
      autoActTimer: null,
      autoActFor: null,
      turnDeadline: null, // Zeitstempel, wann der Zug automatisch endet (Ring)
      turnTotalMs: null, // Gesamtdauer der aktuellen Zug-Uhr
      chat: [],
      matchRecorded: false,
      handRecorded: false, // Hand-Statistik dieser Hand schon geschrieben?
      handParticipants: [], // Teilnehmer der aktuellen Hand (fuer Statistik)
    };
    rooms.set(code, room);
    socket.data.code = code;
    socket.join(code);
    cb?.({ ok: true, code });
    broadcast(room);
    sendProfile(socket, token, cleanName(name));
  });

  onSafe('joinRoom', async ({ code, name, token }, cb) => {
    code = (code || '').toUpperCase().trim();
    if (!token) return cb?.({ error: 'Kein Spieler-Token.' });
    const room = rooms.get(code);
    if (!room) return cb?.({ error: 'Raum nicht gefunden.' });

    let seat = room.players.find((p) => p.token === token);
    if (seat) {
      // Bereits Teil des Raums -> wie Reconnect behandeln.
      seat.socketId = socket.id;
      seat.connected = true;
    } else {
      if (room.table) return cb?.({ error: 'Spiel laeuft bereits.' });
      if (room.players.length >= room.maxPlayers) return cb?.({ error: 'Raum ist voll.' });
      seat = { token, name: cleanName(name), socketId: socket.id, connected: true };
      if (room.cash) {
        const buy = await takeBuyIn(seat, room.startingStack);
        if (buy.error) return cb?.({ error: buy.error });
      }
      room.players.push(seat);
    }
    socket.data.code = code;
    socket.join(code);
    cancelCleanup(room);
    cb?.({ ok: true, code });
    broadcast(room);
    sendChatHistory(socket, room);
    sendProfile(socket, token, cleanName(name));
  });

  // Host startet das Spiel: erstellt den Tisch aus den aktuellen Spielern.
  function ensureTable(room) {
    if (room.table) return;
    const seated = room.players.filter((p) => p.connected);
    if (seated.length < 2) return;
    room.table = new Table(
      room.players.map((p) => ({ id: p.token, name: p.name })),
      {
        flush: room.flush,
        startingStack: room.startingStack,
        tournament: room.tournament,
        levelHands: room.levelHands,
        cash: room.cash,
      }
    );
    // Server deckt All-In-Run-outs zeitversetzt auf (TV-Poker-Stil).
    room.table.autoRunout = false;
  }

  // Treibt einen gestaffelten All-In-Run-out per Timer voran: pro Takt eine Strasse.
  function driveRunout(room) {
    if (room.runoutTimer) return; // laeuft bereits
    const step = () => {
      room.runoutTimer = null;
      try {
        if (!rooms.has(room.code) || !room.table) return;
        const res = room.table.stepRunout();
        broadcast(room);
        if (!res.done) {
          // Vor der letzten Karte (River) extra lange warten = maximaler Sweat.
          const remaining = 5 - (room.table.community?.length ?? 5);
          const delay = remaining === 1 ? RUNOUT_RIVER_MS : RUNOUT_STEP_MS;
          room.runoutTimer = setTimeout(step, delay);
        }
      } catch (e) {
        // Timer-Fehler wuerde sonst den Prozess killen: abfangen, Run-out
        // stoppen (Timer ist schon genullt), Tisch bleibt am Leben.
        logError('driveRunout', e);
      }
    };
    // Erste Karte erst nach einer kurzen Lese-Pause (Hände sind schon aufgedeckt).
    room.runoutTimer = setTimeout(step, RUNOUT_START_MS);
  }

  function maybeDriveRunout(room) {
    if (room.table?.runoutActive && room.table.stage !== 'handover') {
      driveRunout(room);
    }
  }

  function clearAutoAct(room) {
    if (room.autoActTimer) {
      clearTimeout(room.autoActTimer);
      room.autoActTimer = null;
    }
    room.autoActFor = null;
    room.turnDeadline = null;
    room.turnTotalMs = null;
  }

  // Handelt einmal automatisch fuer den Spieler am Zug (Check, sonst Fold).
  function autoActOne(room) {
    const t = room.table;
    const seat = room.players[t.toAct];
    if (!seat) return false;
    const a = t.view(seat.token).actions;
    if (!a) return false;
    const res = t.act(seat.token, a.canCheck ? 'check' : 'fold');
    return !res?.error;
  }

  // Wird ausgeloest, wenn die Zug-Zeit ablaeuft: handelt fuer den aktuellen Spieler
  // und raeumt danach direkt nachfolgende GETRENNTE Spieler mit ab (kein erneutes
  // Warten pro getrenntem Sitz), bis ein verbundener Spieler dran ist.
  function autoActOnTimeout(room) {
    const t = room.table;
    if (!t || t.toAct === null || t.stage === 'handover' || t.stage === 'showdown') return false;
    let acted = autoActOne(room);
    while (t.toAct !== null && t.stage !== 'handover' && t.stage !== 'showdown') {
      const seat = room.players[t.toAct];
      if (!seat || seat.connected) break; // verbundener Spieler bekommt eigene Zeit
      if (!autoActOne(room)) break;
      acted = true;
    }
    return acted;
  }

  // Plant das automatische Handeln fuer den Spieler am Zug. Verbundene Spieler
  // bekommen TURN_MS Bedenkzeit, getrennte nur die kurze Schonfrist.
  // `immediate` (z. B. bewusstes Verlassen) handelt ohne Wartezeit.
  function scheduleAutoAct(room, immediate = false) {
    const t = room.table;
    if (!t || t.toAct === null || t.stage === 'handover' || t.stage === 'showdown') {
      clearAutoAct(room);
      return;
    }
    const seat = room.players[t.toAct];
    if (!seat) {
      clearAutoAct(room);
      return;
    }
    // TURN_MS=0 schaltet die Zug-Uhr fuer verbundene Spieler ab.
    if (seat.connected && TURN_MS <= 0 && !immediate) {
      clearAutoAct(room);
      return;
    }
    // Laeuft bereits ein Timer fuer genau diesen Zug? Dann nicht neu starten,
    // damit unzusammenhaengende Broadcasts die Uhr nicht zuruecksetzen.
    if (room.autoActTimer && room.autoActFor === t.toAct && !immediate) return;
    clearAutoAct(room);
    const ms = immediate ? 0 : seat.connected ? TURN_MS : DISCONNECT_GRACE_MS;
    room.autoActFor = t.toAct;
    room.turnDeadline = Date.now() + ms;
    room.turnTotalMs = ms;
    room.autoActTimer = setTimeout(() => {
      room.autoActTimer = null;
      room.autoActFor = null;
      room.turnDeadline = null;
      room.turnTotalMs = null;
      try {
        if (!rooms.has(room.code) || !room.table) return;
        const acted = autoActOnTimeout(room);
        if (acted) {
          broadcast(room);
          maybeDriveRunout(room);
        }
        // Naechsten Spieler einplanen (eigene Uhr).
        scheduleAutoAct(room);
      } catch (e) {
        // Auto-Act-Fehler nicht eskalieren lassen (wuerde sonst crashen).
        logError('scheduleAutoAct', e);
      }
    }, ms);
  }

  // Reconnect: derselbe Token kehrt zu seinem Sitzplatz zurueck.
  onSafe('resume', ({ code, token }, cb) => {
    code = (code || '').toUpperCase().trim();
    const room = rooms.get(code);
    if (!room) return cb?.({ error: 'gone' });
    const seat = room.players.find((p) => p.token === token);
    if (!seat) return cb?.({ error: 'gone' });
    seat.socketId = socket.id;
    seat.connected = true;
    socket.data.code = code;
    socket.join(code);
    cancelCleanup(room);
    cb?.({ ok: true, code });
    // Reconnect: laufende (kurze) Schonfrist verwerfen und die Zug-Uhr frisch
    // planen (volle Bedenkzeit) – VOR dem Broadcast, damit turnMsLeft stimmt.
    clearAutoAct(room);
    scheduleAutoAct(room);
    broadcast(room);
    sendChatHistory(socket, room);
    sendProfile(socket, token, seat.name);
  });

  onSafe('startHand', () => {
    const room = rooms.get(socket.data.code);
    if (!room) return;
    // Nur der Host darf das Spiel/eine neue Hand starten.
    if (room.players[0]?.socketId !== socket.id && room.table == null) return;
    ensureTable(room);
    if (!room.table) return;
    const res = room.table.startHand();
    if (res?.error) socket.emit('errorMsg', res.error);
    if (!res?.error) {
      // Teilnehmer dieser Hand festhalten (wer ausgeteilt bekam) – fuer die
      // Hand-Statistik am Rundenende. Engine-Index == room.players-Index.
      room.handRecorded = false;
      room.handParticipants = room.players
        .map((p, i) => ({ token: p.token, name: p.name, seat: i, inHand: room.table.players[i]?.inHand }))
        .filter((x) => x.inHand)
        .map(({ token, name, seat }) => ({ token, name, seat }));
    }
    // Zug-Uhr VOR dem Broadcast setzen, damit turnMsLeft mitgesendet wird.
    scheduleAutoAct(room);
    broadcast(room);
    maybeDriveRunout(room);
  });

  onSafe('rematch', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    room.table.resetMatch();
    room.matchRecorded = false;
    clearAutoAct(room);
    broadcast(room);
  });

  // Cash-Game: Chips vom Wallet nachkaufen (zwischen den Haenden).
  onSafe('rebuy', async ({ amount } = {}, cb) => {
    const room = rooms.get(socket.data.code);
    if (!room?.table || !room.cash) return cb?.({ error: 'Kein Cash-Game.' });
    const seat = seatBySocket(room, socket.id);
    if (!seat) return cb?.({ error: 'Kein Sitz.' });
    // Standard-Rebuy = ein Buy-in; Betrag wird aufs Wallet begrenzt.
    let amt = Math.floor(Number(amount));
    if (!Number.isFinite(amt) || amt <= 0) amt = room.startingStack;
    const p = await loadProfile(seat.token, seat.name);
    amt = Math.min(amt, p.wallet || 0);
    if (amt <= 0) return cb?.({ error: 'Nicht genug Guthaben.' });
    const res = room.table.rebuy(seat.token, amt);
    if (res.error) return cb?.({ error: res.error });
    await adjustWallet(seat.token, -amt, seat.name);
    seat.boughtIn = true;
    cb?.({ ok: true, amount: amt });
    broadcast(room);
    sendProfile(socket, seat.token, seat.name);
  });

  onSafe('showCards', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    const seat = seatBySocket(room, socket.id);
    if (!seat) return;
    const res = room.table.revealOwn(seat.token);
    if (res?.error) socket.emit('errorMsg', res.error);
    broadcast(room);
  });

  onSafe('action', ({ type, amount }) => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    const seat = seatBySocket(room, socket.id);
    if (!seat) return;
    const res = room.table.act(seat.token, type, amount);
    if (res?.error) socket.emit('errorMsg', res.error);
    // Zug-Uhr fuer den naechsten Spieler VOR dem Broadcast setzen.
    scheduleAutoAct(room);
    broadcast(room);
    maybeDriveRunout(room);
  });

  // Tisch-Chat: kurze Nachrichten zwischen den Spielern am Tisch.
  onSafe('chat', ({ text }) => {
    const room = rooms.get(socket.data.code);
    if (!room) return;
    const seat = seatBySocket(room, socket.id);
    if (!seat) return;
    const clean = (text || '').toString().replace(/\s+/g, ' ').trim().slice(0, 200);
    if (!clean) return;
    const msg = { name: seat.name, text: clean, ts: Date.now() };
    room.chat.push(msg);
    if (room.chat.length > CHAT_HISTORY) room.chat.shift();
    io.to(room.code).emit('chat', msg);
  });

  // Tisch verlassen und zurueck zur Lobby.
  onSafe('leaveRoom', () => {
    const room = rooms.get(socket.data.code);
    const code = socket.data.code;
    if (code) socket.leave(code);
    socket.data.code = null;
    if (!room) return;
    const seat = seatBySocket(room, socket.id);
    if (seat) {
      if (room.table) {
        // Laufendes Spiel: Sitz bleibt (gilt als getrennt), Indizes der Engine bleiben stabil.
        seat.connected = false;
      } else {
        // Lobby-Phase: Sitz ganz entfernen. Im Cash-Game den Buy-in zurueckzahlen.
        cashOutSeat(room, seat);
        room.players = room.players.filter((p) => p !== seat);
      }
    }
    if (room.players.length === 0) {
      destroyRoom(room);
      return;
    }
    // Bewusstes Verlassen am Zug: sofort automatisch handeln (kein Warten).
    scheduleAutoAct(room, true);
    broadcast(room);
    maybeScheduleCleanup(room);
  });

  socket.on('disconnect', () => {
    const room = rooms.get(socket.data.code);
    if (!room) return;
    const seat = seatBySocket(room, socket.id);
    if (seat) seat.connected = false;
    // Falls der getrennte Spieler am Zug ist: Schonfrist-Uhr vor dem Broadcast setzen.
    scheduleAutoAct(room);
    broadcast(room);
    maybeScheduleCleanup(room);
  });
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`KuhPoker laeuft auf http://localhost:${PORT}`);
});

// Keepalive: Render & aehnliche Free-Tier-Hoster fahren den Dienst nach ~15 Min
// ohne eingehende HTTP-Anfragen herunter – dann brechen alle WebSockets ab und
// der naechste Request hat einen langen Kaltstart. Ein periodischer Selbst-Ping
// haelt den Dienst wach. Aktiv, sobald eine Ziel-URL bekannt ist
// (KEEPALIVE_URL oder von Render gesetztes RENDER_EXTERNAL_URL).
const KEEPALIVE_URL =
  process.env.KEEPALIVE_URL ||
  (process.env.RENDER_EXTERNAL_URL ? `${process.env.RENDER_EXTERNAL_URL.replace(/\/$/, '')}/healthz` : null);
if (KEEPALIVE_URL && typeof fetch === 'function') {
  const ping = () => fetch(KEEPALIVE_URL).catch(() => {});
  setInterval(ping, 10 * 60 * 1000).unref();
  console.log(`Keepalive aktiv -> ${KEEPALIVE_URL} (alle 10 Min)`);
}
