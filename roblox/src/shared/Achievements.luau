--!nonstrict
-- Reine Erfolge-/Abzeichen-Logik fuer KuhPoker. Keine Roblox-API — daher
-- standalone via luau-CLI testbar. Der DataStore-Teil liegt in
-- server/ProfileStore.luau; hier nur die reine Mechanik auf einem Profil.
--
-- Idee (Retention-/Engagement-Hebel): dauerhafte Meilensteine ueber die
-- LEBENSZEIT-Statistiken eines Spielers (gewonnene Haende/Matches, groesster Pot,
-- gesammelte XP, geworbene Freunde). Jeder Meilenstein ist EINMALIG abholbar und
-- gibt Spass-Chips + XP. Anders als Tagesquests werden Erfolge nie zurueckgesetzt.
--
-- Reine Spass-Chips/XP — kein Echtgeldwert, kein Gluecksspiel, kein Pay-to-Win.

local Achievements = {}

-- Meilensteine, gruppiert nach Metrik, aufsteigend nach Ziel. Die Metrik verweist
-- direkt auf ein numerisches Profil-Feld (Lebenszeit-Statistik):
--   handsWon, matchesWon, biggestPot, xp, invitesAccepted
Achievements.LIST = {
	-- Gewonnene Haende
	{ id = "hands_1", metric = "handsWon", goal = 1, chips = 300, xp = 20,
		name = "Erste Hand", nameEn = "First hand",
		desc = "Gewinne deine erste Hand.", descEn = "Win your first hand." },
	{ id = "hands_10", metric = "handsWon", goal = 10, chips = 600, xp = 40,
		name = "Aufsteiger", nameEn = "Up and coming",
		desc = "Gewinne 10 Haende.", descEn = "Win 10 hands." },
	{ id = "hands_50", metric = "handsWon", goal = 50, chips = 1500, xp = 90,
		name = "Routinier", nameEn = "Regular",
		desc = "Gewinne 50 Haende.", descEn = "Win 50 hands." },
	{ id = "hands_200", metric = "handsWon", goal = 200, chips = 4000, xp = 220,
		name = "Hand-Hai", nameEn = "Hand shark",
		desc = "Gewinne 200 Haende.", descEn = "Win 200 hands." },
	{ id = "hands_1000", metric = "handsWon", goal = 1000, chips = 15000, xp = 700,
		name = "Legende", nameEn = "Legend",
		desc = "Gewinne 1000 Haende.", descEn = "Win 1000 hands." },
	-- Gewonnene Matches
	{ id = "match_1", metric = "matchesWon", goal = 1, chips = 800, xp = 50,
		name = "Erster Sieg", nameEn = "First win",
		desc = "Gewinne dein erstes Match.", descEn = "Win your first match." },
	{ id = "match_5", metric = "matchesWon", goal = 5, chips = 2000, xp = 130,
		name = "Seriensieger", nameEn = "Serial winner",
		desc = "Gewinne 5 Matches.", descEn = "Win 5 matches." },
	{ id = "match_25", metric = "matchesWon", goal = 25, chips = 6000, xp = 350,
		name = "Champion", nameEn = "Champion",
		desc = "Gewinne 25 Matches.", descEn = "Win 25 matches." },
	{ id = "match_100", metric = "matchesWon", goal = 100, chips = 20000, xp = 900,
		name = "Großmeister", nameEn = "Grandmaster",
		desc = "Gewinne 100 Matches.", descEn = "Win 100 matches." },
	-- Groesster Pot (Bestwert)
	{ id = "pot_1000", metric = "biggestPot", goal = 1000, chips = 500, xp = 30,
		name = "Dicker Pot", nameEn = "Nice pot",
		desc = "Gewinne einen Pot von 1.000 🪙.", descEn = "Win a 1,000 🪙 pot." },
	{ id = "pot_5000", metric = "biggestPot", goal = 5000, chips = 2500, xp = 150,
		name = "Riesen-Pot", nameEn = "Huge pot",
		desc = "Gewinne einen Pot von 5.000 🪙.", descEn = "Win a 5,000 🪙 pot." },
	{ id = "pot_20000", metric = "biggestPot", goal = 20000, chips = 8000, xp = 400,
		name = "Jackpot", nameEn = "Jackpot",
		desc = "Gewinne einen Pot von 20.000 🪙.", descEn = "Win a 20,000 🪙 pot." },
	-- Erfahrung (XP)
	{ id = "xp_500", metric = "xp", goal = 500, chips = 400, xp = 0,
		name = "Eingespielt", nameEn = "Warmed up",
		desc = "Sammle 500 XP.", descEn = "Collect 500 XP." },
	{ id = "xp_2500", metric = "xp", goal = 2500, chips = 1200, xp = 0,
		name = "Erfahren", nameEn = "Experienced",
		desc = "Sammle 2.500 XP.", descEn = "Collect 2,500 XP." },
	{ id = "xp_10000", metric = "xp", goal = 10000, chips = 5000, xp = 0,
		name = "Veteran", nameEn = "Veteran",
		desc = "Sammle 10.000 XP.", descEn = "Collect 10,000 XP." },
	-- Geworbene Freunde (verzahnt mit dem Einladungs-System)
	{ id = "ref_1", metric = "invitesAccepted", goal = 1, chips = 1000, xp = 60,
		name = "Gastgeber", nameEn = "Host",
		desc = "Wirb 1 Freund/in.", descEn = "Refer 1 friend." },
	{ id = "ref_5", metric = "invitesAccepted", goal = 5, chips = 3500, xp = 200,
		name = "Netzwerker", nameEn = "Networker",
		desc = "Wirb 5 Freunde.", descEn = "Refer 5 friends." },
	{ id = "ref_25", metric = "invitesAccepted", goal = 25, chips = 12000, xp = 600,
		name = "Botschafter", nameEn = "Ambassador",
		desc = "Wirb 25 Freunde.", descEn = "Refer 25 friends." },
}

