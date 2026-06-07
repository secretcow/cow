--!nonstrict
-- KuhPoker — autoritativer Roblox-Server (vollstaendig).
-- Ersetzt die Socket.IO-Schicht aus server.js durch RemoteEvents/-Functions und
-- buendelt die komplette Online-Mechanik:
--   * Mehrtisch-Lobby (Code-basiert) ueber RoomManager
--   * Persistenz (Wallet + Statistiken) ueber ProfileStore (DataStore)
--   * Reconnect/Disconnect mit Schonfrist-Auto-Fold
--   * gestaffelter All-In-Run-out (TV-Poker-Stil) mit Equities
--   * Tisch-Chat
--
-- Remotes:
--   CreateRoom (Function)  client -> {ok, code} | {error}
--   JoinRoom   (Function)  client -> {ok, code} | {error}
--   LeaveRoom  (Event)     client
--   StartHand  (Event)     host
--   Action     (Event)     client (type, amount)
--   Rebuy      (Event)     client (amount)
--   Chat       (Event)     client (text)
--   State      (Event)     server -> client  (Lobby- ODER Tisch-Sicht)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoomManager = require(Shared:WaitForChild("RoomManager"))
local Profile = require(Shared:WaitForChild("Profile"))
-- ProfileStore liegt neben diesem Script (ServerScriptService.Server.ProfileStore).
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

-- ---- Konstanten ----
local ROOM_TTL = 120 -- Sek.: Raum lebt weiter, solange niemand verbunden ist
local RUNOUT_STEP = 1.3 -- Sek. pro Run-out-Strasse
local DISCONNECT_GRACE = 30 -- Sek. bis Auto-Fold eines getrennten Spielers
local CHAT_HISTORY = 40 -- gespeicherte Chat-Nachrichten pro Raum
-- Auto-Pilot fuer oeffentliche Quick-Play-Tische (kein Host noetig):
local AUTO_START_DELAY = 4 -- Sek. Countdown bis Spielstart (laesst weitere Spieler rein)
local HAND_DELAY = 3 -- Sek. Pause bis zur naechsten Hand
local MATCH_END_DELAY = 6 -- Sek. nach Match-Ende bis Tisch wieder oeffnet

-- ---- Remotes anlegen ----
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function mkEvent(name)
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = Remotes
	return e
end
local function mkFunction(name)
	local f = Instance.new("RemoteFunction")
	f.Name = name
	f.Parent = Remotes
	return f
end

local CreateRoomFn = mkFunction("CreateRoom")
local JoinRoomFn = mkFunction("JoinRoom")
local QuickPlayFn = mkFunction("QuickPlay")
local LeaveRoomEvent = mkEvent("LeaveRoom")
local StartHandEvent = mkEvent("StartHand")
local ActionEvent = mkEvent("Action")
local RebuyEvent = mkEvent("Rebuy")
local ChatEvent = mkEvent("Chat")
local StateEvent = mkEvent("State")

-- ---- Zustand ----
local rm = RoomManager.new()
local playerRoom = {} -- [idString] = roomCode

local function idOf(player)
	return tostring(player.UserId)
end
local function playerById(id)
	return Players:GetPlayerByUserId(tonumber(id) or -1)
end

-- ===================== Sichten =====================

-- Schlanke Wartesicht (Lobby des Raums vor Spielstart). Gleiches Schema wie
-- Table:view, damit der Client einheitlich rendern kann.
local function waitingView(room, id)
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
			connected = room.connected[p.id] == true,
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
		blinds = { sb = 10, bb = 20, tournament = room.settings.tournament, level = nil, nextLevelIn = nil },
		waiting = true,
	}
end

-- Vollstaendige Tisch-Sicht fuer einen Spieler, angereichert um Raum-Metadaten.
local function tableView(room, id)
	local v = if room.table then room.table:view(id) else waitingView(room, id)
	v.screen = "table"
	v.code = room.code
	v.hostId = room.hostId
	v.chat = room.chat
	v.youAreHost = room.hostId == id
	v.auto = room.public == true -- oeffentlicher Auto-Pilot-Tisch (kein manueller Start)
	v.canStart = (not room.table) and connectedCount(room) >= 2
	-- Verbindungsstatus je Sitz fuer die UI nachreichen.
	for _, pv in v.players do
		pv.connected = room.connected[pv.id] == true
	end
	return v
