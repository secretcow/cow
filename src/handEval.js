// Poker-Hand-Bewertung fuer das Kuhhandel-Deck.
// Besonderheit: Karten haben keine Farben (nur 10 Werte, je 4-mal).
// -> Flush und Straight-Flush sind unmoeglich.
//
// Rangfolge (hoch -> niedrig):
//   8 Vierling (Four of a kind)
//   7 Full House
//   6 Strasse (Straight)        -- 5 aufeinanderfolgende Werte 1..10, kein Wrap
//   5 Drilling (Three of a kind)
//   4 Zwei Paare (Two Pair)
//   3 Paar (Pair)
//   2 Hohe Karte (High Card)
//
// Jede Hand wird als Score-Array kodiert: [kategorie, ...tiebreaker].
// Vergleich erfolgt lexikografisch, groesser = besser.

export const CATEGORY_NAMES = {
  8: 'Vierling',
  7: 'Full House',
  6: 'Straße',
  5: 'Drilling',
  4: 'Zwei Paare',
  3: 'Paar',
  2: 'Hohe Karte',
};

// Bewertet genau 5 Werte (ranks). Gibt Score-Array zurueck.
function score5(ranks) {
  const sorted = [...ranks].sort((a, b) => b - a); // absteigend

  const counts = new Map();
  for (const r of sorted) counts.set(r, (counts.get(r) || 0) + 1);

  // Gruppen: nach Anzahl, dann nach Wert sortiert.
  const groups = [...counts.entries()].sort((a, b) => {
    if (b[1] !== a[1]) return b[1] - a[1];
    return b[0] - a[0];
  });

  const counts4 = groups[0][1];
  const counts3 = groups.find((g) => g[1] === 3);
  const pairs = groups.filter((g) => g[1] === 2).map((g) => g[0]);

  const distinct = [...counts.keys()].sort((a, b) => b - a);
  const isStraight =
    distinct.length === 5 && distinct[0] - distinct[4] === 4;

  if (counts4 === 4) {
    const quad = groups[0][0];
    const kicker = groups.find((g) => g[1] === 1)[0];
    return [8, quad, kicker];
  }
  if (counts3 && pairs.length >= 1) {
    return [7, counts3[0], pairs[0]];
  }
  if (isStraight) {
    return [6, distinct[0]];
  }
  if (counts3) {
    const kickers = groups
      .filter((g) => g[1] === 1)
      .map((g) => g[0])
      .sort((a, b) => b - a);
    return [5, counts3[0], ...kickers];
  }
  if (pairs.length >= 2) {
    const [hi, lo] = pairs.sort((a, b) => b - a);
    const kicker = groups.find((g) => g[1] === 1)[0];
    return [4, hi, lo, kicker];
  }
  if (pairs.length === 1) {
    const kickers = groups
      .filter((g) => g[1] === 1)
      .map((g) => g[0])
      .sort((a, b) => b - a);
    return [3, pairs[0], ...kickers];
  }
  return [2, ...sorted];
}

export function compareScores(a, b) {
  const len = Math.max(a.length, b.length);
  for (let i = 0; i < len; i++) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    if (av !== bv) return av - bv;
  }
  return 0;
}

// Alle C(n,5)-Kombinationen der Indizes erzeugen.
function combinations5(n) {
  const result = [];
  for (let a = 0; a < n - 4; a++)
    for (let b = a + 1; b < n - 3; b++)
      for (let c = b + 1; c < n - 2; c++)
        for (let d = c + 1; d < n - 1; d++)
          for (let e = d + 1; e < n; e++) result.push([a, b, c, d, e]);
  return result;
}

// Beste 5-Karten-Hand aus beliebig vielen Karten (typisch 7).
// cards: Array von { rank, copy }. Gibt { score, name, ranks } zurueck.
export function evaluate(cards) {
  const ranks = cards.map((c) => c.rank);
  let best = null;
  let bestIdx = null;
  for (const combo of combinations5(ranks.length)) {
    const s = score5(combo.map((i) => ranks[i]));
    if (!best || compareScores(s, best) > 0) {
      best = s;
      bestIdx = combo;
    }
  }
  return {
    score: best,
    name: CATEGORY_NAMES[best[0]],
    cards: bestIdx.map((i) => cards[i]),
  };
}