local function toInt(v, default)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return default
	end
	return math.floor(n)
end

-- Aktueller Wert einer Metrik aus dem Profil (Lebenszeit-Statistik).
local function metricValue(p, metric)
	if type(p) ~= "table" then
		return 0
	end
	return math.max(0, toInt(p[metric], 0))
end

-- Liefert die Definition eines Erfolgs per id (oder nil).
function Achievements.find(id)
	for _, def in Achievements.LIST do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Anzeige-/Auswertungs-Sicht: Liste aller Erfolge mit Wert/Ziel/Status. Read-only
-- (mutiert das Profil NICHT). `unlocked` = Ziel erreicht; `claimed` = schon abgeholt.
function Achievements.view(p)
	p = p or {}
	local claimed = (type(p.achClaimed) == "table") and p.achClaimed or {}
	local out = {}
	for _, def in Achievements.LIST do
		local val = metricValue(p, def.metric)
		local capped = math.min(val, def.goal)
		out[#out + 1] = {
			id = def.id,
			name = def.name,
			nameEn = def.nameEn,
			desc = def.desc,
			descEn = def.descEn,
			metric = def.metric,
			goal = def.goal,
			value = capped,
			unlocked = val >= def.goal,
			claimed = claimed[def.id] == true,
			chips = def.chips,
			xp = def.xp,
		}
	end
	return out
end

-- Holt die Belohnung eines erreichten Erfolgs ab. Mutiert NICHT Wallet/XP — das
-- macht der Aufrufer (Server/ProfileStore), damit die Logik rein bleibt. Markiert
-- den Erfolg als abgeholt. Gibt { ok, chips, xp, id } bzw. { ok=false, reason }.
function Achievements.claim(p, id)
	if type(p.achClaimed) ~= "table" then
		p.achClaimed = {}
	end
	local def = Achievements.find(id)
	if not def then
		return { ok = false, reason = "unknown" }
	end
	if p.achClaimed[def.id] == true then
		return { ok = false, reason = "claimed" }
	end
	if metricValue(p, def.metric) < def.goal then
		return { ok = false, reason = "locked" }
	end
	p.achClaimed[def.id] = true
	return { ok = true, chips = def.chips, xp = def.xp, id = def.id }
end

-- Wie viele Erfolge sind gerade abholbereit (erreicht, aber nicht abgeholt)?
function Achievements.claimableCount(p)
	local n = 0
	for _, a in Achievements.view(p) do
		if a.unlocked and not a.claimed then
			n += 1
		end
	end
	return n
end

return Achievements
