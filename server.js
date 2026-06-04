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

function lobbyState(room) {
  return {
    code: room.code,
    players: room.players.map((p) => ({ name: p.name, connected: p.connected })),
    ready: room.players.length === 2 && room.players.every((p) => p.connected),
    hasTable: !!room.table,
  };
}

function broadcast(room) {
  for (const p of room.players) {
    if (!p.connected) continue;
    if (room.table) io.to(p.socketId).emit('state', room.table.view(p.token));
    io.to(p.socketId).emit('lobby', lobbyState(room));
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

io.on('connection', (socket) => {
  socket.data.code = null;

  socket.on('createRoom', ({ name, token }, cb) => {
    if (!token) return cb?.({ error: 'Kein Spieler-Token.' });
    const code = makeCode();
    const room = {
      code,
      players: [{ token, name: cleanName(name), socketId: socket.id, connected: true }],
      table: null,
      cleanupTimer: null,
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
      if (room.players.length >= 2) return cb?.({ error: 'Raum ist voll.' });
      seat = { token, name: cleanName(name), socketId: socket.id, connected: true };
      room.players.push(seat);
    }
    socket.data.code = code;
    socket.join(code);
    cancelCleanup(room);

    if (room.players.length === 2 && !room.table) {
      room.table = new Table(
        { id: room.players[0].token, name: room.players[0].name },
        { id: room.players[1].token, name: room.players[1].name }
      );
    }
    cb?.({ ok: true, code });
    broadcast(room);
  });

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
  });

  socket.on('startHand', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    const res = room.table.startHand();
    if (res?.error) socket.emit('errorMsg', res.error);
    broadcast(room);
  });

  socket.on('rematch', () => {
    const room = rooms.get(socket.data.code);
    if (!room?.table) return;
    room.table.resetMatch();
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
