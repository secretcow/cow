--!nonstrict
-- KuhPoker — Roblox-Client (Tisch-UI).
-- Empfaengt die Spielsicht (view) vom Server und rendert Tisch, Community-Karten,
-- Pot, Sitze, Log und Aktionen. Nutzt die geteilte i18n-Schicht (Shared.Strings)
-- fuer die Log-Uebersetzung — wortgleich zur Web-Version.
--
-- Hinweis: Diese UI ist programmatisch aufgebaut (keine .rbxlx-Assets noetig),
-- damit das ganze Projekt aus Rojo heraus lauffaehig ist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Strings = require(Shared:WaitForChild("Strings"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartHandEvent = Remotes:WaitForChild("StartHand")
local ActionEvent = Remotes:WaitForChild("Action")
local RebuyEvent = Remotes:WaitForChild("Rebuy")
local StateEvent = Remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lang = "de"
local lastView = nil

-- ---- Farb-/Stil-Konstanten ----
local COL_BG = Color3.fromRGB(13, 18, 24)
local COL_FELT = Color3.fromRGB(22, 70, 52)
local COL_CARD = Color3.fromRGB(244, 241, 232)
local COL_CARD_BACK = Color3.fromRGB(54, 70, 110)
local COL_TEXT = Color3.fromRGB(235, 235, 235)
local COL_DARK = Color3.fromRGB(28, 34, 44)
local COL_ACCENT = Color3.fromRGB(46, 120, 200)
local COL_GOLD = Color3.fromRGB(240, 195, 70)

local function suitColor(suit: number?): Color3
	local s = suit and Cards.suitById(suit)
	if s then
		-- "#rrggbb" -> Color3
		local hex = s.color:gsub("#", "")
		local r = tonumber(hex:sub(1, 2), 16) or 0
		local g = tonumber(hex:sub(3, 4), 16) or 0
		local b = tonumber(hex:sub(5, 6), 16) or 0
		return Color3.fromRGB(r, g, b)
	end
	return Color3.fromRGB(60, 60, 60)
end

-- ---- UI-Grundgeruest ----
local gui = Instance.new("ScreenGui")
gui.Name = "KuhPokerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Size = UDim2.new(1, 0, 1, 0)
root.BackgroundColor3 = COL_BG
root.BorderSizePixel = 0
root.Parent = gui

-- Filz/Tisch in der Mitte
local felt = Instance.new("Frame")
felt.Size = UDim2.new(0, 720, 0, 360)
felt.Position = UDim2.new(0.5, -360, 0, 80)
felt.BackgroundColor3 = COL_FELT
felt.BorderSizePixel = 0
felt.Parent = root
local feltCorner = Instance.new("UICorner")
feltCorner.CornerRadius = UDim.new(0, 180)
feltCorner.Parent = felt

-- Kopfzeile
local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -20, 0, 56)
header.Position = UDim2.new(0, 10, 0, 12)
header.BackgroundTransparency = 1
header.TextColor3 = COL_GOLD
header.Font = Enum.Font.GothamBold
header.TextSize = 26
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "🐄 KuhPoker"
header.Parent = root

local subHeader = Instance.new("TextLabel")
subHeader.Size = UDim2.new(1, -20, 0, 20)
subHeader.Position = UDim2.new(0, 10, 0, 44)
subHeader.BackgroundTransparency = 1
subHeader.TextColor3 = COL_TEXT
subHeader.Font = Enum.Font.Gotham
subHeader.TextSize = 14
subHeader.TextXAlignment = Enum.TextXAlignment.Left
subHeader.Text = ""
subHeader.Parent = root

-- Sprach-Umschalter
local langBtn = Instance.new("TextButton")
langBtn.Size = UDim2.new(0, 60, 0, 32)
langBtn.Position = UDim2.new(1, -70, 0, 16)
langBtn.BackgroundColor3 = COL_DARK
langBtn.TextColor3 = COL_TEXT
langBtn.Font = Enum.Font.GothamBold
langBtn.TextSize = 14
langBtn.Text = "DE"
langBtn.Parent = root
local langCorner = Instance.new("UICorner")
langCorner.CornerRadius = UDim.new(0, 8)
langCorner.Parent = langBtn

-- Pot-Anzeige (Mitte)
local potLabel = Instance.new("TextLabel")
potLabel.Size = UDim2.new(0, 300, 0, 28)
potLabel.Position = UDim2.new(0.5, -150, 0, 110)
potLabel.BackgroundTransparency = 1
potLabel.TextColor3 = COL_GOLD
potLabel.Font = Enum.Font.GothamBold
potLabel.TextSize = 20
potLabel.Text = ""
potLabel.Parent = root

-- Community-Karten-Reihe
local community = Instance.new("Frame")
community.Size = UDim2.new(0, 5 * 64 + 4 * 8, 0, 88)
community.Position = UDim2.new(0.5, -(5 * 64 + 4 * 8) / 2, 0, 150)
community.BackgroundTransparency = 1
community.Parent = root
local commLayout = Instance.new("UIListLayout")
commLayout.FillDirection = Enum.FillDirection.Horizontal
commLayout.Padding = UDim.new(0, 8)
commLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
commLayout.VerticalAlignment = Enum.VerticalAlignment.Center
commLayout.Parent = community

-- Stage-/Zug-Label
local stageLabel = Instance.new("TextLabel")
stageLabel.Size = UDim2.new(0, 400, 0, 26)
stageLabel.Position = UDim2.new(0.5, -200, 0, 250)
stageLabel.BackgroundTransparency = 1
stageLabel.TextColor3 = COL_TEXT
stageLabel.Font = Enum.Font.Gotham
stageLabel.TextSize = 16
stageLabel.Text = ""
stageLabel.Parent = root

-- Sitz-Container (unter dem Tisch, horizontal)
local seatRow = Instance.new("Frame")
seatRow.Size = UDim2.new(0, 720, 0, 70)
seatRow.Position = UDim2.new(0.5, -360, 0, 300)
seatRow.BackgroundTransparency = 1
seatRow.Parent = root
local seatLayout = Instance.new("UIListLayout")
seatLayout.FillDirection = Enum.FillDirection.Horizontal
seatLayout.Padding = UDim.new(0, 8)
seatLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
seatLayout.Parent = seatRow

-- Log-Feld
local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(0, 320, 0, 200)
logFrame.Position = UDim2.new(0, 10, 1, -210)
logFrame.BackgroundColor3 = COL_DARK
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 4
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.Parent = root
local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 8)
logCorner.Parent = logFrame
local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logFrame
local logPad = Instance.new("UIPadding")
logPad.PaddingLeft = UDim.new(0, 8)
logPad.PaddingTop = UDim.new(0, 6)
logPad.PaddingRight = UDim.new(0, 8)
logPad.Parent = logFrame

