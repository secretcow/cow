--!nonstrict
-- DataStore-Persistenz fuer KuhPoker-Profile (Wallet + Statistiken).
-- Pendant zu src/store.js: laedt/speichert je UserId. Reine Profil-Logik liegt
-- in Shared.Profile (testbar); hier nur die Roblox-DataStore-Anbindung.
--
-- Robust: Schlaegt der DataStore fehl (Studio ohne API-Zugriff, Ausfall), laeuft
-- alles rein im Speicher weiter — das Spiel bleibt spielbar, nur nicht persistent.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared:WaitForChild("Profile"))
local Quests = require(Shared:WaitForChild("Quests"))

local ProfileStore = {}

local STORE_NAME = "KuhPokerProfiles_v1"
local MAX_RETRIES = 3

local ok, store = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
if not ok then
	store = nil
	warn("[ProfileStore] DataStore nicht verfuegbar — laufe rein im Speicher.")
end

-- Session-Cache: [userId] = profile. Autoritativ, solange der Spieler online ist.
local cache = {}
-- Beim Laden vergebener Tagesbonus, bis ihn der Server an den Client meldet.
local pendingBonus = {}

local function keyOf(userId)
	return "p_" .. tostring(userId)
end

-- pcall + einfache Wiederholung fuer DataStore-Zugriffe.
local function retry(fn)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local success, result = pcall(fn)
		if success then
			return true, result
		end
		lastErr = result
		task.wait(0.2 * attempt)
	end
	return false, lastErr
end

-- Persistiert das gecachte Profil eines Spielers (UpdateAsync = mehrserver-sicher).
function ProfileStore.save(userId)
	local p = cache[userId]
	if not p or not store then
		return false
	end
	local success, err = retry(function()
		store:UpdateAsync(keyOf(userId), function()
			-- Der lokale Cache ist autoritativ (Spieler ist nur auf einem Server).
			return {
				userId = p.userId,
				name = p.name,
				wallet = p.wallet,
				matchesWon = p.matchesWon,
				handsWon = p.handsWon,
				biggestPot = p.biggestPot,
				createdAt = p.createdAt,
				lastDailyDay = p.lastDailyDay,
				dailyStreak = p.dailyStreak,
				tutorialDone = p.tutorialDone,
					xp = p.xp,
					cardBack = p.cardBack,
					tableTheme = p.tableTheme,
					avatarFrame = p.avatarFrame,
					questDay = p.questDay,
					questProgress = p.questProgress,
					questClaimed = p.questClaimed,
			}
		end)
	end)
	if not success then
		warn("[ProfileStore] save fehlgeschlagen fuer " .. tostring(userId) .. ": " .. tostring(err))
	end
	return success
end

-- Laedt (oder erzeugt) das Profil. Cached es und fuellt ein leeres Wallet auf.
function ProfileStore.load(userId, name)
	if cache[userId] then
		if name and name ~= "" then
			cache[userId].name = name
		end
		return cache[userId]
	end
	local raw = nil
	if store then
		local success, result = retry(function()
			return store:GetAsync(keyOf(userId))
		end)
		if success then
			raw = result
		else
			warn("[ProfileStore] load fehlgeschlagen fuer " .. tostring(userId) .. ", nutze Default.")
		end
	end
	local p = Profile.sanitize(raw, userId, name)
	Profile.refillIfBroke(p)
	cache[userId] = p
	-- Neues/aufgefuelltes Profil gleich sichern. (Der Tagesbonus wird separat
	-- ueber grantDailyBonus vergeben — erst nachdem der VIP-Status feststeht,
	-- damit der VIP-Multiplikator korrekt greift.)
	ProfileStore.save(userId)
	return p
end

-- Vergibt den taeglichen Login-Bonus (einmal pro Kalendertag). `multiplier`
-- skaliert den Betrag (VIP x2). Legt den Bonus zum Abholen ab und persistiert.
function ProfileStore.grantDailyBonus(userId, multiplier)
	local p = cache[userId]
	if not p then
		return nil
	end
	local bonus = Profile.claimDailyBonus(p, nil, multiplier)
	if bonus.granted then
		pendingBonus[userId] = bonus
		ProfileStore.save(userId)
	end
	return bonus
end

-- Setzt das (Laufzeit-)VIP-Flag aus dem Game-Pass-Besitz. Nicht persistiert —
-- wird pro Sitzung neu aus MarketplaceService abgeleitet.
function ProfileStore.setVip(userId, isVip, name)
	local p = ProfileStore.load(userId, name)
	Profile.setVip(p, isVip)
	return p
