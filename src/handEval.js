// Poker-Hand-Bewertung fuer das Kuhhandel-Deck (10 Werte, je 4 Exemplare/Farben).
//
// Zwei Modi:
//   Flush AUS (Standard): keine Farben-Wertung -> kein Flush/Straight Flush.
//     Rangfolge: 8 Vierling, 7 Full House, 6 Strasse, 5 Drilling,
//                4 Zwei Paare, 3 Paar, 2 Hohe Karte.
//   Flush AN: Farben zaehlen. Per Monte-Carlo (40-Karten-Deck) bestaetigt:
//     Flush ist seltener als Full House -> Flush rangt HOEHER (Short-Deck-Regel).
//     Rangfolge: 10 Straße Flush, 9 Vierling, 8 Flush, 7 Full House,
//                6 Strasse, 5 Drilling, 4 Zwei Paare, 3 Paar, 2 Hohe Karte.
//
// Jede Hand wird als Score-Array kodiert: [kategorie, ...tiebreaker].
// Vergleich lexikografisch, groesser = besser.

export const CATEGORY_NAMES = {
  8: 'Vierling',
  7: 'Full House',
  6: 'Straße',
  5: 'Drilling',
  4: 'Zwei Paare',
  3: 'Paar',
  2: 'Hohe Karte',
};

// Kategorienamen im Flush-Modus (eigene Nummerierung).
export const CATEGORY_NAMES_FLUSH = {
  10: 'Straße Flush',
  9: 'Vierling',
  8: 'Flush',
  7: 'Full House',
  6: 'Straße',
  5: 'Drilling',
  4: 'Zwei Paare',
  3: 'Paar',
  2: 'Hohe Karte',
};

// Analysiert die Rang-Struktur von 5 Werten.
function analyzeRanks(ranks) {
  const sorted = [...ranks].sort((a, b) => b - a); // absteigend

  const counts = new Map();
  for (const r of sorted) counts.set(r, (counts.get(r) || 0) + 1);

  const groups = [...counts.entries()].sort((a, b) => {
    if (b[1] !== a[1]) return b[1] - a[1];
    return b[0] - a[0];
  });

  const counts4 = groups[0][1];
  const counts3 = groups.find((g) => g[1] === 3);
  const pairs = groups.filter((g) => g[1] === 2).map((g) => g[0]);

  const distinct = [...counts.keys()].sort((a, b) => b - a);
  const isStraight = distinct.length === 5 && distinct[0] - distinct[4] === 4;
  // Wheel: das Pferd (10) zaehlt zusaetzlich als niedrigste Karte (10-1-2-3-4).
  const isWheel =
    distinct.length === 5 &&
    distinct[0] === 10 &&
    distinct[1] === 4 &&
    distinct[2] === 3 &&
    distinct[3] === 2 &&
    distinct[4] === 1;

  // High-Card der Strasse (Wheel = 4, damit unter 1-2-3-4-5).
  let straightHigh = null;
  if (isStraight) straightHigh = distinct[0];
  else if (isWheel) straightHigh = 4;

  return { sorted, groups, counts4, counts3, pairs, distinct, straightHigh };
}

// Bewertet genau 5 Karten. cards: [{rank, suit}].
// flushEnabled: ob Flush/Straight Flush gewertet werden.
function score5(cards, flushEnabled) {
  const ranks = cards.map((c) => c.rank);
  const a = analyzeRanks(ranks);
  const { sorted, groups, counts4, counts3, pairs, straightHigh } = a;

  const isFlush =
    flushEnabled && cards.every((c) => c.suit === cards[0].suit);
  const isStraightFlush = isFlush && straightHigh !== null;

  if (flushEnabled) {
    // Nummerierung mit Flush (10..2).
    if (isStraightFlush) return [10, straightHigh];
    if (counts4 === 4) {
      const quad = groups[0][0];
      const kicker = groups.find((g) => g[1] === 1)[0];
      return [9, quad, kicker];
    }
    if (isFlush) return [8, ...sorted];
    if (counts3 && pairs.length >= 1) return [7, counts3[0], pairs[0]];
    if (straightHigh !== null) return [6, straightHigh];
    if (counts3) {
      const kickers = groups
        .filter((g) => g[1] === 1)
        .map((g) => g[0])
        .sort((x, y) => y - x);
      return [5, counts3[0], ...kickers];
    }
    if (pairs.length >= 2) {
      const [hi, lo] = pairs.sort((x, y) => y - x);
      const kicker = groups.find((g) => g[1] === 1)[0];
      return [4, hi, lo, kicker];
    }
    if (pairs.length === 1) {
      const kickers = groups
        .filter((g) => g[1] === 1)
        .map((g) => g[0])
        .sort((x, y) => y - x);
      return [3, pairs[0], ...kickers];
    }
    return [2, ...sorted];
  }

  // Nummerierung ohne Flush (8..2) — unveraendert.
  if (counts4 === 4) {
    const quad = groups[0][0];
    const kicker = groups.find((g) => g[1] === 1)[0];
    return [8, quad, kicker];
  }
  if (counts3 && pairs.length >= 1) return [7, counts3[0], pairs[0]];
  if (straightHigh !== null) return [6, straightHigh];
  if (counts3) {
    const kickers = groups
      .filter((g) => g[1] === 1)
      .map((g) => g[0])
      .sort((x, y) => y - x);
    return [5, counts3[0], ...kickers];
  }
  if (pairs.length >= 2) {
    const [hi, lo] = pairs.sort((x, y) => y - x);
    const kicker = groups.find((g) => g[1] === 1)[0];
    return [4, hi, lo, kicker];
  }
  if (pairs.length === 1) {
    const kickers = groups
      .filter((g) => g[1] === 1)
      .map((g) => g[0])
      .sort((x, y) => y - x);
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
// cards: Array von { rank, suit, copy }.
// options: { flush?: boolean }
export function evaluate(cards, options = {}) {
  const flushEnabled = !!options.flush;
  const names = flushEnabled ? CATEGORY_NAMES_FLUSH : CATEGORY_NAMES;
  let best = null;
  let bestIdx = null;
  for (const combo of combinations5(cards.length)) {
    const s = score5(
      combo.map((i) => cards[i]),
      flushEnabled
    );
    if (!best || compareScores(s, best) > 0) {
      best = s;
      bestIdx = combo;
    }
  }
  return {
    score: best,
    name: names[best[0]],
    cards: bestIdx.map((i) => cards[i]),
  };
}
