import { evaluate, compareScores } from './handEval.js';

let pass = 0;
let fail = 0;

function card(rank, copy = 0) {
  return { rank, copy };
}
// Hilfsfunktion: Karten aus Rang-Liste (copy automatisch verteilt)
function hand(...ranks) {
  const used = new Map();
  return ranks.map((r) => {
    const c = used.get(r) || 0;
    used.set(r, c + 1);
    return card(r, c);
  });
}

function assert(name, cond) {
  if (cond) {
    pass++;
  } else {
    fail++;
    console.error('FAIL:', name);
  }
}

function assertCategory(name, cards, expectedCat) {
  const r = evaluate(cards);
  assert(`${name} -> ${expectedCat} (got ${r.score[0]} ${r.name})`, r.score[0] === expectedCat);
}

// Kategorie-Erkennung (7 Karten -> beste 5)
assertCategory('Vierling', hand(9, 9, 9, 9, 2, 3, 4), 8);
assertCategory('Full House', hand(7, 7, 7, 3, 3, 1, 2), 7);
assertCategory('Strasse 6-10', hand(6, 7, 8, 9, 10, 1, 2), 6);
assertCategory('Strasse 1-5', hand(1, 2, 3, 4, 5, 8, 8), 6);
assertCategory('Drilling', hand(5, 5, 5, 1, 2, 8, 9), 5);
assertCategory('Zwei Paare', hand(5, 5, 8, 8, 2, 3, 1), 4);
assertCategory('Paar', hand(5, 5, 1, 2, 3, 7, 9), 3);
assertCategory('Hohe Karte', hand(1, 2, 3, 4, 6, 7, 9), 2);

// Keine Strasse bei Luecke
assertCategory('Keine Strasse (Luecke)', hand(6, 7, 8, 10, 1, 2, 4), 2);

// Wheel: Pferd zaehlt als niedrige Karte -> Pferd-Hahn-Gans-Katze-Hund ist Strasse
assertCategory('Wheel 10-1-2-3-4', hand(10, 1, 2, 3, 4, 8, 9), 6);
// Pferd ohne 1-2-3-4 ergibt KEINE Wheel
assertCategory('Keine Wheel (10-1-2-3-5)', hand(10, 1, 2, 3, 5, 8, 9), 2);

// Vergleiche
function ev(...ranks) {
  return evaluate(hand(...ranks)).score;
}

// Full House schlaegt Strasse
assert('Full House > Strasse', compareScores(ev(7, 7, 7, 3, 3, 1, 2), ev(6, 7, 8, 9, 10, 1, 1)) > 0);
// Strasse schlaegt Drilling
assert('Strasse > Drilling', compareScores(ev(1, 2, 3, 4, 5, 9, 9), ev(10, 10, 10, 1, 2, 3, 4)) > 0);
// Vierling schlaegt Full House
assert('Vierling > Full House', compareScores(ev(2, 2, 2, 2, 9, 8, 7), ev(10, 10, 10, 9, 9, 1, 2)) > 0);
// Hoeheres Paar gewinnt
assert('Hoeheres Paar gewinnt', compareScores(ev(9, 9, 1, 2, 3, 4, 6), ev(8, 8, 1, 2, 3, 4, 6)) > 0);
// Kicker entscheidet bei gleichem Paar
assert('Kicker entscheidet', compareScores(ev(9, 9, 10, 2, 3, 1, 1), ev(9, 9, 8, 2, 3, 1, 1)) > 0);
// Hoehere Strasse gewinnt
assert('Hoehere Strasse gewinnt', compareScores(ev(6, 7, 8, 9, 10, 1, 1), ev(1, 2, 3, 4, 5, 9, 9)) > 0);
// Gleiche Hand -> unentschieden
assert('Split-Pot Gleichstand', compareScores(ev(9, 9, 5, 5, 10, 1, 2), ev(9, 9, 5, 5, 10, 3, 4)) === 0);

// Wheel ist die NIEDRIGSTE Strasse: 1-2-3-4-5 schlaegt die Wheel
assert('1-2-3-4-5 > Wheel', compareScores(ev(1, 2, 3, 4, 5, 8, 9), ev(10, 1, 2, 3, 4, 8, 9)) > 0);
// Wheel schlaegt Drilling
assert('Wheel > Drilling', compareScores(ev(10, 1, 2, 3, 4, 8, 9), ev(7, 7, 7, 1, 2, 5, 6)) > 0);
// Hohe Strasse (6-10) schlaegt Wheel
assert('6-7-8-9-10 > Wheel', compareScores(ev(6, 7, 8, 9, 10, 1, 1), ev(10, 1, 2, 3, 4, 8, 8)) > 0);

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
