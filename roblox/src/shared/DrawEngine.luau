--!nonstrict
-- Tier-Karten-Duell – die ALL-AGES-Engine (kein Wetten, kein Glücksspiel).
--
-- Spielprinzip (Draw/Tausch, wie Video-Poker ohne Geld):
--   1. Jeder bekommt `handSize` Karten aus dem 40er-Tier-Deck.
--   2. Draw-Phase: jeder wählt selbst, welche Karten er behält und welche er
--      gegen neue tauscht (genau EINMAL pro Runde). -> reine Skill-Entscheidung.
--   3. Showdown: beste Hand gewinnt die Runde (+1 Rundensieg).
--   4. Wer zuerst `targetWins` Runden gewinnt, gewinnt das Match.
--
-- Es gibt KEINE Einsätze, KEINEN Pot, KEINE Chips-als-Währung – nur Rundensiege.
-- Damit ist der Modus für alle Altersgruppen geeignet (kein simuliertes Glücksspiel).
-- Monetarisierung erfolgt ausschließlich über Kosmetik (separates Modul/Shop).
--
-- Reine Logik, keine Roblox-API: läuft in Roblox (Rojo -> Shared.DrawEngine) und
-- standalone via luau-CLI für Tests. Sitze/Indizes sind 1-basiert (Lua-Arrays).

local Cards = require(script and script.Parent.Cards or "./Cards")
local HandEval = require(script and script.Parent.HandEval or "./HandEval")

local buildDeck = Cards.buildDeck
local shuffle = Cards.shuffle
local evaluate = HandEval.evaluate
local compareScores = HandEval.compareScores

local DrawEngine = {}
DrawEngine.__index = DrawEngine

export type Options = {
	targetWins: number?, -- Rundensiege zum Matchsieg (Default 3)
	handSize: number?, -- Karten pro Hand (Default 5)
	flush: boolean?, -- Flush-Wertung an? (Default false)
}

-- playerIds: Liste stabiler Spieler-Identifikatoren (string|number).
function DrawEngine.new(playerIds: { any }, options: Options?)
	local opts = options or {}
	local self = setmetatable({}, DrawEngine)
	self.targetWins = math.max(1, opts.targetWins or 3)
	self.handSize = math.max(1, math.min(7, opts.handSize or 5))
	self.flush = not not opts.flush
	self.stage = "idle" -- "idle" | "draw" | "showdown" | "matchover"
	self.round = 0
	self.drawPile = {}
	self.discardPile = {}
	self.lastResult = nil
	self.matchWinners = nil
	self.players = {}
	for _, id in playerIds do
		table.insert(self.players, {
			id = id,
			hand = {},
			wins = 0,
			hasDrawn = false,
			eval = nil,
		})
	end
	return self
end

function DrawEngine:_playerById(id)
	for _, p in self.players do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Zieht eine Karte vom Nachziehstapel. Ist er leer, werden die abgelegten Karten
-- neu gemischt und als Stapel verwendet (robust auch bei 6 Spielern / 40 Karten).
function DrawEngine:_drawCard()
	if #self.drawPile == 0 then
		if #self.discardPile == 0 then
			return nil -- sollte praktisch nie passieren
		end
		self.drawPile = shuffle(self.discardPile)
		self.discardPile = {}
	end
	return table.remove(self.drawPile)
end

-- Startet eine neue Runde: frisches Deck, jedem `handSize` Karten austeilen.
function DrawEngine:startRound()
	if self.stage == "matchover" then
		return { ok = false, error = "Match bereits vorbei." }
	end
	self.round += 1
	self.drawPile = shuffle(buildDeck())
	self.discardPile = {}
	self.lastResult = nil
	for _, p in self.players do
		p.hand = {}
		p.hasDrawn = false
		p.eval = nil
		for _ = 1, self.handSize do
			local c = self:_drawCard()
			if c then
				table.insert(p.hand, c)
			end
		end
	end
	self.stage = "draw"
	return { ok = true }
end