end

-- Lobby-Sicht (Spieler an keinem Tisch): nur Profil + Hinweis.
local function lobbyPayload(player)
	local id = idOf(player)
	local prof = ProfileStore.get(id) or ProfileStore.load(id, player.Name)
	return {
		screen = "lobby",
		profile = Profile.publicView(prof),
		dailyBonus = ProfileStore.consumeDailyBonus(id), -- nil oder {granted,amount,streak}
	}
end

-- ===================== Hilfen =====================

function connectedCount(room)
	local n = 0
	for _, p in room.players do
		if room.connected[p.id] then
			n += 1
		end
	end
	return n
end

local function sendLobby(player)
	StateEvent:FireClient(player, lobbyPayload(player))
end

local function broadcastRoom(room)
	for _, p in room.players do
		if room.connected[p.id] then
			local plr = playerById(p.id)
			if plr then
				StateEvent:FireClient(plr, tableView(room, p.id))
			end
		end
	end
end

-- Aktualisierte Profile (nach Match-Ende) an alle im Raum schicken.
local function pushProfiles(room)
	for _, p in room.players do
		local plr = room.connected[p.id] and playerById(p.id)
		if plr then
			local prof = ProfileStore.get(p.id)
			if prof then
				-- als zusaetzliches Lobby-Feld in der Tisch-Sicht waere unsauber;
				-- wir senden eine eigene Lobby-Payload mit aktuellem Profil.
				StateEvent:FireClient(plr, { screen = "profile", profile = Profile.publicView(prof) })
			end
		end
	end
end

-- Vorwaerts-Deklaration: wird weiter unten definiert, aber schon vom Run-out
-- und von scheduleAutoAct referenziert (laeuft erst zur Laufzeit -> Upvalue gesetzt).
local autoPilotPublic

-- ---- Statistiken verbuchen (idempotent pro Hand/Match) ----
local function recordResults(room)
	local t = room.table
	if not t then
		return
	end
	if t.stage == "handover" and t.result and t.handNo ~= room.lastHandRecorded then
		room.lastHandRecorded = t.handNo
		local pot = t.result.pot or 0
		for _, seatIdx in t.result.winners do
			local p = t.players[seatIdx]
			if p then
				ProfileStore.recordHandWin(p.id, p.name, pot)
			end
		end
	end
	if t.matchOver and not room.matchRecorded then
		room.matchRecorded = true
		if t.matchWinnerId then
			local winnerName
			for _, p in t.players do
				if p.id == t.matchWinnerId then
					winnerName = p.name
				end
			end
			ProfileStore.recordMatchWin(t.matchWinnerId, winnerName)
		end
		pushProfiles(room)
	end
end

-- ---- Run-out (gestaffeltes All-In-Aufdecken) ----
local function maybeDriveRunout(room)
	if not (room.table and room.table.runoutActive and room.table.stage ~= "handover") then
		return
	end
	if room.runoutBusy then
		return
	end
	room.runoutBusy = true
	task.spawn(function()
		while room.table and room.table.runoutActive and room.table.stage ~= "handover" do
			task.wait(RUNOUT_STEP)
			if not (rm:getRoom(room.code) and room.table) then
				break
			end
			local res = room.table:stepRunout()
			recordResults(room)
			broadcastRoom(room)
			if res and res.done then
				break
			end
		end
		room.runoutBusy = false
		-- Run-out fertig (Stage = handover): ggf. naechste Hand auf Auto-Tischen.
		autoPilotPublic(room)
	end)
end

-- ---- Auto-Fold fuer getrennte Spieler ----
local function autoActDisconnected(room)
	local t = room.table
	if not t then
		return false
	end
	local acted = false
	while t.toAct ~= nil and t.stage ~= "handover" and t.stage ~= "showdown" do
		local p = t.players[t.toAct]
		if not p or room.connected[p.id] then
			break
		end
		local a = t:view(p.id).actions
		if not a then
			break
		end
		local res = t:act(p.id, if a.canCheck then "check" else "fold")
		if res and res.error then
			break
		end
		acted = true
	end
	return acted
