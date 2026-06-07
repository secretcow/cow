--!nonstrict
-- Reine Progressions- & Kosmetik-Logik fuer KuhPoker. Keine Roblox-API (auch
-- kein Color3 — Farben als {r,g,b}-Tripel), daher standalone via luau-CLI testbar.
--
-- Zwei Bausteine:
--   1) XP/Level: Spieler sammeln XP (Hand-/Match-Gewinne). Das Level ergibt sich
--      rein aus der XP-Summe (Formel unten) — nichts Spielentscheidendes.
--   2) Kosmetik: freischaltbare Kartenrueckseiten, Tisch-Themen und Avatar-Rahmen.
--      Freigeschaltet allein ueber das Level (kein Pay-to-Win, kein Gluecksspiel).
--      Reiner Look — beeinflusst das Spiel NICHT.

local Progression = {}

-- ---- XP / Level ----
Progression.BASE_XP = 100 -- XP fuer Level 1 -> 2
Progression.STEP_XP = 50 -- Zusatz-XP pro weiterem Level
Progression.MAX_LEVEL = 50

-- XP-Belohnungen (werden vom Server vergeben).
Progression.XP_HAND_WIN = 15
Progression.XP_MATCH_WIN = 120

-- Benoetigte XP, um von `level` auf `level+1` zu steigen.
local function stepFor(level)
	return Progression.BASE_XP + (level - 1) * Progression.STEP_XP
end

-- Kumulative XP, um `level` zu ERREICHEN (Level 1 = 0).
function Progression.xpForLevel(level)
	level = math.max(1, math.floor(level))
	local acc = 0
	for k = 1, level - 1 do
		acc += stepFor(k)
	end
	return acc
end

-- Level aus der XP-Summe (gedeckelt bei MAX_LEVEL).
function Progression.levelFromXp(xp)
	xp = math.max(0, tonumber(xp) or 0)
	local level = 1
	local acc = 0
	while level < Progression.MAX_LEVEL do
		local need = stepFor(level)
		if xp >= acc + need then
			acc += need
			level += 1
		else
			break
		end
	end
	return level
end

-- Detaillierter Fortschritt fuer die Anzeige (Level, XP im Level, bis zum naechsten).
function Progression.progress(xp)
	xp = math.max(0, tonumber(xp) or 0)
	local level = Progression.levelFromXp(xp)
	local base = Progression.xpForLevel(level)
	local need = if level < Progression.MAX_LEVEL then stepFor(level) else 0
	local inLevel = xp - base
	local pct = if need > 0 then math.clamp(inLevel / need, 0, 1) else 1
	return {
		xp = xp,
		level = level,
		xpInLevel = inLevel,
		xpToNext = need,
		pct = pct,
		max = level >= Progression.MAX_LEVEL,
	}
end

-- ---- Kosmetik-Kataloge (Farben als {r,g,b}) ----
-- level = ab welchem Level freigeschaltet. "default" ist immer (Level 1) frei.
Progression.CARD_BACKS = {
	{ id = "default", name = "Standard", nameEn = "Classic", level = 1, color = { 54, 70, 110 } },
	{ id = "crimson", name = "Karmin", nameEn = "Crimson", level = 2, color = { 120, 40, 55 } },
	{ id = "forest", name = "Wald", nameEn = "Forest", level = 4, color = { 30, 80, 55 } },
	{ id = "gold", name = "Gold", nameEn = "Gold", level = 7, color = { 150, 120, 40 } },
	{ id = "violet", name = "Violett", nameEn = "Violet", level = 10, color = { 90, 55, 140 } },
	{ id = "midnight", name = "Mitternacht", nameEn = "Midnight", level = 15, color = { 20, 26, 52 } },
	-- VIP-exklusiv: nicht ueber Level, sondern ueber den VIP-Pass freigeschaltet.
	{ id = "vip_royal", name = "VIP Royal", nameEn = "VIP Royal", level = 0, vip = true, color = { 90, 30, 120 } },
}

Progression.TABLE_THEMES = {
	{ id = "default", name = "Grün", nameEn = "Green", level = 1, color = { 22, 70, 52 } },
	{ id = "blue", name = "Blau", nameEn = "Blue", level = 3, color = { 26, 52, 86 } },
	{ id = "ruby", name = "Rubin", nameEn = "Ruby", level = 6, color = { 80, 28, 40 } },
	{ id = "charcoal", name = "Anthrazit", nameEn = "Charcoal", level = 9, color = { 38, 42, 50 } },
	{ id = "purple", name = "Purpur", nameEn = "Purple", level = 13, color = { 54, 36, 82 } },
}

Progression.AVATAR_FRAMES = {
	{ id = "default", name = "Keiner", nameEn = "None", level = 1, color = { 70, 80, 96 } },
	{ id = "bronze", name = "Bronze", nameEn = "Bronze", level = 2, color = { 170, 110, 60 } },
	{ id = "silver", name = "Silber", nameEn = "Silver", level = 5, color = { 180, 190, 200 } },
	{ id = "gold", name = "Gold", nameEn = "Gold", level = 8, color = { 220, 180, 70 } },
	{ id = "diamond", name = "Diamant", nameEn = "Diamond", level = 12, color = { 120, 210, 230 } },
	-- VIP-exklusiv (per VIP-Pass freigeschaltet, nicht ueber das Level).
	{ id = "vip_crown", name = "VIP Krone", nameEn = "VIP Crown", level = 0, vip = true, color = { 240, 205, 80 } },
}

local CATALOGS = {
	cardBack = Progression.CARD_BACKS,
	tableTheme = Progression.TABLE_THEMES,
	avatarFrame = Progression.AVATAR_FRAMES,
}

-- Gibt die Liste einer Kategorie ("cardBack" | "tableTheme" | "avatarFrame").
function Progression.catalog(category)
	return CATALOGS[category]
end

-- Findet ein Kosmetik-Item per Kategorie + id (oder nil).
function Progression.find(category, id)
	local list = CATALOGS[category]
	if not list then
		return nil
	end
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Standard-id einer Kategorie (immer freigeschaltet).
function Progression.defaultId(category)
	local list = CATALOGS[category]
	return (list and list[1] and list[1].id) or "default"
end

-- Ist das Item freigeschaltet? VIP-Items brauchen `isVip`, alle anderen das
-- noetige Level. `isVip` ist optional (Default false) — rueckwaertskompatibel.
function Progression.isUnlocked(level, category, id, isVip)
	local item = Progression.find(category, id)
	if not item then
		return false
	end
	if item.vip then
		return isVip == true
	end
	return (tonumber(level) or 1) >= item.level
end

-- Farbe eines Items (Fallback: Standard der Kategorie), als {r,g,b}.
function Progression.colorOf(category, id)
	local item = Progression.find(category, id) or Progression.find(category, Progression.defaultId(category))
	return item and item.color or { 255, 255, 255 }
end

return Progression
