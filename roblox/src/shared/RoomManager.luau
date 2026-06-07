--!nonstrict
-- Raum-Verwaltung fuer KuhPoker (Roblox). Reine Logik, keine Roblox-API —
-- daher standalone testbar via luau-CLI. Bildet die Raum-/Code-Mechanik aus
-- server.js nach: Code erzeugen, beitreten, verlassen, Match starten.
--
-- Mehrere Tische pro Server moeglich (Code-basiert). Der Server (GameServer)
-- haelt EINE RoomManager-Instanz und uebersetzt Spieler-Events darauf.

local PokerEngine = require(script and script.Parent.PokerEngine or "./PokerEngine")

local RoomManager = {}
RoomManager.__index = RoomManager

-- Ohne verwechselbare Zeichen (kein 0/O, 1/I).
local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local ALLOWED_STACKS = { [500] = true, [1000] = true, [2000] = true, [5000] = true }

-- opts.rng: function(lo, hi) -> int  (fuer deterministische Tests injizierbar)
function RoomManager.new(opts)
	local self = setmetatable({}, RoomManager)
	self.rooms = {} -- [code] = room
	self.rng = (opts and opts.rng) or math.random
	return self
end

local function clampInt(v, lo, hi, default)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return default
	end
	n = math.floor(n)
	if n < lo then
		n = lo
	end
	if n > hi then
		n = hi
	end
	return n
end

local function clampSettings(opts)
	opts = opts or {}
	local stack = tonumber(opts.startingStack)
	if not (stack and ALLOWED_STACKS[math.floor(stack)]) then
		stack = 1000
	else
		stack = math.floor(stack)
	end
	local cash = not not opts.cash
	return {
		maxPlayers = clampInt(opts.maxPlayers, 2, 6, 6),
		startingStack = stack,
		flush = not not opts.flush,
		cash = cash,
		tournament = (not cash) and (not not opts.tournament),
		levelHands = clampInt(opts.levelHands, 4, 10, 6),
	}
end

function RoomManager:_genCode()
	for _attempt = 1, 200 do
		local code = ""
		for _ = 1, 4 do
			local idx = self.rng(1, #CODE_CHARS)
			code ..= CODE_CHARS:sub(idx, idx)
		end
		if not self.rooms[code] then
			return code
		end
	end
	error("Kein freier Raum-Code gefunden")
end

-- Erstellt einen Raum. hostDef = { id, name }. Gibt code, room zurueck.
function RoomManager:createRoom(hostDef, opts)
	if not (hostDef and hostDef.id) then
		return nil, { error = "Kein gueltiger Host." }
	end
	local code = self:_genCode()
	local room = {
		code = code,
		hostId = hostDef.id,
		players = { { id = hostDef.id, name = hostDef.name or "?" } },
		settings = clampSettings(opts),
		table = nil,
		started = false,
	}
	self.rooms[code] = room
	return code, room
end

function RoomManager:getRoom(code)
	return self.rooms[code]
end

local function seatIndex(room, id)
	for i, p in room.players do
		if p.id == id then
			return i
		end
	end
	return nil
end

-- Tritt einem Raum bei. def = { id, name }.
function RoomManager:joinRoom(code, def)
	local room = self.rooms[code]
	if not room then
		return { error = "Raum nicht gefunden." }
	end
	if not (def and def.id) then
		return { error = "Kein gueltiger Spieler." }
	end
	-- Bereits am Tisch? -> idempotent (z. B. Reconnect).
	if seatIndex(room, def.id) then
		return { ok = true, room = room, rejoined = true }
	end
	if room.started then
		return { error = "Match laeuft bereits." }
	end
	if #room.players >= room.settings.maxPlayers then
		return { error = "Tisch ist voll." }
	end
	table.insert(room.players, { id = def.id, name = def.name or "?" })
	return { ok = true, room = room }
end

-- Verlaesst einen Raum. Gibt zurueck, ob der Raum dadurch zerstoert wurde.
function RoomManager:leaveRoom(code, id)
	local room = self.rooms[code]
	if not room then
		return { error = "Raum nicht gefunden." }
	end
	local idx = seatIndex(room, id)
	if not idx then
		return { error = "Nicht im Raum." }
	end
	table.remove(room.players, idx)
	-- Leer? -> Raum zerstoeren.
	if #room.players == 0 then
		self.rooms[code] = nil
		return { ok = true, destroyed = true }
	end
	-- Host weg? -> ersten verbliebenen Spieler zum Host machen.
	if room.hostId == id then
		room.hostId = room.players[1].id
	end
	return { ok = true, destroyed = false, room = room }
end

-- Startet das Match: baut die PokerEngine.Table aus den Sitzen.
function RoomManager:startMatch(code)
	local room = self.rooms[code]
	if not room then
		return { error = "Raum nicht gefunden." }
	end
	if #room.players < 2 then
		return { error = "Mindestens zwei Spieler noetig." }
	end
	local defs = {}
	for _, p in room.players do
		table.insert(defs, { id = p.id, name = p.name })
	end
	room.table = PokerEngine.Table.new(defs, {
		flush = room.settings.flush,
		startingStack = room.settings.startingStack,
		cash = room.settings.cash,
		tournament = room.settings.tournament,
		levelHands = room.settings.levelHands,
	})
	room.started = true
	return { ok = true, room = room, table = room.table }
end

function RoomManager:destroyRoom(code)
	local existed = self.rooms[code] ~= nil
	self.rooms[code] = nil
	return existed
end

function RoomManager:roomCount()
	local c = 0
	for _ in self.rooms do
		c += 1
	end
	return c
end

return RoomManager
