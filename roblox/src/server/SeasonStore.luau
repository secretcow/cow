--!nonstrict
-- OrderedDataStore-Anbindung fuer die globale Saison-Bestenliste. Pendant zu
-- ProfileStore, aber fuer die Rangliste: schreibt die Saison-Punkte je Spieler in
-- einen pro Saison eigenen OrderedDataStore und liefert die Top-N (gecacht).
-- Die reine Saison-Logik (Zeit/Punkte/Belohnung) liegt in Shared.Season.
--
-- Robust: Ohne DataStore-API (Studio ohne API-Zugriff, Ausfall) faellt alles auf
-- einen In-Memory-Speicher zurueck — die Bestenliste funktioniert dann lokal weiter.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Season = require(Shared:WaitForChild("Season"))

local SeasonStore = {}

local STORE_PREFIX = "KuhPokerSeason_v1_"
local TOP_N = 10
local CACHE_TTL = 30 -- Sek.: Bestenliste hoechstens alle 30 s neu laden (Limit-schonend)
local MAX_RETRIES = 3

-- In-Memory-Fallback: [seasonIdx] = { [userIdStr] = points }
local memScores = {}
-- Namens-Cache (userIdStr -> name), schont GetNameFromUserIdAsync.
local nameCache = {}
-- Bestenlisten-Cache: { idx, time, list } — vermeidet wiederholte GetSortedAsync.
local topCache = nil

-- Pro Saison ein OrderedDataStore (Name enthaelt den Saison-Index). nil bei Fehler.
local function storeFor(idx)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_PREFIX .. tostring(idx))
	end)
	if ok then
		return store
	end
	return nil
end

local function retry(fn)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		task.wait(0.2 * attempt)
	end
	return false, lastErr
end

local function rememberName(userId, name)
	if type(name) == "string" and name ~= "" then
		nameCache[tostring(userId)] = name
	end
end

-- Spielername zu einer UserId (Cache -> Roblox-API -> Fallback "Spieler").
local function resolveName(userId)
	local key = tostring(userId)
	if nameCache[key] then
		return nameCache[key]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(tonumber(userId) or -1)
	end)
	if ok and type(name) == "string" and name ~= "" then
		nameCache[key] = name
		return name
	end
	return "Spieler"
end

-- Schreibt die aktuelle Saison-Punktzahl eines Spielers in die Bestenliste der
-- aktuellen Saison. Bot-/Gast-Ids (nicht-positive UserId) werden ignoriert (nicht
-- gerankt). Gibt true zurueck, wenn persistiert (sonst nur In-Memory).
function SeasonStore.submit(userId, name, points)
	local num = tonumber(userId)
	if not num or num <= 0 then
		return false -- keine echte UserId (z. B. Bot) -> nicht ranken
	end
	points = math.max(0, math.floor(tonumber(points) or 0))
	rememberName(userId, name)
	local idx = Season.indexFor()
	-- In-Memory immer aktualisieren (Fallback + sofort sichtbar in Studio).
	memScores[idx] = memScores[idx] or {}
	memScores[idx][tostring(num)] = points
	-- Cache invalidieren, damit der naechste top() den neuen Stand sieht.
	if topCache and topCache.idx == idx then
		topCache = nil
	end
	local store = storeFor(idx)
	if not store then
		return false
	end
	local ok = retry(function()
		store:SetAsync(tostring(num), points)
	end)
	return ok
end

-- Top-N der aktuellen Saison (gecacht mit TTL). Liste: { {rank, userId, name, points} }.
-- Faellt bei fehlender DataStore-API auf den In-Memory-Speicher zurueck.
function SeasonStore.top(now)
	local idx = Season.indexFor(now)
	if topCache and topCache.idx == idx and (os.clock() - topCache.time) < CACHE_TTL then
		return topCache.list
	end
	local list = {}
	local fetched = false
	local store = storeFor(idx)
	if store then
		local ok, pages = retry(function()
			return store:GetSortedAsync(false, TOP_N)
		end)
		if ok and pages then
			local okPage, entries = pcall(function()
				return pages:GetCurrentPage()
			end)
			if okPage and type(entries) == "table" then
				for _, e in entries do
					list[#list + 1] = { userId = e.key, points = e.value }
				end
				fetched = true
			end
		end
	end
	if not fetched then
		-- Fallback: aus dem In-Memory-Speicher sortieren.
		local scores = memScores[idx] or {}
		for uid, pts in scores do
			list[#list + 1] = { userId = uid, points = pts }
		end
		table.sort(list, function(a, b)
			return a.points > b.points
		end)
		while #list > TOP_N do
			table.remove(list)
		end
	end
	-- Raenge + Namen anreichern.
	for rank, entry in list do
		entry.rank = rank
		entry.name = resolveName(entry.userId)
	end
	topCache = { idx = idx, time = os.clock(), list = list }
	return list
end

return SeasonStore
