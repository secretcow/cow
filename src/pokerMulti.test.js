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

// ---- Test 9: Live-Handstaerke (myHand) waehrend des Setzens ----
{
  const t = new Table(players(2), { flush: false });
  t.startHand();
  const C = (rank, suit) => ({ rank, suit, copy: suit });
  // Praeflop: Paar auf der Hand -> cat 3 (Paar).
  t.players[0].hole = [C(9, 0), C(9, 1)];
  const v = t.view('P0');
  assert('myHand vorhanden praeflop', v.myHand && v.myHand.cat === 3);
  // Hohe Karte: zwei verschiedene Raenge -> cat 2.
  t.players[1].hole = [C(2, 0), C(7, 1)];
  assert('myHand Hohe Karte', t.view('P1').myHand.cat === 2);
  // Mit Board (>=5 Karten) volle Auswertung: Drilling 9.
  t.community = [C(9, 2), C(3, 0), C(4, 1), C(1, 0), C(6, 0)];
  t.stage = 'river';
  assert('myHand Drilling am River', t.view('P0').myHand.cat === 5);
  // Gefoldeter Spieler hat keine Live-Handstaerke.
  t.players[1].folded = true;
  assert('myHand null wenn gefoldet', t.view('P1').myHand === null);
}

// ---- Test 10: All-In-Run-out (autoRunout=false) gestaffelt mit Equities ----
{
  const t = new Table(players(3), { flush: false });
  t.autoRunout = false;
  t.players[0].stack = 100;
  t.players[1].stack = 100;
  t.players[2].stack = 100;
  t.startHand();
  // Alle All-In bis Setzrunde geschlossen.
  let guard = 0;
  while (t.stage === 'preflop' && t.toAct !== null && guard++ < 20) {
    const cur = t.players[t.toAct];
    const a = t.view(cur.id).actions;
    if (a.canRaise) t.act(cur.id, 'raise', a.maxRaiseTo);
    else if (a.canCall) t.act(cur.id, 'call');
    else t.act(cur.id, 'check');
  }
  assert('Run-out aktiv nach All-In', t.runoutActive === true);
  assert('Equities berechnet', Array.isArray(t.equities) && t.equities.length === 3);
  assert('Equities summieren ~100%', Math.abs(t.equities.reduce((s, e) => s + e.pct, 0) - 100) <= 3);
  assert('view exponiert runout', t.view('P0').runout === true);
  assert('Board noch nicht komplett', t.community.length < 5);
  // Sweat: Karte fuer Karte aufdecken (preflop All-In -> Board waechst um genau 1).
  const before = t.community.length;
  const r1 = t.stepRunout();
  assert('Sweat: erster Takt deckt genau 1 Karte auf', t.community.length === before + 1);
  assert('Sweat: nach erstem Takt noch nicht fertig', r1.done === false);
  // Gestaffelt aufdecken, bis Hand vorbei.
  let steps = 0;
  let done = false;
  while (!done && steps++ < 10) done = t.stepRunout().done;
  assert('Run-out endet in handover', t.stage === 'handover');
  assert('Board komplett (5)', t.community.length === 5);
  assert('runoutActive aus nach Ende', t.runoutActive === false);
}

// ---- Test 11: autoRunout=true laeuft synchron durch (Default, fuer Tests) ----
{
  const t = new Table(players(3), { flush: false });
  t.players[0].stack = 100;
  t.players[1].stack = 100;
  t.players[2].stack = 100;
  t.startHand();
  let guard = 0;
  while (t.stage !== 'handover' && guard++ < 30) {
    const cur = t.players[t.toAct];
    const a = t.view(cur.id).actions;
    if (a.canRaise) t.act(cur.id, 'raise', a.maxRaiseTo);
    else if (a.canCall) t.act(cur.id, 'call');
    else t.act(cur.id, 'check');
  }
  assert('autoRunout: direkt handover', t.stage === 'handover');
  assert('autoRunout: runout nie aktiv', t.runoutActive === false);
}