end

local function scheduleAutoAct(room, immediate)
	local t = room.table
	if not t or t.toAct == nil or t.stage == "handover" or t.stage == "showdown" then
		return
	end
	local p = t.players[t.toAct]
	if not p or room.connected[p.id] then
		return
	end
	room.autoActGen = (room.autoActGen or 0) + 1
	local gen = room.autoActGen
	task.delay(if immediate then 0 else DISCONNECT_GRACE, function()
		if room.autoActGen ~= gen then
			return
		end
		if not (rm:getRoom(room.code) and room.table) then
			return
		end
		if autoActDisconnected(room) then
			recordResults(room)
			broadcastRoom(room)
			maybeDriveRunout(room)
			autoPilotPublic(room)
		end
		scheduleAutoAct(room) -- naechster getrennter Spieler?
	end)
end

-- ---- Auto-Pilot fuer oeffentliche Quick-Play-Tische ----
-- Oeffentliche Tische brauchen keinen Host: bei >=2 Spielern startet das Spiel
-- automatisch, Haende laufen selbsttaetig weiter, nach Match-Ende oeffnet der
-- Tisch wieder fuer neue Spieler. Wird nach jeder relevanten Transition aufgerufen.
-- Ein einziger Generationen-Token (autoGen) macht den jeweils letzten geplanten
-- Schritt gueltig und verwirft veraltete Timer.
function autoPilotPublic(room)
	if not room.public then
		return
	end
	local t = room.table

	-- (1) Kein laufendes Match: bei genug Spielern Start einplanen.
	if not room.started then
		if connectedCount(room) >= 2 then
			room.autoGen = (room.autoGen or 0) + 1
			local gen = room.autoGen
			task.delay(AUTO_START_DELAY, function()
				if room.autoGen ~= gen or not rm:getRoom(room.code) then
					return
				end
				if room.started or connectedCount(room) < 2 then
					return
				end
				local res = rm:startMatch(room.code)
				if res.error then
					return
				end
				room.table.autoRunout = false
				room.table:startHand()
				recordResults(room)
				broadcastRoom(room)
				maybeDriveRunout(room)
				scheduleAutoAct(room)
				autoPilotPublic(room)
			end)
		end
		return
	end

	if not t then
		return
	end

	-- (2) Match vorbei: Tisch nach kurzer Pause wieder oeffnen (getrennte Sitze raeumen).
	if t.matchOver then
		room.autoGen = (room.autoGen or 0) + 1
		local gen = room.autoGen
		task.delay(MATCH_END_DELAY, function()
			if room.autoGen ~= gen or not rm:getRoom(room.code) then
				return
			end
			-- Getrennte Spieler aus dem Tisch werfen.
			for _, p in table.clone(room.players) do
				if not room.connected[p.id] then
					local r = rm:leaveRoom(room.code, p.id)
					playerRoom[p.id] = nil
					ProfileStore.release(p.id)
					if r.destroyed then
						return -- Raum ist weg
					end
					room.connected[p.id] = nil
				end
			end
			if not rm:getRoom(room.code) then
				return
			end
			rm:reopen(room.code)
			room.matchRecorded = false
			room.lastHandRecorded = nil
			broadcastRoom(room)
			autoPilotPublic(room)
		end)
		return
	end

	-- (3) Zwischen den Haenden: naechste Hand automatisch geben.
	if t.stage == "handover" then
		room.autoGen = (room.autoGen or 0) + 1
		local gen = room.autoGen
		task.delay(HAND_DELAY, function()
			if room.autoGen ~= gen or not (rm:getRoom(room.code) and room.table) then
				return
			end
			if room.table.matchOver then
				autoPilotPublic(room)
				return
			end
			room.table:startHand()
			recordResults(room)
			broadcastRoom(room)
			maybeDriveRunout(room)
			scheduleAutoAct(room)
			autoPilotPublic(room)
		end)
	end
end

