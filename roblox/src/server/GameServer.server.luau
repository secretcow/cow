--!nonstrict
-- KuhPoker — autoritativer Roblox-Server (Startgeruest).
-- Adaptiert die portierte Engine + RoomManager (ReplicatedStorage.Shared.*) auf
-- Roblox-RemoteEvents. Ersetzt die Socket.IO-Schicht aus server.js:
--   client emit('action')      -> ActionEvent:FireServer(type, amount)
--   server emit('state', view) -> StateEvent:FireClient(player, view)
--
-- Modell: EIN Raum pro Server (Code-Mechanik liegt im RoomManager, lobby-/
-- mehrtisch-faehig — die Code-Eingabe-UamI folgt spaeter). Vor Spielstart wird
-- eine schlanke Lobby-Sicht gesendet, damit Sitze + Start-Button erscheinen.
-- autoRunout = true (synchroner All-In-Run-out), keine Persistenz (folgt).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoomManager = require(Shared:WaitForChild("RoomManager"))

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
local rm = RoomManager.new()
local roomCode = nil -- Code des einzigen Raums dieses Servers

local function idOf(player: Player): string
	return tostring(player.UserId)
end

local function playerById(id: string): Player?
	return Players:GetPlayerByUserId(tonumber(id) or -1)
end

-- Schlanke Lobby-Sicht (vor Spielstart) im gleichen Schema wie Table:view().
local function lobbyView(room, id)
	local players = {}
	local meIdx = 1
	for i, p in room.players do
		if p.id == id then
			meIdx = i
		end
		table.insert(players, {
			id = p.id,
			name = p.name,
			stack = room.settings.startingStack,
			bet = 0,
			committed = 0,
			folded = false,
			allIn = false,
			inHand = false,
			out = false,
			isButton = false,
			isSB = false,
			isBB = false,
			isMe = p.id == id,
			seat = i,
			hole = {},
		})
	end
	return {
		handNo = 0,
		stage = "idle",
		flush = room.settings.flush,
		cash = room.settings.cash,
		buyIn = if room.settings.cash then room.settings.startingStack else nil,
		myStack = room.settings.startingStack,
		betweenHands = true,
		community = {},
		pot = 0,
		totalPot = 0,
		currentBet = 0,
		players = players,
		meIdx = meIdx,
		button = 0,
		toActId = nil,
		yourTurn = false,
		actions = nil,
		result = nil,
		shown = {},
		runout = false,
		equities = nil,
		myHand = nil,
		log = {},
		matchOver = false,
		matchWinnerId = nil,
		blinds = {
			sb = 10,
			bb = 20,
			tournament = room.settings.tournament,
			level = nil,
			nextLevelIn = nil,
		},
		lobby = true,
		hostId = room.hostId,
	}
end

local function broadcast()
	if not roomCode then
		return
	end
	local room = rm:getRoom(roomCode)
	if not room then
		return
	end
	for _, p in room.players do
		local plr = playerById(p.id)
		if plr then
			local view = if room.table then room.table:view(p.id) else lobbyView(room, p.id)
			StateEvent:FireClient(plr, view)
		end
	end
end

local function ensureSeated(player)
	local def = { id = idOf(player), name = player.Name }
	if not roomCode then
		local code = rm:createRoom(def, { startingStack = 1000 })
		roomCode = code
	else
		rm:joinRoom(roomCode, def) -- idempotent; ignoriert "voll"/"laeuft" stillschweigend
	end
end

-- ---- Spieler-Ereignisse ----
Players.PlayerAdded:Connect(function(player)
	ensureSeated(player)
	broadcast()
end)

Players.PlayerRemoving:Connect(function(player)
	if not roomCode then
		return
	end
	local res = rm:leaveRoom(roomCode, idOf(player))
	if res.destroyed then
		roomCode = nil
	end
	broadcast()
end)

-- ---- Aktions-Remotes ----
StartHandEvent.OnServerEvent:Connect(function(player)
	if not roomCode then
		ensureSeated(player)
	end
	local room = rm:getRoom(roomCode)
	if not room then
		return
	end
	-- Nur der Host startet (wie in der Web-Lobby).
	if room.hostId ~= idOf(player) then
		return
	end
	if not room.started then
		local res = rm:startMatch(roomCode)
		if res.error then
			return
		end
	end
	if room.table then
		room.table:startHand()
	end
	broadcast()
end)

ActionEvent.OnServerEvent:Connect(function(player, atype, amount)
	local room = roomCode and rm:getRoom(roomCode)
	if not (room and room.table) then
		return
	end
	-- Engine validiert (Zug-Reihenfolge, Betrag) und ignoriert Ungueltiges.
	room.table:act(idOf(player), atype, amount)
	broadcast()
end)

RebuyEvent.OnServerEvent:Connect(function(player, amount)
	local room = roomCode and rm:getRoom(roomCode)
	if not (room and room.table) then
		return
	end
	-- Ohne Betrag: Standard = voller Buy-in (wie in server.js).
	if type(amount) ~= "number" or amount <= 0 then
		amount = room.table.startingStack
	end
	room.table:rebuy(idOf(player), amount)
	broadcast()
end)

print("[KuhPoker] Server bereit (RoomManager + Engine, Luau-Port von server.js/poker.js).")
