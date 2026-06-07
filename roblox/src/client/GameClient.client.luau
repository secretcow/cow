--!nonstrict
-- KuhPoker — Roblox-Client (Lobby + Tisch-UI).
-- Empfaengt die Spielsicht (view) vom Server und rendert je nach view.screen
-- entweder die Lobby (Profil + Tisch erstellen/beitreten) oder den Tisch
-- (Community-Karten, Pot, Sitze, Log, Aktionen, Chat, Equities).
-- Nutzt die geteilte i18n-Schicht (Shared.Strings) fuer die Log-Uebersetzung.
--
-- Hinweis: Diese UI ist programmatisch aufgebaut (keine .rbxlx-Assets noetig),
-- damit das ganze Projekt aus Rojo heraus lauffaehig ist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Strings = require(Shared:WaitForChild("Strings"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CreateRoomFn = Remotes:WaitForChild("CreateRoom")
local JoinRoomFn = Remotes:WaitForChild("JoinRoom")
local QuickPlayFn = Remotes:WaitForChild("QuickPlay")
local LeaveRoomEvent = Remotes:WaitForChild("LeaveRoom")
local StartHandEvent = Remotes:WaitForChild("StartHand")
local ActionEvent = Remotes:WaitForChild("Action")
local RebuyEvent = Remotes:WaitForChild("Rebuy")
local ChatEvent = Remotes:WaitForChild("Chat")
local StateEvent = Remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lang = "de"
local lastView = nil
local myProfile = nil
local currentScreen = "lobby"

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

-- ---- Mobile-/Tablet-Skalierung ----
-- Die UI ist fuer eine 1280x720-Designflaeche gebaut. UIScale skaliert alle
-- Pixel-Offsets (und damit die ganze Oberflaeche) so, dass sie auf jedem
-- Geraet — Handy, Tablet, Desktop — vollstaendig hineinpasst.
local DESIGN_W, DESIGN_H = 1280, 720
local uiScale = Instance.new("UIScale")
uiScale.Parent = root
local camera = workspace.CurrentCamera
local function fitScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then
		return
	end
	local s = math.min(vp.X / DESIGN_W, vp.Y / DESIGN_H)
	uiScale.Scale = math.clamp(s, 0.5, 1.4)
end
fitScale()
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
	fitScale()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale)
	end
end)

-- Kopfzeile (immer sichtbar)
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
subHeader.Size = UDim2.new(1, -240, 0, 20)
subHeader.Position = UDim2.new(0, 10, 0, 44)
subHeader.BackgroundTransparency = 1
subHeader.TextColor3 = COL_TEXT
subHeader.Font = Enum.Font.Gotham
subHeader.TextSize = 14
subHeader.TextXAlignment = Enum.TextXAlignment.Left
subHeader.Text = ""
subHeader.Parent = root

-- Sprach-Umschalter (immer sichtbar)
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

-- Verlassen-Knopf (nur am Tisch sichtbar)
local leaveBtn = Instance.new("TextButton")
leaveBtn.Size = UDim2.new(0, 92, 0, 32)
leaveBtn.Position = UDim2.new(1, -170, 0, 16)
leaveBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
leaveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
leaveBtn.Font = Enum.Font.GothamBold
leaveBtn.TextSize = 14
leaveBtn.Text = "Verlassen"
leaveBtn.Visible = false
leaveBtn.Parent = root
local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = UDim.new(0, 8)
leaveCorner.Parent = leaveBtn

local function mkCorner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

-- =====================================================================
-- =========================== LOBBY-SCREEN ============================
-- =====================================================================
local lobbyScreen = Instance.new("Frame")
lobbyScreen.Size = UDim2.new(1, 0, 1, -80)
lobbyScreen.Position = UDim2.new(0, 0, 0, 80)
lobbyScreen.BackgroundTransparency = 1
lobbyScreen.Parent = root

-- Profil-Karte
local profileCard = Instance.new("Frame")
profileCard.Size = UDim2.new(0, 420, 0, 120)
profileCard.Position = UDim2.new(0.5, -210, 0, 10)
profileCard.BackgroundColor3 = COL_DARK
profileCard.BorderSizePixel = 0
profileCard.Parent = lobbyScreen
mkCorner(profileCard, 12)

local profileName = Instance.new("TextLabel")
profileName.Size = UDim2.new(1, -20, 0, 28)
profileName.Position = UDim2.new(0, 12, 0, 8)
profileName.BackgroundTransparency = 1
profileName.Font = Enum.Font.GothamBold
profileName.TextSize = 20
profileName.TextColor3 = COL_GOLD
profileName.TextXAlignment = Enum.TextXAlignment.Left
profileName.Text = "—"
profileName.Parent = profileCard

