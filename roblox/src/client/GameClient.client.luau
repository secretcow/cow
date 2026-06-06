--!nonstrict
-- KuhPoker — minimaler Roblox-Client (Startgeruest).
-- Empfaengt die Spielsicht (view) vom Server und zeigt Status + Basis-Aktionen.
-- Dies ersetzt public/client.js noch NICHT vollstaendig — es ist das Grundgeruest
-- der Netzwerkschicht plus eine schlichte UI, auf der die volle Tisch-Darstellung
-- (Sitze, Community-Karten, Pot, Log, Chat) aufgebaut werden kann.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartHandEvent = Remotes:WaitForChild("StartHand")
local ActionEvent = Remotes:WaitForChild("Action")
local StateEvent = Remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---- UI aufbauen ----
local gui = Instance.new("ScreenGui")
gui.Name = "KuhPokerGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 90)
status.Position = UDim2.new(0, 10, 0, 10)
status.BackgroundTransparency = 0.3
status.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
status.TextColor3 = Color3.fromRGB(235, 235, 235)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Font = Enum.Font.Code
status.TextSize = 16
status.Text = "Warte auf Spiel…"
status.Parent = gui

local function mkButton(text: string, x: number)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 130, 0, 44)
	b.Position = UDim2.new(0, x, 1, -60)
	b.BackgroundColor3 = Color3.fromRGB(46, 120, 200)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = text
	b.Parent = gui
	return b
end

local startBtn = mkButton("Hand starten", 10)
local checkCallBtn = mkButton("Check/Call", 150)
local foldBtn = mkButton("Fold", 290)
local raiseBtn = mkButton("Min-Raise", 430)

startBtn.Activated:Connect(function()
	StartHandEvent:FireServer()
end)
foldBtn.Activated:Connect(function()
	ActionEvent:FireServer("fold")
end)

local lastView = nil
checkCallBtn.Activated:Connect(function()
	if lastView and lastView.actions then
		if lastView.actions.canCall then
			ActionEvent:FireServer("call")
		else
			ActionEvent:FireServer("check")
		end
	end
end)
raiseBtn.Activated:Connect(function()
	if lastView and lastView.actions and lastView.actions.canRaise then
		ActionEvent:FireServer("raise", lastView.actions.minRaiseTo)
	end
end)

-- ---- Zustand anzeigen ----
StateEvent.OnClientEvent:Connect(function(view)
	lastView = view
	local me = view.players[view.meIdx]
	local lines = {
		string.format("Hand #%d — Stage: %s", view.handNo or 0, tostring(view.stage)),
		string.format("Pot: %d   Dein Stack: %d", view.totalPot or 0, me and me.stack or 0),
		view.yourTurn and ">> DU BIST AM ZUG <<" or ("Am Zug: " .. tostring(view.toActId)),
	}
	if view.matchOver then
		table.insert(lines, "MATCH VORBEI — Sieger: " .. tostring(view.matchWinnerId))
	end
	status.Text = table.concat(lines, "\n")

	local a = view.actions
	checkCallBtn.Visible = a ~= nil
	foldBtn.Visible = a ~= nil
	raiseBtn.Visible = a ~= nil and a.canRaise == true
	if a then
		checkCallBtn.Text = a.canCall and ("Call " .. tostring(a.toCall)) or "Check"
	end
	startBtn.Visible = view.betweenHands == true
end)