-- Aktions-Leiste
local actionBar = Instance.new("Frame")
actionBar.Size = UDim2.new(0, 560, 0, 56)
actionBar.Position = UDim2.new(1, -570, 1, -70)
actionBar.BackgroundTransparency = 1
actionBar.Parent = root
local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.Padding = UDim.new(0, 8)
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
actionLayout.Parent = actionBar

local function mkActionButton(text: string)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 120, 0, 44)
	b.BackgroundColor3 = COL_ACCENT
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Text = text
	b.Visible = false
	b.Parent = actionBar
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	return b
end

local startBtn = mkActionButton(if lang == "de" then "Hand starten" else "Start hand")
local foldBtn = mkActionButton("Fold")
local checkCallBtn = mkActionButton("Check")
local raiseBtn = mkActionButton("Raise")
local rebuyBtn = mkActionButton("➕ Rebuy")
startBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
foldBtn.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
rebuyBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 200)

-- ---- Karten-Widgets ----
local function mkCard(parent, card, hidden: boolean)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 64, 0, 84)
	f.BackgroundColor3 = if hidden then COL_CARD_BACK else COL_CARD
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	if hidden then
		local q = Instance.new("TextLabel")
		q.Size = UDim2.new(1, 0, 1, 0)
		q.BackgroundTransparency = 1
		q.Text = "🐄"
		q.TextSize = 28
		q.TextColor3 = Color3.fromRGB(200, 210, 240)
		q.Parent = f
		return f
	end
	local animal = Cards.animalByRank(card.rank)
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.new(1, 0, 0, 40)
	emoji.Position = UDim2.new(0, 0, 0, 8)
	emoji.BackgroundTransparency = 1
	emoji.Text = animal and animal.emoji or "?"
	emoji.TextSize = 30
	emoji.Parent = f
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -4, 0, 16)
	nameLbl.Position = UDim2.new(0, 2, 1, -22)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = animal and (if lang == "en" then animal.nameEn else animal.name) or "?"
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 11
	nameLbl.TextColor3 = Color3.fromRGB(30, 30, 30)
	nameLbl.Parent = f
	-- Farb-Markierung (Suit)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 10, 0, 10)
	dot.Position = UDim2.new(1, -14, 0, 4)
	dot.BackgroundColor3 = suitColor(card.suit)
	dot.Parent = f
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = dot
	return f
end

local function clear(frame)
	for _, ch in frame:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

