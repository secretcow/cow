// Kuhhandel-Tierkarten: 10 Tiere mit aufsteigendem Wert, je 4 Karten im Deck.
// Fuer Poker zaehlt der "rank" (1..10). Der "value" ist der originale Kuhhandel-Wert.

export const ANIMALS = [
  { rank: 1, name: 'Hahn', value: 10, emoji: '🐓' },
  { rank: 2, name: 'Gans', value: 40, emoji: '🪿' },
  { rank: 3, name: 'Katze', value: 90, emoji: '🐈' },
  { rank: 4, name: 'Hund', value: 160, emoji: '🐕' },
  { rank: 5, name: 'Schaf', value: 250, emoji: '🐑' },
  { rank: 6, name: 'Ziege', value: 350, emoji: '🐐' },
  { rank: 7, name: 'Esel', value: 500, emoji: '🫏' },
  { rank: 8, name: 'Schwein', value: 650, emoji: '🐖' },
  { rank: 9, name: 'Kuh', value: 800, emoji: '🐄' },
  { rank: 10, name: 'Pferd', value: 1000, emoji: '🐎' },
];

const BY_RANK = new Map(ANIMALS.map((a) => [a.rank, a]));

export function animalByRank(rank) {
  return BY_RANK.get(rank);
}

// Baut ein gemischtes Deck aus 40 Karten (jedes Tier 4x).
// Jede Karte: { rank, copy } wobei copy 0..3 die vier identischen Exemplare unterscheidet.
export function buildDeck() {
  const deck = [];
  for (const animal of ANIMALS) {
    for (let copy = 0; copy < 4; copy++) {
      deck.push({ rank: animal.rank, copy });
    }
  }
  return deck;
}

// Fisher-Yates Shuffle.
export function shuffle(deck) {
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

export function cardLabel(card) {
  const a = animalByRank(card.rank);
  return `${a.emoji} ${a.name}`;
}
