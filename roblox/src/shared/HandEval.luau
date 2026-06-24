--!strict
-- Poker-Hand-Bewertung fuer das Kuhhandel-Deck (10 Werte, je 4 Exemplare/Farben).
-- Faithful Luau port of src/handEval.js.
--
-- Zwei Modi:
--   Flush AUS (Standard): keine Farben-Wertung -> kein Flush/Straight Flush.
--     Rangfolge: 8 Vierling, 7 Full House, 6 Strasse, 5 Drilling,
--                4 Zwei Paare, 3 Paar, 2 Hohe Karte.
--   Flush AN: Farben zaehlen. Flush rangt HOEHER als Full House (Short-Deck-Regel).
--     Rangfolge: 10 Strasse Flush, 9 Vierling, 8 Flush, 7 Full House,
--                6 Strasse, 5 Drilling, 4 Zwei Paare, 3 Paar, 2 Hohe Karte.
--
-- Jede Hand wird als Score-Array kodiert: {kategorie, ...tiebreaker}.
-- Vergleich lexikografisch, groesser = besser.

local HandEval = {}

-- Eine Karte (rank Pflicht, suit fuer Flush-Modus).
export type ScoreCard = {
	rank: number,
	suit: number?,
	copy: number?,
}

export type Score = { number }

export type EvalResult = {
	score: Score,
	name: string,
	cards: { ScoreCard },
}

HandEval.CATEGORY_NAMES = {
	[8] = "Vierling",
	[7] = "Full House",
	[6] = "Straße",
	[5] = "Drilling",
	[4] = "Zwei Paare",
	[3] = "Paar",
	[2] = "Hohe Karte",
} :: { [number]: string }

-- Kategorienamen im Flush-Modus (eigene Nummerierung).
HandEval.CATEGORY_NAMES_FLUSH = {
	[10] = "Straße Flush",
	[9] = "Vierling",
	[8] = "Flush",
	[7] = "Full House",
	[6] = "Straße",
	[5] = "Drilling",
	[4] = "Zwei Paare",
	[3] = "Paar",
	[2] = "Hohe Karte",
} :: { [number]: string }

type Group = { number } -- {rank, count}

type RankAnalysis = {
	sorted: { number },
	groups: { Group },
	counts4: number,
	counts3: Group?,
	pairs: { number },
	distinct: { number },
	straightHigh: number?,
}

-- Analysiert die Rang-Struktur von 5 Werten.
local function analyzeRanks(ranks: { number }): RankAnalysis
	local sorted = table.clone(ranks)
	table.sort(sorted, function(a, b)
		return a > b
	end) -- absteigend

	local counts: { [number]: number } = {}
	for _, r in sorted do
		counts[r] = (counts[r] or 0) + 1
	end

	local groups: { Group } = {}
	for r, c in counts do
		table.insert(groups, { r, c })
	end
	table.sort(groups, function(a, b)
		if b[2] ~= a[2] then
			return a[2] > b[2]
		end
		return a[1] > b[1]
	end)

	local counts4 = groups[1][2]
	local counts3: Group? = nil
	for _, g in groups do
		if g[2] == 3 then
			counts3 = g
			break
		end
	end
	local pairsList: { number } = {}
	for _, g in groups do
		if g[2] == 2 then
			table.insert(pairsList, g[1])
		end
	end

	local distinct: { number } = {}
	for r in counts do
		table.insert(distinct, r)
	end
	table.sort(distinct, function(a, b)
		return a > b
	end)

	local isStraight = #distinct == 5 and (distinct[1] - distinct[5] == 4)
	-- Wheel: Rang 10 zaehlt zusaetzlich als niedrigste Karte (10-1-2-3-4).
	local isWheel = #distinct == 5
		and distinct[1] == 10
		and distinct[2] == 4
		and distinct[3] == 3
		and distinct[4] == 2
		and distinct[5] == 1

	-- High-Card der Strasse (Wheel = 4, damit unter 1-2-3-4-5).
	local straightHigh: number? = nil
	if isStraight then
		straightHigh = distinct[1]
	elseif isWheel then
		straightHigh = 4
	end

	return {
		sorted = sorted,
		groups = groups,
		counts4 = counts4,
		counts3 = counts3,
		pairs = pairsList,
		distinct = distinct,
		straightHigh = straightHigh,
	}
end