-- ---- Rendering ----
local function render(view)
	if not view then
		return
	end
	local me = view.players[view.meIdx]

	-- Pot
	potLabel.Text = `Pot: {view.totalPot or 0} 🪙`

	-- Blinds/Stage-Untertitel
	local blindTxt = ""
	if view.blinds then
		blindTxt = `Blinds {view.blinds.sb}/{view.blinds.bb}`
		if view.blinds.tournament and view.blinds.level then
			blindTxt ..= ` · Stufe {view.blinds.level}`
		end
	end
	if view.cash then
		blindTxt ..= `   💵 Cash · Buy-in {view.buyIn or 0}`
	end
	subHeader.Text = blindTxt

	-- Community
	clear(community)
	for _, c in view.community do
		mkCard(community, c, false)
	end

	-- Stage / Zug
	local stageTxt = `Hand #{view.handNo or 0} — {tostring(view.stage)}`
	if view.matchOver then
		stageTxt = if view.matchWinnerId == (me and me.id)
			then "🏆 Du hast das Match gewonnen!"
			else "Match beendet."
	elseif view.yourTurn then
		stageTxt = ">> DU BIST AM ZUG <<"
	elseif view.toActId then
		stageTxt ..= `   ·   am Zug: {tostring(view.toActId)}`
	end
	stageLabel.Text = stageTxt

	-- Sitze
	clear(seatRow)
	for _, p in view.players do
		local seat = Instance.new("Frame")
		seat.Size = UDim2.new(0, 130, 0, 66)
		seat.BackgroundColor3 = if p.isMe then Color3.fromRGB(38, 48, 64) else COL_DARK
		seat.BorderSizePixel = 0
		seat.Parent = seatRow
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 8)
		sc.Parent = seat
		if p.id == view.toActId then
			local stroke = Instance.new("UIStroke")
			stroke.Color = COL_GOLD
			stroke.Thickness = 2
			stroke.Parent = seat
		end
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -8, 0, 18)
		nm.Position = UDim2.new(0, 4, 0, 2)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 13
		nm.TextColor3 = if p.folded then Color3.fromRGB(130, 130, 130) else COL_TEXT
		nm.TextXAlignment = Enum.TextXAlignment.Left
		local tags = ""
		if p.isButton then
			tags ..= " Ⓑ"
		end
		if p.allIn then
			tags ..= " All-In"
		end
		nm.Text = (p.name or "?") .. tags
		nm.Parent = seat
		local st = Instance.new("TextLabel")
		st.Size = UDim2.new(1, -8, 0, 16)
		st.Position = UDim2.new(0, 4, 0, 22)
		st.BackgroundTransparency = 1
		st.Font = Enum.Font.Gotham
		st.TextSize = 12
		st.TextColor3 = COL_GOLD
		st.TextXAlignment = Enum.TextXAlignment.Left
		st.Text = `{p.stack} 🪙` .. (if p.bet and p.bet > 0 then `  (Bet {p.bet})` else "")
		st.Parent = seat
		-- eigene Hole-Cards mini anzeigen
		if p.isMe then
			local handTxt = Instance.new("TextLabel")
			handTxt.Size = UDim2.new(1, -8, 0, 16)
			handTxt.Position = UDim2.new(0, 4, 0, 40)
			handTxt.BackgroundTransparency = 1
			handTxt.Font = Enum.Font.Gotham
			handTxt.TextSize = 12
			handTxt.TextColor3 = Color3.fromRGB(180, 220, 255)
			handTxt.TextXAlignment = Enum.TextXAlignment.Left
			local parts = {}
			for _, c in p.hole do
				if c and c.rank then
					local a = Cards.animalByRank(c.rank)
					table.insert(parts, a and a.emoji or "?")
				end
			end
			handTxt.Text = table.concat(parts, " ")
			handTxt.Parent = seat
		end
	end

	-- Log (uebersetzt)
	clear(logFrame)
	local logArr = view.log or {}
	for _, event in logArr do
		local line = Instance.new("TextLabel")
		line.Size = UDim2.new(1, -16, 0, 16)
		line.BackgroundTransparency = 1
		line.Font = Enum.Font.Gotham
		line.TextSize = 12
		line.TextColor3 = Color3.fromRGB(200, 205, 215)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextWrapped = true
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.Text = Strings.translateLog(lang, event)
		line.Parent = logFrame
	end

	-- Aktionen
	local a = view.actions
	startBtn.Visible = view.betweenHands == true and not view.matchOver
	foldBtn.Visible = a ~= nil
	checkCallBtn.Visible = a ~= nil
	raiseBtn.Visible = a ~= nil and a.canRaise == true
	if a then
		checkCallBtn.Text = if a.canCall then `Call {a.toCall}` else "Check"
	end
	-- Rebuy nur im Cash, zwischen Haenden, wenn unter Buy-in
	rebuyBtn.Visible = view.cash == true
		and view.betweenHands == true
		and (view.myStack or 0) < (view.buyIn or 0)
end

-- ---- Aktionen verdrahten ----
startBtn.Activated:Connect(function()
	StartHandEvent:FireServer()
end)
foldBtn.Activated:Connect(function()
	ActionEvent:FireServer("fold")
end)
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
		-- Einfacher Startwert: Min-Raise. (Slider/Pot/All-In folgen mit der Vollausbau-UI.)
		ActionEvent:FireServer("raise", lastView.actions.minRaiseTo)
	end
end)
rebuyBtn.Activated:Connect(function()
	RebuyEvent:FireServer()
end)
langBtn.Activated:Connect(function()
	lang = if lang == "de" then "en" else "de"
	langBtn.Text = string.upper(lang)
	render(lastView)
end)

-- ---- Server-Zustand ----
StateEvent.OnClientEvent:Connect(function(view)
	lastView = view
	render(view)
end)