local profileWallet = Instance.new("TextLabel")
profileWallet.Size = UDim2.new(1, -20, 0, 26)
profileWallet.Position = UDim2.new(0, 12, 0, 38)
profileWallet.BackgroundTransparency = 1
profileWallet.Font = Enum.Font.GothamBold
profileWallet.TextSize = 22
profileWallet.TextColor3 = COL_TEXT
profileWallet.TextXAlignment = Enum.TextXAlignment.Left
profileWallet.Text = "🪙 —"
profileWallet.Parent = profileCard

local profileStats = Instance.new("TextLabel")
profileStats.Size = UDim2.new(1, -20, 0, 38)
profileStats.Position = UDim2.new(0, 12, 0, 70)
profileStats.BackgroundTransparency = 1
profileStats.Font = Enum.Font.Gotham
profileStats.TextSize = 13
profileStats.TextColor3 = Color3.fromRGB(190, 200, 215)
profileStats.TextXAlignment = Enum.TextXAlignment.Left
profileStats.TextYAlignment = Enum.TextYAlignment.Top
profileStats.Text = ""
profileStats.Parent = profileCard

-- ---- Schnell spielen (Matchmaking) ----
local quickBtn = Instance.new("TextButton")
quickBtn.Size = UDim2.new(0, 860, 0, 56)
quickBtn.Position = UDim2.new(0.5, -430, 0, 140)
quickBtn.BackgroundColor3 = COL_GOLD
quickBtn.TextColor3 = Color3.fromRGB(30, 26, 12)
quickBtn.Font = Enum.Font.GothamBold
quickBtn.TextSize = 22
quickBtn.Text = "⚡ Schnell spielen"
quickBtn.Parent = lobbyScreen
mkCorner(quickBtn, 12)

-- ---- Tisch erstellen ----
local createCard = Instance.new("Frame")
createCard.Size = UDim2.new(0, 420, 0, 260)
createCard.Position = UDim2.new(0.5, -430, 0, 212)
createCard.BackgroundColor3 = COL_DARK
createCard.BorderSizePixel = 0
createCard.Parent = lobbyScreen
mkCorner(createCard, 12)

local createTitle = Instance.new("TextLabel")
createTitle.Size = UDim2.new(1, -20, 0, 24)
createTitle.Position = UDim2.new(0, 12, 0, 10)
createTitle.BackgroundTransparency = 1
createTitle.Font = Enum.Font.GothamBold
createTitle.TextSize = 16
createTitle.TextColor3 = COL_GOLD
createTitle.TextXAlignment = Enum.TextXAlignment.Left
createTitle.Text = "Tisch erstellen"
createTitle.Parent = createCard

-- Einstellungen (Zyklus-/Umschalt-Knoepfe)
local settings = { maxPlayers = 6, startingStack = 1000, flush = false, cash = false, tournament = false }
local STACKS = { 500, 1000, 2000, 5000 }

local function mkSettingBtn(yOff)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -24, 0, 34)
	b.Position = UDim2.new(0, 12, 0, yOff)
	b.BackgroundColor3 = Color3.fromRGB(44, 52, 66)
	b.TextColor3 = COL_TEXT
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.Parent = createCard
	mkCorner(b, 8)
	return b
end

local maxBtn = mkSettingBtn(44)
local stackBtn = mkSettingBtn(84)
local modeBtn = mkSettingBtn(124)
local flushBtn = mkSettingBtn(164)

local function modeLabel()
	if settings.cash then
		return if lang == "de" then "Modus: Cash-Game 💵" else "Mode: Cash game 💵"
	elseif settings.tournament then
		return if lang == "de" then "Modus: Turnier 🏆" else "Mode: Tournament 🏆"
	end
	return if lang == "de" then "Modus: Normal" else "Mode: Normal"
end

local function refreshSettingBtns()
	maxBtn.Text = (if lang == "de" then "Max. Spieler: " else "Max players: ") .. settings.maxPlayers
	stackBtn.Text = (if lang == "de" then "Start-Chips: " else "Starting chips: ") .. settings.startingStack
	modeBtn.Text = modeLabel()
	flushBtn.Text = (if lang == "de" then "Flush: " else "Flush: ")
		.. (if settings.flush then "An" else "Aus")
end

maxBtn.Activated:Connect(function()
	settings.maxPlayers += 1
	if settings.maxPlayers > 6 then
		settings.maxPlayers = 2
	end
	refreshSettingBtns()
end)
stackBtn.Activated:Connect(function()
	local idx = 1
	for i, v in STACKS do
		if v == settings.startingStack then
			idx = i
		end
	end
	idx += 1
	if idx > #STACKS then
		idx = 1
	end
	settings.startingStack = STACKS[idx]
	refreshSettingBtns()
end)
modeBtn.Activated:Connect(function()
	-- Normal -> Turnier -> Cash -> Normal
	if not settings.cash and not settings.tournament then
		settings.tournament = true
	elseif settings.tournament then
		settings.tournament = false
		settings.cash = true
	else
		settings.cash = false
	end
	refreshSettingBtns()
end)
flushBtn.Activated:Connect(function()
	settings.flush = not settings.flush
	refreshSettingBtns()
end)

