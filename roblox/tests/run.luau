--!nonstrict
-- Standalone-Tests fuer die Luau-Portierung der KuhPoker-Engine.
-- Lauf:  /tmp/luau roblox/tests/run.luau      (vom Repo-Root)
-- Verifiziert Parität mit der JS-Engine (src/cards.js, src/handEval.js, src/poker.js).

local Cards = require("../src/shared/Cards")
local HandEval = require("../src/shared/HandEval")
local PokerEngine = require("../src/shared/PokerEngine")
local Strings = require("../src/shared/Strings")
local RoomManager = require("../src/shared/RoomManager")
local Profile = require("../src/shared/Profile")
local Bot = require("../src/shared/Bot")
local Progression = require("../src/shared/Progression")
local Monetization = require("../src/shared/Monetization")
local Quests = require("../src/shared/Quests")
local Season = require("../src/shared/Season")
local Friends = require("../src/shared/Friends")

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

print("== Strings: Log-Uebersetzung DE/EN ==")
do
	ok(
		Strings.translateLog("de", { key = "handStart", hand = 3, name = "Anna" })
			== "— Hand 3 — Anna hat den Button.",
		"DE handStart"
	)
	ok(
		Strings.translateLog("en", { key = "handStart", hand = 3, name = "Anna" })
			== "— Hand 3 — Anna is on the button.",
		"EN handStart"
	)
	ok(Strings.translateLog("de", { key = "fold", name = "Bert" }) == "Bert steigt aus (Fold).", "DE fold")
	ok(
		Strings.translateLog("de", { key = "call", name = "Bert", amount = 40, allIn = true })
			== "Bert geht mit (40). All-In!",
		"DE call all-in"
	)
	ok(
		Strings.translateLog("en", { key = "raise", name = "Cara", to = 120, allIn = false })
			== "Cara raises to 120.",
		"EN raise"
	)
	-- community: Tiernamen, sprachabhaengig
	ok(
		Strings.translateLog("de", { key = "community", street = "flop", cards = { { rank = 1 }, { rank = 9 }, { rank = 10 } } })
			== "Flop: Hahn, Kuh, Pferd",
		"DE community Flop"
	)
	ok(
		Strings.translateLog("en", { key = "community", street = "turn", cards = { { rank = 5 } } })
			== "Turn: Sheep",
		"EN community Turn"
	)
	-- win mit Kategorie (Flush aus): cat 8 = Vierling / Four of a Kind
	ok(
		Strings.translateLog("de", { key = "win", name = "Anna", amount = 200, cat = 8, flush = false })
			== "Anna gewinnt 200 mit Vierling.",
		"DE win Vierling"
	)
	ok(
		Strings.translateLog("en", { key = "win", name = "Anna", amount = 200, cat = 8, flush = false })
			== "Anna wins 200 with Four of a Kind.",
		"EN win Quads"
	)
	-- Flush-Modus: cat 8 = Flush (nicht Vierling)
	ok(Strings.catName("de", 8, true) == "Flush", "catName Flush-Modus code 8 = Flush")
	ok(Strings.catName("de", 8, false) == "Vierling", "catName ohne Flush code 8 = Vierling")
	ok(Strings.translateLog("de", { key = "win", name = "X", amount = 10 }) == "X gewinnt 10.", "win ohne cat")
	ok(Strings.translateLog("de", { key = "rematch" }) == "Revanche! Neue Stacks, neues Glück.", "DE rematch")
	ok(
		Strings.translateLog("en", { key = "rebuy", name = "Bert", amount = 500 }) == "Bert rebuys: +500 🪙.",
		"EN rebuy"
	)
	ok(Strings.translateLog("de", { key = "unbekannt" }) == "unbekannt", "Fallback auf key")
end

