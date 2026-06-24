// End-to-End-Test fuer die neueren Server-Features ueber echte Sockets:
//   - Emotes (erlaubte Liste, Anti-Spam-Entprellung, Broadcast mit Sitz-Index)
//   - Hand-Historie (Eintrag pro Hand, Gewinner/Pot/Grund)
//   - Beobachter-Modus (keine verdeckten Karten, kann nicht handeln, Zaehler)
// Ziel-URL ueber KP_TEST_URL (vom Harness gesetzt), sonst localhost:3000.
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
    s.emotes = [];
    s.history = null;
    s.on('state', (st) => (s.latestState = st));
    s.on('lobby', (lb) => (s.latestLobby = lb));
    s.on('emote', (e) => s.emotes.push(e));
    s.on('handHistory', (h) => (s.history = h));
    s.on('connect', () => resolve(s));
  });
}

const mk = (extra) => ({ name: extra.name, token: extra.token, maxPlayers: 6, flush: false, startingStack: 1000, tournament: false, levelHands: 8, cash: false });

async function main() {
  const a = await connect();
  const b = await connect();
  const spec = await connect();

  const code = await new Promise((res) => a.emit('createRoom', mk({ name: 'Anna', token: 'fa' }), (r) => res(r.code)));
  await new Promise((res) => b.emit('joinRoom', { code, name: 'Ben', token: 'fb' }, () => res()));

  // ---------- Emotes ----------
  // 3 schnelle Emotes von A -> nur 1 darf durchkommen (Entprellung).
  a.emit('emote', { emote: '🔥' });
  a.emit('emote', { emote: '😂' });
  a.emit('emote', { emote: '👍' });
  await wait(250);
  assert('Emote: Rate-Limit (3 schnell -> 1)', b.emotes.length === 1);
  assert('Emote: korrekter Sitz-Index', b.emotes[0]?.seat === 0);
  assert('Emote: korrektes Emoji', b.emotes[0]?.emote === '🔥');
  // Ungueltiges Emote wird ignoriert.
  a.emit('emote', { emote: '💣' });
  await wait(200);
  assert('Emote: ungueltiges ignoriert', b.emotes.length === 1);
  // Nach Cooldown wieder erlaubt.
  await wait(1300);
  a.emit('emote', { emote: '😮' });
  await wait(200);
  assert('Emote: nach Cooldown erlaubt', b.emotes.length === 2);

  // ---------- Beobachter-Modus ----------
  const specRes = await new Promise((res) => spec.emit('spectate', { code }, (r) => res(r)));
  assert('Spectate: erfolgreich beigetreten', specRes.ok === true);
  await wait(150);
  assert('Spectate: Lobby-Zaehler = 1', a.latestLobby?.spectators === 1);
  assert('Spectate: youAreSpectator', spec.latestLobby?.youAreSpectator === true);

  // Hand starten -> Zuschauer sieht keine verdeckten Karten.
  a.emit('startHand');
  await wait(200);
  assert('Spectate: meIdx -1', spec.latestState?.meIdx === -1);
  assert('Spectate: spectator-Flag', spec.latestState?.spectator === true);
  const anyHoleVisible = (spec.latestState?.players || []).some((p) => (p.hole || []).some((c) => c !== null));
  assert('Spectate: keine verdeckten Karten sichtbar', anyHoleVisible === false);
  // Zuschauer-Aktion wird ignoriert (kein Crash, kein Sitz).
  spec.emit('action', { type: 'check' });
  await wait(120);
  assert('Spectate: Aktion ohne Wirkung (kein Crash)', spec.latestState?.stage === 'preflop');

  // ---------- Hand spielen + Hand-Historie ----------
  async function actCurrent() {
    const turnId = a.latestState?.toActId;
    for (const s of [a, b]) {
      const st = s.latestState;
      if (!st || st.meIdx < 0) continue;
      const myId = st.players[st.meIdx]?.id;
      if (myId === turnId && st.actions) {
        s.emit('action', { type: st.actions.canCheck ? 'check' : 'call' });
        return;
      }
    }
  }
  let guard = 0;
  while (a.latestState?.stage !== 'handover' && guard++ < 40) {
    await actCurrent();
    await wait(70);
  }
  assert('Hand erreicht handover', a.latestState?.stage === 'handover');
  await wait(150);
  assert('Historie: Eintrag vorhanden', Array.isArray(a.history) && a.history.length === 1);
  const h0 = (a.history || [])[0] || {};
  assert('Historie: Hand-Nr gesetzt', h0.hand === 1);
  assert('Historie: Gewinner vorhanden', Array.isArray(h0.winners) && h0.winners.length >= 1);
  assert('Historie: Pot > 0', h0.pot > 0);
  assert('Historie: Grund gesetzt', h0.reason === 'showdown' || h0.reason === 'fold');
  assert('Spectate: Zuschauer erhielt Historie', Array.isArray(spec.history) && spec.history.length === 1);

  // ---------- Zuschauer verlaesst -> Zaehler 0 ----------
  spec.emit('leaveRoom');
  await wait(200);
  assert('Spectate: Zaehler nach Verlassen = 0', a.latestLobby?.spectators === 0);

  a.close();
  b.close();
  spec.close();
  console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
