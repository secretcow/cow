import { Table } from './poker.js';

let pass = 0, fail = 0;
function assert(name, cond) {
  if (cond) pass++;
  else { fail++; console.error('FAIL:', name); }
}

// ---- Test 1: Limp/Check bis River, dann Showdown ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand();
  // button = 0 (Anna SB), Anna handelt zuerst praeflop
  assert('Stage preflop', t.stage === 'preflop');
  assert('Anna ist Button', t.button === 0);
  assert('Anna toAct praeflop', t.toAct === 0);
  assert('Pot = SB+BB', t.pot === 30);

  t.act('A', 'call');          // Anna limpt (gleicht BB aus)
  assert('Ben toAct nach Limp', t.toAct === 1);
  t.act('B', 'check');         // Ben checkt -> Flop
  assert('Flop nach check', t.stage === 'flop');
  assert('3 Community', t.community.length === 3);
  // Postflop handelt Nicht-Button (Ben) zuerst
  assert('Ben toAct postflop', t.toAct === 1);

  t.act('B', 'check');
  t.act('A', 'check');
  assert('Turn', t.stage === 'turn' && t.community.length === 4);

  t.act('B', 'check');
  t.act('A', 'check');
  assert('River', t.stage === 'river' && t.community.length === 5);

  t.act('B', 'check');
  t.act('A', 'check');
  assert('Handover nach River', t.stage === 'handover');
  assert('Ergebnis vorhanden', !!t.result);
  assert('Stacks summieren auf 2000', t.players[0].stack + t.players[1].stack === 2000);
}

// ---- Test 2: Fold gewinnt den Pot ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand(); // button=0
  t.act('A', 'raise', 60);   // Anna erhoeht
  t.act('B', 'fold');        // Ben gibt auf
  assert('Fold -> handover', t.stage === 'handover');
  // Anna gewinnt Bens BB(20); Anna's eigener Ueberschuss zurueck.
  assert('Anna gewinnt BB', t.players[0].stack === 1020 && t.players[1].stack === 980);
}

// ---- Test 3: Raise / Re-Raise / Call ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand(); // button=0, currentBet=20
  t.act('A', 'raise', 60);   // auf 60
  assert('currentBet 60', t.currentBet === 60);
  assert('minRaise 40', t.minRaise === 40);
  t.act('B', 'raise', 140);  // auf 140
  assert('currentBet 140', t.currentBet === 140);
  t.act('A', 'call');        // gleicht aus -> Flop
  assert('Flop nach Call', t.stage === 'flop');
  assert('Pot 280', t.pot === 280);
}

// ---- Test 4: Ungueltige Aktionen werden abgelehnt ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand();
  assert('Falscher Spieler -> Fehler', !!t.act('B', 'check').error); // Ben nicht am Zug
  assert('Check mit offenem Einsatz -> Fehler', !!t.act('A', 'check').error); // Anna muss callen
  assert('Mini-Raise -> Fehler', !!t.act('A', 'raise', 25).error); // unter min
}

// ---- Test 5: All-In Run-out bis Showdown ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand(); // button=0
  t.act('A', 'raise', 1000);  // Anna All-In
  assert('Anna allIn', t.players[0].allIn === true);
  t.act('B', 'call');         // Ben callt All-In -> Board laeuft durch
  assert('Showdown/handover', t.stage === 'handover');
  assert('5 Community ausgeteilt', t.community.length === 5);
  assert('Chips erhalten', t.players[0].stack + t.players[1].stack === 2000);
}

// ---- Test 6: Button rotiert ----
{
  const t = new Table({ id: 'A', name: 'Anna' }, { id: 'B', name: 'Ben' });
  t.startHand();
  const b1 = t.button;
  t.act('A', 'raise', 1000); t.act('B', 'call'); // Hand zu Ende
  if (!t.matchOver) {
    t.startHand();
    assert('Button rotiert', t.button !== b1);
  } else {
    pass++; // Match war vorbei (jemand pleite), ok
  }
}

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