// ---- Helfer: spielt eine Hand schnell zu Ende (check, sonst fold) ----
function quickHand(t) {
  t.startHand();
  let guard = 0;
  while (t.stage !== 'handover' && t.stage !== 'idle' && guard++ < 80) {
    const cur = t.players[t.toAct];
    if (cur == null) break;
    const a = t.view(cur.id).actions;
    if (!a) break;
    if (a.canCheck) t.act(cur.id, 'check');
    else t.act(cur.id, 'fold');
  }
}

// ---- Test 12: Nicht-Turnier -> Blinds bleiben konstant 10/20 ----
{
  const t = new Table(players(3), { startingStack: 100000 });
  for (let h = 0; h < 5; h++) {
    quickHand(t);
    assert(`fix SB=10 (Hand ${h + 1})`, t.smallBlind === 10);
    assert(`fix BB=20 (Hand ${h + 1})`, t.bigBlind === 20);
  }
  const v = t.view('P0');
  assert('fix view tournament=false', v.blinds.tournament === false);
  assert('fix view level=null', v.blinds.level === null);
  assert('fix view nextLevelIn=null', v.blinds.nextLevelIn === null);
}

// ---- Test 13: Turnier -> Blinds steigen alle levelHands Haende ----
{
  const t = new Table(players(3), { tournament: true, levelHands: 2, startingStack: 100000 });
  quickHand(t); // Hand 1, Level 0
  assert('tourney H1 BB=20', t.bigBlind === 20 && t.smallBlind === 10);
  assert('tourney H1 level=1', t.view('P0').blinds.level === 1);
  assert('tourney H1 nextLevelIn=1', t.view('P0').blinds.nextLevelIn === 1);
  quickHand(t); // Hand 2, Level 0
  assert('tourney H2 BB=20', t.bigBlind === 20);
  assert('tourney H2 nextLevelIn=0', t.view('P0').blinds.nextLevelIn === 0);
  quickHand(t); // Hand 3, Level 1 -> 15/30
  assert('tourney H3 SB=15', t.smallBlind === 15);
  assert('tourney H3 BB=30', t.bigBlind === 30);
  assert('tourney H3 level=2', t.view('P0').blinds.level === 2);
  assert('tourney H3 blindsUp geloggt', t.log.some((e) => e.key === 'blindsUp' && e.bb === 30));
  quickHand(t); // Hand 4, Level 1
  assert('tourney H4 BB=30', t.bigBlind === 30);
  quickHand(t); // Hand 5, Level 2 -> 25/50
  assert('tourney H5 SB=25', t.smallBlind === 25);
  assert('tourney H5 BB=50', t.bigBlind === 50);
}

// ---- Test 14: Turnier -> Blinds deckeln beim letzten Level ----
{
  const t = new Table(players(3), { tournament: true, levelHands: 1, startingStack: 1000000 });
  for (let h = 0; h < 15; h++) quickHand(t); // weit ueber 12 Level hinaus
  assert('cap SB=1000', t.smallBlind === 1000);
  assert('cap BB=2000', t.bigBlind === 2000);
  assert('cap handsUntilNextLevel=null', t.handsUntilNextLevel() === null);
  assert('cap view nextLevelIn=null', t.view('P0').blinds.nextLevelIn === null);
}

