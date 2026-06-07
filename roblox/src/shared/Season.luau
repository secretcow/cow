--!nonstrict
-- Reine Saison-Logik fuer KuhPoker (woechentliches Leaderboard). Keine Roblox-API
-- — daher standalone via luau-CLI testbar. Die OrderedDataStore-Anbindung (globale
-- Bestenliste) liegt getrennt in server/SeasonStore.luau; hier nur die Zeit-,
-- Punkte- und Belohnungs-Logik auf einem Profil.
--
-- Idee (Wettbewerbs-/Retention-Hebel): Spieler sammeln waehrend einer Saison (eine
-- Woche, UTC, an Montagen ausgerichtet) Saison-Punkte durch Spielerfolge. Diese
-- Punkte fuettern eine globale Bestenliste. Am Saison-Ende setzt der Stand zurueck;
-- wer genug Punkte erreicht hat, bekommt eine (Spass-Chip-/XP-)Belohnung.
--
-- Reine Spass-Chips/XP — kein Echtgeldwert, kein Gluecksspiel, kein Pay-to-Win.

local Season = {}

-- Saison-Laenge: 1 Woche. EPOCH = Montag, 2026-06-01 00:00 UTC (hier beginnt
-- Saison #1). Auf Wochengrenzen ausgerichtet, damit Saisons sauber am Montag wechseln.
Season.EPOCH = 1780272000
Season.LENGTH = 7 * 86400 -- Sekunden pro Saison (1 Woche)

-- Saison-Punkte je gemeldeter Metrik (siehe Server/recordResults):
Season.POINTS = {
	handWin = 1, -- eine Hand gewonnen
	bigPot = 2, -- einen grossen Pot gewonnen (>= Quests.BIG_POT)
	matchWin = 8, -- ein ganzes Match gewonnen
}

-- Belohnungsstufen nach Saison-Endpunktzahl (absteigend). Wer die Mindestpunkte
-- erreicht, bekommt beim Saison-Wechsel die jeweilige Belohnung (einmalig).
Season.REWARDS = {
	{ tier = 4, minPoints = 160, chips = 6000, xp = 350, name = "Champion", nameEn = "Champion" },
	{ tier = 3, minPoints = 80, chips = 3000, xp = 180, name = "Diamant", nameEn = "Diamond" },
	{ tier = 2, minPoints = 40, chips = 1500, xp = 90, name = "Gold", nameEn = "Gold" },
	{ tier = 1, minPoints = 15, chips = 600, xp = 40, name = "Silber", nameEn = "Silver" },
}

local function toInt(v, default)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return default
	end
	return math.floor(n)
end

local function nowOr(now)
	return tonumber(now) or os.time()
end

-- Saison-Index (0-basiert; vor EPOCH negativ) aus einem Zeitstempel. `now` injizierbar.
function Season.indexFor(now)
	return math.floor((nowOr(now) - Season.EPOCH) / Season.LENGTH)
end

-- Anzeige-Nummer der Saison (Saison #1 = erste Woche ab EPOCH).
function Season.number(now)
	return Season.indexFor(now) + 1
end

-- Start-/Endzeit (Sekunden) einer Saison. Ende ist exklusiv (= Start der naechsten).
function Season.startTime(idx)
	return Season.EPOCH + toInt(idx, 0) * Season.LENGTH
end
function Season.endTime(idx)
	return Season.startTime(idx) + Season.LENGTH
end

-- Verbleibende Sekunden bis zum Saison-Ende (>= 0).
function Season.secondsLeft(now)
	now = nowOr(now)
	return math.max(0, Season.endTime(Season.indexFor(now)) - now)
end

-- Punkte fuer eine Metrik (0, falls unbekannt).
function Season.pointsFor(metric)
	return Season.POINTS[metric] or 0
end

-- Belohnung fuer eine End-Punktzahl (hoechste erreichte Stufe) oder nil.
function Season.rewardForPoints(points)
	points = toInt(points, 0)
	for _, r in Season.REWARDS do
		if points >= r.minPoints then
			return {
				tier = r.tier,
				chips = r.chips,
				xp = r.xp,
				name = r.name,
				nameEn = r.nameEn,
				minPoints = r.minPoints,
			}
		end
	end
	return nil
end

-- Stellt sicher, dass das Profil zur aktuellen Saison gehoert. Bei Saison-Wechsel:
-- berechnet die Belohnung fuer die Punkte der ABGELAUFENEN Saison (oder nil) und
-- setzt die Punkte zurueck. Mutiert das Profil. Gibt die Belohnung (oder nil) zurueck.
function Season.rollover(p, now)
	local cur = Season.indexFor(now)
	local prev = toInt(p.seasonIndex, -1)
	p.seasonPoints = math.max(0, toInt(p.seasonPoints, 0))
	if prev == cur then
		return nil
	end
	local reward = nil
	-- prev >= 0: es gab eine echte vorige Saison mit evtl. gesammelten Punkten.
	-- prev < 0 (frisches Profil ohne Saison): nur uebernehmen, keine Belohnung.
	if prev >= 0 then
		reward = Season.rewardForPoints(p.seasonPoints)
	end
	p.seasonIndex = cur
	p.seasonPoints = 0
	return reward
end

-- Erhoeht die Saison-Punkte um den Wert der Metrik (nach vorheriger rollover-Sync).
-- Gibt die hinzugefuegten Punkte zurueck.
function Season.addPoints(p, metric)
	local add = math.max(0, Season.pointsFor(metric))
	p.seasonPoints = math.max(0, toInt(p.seasonPoints, 0)) + add
	return add
end

-- Anzeige-Sicht der Saison (fuer den Client): Nummer, Restzeit, eigene Punkte.
-- Eigene Punkte zaehlen nur, wenn sie zur aktuellen Saison gehoeren (sonst 0).
function Season.view(p, now)
	p = p or {}
	local idx = Season.indexFor(now)
	local pts = (toInt(p.seasonIndex, -1) == idx) and math.max(0, toInt(p.seasonPoints, 0)) or 0
	return {
		number = idx + 1,
		secondsLeft = Season.secondsLeft(now),
		points = pts,
	}
end

return Season
