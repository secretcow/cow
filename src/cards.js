// Kuhhandel-Tierkarten: 10 Tiere mit aufsteigendem Wert, je 4 Karten im Deck.
// Fuer Poker zaehlt der "rank" (1..10). Der "value" ist der originale Kuhhandel-Wert.

export const ANIMALS = [
  { rank: 1, name: 'Hahn', nameEn: 'Rooster', value: 10, emoji: '🐓' },
  { rank: 2, name: 'Gans', nameEn: 'Goose', value: 40, emoji: '🪿' },
  { rank: 3, name: 'Katze', nameEn: 'Cat', value: 90, emoji: '🐈' },
  { rank: 4, name: 'Hund', nameEn: 'Dog', value: 160, emoji: '🐕' },
  { rank: 5, name: 'Schaf', nameEn: 'Sheep', value: 250, emoji: '🐑' },
  { rank: 6, name: 'Ziege', nameEn: 'Goat', value: 350, emoji: '🐐' },
  { rank: 7, name: 'Esel', nameEn: 'Donkey', value: 500, emoji: '🫏' },
  { rank: 8, name: 'Schwein', nameEn: 'Pig', value: 650, emoji: '🐖' },
  { rank: 9, name: 'Kuh', nameEn: 'Cow', value: 800, emoji: '🐄' },
  { rank: 10, name: 'Pferd', nameEn: 'Horse', value: 1000, emoji: '🐎' },
];

// Vier Farben (Suits). Da das Deck genau 4 Exemplare pro Tier hat, bekommt jedes
// Exemplar eine eigene Farbe. Ohne aktivierten Flush sind die Farben rein dekorativ.
export const SUITS = [
  { id: 0, name: 'Sonne', nameEn: 'Sun', color: '#f5b50a', symbol: '☀' },
  { id: 1, name: 'Mond', nameEn: 'Moon', color: '#5a8fe6', symbol: '☾' },
  { id: 2, name: 'Klee', nameEn: 'Clover', color: '#3fae5a', symbol: '☘' },
  { id: 3, name: 'Herz', nameEn: 'Heart', color: '#e2483b', symbol: '♥' },
];

const BY_RANK = new Map(ANIMALS.map((a) => [a.rank, a]));
const BY_SUIT = new Map(SUITS.map((s) => [s.id, s]));

export function animalByRank(rank) {
  return BY_RANK.get(rank);
}

export function suitById(id) {
  return BY_SUIT.get(id);
}

// Baut ein gemischtes Deck aus 40 Karten (jedes Tier 4x, je eine Farbe pro Exemplar).
// Jede Karte: { rank, copy, suit } wobei copy 0..3 die Exemplare unterscheidet
// und suit (0..3) der Farbe entspricht (suit === copy).
export function buildDeck() {
  const deck = [];
  for (const animal of ANIMALS) {
    for (let copy = 0; copy < 4; copy++) {
      deck.push({ rank: animal.rank, copy, suit: copy });
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
