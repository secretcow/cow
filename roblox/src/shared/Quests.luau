--!nonstrict
-- Reine Tagesquest-Logik fuer KuhPoker. Keine Roblox-API — daher standalone via
-- luau-CLI testbar. Der DataStore-Teil (Laden/Speichern) liegt getrennt in
-- server/ProfileStore.luau; hier nur die reine Quest-Mechanik auf einem Profil.
--
-- Idee (Retention-Hebel): Jeder Spieler bekommt pro Kalendertag (UTC) eine kleine
-- Auswahl Mini-Ziele mit Chip-/XP-Belohnung. Die Auswahl ist DETERMINISTISCH aus
-- dem Tagesindex abgeleitet (alle Spieler sehen am selben Tag dieselben Quests) —
-- es muss also NICHT gespeichert werden, WELCHE Quests aktiv sind, nur der
-- Fortschritt. Bei Tageswechsel werden Fortschritt + Abgeholt-Status zurueckgesetzt.
--
-- Reine Spass-Chips/XP — kein Echtgeldwert, kein Gluecksspiel, kein Pay-to-Win.

local Quests = {}

Quests.DAILY_COUNT = 3 -- wie viele Quests pro Tag aktiv sind
Quests.BIG_POT = 1500 -- ab dieser Pot-Groesse zaehlt ein Gewinn als "grosser Pot"

-- Metriken, die der Server meldet:
--   "handWin"    — eine Hand gewonnen
--   "handPlayed" — an einer Hand teilgenommen (egal ob gewonnen)
--   "matchWin"   — ein Match gewonnen
--   "bigPot"     — einen Pot >= BIG_POT gewonnen
Quests.POOL = {
	{ id = "win2hands", metric = "handWin", goal = 2, chips = 400, xp = 25,
		name = "Gewinne 2 Hände", nameEn = "Win 2 hands",
		desc = "Gewinne heute 2 Hände.", descEn = "Win 2 hands today." },
	{ id = "win4hands", metric = "handWin", goal = 4, chips = 800, xp = 45,
		name = "Gewinne 4 Hände", nameEn = "Win 4 hands",
		desc = "Gewinne heute 4 Hände.", descEn = "Win 4 hands today." },
	{ id = "play6hands", metric = "handPlayed", goal = 6, chips = 350, xp = 20,
		name = "Spiele 6 Hände", nameEn = "Play 6 hands",
		desc = "Nimm an 6 Händen teil.", descEn = "Take part in 6 hands." },
	{ id = "play12hands", metric = "handPlayed", goal = 12, chips = 700, xp = 40,
		name = "Spiele 12 Hände", nameEn = "Play 12 hands",
		desc = "Nimm an 12 Händen teil.", descEn = "Take part in 12 hands." },
	{ id = "winmatch", metric = "matchWin", goal = 1, chips = 1000, xp = 70,
		name = "Gewinne 1 Match", nameEn = "Win 1 match",
		desc = "Gewinne ein ganzes Match.", descEn = "Win a whole match." },
	{ id = "win2matches", metric = "matchWin", goal = 2, chips = 2000, xp = 140,
		name = "Gewinne 2 Matches", nameEn = "Win 2 matches",
		desc = "Gewinne zwei Matches.", descEn = "Win two matches." },
	{ id = "bigpot1", metric = "bigPot", goal = 1, chips = 600, xp = 35,
		name = "Großer Pot", nameEn = "Big pot",
		desc = `Gewinne einen Pot mit mindestens {Quests.BIG_POT} 🪙.`,
		descEn = `Win a pot of at least {Quests.BIG_POT} 🪙.` },
	{ id = "bigpot2", metric = "bigPot", goal = 2, chips = 1200, xp = 70,
		name = "2 große Pots", nameEn = "2 big pots",
		desc = `Gewinne 2 Pots mit je mindestens {Quests.BIG_POT} 🪙.`,
		descEn = `Win 2 pots of at least {Quests.BIG_POT} 🪙 each.` },
}

local function toInt(v, default)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return default
	end
	return math.floor(n)
end

-- Kalendertag-Index (UTC) aus einem Zeitstempel (Sekunden). `now` ist injizierbar.
function Quests.dayIndex(now)
	return math.floor((tonumber(now) or os.time()) / 86400)
end

-- Deterministische Auswahl von `count` aus `n` Indizes per Seed (Fisher-Yates mit
-- einem einfachen LCG). Gleicher Seed -> gleiche Auswahl (serverunabhaengig).
local function pickIndices(n, count, seed)
	local idx = {}
	for i = 1, n do
		idx[i] = i
	end
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function rnd()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	for i = n, 2, -1 do
		local j = math.floor(rnd() * i) + 1
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out = {}
	for i = 1, math.min(count, n) do
		out[i] = idx[i]
	end
	return out