local createBtn = Instance.new("TextButton")
createBtn.Size = UDim2.new(1, -24, 0, 40)
createBtn.Position = UDim2.new(0, 12, 0, 208)
createBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
createBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
createBtn.Font = Enum.Font.GothamBold
createBtn.TextSize = 16
createBtn.Text = "Tisch erstellen"
createBtn.Parent = createCard
mkCorner(createBtn, 8)

-- ---- Tisch beitreten ----
local joinCard = Instance.new("Frame")
joinCard.Size = UDim2.new(0, 420, 0, 200)
joinCard.Position = UDim2.new(0.5, 10, 0, 212)
joinCard.BackgroundColor3 = COL_DARK
joinCard.BorderSizePixel = 0
joinCard.Parent = lobbyScreen
mkCorner(joinCard, 12)

local joinTitle = Instance.new("TextLabel")
joinTitle.Size = UDim2.new(1, -20, 0, 24)
joinTitle.Position = UDim2.new(0, 12, 0, 10)
joinTitle.BackgroundTransparency = 1
joinTitle.Font = Enum.Font.GothamBold
joinTitle.TextSize = 16
joinTitle.TextColor3 = COL_GOLD
joinTitle.TextXAlignment = Enum.TextXAlignment.Left
joinTitle.Text = "Tisch beitreten"
joinTitle.Parent = joinCard

local joinHint = Instance.new("TextLabel")
joinHint.Size = UDim2.new(1, -24, 0, 20)
joinHint.Position = UDim2.new(0, 12, 0, 40)
joinHint.BackgroundTransparency = 1
joinHint.Font = Enum.Font.Gotham
joinHint.TextSize = 13
joinHint.TextColor3 = Color3.fromRGB(190, 200, 215)
joinHint.TextXAlignment = Enum.TextXAlignment.Left
joinHint.Text = "Code vom Host eingeben:"
joinHint.Parent = joinCard

local codeInput = Instance.new("TextBox")
codeInput.Size = UDim2.new(1, -24, 0, 48)
codeInput.Position = UDim2.new(0, 12, 0, 66)
codeInput.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
codeInput.TextColor3 = COL_GOLD
codeInput.Font = Enum.Font.GothamBold
codeInput.TextSize = 28
codeInput.PlaceholderText = "ABCD"
codeInput.Text = ""
codeInput.ClearTextOnFocus = false
codeInput.Parent = joinCard
mkCorner(codeInput, 8)

local joinBtn = Instance.new("TextButton")
joinBtn.Size = UDim2.new(1, -24, 0, 40)
joinBtn.Position = UDim2.new(0, 12, 0, 126)
joinBtn.BackgroundColor3 = COL_ACCENT
joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
joinBtn.Font = Enum.Font.GothamBold
joinBtn.TextSize = 16
joinBtn.Text = "Beitreten"
joinBtn.Parent = joinCard
mkCorner(joinBtn, 8)

local lobbyError = Instance.new("TextLabel")
lobbyError.Size = UDim2.new(0, 860, 0, 24)
lobbyError.Position = UDim2.new(0.5, -430, 0, 482)
lobbyError.BackgroundTransparency = 1
lobbyError.Font = Enum.Font.GothamBold
lobbyError.TextSize = 15
lobbyError.TextColor3 = Color3.fromRGB(240, 120, 120)
lobbyError.Text = ""
lobbyError.Parent = lobbyScreen

-- Tagesbonus-Toast (schwebt unten, blendet nach einigen Sekunden aus)
local dailyToast = Instance.new("TextLabel")
dailyToast.Size = UDim2.new(0, 480, 0, 44)
dailyToast.Position = UDim2.new(0.5, -240, 1, -64)
dailyToast.BackgroundColor3 = COL_GOLD
dailyToast.TextColor3 = Color3.fromRGB(30, 26, 12)
dailyToast.Font = Enum.Font.GothamBold
dailyToast.TextSize = 18
dailyToast.Text = ""
dailyToast.Visible = false
dailyToast.ZIndex = 50
dailyToast.Parent = root
mkCorner(dailyToast, 10)

