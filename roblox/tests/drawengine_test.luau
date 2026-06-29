--!nonstrict
-- Standalone-Tests für die All-Ages Tier-Karten-Duell-Engine (DrawEngine).
-- Lauf:  luau roblox/tests/drawengine_test.luau   (vom Repo-Root)

local HandEval = require("../src/shared/HandEval")
local DrawEngine = require("../src/shared/DrawEngine")

math.randomseed(1)

local passed, failed = 0, 0
local function ok(cond, name)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name)
	end
end

local function key(c)
	return tostring(c.rank) .. "-" .. tostring(c.copy)
end

-- ---- new() ----
do
	local e = DrawEngine.new({ "a", "b" }, { targetWins = 3 })
	ok(e.stage == "idle", "neu: stage idle")
	ok(#e.players == 2, "neu: 2 Spieler")
	ok(e.players[1].wins == 0 and e.players[2].wins == 0, "neu: 0 Siege")
	ok(e.targetWins == 3, "neu: targetWins übernommen")
end

-- ---- startRound: austeilen ----
do
	local e = DrawEngine.new({ "a", "b", "c" }, { handSize = 5 })
	e:startRound()
	ok(e.stage == "draw", "startRound: stage draw")
	ok(#e.players[1].hand == 5, "startRound: 5 Karten ausgeteilt")
	ok(e.drawPileCount == nil, "startRound: drawPileCount nur in view")
	local v = e:view("a")
	ok(v.drawPileCount == 40 - 3 * 5, "startRound: Reststapel = 40 - 3*5")
	-- eigene Hand sichtbar, fremde nicht (in Draw-Phase)
	ok(v.players[1].hand ~= nil, "view: eigene Hand sichtbar")
	ok(v.players[2].hand == nil and v.players[2].handCount == 5, "view: fremde Hand verdeckt (nur Anzahl)")
end

-- ---- discard: Karten tauschen ----
do
	local e = DrawEngine.new({ "a", "b" }, { handSize = 5 })
	e:startRound()
	local before = {}
	for i, c in e.players[1].hand do
		before[i] = key(c)
	end
	local r = e:discard("a", { 1, 2 })
	ok(r.ok and r.swapped == 2, "discard: 2 Karten getauscht")
	ok(#e.players[1].hand == 5, "discard: Hand bleibt 5 Karten")
	ok(e.players[1].hasDrawn, "discard: hasDrawn gesetzt")
	-- nochmaliger Tausch verboten
	ok(e:discard("a", { 3 }).ok == false, "discard: zweiter Tausch verboten")
	-- ungültige Indizes ignoriert (kein Crash)
	ok(e:discard("b", { 0, 99, 2, 2 }).swapped == 1, "discard: ungültige/doppelte Indizes bereinigt")
end

-- ---- Showdown: beste Hand gewinnt ----
do
	local e = DrawEngine.new({ "a", "b" }, { handSize = 5, targetWins = 99 })
	e:startRound()
	e:discard("a", {})
	e:discard("b", {})
	ok(e.stage == "showdown", "showdown: stage nach allen Tauschen")
	-- Gewinner muss die (gemeinsam) beste Hand haben.
	local best = nil
	for _, p in e.players do
		if best == nil or HandEval.compareScores(p.eval.score, best) > 0 then
			best = p.eval.score
		end
	end
	local winners = e.lastResult.winners
	ok(#winners >= 1, "showdown: mindestens ein Gewinner")
	for _, p in e.players do
		local isWinner = false
		for _, wid in winners do
			if wid == p.id then
				isWinner = true
			end
		end
		if isWinner then
			ok(HandEval.compareScores(p.eval.score, best) == 0, "showdown: Gewinner hat beste Hand")
		else
			ok(HandEval.compareScores(p.eval.score, best) < 0, "showdown: Verlierer strikt schlechter")
		end
	end
	-- Summe der Siege = Anzahl Gewinner
	local totalWins = 0
	for _, p in e.players do
		totalWins += p.wins
	end
	ok(totalWins == #winners, "showdown: genau die Gewinner bekommen +1")
	-- im Showdown sind alle Hände sichtbar
	local v = e:view("a")
	ok(v.players[2].hand ~= nil and v.players[2].category ~= nil, "view: Showdown deckt fremde Hand auf")
end

-- ---- Matchende bei targetWins ----
do
	local e = DrawEngine.new({ "a", "b" }, { handSize = 5, targetWins = 1 })
	e:startRound()
	e:discard("a", {})
	e:discard("b", {})
	-- targetWins=1 -> nach einer Runde muss (sofern kein Gleichstand) Matchende sein
	ok(e.stage == "matchover" or e.stage == "showdown", "match: stage matchover/showdown")
	if e.stage == "matchover" then
		ok(e.matchWinners ~= nil and #e.matchWinners >= 1, "match: matchWinners gesetzt")
	end
end

-- ---- Deck-Robustheit: 6 Spieler tauschen alle 5 Karten (Nachzieh-Reshuffle) ----
do
	local e = DrawEngine.new({ "a", "b", "c", "d", "e", "f" }, { handSize = 5 })
	e:startRound()
	for _, pid in { "a", "b", "c", "d", "e", "f" } do
		e:discard(pid, { 1, 2, 3, 4, 5 })
	end
	ok(e.stage == "showdown", "robust: 6 Spieler, alle tauschen -> Showdown ohne Crash")
	for _, p in e.players do
		ok(#p.hand == 5, "robust: Hand von " .. tostring(p.id) .. " bleibt voll")
	end
end

-- ---- resetMatch ----
do
	local e = DrawEngine.new({ "a", "b" }, { targetWins = 1, handSize = 5 })
	e:startRound()
	e:discard("a", {})
	e:discard("b", {})
	e:resetMatch()
	ok(e.stage == "idle" and e.round == 0, "reset: stage idle, Runde 0")
	ok(e.players[1].wins == 0 and e.players[2].wins == 0, "reset: Siege auf 0")
end

print(string.format("\n%d bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
	error("DrawEngine-Tests fehlgeschlagen")
end
