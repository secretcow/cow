// End-to-End-Test mit VIER Spielern ueber echte Sockets gegen den laufenden
// Server (Port 3000). Prueft Mehrspieler-Plumbing, Setzreihenfolge, Kartengeheimnis
// pro Sitz, All-In ueber Sockets und vor allem ECHTE geschichtete Side Pots.
//
// Der Side-Pot-Teil ist bewusst deterministisch aufgebaut (unabhaengig vom
// gemischten Deck):
//   Hand 1 endet per Fold-to-Raise -> garantiert ungleiche Stacks
//           A=1000, B=990, C=980, D=1030
//   Hand 2 alle All-In -> committed {1000,990,980,1030} ergibt zwingend
//           vier geschichtete Pots. Wer gewinnt, haengt von den Karten ab,
//           aber Pot-Struktur und Chip-Erhaltung gelten immer.
//
// Voraussetzung: Server laeuft auf localhost:3000.
//   node server.js &   (oder Preview)  ->  node src/socketMulti.test.js
import { io } from 'socket.io-client';

const URL = process.env.KP_TEST_URL || 'http://localhost:3000';
let pass = 0,
  fail = 0;
const assert = (n, c) => {
  if (c) pass++;
  else {
    fail++;
    console.error('FAIL:', n);
  }
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function connect() {
  return new Promise((resolve) => {
    const s = io(URL, { forceNew: true, transports: ['websocket'] });
    s.latestState = null;
    s.latestLobby = null;
    s.on('state', (st) => (s.latestState = st));
    s.on('lobby', (lb) => (s.latestLobby = lb));
    s.on('connect', () => resolve(s));
  });
}

const ack = (s, ev, payload) =>
  new Promise((res) => s.emit(ev, payload, (r) => res(r)));

// Treibt die Hand, bis sie 'handover' erreicht. Fuer jeden Zug wird der Socket
// gesucht, dessen eigener Sitz am Zug ist, und die Strategie liefert die Aktion.
// Deadline-basiert statt fester Schrittzahl: ein All-In-Run-out wird vom Server
// zeitversetzt aufgedeckt (mehrere Sekunden), daher warten wir bis zum Handover
// oder bis das Zeitlimit erreicht ist.
async function playUntilHandover(sockets, strategy, deadlineMs = 25000) {
  const until = Date.now() + deadlineMs;
  while (Date.now() < until) {
    const ref = sockets.find((s) => s.latestState)?.latestState;
    if (!ref) {
      await wait(50);
      continue;
    }
    if (ref.stage === 'handover') return true;
    const turnId = ref.toActId;
    if (turnId == null) {
      // Niemand am Zug (z. B. laufender All-In-Run-out) -> auf naechsten Tick warten.
      await wait(50);
      continue;
    }
    const actor = sockets.find(
      (s) =>
        s.latestState &&
        s.latestState.players[s.latestState.meIdx].id === turnId
    );
    if (!actor) {
      await wait(50);
      continue;
    }
    actor.emit('action', strategy(actor.latestState));
    await wait(70);
  }
  return false;
}

// Hand 1: der erste Spieler erhoeht, alle anderen folden (deterministischer Fold-Sieg).
function foldToRaiseStrat(st) {
  const a = st.actions;
  if (st.currentBet === 20) {
    // Noch keine Erhoehung -> der erste Akteur (UTG) erhoeht auf 60.
    return a.canRaise ? { type: 'raise', amount: 60 } : { type: 'call' };
  }
  return { type: 'fold' };
}

// Hand 2: jeder geht maximal All-In (grosse Stacks erhoehen, kurze callen all-in).
function allInStrat(st) {
  const a = st.actions;
  if (a.canRaise && a.maxRaiseTo > st.currentBet)
    return { type: 'raise', amount: a.maxRaiseTo };
  if (a.canCall) return { type: 'call' };
  return { type: 'check' };
}

async function main() {
  const sockets = await Promise.all([connect(), connect(), connect(), connect()]);
  const [a, b, c, d] = sockets;
  const tokens = ['m-anna', 'm-ben', 'm-cara', 'm-dora'];
  const names = ['Anna', 'Ben', 'Cara', 'Dora'];

  // ----- Raum mit 4 Plaetzen erstellen + Beitritt -----
  const cr = await ack(a, 'createRoom', {
    name: names[0],
    token: tokens[0],
    maxPlayers: 4,
    flush: false,
  });
  const code = cr.code;
  assert('Raum-Code erhalten', /^[A-Z2-9]{4}$/.test(code));

  for (let i = 1; i < 4; i++) {
    await ack(sockets[i], 'joinRoom', { code, name: names[i], token: tokens[i] });
  }
  await wait(200);
  assert('Lobby zeigt 4 Spieler', a.latestLobby?.players.length === 4);
  assert('A ist Host', a.latestLobby?.youAreHost === true);
  assert('D ist nicht Host', d.latestLobby?.youAreHost === false);
  assert('Lobby kann mit 4 starten', a.latestLobby?.canStart === true);

  // ============ HAND 1 ============
  a.emit('startHand');
  await wait(200);
  assert('Hand 1 preflop', a.latestState?.stage === 'preflop');

  // Positionen: Button=A(0), SB=B(1), BB=C(2), UTG/erster=D(3).
  const ps = a.latestState.players;
  assert('A ist Button', ps[0].isButton === true);
  assert('B ist Small Blind', ps[1].isSB === true);
  assert('C ist Big Blind', ps[2].isBB === true);
  assert('UTG (Dora) ist zuerst am Zug', a.latestState.toActId === d.latestState.players[d.latestState.meIdx].id);

  // Kartengeheimnis: jeder Sitz sieht NUR die eigenen 2 Karten, fremde sind null.
  let privacyOk = true;
  for (const s of sockets) {
    const st = s.latestState;
    const meHole = st.players[st.meIdx].hole;
    if (meHole.filter((h) => h).length !== 2) privacyOk = false;
    st.players.forEach((p, i) => {
      if (i !== st.meIdx && !p.hole.every((h) => h === null)) privacyOk = false;
    });
  }
  assert('Alle 4 sehen nur eigene Karten (preflop)', privacyOk);

  const ok1 = await playUntilHandover(sockets, foldToRaiseStrat);
  assert('Hand 1 erreicht handover', ok1 && a.latestState.stage === 'handover');
  assert('Hand 1 endet per Fold', a.latestState.result?.reason === 'fold');

  // Stacks jetzt garantiert ungleich (Voraussetzung fuer echte Side Pots).
  const st1 = a.latestState.players;
  assert('Stacks nach Hand 1: A=1000', st1[0].stack === 1000);
  assert('Stacks nach Hand 1: B=990 (SB)', st1[1].stack === 990);
  assert('Stacks nach Hand 1: C=980 (BB)', st1[2].stack === 980);
  assert('Stacks nach Hand 1: D=1030 (Sieger)', st1[3].stack === 1030);
  assert(
    'Chip-Erhaltung nach Hand 1 (4000)',
    st1.reduce((s, p) => s + p.stack, 0) === 4000
  );

  // ============ HAND 2: 4-fach All-In -> Side Pots ============
  a.emit('startHand');
  await wait(200);
  assert('Hand 2 preflop', a.latestState?.stage === 'preflop');

  const ok2 = await playUntilHandover(sockets, allInStrat);
  assert('Hand 2 erreicht handover', ok2 && a.latestState.stage === 'handover');

  const res = a.latestState.result;
  assert('Hand 2 endet im Showdown', res?.reason === 'showdown');
  assert(
    'Chip-Erhaltung nach Hand 2 (4000)',
    a.latestState.players.reduce((s, p) => s + p.stack, 0) === 4000
  );

  // committed {1000,990,980,1030} => vier geschichtete Pots (deterministisch).
  assert('Genau vier geschichtete Pots', res?.pots?.length === 4);
  assert(
    'Summe der Pots == 4000',
    res.pots.reduce((s, p) => s + p.amount, 0) === 4000
  );

  // Hauptpot = 4 * kuerzester Einsatz (980) = 3920. Cara (kuerzester Stack)
  // ist nur fuer den Hauptpot berechtigt und kann nie mehr als 3920 halten.
  const mainPot = res.pots[0];
  assert('Hauptpot = 3920 (4x980)', mainPot.amount === 3920);
  assert('Hauptpot: alle 4 berechtigt', mainPot.eligible.length === 4);
  const cara = a.latestState.players[2];
  assert('Cara haelt hoechstens den Hauptpot (<=3920)', cara.stack <= 3920);

  // Dora hat 30 Chips ueber allen anderen -> dieser oberste Pot ist
  // unbestritten und faellt garantiert an Dora zurueck.
  const topPot = res.pots[3];
  assert('Oberster Pot nur fuer Dora', topPot.eligible.length === 1);
  const dora = a.latestState.players[3];
  assert('Dora bekommt mindestens ihren unbestrittenen Ueberschuss (>=30)', dora.stack >= 30);

  // Showdown-Reveal wird an alle gebroadcastet: nicht gefoldete Haende sind sichtbar.
  let revealOk = true;
  for (const s of sockets) {
    const rev = s.latestState.result?.reveal;
    if (!rev) {
      revealOk = false;
      continue;
    }
    for (const r of rev) {
      if (!r.folded && r.hole.some((h) => h === null)) revealOk = false;
    }
  }
  assert('Showdown-Reveal an alle gebroadcastet', revealOk);

  for (const s of sockets) s.close();
  console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