-- Bewertet genau 5 Karten.
local function score5(cards: { ScoreCard }, flushEnabled: boolean): Score
	local ranks: { number } = {}
	for _, c in cards do
		table.insert(ranks, c.rank)
	end
	local a = analyzeRanks(ranks)
	local sorted, groups, counts4, counts3, pairsList, straightHigh =
		a.sorted, a.groups, a.counts4, a.counts3, a.pairs, a.straightHigh

	local isFlush = false
	if flushEnabled then
		isFlush = true
		for _, c in cards do
			if c.suit ~= cards[1].suit then
				isFlush = false
				break
			end
		end
	end
	local isStraightFlush = isFlush and straightHigh ~= nil

	-- Kicker (erster Sitz mit count==1) und alle count-1-Kicker absteigend.
	local function kickerOfCount1(): number
		for _, g in groups do
			if g[2] == 1 then
				return g[1]
			end
		end
		return 0
	end
	local function kickersDesc(): { number }
		local ks: { number } = {}
		for _, g in groups do
			if g[2] == 1 then
				table.insert(ks, g[1])
			end
		end
		table.sort(ks, function(x, y)
			return x > y
		end)
		return ks
	end

	if flushEnabled then
		-- Nummerierung mit Flush (10..2).
		if isStraightFlush then
			return { 10, straightHigh :: number }
		end
		if counts4 == 4 then
			return { 9, groups[1][1], kickerOfCount1() }
		end
		if isFlush then
			local r: Score = { 8 }
			for _, v in sorted do
				table.insert(r, v)
			end
			return r
		end
		if counts3 and #pairsList >= 1 then
			return { 7, counts3[1], pairsList[1] }
		end
		if straightHigh ~= nil then
			return { 6, straightHigh }
		end
		if counts3 then
			local r: Score = { 5, counts3[1] }
			for _, k in kickersDesc() do
				table.insert(r, k)
			end
			return r
		end
		if #pairsList >= 2 then
			local sp = table.clone(pairsList)
			table.sort(sp, function(x, y)
				return x > y
			end)
			return { 4, sp[1], sp[2], kickerOfCount1() }
		end
		if #pairsList == 1 then
			local r: Score = { 3, pairsList[1] }
			for _, k in kickersDesc() do
				table.insert(r, k)
			end
			return r
		end
		local r: Score = { 2 }
		for _, v in sorted do
			table.insert(r, v)
		end
		return r
	end

	-- Nummerierung ohne Flush (8..2).
	if counts4 == 4 then
		return { 8, groups[1][1], kickerOfCount1() }
	end
	if counts3 and #pairsList >= 1 then
		return { 7, counts3[1], pairsList[1] }
	end
	if straightHigh ~= nil then
		return { 6, straightHigh }
	end
	if counts3 then
		local r: Score = { 5, counts3[1] }
		for _, k in kickersDesc() do
			table.insert(r, k)
		end
		return r
	end
	if #pairsList >= 2 then
		local sp = table.clone(pairsList)
		table.sort(sp, function(x, y)
			return x > y
		end)
		return { 4, sp[1], sp[2], kickerOfCount1() }
	end
	if #pairsList == 1 then
		local r: Score = { 3, pairsList[1] }
		for _, k in kickersDesc() do
			table.insert(r, k)
		end
		return r
	end
	local r: Score = { 2 }
	for _, v in sorted do
		table.insert(r, v)
	end
	return r
end

function HandEval.compareScores(a: Score, b: Score): number
	local len = math.max(#a, #b)
	for i = 1, len do
		local av = a[i] or 0
		local bv = b[i] or 0
		if av ~= bv then
			return av - bv
		end
	end
	return 0
end

-- Alle C(n,5)-Kombinationen der Indizes (1-basiert) erzeugen.
local function combinations5(n: number): { { number } }
	local result: { { number } } = {}
	for a = 1, n - 4 do
		for b = a + 1, n - 3 do
			for c = b + 1, n - 2 do
				for d = c + 1, n - 1 do
					for e = d + 1, n do
						table.insert(result, { a, b, c, d, e })
					end
				end
			end
		end
	end
	return result
end

-- Beste 5-Karten-Hand aus beliebig vielen Karten (typisch 7).
export type EvalOptions = { flush: boolean? }

function HandEval.evaluate(cards: { ScoreCard }, options: EvalOptions?): EvalResult
	local opts = options or {}
	local flushEnabled = not not opts.flush
	local names = if flushEnabled then HandEval.CATEGORY_NAMES_FLUSH else HandEval.CATEGORY_NAMES
	local best: Score? = nil
	local bestIdx: { number }? = nil
	for _, combo in combinations5(#cards) do
		local picked: { ScoreCard } = {}
		for _, i in combo do
			table.insert(picked, cards[i])
		end
		local s = score5(picked, flushEnabled)
		if best == nil or HandEval.compareScores(s, best) > 0 then
			best = s
			bestIdx = combo
		end
	end
	local b = best :: Score
	local bi = bestIdx :: { number }
	local bestCards: { ScoreCard } = {}
	for _, i in bi do
		table.insert(bestCards, cards[i])
	end
	return {
		score = b,
		name = names[b[1]],
		cards = bestCards,
	}
end

return HandEval