end

-- Schreibt gekaufte Chips gut (Developer-Product-Kauf). Write-through, da ein
-- Kauf nie verloren gehen darf.
function ProfileStore.addChips(userId, amount, name)
	local p = ProfileStore.load(userId, name)
	Profile.adjustWallet(p, math.max(0, math.floor(tonumber(amount) or 0)))
	ProfileStore.save(userId)
	return p
end

-- Liefert (und verbraucht) den beim Laden vergebenen Tagesbonus, oder nil.
function ProfileStore.consumeDailyBonus(userId)
	local b = pendingBonus[userId]
	pendingBonus[userId] = nil
	return b
end

-- Liefert das gecachte Profil (muss vorher geladen sein) oder nil.
function ProfileStore.get(userId)
	return cache[userId]
end

-- ---- Mutatoren: aendern den Cache und persistieren write-through ----

function ProfileStore.adjustWallet(userId, delta, name)
	local p = ProfileStore.load(userId, name)
	Profile.adjustWallet(p, delta)
	ProfileStore.save(userId)
	return p
end

function ProfileStore.recordMatchWin(userId, name)
	local p = ProfileStore.load(userId, name)
	Profile.recordMatchWin(p)
	ProfileStore.save(userId)
	return p
end

-- Markiert das Einsteiger-Tutorial als gesehen und persistiert (write-through).
function ProfileStore.markTutorialDone(userId, name)
	local p = ProfileStore.load(userId, name)
	if not p.tutorialDone then
		Profile.markTutorialDone(p)
		ProfileStore.save(userId)
	end
	return p
end

-- Vergibt XP. `persist` steuert das Schreiben in den DataStore: bei haeufigen
-- Hand-Gewinnen false (nur Cache), beim Match-Gewinn true (write-through).
function ProfileStore.addXp(userId, amount, persist, name)
	local p = ProfileStore.load(userId, name)
	Profile.addXp(p, amount)
	if persist then
		ProfileStore.save(userId)
	end
	return p
end

-- Setzt ein ausgewaehltes Kosmetik-Item und persistiert (write-through).
-- Die Freischalt-Pruefung (per Level) erfolgt im Aufrufer (GameServer).
function ProfileStore.setCosmetic(userId, category, id, name)
	local p = ProfileStore.load(userId, name)
	Profile.setCosmetic(p, category, id)
	ProfileStore.save(userId)
	return p
end

-- Meldet ein Quest-Ereignis (Metrik). Wie Hand-Gewinne haeufig -> nur Cache
-- mutieren, NICHT bei jedem Event persistieren (schont DataStore-Limits;
-- gesichert wird ohnehin beim Match-Ende/Abholen/Verlassen). Gibt die Liste der
-- dadurch gerade abgeschlossenen Quests zurueck.
function ProfileStore.recordQuestEvent(userId, metric, amount, name)
	local p = ProfileStore.load(userId, name)
	return Quests.recordEvent(p, metric, amount)
end

-- Holt die Belohnung einer abgeschlossenen Quest ab. Schreibt Chips + XP gut und
-- persistiert write-through (eine Belohnung darf nie verloren gehen). Gibt das
-- Ergebnis (Quests.claim) und das aktualisierte Profil zurueck.
function ProfileStore.claimQuest(userId, questId, name)
	local p = ProfileStore.load(userId, name)
	local res = Quests.claim(p, questId)
	if res.ok then
		Profile.adjustWallet(p, res.chips)
		Profile.addXp(p, res.xp)
		ProfileStore.save(userId)
	end
	return res, p
end

-- Hand-Gewinne sind haeufig: nur den Cache mutieren, NICHT bei jeder Hand in den
-- DataStore schreiben (schont DataStore-Limits). Persistiert wird beim Match-Ende,
-- beim Verlassen und beim Server-Shutdown.
function ProfileStore.recordHandWin(userId, name, potSize)
	local p = ProfileStore.load(userId, name)
	Profile.recordHandWin(p, potSize)
	return p
end

-- Beim Verlassen: speichern und aus dem Cache entfernen.
function ProfileStore.release(userId)
	ProfileStore.save(userId)
	cache[userId] = nil
	pendingBonus[userId] = nil
end

-- Beim Server-Shutdown alle offenen Profile sichern (BindToClose).
function ProfileStore.flushAll()
	for userId in cache do
		ProfileStore.save(userId)
	end
end

return ProfileStore
