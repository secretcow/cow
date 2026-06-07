--!nonstrict
-- Reine Profil-Logik fuer KuhPoker (Roblox). Keine Roblox-API — daher standalone
-- via luau-CLI testbar. Spiegelt src/store.js (Wallet + Statistiken):
--   wallet, matchesWon, handsWon, biggestPot.
-- Der DataStore-Teil (Laden/Speichern) liegt getrennt in server/ProfileStore.luau,
-- damit diese Logik testbar bleibt.

local Profile = {}

Profile.STARTING_WALLET = 10000 -- Startguthaben fuer neue Spieler (Spass-Chips)
Profile.REFILL_TO = 1000 -- Auffuellbetrag, falls das Wallet leer ist

-- Taeglicher Login-Bonus (reiner Spass-Chip-Bonus, kein Echtgeldwert).
Profile.DAILY_BASE = 500 -- Grundbonus am Tag 1
Profile.DAILY_STEP = 250 -- Aufschlag je Streak-Tag
Profile.DAILY_MAX_STREAK = 7 -- ab hier kein weiterer Aufschlag

local function toInt(v, default)
	local n = tonumber(v)
	if n == nil or n ~= n then -- nil oder NaN
		return default
	end
	return math.floor(n)
end

-- Neues Standard-Profil fuer eine UserId.
function Profile.default(userId, name)
	return {
		userId = tostring(userId or ""),
		name = name or "Spieler",
		wallet = Profile.STARTING_WALLET,
		matchesWon = 0,
		handsWon = 0,
		biggestPot = 0,
		createdAt = os.time(),
		lastDailyDay = 0, -- Tagesindex des letzten beanspruchten Bonus
		dailyStreak = 0, -- aktuelle Login-Serie
	}
end

-- Bereinigt/ergaenzt ein (evtl. aus dem DataStore geladenes) rohes Profil zu
-- einem vollstaendigen, gueltigen Profil. Robust gegen fehlende/fehlerhafte Felder.
function Profile.sanitize(raw, userId, name)
	if type(raw) ~= "table" then
		return Profile.default(userId, name)
	end
	local p = {
		userId = tostring(userId or raw.userId or ""),
		name = (type(raw.name) == "string" and raw.name) or name or "Spieler",
		wallet = math.max(0, toInt(raw.wallet, Profile.STARTING_WALLET)),
		matchesWon = math.max(0, toInt(raw.matchesWon, 0)),
		handsWon = math.max(0, toInt(raw.handsWon, 0)),
		biggestPot = math.max(0, toInt(raw.biggestPot, 0)),
		createdAt = toInt(raw.createdAt, os.time()),
		lastDailyDay = math.max(0, toInt(raw.lastDailyDay, 0)),
		dailyStreak = math.max(0, toInt(raw.dailyStreak, 0)),
	}
	if name and name ~= "" then
		p.name = name
	end
	return p
end

-- Fuellt ein leeres Wallet auf ein Grundguthaben auf (verhindert Aussperren).
-- Nur beim Laden anwenden, nicht bei gezielten Abbuchungen.
function Profile.refillIfBroke(p)
	if not (p.wallet and p.wallet > 0) then
		p.wallet = Profile.REFILL_TO
	end
	return p
end

-- Veraendert das Wallet um delta (Buy-in negativ, Cash-out positiv). Clamp >= 0.
function Profile.adjustWallet(p, delta)
	p.wallet = math.max(0, math.floor((p.wallet or 0) + (tonumber(delta) or 0) + 0.5))
	return p
end

function Profile.recordMatchWin(p)
	p.matchesWon = (p.matchesWon or 0) + 1
	return p
end

function Profile.recordHandWin(p, potSize)
	p.handsWon = (p.handsWon or 0) + 1
	local pot = toInt(potSize, 0)
	if pot > (p.biggestPot or 0) then
		p.biggestPot = pot
	end
	return p
end

-- Taeglicher Login-Bonus. `now` (Sekunden) ist injizierbar fuer Tests.
-- Vergibt einmal pro Kalendertag (UTC). Aufeinanderfolgende Tage erhoehen die
-- Streak (und damit den Bonus); eine Luecke setzt die Streak zurueck.
-- Gibt { granted, amount, streak } zurueck.
function Profile.claimDailyBonus(p, now)
	now = tonumber(now) or os.time()
	local day = math.floor(now / 86400)
	local last = toInt(p.lastDailyDay, 0)
	-- Schon heute (oder spaeter) beansprucht? -> nichts.
	if last ~= 0 and day <= last then
		return { granted = false, amount = 0, streak = toInt(p.dailyStreak, 0) }
	end
	local streak
	if last ~= 0 and day == last + 1 then
		streak = toInt(p.dailyStreak, 0) + 1
	else
		streak = 1
	end
	local effective = math.min(streak, Profile.DAILY_MAX_STREAK)
	local amount = Profile.DAILY_BASE + (effective - 1) * Profile.DAILY_STEP
	p.wallet = math.max(0, toInt(p.wallet, 0)) + amount
	p.lastDailyDay = day
	p.dailyStreak = streak
	return { granted = true, amount = amount, streak = streak }
end

-- Schlanke Sicht fuer Anzeige/Leaderboard (ohne interne Felder).
function Profile.publicView(p)
	return {
		name = p.name or "Spieler",
		wallet = p.wallet or 0,
		matchesWon = p.matchesWon or 0,
		handsWon = p.handsWon or 0,
		biggestPot = p.biggestPot or 0,
	}
end

return Profile