local toastGen = 0
local function showDailyBonus(b)
	if not (b and b.granted) then
		return
	end
	dailyToast.Text = if lang == "de"
		then `🎁 Täglicher Bonus: +{b.amount} 🪙   ·   Serie {b.streak} Tag(e)`
		else `🎁 Daily bonus: +{b.amount} 🪙   ·   Streak {b.streak} day(s)`
	dailyToast.Visible = true
	toastGen += 1
	local gen = toastGen
	task.delay(6, function()
		if toastGen == gen then
			dailyToast.Visible = false
		end
	end)
end

-- =====================================================================
-- =========================== TISCH-SCREEN ============================
-- =====================================================================
local tableScreen = Instance.new("Frame")
tableScreen.Size = UDim2.new(1, 0, 1, 0)
tableScreen.BackgroundTransparency = 1
tableScreen.Visible = false
tableScreen.Parent = root

-- Filz/Tisch
local felt = Instance.new("Frame")
felt.Size = UDim2.new(0, 720, 0, 360)
felt.Position = UDim2.new(0.5, -360, 0, 80)
felt.BackgroundColor3 = COL_FELT
felt.BorderSizePixel = 0
felt.Parent = tableScreen
mkCorner(felt, 180)

-- Pot-Anzeige
local potLabel = Instance.new("TextLabel")
potLabel.Size = UDim2.new(0, 300, 0, 28)
potLabel.Position = UDim2.new(0.5, -150, 0, 110)
potLabel.BackgroundTransparency = 1
potLabel.TextColor3 = COL_GOLD
potLabel.Font = Enum.Font.GothamBold
potLabel.TextSize = 20
potLabel.Text = ""
potLabel.Parent = tableScreen

-- Community-Karten
local community = Instance.new("Frame")
community.Size = UDim2.new(0, 5 * 64 + 4 * 8, 0, 88)
community.Position = UDim2.new(0.5, -(5 * 64 + 4 * 8) / 2, 0, 150)
community.BackgroundTransparency = 1
community.Parent = tableScreen
local commLayout = Instance.new("UIListLayout")
commLayout.FillDirection = Enum.FillDirection.Horizontal
commLayout.Padding = UDim.new(0, 8)
commLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
commLayout.VerticalAlignment = Enum.VerticalAlignment.Center
commLayout.Parent = community

-- Stage-/Zug-Label
local stageLabel = Instance.new("TextLabel")
stageLabel.Size = UDim2.new(0, 460, 0, 26)
stageLabel.Position = UDim2.new(0.5, -230, 0, 250)
stageLabel.BackgroundTransparency = 1
stageLabel.TextColor3 = COL_TEXT
stageLabel.Font = Enum.Font.Gotham
stageLabel.TextSize = 16
stageLabel.Text = ""
stageLabel.Parent = tableScreen

-- Sitz-Container
local seatRow = Instance.new("Frame")
seatRow.Size = UDim2.new(0, 720, 0, 86)
seatRow.Position = UDim2.new(0.5, -360, 0, 300)
seatRow.BackgroundTransparency = 1
seatRow.Parent = tableScreen
local seatLayout = Instance.new("UIListLayout")
seatLayout.FillDirection = Enum.FillDirection.Horizontal
seatLayout.Padding = UDim.new(0, 8)
seatLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
seatLayout.Parent = seatRow

-- Log-Feld (Spielverlauf)
local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(0, 320, 0, 180)
logFrame.Position = UDim2.new(0, 10, 1, -380)
logFrame.BackgroundColor3 = COL_DARK
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 4
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.Parent = tableScreen
mkCorner(logFrame, 8)
local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logFrame
local logPad = Instance.new("UIPadding")
logPad.PaddingLeft = UDim.new(0, 8)
logPad.PaddingTop = UDim.new(0, 6)
logPad.PaddingRight = UDim.new(0, 8)
logPad.Parent = logFrame

-- ---- Chat ----
local chatList = Instance.new("ScrollingFrame")
chatList.Size = UDim2.new(0, 320, 0, 150)
chatList.Position = UDim2.new(0, 10, 1, -190)
chatList.BackgroundColor3 = Color3.fromRGB(20, 26, 34)
chatList.BorderSizePixel = 0
chatList.ScrollBarThickness = 4
chatList.CanvasSize = UDim2.new(0, 0, 0, 0)
chatList.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatList.Parent = tableScreen
mkCorner(chatList, 8)
local chatLayout = Instance.new("UIListLayout")
chatLayout.Padding = UDim.new(0, 2)
chatLayout.Parent = chatList
local chatPad = Instance.new("UIPadding")
chatPad.PaddingLeft = UDim.new(0, 8)
chatPad.PaddingTop = UDim.new(0, 6)
chatPad.PaddingRight = UDim.new(0, 8)
chatPad.Parent = chatList

