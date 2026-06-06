--!strict
-- Kuhhandel-Tierkarten: 10 Tiere mit aufsteigendem Wert, je 4 Karten im Deck.
-- Fuer Poker zaehlt der "rank" (1..10). Der "value" ist der originale Kuhhandel-Wert.
--
-- Faithful Luau port of src/cards.js. Pure logic, no Roblox API dependencies, so
-- this module runs both inside Roblox (Rojo -> ReplicatedStorage.Shared.Cards) and
-- standalone via the luau CLI for testing.

export type Animal = {
	rank: number,
	name: string,
	nameEn: string,
	value: number,
	emoji: string,
}

export type Suit = {
	id: number,
	name: string,
	nameEn: string,
	color: string,
	symbol: string,
}

export type Card = {
	rank: number,
	copy: number,
	suit: number,
}

local Cards = {}

Cards.ANIMALS = {
	{ rank = 1, name = "Hahn", nameEn = "Rooster", value = 10, emoji = "🐓" },
	{ rank = 2, name = "Gans", nameEn = "Goose", value = 40, emoji = "🪿" },
	{ rank = 3, name = "Katze", nameEn = "Cat", value = 90, emoji = "🐈" },
	{ rank = 4, name = "Hund", nameEn = "Dog", value = 160, emoji = "🐕" },
	{ rank = 5, name = "Schaf", nameEn = "Sheep", value = 250, emoji = "🐑" },
	{ rank = 6, name = "Ziege", nameEn = "Goat", value = 350, emoji = "🐐" },
	{ rank = 7, name = "Esel", nameEn = "Donkey", value = 500, emoji = "🫏" },
	{ rank = 8, name = "Schwein", nameEn = "Pig", value = 650, emoji = "🐖" },
	{ rank = 9, name = "Kuh", nameEn = "Cow", value = 800, emoji = "🐄" },
	{ rank = 10, name = "Pferd", nameEn = "Horse", value = 1000, emoji = "🐎" },
} :: { Animal }

-- Vier Farben (Suits). Da das Deck genau 4 Exemplare pro Tier hat, bekommt jedes
-- Exemplar eine eigene Farbe. Ohne aktivierten Flush sind die Farben rein dekorativ.
Cards.SUITS = {
	{ id = 0, name = "Sonne", nameEn = "Sun", color = "#f5b50a", symbol = "☀" },
	{ id = 1, name = "Mond", nameEn = "Moon", color = "#5a8fe6", symbol = "☾" },
	{ id = 2, name = "Klee", nameEn = "Clover", color = "#3fae5a", symbol = "☘" },
	{ id = 3, name = "Herz", nameEn = "Heart", color = "#e2483b", symbol = "♥" },
} :: { Suit }

local BY_RANK: { [number]: Animal } = {}
for _, a in Cards.ANIMALS do
	BY_RANK[a.rank] = a
end

local BY_SUIT: { [number]: Suit } = {}
for _, s in Cards.SUITS do
	BY_SUIT[s.id] = s
end

function Cards.animalByRank(rank: number): Animal?
	return BY_RANK[rank]
end

function Cards.suitById(id: number): Suit?
	return BY_SUIT[id]
end

-- Baut ein Deck aus 40 Karten (jedes Tier 4x, je eine Farbe pro Exemplar).
-- Jede Karte: { rank, copy, suit } wobei copy 0..3 die Exemplare unterscheidet
-- und suit (0..3) der Farbe entspricht (suit === copy).
function Cards.buildDeck(): { Card }
	local deck: { Card } = {}
	for _, animal in Cards.ANIMALS do
		for copy = 0, 3 do
			table.insert(deck, { rank = animal.rank, copy = copy, suit = copy })
		end
	end
	return deck
end

-- Fisher-Yates Shuffle (in place).
function Cards.shuffle(deck: { Card }): { Card }
	for i = #deck, 2, -1 do
		local j = math.random(1, i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

function Cards.cardLabel(card: Card): string
	local a = Cards.animalByRank(card.rank)
	if a then
		return `{a.emoji} {a.name}`
	end
	return "?"
end

return Cards
