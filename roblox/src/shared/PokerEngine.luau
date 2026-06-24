--!nonstrict
-- Texas Hold'em Engine fuer 2-6 Spieler mit Brainrot-Karten.
-- Faithful Luau port of src/poker.js. Autoritativer Spielzustand: Clients schicken
-- nur Aktionen, der Server validiert alles. Button-/Blind-Rotation, korrekte
-- Setzreihenfolge, Side Pots, optionaler Flush-Modus, Turnier- und Cash-Game-Modus.
--
-- WICHTIG zur Indexierung: Im JS-Original sind Spieler 0-basiert. In dieser Luau-
-- Portierung sind Sitze 1-basiert (Lua-Arrays), aber die gesamte Modulo-Arithmetik
-- ist intern konsistent. Die view() liefert seat-Indizes 1-basiert.

local Cards = require(script and script.Parent.Cards or "./Cards")
local HandEval = require(script and script.Parent.HandEval or "./HandEval")

local buildDeck = Cards.buildDeck
local shuffle = Cards.shuffle
local evaluate = HandEval.evaluate
local compareScores = HandEval.compareScores

local PokerEngine = {}

PokerEngine.STARTING_STACK = 1000
PokerEngine.SMALL_BLIND = 10
PokerEngine.BIG_BLIND = 20

-- Turnier-Blindstruktur: steigt mit jedem Level.
PokerEngine.TOURNEY_BLINDS = {
	{ sb = 10, bb = 20 },
	{ sb = 15, bb = 30 },
	{ sb = 25, bb = 50 },
	{ sb = 50, bb = 100 },
	{ sb = 75, bb = 150 },
	{ sb = 100, bb = 200 },
	{ sb = 150, bb = 300 },
	{ sb = 200, bb = 400 },
	{ sb = 300, bb = 600 },
	{ sb = 500, bb = 1000 },
	{ sb = 750, bb = 1500 },
	{ sb = 1000, bb = 2000 },
}

local STARTING_STACK = PokerEngine.STARTING_STACK
local SMALL_BLIND = PokerEngine.SMALL_BLIND
local BIG_BLIND = PokerEngine.BIG_BLIND
local TOURNEY_BLINDS = PokerEngine.TOURNEY_BLINDS

-- ---- kleine Helfer ----
local function round(x: number): number
	return math.floor(x + 0.5)
end

-- Aequivalent zu Math.floor(Number(v)): nil/NaN/inf -> nil.
local function toInt(v: any): number?
	local n: number?
	if type(v) == "number" then
		n = v
	else
		n = tonumber(v)
	end
	if n == nil then
		return nil
	end
	if n ~= n then
		return nil -- NaN
	end
	if n == math.huge or n == -math.huge then
		return nil
	end
	return math.floor(n)
end

-- Binomialkoeffizient C(n, k).
local function nCk(n: number, k: number): number
	if k < 0 or k > n then
		return 0
	end
	if k == 0 or k == n then
		return 1
	end
	k = math.min(k, n - k)
	local r = 1
	for j = 0, k - 1 do
		r = (r * (n - j)) / (j + 1)
	end
	return round(r)
end

-- Live-Handstaerke waehrend des Setzens.
local function liveCategory(hole, community, flush)
	local cards = {}
	for _, c in hole do
		table.insert(cards, c)
	end
	for _, c in community do
		table.insert(cards, c)
	end
	if #cards >= 5 then
		return evaluate(cards, { flush = flush }).score[1]
	end
	local counts = {}
	for _, c in cards do
		counts[c.rank] = (counts[c.rank] or 0) + 1
	end
	local max = 0
	for _, v in counts do
		if v > max then
			max = v
		end
	end
	if max >= 4 then
		return 8
	end
	if max == 3 then
		return 5
	end
	if max == 2 then
		local pairCount = 0
		for _, v in counts do
			if v >= 2 then
				pairCount += 1
			end
		end
		return if pairCount >= 2 then 4 else 3
	end
	return 2
end

local Table = {}
Table.__index = Table
PokerEngine.Table = Table