-- ---- Raum-Aufraeumen (TTL, wenn niemand verbunden) ----
local function destroyRoom(room)
	for _, p in room.players do
		playerRoom[p.id] = nil
		ProfileStore.release(p.id)
	end
	rm:destroyRoom(room.code)
end

local function cancelCleanup(room)
	room.cleanupGen = (room.cleanupGen or 0) + 1
end

local function maybeScheduleCleanup(room)
	if connectedCount(room) > 0 then
		return
	end
	room.cleanupGen = (room.cleanupGen or 0) + 1
	local gen = room.cleanupGen
	task.delay(ROOM_TTL, function()
		if room.cleanupGen ~= gen then
			return
		end
		local r = rm:getRoom(room.code)
		if r and connectedCount(r) == 0 then
			destroyRoom(r)
		end
	end)
end

-- Initialisiert Laufzeitfelder eines frisch erstellten Raums (idempotent).
local function initRoomRuntime(room)
	if room._inited then
		return
	end
	room._inited = true
	room.connected = {}
	room.chat = {}
	room.matchRecorded = false
	room.lastHandRecorded = nil
end

-- ===================== Remotes verdrahten =====================

CreateRoomFn.OnServerInvoke = function(player, settings)
	local id = idOf(player)
	if playerRoom[id] then
		return { error = "Du bist bereits an einem Tisch." }
	end
	ProfileStore.load(id, player.Name)
	if type(settings) ~= "table" then
		settings = {}
	end
	local code = rm:createRoom({ id = id, name = player.Name }, {
		maxPlayers = settings.maxPlayers,
		startingStack = settings.startingStack,
		flush = settings.flush,
		cash = settings.cash,
		tournament = settings.tournament,
		levelHands = settings.levelHands,
	})
	if not code then
		return { error = "Tisch konnte nicht erstellt werden." }
	end
	local room = rm:getRoom(code)
	initRoomRuntime(room)
	room.connected[id] = true
	playerRoom[id] = code
	broadcastRoom(room)
	return { ok = true, code = code }
end

JoinRoomFn.OnServerInvoke = function(player, code)
	local id = idOf(player)
	if playerRoom[id] then
		return { error = "Du bist bereits an einem Tisch." }
	end
	code = tostring(code or ""):upper():gsub("%s+", "")
	local res = rm:joinRoom(code, { id = id, name = player.Name })
	if res.error then
		return { error = res.error }
	end
	ProfileStore.load(id, player.Name)
	local room = rm:getRoom(code)
	initRoomRuntime(room)
	room.connected[id] = true
	playerRoom[id] = code
	cancelCleanup(room)
	broadcastRoom(room)
	return { ok = true, code = code }
end

-- Quick-Play: setzt den Spieler sofort an einen offenen oeffentlichen Tisch
-- (oder erstellt einen neuen). Kein Code, kein Host noetig — Auto-Pilot startet.
QuickPlayFn.OnServerInvoke = function(player)
	local id = idOf(player)
	if playerRoom[id] then
		return { error = "Du bist bereits an einem Tisch." }
	end
	ProfileStore.load(id, player.Name)
	local code = rm:findJoinablePublic()
	if code then
		local res = rm:joinRoom(code, { id = id, name = player.Name })
		if res.error then
			code = nil -- Rennen verloren (gerade voll/gestartet) -> neuen Tisch
		end
	end
	if not code then
		code = rm:createRoom({ id = id, name = player.Name }, {
			public = true,
			cash = false,
			tournament = false,
			startingStack = 1000,
			maxPlayers = 6,
		})
	end
	if not code then
		return { error = "Kein Tisch verfuegbar." }
	end
	local room = rm:getRoom(code)
	initRoomRuntime(room)
	room.connected[id] = true
	playerRoom[id] = code
	cancelCleanup(room)
	broadcastRoom(room)
	autoPilotPublic(room)
	return { ok = true, code = code }
end

