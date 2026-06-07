--!nonstrict
-- Reine, testbare KI-Policy fuer KuhPoker-Bots. Keine Roblox-API — daher
-- standalone via luau-CLI testbar. Entscheidet anhand der Spieler-Sicht
-- (PokerEngine Table:view(botId)) eine Aktion.
--
-- Designziel: "okay, nicht perfekt". Die Bots spielen plausibel nach
-- Handstaerke und Pot-Odds, mit etwas Varianz (gelegentliche Bluffs/Folds),
-- damit sie menschlich wirken und neue Spieler nie an einem leeren Tisch sitzen.
-- Sie sind bewusst schlagbar.

local Bot = {}

-- Huebsche, neutrale Bot-Namen (mit Praefix als Bot erkennbar gemacht im Server).
Bot.NAMES = {
	"Bolle", "Klara", "Mathilde", "Theo", "Frieda", "Emil", "Greta", "Otto",
	"Lotte", "Henri", "Paula", "Fritz", "Marie", "Anton", "Rosa", "Karl",
}

-- Kategorie (Nicht-Flush-Skala 2..8, Flush-Skala bis 10) -> grobe
-- Gewinn-Wahrscheinlichkeit postflop. Hoeher = staerker.
local function strengthFromCategory(cat)
	if cat >= 9 then
		return 0.98 -- Vierling/Straight-Flush (Flush-Modus)
	elseif cat == 8 then
		return 0.97 -- Vierling
	elseif cat == 7 then
		return 0.94 -- Full House
	elseif cat == 6 then
		return 0.88 -- Strasse / Flush(8 im Flush-Modus deckt sich grob)
	elseif cat == 5 then
		return 0.82 -- Drilling
	elseif cat == 4 then
		return 0.7 -- Zwei Paare
	elseif cat == 3 then
		return 0.48 -- Paar
	else
		return 0.16 -- Hohe Karte
	end
end

-- Schaetzt die "Staerke" (0..1) der eigenen Hand aus der Sicht.
local function estimateStrength(view)
	local me = view.players and view.meIdx and view.players[view.meIdx]
	local hole = (me and me.hole) or {}
	local community = view.community or {}
	local preflop = #community == 0
	local cat = (view.myHand and view.myHand.cat) or 2

	if preflop then
		-- Preflop liefert die Kategorie nur Paar (>=3) vs. hohe Karte (2).
		-- High-Card-Qualitaet (Raenge 1..10) feiner einbeziehen.
		local hi, lo = 0, 0
		for _, c in hole do
			if type(c) == "table" and c.rank then
				if c.rank > hi then
					lo = hi
					hi = c.rank
				elseif c.rank > lo then
					lo = c.rank
				end
			end
		end
		local s
		if cat >= 3 then
			-- Pocket Pair: stark, skaliert mit Rang.
			s = 0.6 + 0.035 * hi
		else
			s = 0.12 + 0.05 * hi + 0.02 * lo
		end
		return math.clamp(s, 0.1, 0.95)
	end

	return strengthFromCategory(cat)
end

-- Waehlt eine Erhoehungs-Zielsumme (absolut, wie act() es erwartet).
local function raiseAction(view, a, s, rng)
	local minTo = a.minRaiseTo or 0
	local maxTo = a.maxRaiseTo or 0
	if maxTo <= minTo then
		-- Nur All-In moeglich (kein Spielraum).
		return { type = "raise", amount = maxTo }
	end
	local pot = math.max(1, view.totalPot or 0)
	-- Halber bis ganzer Pot, staerkere Haende setzen groesser; etwas Rauschen.
	local frac = 0.5 + 0.5 * math.clamp(s, 0, 1) + (rng() - 0.5) * 0.2
	local target = (view.currentBet or 0) + math.floor(frac * pot)
	-- Monster gelegentlich direkt All-In.
	if s > 0.93 and rng() < 0.3 then
		target = maxTo
	end
	if target < minTo then
		target = minTo
	elseif target > maxTo then
		target = maxTo
	end
	return { type = "raise", amount = target }
end

-- Entscheidet die naechste Aktion fuer den Bot. `rng` ist injizierbar
-- (Funktion -> [0,1)) fuer deterministische Tests; default math.random.
-- Gibt { type = "fold"|"check"|"call"|"raise", amount? } oder nil zurueck,
-- falls der Bot nicht am Zug ist.
function Bot.decide(view, rng)
	rng = rng or math.random
	if not view or not view.yourTurn or not view.actions then
		return nil
	end
	local a = view.actions

	local s = estimateStrength(view)
	-- Etwas Rauschen fuer menschliches Verhalten.
	s = math.clamp(s + (rng() - 0.5) * 0.15, 0, 1)

	local toCall = a.toCall or 0
	local pot = math.max(1, view.totalPot or 0)

	-- Kein Einsatz anliegend: checken oder gelegentlich (Value/Bluff) setzen.
	if a.canCheck then
		if a.canRaise and (s > 0.7 or rng() < 0.12) then
			return raiseAction(view, a, s, rng)
		end
		return { type = "check" }
	end

	-- Es liegt ein Einsatz an. Benoetigte Equity (Pot-Odds).
	local potOdds = toCall / (pot + toCall)

	-- Mit starker Hand erhoehen.
	if a.canRaise and (s > 0.8 or (s > 0.62 and rng() < 0.35)) then
		return raiseAction(view, a, s, rng)
	end

	-- Callen, wenn die Staerke die Pot-Odds (mit kleiner Toleranz) schlaegt.
	if s >= potOdds - 0.05 then
		return { type = "call" }
	end

	-- Seltener Float/Bluff-Call gegen kleine Einsaetze.
	if rng() < 0.05 and toCall <= pot * 0.25 then
		return { type = "call" }
	end

	return { type = "fold" }
end

return Bot