-- Aufruf:
--   PokerEngine.Table.new({ {id,name}, ... }, { flush = ..., startingStack = ..., ... })
--   PokerEngine.Table.new({id,name}, {id,name})   -- Heads-up Rueckwaerts-Kompat
function Table.new(playersOrP0, p1OrOptions, options)
	local self = setmetatable({}, Table)

	local playerDefs, opts
	if type(playersOrP0) == "table" and playersOrP0[1] ~= nil then
		playerDefs = playersOrP0
		opts = p1OrOptions or {}
	else
		playerDefs = { playersOrP0, p1OrOptions }
		opts = options or {}
	end

	self.flush = not not opts.flush
	local ss = toInt(opts.startingStack)
	self.startingStack = (ss ~= nil and ss > 0) and ss or STARTING_STACK
	-- Cash-Game: Buy-in = startingStack, busten beendet das Match NICHT.
	self.cash = not not opts.cash
	-- Turniermodus: Blinds steigen mit der Handnummer. Sonst fix 10/20.
	self.tournament = (not self.cash) and (not not opts.tournament)
	local lh = toInt(opts.levelHands)
	self.levelHands = (lh ~= nil and lh > 0) and lh or 6
	self.smallBlind = SMALL_BLIND
	self.bigBlind = BIG_BLIND
	self.blindLevel = 0

	self.players = {}
	for _, p in playerDefs do
		table.insert(self.players, {
			id = p.id,
			name = p.name,
			stack = self.startingStack,
			hole = {},
			bet = 0, -- Einsatz in der aktuellen Setzrunde
			committed = 0, -- Einsatz insgesamt in dieser Hand
			folded = false,
			allIn = false,
			inHand = false,
		})
	end
	self.n = #self.players
	self.button = self.n -- erstes startHand rotiert auf 1
	self.handNo = 0
	self.stage = "idle" -- idle | preflop | flop | turn | river | showdown | handover
	self.community = {}
	self.deck = {}
	self.pot = 0
	self.currentBet = 0
	self.minRaise = self.bigBlind
	self.toAct = nil
	self.actedSinceRaise = {} -- Set: { [seatIdx] = true }
	self.sbPos = nil
	self.bbPos = nil
	self.log = {}
	self.result = nil
	self.matchOver = false
	self.matchWinnerId = nil
	self.shownCards = {} -- Set: { [seatIdx] = true }

	-- All-In-Run-out (siehe JS-Doku). autoRunout=true => sofort/synchron.
	self.autoRunout = true
	self.runoutActive = false
	self.equities = nil

	return self
end

-- Index eines Spieler-Objekts (1-basiert) oder nil.
local function indexOfPlayer(self, p)
	for i, x in self.players do
		if x == p then
			return i
		end
	end
	return nil
end

-- Strukturiertes Log-Event.
function Table:addLog(event)
	table.insert(self.log, event)
	if #self.log > 40 then
		table.remove(self.log, 1)
	end
end

function Table:resetMatch()
	for _, p in self.players do
		p.stack = self.startingStack
		p.hole = {}
		p.bet = 0
		p.committed = 0
		p.folded = false
		p.allIn = false
		p.inHand = false
	end
	self.button = self.n
	self.handNo = 0
	self.stage = "idle"
	self.community = {}
	self.deck = {}
	self.pot = 0
	self.currentBet = 0
	self:applyBlindLevel()
	self.minRaise = self.bigBlind
	self.toAct = nil
	self.actedSinceRaise = {}
	self.sbPos = nil
	self.bbPos = nil
	self.result = nil
	self.matchOver = false
	self.matchWinnerId = nil
	self.shownCards = {}
	self.runoutActive = false
	self.equities = nil
	self.log = {}
	self:addLog({ key = "rematch" })
	return { ok = true }
end

