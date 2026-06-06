--!nonstrict
-- Standalone-Tests fuer die Luau-Portierung der KuhPoker-Engine.
-- Lauf:  /tmp/luau roblox/tests/run.luau      (vom Repo-Root)
-- Verifiziert Parität mit der JS-Engine (src/cards.js, src/handEval.js, src/poker.js).

local Cards = require("../src/shared/Cards")
local HandEval = require("../src/shared/HandEval")
local PokerEngine = require("../src/shared/PokerEngine")

local passed = 0
local failed = 0
local failures = {}

local function ok(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		table.insert(failures, msg)
		print("  ✗ " .. msg)
	end
end

local function eqArr(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function arrStr(a)
	local parts = {}
	for _, v in a do
		table.insert(parts, tostring(v))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Karten {rank, suit}
local function C(rank, suit)
	return { rank = rank, suit = suit or 0 }
end

local function scoreOf(cards, flush)
	return HandEval.evaluate(cards, { flush = flush }).score
end

local function expectScore(cards, flush, expected, label)
	local s = scoreOf(cards, flush)
	ok(eqArr(s, expected), `{label}: erwartet {arrStr(expected)}, bekam {arrStr(s)}`)
end

print("== Cards ==")
do
	local deck = Cards.buildDeck()
	ok(#deck == 40, "Deck hat 40 Karten (" .. #deck .. ")")
	local perRank = {}
	local suitEqCopy = true
	for _, c in deck do
		perRank[c.rank] = (perRank[c.rank] or 0) + 1
		if c.suit ~= c.copy then
			suitEqCopy = false
		end
	end
	local all4 = true
	for r = 1, 10 do
		if perRank[r] ~= 4 then
			all4 = false
		end
	end
	ok(all4, "jeder Rang 1..10 genau 4x im Deck")
	ok(suitEqCopy, "suit === copy fuer jede Karte")
	ok(#Cards.ANIMALS == 10 and Cards.ANIMALS[10].value == 1000, "Pferd hat Wert 1000")
end

print("== HandEval (Flush AUS) ==")
do
	expectScore({ C(5), C(5), C(5), C(5), C(9) }, false, { 8, 5, 9 }, "Vierling")
	expectScore({ C(7), C(7), C(7), C(3), C(3) }, false, { 7, 7, 3 }, "Full House")
	expectScore({ C(6), C(5), C(4), C(3), C(2) }, false, { 6, 6 }, "Strasse")
	expectScore({ C(10), C(1), C(2), C(3), C(4) }, false, { 6, 4 }, "Wheel (Pferd-1-2-3-4, High 4)")
	expectScore({ C(9), C(9), C(9), C(2), C(5) }, false, { 5, 9, 5, 2 }, "Drilling")
	expectScore({ C(8), C(8), C(3), C(3), C(10) }, false, { 4, 8, 3, 10 }, "Zwei Paare")
	expectScore({ C(4), C(4), C(9), C(7), C(2) }, false, { 3, 4, 9, 7, 2 }, "Paar")
	expectScore({ C(10), C(8), C(6), C(4), C(2) }, false, { 2, 10, 8, 6, 4, 2 }, "Hohe Karte")
	-- Wheel ist schwaecher als 2-3-4-5-6
	ok(
		HandEval.compareScores(scoreOf({ C(6), C(5), C(4), C(3), C(2) }, false), scoreOf({ C(10), C(1), C(2), C(3), C(4) }, false)) > 0,
		"6-hohe Strasse schlaegt Wheel"
	)
end

print("== HandEval (Flush AN) ==")
do
	-- Strasse Flush 6-hoch (alle suit 1)
	expectScore({ C(6, 1), C(5, 1), C(4, 1), C(3, 1), C(2, 1) }, true, { 10, 6 }, "Strasse Flush")
	-- Reiner Flush (nicht zusammenhaengend), alle suit 1
	expectScore({ C(2, 1), C(4, 1), C(6, 1), C(8, 1), C(10, 1) }, true, { 8, 10, 8, 6, 4, 2 }, "Flush")
	-- Vierling im Flush-Modus = Kategorie 9
	expectScore({ C(5, 0), C(5, 1), C(5, 2), C(5, 3), C(9, 0) }, true, { 9, 5, 9 }, "Vierling (Flush-Modus)")
	-- Flush schlaegt Full House (Short-Deck-Regel)
	local flush = scoreOf({ C(2, 1), C(4, 1), C(6, 1), C(8, 1), C(10, 1) }, true)
	local fh = scoreOf({ C(7, 0), C(7, 1), C(7, 2), C(3, 0), C(3, 1) }, true)
	ok(HandEval.compareScores(flush, fh) > 0, "Flush schlaegt Full House")
end

print("== HandEval.evaluate (beste aus 7) ==")
do
	-- 7 Karten: zwei Hole + 5 Board, bestes ist Vierling 8er
	local seven = { C(8), C(8), C(8), C(8), C(2), C(5), C(10) }
	local r = HandEval.evaluate(seven, { flush = false })
	ok(eqArr(r.score, { 8, 8, 10 }), "beste 5 aus 7: Vierling 8 + Kicker 10 (" .. arrStr(r.score) .. ")")
	ok(r.name == "Vierling", "Kategoriename = Vierling")
end

print("== Engine: Setup & Sicht ==")
do
	local t = PokerEngine.Table.new({ { id = "A", name = "Anna" }, { id = "B", name = "Bert" } }, { startingStack = 1000 })
	ok(t.n == 2, "2 Spieler")
	ok(t.players[1].stack == 1000 and t.players[2].stack == 1000, "Startstacks 1000")
	local v = t:view("A")
	ok(v.stage == "idle", "Start-Stage idle")
	ok(#v.players == 2, "view liefert 2 Spieler")
	ok(v.meIdx == 1, "meIdx zeigt auf eigenen Sitz")
end

print("== Engine: ganze Hand bis Showdown, Chip-Erhaltung ==")
do
	math.randomseed(12345)
	local function playOut(opts)
		local t = PokerEngine.Table.new(
			{ { id = "A", name = "Anna" }, { id = "B", name = "Bert" }, { id = "C", name = "Cara" } },
			opts
		)
		local before = 0
		for _, p in t.players do
			before += p.stack
		end
		local res = t:startHand()
		ok(res.ok == true, "startHand ok")
		local guard = 0
		while t.toAct ~= nil do
			guard += 1
			if guard > 500 then
				ok(false, "Endlosschleife in playOut")
				break
			end
			local p = t.players[t.toAct]
			local toCall = t.currentBet - p.bet
			if toCall > 0 then
				t:act(p.id, "call")
			else
				t:act(p.id, "check")
			end
		end
		local after = 0
		for _, p in t.players do
			after += p.stack
		end
		ok(after == before, `Chip-Erhaltung ({before} -> {after})`)
		ok(t.stage == "handover", "Stage handover nach Showdown/Fold")
		ok(t.result ~= nil, "result gesetzt")
		return t
	end
	playOut({ startingStack = 1000 })
	playOut({ startingStack = 1000, flush = true })
end

print("== Engine: viele Haende, Match endet irgendwann ==")
do
	math.randomseed(999)
	local t = PokerEngine.Table.new({ { id = "A", name = "Anna" }, { id = "B", name = "Bert" } }, { startingStack = 200 })
	local hands = 0
	while not t.matchOver and hands < 1000 do
		local r = t:startHand()
		if r.error then
			break
		end
		hands += 1
		local guard = 0
		while t.toAct ~= nil do
			guard += 1
			if guard > 500 then
				break
			end
			local p = t.players[t.toAct]
			local toCall = t.currentBet - p.bet
			-- Aggressiv: immer all-in callen, damit das Match terminiert
			if toCall > 0 then
				t:act(p.id, "call")
			else
				t:act(p.id, "check")
			end
		end
	end
	ok(t.matchOver == true, `Match endet (nach {hands} Haenden)`)
	ok(t.matchWinnerId == "A" or t.matchWinnerId == "B", "matchWinnerId gesetzt")
	local total = 0
	for _, p in t.players do
		total += p.stack
	end
	ok(total == 400, `Gesamt-Chips bleiben 400 ({total})`)
end

print("== Engine: Side Pots ==")
do
	local t = PokerEngine.Table.new(
		{ { id = "A", name = "A" }, { id = "B", name = "B" }, { id = "C", name = "C" } },
		{ startingStack = 1000 }
	)
	t.players[1].committed = 100
	t.players[2].committed = 50
	t.players[3].committed = 25
	local pots = t:buildSidePots()
	ok(#pots == 3, "3 Pots aus 100/50/25 (" .. #pots .. ")")
	ok(pots[1].amount == 75 and #pots[1].eligible == 3, "Hauptpot 75, 3 berechtigt")
	ok(pots[2].amount == 50 and #pots[2].eligible == 2, "Side-Pot 50, 2 berechtigt")
	ok(pots[3].amount == 50 and #pots[3].eligible == 1, "Side-Pot 50, 1 berechtigt")
	local sum = pots[1].amount + pots[2].amount + pots[3].amount
	ok(sum == 175, "Pot-Summe = 175")
end

print("== Engine: Cash-Game ==")
do
	local t = PokerEngine.Table.new({ { id = "A", name = "A" }, { id = "B", name = "B" } }, { cash = true, startingStack = 200 })
	ok(t.cash == true, "cash-Flag true")
	ok(t.tournament == false, "cash deaktiviert Turnier")
	local v = t:view("A")
	ok(v.cash == true and v.buyIn == 200, "view: cash + buyIn 200")
	ok(t:stackOf("A") == 200, "stackOf(A) = 200")
	-- Rebuy zwischen den Haenden
	local r = t:rebuy("A", 500)
	ok(r.ok == true and r.amount == 500, "rebuy +500 ok")
	ok(t:stackOf("A") == 700, "Stack nach Rebuy 700")
	local lastLog = t.log[#t.log]
	ok(lastLog and lastLog.key == "rebuy" and lastLog.amount == 500, "rebuy-Log geschrieben")
	-- Rebuy waehrend laufender Hand abgelehnt
	t:startHand()
	local r2 = t:rebuy("A", 100)
	ok(r2.error ~= nil, "rebuy waehrend Hand abgelehnt")
	-- Rebuy im Nicht-Cash-Game abgelehnt
	local t2 = PokerEngine.Table.new({ { id = "A", name = "A" }, { id = "B", name = "B" } }, {})
	ok(t2:rebuy("A", 100).error ~= nil, "rebuy ohne Cash abgelehnt")
end

print("== Engine: matchOver-Unterdrueckung im Cash ==")
do
	-- Deterministisch: ein Spieler hat Chips, einer ist bei 0. distribute() prueft matchOver.
	local function mk(cash)
		local t = PokerEngine.Table.new({ { id = "A", name = "A" }, { id = "B", name = "B" } }, { cash = cash, startingStack = 200 })
		t.players[1].stack = 400
		t.players[2].stack = 0
		t:distribute("fold", nil, { 1 })
		return t
	end
	ok(mk(false).matchOver == true, "Nicht-Cash: matchOver bei nur einem Spieler mit Chips")
	ok(mk(true).matchOver == false, "Cash: kein matchOver trotz Bust")
end

print("== Engine: Turnier-Blinds ==")
do
	local t = PokerEngine.Table.new({ { id = "A", name = "A" }, { id = "B", name = "B" } }, { tournament = true, levelHands = 6 })
	t.handNo = 1
	t:applyBlindLevel()
	ok(t.smallBlind == 10 and t.bigBlind == 20, "Hand 1: 10/20")
	t.handNo = 7
	t:applyBlindLevel()
	ok(t.smallBlind == 15 and t.bigBlind == 30, "Hand 7: 15/30 (Level 2)")
	t.handNo = 13
	t:applyBlindLevel()
	ok(t.smallBlind == 25 and t.bigBlind == 50, "Hand 13: 25/50 (Level 3)")
	-- letztes Level haelt unbegrenzt
	t.handNo = 1000
	t:applyBlindLevel()
	ok(t.bigBlind == 2000, "spaetes Level: 1000/2000 (Maximum)")
end

print(string.format("\n%d bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
	for _, m in failures do
		print("FAIL: " .. m)
	end
	os.exit(1)
end
