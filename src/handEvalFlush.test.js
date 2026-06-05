// Tests fuer den Flush-Modus der Hand-Bewertung.
import { evaluate, compareScores } from './handEval.js';

let pass = 0;
let fail = 0;

function assert(name, cond) {
  if (cond) pass++;
  else {
    fail++;
    console.error('FAIL:', name);
  }
}

// Karte mit explizitem Rang + Farbe.
function c(rank, suit) {
  return { rank, suit, copy: suit };
}

const F = { flush: true };

function cat(cards) {
  return evaluate(cards, F).score[0];
}

// --- Kategorie-Erkennung im Flush-Modus ---
// Flush: 5 Karten gleicher Farbe (suit 0). Kategorie 8.
assert(
  'Flush erkannt (Kat 8)',
  cat([c(1, 0), c(3, 0), c(5, 0), c(7, 0), c(9, 0), c(2, 1), c(4, 2)]) === 8
);
// Straight Flush: 6-7-8-9-10 gleiche Farbe. Kategorie 10.
assert(
  'Straße Flush erkannt (Kat 10)',
  cat([c(6, 2), c(7, 2), c(8, 2), c(9, 2), c(10, 2), c(1, 0), c(2, 1)]) === 10
);
// Wheel-Straight-Flush: 10-1-2-3-4 gleiche Farbe.
assert(
  'Wheel Straße Flush (Kat 10)',
  cat([c(10, 3), c(1, 3), c(2, 3), c(3, 3), c(4, 3), c(8, 0), c(9, 1)]) === 10
);
// Vierling bleibt Kategorie 9 im Flush-Modus.
assert(
  'Vierling im Flush-Modus (Kat 9)',
  cat([c(9, 0), c(9, 1), c(9, 2), c(9, 3), c(2, 0), c(3, 1), c(4, 2)]) === 9
);
// Full House = Kategorie 7.
assert(
  'Full House (Kat 7)',
  cat([c(7, 0), c(7, 1), c(7, 2), c(3, 0), c(3, 1), c(1, 2), c(2, 3)]) === 7
);
// Nur 4 gleiche Farben -> kein Flush (braucht 5). Ranks ohne Strasse -> hohe Karte.
assert(
  'Vier gleiche Farben sind kein Flush',
  cat([c(1, 0), c(3, 0), c(5, 0), c(7, 0), c(9, 1), c(10, 2), c(2, 3)]) === 2
);

// --- Rangfolge-Vergleiche ---
function score(cards) {
  return evaluate(cards, F).score;
}
const flush = [c(1, 0), c(3, 0), c(5, 0), c(7, 0), c(9, 0), c(2, 1), c(4, 2)];
const fullHouse = [c(7, 0), c(7, 1), c(7, 2), c(3, 0), c(3, 1), c(1, 2), c(2, 3)];
const straight = [c(6, 0), c(7, 1), c(8, 2), c(9, 3), c(10, 0), c(1, 1), c(2, 2)];
const quads = [c(9, 0), c(9, 1), c(9, 2), c(9, 3), c(2, 0), c(3, 1), c(4, 2)];
const sflush = [c(6, 2), c(7, 2), c(8, 2), c(9, 2), c(10, 2), c(1, 0), c(2, 1)];

// Flush schlaegt Full House (Short-Deck-Regel, per Simulation bestaetigt).
assert('Flush > Full House', compareScores(score(flush), score(fullHouse)) > 0);
// Full House schlaegt Strasse.
assert('Full House > Strasse', compareScores(score(fullHouse), score(straight)) > 0);
// Vierling schlaegt Flush.
assert('Vierling > Flush', compareScores(score(quads), score(flush)) > 0);
// Straße Flush schlaegt Vierling.
assert('Straße Flush > Vierling', compareScores(score(sflush), score(quads)) > 0);
// Hoeherer Flush gewinnt (Kicker-Vergleich).
const flushHi = [c(2, 0), c(4, 0), c(6, 0), c(8, 0), c(10, 0), c(1, 1), c(3, 2)];
assert('Hoeherer Flush gewinnt', compareScores(score(flushHi), score(flush)) > 0);

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
