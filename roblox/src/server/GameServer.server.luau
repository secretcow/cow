--!nonstrict
-- KuhPoker — autoritativer Roblox-Server (Startgeruest).
-- Adaptiert die portierte Engine (ReplicatedStorage.Shared.PokerEngine) auf
-- Roblox-RemoteEvents. Ersetzt die Socket.IO-Schicht aus server.js:
--   client emit('action')      -> ActionEvent:FireServer(type, amount)
--   server emit('state', view) -> StateEvent:FireClient(player, view)
--
-- Vereinfachungen ggü. der Web-Version (bewusst, als Ausgangspunkt):
--   * EIN globaler Tisch fuer den ganzen Place (keine Room-Codes).
--   * Beitritt/Austritt zwischen den Haenden baut den Tisch neu auf (Stacks reset).
--   * autoRunout = true (All-In wird synchron ausgespielt, kein gestaffeltes Aufdecken).
--   * Keine Persistenz/Wallet (kommt spaeter via DataStoreService oder HTTP-Backend).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PokerEngine = require(Shared:WaitForChild("PokerEngine"))

-- ---- Remotes anlegen ----
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function mkEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = Remotes
	return e
end

local StartHandEvent = mkEvent("StartHand")
local ActionEvent = mkEvent("Action")
local RebuyEvent = mkEvent("Rebuy")
local StateEvent = mkEvent("State")

-- ---- Zustand ----
local seats = {} -- { { player = Player }, ... }
local tbl = nil -- aktuelle PokerEngine.Table

local function idOf(player: Player): string
	return tostring(player.UserId)
end

local function betweenHands(): boolean
	return (not tbl) or tbl.stage == "idle" or tbl.stage == "handover"
end

local function broadcast()
	if not tbl then
		return
	end
	for _, s in seats do
		StateEvent:FireClient(s.player, tbl:view(idOf(s.player)))
	end
end

-- Baut den Tisch aus den aktuell sitzenden Spielern neu auf (nur zwischen Haenden).
local function rebuildTable()
	if #seats < 2 then
		tbl = nil
		return
	end
	local defs = {}
	for _, s in seats do
		table.insert(defs, { id = idOf(s.player), name = s.player.Name })
	end
	tbl = PokerEngine.Table.new(defs, { startingStack = 1000 })
end

-- ---- Spieler-Ereignisse ----
Players.PlayerAdded:Connect(function(player)
	table.insert(seats, { player = player })
	if betweenHands() then
		rebuildTable()
	end
	broadcast()
end)

Players.PlayerRemoving:Connect(function(player)
	for i = #seats, 1, -1 do
		if seats[i].player == player then
			table.remove(seats, i)
		end
	end
	if betweenHands() then
		rebuildTable()
	end
	broadcast()
end)

-- ---- Aktions-Remotes ----
StartHandEvent.OnServerEvent:Connect(function(_player)
	if not tbl then
		rebuildTable()
	end
	if tbl then
		tbl:startHand()
		broadcast()
	end
end)

ActionEvent.OnServerEvent:Connect(function(player, atype, amount)
	if not tbl then
		return
	end
	-- Engine validiert (Zug-Reihenfolge, Betrag) und ignoriert ungueltige Aktionen.
	tbl:act(idOf(player), atype, amount)
	broadcast()
end)

RebuyEvent.OnServerEvent:Connect(function(player, amount)
	if not tbl then
		return
	end
	tbl:rebuy(idOf(player), amount)
	broadcast()
end)

print("[KuhPoker] Server bereit. Engine-Version: Luau-Port von src/poker.js")
