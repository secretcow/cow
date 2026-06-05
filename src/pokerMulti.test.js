// Tests fuer 2-6 Spieler: Blind-Positionen, Setzreihenfolge, Side Pots, Rotation.
import { Table } from './poker.js';
import { evaluate } from './handEval.js';

let pass = 0;
let fail = 0;
function assert(name, cond) {
  if (cond) pass++;
  else {
    fail++;
    console.error('FAIL:', name);
  }
}

function players(n) {
  return Array.from({ length: n }, (_, i) => ({ id: 'P' + i, name: 'P' + i }));
}

// ---- Test 1: 3-Spieler Blind-Positionen & Reihenfolge ----
{
  const t = new Table(players(3), {});
  t.startHand();
  assert('3p Button=0', t.button === 0);
  assert('3p SB=1', t.sbPos === 1);
  assert('3p BB=2', t.bbPos === 2);
  // 3-handed: Button ist UTG und handelt praeflop zuerst.
  assert('3p UTG=Button(0) toAct', t.toAct === 0);
  assert('3p Pot=30', t.pot === 30);

  t.act('P0', 'call'); // UTG callt 20
  assert('3p toAct -> SB(1)', t.toAct === 1);
  t.act('P1', 'call'); // SB callt
  assert('3p toAct -> BB(2)', t.toAct === 2);
  t.act('P2', 'check'); // BB Option -> Flop
  assert('3p Flop', t.stage === 'flop');
  // Postflop: erster aktiver links vom Button = SB(1).
  assert('3p postflop toAct=SB(1)', t.toAct === 1);
}

// ---- Test 2: 6-Spieler Setup ----
{
  const t = new Table(players(6), {});
  t.startHand();
  assert('6p Button=0', t.button === 0);
  assert('6p SB=1', t.sbPos === 1);
  assert('6p BB=2', t.bbPos === 2);
  assert('6p UTG=3 toAct', t.toAct === 3);
  assert('6p Pot=30', t.pot === 30);
  assert('6p alle haben 2 Karten', t.players.every((p) => p.hole.length === 2));
}

// ---- Test 3: Button-Rotation ueber mehrere Haende (3 Spieler) ----
{
  const t = new Table(players(3), {});
  const seen = [];
  for (let h = 0; h < 3; h++) {
    t.startHand();
    seen.push(t.button);
    // Hand schnell beenden: alle folden bis einer bleibt.
    // toAct faltet, bis nur einer uebrig ist.
    let guard = 0;
    while (t.stage !== 'handover' && guard++ < 20) {
      const id = t.toActId ?? (t.toAct !== null ? t.players[t.toAct].id : null);
      const cur = t.players[t.toAct];
      // BB darf checken; sonst fold
      if (t.currentBet - cur.bet === 0) t.act(cur.id, 'check');
      else t.act(cur.id, 'fold');
    }
  }
  assert('3p Button rotiert 0,1,2', seen[0] === 0 && seen[1] === 1 && seen[2] === 2);
}

// ---- Test 4: buildSidePots Schichtung ----
{
  const t = new Table(players(3), {});
  t.players[0].committed = 100;
  t.players[1].committed = 300;
  t.players[2].committed = 300;
  const pots = t.buildSidePots();
  assert('Side pots: 2 Schichten', pots.length === 2);
  assert('Main pot 300 alle', pots[0].amount === 300 && pots[0].eligible.length === 3);
  assert('Side pot 400 nur 1&2', pots[1].amount === 400 &&
    pots[1].eligible.includes(1) && pots[1].eligible.includes(2) && !pots[1].eligible.includes(0));
}

