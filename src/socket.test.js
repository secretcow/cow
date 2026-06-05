// End-to-End-Test ueber echte Sockets gegen den laufenden Server (Port 3000).
import { io } from 'socket.io-client';

const URL = 'http://localhost:3000';
let pass = 0, fail = 0;
const assert = (n, c) => { if (c) pass++; else { fail++; console.error('FAIL:', n); } };
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

const tokenA = 'tok-anna';
const tokenB = 'tok-ben';

async function main() {
  const a = await connect();
  const b = await connect();

  const code = await new Promise((res) =>
    a.emit('createRoom', { name: 'Anna', token: tokenA }, (r) => res(r.code))
  );
  assert('Raum-Code erhalten', /^[A-Z2-9]{4}$/.test(code));

  await new Promise((res) => b.emit('joinRoom', { code, name: 'Ben', token: tokenB }, () => res()));
  await wait(150);
  assert('A hat Lobby nach Join', !!a.latestLobby);
  assert('B hat Lobby nach Join', !!b.latestLobby);
  assert('A ist Host', a.latestLobby.youAreHost === true);
  assert('B ist nicht Host', b.latestLobby.youAreHost === false);
  assert('Lobby kann starten (2 Spieler)', a.latestLobby.canStart === true);

  a.emit('startHand');
  await wait(150);
  assert('Stage preflop', a.latestState.stage === 'preflop');

  const aMe = a.latestState.players[a.latestState.meIdx];
  const aOpp = a.latestState.players[a.latestState.meIdx === 0 ? 1 : 0];
  assert('A sieht eigene 2 Karten', aMe.hole.filter((h) => h).length === 2);
  assert('A sieht NICHT Gegnerkarten', aOpp.hole.every((h) => h === null));

  // ----- Reconnect-Test: A trennt sich, neuer Socket nimmt mit gleichem Token den Sitz wieder ein -----
  const aHoleBefore = JSON.stringify(aMe.hole);
  a.close();
  await wait(150);
  const a2 = await connect();
  const resumeRes = await new Promise((res) =>
    a2.emit('resume', { code, token: tokenA }, (r) => res(r))
  );
  await wait(150);
  assert('Resume erfolgreich', resumeRes.ok === true);
  assert('A2 erhaelt State', !!a2.latestState);
  const a2Me = a2.latestState.players[a2.latestState.meIdx];
  assert('A2 hat denselben Sitz/Karten', JSON.stringify(a2Me.hole) === aHoleBefore);

  // ----- Spiele die Hand durch (A2 + B checken/callen) -----
  async function actCurrent(sockets) {
    const turnId = a2.latestState.toActId;
    for (const s of sockets) {
      const st = s.latestState;
      if (!st) continue;
      const myId = st.players[st.meIdx].id;
      if (myId === turnId && st.actions) {
        if (st.actions.canCheck) s.emit('action', { type: 'check' });
        else s.emit('action', { type: 'call' });
        return;
      }
    }
  }
  let guard = 0;
  while (a2.latestState.stage !== 'handover' && guard++ < 30) {
    await actCurrent([a2, b]);
    await wait(80);
  }
  assert('Hand erreicht handover', a2.latestState.stage === 'handover');
  assert('Chips summieren 2000', a2.latestState.players.reduce((s, p) => s + p.stack, 0) === 2000);

  // ----- Rematch-Test -----
  a2.emit('rematch');
  await wait(150);
  assert('Rematch -> idle', a2.latestState.stage === 'idle');
  assert('Rematch -> Stacks 1000', a2.latestState.players.every((p) => p.stack === 1000));

  a2.close();
  b.close();
  console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
