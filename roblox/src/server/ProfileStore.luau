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
	-- Neues/aufgefuelltes Profil gleich sichern.
	ProfileStore.save(userId)
	return p
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
end

-- Beim Server-Shutdown alle offenen Profile sichern (BindToClose).
function ProfileStore.flushAll()
	for userId in cache do
		ProfileStore.save(userId)
	end
end

return ProfileStore