LeaveRoomEvent.OnServerEvent:Connect(function(player)
	local id = idOf(player)
	local code = playerRoom[id]
	if not code then
		return
	end
	local room = rm:getRoom(code)
	playerRoom[id] = nil
	if not room then
		sendLobby(player)
		return
	end
	if room.table then
		-- Laufendes Spiel: Sitz bleibt (gilt als getrennt), Auto-Fold uebernimmt.
		room.connected[id] = false
		scheduleAutoAct(room, true)
		maybeScheduleCleanup(room)
	else
		-- Wartephase: Sitz entfernen.
		local r = rm:leaveRoom(code, id)
		if r.destroyed then
			ProfileStore.release(id)
			sendLobby(player)
			return
		end
		room.connected[id] = nil
	end
	broadcastRoom(room)
	sendLobby(player)
end)

StartHandEvent.OnServerEvent:Connect(function(player)
	local id = idOf(player)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if not room then
		return
	end
	if room.hostId ~= id then
		return -- nur der Host startet
	end
	-- Nach Match-Ende: neues Match aufsetzen.
	if room.table and room.table.matchOver then
		room.table:resetMatch()
		room.matchRecorded = false
		room.lastHandRecorded = nil
	end
	if not room.started then
		if connectedCount(room) < 2 then
			return
		end
		local res = rm:startMatch(code)
		if res.error then
			return
		end
		room.table.autoRunout = false -- gestaffeltes Aufdecken serverseitig
	end
	if room.table then
		room.table:startHand()
	end
	recordResults(room)
	broadcastRoom(room)
	maybeDriveRunout(room)
	scheduleAutoAct(room)
end)

ActionEvent.OnServerEvent:Connect(function(player, atype, amount)
	local id = idOf(player)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if not (room and room.table) then
		return
	end
	room.table:act(id, atype, amount) -- Engine validiert; Ungueltiges ignoriert
	recordResults(room)
	broadcastRoom(room)
	maybeDriveRunout(room)
	scheduleAutoAct(room)
	autoPilotPublic(room)
end)

RebuyEvent.OnServerEvent:Connect(function(player, amount)
	local id = idOf(player)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if not (room and room.table) then
		return
	end
	if type(amount) ~= "number" or amount <= 0 then
		amount = room.table.startingStack
	end
	room.table:rebuy(id, amount)
	broadcastRoom(room)
end)

ChatEvent.OnServerEvent:Connect(function(player, text)
	local id = idOf(player)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if not room then
		return
	end
	local clean = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	clean = clean:sub(1, 160)
	if clean == "" then
		return
	end
	table.insert(room.chat, { name = player.Name, text = clean, ts = os.time() })
	while #room.chat > CHAT_HISTORY do
		table.remove(room.chat, 1)
	end
	broadcastRoom(room)
end)

-- ===================== Spieler-Ereignisse =====================

Players.PlayerAdded:Connect(function(player)
	local id = idOf(player)
	ProfileStore.load(id, player.Name)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if room then
		-- Reconnect: zurueck auf den Sitz.
		rm:joinRoom(code, { id = id, name = player.Name }) -- idempotent (rejoined)
		room.connected[id] = true
		cancelCleanup(room)
		broadcastRoom(room)
	else
		playerRoom[id] = nil
		sendLobby(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local id = idOf(player)
	ProfileStore.save(id)
	local code = playerRoom[id]
	local room = code and rm:getRoom(code)
	if not room then
		ProfileStore.release(id)
		return
	end
	room.connected[id] = false
	if room.table then
		-- Sitz bleibt fuer moeglichen Reconnect; Auto-Fold + ggf. Aufraeumen.
		scheduleAutoAct(room)
		maybeScheduleCleanup(room)
		broadcastRoom(room)
	else
		-- Wartephase: Sitz entfernen.
		local r = rm:leaveRoom(code, id)
		playerRoom[id] = nil
		if r.destroyed then
			ProfileStore.release(id)
		else
			room.connected[id] = nil
			broadcastRoom(room)
		end
	end
end)

-- Beim Server-Shutdown alle Profile sichern.
game:BindToClose(function()
	ProfileStore.flushAll()
	task.wait(1)
end)

print("[KuhPoker] Server bereit — Mehrtisch-Lobby, Persistenz, Reconnect, Run-out, Chat.")