local chatInput = Instance.new("TextBox")
chatInput.Size = UDim2.new(0, 250, 0, 30)
chatInput.Position = UDim2.new(0, 10, 1, -34)
chatInput.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
chatInput.TextColor3 = COL_TEXT
chatInput.Font = Enum.Font.Gotham
chatInput.TextSize = 14
chatInput.TextXAlignment = Enum.TextXAlignment.Left
chatInput.PlaceholderText = "Nachricht…"
chatInput.Text = ""
chatInput.ClearTextOnFocus = false
chatInput.Parent = tableScreen
mkCorner(chatInput, 8)
local chatInputPad = Instance.new("UIPadding")
chatInputPad.PaddingLeft = UDim.new(0, 8)
chatInputPad.Parent = chatInput

local chatSend = Instance.new("TextButton")
chatSend.Size = UDim2.new(0, 64, 0, 30)
chatSend.Position = UDim2.new(0, 266, 1, -34)
chatSend.BackgroundColor3 = COL_ACCENT
chatSend.TextColor3 = Color3.fromRGB(255, 255, 255)
chatSend.Font = Enum.Font.GothamBold
chatSend.TextSize = 14
chatSend.Text = "Senden"
chatSend.Parent = tableScreen
mkCorner(chatSend, 8)

-- ---- Aktions-Leiste ----
local actionBar = Instance.new("Frame")
actionBar.Size = UDim2.new(0, 560, 0, 56)
actionBar.Position = UDim2.new(1, -570, 1, -70)
actionBar.BackgroundTransparency = 1
actionBar.Parent = tableScreen
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
	mkCorner(b, 8)
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

-- ---- Raise-Panel mit ziehbarem Slider ----
local raiseState = { open = false, min = 0, max = 0, val = 0 }

local raisePanel = Instance.new("Frame")
raisePanel.Size = UDim2.new(0, 560, 0, 120)
raisePanel.Position = UDim2.new(1, -570, 1, -190)
raisePanel.BackgroundColor3 = COL_DARK
raisePanel.BorderSizePixel = 0
raisePanel.Visible = false
raisePanel.Parent = tableScreen
mkCorner(raisePanel, 10)

local raiseValLabel = Instance.new("TextLabel")
raiseValLabel.Size = UDim2.new(1, -20, 0, 26)
raiseValLabel.Position = UDim2.new(0, 10, 0, 8)
raiseValLabel.BackgroundTransparency = 1
raiseValLabel.Font = Enum.Font.GothamBold
raiseValLabel.TextSize = 18
raiseValLabel.TextColor3 = COL_GOLD
raiseValLabel.TextXAlignment = Enum.TextXAlignment.Left
raiseValLabel.Text = "Erhöhen auf 0"
raiseValLabel.Parent = raisePanel

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -20, 0, 8)
track.Position = UDim2.new(0, 10, 0, 44)
track.BackgroundColor3 = Color3.fromRGB(60, 68, 82)
track.BorderSizePixel = 0
track.Parent = raisePanel
mkCorner(track, 8).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = COL_ACCENT
fill.BorderSizePixel = 0
fill.Parent = track
mkCorner(fill, 8).CornerRadius = UDim.new(1, 0)

local knob = Instance.new("TextButton")
knob.Size = UDim2.new(0, 22, 0, 22)
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.new(0, 0, 0.5, 0)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.Text = ""
knob.AutoButtonColor = false
knob.Parent = track
mkCorner(knob, 11).CornerRadius = UDim.new(1, 0)

local function refreshSlider()
	local span = math.max(1, raiseState.max - raiseState.min)
	local frac = math.clamp((raiseState.val - raiseState.min) / span, 0, 1)
	fill.Size = UDim2.new(frac, 0, 1, 0)
	knob.Position = UDim2.new(frac, 0, 0.5, 0)
	raiseValLabel.Text = (if lang == "de" then "Erhöhen auf " else "Raise to ") .. tostring(raiseState.val)
		.. (if raiseState.val >= raiseState.max then " (All-In)" else "")
end

local function setRaiseVal(v)
	v = math.floor(v)
	v = math.clamp(v, raiseState.min, raiseState.max)
	raiseState.val = v
	refreshSlider()
end

local quickRow = Instance.new("Frame")
quickRow.Size = UDim2.new(1, -20, 0, 36)
quickRow.Position = UDim2.new(0, 10, 0, 60)
quickRow.BackgroundTransparency = 1
quickRow.Parent = raisePanel
local quickLayout = Instance.new("UIListLayout")
quickLayout.FillDirection = Enum.FillDirection.Horizontal
quickLayout.Padding = UDim.new(0, 6)
quickLayout.Parent = quickRow