// ---- Test 15: Cash-Game -> Busten beendet das Match nicht, Rebuy & Cash-out ----
{
  const t = new Table(players(2), { cash: true, startingStack: 200 });
  assert('cash flag gesetzt', t.cash === true);
  assert('cash view cash=true', t.view('P0').cash === true);
  assert('cash view buyIn=200', t.view('P0').buyIn === 200);
  assert('cash stackOf P0=200', t.stackOf('P0') === 200);

  // Spieler 1 verliert seinen ganzen Stack -> im Nicht-Cash waere das Match-over.
  t.players[1].stack = 0;
  // Eine Hand zu Ende spielen (nur P0 hat Chips -> kann nicht starten? -> liveCount<2)
  // Stattdessen direkt endHand-Pfad ueber eine normale Hand mit beiden Chips testen:
  t.players[1].stack = 50;
  quickHand(t);
  assert('cash kein matchOver trotz moeglicher Pleite', t.matchOver === false);

  // Rebuy nur zwischen den Haenden erlaubt und addiert Chips.
  const before = t.stackOf('P1');
  const r = t.rebuy('P1', 500);
  assert('cash rebuy ok', r.ok === true && r.amount === 500);
  assert('cash rebuy addiert Chips', t.stackOf('P1') === before + 500);
  assert('cash rebuy geloggt', t.log.some((e) => e.key === 'rebuy' && e.amount === 500));

  // Rebuy mitten in der Hand abgelehnt.
  t.startHand();
  const r2 = t.rebuy('P1', 100);
  assert('cash rebuy waehrend Hand abgelehnt', !!r2.error);

  // Nicht-Cash: rebuy verweigert.
  const t2 = new Table(players(2), { startingStack: 200 });
  assert('non-cash rebuy verweigert', !!t2.rebuy('P0', 100).error);
  assert('non-cash view cash=false', t2.view('P0').cash === false);
  assert('non-cash view buyIn=null', t2.view('P0').buyIn === null);

  // Cash schliesst Turnier aus.
  const t3 = new Table(players(2), { cash: true, tournament: true });
  assert('cash deaktiviert tournament', t3.tournament === false);
}

// ---- Test: lastAction pro Spieler (Sitz-Anzeige) ----
{
  const t = new Table(players(3), { flush: false });
  t.startHand();
  // Vor jeder Aktion ist lastAction null.
  assert('lastAction initial null', t.players.every((p) => p.lastAction === null));
  // Erster Spieler am Zug erhoeht.
  const cur = t.players[t.toAct];
  const a = t.view(cur.id).actions;
  t.act(cur.id, 'raise', a.minRaiseTo);
  const after = t.players.find((p) => p.id === cur.id);
  assert('lastAction raise/bet gesetzt', after.lastAction && (after.lastAction.type === 'raise' || after.lastAction.type === 'bet'));
  assert('lastAction in view exponiert', t.view(cur.id).players.find((p) => p.id === cur.id).lastAction != null);
  // Naechster foldet -> lastAction fold.
  const nxt = t.players[t.toAct];
  t.act(nxt.id, 'fold');
  assert('lastAction fold gesetzt', t.players.find((p) => p.id === nxt.id).lastAction.type === 'fold');
}

// ---- Test: showdown ist idempotent (kein doppeltes Distribute) ----
// Schuetzt gegen den Bug, bei dem ein zweiter Showdown (synchron + getakteter
// Run-out) das Side-Pot-Ergebnis mit committed=0 ueberschrieb.
{
  const t = new Table(players(3), { flush: false });
  t.players[0].stack = 100;
  t.players[1].stack = 100;
  t.players[2].stack = 100;
  t.startHand();
  let guard = 0;
  while (t.stage !== 'handover' && guard++ < 30) {
    const cur = t.players[t.toAct];
    const a = t.view(cur.id).actions;
    if (a.canRaise) t.act(cur.id, 'raise', a.maxRaiseTo);
    else if (a.canCall) t.act(cur.id, 'call');
    else t.act(cur.id, 'check');
  }
  assert('idempotent: handover erreicht', t.stage === 'handover');
  assert('idempotent: pots vorhanden', Array.isArray(t.result.pots) && t.result.pots.length >= 1);
  const potsBefore = JSON.stringify(t.result.pots);
  const stacksBefore = t.players.map((p) => p.stack).join(',');
  const potSumBefore = t.result.pots.reduce((s, p) => s + p.amount, 0);
  t.showdown(); // zweiter Aufruf darf nichts veraendern
  assert('idempotent: pots unveraendert', JSON.stringify(t.result.pots) === potsBefore);
  assert('idempotent: stacks unveraendert', t.players.map((p) => p.stack).join(',') === stacksBefore);
  assert('idempotent: Pot-Summe == Gesamtpot', potSumBefore === t.result.pot);
}

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
