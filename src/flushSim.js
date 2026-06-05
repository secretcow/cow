// Monte-Carlo: Wie haeufig sind Flush vs. Full House (und hoeher) im 40-Karten-Deck?
// Ziel: korrekte Rangfolge bestimmen (seltener = staerker).
// Aufruf: node src/flushSim.js [iterations]

import { buildDeck, shuffle } from './cards.js';

const N = Number(process.argv[2]) || 2_000_000;

// Pruefe in 7 Karten, ob eine bestimmte Kategorie erreichbar ist (unabhaengig von Rangfolge).
function analyze(cards) {
  const rankCounts = new Map();
  const suitCounts = new Map();
  for (const c of cards) {
    rankCounts.set(c.rank, (rankCounts.get(c.rank) || 0) + 1);
    suitCounts.set(c.suit, (suitCounts.get(c.suit) || 0) + 1);
  }
  const counts = [...rankCounts.values()].sort((a, b) => b - a);
  const maxSuit = Math.max(...suitCounts.values());

  const hasQuads = counts[0] >= 4;
  const trips = counts.filter((c) => c === 3).length;
  const pairs = counts.filter((c) => c === 2).length;
  const hasFullHouse = (counts[0] >= 3 && (counts[1] >= 2 || trips >= 2));
  const hasFlush = maxSuit >= 5;

  // Strasse (inkl. Wheel: Pferd 10 zaehlt auch tief vor 1)
  const present = new Set([...rankCounts.keys()]);
  const lowSet = new Set(present);
  if (present.has(10)) lowSet.add(0); // 10 als tiefe Karte (vor 1)
  const isStraight = (set) => {
    const vals = [...set].sort((a, b) => a - b);
    let run = 1;
    for (let i = 1; i < vals.length; i++) {
      if (vals[i] === vals[i - 1] + 1) {
        run++;
        if (run >= 5) return true;
      } else run = 1;
    }
    return false;
  };
  const hasStraight = isStraight(present) || isStraight(lowSet);

  return { hasQuads, hasFullHouse, hasFlush, hasStraight };
}

let flush = 0,
  fullHouse = 0,
  quads = 0,
  straight = 0;

for (let i = 0; i < N; i++) {
  const deck = shuffle(buildDeck());
  const seven = deck.slice(0, 7);
  const a = analyze(seven);
  if (a.hasFlush) flush++;
  if (a.hasFullHouse) fullHouse++;
  if (a.hasQuads) quads++;
  if (a.hasStraight) straight++;
}

const pct = (x) => ((x / N) * 100).toFixed(4) + '%';
console.log(`Iterationen: ${N.toLocaleString()}`);
console.log(`Vierling     : ${pct(quads)}`);
console.log(`Full House   : ${pct(fullHouse)}`);
console.log(`Flush        : ${pct(flush)}`);
console.log(`Strasse      : ${pct(straight)}`);
console.log('---');
console.log(
  flush < fullHouse
    ? 'Flush ist SELTENER als Full House -> Flush RANGT HOEHER.'
    : 'Flush ist HAEUFIGER als Full House -> Flush rangt NIEDRIGER (unter Full House).'
);