local function mkQuick(text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 90, 0, 32)
	b.BackgroundColor3 = Color3.fromRGB(50, 58, 72)
	b.TextColor3 = COL_TEXT
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.Text = text
	b.Parent = quickRow
	mkCorner(b, 6)
	return b
end

local minQuick = mkQuick("Min")
local potQuick = mkQuick("Pot")
local maxQuick = mkQuick("All-In")
local backQuick = mkQuick("Zurück")
local confirmQuick = mkQuick("Erhöhen")
confirmQuick.BackgroundColor3 = COL_ACCENT
backQuick.BackgroundColor3 = Color3.fromRGB(90, 90, 100)

-- Slider-Drag
local dragging = false
local function updateFromX(mouseX)
	local rel = (mouseX - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
	rel = math.clamp(rel, 0, 1)
	setRaiseVal(raiseState.min + rel * (raiseState.max - raiseState.min))
end
knob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
	end
end)
track.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		updateFromX(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateFromX(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

local function openRaisePanel()
	local a = lastView and lastView.actions
	if not (a and a.canRaise) then
		return
	end
	raiseState.open = true
	raiseState.min = a.minRaiseTo
	raiseState.max = a.maxRaiseTo
	setRaiseVal(a.minRaiseTo)
	raisePanel.Visible = true
end
local function closeRaisePanel()
	raiseState.open = false
	raisePanel.Visible = false
end

minQuick.Activated:Connect(function()
	setRaiseVal(raiseState.min)
end)
potQuick.Activated:Connect(function()
	local potVal = (lastView and lastView.pot) or raiseState.min
	setRaiseVal(potVal)
end)
maxQuick.Activated:Connect(function()
	setRaiseVal(raiseState.max)
end)
backQuick.Activated:Connect(function()
	closeRaisePanel()
end)
confirmQuick.Activated:Connect(function()
	ActionEvent:FireServer("raise", raiseState.val)
	closeRaisePanel()
end)

-- ---- Karten-Widgets ----
local function mkCard(parent, card, hidden: boolean)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 64, 0, 84)
	f.BackgroundColor3 = if hidden then COL_CARD_BACK else COL_CARD
	f.BorderSizePixel = 0
	f.Parent = parent
	mkCorner(f, 8)
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
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 10, 0, 10)
	dot.Position = UDim2.new(1, -14, 0, 4)
	dot.BackgroundColor3 = suitColor(card.suit)
	dot.Parent = f
	mkCorner(dot, 5).CornerRadius = UDim.new(1, 0)
	return f
end

local function clear(frame)
	for _, ch in frame:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

-- ---- Spieler-Avatare (Kopfbild) ----
local avatarCache = {} -- [userId:number] = content-string
local function loadAvatar(imgLabel, idStr)
	local uid = tonumber(idStr)
	if not uid then
		return
	end
	if avatarCache[uid] then
		imgLabel.Image = avatarCache[uid]
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and content then
			avatarCache[uid] = content
			-- Sitz koennte beim naechsten Render schon ersetzt sein -> Parent pruefen.
			if imgLabel and imgLabel.Parent then
				imgLabel.Image = content
			end
		end
	end)
end

-- =====================================================================
-- ============================ RENDERING ==============================
-- =====================================================================
local function showScreen(name)
	currentScreen = name
	lobbyScreen.Visible = name == "lobby"
	tableScreen.Visible = name == "table"
	leaveBtn.Visible = name == "table"
end

local function renderProfile(prof)
	if not prof then
		return
	end
	myProfile = prof
	profileName.Text = prof.name or "Spieler"
	profileWallet.Text = `🪙 {prof.wallet or 0}`
	profileStats.Text = string.format(
		(if lang == "de"
			then "Matches gewonnen: %d   ·   Haende gewonnen: %d\nGroesster Pot: %d 🪙"
			else "Matches won: %d   ·   Hands won: %d\nBiggest pot: %d 🪙"),
		prof.matchesWon or 0,
		prof.handsWon or 0,
		prof.biggestPot or 0
	)
end

local function renderLobby()
	header.Text = "🐄 KuhPoker"
	subHeader.Text = if lang == "de" then "Lobby — erstelle oder betritt einen Tisch" else "Lobby — create or join a table"
	createTitle.Text = if lang == "de" then "Tisch erstellen" else "Create table"
	joinTitle.Text = if lang == "de" then "Tisch beitreten" else "Join table"
	joinHint.Text = if lang == "de" then "Code vom Host eingeben:" else "Enter the host's code:"
	createBtn.Text = if lang == "de" then "Tisch erstellen" else "Create table"
	joinBtn.Text = if lang == "de" then "Beitreten" else "Join"
	quickBtn.Text = if lang == "de" then "⚡ Schnell spielen" else "⚡ Quick play"
	refreshSettingBtns()
	renderProfile(myProfile)