-- Setzt smallBlind/bigBlind passend zur Handnummer.
function Table:applyBlindLevel()
	if not self.tournament then
		self.blindLevel = 0
		self.smallBlind = SMALL_BLIND
		self.bigBlind = BIG_BLIND
		return
	end
	local level = math.max(0, math.floor((self.handNo - 1) / self.levelHands))
	local prevBb = self.bigBlind
	local b = TOURNEY_BLINDS[math.min(level, #TOURNEY_BLINDS - 1) + 1]
	self.blindLevel = level
	self.smallBlind = b.sb
	self.bigBlind = b.bb
	if self.handNo > 1 and self.bigBlind > prevBb then
		self:addLog({ key = "blindsUp", sb = self.smallBlind, bb = self.bigBlind, level = level + 1 })
	end
end

-- Haende bis zur naechsten Blind-Erhoehung (nur Turnier).
function Table:handsUntilNextLevel()
	if not self.tournament then
		return nil
	end
	if self.blindLevel >= #TOURNEY_BLINDS - 1 then
		return nil
	end
	return (self.blindLevel + 1) * self.levelHands - self.handNo
end

-- ---- Index-Helfer (1-basiert, rund um den Tisch) ----
function Table:nextLive(from)
	for k = 1, self.n do
		local idx = ((from - 1 + k) % self.n) + 1
		if self.players[idx].stack > 0 then
			return idx
		end
	end
	return from
end

function Table:firstActorFrom(start)
	for k = 0, self.n - 1 do
		local idx = ((start - 1 + k) % self.n) + 1
		local p = self.players[idx]
		if not p.folded and not p.allIn and p.inHand then
			return idx
		end
	end
	return nil
end

function Table:nextToAct(from)
	for k = 1, self.n do
		local idx = ((from - 1 + k) % self.n) + 1
		local p = self.players[idx]
		if not p.folded and not p.allIn and p.inHand then
			return idx
		end
	end
	return nil
end

function Table:liveCount()
	local c = 0
	for _, p in self.players do
		if p.stack > 0 then
			c += 1
		end
	end
	return c
end

-- ---- Hand starten ----
function Table:startHand()
	if self.matchOver then
		return { error = "Match ist beendet." }
	end
	if self.stage ~= "idle" and self.stage ~= "handover" then
		return { error = "Hand laeuft noch." }
	end
	if self:liveCount() < 2 then
		return { error = "Mindestens zwei Spieler mit Chips noetig." }
	end

	self.handNo += 1
	self:applyBlindLevel()
	self.button = self:nextLive(self.button)
	self.deck = shuffle(buildDeck())
	self.community = {}
	self.pot = 0
	self.currentBet = 0
	self.minRaise = self.bigBlind
	self.result = nil
	self.actedSinceRaise = {}
	self.shownCards = {}
	self.runoutActive = false
	self.equities = nil

	for _, p in self.players do
		p.hole = {}
		p.bet = 0
		p.committed = 0
		p.allIn = false
		p.inHand = p.stack > 0
		p.folded = not p.inHand
	end

	-- Karten austeilen (nur aktive Spieler), beginnend links vom Button.
	local order = {}
	for k = 1, self.n do
		table.insert(order, ((self.button - 1 + k) % self.n) + 1)
	end
	for _round = 1, 2 do
		for _, idx in order do
			if self.players[idx].inHand then
				table.insert(self.players[idx].hole, table.remove(self.deck))
			end
		end
	end

	local liveIdx = {}
	for i, p in self.players do
		if p.stack > 0 then
			table.insert(liveIdx, i)
		end
	end

	local firstToAct
	if #liveIdx == 2 then
		-- Heads-up: Button ist Small Blind und handelt praeflop zuerst.
		self.sbPos = self.button
		self.bbPos = self:nextLive(self.button)
		firstToAct = self.sbPos
	else
		self.sbPos = self:nextLive(self.button)
		self.bbPos = self:nextLive(self.sbPos)
		firstToAct = self:nextLive(self.bbPos) -- UTG
	end

	self:postBlind(self.sbPos, self.smallBlind)
	self:postBlind(self.bbPos, self.bigBlind)
	self.currentBet = self.bigBlind
	self.minRaise = self.bigBlind

	self.stage = "preflop"
	self:addLog({ key = "handStart", hand = self.handNo, name = self.players[self.button].name })
	self:syncPot()

	self.toAct = self:firstActorFrom(firstToAct)
	if self.toAct == nil or self:isBettingClosed() then
		self:proceedAfterBetting()
	end
	return { ok = true }
end

function Table:postBlind(i, amount)
	local p = self.players[i]
	local pay = math.min(amount, p.stack)
	p.stack -= pay
	p.bet += pay
	p.committed += pay
	if p.stack == 0 then
		p.allIn = true
	end
end

function Table:syncPot()
	local s = 0
	for _, p in self.players do
		s += p.committed
	end
	self.pot = s
end

-- ---- Aktion verarbeiten ----
function Table:act(playerId, atype, amount)
	if self.stage == "idle" or self.stage == "handover" or self.stage == "showdown" then
		return { error = "Keine aktive Setzrunde." }
	end
	if self.toAct == nil then
		return { error = "Niemand am Zug." }
	end
	local i = self.toAct
	local p = self.players[i]
	if p.id ~= playerId then
		return { error = "Du bist nicht am Zug." }
	end

	local toCall = self.currentBet - p.bet

	if atype == "fold" then
		p.folded = true
		p.inHand = false
		self:addLog({ key = "fold", name = p.name })
		local remaining = 0
		for _, x in self.players do
			if not x.folded then
				remaining += 1
			end
		end
		if remaining == 1 then
			return self:endByFold()
		end
	elseif atype == "check" then
		if toCall > 0 then
			return { error = "Check nicht moeglich, es liegt ein Einsatz an." }
		end
		self.actedSinceRaise[i] = true
		self:addLog({ key = "check", name = p.name })
	elseif atype == "call" then
		if toCall <= 0 then
			self.actedSinceRaise[i] = true
			self:addLog({ key = "check", name = p.name })
		else
			local pay = math.min(toCall, p.stack)
			p.stack -= pay
			p.bet += pay
			p.committed += pay
			if p.stack == 0 then
				p.allIn = true
			end
			self.actedSinceRaise[i] = true
			self:addLog({ key = "call", name = p.name, amount = pay, allIn = p.allIn })
		end
	elseif atype == "raise" then
		if p.stack <= toCall then
			return { error = "Nicht genug Chips zum Erhoehen." }
		end
		local maxTo = p.bet + p.stack -- All-In-Ziel
		local raiseTo = toInt(amount)
		if raiseTo == nil then
			return { error = "Ungueltiger Betrag." }
		end
		local minTo = self.currentBet + self.minRaise
		if raiseTo > maxTo then
			raiseTo = maxTo
		end
		local isAllIn = raiseTo == maxTo
		if raiseTo < minTo and not isAllIn then
			return { error = `Mindestens auf {minTo} erhoehen.` }
		end
		if raiseTo <= self.currentBet then
			return { error = "Erhoehung muss ueber dem aktuellen Einsatz liegen." }
		end

		local pay = raiseTo - p.bet
		local prevBet = self.currentBet
		p.stack -= pay
		p.bet = raiseTo
		p.committed += pay
		if p.stack == 0 then
			p.allIn = true
		end
		local raiseSize = raiseTo - prevBet
		if raiseSize >= self.minRaise then
			self.minRaise = raiseSize
			self.actedSinceRaise = { [i] = true }
		else
			self.actedSinceRaise[i] = true
		end
		self.currentBet = raiseTo
		self:addLog({ key = "raise", name = p.name, to = raiseTo, allIn = p.allIn })
	else
		return { error = "Unbekannte Aktion." }
	end

	self:syncPot()

	if self:isBettingClosed() then
		self:proceedAfterBetting()
	else
		local nxt = self:nextToAct(i)
		if nxt == nil then
			self:proceedAfterBetting()
		else
			self.toAct = nxt
		end
	end
	return { ok = true }
end

function Table:endByFold()
	local winner = nil
	for i, p in self.players do
		if not p.folded then
			winner = i
			break
		end
	end
	self:distribute("fold", nil, { winner })
	return { ok = true }
end

-- Freiwilliges Aufdecken nach einem Fold-Sieg.
function Table:revealOwn(playerId)
	if self.stage ~= "handover" or not (self.result and self.result.reason == "fold") then
		return { error = "Zeigen jetzt nicht moeglich." }
	end
	local i = nil
	for idx, p in self.players do
		if p.id == playerId then
			i = idx
			break
		end
	end
	if i == nil then
		return { error = "Unbekannter Spieler." }
	end
	if self.players[i].folded then
		return { error = "Gefoldete Karten koennen nicht gezeigt werden." }
	end
	if self.shownCards[i] then
		return { ok = true }
	end
	self.shownCards[i] = true

	local ev = nil
	if #self.players[i].hole + #self.community >= 5 then
		local all = {}
		for _, c in self.players[i].hole do
			table.insert(all, c)
		end
		for _, c in self.community do
			table.insert(all, c)
		end
		ev = evaluate(all, { flush = self.flush })
	end
	if not self.result.reveal then
		self.result.reveal = {}
	end
	local found = false
	for _, r in self.result.reveal do
		if r.i == i then
			found = true
			break
		end
	end
	if not found then
		table.insert(self.result.reveal, { i = i, hole = self.players[i].hole, eval = ev, folded = false })
	end

	self:addLog({ key = "shown", name = self.players[i].name })
	return { ok = true }
end

function Table:isBettingClosed()
	local inHand = {}
	for _, p in self.players do
		if not p.folded then
			table.insert(inHand, p)
		end
	end
	if #inHand <= 1 then
		return true
	end
	for _, p in inHand do
		if not (p.allIn or p.bet == self.currentBet) then
			return false
		end
	end
	local canAct = {}
	for _, p in inHand do
		if not p.allIn then
			table.insert(canAct, p)
		end
	end
	if #canAct <= 1 then
		if #canAct == 0 then
			return true
		end
		local onlyOne = canAct[1]
		return self.actedSinceRaise[indexOfPlayer(self, onlyOne)] == true
	end
	for _, p in canAct do
		if self.actedSinceRaise[indexOfPlayer(self, p)] ~= true then
			return false
		end
	end
	return true
end

function Table:canActCount()
	local c = 0
	for _, p in self.players do
		if not p.folded and not p.allIn then
			c += 1
		end
	end
	return c
end

function Table:contenderCount()
	local c = 0
	for _, p in self.players do
		if not p.folded then
			c += 1
		end
	end
	return c
end

function Table:proceedAfterBetting()
	for _, p in self.players do
		p.bet = 0
	end
	self.currentBet = 0
	self.minRaise = self.bigBlind
	self.actedSinceRaise = {}

	local isRunout = self:contenderCount() >= 2 and self:canActCount() < 2 and #self.community < 5

	if isRunout and not self.autoRunout then
		self.runoutActive = true
		self:computeEquities()
		return
	end

	while true do
		if self:advanceStreet() then
			return self:showdown()
		end

		if self:canActCount() >= 2 then
			self.toAct = self:firstActorFrom((self.button % self.n) + 1)
			if self.toAct ~= nil then
				return
			end
		end
	end
end

-- Deckt die naechste Strasse auf. true => River lag bereits (Showdown).
function Table:advanceStreet()
	if self.stage == "preflop" then
		self:dealCommunity(3)
		self.stage = "flop"
	elseif self.stage == "flop" then
		self:dealCommunity(1)
		self.stage = "turn"
	elseif self.stage == "turn" then
		self:dealCommunity(1)
		self.stage = "river"
	elseif self.stage == "river" then
		return true
	end
	return false
end

-- Ein Takt des gestaffelten All-In-Run-outs.
function Table:stepRunout()
	if not self.runoutActive then
		return { done = true }
	end
	if self.stage == "river" then
		self.runoutActive = false
		self.equities = nil
		self:showdown()
		return { done = true }
	end
	self:advanceStreet()
	self:computeEquities()
	return { done = false }
end

function Table:dealCommunity(n)
	local street = if n == 3 then "flop" elseif self.stage == "flop" then "turn" else "river"
	for _k = 1, n do
		table.insert(self.community, table.remove(self.deck))
	end
	local cards = {}
	for j = #self.community - n + 1, #self.community do
		local c = self.community[j]
		table.insert(cards, { rank = c.rank, suit = c.suit })
	end
	self:addLog({ key = "community", street = street, cards = cards })
end

-- ---- All-In-Gewinnwahrscheinlichkeiten ----
function Table:computeEquities()
	local contenders = {}
	for i, p in self.players do
		if not p.folded then
			table.insert(contenders, { p = p, i = i })
		end
	end
	if #contenders < 2 then
		self.equities = nil
		return
	end

	local need = 5 - #self.community
	local used = {}
	local function keyOf(c)
		return c.rank * 10 + c.suit
	end
	for _, c in self.community do
		used[keyOf(c)] = true
	end
	for _, x in contenders do
		for _, c in x.p.hole do
			used[keyOf(c)] = true
		end
	end
	local deck = {}
	for _, c in buildDeck() do
		if not used[keyOf(c)] then
			table.insert(deck, c)
		end
	end

	local wins = {}
	for k = 1, #contenders do
		wins[k] = 0
	end
	local total = 0

	local function tally(board)
		local full = {}
		for _, c in self.community do
			table.insert(full, c)
		end
		for _, c in board do
			table.insert(full, c)
		end
		local best = nil
		local bestIdxs = {}
		for k = 1, #contenders do
			local hand = {}
			for _, c in contenders[k].p.hole do
				table.insert(hand, c)
			end
			for _, c in full do
				table.insert(hand, c)
			end
			local sc = evaluate(hand, { flush = self.flush }).score
			local cmp = if best == nil then 1 else compareScores(sc, best)
			if cmp > 0 then
				best = sc
				bestIdxs = { k }
			elseif cmp == 0 then
				table.insert(bestIdxs, k)
			end
		end
		local share = 1 / #bestIdxs
		for _, k in bestIdxs do
			wins[k] += share
		end
		total += 1
	end

	if need == 0 then
		tally({})
	else
		local combos = nCk(#deck, need)
		if combos <= 20000 then
			local idx = {}
			local function rec(start, depth)
				if depth == need then
					local board = {}
					for _, j in idx do
						table.insert(board, deck[j])
					end
					tally(board)
					return
				end
				for j = start, #deck do
					table.insert(idx, j)
					rec(j + 1, depth + 1)
					table.remove(idx)
				end
			end
			rec(1, 0)
		else
			local SAMPLES = 2500
			for _s = 1, SAMPLES do
				local pool = table.clone(deck)
				local board = {}
				for d = 1, need do
					local r = math.random(d, #pool)
					pool[d], pool[r] = pool[r], pool[d]
					table.insert(board, pool[d])
				end
				tally(board)
			end
		end
	end

	self.equities = {}
	for k, x in contenders do
		table.insert(self.equities, {
			i = x.i,
			pct = if total > 0 then round((wins[k] / total) * 100) else 0,
		})
	end
end

function Table:showdown()
	self.stage = "showdown"
	local contenders = {}
	for i, p in self.players do
		if not p.folded then
			table.insert(contenders, { p = p, i = i })
		end
	end

	local evals = {}
	for _, x in contenders do
		local all = {}
		for _, c in x.p.hole do
			table.insert(all, c)
		end
		for _, c in self.community do
			table.insert(all, c)
		end
		table.insert(evals, { i = x.i, eval = evaluate(all, { flush = self.flush }) })
	end

	self:distribute("showdown", evals, nil)
	return { ok = true }
end

-- ---- Side-Pot-Verteilung ----
function Table:buildSidePots()
	local remaining = {}
	for i, p in self.players do
		table.insert(remaining, { i = i, amount = p.committed, folded = p.folded })
	end
	local pots = {}
	local carry = 0
	while true do
		local hasPositive = false
		local minAmt = math.huge
		for _, c in remaining do
			if c.amount > 0 then
				hasPositive = true
				if c.amount < minAmt then
					minAmt = c.amount
				end
			end
		end
		if not hasPositive then
			break
		end
		local amount = 0
		local eligible = {}
		for _, c in remaining do
			if c.amount > 0 then
				amount += minAmt
				c.amount -= minAmt
				if not c.folded then
					table.insert(eligible, c.i)
				end
			end
		end
		if #eligible == 0 then
			carry += amount
			continue
		end
		amount += carry
		carry = 0
		table.insert(pots, { amount = amount, eligible = eligible })
	end
	return pots
end

function Table:distribute(reason, evals, foldWinners)
	local evalMap = {}
	if evals then
		for _, e in evals do
			evalMap[e.i] = e.eval
		end
	end

	local pots = self:buildSidePots()
	local winnings = {} -- [i] = amount
	local winningsOrder = {} -- Reihenfolge der Erstgutschrift
	local function addWin(i, amt)
		if winnings[i] == nil then
			winnings[i] = 0
			table.insert(winningsOrder, i)
		end
		winnings[i] += amt
	end

	for _, pot in pots do
		local winners
		if reason == "fold" then
			winners = {}
			for _, w in foldWinners do
				if table.find(pot.eligible, w) then
					table.insert(winners, w)
				end
			end
			if #winners == 0 then
				winners = table.clone(pot.eligible)
			end
		else
			local best = nil
			for _, i in pot.eligible do
				local sc = evalMap[i].score
				if best == nil or compareScores(sc, best) > 0 then
					best = sc
				end
			end
			winners = {}
			for _, i in pot.eligible do
				if compareScores(evalMap[i].score, best) == 0 then
					table.insert(winners, i)
				end
			end
		end
		pot.winners = table.clone(winners)

		-- Aufteilen, ungerade Chips an die ersten Sitze links vom Button.
		local ordered = table.clone(winners)
		table.sort(ordered, function(a, b)
			return ((a - self.button) % self.n + self.n) % self.n < ((b - self.button) % self.n + self.n) % self.n
		end)
		local share = math.floor(pot.amount / #winners)
		local remainder = pot.amount - share * #winners
		for _, w in ordered do
			local amt = share
			if remainder > 0 then
				amt += 1
				remainder -= 1
			end
			self.players[w].stack += amt
			addWin(w, amt)
		end
	end

	local totalPot = 0
	for _, p in self.players do
		totalPot += p.committed
	end

	-- Log
	if reason == "fold" then
		local w = foldWinners[1]
		self:addLog({ key = "winFold", name = self.players[w].name, pot = totalPot })
	else
		local entries = {}
		for _, i in winningsOrder do
			table.insert(entries, { i = i, amt = winnings[i] })
		end
		table.sort(entries, function(a, b)
			return a.amt > b.amt
		end)
		for _, e in entries do
			local ev = evalMap[e.i]
			self:addLog({
				key = "win",
				name = self.players[e.i].name,
				amount = e.amt,
				cat = if ev and ev.score then ev.score[1] else nil,
				flush = self.flush,
			})
		end
	end

	local winnersList = {}
	for _, i in winningsOrder do
		table.insert(winnersList, i)
	end
	local winningsArr = {}
	for _, i in winningsOrder do
		table.insert(winningsArr, { i = i, amount = winnings[i] })
	end
	local potsArr = {}
	for _, p in pots do
		table.insert(potsArr, { amount = p.amount, eligible = p.eligible, winners = p.winners or {} })
	end
	local reveal = nil
	if reason == "showdown" then
		reveal = {}
		for i, p in self.players do
			table.insert(reveal, { i = i, hole = p.hole, eval = evalMap[i] or nil, folded = p.folded })
		end
	end

	self.result = {
		reason = reason,
		winners = winnersList,
		winnings = winningsArr,
		pot = totalPot,
		pots = potsArr,
		reveal = reveal,
	}

	for _, p in self.players do
		p.bet = 0
		p.committed = 0
	end
	self.pot = 0
	self.toAct = nil
	self.stage = "handover"

	-- Match-Ende? Nur im Nicht-Cash-Game.
	if not self.cash then
		local withChips = {}
		for _, p in self.players do
			if p.stack > 0 then
				table.insert(withChips, p)
			end
		end
		if #withChips <= 1 then
			self.matchOver = true
			self.matchWinnerId = if withChips[1] then withChips[1].id else nil
			if withChips[1] then
				self:addLog({ key = "matchOver", name = withChips[1].name })
			end
		end
	end
end

-- Cash-Game-Rebuy: Chips zwischen den Haenden nachkaufen.
function Table:rebuy(playerId, amount)
	if not self.cash then
		return { error = "Rebuy nur im Cash-Game." }
	end
	if self.stage ~= "idle" and self.stage ~= "handover" then
		return { error = "Rebuy nur zwischen den Haenden." }
	end
	local p = nil
	for _, x in self.players do
		if x.id == playerId then
			p = x
			break
		end
	end
	if not p then
		return { error = "Spieler nicht gefunden." }
	end
	local amt = toInt(amount)
	if amt == nil or not (amt > 0) then
		return { error = "Ungueltiger Betrag." }
	end
	p.stack += amt
	self:addLog({ key = "rebuy", name = p.name, amount = amt })
	return { ok = true, amount = amt }
end

-- Aktueller Stack eines Spielers (fuer Cash-out beim Verlassen).
function Table:stackOf(playerId)
	for _, p in self.players do
		if p.id == playerId then
			return p.stack
		end
	end
	return 0
end

-- ---- Spieler-spezifische Sicht ----
function Table:view(playerId)
	local meIdx = nil
	for i, p in self.players do
		if p.id == playerId then
			meIdx = i
			break
		end
	end
	local showAll = self.stage == "showdown" or self.stage == "handover"

	local function mkPlayer(p, i)
		local isMe = i == meIdx
		local revealHole = isMe
			or (showAll and not p.folded and (self.result and self.result.reason == "showdown"))
			or (showAll and self.shownCards[i] == true)
		local hole
		if revealHole then
			hole = p.hole
		else
			hole = {}
			for _ = 1, #p.hole do
				table.insert(hole, false) -- verdeckt
			end
		end
		return {
			id = p.id,
			name = p.name,
			stack = p.stack,
			bet = p.bet,
			committed = p.committed,
			folded = p.folded,
			allIn = p.allIn,
			inHand = p.inHand,
			out = p.stack <= 0 and not p.inHand,
			isButton = i == self.button,
			isSB = i == self.sbPos,
			isBB = i == self.bbPos,
			isMe = isMe,
			seat = i,
			hole = hole,
		}
	end

	local me = if meIdx then self.players[meIdx] else nil
	local toCall = if self.toAct ~= nil then self.currentBet - self.players[self.toAct].bet else 0
	local yourTurn = self.toAct == meIdx and meIdx ~= nil
	local minRaiseTo = if me then math.min(self.currentBet + self.minRaise, me.bet + me.stack) else 0
	local maxRaiseTo = if me then me.bet + me.stack else 0

	local collected = 0
	for _, p in self.players do
		collected += (p.committed - p.bet)
	end

	local totalPot = 0
	for _, p in self.players do
		totalPot += p.committed
	end

	local myHand = nil
	if
		me
		and not me.folded
		and me.inHand
		and (self.stage == "preflop" or self.stage == "flop" or self.stage == "turn" or self.stage == "river")
	then
		myHand = { cat = liveCategory(me.hole, self.community, self.flush) }
	end

	local players = {}
	for i, p in self.players do
		table.insert(players, mkPlayer(p, i))
	end

	local actions = nil
	if yourTurn and me then
		actions = {
			canCheck = toCall <= 0,
			canCall = toCall > 0,
			toCall = math.min(toCall, me.stack),
			canRaise = me.stack > math.max(0, toCall),
			minRaiseTo = minRaiseTo,
			maxRaiseTo = maxRaiseTo,
		}
	end

	local shown = {}
	for i in self.shownCards do
		table.insert(shown, i)
	end

	return {
		handNo = self.handNo,
		stage = self.stage,
		flush = self.flush,
		cash = self.cash,
		buyIn = if self.cash then self.startingStack else nil,
		myStack = if me then me.stack else 0,
		betweenHands = self.stage == "idle" or self.stage == "handover",
		community = self.community,
		pot = collected,
		totalPot = totalPot,
		currentBet = self.currentBet,
		players = players,
		meIdx = meIdx,
		button = self.button,
		toActId = if self.toAct ~= nil then self.players[self.toAct].id else nil,
		yourTurn = yourTurn,
		actions = actions,
		result = self.result,
		shown = shown,
		runout = self.runoutActive,
		equities = if self.runoutActive then self.equities else nil,
		myHand = myHand,
		log = self.log,
		matchOver = self.matchOver,
		matchWinnerId = self.matchWinnerId,
		blinds = {
			sb = self.smallBlind,
			bb = self.bigBlind,
			tournament = self.tournament,
			level = if self.tournament then self.blindLevel + 1 else nil,
			nextLevelIn = self:handsUntilNextLevel(),
		},
	}
end

return PokerEngine