end

-- Die fuer einen Tag aktiven Quest-Definitionen (deterministisch). `now` optional.
function Quests.dailyFor(now)
	local day = Quests.dayIndex(now)
	local picks = pickIndices(#Quests.POOL, Quests.DAILY_COUNT, day + 1)
	local out = {}
	for _, i in picks do
		out[#out + 1] = Quests.POOL[i]
	end
	return out
end

-- Setzt Fortschritt + Abgeholt-Status zurueck, wenn ein neuer Tag begonnen hat.
-- Gibt den aktuellen Tagesindex zurueck. (Mutiert das Profil.)
function Quests.ensureDay(p, now)
	local day = Quests.dayIndex(now)
	if (tonumber(p.questDay) or -1) ~= day then
		p.questDay = day
		p.questProgress = {}
		p.questClaimed = {}
	end
	if type(p.questProgress) ~= "table" then
		p.questProgress = {}
	end
	if type(p.questClaimed) ~= "table" then
		p.questClaimed = {}
	end
	return day
end

-- Meldet ein Spiel-Ereignis (Metrik). Erhoeht den Fortschritt aller heute aktiven
-- Quests dieser Metrik (gedeckelt aufs Ziel), ausser bereits abgeholten. Gibt die
-- Liste der dadurch GERADE abgeschlossenen Quest-Definitionen zurueck (fuer Hinweise).
function Quests.recordEvent(p, metric, amount, now)
	Quests.ensureDay(p, now)
	amount = math.max(1, toInt(amount, 1))
	local completed = {}
	for _, def in Quests.dailyFor(now) do
		if def.metric == metric and p.questClaimed[def.id] ~= true then
			local cur = toInt(p.questProgress[def.id], 0)
			if cur < def.goal then
				local nv = math.min(def.goal, cur + amount)
				p.questProgress[def.id] = nv
				if nv >= def.goal then
					completed[#completed + 1] = def
				end
			end
		end
	end
	return completed
end

-- Holt die Belohnung einer abgeschlossenen Quest ab. Mutiert NICHT das Wallet/XP —
-- das macht der Aufrufer (Server/ProfileStore), damit die Quest-Logik rein bleibt.
-- Markiert die Quest als abgeholt. Gibt { ok, chips, xp, id } bzw. { ok=false, reason }.
function Quests.claim(p, questId, now)
	Quests.ensureDay(p, now)
	for _, def in Quests.dailyFor(now) do
		if def.id == questId then
			if p.questClaimed[def.id] == true then
				return { ok = false, reason = "claimed" }
			end
			local cur = toInt(p.questProgress[def.id], 0)
			if cur < def.goal then
				return { ok = false, reason = "incomplete" }
			end
			p.questClaimed[def.id] = true
			return { ok = true, chips = def.chips, xp = def.xp, id = def.id }
		end
	end
	return { ok = false, reason = "unknown" }
end

-- Anzeige-Sicht fuer den Client: Liste der heutigen Quests mit Fortschritt/Status.
-- Read-only (mutiert das Profil NICHT) — Fortschritt zaehlt nur, wenn er zum
-- heutigen Tag gehoert (sonst 0), damit ein faelliger Reset nichts Altes zeigt.
function Quests.view(p, now)
	p = p or {}
	local day = Quests.dayIndex(now)
	local active = (tonumber(p.questDay) or -1) == day
	local progress = (active and type(p.questProgress) == "table") and p.questProgress or {}
	local claimed = (active and type(p.questClaimed) == "table") and p.questClaimed or {}
	local out = {}
	for _, def in Quests.dailyFor(now) do
		local prog = math.min(toInt(progress[def.id], 0), def.goal)
		out[#out + 1] = {
			id = def.id,
			name = def.name,
			nameEn = def.nameEn,
			desc = def.desc,
			descEn = def.descEn,
			metric = def.metric,
			goal = def.goal,
			progress = prog,
			done = prog >= def.goal,
			claimed = claimed[def.id] == true,
			chips = def.chips,
			xp = def.xp,
		}
	end
	return out
end

-- Wie viele Quests sind gerade abholbereit (fertig, aber nicht abgeholt)?
function Quests.claimableCount(p, now)
	local n = 0
	for _, q in Quests.view(p, now) do
		if q.done and not q.claimed then
			n += 1
		end
	end
	return n
end

return Quests