end

local function renderTable(view)
	if not view then
		return
	end
	local me = view.players[view.meIdx]

	-- Equity-Map (Sitzindex -> Prozent)
	local eqMap = {}
	if view.runout and view.equities then
		for _, e in view.equities do
			eqMap[e.i] = e.pct
		end
	end

	potLabel.Text = `Pot: {view.totalPot or 0} 🪙`

	-- Untertitel: Code + Blinds + Modus
	local sub = ""
	if view.code then
		sub = `Code {view.code}`
	end
	if view.blinds then
		sub ..= (if sub ~= "" then "   ·   " else "") .. `Blinds {view.blinds.sb}/{view.blinds.bb}`
		if view.blinds.tournament and view.blinds.level then
			sub ..= ` · Stufe {view.blinds.level}`
		end
	end
	if view.cash then
		sub ..= `   ·   💵 Buy-in {view.buyIn or 0}`
	end
	subHeader.Text = sub

	-- Community
	clear(community)
	for _, c in view.community do
		mkCard(community, c, false)
	end

	-- Stage / Zug
	local stageTxt = `Hand #{view.handNo or 0} — {tostring(view.stage)}`
	if view.waiting then
		if view.auto then
			stageTxt = if view.canStart
				then (if lang == "de" then "⏳ Spiel startet gleich…" else "⏳ Starting soon…")
				else (if lang == "de" then "Warte auf Gegner…" else "Waiting for opponents…")
		elseif view.youAreHost then
			stageTxt = if view.canStart
				then (if lang == "de" then "Bereit — starte die erste Hand!" else "Ready — start the first hand!")
				else (if lang == "de" then "Warte auf Mitspieler…" else "Waiting for players…")
		else
			stageTxt = if lang == "de" then "Warte auf den Host…" else "Waiting for the host…"
		end
	elseif view.matchOver then
		stageTxt = if view.matchWinnerId == (me and me.id)
			then "🏆 Du hast das Match gewonnen!"
			else "Match beendet."
	elseif view.runout then
		stageTxt = if lang == "de" then "🃏 All-In — Karten werden aufgedeckt…" else "🃏 All-in — running it out…"
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
		seat.Size = UDim2.new(0, 132, 0, 82)
		seat.BackgroundColor3 = if p.isMe then Color3.fromRGB(38, 48, 64) else COL_DARK
		seat.BorderSizePixel = 0
		seat.Parent = seatRow
		mkCorner(seat, 8)
		if p.id == view.toActId then
			local stroke = Instance.new("UIStroke")
			stroke.Color = COL_GOLD
			stroke.Thickness = 2
			stroke.Parent = seat
		end
		-- Avatar (Kopfbild) oben rechts
		local av = Instance.new("ImageLabel")
		av.Size = UDim2.new(0, 30, 0, 30)
		av.Position = UDim2.new(1, -34, 0, 3)
		av.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
		av.BorderSizePixel = 0
		av.Image = ""
		av.Parent = seat
		mkCorner(av, 15)
		loadAvatar(av, p.id)

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -42, 0, 18)
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
		if p.connected == false then
			tags ..= " ⚠"
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
		-- eigene Hole-Cards mini
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
		-- Equity-Anzeige waehrend des Run-outs
		if eqMap[p.seat] ~= nil then
			local eq = Instance.new("TextLabel")
			eq.Size = UDim2.new(1, -8, 0, 16)
			eq.Position = UDim2.new(0, 4, 0, 60)
			eq.BackgroundTransparency = 1
			eq.Font = Enum.Font.GothamBold
			eq.TextSize = 12
			eq.TextColor3 = Color3.fromRGB(120, 230, 150)
			eq.TextXAlignment = Enum.TextXAlignment.Left
			eq.Text = `≈ {eqMap[p.seat]}%`
			eq.Parent = seat
		end
	end

	-- Log (uebersetzt)
	clear(logFrame)
	for _, event in (view.log or {}) do
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

	-- Chat
	clear(chatList)
	for _, msg in (view.chat or {}) do
		local line = Instance.new("TextLabel")
		line.Size = UDim2.new(1, -16, 0, 16)
		line.BackgroundTransparency = 1
		line.Font = Enum.Font.Gotham
		line.TextSize = 13
		line.TextColor3 = Color3.fromRGB(210, 220, 235)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextWrapped = true
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.RichText = true
		local safeName = (msg.name or "?"):gsub("<", "&lt;")
		local safeText = (msg.text or ""):gsub("<", "&lt;")
		line.Text = `<b>{safeName}:</b> {safeText}`
		line.Parent = chatList
	end

	-- Aktionen
	local a = view.actions
	startBtn.Text = if lang == "de" then "Hand starten" else "Start hand"
	-- Auto-Tische (Quick-Play) starten ohne manuellen Knopf.
	startBtn.Visible = view.auto ~= true
		and view.youAreHost == true
		and view.betweenHands == true
		and not view.matchOver
	startBtn.Active = (not view.waiting) or view.canStart == true
	startBtn.AutoButtonColor = startBtn.Active
	startBtn.BackgroundColor3 = if startBtn.Active then Color3.fromRGB(40, 160, 90) else Color3.fromRGB(70, 90, 78)
	foldBtn.Visible = a ~= nil
	checkCallBtn.Visible = a ~= nil
	raiseBtn.Visible = a ~= nil and a.canRaise == true
	if a then
		checkCallBtn.Text = if a.canCall then `Call {a.toCall}` else "Check"
	end
	rebuyBtn.Visible = view.cash == true
		and view.betweenHands == true
		and (view.myStack or 0) < (view.buyIn or 0)

	if raiseState.open and not (a and a.canRaise) then
		closeRaisePanel()
	end
	minQuick.Text = "Min"
	potQuick.Text = "Pot"
	maxQuick.Text = "All-In"
	backQuick.Text = if lang == "de" then "Zurück" else "Back"
	confirmQuick.Text = if lang == "de" then "Erhöhen" else "Raise"
	chatSend.Text = if lang == "de" then "Senden" else "Send"
	if raiseState.open then
		refreshSlider()
	end
