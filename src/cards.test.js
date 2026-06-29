// Sichert die Integritaet des Kartensystems ab: Ein versehentlicher Edit an den
// Tier-Werten, der Deck-Zusammensetzung oder den Farben wuerde das ganze Spiel
// verfaelschen – diese Tests fangen das.
import { ANIMALS, SUITS, animalByRank, suitById, buildDeck, shuffle, cardLabel } from './cards.js';

let pass = 0;
let fail = 0;
function assert(name, cond) {
  if (cond) pass++;
  else {
    fail++;
    console.error('FAIL:', name);
  }
}

// --- ANIMALS ---
assert('10 Tiere', ANIMALS.length === 10);
assert('Raenge 1..10 lueckenlos', ANIMALS.every((a, i) => a.rank === i + 1));
assert('Werte streng aufsteigend', ANIMALS.every((a, i) => i === 0 || a.value > ANIMALS[i - 1].value));
assert('jedes Tier hat name/nameEn/emoji', ANIMALS.every((a) => a.name && a.nameEn && a.emoji));
assert('Hahn=10, Pferd=1000', ANIMALS[0].value === 10 && ANIMALS[9].value === 1000);

// --- SUITS ---
assert('4 Farben', SUITS.length === 4);
assert('Farb-IDs 0..3', SUITS.every((s, i) => s.id === i));
assert('jede Farbe hat name/symbol/color', SUITS.every((s) => s.name && s.symbol && s.color));

// --- Lookups ---
assert('animalByRank(7) == Esel', animalByRank(7).name === 'Esel');
assert('animalByRank(99) undefined', animalByRank(99) === undefined);
assert('suitById(0) == Sonne', suitById(0).name === 'Sonne');

// --- buildDeck ---
const deck = buildDeck();
assert('Deck hat 40 Karten', deck.length === 40);
assert('genau 4 Karten pro Rang', ANIMALS.every((a) => deck.filter((c) => c.rank === a.rank).length === 4));
assert('pro Rang Kopien 0..3', ANIMALS.every((a) => {
  const copies = deck.filter((c) => c.rank === a.rank).map((c) => c.copy).sort();
  return copies.join(',') === '0,1,2,3';
}));
assert('suit == copy (jede Kopie eine Farbe)', deck.every((c) => c.suit === c.copy));
assert('keine doppelte Rang/Kopie-Kombination', new Set(deck.map((c) => `${c.rank}-${c.copy}`)).size === 40);

// --- shuffle ---
const before = buildDeck();
const key = (c) => `${c.rank}-${c.copy}`;
const shuffled = shuffle(buildDeck());
assert('shuffle behaelt 40 Karten', shuffled.length === 40);
assert('shuffle behaelt dieselbe Multimenge', JSON.stringify(before.map(key).sort()) === JSON.stringify(shuffled.map(key).sort()));

// --- cardLabel ---
assert('cardLabel enthaelt Emoji + Name', cardLabel({ rank: 9, copy: 0 }) === '🐄 Kuh');

console.log(`\n${pass} bestanden, ${fail} fehlgeschlagen`);
process.exit(fail === 0 ? 0 : 1);
