import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Table } from './src/poker.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

const app = express();
app.use(express.static(join(__dirname, 'public')));

const httpServer = createServer(app);
const io = new Server(httpServer);

/**
 * Raum: { code, players: Seat[], table, cleanupTimer }
 * Seat: { token, name, socketId, connected }
 * Spieler werden ueber einen stabilen Token identifiziert (nicht die socket.id),
 * damit ein Reconnect denselben Sitzplatz wiederfindet.
 */
const rooms = new Map();
const ROOM_TTL_MS = 10 * 60 * 1000; // Raum nach 10 Min. ohne Verbindung loeschen
const RUNOUT_STEP_MS = Number(process.env.RUNOUT_STEP_MS ?? 1300); // Takt fuer All-In-Reveal
const CHAT_HISTORY = 60; // gespeicherte Chat-Nachrichten pro Raum

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

function lobbyState(room, forToken) {
  const connectedCount = room.players.filter((p) => p.connected).length;
  return {
    code: room.code,
    maxPlayers: room.maxPlayers,
    flush: room.flush,
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
  for (const p of room.players) {
    if (!p.connected) continue;
    if (room.table) io.to(p.socketId).emit('state', room.table.view(p.token));
    io.to(p.socketId).emit('lobby', lobbyState(room, p.token));
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
    room.cleanupTimer = setTimeout(() => rooms.delete(room.code), ROOM_TTL_MS);
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

  socket.on('createRoom', ({ name, token, maxPlayers, flush }, cb) => {
    if (!token) return cb?.({ error: 'Kein Spieler-Token.' });
    const code = makeCode();
    const room = {
      code,
      maxPlayers: clampMaxPlayers(maxPlayers),
      flush: !!flush,
      players: [{ token, name: cleanName(name), socketId: socket.id, connected: true }],
      table: null,
      cleanupTimer: null,
      runoutTimer: null,
      chat: [],
    };
    rooms.set(code, room);
    socket.data.code = code;
    socket.join(code);
    cb?.({ ok: true, code });
    broadcast(room);
  });

  socket.on('joinRoom', ({ code, name, token }, cb) => {
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
      room.players.push(seat);
    }
    socket.data.code = code;
    socket.join(code);
    cancelCleanup(room);
    cb?.({ ok: true, code });
    broadcast(room);
    sendChatHistory(socket, room);
  });

  // Host startet das Spiel: erstellt den Tisch aus den aktuellen Spielern.
  function ensureTable(room) {
    if (room.table) return;
    const seated = room.players.filter((p) => p.connected);
    if (seated.length < 2) return;
    room.table = new Table(
      room.players.map((p) => ({ id: p.token, name: p.name })),
      { flush: room.flush }
    );
    // Server deckt All-In-Run-outs zeitversetzt auf (TV-Poker-Stil).
    room.table.autoRunout = false;
  }

  // Treibt einen gestaffelten All-In-Run-out per Timer voran: pro Takt eine Strasse.
  function driveRunout(room) {
    if (room.runoutTimer) return; // laeuft bereits
    const step = () => {
      room.runoutTimer = null;
      if (!rooms.has(room.code) || !room.table) return;
      const res = room.table.stepRunout();
      broadcast(room);
      if (!res.done) {
        room.runoutTimer = setTimeout(step, RUNOUT_STEP_MS);
      }
    };
    room.runoutTimer = setTimeout(step, RUNOUT_STEP_MS);
  }

  function maybeDriveRunout(room) {
    if (room.table?.runoutActive && room.table.stage !== 'handover') {
      driveRunout(room);
    }
  }

  // Reconnect: derselbe Token kehrt zu seinem Sitzplatz zurueck.
  socket.on('resume', ({ code, token }, cb) => {
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
    broadcast(room);
    sendChatHistory(socket, room);
  });

  socket.on('startHand', () => {
    const room = rooms.get(socket.data.code);
    if (!room) return;
    // Nur der Host darf das Spiel/eine neue Hand starten.
    if (room.players[0]?.socketId !== socket.id && room.table == null) return;
    ensureTable(room);
    if (!room.table) return;
    const res = room.table.startHand();
    if (res?.error) socket.emit('errorMsg', res.error);
    broadcast(room);
    maybeDriveRunout(room);
  });

  socket.on('rematch', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    room.table.resetMatch();
    broadcast(room);
  });

  socket.on('showCards', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    const seat = seatBySocket(room, socket.id);
    if (!seat) return;
    const res = room.table.revealOwn(seat.token);
    if (res?.error) socket.emit('errorMsg', res.error);
    broadcast(room);
  });

  socket.on('action', ({ type, amount }) => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    const seat = seatBySocket(room, socket.id);
    if (!seat) return;
    const res = room.table.act(seat.token, type, amount);
    if (res?.error) socket.emit('errorMsg', res.error);
    broadcast(room);
    maybeDriveRunout(room);
  });

  // Tisch-Chat: kurze Nachrichten zwischen den Spielern am Tisch.
  socket.on('chat', ({ text }) => {
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
  socket.on('leaveRoom', () => {
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
        // Lobby-Phase: Sitz ganz entfernen.
        room.players = room.players.filter((p) => p !== seat);
      }
    }
    if (room.players.length === 0) {
      cancelCleanup(room);
      rooms.delete(room.code);
      return;
    }
    broadcast(room);
    maybeScheduleCleanup(room);
  });

  socket.on('disconnect', () => {
    const room = rooms.get(socket.data.code);
    if (!room) return;
    const seat = seatBySocket(room, socket.id);
    if (seat) seat.connected = false;
    broadcast(room);
    maybeScheduleCleanup(room);
  });
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`KuhPoker laeuft auf http://localhost:${PORT}`);
});