end

-- =====================================================================
-- ======================== AKTIONEN VERDRAHTEN ========================
-- =====================================================================
createBtn.Activated:Connect(function()
	lobbyError.Text = ""
	local ok, res = pcall(function()
		return CreateRoomFn:InvokeServer(settings)
	end)
	if not ok then
		lobbyError.Text = if lang == "de" then "Verbindungsfehler." else "Connection error."
	elseif res and res.error then
		lobbyError.Text = res.error
	end
	-- Erfolg: Server sendet automatisch die Tisch-Sicht (StateEvent).
end)

quickBtn.Activated:Connect(function()
	lobbyError.Text = ""
	quickBtn.Text = if lang == "de" then "Suche Tisch…" else "Finding table…"
	local ok, res = pcall(function()
		return QuickPlayFn:InvokeServer()
	end)
	quickBtn.Text = if lang == "de" then "⚡ Schnell spielen" else "⚡ Quick play"
	if not ok then
		lobbyError.Text = if lang == "de" then "Verbindungsfehler." else "Connection error."
	elseif res and res.error then
		lobbyError.Text = res.error
	end
	-- Erfolg: Server sendet automatisch die Tisch-Sicht (StateEvent).
end)

joinBtn.Activated:Connect(function()
	lobbyError.Text = ""
	local code = codeInput.Text
	if not code or #code == 0 then
		lobbyError.Text = if lang == "de" then "Bitte Code eingeben." else "Please enter a code."
		return
	end
	local ok, res = pcall(function()
		return JoinRoomFn:InvokeServer(code)
	end)
	if not ok then
		lobbyError.Text = if lang == "de" then "Verbindungsfehler." else "Connection error."
	elseif res and res.error then
		lobbyError.Text = res.error
	else
		codeInput.Text = ""
	end
end)

leaveBtn.Activated:Connect(function()
	LeaveRoomEvent:FireServer()
end)

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
	if raiseState.open then
		closeRaisePanel()
	else
		openRaisePanel()
	end
end)
rebuyBtn.Activated:Connect(function()
	RebuyEvent:FireServer()
end)

local function sendChat()
	local text = chatInput.Text
	if text and #text > 0 then
		ChatEvent:FireServer(text)
		chatInput.Text = ""
	end
end
chatSend.Activated:Connect(sendChat)
chatInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		sendChat()
	end
end)

langBtn.Activated:Connect(function()
	lang = if lang == "de" then "en" else "de"
	langBtn.Text = string.upper(lang)
	if currentScreen == "table" then
		renderTable(lastView)
	else
		renderLobby()
	end
end)

-- =====================================================================
-- ============================ ZUSTAND ================================
-- =====================================================================
StateEvent.OnClientEvent:Connect(function(view)
	if type(view) ~= "table" then
		return
	end
	if view.screen == "lobby" then
		myProfile = view.profile or myProfile
		showScreen("lobby")
		renderLobby()
		showDailyBonus(view.dailyBonus)
	elseif view.screen == "profile" then
		-- Profil-Update (z. B. nach Match-Ende) — Screen nicht wechseln.
		renderProfile(view.profile)
		if currentScreen == "lobby" then
			renderLobby()
		end
	else
		-- Tisch-Sicht
		lastView = view
		showScreen("table")
		renderTable(view)
	end
end)

renderLobby()