// ---- Test 5: Side-Pot-Showdown: kurzer All-In gewinnt nur Main Pot ----
{
  const t = new Table(players(3), {});
  // Community ohne Paar-Hilfe: 1,2,3,4,6
  const C = (rank, suit) => ({ rank, suit, copy: suit });
  t.community = [C(1, 0), C(2, 1), C(3, 2), C(4, 3), C(6, 0)];
  t.players[0].hole = [C(9, 0), C(9, 1)]; // Paar 9 (bestes)
  t.players[1].hole = [C(8, 0), C(8, 1)]; // Paar 8
  t.players[2].hole = [C(7, 0), C(7, 1)]; // Paar 7
  t.players[0].committed = 100;
  t.players[1].committed = 300;
  t.players[2].committed = 300;
  const evals = [0, 1, 2].map((i) => ({
    i,
    eval: evaluate([...t.players[i].hole, ...t.community], { flush: false }),
  }));
  const before = t.players.map((p) => p.stack);
  t.distribute('showdown', evals, null);
  const gained = t.players.map((p, i) => p.stack - before[i]);
  // P0 gewinnt Main Pot 300, P1 gewinnt Side Pot 400, P2 nichts.
  assert('Kurzer All-In P0 +300', gained[0] === 300);
  assert('P1 gewinnt Side Pot +400', gained[1] === 400);
  assert('P2 +0', gained[2] === 0);
}

// ---- Test 6: 3-Spieler All-In Run-out, Chip-Erhaltung ----
{
  const t = new Table(players(3), {});
  t.players[0].stack = 100;
  t.players[1].stack = 300;
  t.players[2].stack = 1000;
  const total = 100 + 300 + 1000;
  t.startHand();
  // Alle gehen All-In / callen, bis Hand vorbei.
  let guard = 0;
  while (t.stage !== 'handover' && guard++ < 30) {
    const cur = t.players[t.toAct];
    const a = t.view(cur.id).actions;
    if (a.canRaise) t.act(cur.id, 'raise', a.maxRaiseTo);
    else if (a.canCall) t.act(cur.id, 'call');
    else t.act(cur.id, 'check');
  }
  const sum = t.players.reduce((s, p) => s + p.stack, 0);
  assert('3p All-In Chip-Erhaltung', sum === total);
  assert('3p Hand beendet', t.stage === 'handover');
}

// ---- Test 7: Heads-up via Array-Konstruktor ----
{
  const t = new Table(players(2), { flush: true });
  assert('Flush-Option gesetzt', t.flush === true);
  t.startHand();
  assert('2p Button=0', t.button === 0);
  assert('2p toAct=0 (SB/Button)', t.toAct === 0);
}

// ---- Test 8: Freiwilliges Aufdecken nach Fold-Sieg (revealOwn) ----
{
  const t = new Table(players(3), { flush: false });
  t.startHand();
  assert('Show vor handover -> Fehler', !!t.revealOwn('P0').error);
  // Alle bis auf einen folden.
  let guard = 0;
  while (t.stage !== 'handover' && guard++ < 20) t.act(t.players[t.toAct].id, 'fold');
  assert('Fold-Sieg erreicht handover', t.stage === 'handover' && t.result.reason === 'fold');

  const winnerIdx = t.players.findIndex((p) => !p.folded);
  const winnerId = t.players[winnerIdx].id;
  const folderId = t.players.find((p) => p.folded).id;

  assert('Gefoldeter darf nicht zeigen', !!t.revealOwn(folderId).error);
  // Vor dem Zeigen sieht ein Mitspieler die Gewinnerkarten verdeckt.
  assert(
    'Vor Show: Karten verdeckt',
    t.view('P_none').players[winnerIdx].hole.every((h) => h === null) ||
      t.view(folderId).players[winnerIdx].hole.every((h) => h === null)
  );
  assert('Show erfolgreich', !!t.revealOwn(winnerId).ok);
  // Danach sieht jeder andere die zwei Karten.
  const seen = t.view(folderId).players[winnerIdx].hole.filter((h) => h).length;
  assert('Nach Show: 2 Karten sichtbar', seen === 2);
  assert('view.shown enthaelt Sieger', t.view(folderId).shown.includes(winnerIdx));
  assert('Show-Log-Event vorhanden', t.log.some((e) => e.key === 'shown'));
  // Idempotent.
  t.revealOwn(winnerId);
  assert('Show idempotent', t.shownCards.size === 1);
}

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