-- Ein Spieler tauscht Karten: `indices` = 1-basierte Positionen in seiner Hand,
-- die gegen neue Karten ersetzt werden. Leere Liste = alles behalten ("stehen").
-- Jeder Spieler darf pro Runde genau einmal tauschen.
function DrawEngine:discard(playerId, indices)
	if self.stage ~= "draw" then
		return { ok = false, error = "Gerade keine Tausch-Phase." }
	end
	local p = self:_playerById(playerId)
	if not p then
		return { ok = false, error = "Unbekannter Spieler." }
	end
	if p.hasDrawn then
		return { ok = false, error = "Schon getauscht." }
	end
	indices = indices or {}

	-- Eindeutige, gültige Indizes einsammeln.
	local seen = {}
	local toReplace = {}
	for _, idx in indices do
		idx = tonumber(idx)
		if idx and idx >= 1 and idx <= #p.hand and not seen[idx] then
			seen[idx] = true
			table.insert(toReplace, idx)
		end
	end

	-- Ausgewählte Karten ablegen und durch frische ersetzen (Position bleibt gleich).
	for _, idx in toReplace do
		table.insert(self.discardPile, p.hand[idx])
		local c = self:_drawCard()
		if c then
			p.hand[idx] = c
		end
	end
	p.hasDrawn = true

	-- Haben alle getauscht -> Showdown.
	local allDone = true
	for _, q in self.players do
		if not q.hasDrawn then
			allDone = false
			break
		end
	end
	if allDone then
		self:_resolveShowdown()
	end
	return { ok = true, swapped = #toReplace }
end

function DrawEngine:_resolveShowdown()
	self.stage = "showdown"
	local best = nil
	for _, p in self.players do
		p.eval = evaluate(p.hand, { flush = self.flush })
		if best == nil or compareScores(p.eval.score, best) > 0 then
			best = p.eval.score
		end
	end
	-- Gewinner = alle Spieler mit der besten Hand (Gleichstand -> mehrere).
	local winners = {}
	for _, p in self.players do
		if best ~= nil and compareScores(p.eval.score, best) == 0 then
			p.wins += 1
			table.insert(winners, p.id)
		end
	end
	self.lastResult = {
		winners = winners,
		hands = {},
	}
	for _, p in self.players do
		table.insert(self.lastResult.hands, {
			id = p.id,
			hand = p.hand,
			category = p.eval.name,
			wins = p.wins,
		})
	end
	-- Matchende? (jemand hat targetWins erreicht)
	local maxWins = 0
	for _, p in self.players do
		if p.wins > maxWins then
			maxWins = p.wins
		end
	end
	if maxWins >= self.targetWins then
		self.stage = "matchover"
		local champs = {}
		for _, p in self.players do
			if p.wins == maxWins then
				table.insert(champs, p.id)
			end
		end
		self.matchWinners = champs
	end
end

-- Sicht für einen Spieler (eigene Hand sichtbar; fremde Hände erst im Showdown).
-- viewerId == nil -> Zuschauer (alle Hände erst im Showdown sichtbar).
function DrawEngine:view(viewerId)
	local reveal = self.stage == "showdown" or self.stage == "matchover"
	local players = {}
	for _, p in self.players do
		local isMe = viewerId ~= nil and p.id == viewerId
		table.insert(players, {
			id = p.id,
			wins = p.wins,
			hasDrawn = p.hasDrawn,
			handCount = #p.hand,
			hand = (isMe or reveal) and p.hand or nil,
			category = reveal and p.eval and p.eval.name or nil,
		})
	end
	return {
		stage = self.stage,
		round = self.round,
		targetWins = self.targetWins,
		handSize = self.handSize,
		flush = self.flush,
		yourId = viewerId,
		players = players,
		result = self.lastResult,
		matchWinners = self.matchWinners,
		drawPileCount = #self.drawPile,
	}
end

-- Match komplett zurücksetzen (Rematch): Siege auf 0, neue Runde startbereit.
function DrawEngine:resetMatch()
	for _, p in self.players do
		p.wins = 0
		p.hand = {}
		p.hasDrawn = false
		p.eval = nil
	end
	self.stage = "idle"
	self.round = 0
	self.lastResult = nil
	self.matchWinners = nil
end

return DrawEngine