print("== RoomManager ==")
do
	local rm = RoomManager.new()
	local code, room = rm:createRoom({ id = "h1", name = "Host" }, { maxPlayers = 3, startingStack = 2000, flush = true })
	ok(type(code) == "string" and #code == 4, "createRoom liefert 4-stelligen Code")
	ok(room.hostId == "h1" and #room.players == 1, "Host sitzt allein im Raum")
	ok(room.settings.startingStack == 2000 and room.settings.flush == true, "Settings uebernommen")
	ok(room.settings.maxPlayers == 3, "maxPlayers geklemmt/uebernommen")

	-- Beitritt
	ok(rm:joinRoom(code, { id = "p2", name = "Bert" }).ok == true, "Spieler 2 tritt bei")
	ok(rm:joinRoom(code, { id = "p3", name = "Cara" }).ok == true, "Spieler 3 tritt bei")
	-- Voll
	ok(rm:joinRoom(code, { id = "p4", name = "Dora" }).error ~= nil, "voller Tisch lehnt ab (max 3)")
	-- Idempotenter Re-Join
	local rj = rm:joinRoom(code, { id = "p2", name = "Bert" })
	ok(rj.ok == true and rj.rejoined == true, "erneuter Beitritt = idempotent (rejoined)")
	ok(#room.players == 3, "weiterhin 3 Spieler")

	-- Falscher Code
	ok(rm:joinRoom("ZZZZ", { id = "x", name = "X" }).error ~= nil, "unbekannter Code lehnt ab")

	-- Start mit zu wenigen Spielern
	local rmSolo = RoomManager.new()
	local sc = rmSolo:createRoom({ id = "s", name = "Solo" })
	ok(rmSolo:startMatch(sc).error ~= nil, "Start mit 1 Spieler abgelehnt")

	-- Match starten baut Engine-Tisch
	local started = rm:startMatch(code)
	ok(started.ok == true and started.table ~= nil, "startMatch baut Engine-Tisch")
	ok(started.table.flush == true and started.table.startingStack == 2000, "Tisch erbt Settings")
	ok(room.started == true, "room.started = true")
	-- Beitritt nach Start abgelehnt
	ok(rm:joinRoom(code, { id = "late", name = "Spaet" }).error ~= nil, "Beitritt nach Start abgelehnt")

	-- Host verlaesst -> Host-Reassignment
	local lv = rm:leaveRoom(code, "h1")
	ok(lv.ok == true and lv.destroyed == false, "Host verlaesst, Raum bleibt")
	ok(room.hostId == "p2", "Host neu vergeben an naechsten Spieler")

	-- Alle verlassen -> Raum zerstoert
	rm:leaveRoom(code, "p2")
	local last = rm:leaveRoom(code, "p3")
	ok(last.destroyed == true, "letzter Spieler verlaesst -> Raum zerstoert")
	ok(rm:getRoom(code) == nil, "Raum entfernt")
	ok(rm:roomCount() == 0, "keine Raeume mehr")
end

print("== RoomManager: Code-Kollision wird aufgeloest ==")
do
	-- Deterministische RNG: erzeugt zunaechst denselben Code wie der erste Raum,
	-- danach einen anderen. Erwartung: der zweite Raum bekommt einen frischen Code.
	-- Raum1: AAAA. Raum2 Versuch1: AAAA (Kollision!) -> Versuch2: AAAB.
	local seq = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2 }
	local i = 0
	local rng = function(_lo, _hi)
		i += 1
		return seq[i] or 1
	end
	local rm = RoomManager.new({ rng = rng })
	local c1 = rm:createRoom({ id = "a", name = "A" })
	local c2 = rm:createRoom({ id = "b", name = "B" })
	ok(c1 ~= c2, `Kollision aufgeloest: {c1} ~= {c2}`)
	ok(rm:roomCount() == 2, "beide Raeume existieren")
end

print("== RoomManager: Quick-Play (oeffentliche Tische) ==")
do
	local rm = RoomManager.new()
	-- Privater Tisch (Standard) wird vom Matchmaking ignoriert.
	rm:createRoom({ id = "priv", name = "P" })
	ok(rm:findJoinablePublic() == nil, "privater Tisch ist nicht oeffentlich beitretbar")

	-- Oeffentlicher Tisch wird gefunden.
	local pub = rm:createRoom({ id = "host", name = "H" }, { public = true, maxPlayers = 2 })
	ok(rm:getRoom(pub).public == true, "public-Flag gesetzt")
	ok(rm:findJoinablePublic() == pub, "oeffentlicher Wartetisch wird gefunden")

	-- Voll -> nicht mehr beitretbar.
	rm:joinRoom(pub, { id = "p2", name = "Q" })
	ok(rm:findJoinablePublic() == nil, "voller Tisch wird nicht mehr gefunden")

	-- Match gestartet -> nicht beitretbar; reopen() macht ihn wieder verfuegbar.
	rm:startMatch(pub)
	ok(rm:getRoom(pub).started == true, "Match gestartet")
	ok(rm:findJoinablePublic() == nil, "laufender Tisch wird nicht gefunden")
	rm:reopen(pub)
	ok(rm:getRoom(pub).started == false and rm:getRoom(pub).table == nil, "reopen: zurueck in Wartephase")
	-- Noch voll (2/2 Sitze) -> erst nach Freiwerden eines Sitzes wieder beitretbar.
	ok(rm:findJoinablePublic() == nil, "nach reopen, aber noch voll -> nicht gefunden")
	rm:leaveRoom(pub, "p2")
	ok(rm:findJoinablePublic() == pub, "nach Freiwerden eines Sitzes wieder gefunden")
end

-- ===================== Profile (Wallet + Statistiken) =====================
print("== Profile: Default + Sanitize ==")
do
	local d = Profile.default(123, "Anna")
	ok(d.userId == "123", "default userId als String")
	ok(d.name == "Anna", "default name")
	ok(d.wallet == Profile.STARTING_WALLET, "default wallet = Startguthaben")
	ok(d.matchesWon == 0 and d.handsWon == 0 and d.biggestPot == 0, "default Statistiken 0")

	-- Sanitize: fehlende/fehlerhafte Felder werden ergaenzt/korrigiert.
	local s = Profile.sanitize({ wallet = "250", matchesWon = 3, biggestPot = -5 }, 7, "Bob")
	ok(s.wallet == 250, "sanitize: String-Wallet -> Zahl")
	ok(s.matchesWon == 3, "sanitize: matchesWon uebernommen")
	ok(s.handsWon == 0, "sanitize: fehlendes Feld -> 0")
	ok(s.biggestPot == 0, "sanitize: negatives Feld -> 0 geklemmt")
	ok(s.name == "Bob", "sanitize: Name-Override")

	-- Nicht-Tabelle (z. B. nil aus leerem DataStore) -> Default.
	local n = Profile.sanitize(nil, 9, "Cara")
	ok(n.wallet == Profile.STARTING_WALLET and n.name == "Cara", "sanitize(nil) -> Default")

	-- Tutorial-Flag: default false, sanitize bewahrt true, markTutorialDone setzt.
	ok(d.tutorialDone == false, "default: Tutorial noch nicht gesehen")
	ok(Profile.sanitize({ tutorialDone = true }, 1, "X").tutorialDone == true, "sanitize bewahrt tutorialDone")
	ok(Profile.sanitize({}, 1, "X").tutorialDone == false, "sanitize: fehlendes tutorialDone -> false")
	local tp = Profile.default(1, "X")
	Profile.markTutorialDone(tp)
	ok(tp.tutorialDone == true, "markTutorialDone setzt das Flag")

	-- Progressions-/Kosmetik-Felder: Defaults, Sanitize, Mutatoren, publicView.
	ok(d.xp == 0, "default: xp 0")
	ok(d.cardBack == "default" and d.tableTheme == "default" and d.avatarFrame == "default", "default: Kosmetik = default")
	local sc = Profile.sanitize({ xp = "150", cardBack = "crimson", tableTheme = 5, avatarFrame = "gold" }, 1, "X")
	ok(sc.xp == 150, "sanitize: String-XP -> Zahl")
	ok(sc.cardBack == "crimson", "sanitize: cardBack uebernommen")
	ok(sc.tableTheme == "default", "sanitize: nicht-String tableTheme -> default")
	ok(sc.avatarFrame == "gold", "sanitize: avatarFrame uebernommen")
	ok(Profile.sanitize({ xp = -10 }, 1, "X").xp == 0, "sanitize: negatives xp -> 0")
	local xp = Profile.default(1, "X")
	Profile.addXp(xp, 30)
	Profile.addXp(xp, 0)
	Profile.addXp(xp, -100) -- negativ wird ignoriert (>=0)
	ok(xp.xp == 30, "addXp: summiert, negativ ignoriert")
	Profile.setCosmetic(xp, "cardBack", "forest")
	Profile.setCosmetic(xp, "tableTheme", "blue")
	Profile.setCosmetic(xp, "avatarFrame", "silver")
	Profile.setCosmetic(xp, "unknownCat", "x") -- ignoriert
	Profile.setCosmetic(xp, "cardBack", "") -- leere id ignoriert
	ok(xp.cardBack == "forest" and xp.tableTheme == "blue" and xp.avatarFrame == "silver", "setCosmetic setzt je Kategorie")
	local pubc = Profile.publicView(xp)
	ok(pubc.xp == 30 and pubc.cardBack == "forest" and pubc.tableTheme == "blue" and pubc.avatarFrame == "silver", "publicView enthaelt xp + Kosmetik")
end

-- ===================== Progression (XP/Level + Kosmetik) =====================
print("== Progression: XP / Level ==")
do
	-- Level 1 ab 0 XP; xpForLevel(1) = 0.
	ok(Progression.levelFromXp(0) == 1, "0 XP -> Level 1")
	ok(Progression.xpForLevel(1) == 0, "xpForLevel(1) = 0")
	-- Genau BASE_XP -> Level 2; einen Punkt darunter -> noch Level 1.
	ok(Progression.levelFromXp(Progression.BASE_XP) == 2, "BASE_XP -> Level 2")
	ok(Progression.levelFromXp(Progression.BASE_XP - 1) == 1, "knapp drunter -> Level 1")
	-- xpForLevel/levelFromXp sind konsistent: an jeder Schwelle steigt das Level.
	for lvl = 1, 10 do
		local need = Progression.xpForLevel(lvl)
		ok(Progression.levelFromXp(need) == lvl, "xpForLevel/levelFromXp konsistent bei " .. lvl)
		if lvl > 1 then
			ok(Progression.levelFromXp(need - 1) == lvl - 1, "eine XP unter Schwelle -> Level-1 bei " .. lvl)
		end
	end
	-- Deckel bei MAX_LEVEL.
	ok(Progression.levelFromXp(1e9) == Progression.MAX_LEVEL, "riesige XP -> MAX_LEVEL")
	-- progress(): Felder + Prozent.
	local pr = Progression.progress(Progression.BASE_XP) -- exakt Level 2, 0 im Level
	ok(pr.level == 2 and pr.xpInLevel == 0, "progress: Level 2, 0 im Level")
	ok(pr.pct == 0 and pr.max == false, "progress: pct 0, nicht max")
	local prMax = Progression.progress(1e9)
	ok(prMax.max == true and prMax.pct == 1 and prMax.xpToNext == 0, "progress: MAX -> pct 1, xpToNext 0")
	-- Negatives/Unsinn-XP wird auf 0 geklemmt.
	ok(Progression.progress(-50).level == 1, "progress(negativ) -> Level 1")
end

print("== Progression: Kosmetik-Kataloge ==")
do
	for _, cat in { "cardBack", "tableTheme", "avatarFrame" } do
		local list = Progression.catalog(cat)
		ok(type(list) == "table" and #list >= 1, "catalog " .. cat .. " vorhanden")
		ok(list[1].level == 1, "default-Item von " .. cat .. " ist Level 1")
		ok(Progression.defaultId(cat) == list[1].id, "defaultId = erstes Item (" .. cat .. ")")
		-- Default ist immer freigeschaltet (auch auf Level 1).
		ok(Progression.isUnlocked(1, cat, list[1].id) == true, "default von " .. cat .. " auf Level 1 frei")
		-- colorOf liefert ein {r,g,b}-Tripel.
		local col = Progression.colorOf(cat, list[1].id)
		ok(type(col) == "table" and #col == 3, "colorOf " .. cat .. " -> {r,g,b}")
	end
	ok(Progression.catalog("quatsch") == nil, "unbekannte Kategorie -> nil")
	ok(Progression.find("cardBack", "gibtsnicht") == nil, "find: unbekannte id -> nil")
	-- isUnlocked: gesperrtes Item erst ab seinem Level.
	local crimson = Progression.find("cardBack", "crimson")
	ok(crimson ~= nil and crimson.level >= 2, "crimson existiert und braucht Level >= 2")
	ok(Progression.isUnlocked(crimson.level - 1, "cardBack", "crimson") == false, "crimson unter Level gesperrt")
	ok(Progression.isUnlocked(crimson.level, "cardBack", "crimson") == true, "crimson ab Level frei")
	-- isUnlocked auf unbekannte id/Kategorie -> false (kein Crash).
	ok(Progression.isUnlocked(99, "cardBack", "gibtsnicht") == false, "isUnlocked unbekannte id -> false")
	-- colorOf-Fallback bei unbekannter id -> Default-Farbe der Kategorie.
	ok(type(Progression.colorOf("cardBack", "gibtsnicht")) == "table", "colorOf-Fallback liefert Default-Farbe")
end

print("== Progression: VIP-exklusive Kosmetik ==")
do
	-- VIP-Items sind ohne VIP gesperrt — selbst auf Max-Level.
	ok(Progression.find("cardBack", "vip_royal") ~= nil, "vip_royal existiert")
	ok(Progression.find("avatarFrame", "vip_crown") ~= nil, "vip_crown existiert")
	ok(Progression.isUnlocked(Progression.MAX_LEVEL, "cardBack", "vip_royal", false) == false, "VIP-Item ohne VIP gesperrt (auch Max-Level)")
	ok(Progression.isUnlocked(1, "cardBack", "vip_royal", true) == true, "VIP-Item mit VIP frei (auch Level 1)")
	ok(Progression.isUnlocked(Progression.MAX_LEVEL, "avatarFrame", "vip_crown", false) == false, "vip_crown ohne VIP gesperrt")
	ok(Progression.isUnlocked(1, "avatarFrame", "vip_crown", true) == true, "vip_crown mit VIP frei")
	-- Normale Items ignorieren das VIP-Flag (rueckwaertskompatibel).
	ok(Progression.isUnlocked(2, "cardBack", "crimson") == true, "normales Item ohne isVip-Arg weiterhin frei")
end

-- ===================== Monetization (Shop) =====================
print("== Monetization: Chip-Pakete + VIP ==")
do
	-- Kataloge vorhanden.
	ok(#Monetization.CHIP_PACKS >= 1, "Chip-Pakete im Katalog")
	ok(type(Monetization.VIP) == "table" and Monetization.VIP.dailyMultiplier == 2, "VIP-Definition mit x2-Bonus")

	-- Default: productId/passId 0 -> nichts kaufbar (kein versehentlicher Verkauf).
	for _, pack in Monetization.CHIP_PACKS do
		ok(Monetization.packAvailable(pack) == false, "Paket ohne productId nicht kaufbar: " .. pack.id)
	end
	ok(Monetization.vipAvailable() == false, "VIP ohne passId nicht kaufbar")

	-- findPack per id.
	local small = Monetization.findPack("chips_small")
	ok(small ~= nil and small.chips > 0, "findPack liefert Paket")
	ok(Monetization.findPack("gibtsnicht") == nil, "findPack: unbekannte id -> nil")

	-- productId 0 matcht NIE (Schutz vor Fehlgutschrift).
	ok(Monetization.packByProductId(0) == nil, "productId 0 -> nil")
	ok(Monetization.chipsForProduct(0) == 0, "chipsForProduct(0) = 0")
	ok(Monetization.chipsForProduct(12345) == 0, "unbekannte productId -> 0 Chips")

	-- Mit gesetzter productId wird das Paket auffindbar + kaufbar.
	local pk = Monetization.CHIP_PACKS[1]
	local origId = pk.productId
	pk.productId = 99001
	ok(Monetization.packAvailable(pk) == true, "Paket mit productId kaufbar")
	ok(Monetization.packByProductId(99001) == pk, "packByProductId findet das Paket")
	ok(Monetization.chipsForProduct(99001) == pk.chips, "chipsForProduct = Paket-Chips")
	pk.productId = origId -- Katalog wiederherstellen (keine Seiteneffekte)

	-- VIP-Bonus-Multiplikator.
	ok(Monetization.applyVipBonus(500, false) == 500, "Nicht-VIP: Bonus unveraendert")
	ok(Monetization.applyVipBonus(500, true) == 1000, "VIP: Bonus verdoppelt")
	ok(Monetization.applyVipBonus(-50, true) == 0, "negativer Bonus -> 0 geklemmt")
end

print("== Profile: VIP-Flag + Tagesbonus-Multiplikator ==")
do
	local p = Profile.default(1, "X")
	ok(p.vip == false, "default: kein VIP")
	Profile.setVip(p, true)
	ok(p.vip == true, "setVip setzt das Flag")
	ok(Profile.publicView(p).vip == true, "publicView enthaelt vip")
	-- sanitize vertraut gespeichertem VIP NICHT (immer false; Server leitet ab).
	ok(Profile.sanitize({ vip = true }, 1, "X").vip == false, "sanitize: VIP wird nicht aus Speicher vertraut")

	-- Tagesbonus mit Multiplikator (VIP x2).
	local DAY = 86400
	local q = Profile.default(2, "Y")
	q.wallet = 0
	local b = Profile.claimDailyBonus(q, 10 * DAY, 2)
	ok(b.granted and b.amount == Profile.DAILY_BASE * 2, "VIP-Tagesbonus verdoppelt")
	ok(b.vip == true, "Bonus markiert vip=true bei Multiplikator")
	ok(q.wallet == Profile.DAILY_BASE * 2, "Wallet erhaelt den verdoppelten Bonus")
	-- Ohne Multiplikator: unveraendert (Default 1).
	local r = Profile.default(3, "Z")
	local b2 = Profile.claimDailyBonus(r, 10 * DAY)
	ok(b2.amount == Profile.DAILY_BASE and b2.vip == false, "ohne Multiplikator: Basisbetrag, vip=false")
end

print("== Profile: refill + Mutatoren ==")
do
	local p = Profile.default(1, "X")
	p.wallet = 0
	Profile.refillIfBroke(p)
	ok(p.wallet == Profile.REFILL_TO, "refill: leeres Wallet aufgefuellt")

	p.wallet = 500
	Profile.refillIfBroke(p)
	ok(p.wallet == 500, "refill: volles Wallet unveraendert")

	Profile.adjustWallet(p, -200)
	ok(p.wallet == 300, "adjustWallet: Abbuchung")
	Profile.adjustWallet(p, -9999)
	ok(p.wallet == 0, "adjustWallet: Clamp >= 0")
	Profile.adjustWallet(p, 150)
	ok(p.wallet == 150, "adjustWallet: Gutschrift")

	Profile.recordMatchWin(p)
	Profile.recordMatchWin(p)
	ok(p.matchesWon == 2, "recordMatchWin zaehlt")

	Profile.recordHandWin(p, 400)
	ok(p.handsWon == 1 and p.biggestPot == 400, "recordHandWin: Hand + biggestPot")
	Profile.recordHandWin(p, 100)
	ok(p.biggestPot == 400, "recordHandWin: kleinerer Pot aendert biggestPot nicht")
	Profile.recordHandWin(p, 900)
	ok(p.biggestPot == 900, "recordHandWin: groesserer Pot aktualisiert biggestPot")

	local pub = Profile.publicView(p)
	ok(pub.wallet == 150 and pub.matchesWon == 2 and pub.handsWon == 3, "publicView Felder")
	ok(pub.userId == nil and pub.createdAt == nil, "publicView ohne interne Felder")
end

print("== Profile: taeglicher Login-Bonus ==")
do
	local DAY = 86400
	local p = Profile.default(1, "X")
	p.wallet = 1000

	-- Tag 10: erster Bonus -> Basisbetrag, Streak 1.
	local b1 = Profile.claimDailyBonus(p, 10 * DAY + 500)
	ok(b1.granted and b1.streak == 1, "Bonus Tag 1 vergeben, Streak 1")
	ok(b1.amount == Profile.DAILY_BASE, "Bonus Tag 1 = Basisbetrag")
	ok(p.wallet == 1000 + Profile.DAILY_BASE, "Wallet um Bonus erhoeht")

	-- Selber Tag erneut -> kein Bonus.
	local b1b = Profile.claimDailyBonus(p, 10 * DAY + 9000)
	ok(not b1b.granted and b1b.amount == 0, "kein zweiter Bonus am selben Tag")

	-- Folgetag -> Streak 2, hoeherer Betrag.
	local b2 = Profile.claimDailyBonus(p, 11 * DAY + 10)
	ok(b2.granted and b2.streak == 2, "Folgetag: Streak 2")
	ok(b2.amount == Profile.DAILY_BASE + Profile.DAILY_STEP, "Folgetag: Betrag +Step")

	-- Luecke (Tag 20) -> Streak zurueck auf 1.
	local b3 = Profile.claimDailyBonus(p, 20 * DAY)
	ok(b3.granted and b3.streak == 1, "Luecke setzt Streak zurueck")

	-- Streak-Deckel: viele aufeinanderfolgende Tage -> Betrag bei MAX_STREAK gedeckelt.
	local q = Profile.default(2, "Y")
	local last
	for d = 0, Profile.DAILY_MAX_STREAK + 3 do
		last = Profile.claimDailyBonus(q, (100 + d) * DAY)
	end
	local capAmount = Profile.DAILY_BASE + (Profile.DAILY_MAX_STREAK - 1) * Profile.DAILY_STEP
	ok(last.amount == capAmount, "Bonus bei MAX_STREAK gedeckelt")

	-- sanitize bewahrt die Bonus-Felder.
	local s = Profile.sanitize({ lastDailyDay = 42, dailyStreak = 3 }, 5, "Z")
	ok(s.lastDailyDay == 42 and s.dailyStreak == 3, "sanitize bewahrt Bonus-Felder")
end

-- ===================== Quests (Tagesquests) =====================
print("== Quests: taegliche Auswahl deterministisch ==")
do
	local DAY = 86400
	-- Gleicher Tag -> gleiche Auswahl; pro Tag genau DAILY_COUNT.
	local a = Quests.dailyFor(100 * DAY + 10)
	local b = Quests.dailyFor(100 * DAY + 80000)
	ok(#a == Quests.DAILY_COUNT, "DAILY_COUNT Quests pro Tag")
	ok(#b == Quests.DAILY_COUNT, "auch spaeter am Tag DAILY_COUNT")
	local sameIds = true
	for i = 1, #a do
		if a[i].id ~= b[i].id then
			sameIds = false
		end
	end
	ok(sameIds, "selber Tag -> identische Quest-Auswahl")
	-- Alle gewaehlten Quests stammen aus dem Pool und haben Belohnung > 0.
	local poolIds = {}
	for _, def in Quests.POOL do
		poolIds[def.id] = true
	end
	for _, q in a do
		ok(poolIds[q.id] == true and q.chips > 0, "Quest aus Pool mit Chip-Belohnung: " .. q.id)
	end
	-- dayIndex monoton/korrekt.
	ok(Quests.dayIndex(0) == 0 and Quests.dayIndex(DAY) == 1, "dayIndex rechnet UTC-Tage")
end

print("== Quests: Fortschritt, Tageswechsel & Abholen ==")
do
	local DAY = 86400
	local now = 200 * DAY + 100
	local p = Profile.default(1, "X")
	-- Eine aktive Quest dieses Tages mit Ziel >= 2 herausgreifen (fuer Teil-
	-- Fortschritt). Faellt notfalls auf die erste Quest zurueck.
	local defs = Quests.dailyFor(now)
	local target = defs[1]
	for _, def in defs do
		if def.goal >= 2 then
			target = def
			break
		end
	end

	-- Fortschritt unter dem Ziel -> noch nicht abholbar.
	Quests.recordEvent(p, target.metric, target.goal - 1, now)
	local view1 = Quests.view(p, now)
	local seen
	for _, q in view1 do
		if q.id == target.id then
			seen = q
		end
	end
	ok(seen ~= nil and seen.progress == target.goal - 1 and not seen.done, "Fortschritt unter Ziel: nicht fertig")

	-- Abholen schlaegt fehl, solange unvollstaendig.
	local pre = Quests.claim(p, target.id, now)
	ok(pre.ok == false and pre.reason == "incomplete", "claim verweigert vor Abschluss")

	-- Ein weiteres Ereignis schliesst die Quest ab (und meldet sie als 'gerade fertig').
	local completed = Quests.recordEvent(p, target.metric, 5, now)
	local reported = false
	for _, def in completed do
		if def.id == target.id then
			reported = true
		end
	end
	ok(reported, "recordEvent meldet gerade abgeschlossene Quest")
	ok(Quests.claimableCount(p, now) >= 1, "mindestens eine Quest abholbereit")

	-- Abholen liefert die Belohnung und markiert als abgeholt.
	local res = Quests.claim(p, target.id, now)
	ok(res.ok and res.chips == target.chips and res.xp == target.xp, "claim liefert Chip-/XP-Belohnung")
	local again = Quests.claim(p, target.id, now)
	ok(again.ok == false and again.reason == "claimed", "kein doppeltes Abholen")

	-- Fortschritt deckelt aufs Ziel (keine Ueberzaehlung).
	local viewDone
	for _, q in Quests.view(p, now) do
		if q.id == target.id then
			viewDone = q
		end
	end
	ok(viewDone.progress == target.goal and viewDone.claimed, "Fortschritt aufs Ziel gedeckelt + abgeholt")

	-- Tageswechsel setzt Fortschritt + Abgeholt-Status zurueck.
	local nextDay = now + DAY
	Quests.ensureDay(p, nextDay)
	ok(p.questDay == Quests.dayIndex(nextDay), "ensureDay aktualisiert questDay")
	local viewNew = Quests.view(p, nextDay)
	local anyProgress = false
	for _, q in viewNew do
		if q.progress > 0 or q.claimed then
			anyProgress = true
		end
	end
	ok(not anyProgress, "Tageswechsel: Fortschritt zurueckgesetzt")

	-- Unbekannte Quest-id -> sauberes Fehlerergebnis.
	ok(Quests.claim(p, "gibtsnicht", nextDay).ok == false, "claim unbekannte id -> ok=false")
end

print("== Quests: Persistenz ueber Profil (sanitize) ==")
do
	local now = 300 * 86400
	local p = Profile.default(7, "P")
	p.questDay = Quests.dayIndex(now)
	p.questProgress = { win2hands = 1, junk = 3 }
	p.questClaimed = { win2hands = true }
	-- default enthaelt die Quest-Felder.
	ok(type(p.questProgress) == "table" and type(p.questClaimed) == "table", "default hat Quest-Tabellen")
	-- sanitize bewahrt die Quest-Felder (string-Keys, bereinigte Werte).
	local s = Profile.sanitize({
		questDay = 42,
		questProgress = { win2hands = 2, [5] = 9 },
		questClaimed = { win2hands = true, bogus = "x" },
	}, 7, "P")
	ok(s.questDay == 42, "sanitize bewahrt questDay")
	ok(s.questProgress.win2hands == 2 and s.questProgress[5] == nil, "sanitize: nur string-Keys im Fortschritt")
	ok(s.questClaimed.win2hands == true and s.questClaimed.bogus == nil, "sanitize: nur echte true-Claims")
end

-- ===================== Saison-Leaderboard =====================
print("== Season: Index, Nummer & Restzeit ==")
do
	-- EPOCH = Saison #1, Start. Index 0 -> Nummer 1.
	ok(Season.indexFor(Season.EPOCH) == 0, "EPOCH -> Index 0")
	ok(Season.number(Season.EPOCH) == 1, "EPOCH -> Saison #1")
	-- Eine Woche spaeter: Index 1, Nummer 2.
	ok(Season.indexFor(Season.EPOCH + Season.LENGTH) == 1, "EPOCH + 1 Woche -> Index 1")
	ok(Season.number(Season.EPOCH + Season.LENGTH) == 2, "EPOCH + 1 Woche -> Saison #2")
	-- Kurz vor dem Wechsel noch Index 0.
	ok(Season.indexFor(Season.EPOCH + Season.LENGTH - 1) == 0, "1 s vor Wechsel -> noch Index 0")
	-- Restzeit: am Start = volle Woche; kurz vor Ende = 1 s; nie negativ.
	ok(Season.secondsLeft(Season.EPOCH) == Season.LENGTH, "Restzeit am Start = volle Woche")
	ok(Season.secondsLeft(Season.EPOCH + Season.LENGTH - 1) == 1, "Restzeit kurz vor Ende = 1 s")
	ok(Season.secondsLeft(Season.EPOCH) >= 0, "Restzeit nie negativ")
	-- Start-/Endzeit konsistent.
	ok(Season.startTime(3) == Season.EPOCH + 3 * Season.LENGTH, "startTime(3) korrekt")
	ok(Season.endTime(3) == Season.startTime(4), "endTime(3) = startTime(4)")
end

print("== Season: Punkte & Belohnungsstufen ==")
do
	ok(Season.pointsFor("handWin") == 1, "handWin = 1 Punkt")
	ok(Season.pointsFor("bigPot") == 2, "bigPot = 2 Punkte")
	ok(Season.pointsFor("matchWin") == 8, "matchWin = 8 Punkte")
	ok(Season.pointsFor("unbekannt") == 0, "unbekannte Metrik = 0 Punkte")
	-- Belohnung nach End-Punktzahl (hoechste erreichte Stufe).
	ok(Season.rewardForPoints(0) == nil, "0 Punkte -> keine Belohnung")
	ok(Season.rewardForPoints(14) == nil, "14 Punkte -> noch keine Stufe")
	ok(Season.rewardForPoints(15).tier == 1, "15 Punkte -> Stufe 1 (Silber)")
	ok(Season.rewardForPoints(79).tier == 2, "79 Punkte -> Stufe 2 (Gold)")
	ok(Season.rewardForPoints(1000).tier == 4, "viele Punkte -> hoechste Stufe (Champion)")
	-- addPoints summiert nach Metrik.
	local p = Profile.default(1, "P")
	p.seasonIndex = Season.indexFor(Season.EPOCH)
	Season.addPoints(p, "handWin")
	Season.addPoints(p, "matchWin")
	ok(p.seasonPoints == 9, "addPoints: 1 + 8 = 9")
	Season.addPoints(p, "unbekannt")
	ok(p.seasonPoints == 9, "addPoints: unbekannte Metrik aendert nichts")
end

print("== Season: Rollover & Belohnungsvergabe ==")
do
	local s0 = Season.EPOCH -- Saison #1
	local s1 = Season.EPOCH + Season.LENGTH -- Saison #2
	-- Frisches Profil (seasonIndex -1): erster Sync uebernimmt nur, keine Belohnung.
	local p = Profile.default(1, "P")
	ok(p.seasonIndex == -1, "default seasonIndex = -1")
	local r0 = Season.rollover(p, s0)
	ok(r0 == nil, "erster Sync gibt keine Belohnung")
	ok(p.seasonIndex == Season.indexFor(s0) and p.seasonPoints == 0, "Sync setzt Index, Punkte 0")
	-- Gleiche Saison: kein Rollover, Punkte bleiben.
	Season.addPoints(p, "matchWin") -- 8
	Season.addPoints(p, "matchWin") -- 16
	ok(Season.rollover(p, s0) == nil, "gleiche Saison -> kein Rollover")
	ok(p.seasonPoints == 16, "gleiche Saison -> Punkte bleiben")
	-- Saison-Wechsel mit genug Punkten (16 >= 15): Stufe 1, Punkte zuruecksetzen.
	local r1 = Season.rollover(p, s1)
	ok(r1 ~= nil and r1.tier == 1, "Wechsel mit 16 Pkt -> Belohnung Stufe 1")
	ok(p.seasonPoints == 0, "nach Wechsel Punkte zurueckgesetzt")
	ok(p.seasonIndex == Season.indexFor(s1), "nach Wechsel neuer Saison-Index")
	-- Saison-Wechsel mit zu wenig Punkten: keine Belohnung, trotzdem Reset.
	local q = Profile.default(2, "Q")
	q.seasonIndex = Season.indexFor(s0)
	Season.addPoints(q, "handWin") -- 1 Punkt (< 15)
	local rq = Season.rollover(q, s1)
	ok(rq == nil, "Wechsel mit 1 Pkt -> keine Belohnung")
	ok(q.seasonPoints == 0 and q.seasonIndex == Season.indexFor(s1), "trotzdem Reset auf neue Saison")
end

print("== Season: View & Profil-Persistenz ==")
do
	local s0 = Season.EPOCH
	-- view: eigene Punkte zaehlen nur in der aktuellen Saison.
	local p = Profile.default(1, "P")
	p.seasonIndex = Season.indexFor(s0)
	p.seasonPoints = 42
	local v = Season.view(p, s0)
	ok(v.number == 1 and v.points == 42, "view: Nummer + eigene Punkte")
	ok(v.secondsLeft == Season.LENGTH, "view: Restzeit am Saison-Start")
	-- Punkte aus einer alten Saison zaehlen nicht (zeigt 0).
	local vOld = Season.view(p, s0 + Season.LENGTH)
	ok(vOld.points == 0, "view: Punkte alter Saison zaehlen nicht")
	-- default + sanitize bewahren die Saison-Felder.
	ok(Profile.default(9).seasonIndex == -1 and Profile.default(9).seasonPoints == 0, "default hat Saison-Felder")
	local sp = Profile.sanitize({ seasonIndex = 5, seasonPoints = 77 }, 9, "P")
	ok(sp.seasonIndex == 5 and sp.seasonPoints == 77, "sanitize bewahrt Saison-Felder")
	-- Negative/ungueltige Punkte werden geklemmt; fehlende Felder -> Defaults.
	local sp2 = Profile.sanitize({ seasonPoints = -10 }, 9, "P")
	ok(sp2.seasonPoints == 0, "sanitize klemmt negative Punkte auf 0")
	ok(sp2.seasonIndex == -1, "sanitize: fehlender Index -> -1")
end

-- ===================== Friends (Einladungen/Empfehlungen) =====================
print("== Friends: Berechtigung & Werbung ==")
do
	-- Ein frisches Profil ist werbe-berechtigt; ein bereits geworbenes nicht.
	local p = Profile.default(2, "Neu")
	ok(Friends.eligibleInvitee(p), "frisches Profil ist werbe-berechtigt")
	local reward = Friends.markReferred(p, 99, 2)
	ok(reward ~= nil and reward.chips == Friends.INVITEE_CHIPS, "markReferred gibt Willkommensbonus")
	ok(p.referredBy == "99", "referredBy wird auf Inviter-Id gesetzt")
	ok(not Friends.eligibleInvitee(p), "nach Werbung nicht mehr berechtigt")
	-- Doppelte Werbung tut nichts.
	ok(Friends.markReferred(p, 77, 2) == nil, "doppelte Werbung -> nil")
	ok(p.referredBy == "99", "doppelte Werbung aendert Inviter nicht")
end

print("== Friends: Guards (Selbstwerbung, ungueltig) ==")
do
	-- Selbstwerbung ist verboten.
	local p = Profile.default(5, "Ich")
	ok(Friends.markReferred(p, 5, 5) == nil, "Selbstwerbung -> nil")
	ok(p.referredBy == "", "Selbstwerbung setzt nichts")
	-- Leere/ungueltige Inviter-Id -> nil.
	ok(Friends.markReferred(p, "", 5) == nil, "leere Inviter-Id -> nil")
	ok(Friends.markReferred(p, nil, 5) == nil, "nil Inviter-Id -> nil")
end

print("== Friends: Empfehlungs-Belohnung & Cap ==")
do
	-- Erster geworbener Freund -> Belohnung + Zaehler 1.
	local inv = Profile.default(10, "Werber")
	local r1 = Friends.recordSuccess(inv)
	ok(r1.rewarded and r1.count == 1 and r1.chips == Friends.INVITER_CHIPS, "1. Empfehlung: Belohnung + count 1")
	-- Bis zum Cap wird verguetet.
	for _ = 2, Friends.MAX_REWARDED do
		Friends.recordSuccess(inv)
	end
	ok(inv.invitesAccepted == Friends.MAX_REWARDED, "Zaehler steht am Cap")
	-- Ueber dem Cap: weiter zaehlen, nicht mehr verguetet.
	local rOver = Friends.recordSuccess(inv)
	ok(not rOver.rewarded and rOver.chips == 0, "ueber Cap: nicht verguetet")
	ok(inv.invitesAccepted == Friends.MAX_REWARDED + 1, "ueber Cap: weiter gezaehlt")
end

print("== Friends: View & Profil-Persistenz ==")
do
	-- default + sanitize bewahren die Freundes-Felder.
	ok(Profile.default(7).referredBy == "" and Profile.default(7).invitesAccepted == 0, "default hat Freundes-Felder")
	local sp = Profile.sanitize({ referredBy = "42", invitesAccepted = 3 }, 7, "P")
	ok(sp.referredBy == "42" and sp.invitesAccepted == 3, "sanitize bewahrt Freundes-Felder")
	-- Ungueltige Werte werden bereinigt.
	local sp2 = Profile.sanitize({ referredBy = 123, invitesAccepted = -5 }, 7, "P")
	ok(sp2.referredBy == "" and sp2.invitesAccepted == 0, "sanitize bereinigt ungueltige Freundes-Felder")
	-- View spiegelt Zaehler + Geworben-Status.
	local v = Friends.view(sp)
	ok(v.invitesAccepted == 3 and v.wasReferred == true, "view: Zaehler + wasReferred")
	local vFresh = Friends.view(Profile.default(8))
	ok(vFresh.invitesAccepted == 0 and vFresh.wasReferred == false, "view: frisches Profil")
end

-- ===================== Bot (KI-Gegner) =====================
print("== Bot: Entscheidungslogik ==")
do
	-- Nicht am Zug -> keine Entscheidung.
	ok(Bot.decide({ yourTurn = false }) == nil, "kein Zug -> nil")
	ok(Bot.decide({ yourTurn = true, actions = nil }) == nil, "keine Aktionen -> nil")

	-- Schwache Hand (hohe Karte) gegen grossen Einsatz -> Fold.
	local rngHi = function()
		return 0.99
	end
	local weakFacingBet = {
		yourTurn = true,
		totalPot = 100,
		currentBet = 200,
		community = { { rank = 1, suit = 0 }, { rank = 3, suit = 1 }, { rank = 5, suit = 2 } },
		meIdx = 1,
		players = { { hole = { { rank = 2, suit = 0 }, { rank = 4, suit = 1 } } } },
		myHand = { cat = 2 },
		actions = { canCheck = false, canCall = true, toCall = 200, canRaise = true, minRaiseTo = 400, maxRaiseTo = 1000 },
	}
	ok(Bot.decide(weakFacingBet, rngHi).type == "fold", "schwache Hand gegen grossen Einsatz -> Fold")

	-- Starke Hand (Full House) gegen Einsatz -> Raise mit gueltigem Betrag.
	local strongFacingBet = {
		yourTurn = true,
		totalPot = 300,
		currentBet = 100,
		community = { { rank = 9, suit = 0 }, { rank = 9, suit = 1 }, { rank = 5, suit = 2 } },
		meIdx = 1,
		players = { { hole = { { rank = 9, suit = 3 }, { rank = 5, suit = 0 } } } },
		myHand = { cat = 7 },
		actions = { canCheck = false, canCall = true, toCall = 100, canRaise = true, minRaiseTo = 200, maxRaiseTo = 1000 },
	}
	local d = Bot.decide(strongFacingBet, rngHi)
	ok(d.type == "raise", "starke Hand -> Raise")
	ok(d.amount >= 200 and d.amount <= 1000, "Raise-Betrag liegt im erlaubten Bereich")

	-- Kein Einsatz, mittlere Hand, kein Bluff-Wurf -> Check.
	local noBet = {
		yourTurn = true,
		totalPot = 40,
		currentBet = 0,
		community = { { rank = 6, suit = 0 }, { rank = 2, suit = 1 }, { rank = 8, suit = 2 } },
		meIdx = 1,
		players = { { hole = { { rank = 6, suit = 3 }, { rank = 3, suit = 0 } } } },
		myHand = { cat = 3 },
		actions = { canCheck = true, canCall = false, toCall = 0, canRaise = true, minRaiseTo = 20, maxRaiseTo = 980 },
	}
	ok(Bot.decide(noBet, rngHi).type == "check", "kein Einsatz, mittlere Hand -> Check")
end

print("== Bot: treibt eine ganze Partie (Engine-Integration) ==")
do
	-- Drei Bots spielen eine komplette Partie nur via Bot.decide. Verifiziert, dass
	-- die Entscheidungen von der Engine stets akzeptiert werden, die Partie endet
	-- und Chips erhalten bleiben.
	math.randomseed(12345)
	local defs = { { id = "b1", name = "A" }, { id = "b2", name = "B" }, { id = "b3", name = "C" } }
	local t = PokerEngine.Table.new(defs, { startingStack = 1000 })
	t:startHand()
	local guard = 0
	local allValid = true
	local alwaysDecides = true
	while not t.matchOver and guard < 8000 do
		guard += 1
		if t.toAct ~= nil and t.stage ~= "handover" and t.stage ~= "showdown" then
			local pid = t.players[t.toAct].id
			local decision = Bot.decide(t:view(pid))
			if decision == nil then
				alwaysDecides = false
				break
			end
			local res = t:act(pid, decision.type, decision.amount)
			if res and res.error then
				allValid = false
				break
			end
		elseif t.stage == "handover" then
			if t.matchOver then
				break
			end
			t:startHand()
		else
			break
		end
	end
	ok(alwaysDecides, "Bot liefert immer eine Entscheidung, wenn am Zug")
	ok(allValid, "alle Bot-Aktionen sind fuer die Engine gueltig")
	ok(t.matchOver, "Partie unter Bots terminiert")
	ok(guard < 8000, "Partie endet ohne Endlosschleife")
	local total = 0
	for _, p in t.players do
		total += p.stack
	end
	ok(total == 3000, "Chips bleiben erhalten (3x1000)")
end

print(string.format("\n%d bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then
	for _, m in failures do
		print("FAIL: " .. m)
	end
	os.exit(1)
end
