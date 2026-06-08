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
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cards = require(Shared:WaitForChild("Cards"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = require(Shared:WaitForChild("Progression"))
local Monetization = require(Shared:WaitForChild("Monetization"))
local Quests = require(Shared:WaitForChild("Quests"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CreateRoomFn = Remotes:WaitForChild("CreateRoom")
local JoinRoomFn = Remotes:WaitForChild("JoinRoom")
local QuickPlayFn = Remotes:WaitForChild("QuickPlay")
local LeaveRoomEvent = Remotes:WaitForChild("LeaveRoom")
local StartHandEvent = Remotes:WaitForChild("StartHand")
local ActionEvent = Remotes:WaitForChild("Action")
local RebuyEvent = Remotes:WaitForChild("Rebuy")
local ChatEvent = Remotes:WaitForChild("Chat")
local TutorialDoneEvent = Remotes:WaitForChild("TutorialDone")
local EquipEvent = Remotes:WaitForChild("Equip")
local RefreshVipEvent = Remotes:WaitForChild("RefreshVip")
local ClaimQuestEvent = Remotes:WaitForChild("ClaimQuest")
local StateEvent = Remotes:WaitForChild("State")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lang = "de"
local lastView = nil
local myProfile = nil
local currentScreen = "lobby"

-- ---- Polish: Zustand fuer Animationen/Sounds ----
local prevCommunityLen = 0 -- wie viele Gemeinschaftskarten zuletzt lagen (nur neue animieren)
local potShown = 0 -- aktuell angezeigter Pot-Wert (fuer Count-up)
local prevYourTurn = false -- war ich letzten Frame schon am Zug? (Puls nur bei Wechsel)
local potCountGen = 0 -- Generations-Token fuer den Pot-Count-up
local winSoundPlayed = false -- Gewinn-Sound nur einmal pro Match abspielen

-- ---- Farb-/Stil-Konstanten ----
local COL_BG = Color3.fromRGB(13, 18, 24)
local COL_FELT = Color3.fromRGB(22, 70, 52)
local COL_CARD = Color3.fromRGB(244, 241, 232)
local COL_CARD_BACK = Color3.fromRGB(54, 70, 110)
local COL_TEXT = Color3.fromRGB(235, 235, 235)
local COL_DARK = Color3.fromRGB(28, 34, 44)
local COL_ACCENT = Color3.fromRGB(46, 120, 200)
local COL_GOLD = Color3.fromRGB(240, 195, 70)

-- Wandelt ein {r,g,b}-Tripel (aus Shared/Progression) in ein Color3.
local function rgbColor(triple): Color3
	if type(triple) == "table" and triple[1] then
		return Color3.fromRGB(triple[1], triple[2], triple[3])
	end
	return Color3.fromRGB(255, 255, 255)
end

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

-- Hilfe/Tutorial erneut öffnen (nur in der Lobby sichtbar)
local helpBtn = Instance.new("TextButton")
helpBtn.Size = UDim2.new(0, 32, 0, 32)
helpBtn.Position = UDim2.new(1, -110, 0, 16)
helpBtn.BackgroundColor3 = COL_DARK
helpBtn.TextColor3 = COL_GOLD
helpBtn.Font = Enum.Font.GothamBold
helpBtn.TextSize = 18
helpBtn.Text = "?"
helpBtn.Visible = false
helpBtn.Parent = root
local helpCorner = Instance.new("UICorner")
helpCorner.CornerRadius = UDim.new(0, 8)
helpCorner.Parent = helpBtn

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

-- ---- Sound-Manager ----
-- Asset-IDs leer lassen = stummes No-op. Trage hier eigene rbxassetid ein
-- (z.B. "rbxassetid://1234567"), um Effekte zu aktivieren. Ohne IDs schippt
-- alles sauber und tonlos.
local SOUND_IDS = {
	deal = "", -- Karte austeilen
	turn = "", -- du bist am Zug
	win = "", -- Hand/Match gewonnen
	chip = "", -- Pot/Einsatz
	click = "", -- Button-Klick
}
local sounds = {}
for name, id in SOUND_IDS do
	local s = Instance.new("Sound")
	s.Name = "sfx_" .. name
	s.SoundId = id
	s.Volume = 0.5
	s.Parent = SoundService
	sounds[name] = s
end
local function playSound(name)
	local s = sounds[name]
	if s and s.SoundId ~= "" then
		s:Play()
	end
end

-- ---- Animations-Helfer ----
-- Skaliert ein GuiObject von `from` auf 1 hoch (Einblend-/Puls-Effekt).
local function scaleIn(obj, from, duration)
	local sc = Instance.new("UIScale")
	sc.Scale = from
	sc.Parent = obj
	local tw = TweenService:Create(
		sc,
		TweenInfo.new(duration or 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	tw:Play()
	return sc
end

-- Kurzer Aufmerksamkeits-Puls (hoch und zurueck) auf einem Element.
local pulseGen = 0
local function pulse(obj)
	pulseGen += 1
	local myGen = pulseGen
	local existing = obj:FindFirstChildOfClass("UIScale")
	local sc = existing or Instance.new("UIScale")
	sc.Parent = obj
	local up = TweenService:Create(
		sc,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1.08 }
	)
	up:Play()
	up.Completed:Connect(function()
		if myGen ~= pulseGen then
			return
		end
		TweenService:Create(
			sc,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end)
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
profileStats.Size = UDim2.new(1, -20, 0, 22)
profileStats.Position = UDim2.new(0, 12, 0, 66)
profileStats.BackgroundTransparency = 1
profileStats.Font = Enum.Font.Gotham
profileStats.TextSize = 13
profileStats.TextColor3 = Color3.fromRGB(190, 200, 215)
profileStats.TextXAlignment = Enum.TextXAlignment.Left
profileStats.TextYAlignment = Enum.TextYAlignment.Top
profileStats.Text = ""
profileStats.Parent = profileCard

-- Level-Abzeichen (oben rechts auf der Profil-Karte).
local levelBadge = Instance.new("TextLabel")
levelBadge.Size = UDim2.new(0, 64, 0, 26)
levelBadge.Position = UDim2.new(1, -76, 0, 9)
levelBadge.BackgroundColor3 = COL_GOLD
levelBadge.Font = Enum.Font.GothamBold
levelBadge.TextSize = 14
levelBadge.TextColor3 = Color3.fromRGB(30, 26, 12)
levelBadge.Text = "Lv 1"
levelBadge.Parent = profileCard
mkCorner(levelBadge, 8)

-- XP-Fortschrittsbalken (unten auf der Profil-Karte).
local xpBarBg = Instance.new("Frame")
xpBarBg.Size = UDim2.new(1, -20, 0, 12)
xpBarBg.Position = UDim2.new(0, 12, 0, 96)
xpBarBg.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
xpBarBg.BorderSizePixel = 0
xpBarBg.Parent = profileCard
mkCorner(xpBarBg, 6)

local xpBarFill = Instance.new("Frame")
xpBarFill.Size = UDim2.new(0, 0, 1, 0)
xpBarFill.BackgroundColor3 = COL_GOLD
xpBarFill.BorderSizePixel = 0
xpBarFill.Parent = xpBarBg
mkCorner(xpBarFill, 6)

local xpBarText = Instance.new("TextLabel")
xpBarText.Size = UDim2.new(1, 0, 1, 0)
xpBarText.BackgroundTransparency = 1
xpBarText.Font = Enum.Font.GothamBold
xpBarText.TextSize = 10
xpBarText.TextColor3 = COL_TEXT
xpBarText.Text = ""
xpBarText.Parent = xpBarBg

-- "Anpassen" (Kosmetik) — oeffnet das Kosmetik-Menue.
local customizeBtn = Instance.new("TextButton")
customizeBtn.Size = UDim2.new(0, 96, 0, 40)
customizeBtn.Position = UDim2.new(0.5, 216, 0, 50)
customizeBtn.BackgroundColor3 = COL_DARK
customizeBtn.TextColor3 = COL_GOLD
customizeBtn.Font = Enum.Font.GothamBold
customizeBtn.TextSize = 15
customizeBtn.Text = "🎨 Anpassen"
customizeBtn.Parent = lobbyScreen
mkCorner(customizeBtn, 10)

-- "Shop" — Chip-Pakete & VIP (reine Spass-Chips/Optik, kein Echtgeldwert).
local shopBtn = Instance.new("TextButton")
shopBtn.Size = UDim2.new(0, 96, 0, 40)
shopBtn.Position = UDim2.new(0.5, -312, 0, 50)
shopBtn.BackgroundColor3 = COL_GOLD
shopBtn.TextColor3 = Color3.fromRGB(30, 26, 12)
shopBtn.Font = Enum.Font.GothamBold
shopBtn.TextSize = 15
shopBtn.Text = "🛒 Shop"
shopBtn.Parent = lobbyScreen
mkCorner(shopBtn, 10)

-- "Quests" — taegliche Mini-Ziele mit Chip-/XP-Belohnung (Retention-Hebel).
local questBtn = Instance.new("TextButton")
questBtn.Size = UDim2.new(0, 96, 0, 40)
questBtn.Position = UDim2.new(0.5, -312, 0, 98)
questBtn.BackgroundColor3 = COL_ACCENT
questBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
questBtn.Font = Enum.Font.GothamBold
questBtn.TextSize = 15
questBtn.Text = "🎯 Quests"
questBtn.Parent = lobbyScreen
mkCorner(questBtn, 10)

-- Roter Hinweis-Punkt mit Anzahl abholbereiter Quests (oben rechts am Knopf).
-- Als Kind von questBtn (kein eigener Top-Level-Local — Register sparen).
do
	local questBadge = Instance.new("TextLabel")
	questBadge.Name = "QuestBadge"
	questBadge.Size = UDim2.new(0, 20, 0, 20)
	questBadge.Position = UDim2.new(1, -10, 0, -8)
	questBadge.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	questBadge.Font = Enum.Font.GothamBold
	questBadge.TextSize = 12
	questBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	questBadge.Text = "0"
	questBadge.Visible = false
	questBadge.ZIndex = 5
	questBadge.Parent = questBtn
	mkCorner(questBadge, 10).CornerRadius = UDim.new(1, 0)
end

-- ---- Schnell spielen (Matchmaking) ----
local quickBtn = Instance.new("TextButton")
quickBtn.Size = UDim2.new(0, 860, 0, 56)
quickBtn.Position = UDim2.new(0.5, -430, 0, 196)
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
createCard.Position = UDim2.new(0.5, -430, 0, 268)
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
joinCard.Position = UDim2.new(0.5, 10, 0, 268)
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
lobbyError.Position = UDim2.new(0.5, -430, 0, 538)
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
local function showToast(text)
	dailyToast.Text = text
	dailyToast.Visible = true
	toastGen += 1
	local gen = toastGen
	task.delay(6, function()
		if toastGen == gen then
			dailyToast.Visible = false
		end
	end)
end

local function showDailyBonus(b)
	if not (b and b.granted) then
		return
	end
	local vipTag = if b.vip then " 👑x2" else ""
	showToast(if lang == "de"
		then `🎁 Täglicher Bonus: +{b.amount} 🪙{vipTag}   ·   Serie {b.streak} Tag(e)`
		else `🎁 Daily bonus: +{b.amount} 🪙{vipTag}   ·   Streak {b.streak} day(s)`)
end

-- Kauf-Bestaetigung (Chips gutgeschrieben) — wiederverwendet den Toast.
local function showPurchaseToast(chips)
	showToast(if lang == "de"
		then `✅ Kauf erfolgreich: +{chips} 🪙 gutgeschrieben`
		else `✅ Purchase complete: +{chips} 🪙 added`)
end

-- Quest-Belohnung abgeholt — wiederverwendet den Toast.
local function showQuestRewardToast(r)
	local xpPart = if r.xp and r.xp > 0 then ` · +{r.xp} XP` else ""
	showToast(if lang == "de"
		then `🎯 Quest abgeschlossen: +{r.chips} 🪙{xpPart}`
		else `🎯 Quest complete: +{r.chips} 🪙{xpPart}`)
end

-- Saison-Belohnung (beim Saison-Wechsel gutgeschrieben) — wiederverwendet den Toast.
local function showSeasonRewardToast(r)
	if not (r and r.chips) then
		return
	end
	local tierName = if lang == "de" then (r.name or "") else (r.nameEn or r.name or "")
	local xpPart = if r.xp and r.xp > 0 then ` · +{r.xp} XP` else ""
	showToast(if lang == "de"
		then `🏆 Saison-Belohnung ({tierName}): +{r.chips} 🪙{xpPart}`
		else `🏆 Season reward ({tierName}): +{r.chips} 🪙{xpPart}`)
end

-- Formatiert eine Restdauer (Sekunden) kompakt: "3T 4Std" / "3d 4h" bzw. "5Min".
local function fmtDuration(sec)
	sec = math.max(0, math.floor(tonumber(sec) or 0))
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	if lang == "de" then
		if d > 0 then
			return `{d}T {h}Std`
		elseif h > 0 then
			return `{h}Std {m}Min`
		else
			return `{m}Min`
		end
	else
		if d > 0 then
			return `{d}d {h}h`
		elseif h > 0 then
			return `{h}h {m}m`
		else
			return `{m}m`
		end
	end
end

-- =====================================================================
-- ===================== EINSTEIGER-TUTORIAL ==========================
-- =====================================================================
-- Eine kurze, geblätterte Einführung für Poker-Neulinge. Wird beim ersten
-- Login automatisch gezeigt (Server-Flag tutorialDone) und kann jederzeit
-- über das "?"-Symbol erneut geöffnet werden.
local TUTORIAL_STEPS = {
	{
		emoji = "🐄",
		titleDe = "Willkommen bei KuhPoker!",
		titleEn = "Welcome to KuhPoker!",
		bodyDe = "Das ist Texas Hold'em — aber mit Tierkarten statt Spielkarten. Ziel: Bilde aus deinen Karten und den Tischkarten die beste Pokerhand und gewinne den Pot (die Chips in der Mitte).",
		bodyEn = "This is Texas Hold'em — but with animal cards instead of a standard deck. Goal: make the best poker hand from your cards plus the table cards and win the pot (the chips in the middle).",
	},
	{
		emoji = "🃏",
		titleDe = "Deine Karten",
		titleEn = "Your cards",
		bodyDe = "Zu Beginn jeder Hand bekommst du 2 verdeckte Karten — nur du siehst sie. Ganz wichtig: Höhere Tiere sind stärker (🐓 Hahn = niedrig … 🐎 Pferd = hoch). Es gibt keine Farben, also auch keinen Flush.",
		bodyEn = "Each hand you get 2 face-down cards — only you see them. Higher animals are stronger (🐓 Rooster = low … 🐎 Horse = high). There are no suits, so no flush.",
	},
	{
		emoji = "🂠",
		titleDe = "Die Tischkarten",
		titleEn = "The table cards",
		bodyDe = "In der Mitte werden nach und nach 5 offene Karten aufgedeckt: erst 3 (Flop), dann 1 (Turn), dann 1 (River). Sie gelten für ALLE Spieler. Deine beste 5-Karten-Kombination aus deinen 2 + diesen 5 zählt.",
		bodyEn = "Five face-up cards are revealed over time: first 3 (flop), then 1 (turn), then 1 (river). They are shared by ALL players. Your best 5-card combo from your 2 + these 5 counts.",
	},
	{
		emoji = "🎯",
		titleDe = "Deine Aktionen",
		titleEn = "Your actions",
		bodyDe = "Bist du am Zug, kannst du: CHECK/CALL (mitgehen, kostenlos oder Einsatz bezahlen), RAISE (erhöhen, Druck machen) oder FOLD (aussteigen, Hand wegwerfen). Tipp: Steige aus, wenn deine Hand schwach ist — du verlierst dann nur wenig.",
		bodyEn = "On your turn you can: CHECK/CALL (stay in, free or match the bet), RAISE (increase the bet) or FOLD (give up the hand). Tip: fold weak hands — you only lose a little.",
	},
	{
		emoji = "⚡",
		titleDe = "Los geht's!",
		titleEn = "Let's go!",
		bodyDe = "Drück „⚡ Schnell spielen\", um sofort an einem Tisch zu landen — gegen echte Spieler und KI-Gegner. Du startest mit Spiel-Chips; geht dir das Guthaben aus, füllen wir es wieder auf. Viel Erfolg!",
		bodyEn = "Hit \"⚡ Quick play\" to jump straight into a table — against real players and AI opponents. You start with play chips; if you run out, we top you up. Good luck!",
	},
}

local tutorialOverlay = Instance.new("Frame")
tutorialOverlay.Size = UDim2.new(1, 0, 1, 0)
tutorialOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
tutorialOverlay.BackgroundTransparency = 0.25
tutorialOverlay.BorderSizePixel = 0
tutorialOverlay.Visible = false
tutorialOverlay.ZIndex = 100
tutorialOverlay.Parent = root

local tutCard = Instance.new("Frame")
tutCard.Size = UDim2.new(0, 560, 0, 420)
tutCard.Position = UDim2.new(0.5, -280, 0.5, -210)
tutCard.BackgroundColor3 = COL_DARK
tutCard.BorderSizePixel = 0
tutCard.ZIndex = 101
tutCard.Parent = tutorialOverlay
mkCorner(tutCard, 16)
local tutStroke = Instance.new("UIStroke")
tutStroke.Color = COL_GOLD
tutStroke.Thickness = 2
tutStroke.Parent = tutCard

local tutEmoji = Instance.new("TextLabel")
tutEmoji.Size = UDim2.new(1, 0, 0, 72)
tutEmoji.Position = UDim2.new(0, 0, 0, 26)
tutEmoji.BackgroundTransparency = 1
tutEmoji.Text = "🐄"
tutEmoji.TextSize = 56
tutEmoji.ZIndex = 102
tutEmoji.Parent = tutCard

local tutTitle = Instance.new("TextLabel")
tutTitle.Size = UDim2.new(1, -48, 0, 32)
tutTitle.Position = UDim2.new(0, 24, 0, 102)
tutTitle.BackgroundTransparency = 1
tutTitle.Font = Enum.Font.GothamBold
tutTitle.TextSize = 22
tutTitle.TextColor3 = COL_GOLD
tutTitle.Text = ""
tutTitle.ZIndex = 102
tutTitle.Parent = tutCard

local tutBody = Instance.new("TextLabel")
tutBody.Size = UDim2.new(1, -64, 0, 170)
tutBody.Position = UDim2.new(0, 32, 0, 142)
tutBody.BackgroundTransparency = 1
tutBody.Font = Enum.Font.Gotham
tutBody.TextSize = 17
tutBody.TextColor3 = COL_TEXT
tutBody.TextWrapped = true
tutBody.TextYAlignment = Enum.TextYAlignment.Top
tutBody.Text = ""
tutBody.ZIndex = 102
tutBody.Parent = tutCard

-- Fortschritts-Punkte
local tutDots = Instance.new("Frame")
tutDots.Size = UDim2.new(0, 200, 0, 12)
tutDots.Position = UDim2.new(0.5, -100, 1, -78)
tutDots.BackgroundTransparency = 1
tutDots.ZIndex = 102
tutDots.Parent = tutCard
local tutDotsLayout = Instance.new("UIListLayout")
tutDotsLayout.FillDirection = Enum.FillDirection.Horizontal
tutDotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tutDotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tutDotsLayout.Padding = UDim.new(0, 8)
tutDotsLayout.Parent = tutDots
local tutDotObjs = {}
for i = 1, #TUTORIAL_STEPS do
	local d = Instance.new("Frame")
	d.Size = UDim2.new(0, 10, 0, 10)
	d.BackgroundColor3 = Color3.fromRGB(90, 100, 120)
	d.BorderSizePixel = 0
	d.ZIndex = 102
	d.LayoutOrder = i
	d.Parent = tutDots
	mkCorner(d, 5).CornerRadius = UDim.new(1, 0)
	tutDotObjs[i] = d
end

local function mkTutBtn(text, w, x, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 40)
	b.Position = UDim2.new(0, x, 1, -56)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = text
	b.ZIndex = 103
	b.Parent = tutCard
	mkCorner(b, 10)
	return b
end

local tutBackBtn = mkTutBtn("Zurück", 120, 24, Color3.fromRGB(60, 70, 88))
local tutNextBtn = mkTutBtn("Weiter", 160, 376, Color3.fromRGB(40, 160, 90))

-- "Überspringen"-Kreuz oben rechts
local tutSkipBtn = Instance.new("TextButton")
tutSkipBtn.Size = UDim2.new(0, 36, 0, 36)
tutSkipBtn.Position = UDim2.new(1, -44, 0, 12)
tutSkipBtn.BackgroundTransparency = 1
tutSkipBtn.Font = Enum.Font.GothamBold
tutSkipBtn.TextSize = 24
tutSkipBtn.TextColor3 = Color3.fromRGB(150, 160, 175)
tutSkipBtn.Text = "✕"
tutSkipBtn.ZIndex = 103
tutSkipBtn.Parent = tutCard

local tutStep = 1
local tutorialShownThisSession = false

local function renderTutStep()
	local s = TUTORIAL_STEPS[tutStep]
	if not s then
		return
	end
	tutEmoji.Text = s.emoji
	tutTitle.Text = if lang == "de" then s.titleDe else s.titleEn
	tutBody.Text = if lang == "de" then s.bodyDe else s.bodyEn
	tutBackBtn.Visible = tutStep > 1
	local last = tutStep >= #TUTORIAL_STEPS
	tutNextBtn.Text = if last
		then (if lang == "de" then "Los geht's! ⚡" else "Let's go! ⚡")
		else (if lang == "de" then "Weiter" else "Next")
	tutSkipBtn.Visible = not last
	for i, d in tutDotObjs do
		d.BackgroundColor3 = if i == tutStep then COL_GOLD else Color3.fromRGB(90, 100, 120)
	end
end

local function hideTutorial()
	tutorialOverlay.Visible = false
end

local function finishTutorial()
	hideTutorial()
	-- Flag dauerhaft setzen (idempotent serverseitig).
	pcall(function()
		TutorialDoneEvent:FireServer()
	end)
end

local function showTutorial()
	tutStep = 1
	renderTutStep()
	tutorialOverlay.Visible = true
	scaleIn(tutCard, 0.8, 0.22)
end

tutNextBtn.Activated:Connect(function()
	if tutStep >= #TUTORIAL_STEPS then
		finishTutorial()
	else
		tutStep += 1
		renderTutStep()
	end
end)
tutBackBtn.Activated:Connect(function()
	if tutStep > 1 then
		tutStep -= 1
		renderTutStep()
	end
end)
tutSkipBtn.Activated:Connect(finishTutorial)
helpBtn.Activated:Connect(showTutorial)

-- =====================================================================
-- ====================== KOSMETIK-MENUE (Overlay) =====================
-- Freischaltbare Looks (Kartenrueckseiten, Tisch-Themen, Avatar-Rahmen).
-- Rein optisch — per Level freigeschaltet (kein Pay-to-Win, kein Gluecksspiel).

local COSMETIC_ROWS = {
	{ key = "cardBack", de = "Kartenrückseite", en = "Card back" },
	{ key = "tableTheme", de = "Tisch-Thema", en = "Table theme" },
	{ key = "avatarFrame", de = "Avatar-Rahmen", en = "Avatar frame" },
}

local cosmeticsOverlay = Instance.new("Frame")
cosmeticsOverlay.Size = UDim2.new(1, 0, 1, 0)
cosmeticsOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
cosmeticsOverlay.BackgroundTransparency = 0.25
cosmeticsOverlay.BorderSizePixel = 0
cosmeticsOverlay.Visible = false
cosmeticsOverlay.ZIndex = 100
cosmeticsOverlay.Parent = root

local cosCard = Instance.new("Frame")
cosCard.Size = UDim2.new(0, 660, 0, 470)
cosCard.Position = UDim2.new(0.5, -330, 0.5, -235)
cosCard.BackgroundColor3 = COL_DARK
cosCard.BorderSizePixel = 0
cosCard.ZIndex = 101
cosCard.Parent = cosmeticsOverlay
mkCorner(cosCard, 16)
local cosStroke = Instance.new("UIStroke")
cosStroke.Color = COL_GOLD
cosStroke.Thickness = 2
cosStroke.Parent = cosCard

local cosTitle = Instance.new("TextLabel")
cosTitle.Size = UDim2.new(1, -48, 0, 34)
cosTitle.Position = UDim2.new(0, 24, 0, 18)
cosTitle.BackgroundTransparency = 1
cosTitle.Font = Enum.Font.GothamBold
cosTitle.TextSize = 24
cosTitle.TextColor3 = COL_GOLD
cosTitle.TextXAlignment = Enum.TextXAlignment.Left
cosTitle.Text = "🎨 Anpassen"
cosTitle.ZIndex = 102
cosTitle.Parent = cosCard

local cosHint = Instance.new("TextLabel")
cosHint.Size = UDim2.new(1, -48, 0, 18)
cosHint.Position = UDim2.new(0, 24, 0, 50)
cosHint.BackgroundTransparency = 1
cosHint.Font = Enum.Font.Gotham
cosHint.TextSize = 13
cosHint.TextColor3 = Color3.fromRGB(170, 180, 195)
cosHint.TextXAlignment = Enum.TextXAlignment.Left
cosHint.Text = ""
cosHint.ZIndex = 102
cosHint.Parent = cosCard

local cosClose = Instance.new("TextButton")
cosClose.Size = UDim2.new(0, 36, 0, 36)
cosClose.Position = UDim2.new(1, -44, 0, 14)
cosClose.BackgroundTransparency = 1
cosClose.Font = Enum.Font.GothamBold
cosClose.TextSize = 24
cosClose.TextColor3 = Color3.fromRGB(150, 160, 175)
cosClose.Text = "✕"
cosClose.ZIndex = 103
cosClose.Parent = cosCard

-- Pro Kategorie: Beschriftung + horizontaler Streifen mit Farb-Kacheln.
local cosSwatchHolders = {} -- [category] = Frame (Container der Kacheln)
for i, row in COSMETIC_ROWS do
	local yTop = 84 + (i - 1) * 122
	local rowLabel = Instance.new("TextLabel")
	rowLabel.Size = UDim2.new(1, -48, 0, 20)
	rowLabel.Position = UDim2.new(0, 24, 0, yTop)
	rowLabel.BackgroundTransparency = 1
	rowLabel.Font = Enum.Font.GothamBold
	rowLabel.TextSize = 15
	rowLabel.TextColor3 = COL_TEXT
	rowLabel.TextXAlignment = Enum.TextXAlignment.Left
	rowLabel.Text = if lang == "de" then row.de else row.en
	rowLabel.ZIndex = 102
	rowLabel.Name = "Label_" .. row.key
	rowLabel.Parent = cosCard

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -48, 0, 88)
	holder.Position = UDim2.new(0, 24, 0, yTop + 22)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 102
	holder.Parent = cosCard
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	hl.Padding = UDim.new(0, 10)
	hl.Parent = holder
	cosSwatchHolders[row.key] = holder
end

local cosmeticsShown = false

-- Baut die Kacheln einer Kategorie neu auf (Farbe, Name, Schloss, Auswahl).
local function renderCosmetics()
	local prof = myProfile or {}
	local level = Progression.levelFromXp(prof.xp or 0)
	cosTitle.Text = if lang == "de" then "🎨 Anpassen" else "🎨 Customize"
	cosHint.Text = if lang == "de"
		then `Level {level} · steige im Level auf, um mehr freizuschalten`
		else `Level {level} · level up to unlock more`
	for _, row in COSMETIC_ROWS do
		local holder = cosSwatchHolders[row.key]
		-- Vorhandene Kacheln entfernen (Layout behalten).
		for _, ch in holder:GetChildren() do
			if ch:IsA("TextButton") then
				ch:Destroy()
			end
		end
		local label = cosCard:FindFirstChild("Label_" .. row.key)
		if label then
			label.Text = if lang == "de" then row.de else row.en
		end
		local equippedId = prof[row.key] or Progression.defaultId(row.key)
		for j, item in Progression.catalog(row.key) do
			local unlocked = Progression.isUnlocked(level, row.key, item.id, prof.vip == true)
			local tile = Instance.new("TextButton")
			tile.Size = UDim2.new(0, 84, 0, 84)
			tile.BackgroundColor3 = rgbColor(item.color)
			tile.AutoButtonColor = unlocked
			tile.Text = ""
			tile.LayoutOrder = j
			tile.ZIndex = 103
			tile.Parent = holder
			mkCorner(tile, 10)
			if not unlocked then
				tile.BackgroundTransparency = 0.45
			end
			-- Auswahl-Rahmen (gold) fuer das aktuell getragene Item.
			if item.id == equippedId then
				local sel = Instance.new("UIStroke")
				sel.Color = COL_GOLD
				sel.Thickness = 3
				sel.Parent = tile
			end
			-- Name unten auf der Kachel.
			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -4, 0, 16)
			nm.Position = UDim2.new(0, 2, 1, -18)
			nm.BackgroundTransparency = 1
			nm.Font = Enum.Font.GothamBold
			nm.TextSize = 11
			nm.TextColor3 = Color3.fromRGB(255, 255, 255)
			nm.TextStrokeTransparency = 0.4
			nm.Text = if lang == "de" then item.name else item.nameEn
			nm.ZIndex = 104
			nm.Parent = tile
			-- Schloss + benoetigtes Level fuer gesperrte Items.
			if not unlocked then
				local lock = Instance.new("TextLabel")
				lock.Size = UDim2.new(1, 0, 0, 28)
				lock.Position = UDim2.new(0, 0, 0, 14)
				lock.BackgroundTransparency = 1
				lock.Font = Enum.Font.GothamBold
				lock.TextSize = 13
				lock.TextColor3 = Color3.fromRGB(255, 255, 255)
				lock.TextStrokeTransparency = 0.3
				lock.Text = if item.vip then "🔒 VIP" else `🔒 Lvl {item.level}`
				lock.ZIndex = 104
				lock.Parent = tile
			end
			if unlocked then
				local catKey, itemId = row.key, item.id
				tile.Activated:Connect(function()
					if (myProfile and myProfile[catKey]) == itemId then
						return
					end
					playSound("click")
					if myProfile then
						myProfile[catKey] = itemId -- optimistisch
					end
					pcall(function()
						EquipEvent:FireServer(catKey, itemId)
					end)
					renderCosmetics()
				end)
			end
		end
	end
end

local function showCosmetics()
	cosmeticsShown = true
	renderCosmetics()
	cosmeticsOverlay.Visible = true
	scaleIn(cosCard, 0.85, 0.2)
end

local function hideCosmetics()
	cosmeticsShown = false
	cosmeticsOverlay.Visible = false
end

cosClose.Activated:Connect(hideCosmetics)
customizeBtn.Activated:Connect(showCosmetics)

-- =====================================================================
-- ============================ SHOP (Overlay) =========================
-- Chip-Pakete (Developer Products) + VIP (Game Pass). Reine Spass-Chips/
-- Optik — kein Echtgeldwert, keine Auszahlung, keine Zufalls-Lootboxen.
-- Nicht konfigurierte Eintraege (Asset-Id 0) werden ausgeblendet.
-- In einen do-Block gekapselt (Register-Limit der Hauptfunktion schonen).

local shopShown = false
local renderShop
local hideShop
do
	local shopOverlay = Instance.new("Frame")
shopOverlay.Size = UDim2.new(1, 0, 1, 0)
shopOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
shopOverlay.BackgroundTransparency = 0.25
shopOverlay.BorderSizePixel = 0
shopOverlay.Visible = false
shopOverlay.ZIndex = 100
shopOverlay.Parent = root

local shopCard = Instance.new("Frame")
shopCard.Size = UDim2.new(0, 560, 0, 500)
shopCard.Position = UDim2.new(0.5, -280, 0.5, -250)
shopCard.BackgroundColor3 = COL_DARK
shopCard.BorderSizePixel = 0
shopCard.ZIndex = 101
shopCard.Parent = shopOverlay
mkCorner(shopCard, 16)
local shopStroke = Instance.new("UIStroke")
shopStroke.Color = COL_GOLD
shopStroke.Thickness = 2
shopStroke.Parent = shopCard

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, -48, 0, 34)
shopTitle.Position = UDim2.new(0, 24, 0, 18)
shopTitle.BackgroundTransparency = 1
shopTitle.Font = Enum.Font.GothamBold
shopTitle.TextSize = 24
shopTitle.TextColor3 = COL_GOLD
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Text = "🛒 Shop"
shopTitle.ZIndex = 102
shopTitle.Parent = shopCard

local shopHint = Instance.new("TextLabel")
shopHint.Size = UDim2.new(1, -48, 0, 16)
shopHint.Position = UDim2.new(0, 24, 0, 50)
shopHint.BackgroundTransparency = 1
shopHint.Font = Enum.Font.Gotham
shopHint.TextSize = 12
shopHint.TextColor3 = Color3.fromRGB(150, 160, 175)
shopHint.TextXAlignment = Enum.TextXAlignment.Left
shopHint.Text = ""
shopHint.ZIndex = 102
shopHint.Parent = shopCard

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.Position = UDim2.new(1, -44, 0, 14)
shopClose.BackgroundTransparency = 1
shopClose.Font = Enum.Font.GothamBold
shopClose.TextSize = 24
shopClose.TextColor3 = Color3.fromRGB(150, 160, 175)
shopClose.Text = "✕"
shopClose.ZIndex = 103
shopClose.Parent = shopCard

-- Scroll-Bereich fuer die Angebote (falls viele Pakete).
local shopList = Instance.new("ScrollingFrame")
shopList.Size = UDim2.new(1, -32, 1, -92)
shopList.Position = UDim2.new(0, 16, 0, 76)
shopList.BackgroundTransparency = 1
shopList.BorderSizePixel = 0
shopList.ScrollBarThickness = 6
shopList.CanvasSize = UDim2.new(0, 0, 0, 0)
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.ZIndex = 102
shopList.Parent = shopCard
local shopLayout = Instance.new("UIListLayout")
shopLayout.FillDirection = Enum.FillDirection.Vertical
shopLayout.Padding = UDim.new(0, 10)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopList

-- Baut die Angebotsliste neu auf (nur konfigurierte Eintraege, VIP-Status).
function renderShop()
	local prof = myProfile or {}
	shopTitle.Text = if lang == "de" then "🛒 Shop" else "🛒 Shop"
	shopHint.Text = if lang == "de"
		then "Spass-Chips & Optik · kein Echtgeldwert"
		else "Play chips & looks · no real-world value"
	for _, ch in shopList:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	local order = 0
	local anyOffer = false

	-- VIP-Karte (falls Pass konfiguriert).
	if Monetization.vipAvailable() then
		anyOffer = true
		order += 1
		local vip = Monetization.VIP
		local owned = prof.vip == true
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 150)
		card.BackgroundColor3 = Color3.fromRGB(46, 36, 64)
		card.BorderSizePixel = 0
		card.LayoutOrder = order
		card.ZIndex = 102
		card.Parent = shopList
		mkCorner(card, 12)
		local vs = Instance.new("UIStroke")
		vs.Color = COL_GOLD
		vs.Thickness = 2
		vs.Parent = card
		local vt = Instance.new("TextLabel")
		vt.Size = UDim2.new(1, -120, 0, 26)
		vt.Position = UDim2.new(0, 14, 0, 10)
		vt.BackgroundTransparency = 1
		vt.Font = Enum.Font.GothamBold
		vt.TextSize = 19
		vt.TextColor3 = COL_GOLD
		vt.TextXAlignment = Enum.TextXAlignment.Left
		vt.Text = `{vip.tag} VIP`
		vt.ZIndex = 103
		vt.Parent = card
		local perks = if lang == "de" then vip.perks else vip.perksEn
		local pl = Instance.new("TextLabel")
		pl.Size = UDim2.new(1, -28, 0, 78)
		pl.Position = UDim2.new(0, 14, 0, 40)
		pl.BackgroundTransparency = 1
		pl.Font = Enum.Font.Gotham
		pl.TextSize = 14
		pl.TextColor3 = COL_TEXT
		pl.TextXAlignment = Enum.TextXAlignment.Left
		pl.TextYAlignment = Enum.TextYAlignment.Top
		pl.Text = table.concat(perks, "\n")
		pl.ZIndex = 103
		pl.Parent = card
		local buy = Instance.new("TextButton")
		buy.Size = UDim2.new(0, 150, 0, 36)
		buy.Position = UDim2.new(1, -164, 1, -46)
		buy.BackgroundColor3 = if owned then Color3.fromRGB(60, 70, 88) else COL_GOLD
		buy.TextColor3 = if owned then COL_TEXT else Color3.fromRGB(30, 26, 12)
		buy.Font = Enum.Font.GothamBold
		buy.TextSize = 15
		buy.AutoButtonColor = not owned
		buy.Text = if owned
			then (if lang == "de" then "✓ Du bist VIP" else "✓ You're VIP")
			else `R$ {vip.robux}`
		buy.ZIndex = 103
		buy.Parent = card
		mkCorner(buy, 8)
		if not owned then
			buy.Activated:Connect(function()
				playSound("click")
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, vip.passId)
				end)
			end)
		end
	end

	-- Chip-Pakete.
	for _, pack in Monetization.CHIP_PACKS do
		if Monetization.packAvailable(pack) then
			anyOffer = true
			order += 1
			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, -8, 0, 66)
			card.BackgroundColor3 = Color3.fromRGB(38, 44, 56)
			card.BorderSizePixel = 0
			card.LayoutOrder = order
			card.ZIndex = 102
			card.Parent = shopList
			mkCorner(card, 12)
			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -160, 0, 24)
			nm.Position = UDim2.new(0, 14, 0, 10)
			nm.BackgroundTransparency = 1
			nm.Font = Enum.Font.GothamBold
			nm.TextSize = 16
			nm.TextColor3 = COL_TEXT
			nm.TextXAlignment = Enum.TextXAlignment.Left
			nm.Text = if lang == "de" then pack.name else pack.nameEn
			nm.ZIndex = 103
			nm.Parent = card
			local amt = Instance.new("TextLabel")
			amt.Size = UDim2.new(1, -160, 0, 20)
			amt.Position = UDim2.new(0, 14, 0, 34)
			amt.BackgroundTransparency = 1
			amt.Font = Enum.Font.GothamBold
			amt.TextSize = 15
			amt.TextColor3 = COL_GOLD
			amt.TextXAlignment = Enum.TextXAlignment.Left
			amt.Text = `🪙 {pack.chips}`
			amt.ZIndex = 103
			amt.Parent = card
			local buy = Instance.new("TextButton")
			buy.Size = UDim2.new(0, 130, 0, 40)
			buy.Position = UDim2.new(1, -144, 0.5, -20)
			buy.BackgroundColor3 = COL_GOLD
			buy.TextColor3 = Color3.fromRGB(30, 26, 12)
			buy.Font = Enum.Font.GothamBold
			buy.TextSize = 15
			buy.Text = `R$ {pack.robux}`
			buy.ZIndex = 103
			buy.Parent = card
			mkCorner(buy, 8)
			local productId = pack.productId
			buy.Activated:Connect(function()
				playSound("click")
				pcall(function()
					MarketplaceService:PromptProductPurchase(player, productId)
				end)
			end)
		end
	end

	-- Keine Angebote konfiguriert -> Hinweis (Setup im Roblox-Dashboard noetig).
	if not anyOffer then
		local note = Instance.new("TextLabel")
		note.Size = UDim2.new(1, -16, 0, 80)
		note.BackgroundTransparency = 1
		note.Font = Enum.Font.Gotham
		note.TextSize = 15
		note.TextColor3 = Color3.fromRGB(170, 180, 195)
		note.TextWrapped = true
		note.LayoutOrder = 1
		note.ZIndex = 103
		note.Text = if lang == "de"
			then "Der Shop wird bald freigeschaltet. 🐄"
			else "The shop opens soon. 🐄"
		note.Parent = shopList
	end
end

local function showShop()
	shopShown = true
	renderShop()
	shopOverlay.Visible = true
	scaleIn(shopCard, 0.85, 0.2)
end

function hideShop()
	shopShown = false
	shopOverlay.Visible = false
end

shopClose.Activated:Connect(hideShop)
shopBtn.Activated:Connect(showShop)
end -- do (Shop-Overlay)

-- Nach einem VIP-Kauf den Pass-Status serverseitig neu pruefen lassen.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, purchased)
	if purchased and Monetization.vipAvailable() and passId == Monetization.VIP.passId then
		pcall(function()
			RefreshVipEvent:FireServer()
		end)
	end
end)

-- =====================================================================
-- =========================== QUESTS (Overlay) ========================
-- Taegliche Mini-Ziele mit Chip-/XP-Belohnung. Reine Spass-Chips/XP — kein
-- Echtgeldwert, kein Gluecksspiel. Fortschritt kommt vom Server (im Profil).
-- In einen do-Block gekapselt, damit die UI-Locals nicht das 200er-Register-
-- Limit der Hauptfunktion sprengen (nur die noetigen Namen leben ausserhalb).

local questsShown = false
local renderQuests
local hideQuests
do
	local questOverlay = Instance.new("Frame")
questOverlay.Size = UDim2.new(1, 0, 1, 0)
questOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
questOverlay.BackgroundTransparency = 0.25
questOverlay.BorderSizePixel = 0
questOverlay.Visible = false
questOverlay.ZIndex = 100
questOverlay.Parent = root

local questCard = Instance.new("Frame")
questCard.Size = UDim2.new(0, 560, 0, 470)
questCard.Position = UDim2.new(0.5, -280, 0.5, -235)
questCard.BackgroundColor3 = COL_DARK
questCard.BorderSizePixel = 0
questCard.ZIndex = 101
questCard.Parent = questOverlay
mkCorner(questCard, 16)
local questStroke = Instance.new("UIStroke")
questStroke.Color = COL_GOLD
questStroke.Thickness = 2
questStroke.Parent = questCard

local questTitle = Instance.new("TextLabel")
questTitle.Size = UDim2.new(1, -48, 0, 34)
questTitle.Position = UDim2.new(0, 24, 0, 18)
questTitle.BackgroundTransparency = 1
questTitle.Font = Enum.Font.GothamBold
questTitle.TextSize = 24
questTitle.TextColor3 = COL_GOLD
questTitle.TextXAlignment = Enum.TextXAlignment.Left
questTitle.Text = "🎯 Tagesquests"
questTitle.ZIndex = 102
questTitle.Parent = questCard

local questHint = Instance.new("TextLabel")
questHint.Size = UDim2.new(1, -48, 0, 16)
questHint.Position = UDim2.new(0, 24, 0, 50)
questHint.BackgroundTransparency = 1
questHint.Font = Enum.Font.Gotham
questHint.TextSize = 12
questHint.TextColor3 = Color3.fromRGB(150, 160, 175)
questHint.TextXAlignment = Enum.TextXAlignment.Left
questHint.Text = ""
questHint.ZIndex = 102
questHint.Parent = questCard

local questClose = Instance.new("TextButton")
questClose.Size = UDim2.new(0, 36, 0, 36)
questClose.Position = UDim2.new(1, -44, 0, 14)
questClose.BackgroundTransparency = 1
questClose.Font = Enum.Font.GothamBold
questClose.TextSize = 24
questClose.TextColor3 = Color3.fromRGB(150, 160, 175)
questClose.Text = "✕"
questClose.ZIndex = 103
questClose.Parent = questCard

local questList = Instance.new("ScrollingFrame")
questList.Size = UDim2.new(1, -32, 1, -92)
questList.Position = UDim2.new(0, 16, 0, 76)
questList.BackgroundTransparency = 1
questList.BorderSizePixel = 0
questList.ScrollBarThickness = 6
questList.CanvasSize = UDim2.new(0, 0, 0, 0)
questList.AutomaticCanvasSize = Enum.AutomaticSize.Y
questList.ZIndex = 102
questList.Parent = questCard
local questLayout = Instance.new("UIListLayout")
questLayout.FillDirection = Enum.FillDirection.Vertical
questLayout.Padding = UDim.new(0, 10)
questLayout.SortOrder = Enum.SortOrder.LayoutOrder
questLayout.Parent = questList

-- Baut die Quest-Liste neu auf (Fortschrittsbalken + Abhol-Knopf je Quest).
function renderQuests()
	questTitle.Text = if lang == "de" then "🎯 Tagesquests" else "🎯 Daily quests"
	questHint.Text = if lang == "de"
		then "Jeden Tag neu · schliesse sie ab und hol dir die Belohnung"
		else "New every day · complete them and claim your reward"
	for _, ch in questList:GetChildren() do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	local quests = (myProfile and myProfile.quests) or {}
	if #quests == 0 then
		local note = Instance.new("TextLabel")
		note.Size = UDim2.new(1, -16, 0, 60)
		note.BackgroundTransparency = 1
		note.Font = Enum.Font.Gotham
		note.TextSize = 15
		note.TextColor3 = Color3.fromRGB(170, 180, 195)
		note.TextWrapped = true
		note.LayoutOrder = 1
		note.ZIndex = 103
		note.Text = if lang == "de"
			then "Heute keine Quests verfügbar. Schau morgen wieder rein! 🐄"
			else "No quests available today. Come back tomorrow! 🐄"
		note.Parent = questList
		return
	end
	for i, q in quests do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 96)
		card.BackgroundColor3 = Color3.fromRGB(38, 44, 56)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.ZIndex = 102
		card.Parent = questList
		mkCorner(card, 12)

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -170, 0, 22)
		nm.Position = UDim2.new(0, 14, 0, 10)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 16
		nm.TextColor3 = COL_TEXT
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.Text = if lang == "de" then q.name else q.nameEn
		nm.ZIndex = 103
		nm.Parent = card

		local rew = Instance.new("TextLabel")
		rew.Size = UDim2.new(1, -170, 0, 18)
		rew.Position = UDim2.new(0, 14, 0, 32)
		rew.BackgroundTransparency = 1
		rew.Font = Enum.Font.GothamBold
		rew.TextSize = 13
		rew.TextColor3 = COL_GOLD
		rew.TextXAlignment = Enum.TextXAlignment.Left
		local xpPart = if q.xp and q.xp > 0 then ` · +{q.xp} XP` else ""
		rew.Text = `+{q.chips} 🪙{xpPart}`
		rew.ZIndex = 103
		rew.Parent = card

		-- Fortschrittsbalken.
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -170, 0, 12)
		barBg.Position = UDim2.new(0, 14, 0, 58)
		barBg.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
		barBg.BorderSizePixel = 0
		barBg.ZIndex = 103
		barBg.Parent = card
		mkCorner(barBg, 6)
		local frac = math.clamp((q.progress or 0) / math.max(1, q.goal or 1), 0, 1)
		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(frac, 0, 1, 0)
		barFill.BackgroundColor3 = if q.done then Color3.fromRGB(80, 200, 120) else COL_ACCENT
		barFill.BorderSizePixel = 0
		barFill.ZIndex = 104
		barFill.Parent = barBg
		mkCorner(barFill, 6)
		local barTxt = Instance.new("TextLabel")
		barTxt.Size = UDim2.new(1, 0, 1, 0)
		barTxt.BackgroundTransparency = 1
		barTxt.Font = Enum.Font.GothamBold
		barTxt.TextSize = 10
		barTxt.TextColor3 = COL_TEXT
		barTxt.Text = `{math.min(q.progress or 0, q.goal or 0)}/{q.goal or 0}`
		barTxt.ZIndex = 105
		barTxt.Parent = barBg

		-- Abhol-Knopf (Zustaende: in Arbeit / abholbereit / abgeholt).
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 134, 0, 40)
		btn.Position = UDim2.new(1, -148, 0.5, -20)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 15
		btn.ZIndex = 103
		btn.Parent = card
		mkCorner(btn, 8)
		if q.claimed then
			btn.BackgroundColor3 = Color3.fromRGB(60, 70, 88)
			btn.TextColor3 = COL_TEXT
			btn.AutoButtonColor = false
			btn.Text = if lang == "de" then "✓ Abgeholt" else "✓ Claimed"
		elseif q.done then
			btn.BackgroundColor3 = COL_GOLD
			btn.TextColor3 = Color3.fromRGB(30, 26, 12)
			btn.AutoButtonColor = true
			btn.Text = if lang == "de" then "Abholen" else "Claim"
			local questId = q.id
			btn.Activated:Connect(function()
				playSound("click")
				-- optimistisch markieren; Server bestaetigt mit Belohnungs-Toast.
				q.claimed = true
				pcall(function()
					ClaimQuestEvent:FireServer(questId)
				end)
				renderQuests()
			end)
		else
			btn.BackgroundColor3 = Color3.fromRGB(44, 52, 66)
			btn.TextColor3 = Color3.fromRGB(150, 160, 175)
			btn.AutoButtonColor = false
			btn.Text = if lang == "de" then "In Arbeit" else "In progress"
		end
	end
end

local function showQuests()
	questsShown = true
	renderQuests()
	questOverlay.Visible = true
	scaleIn(questCard, 0.85, 0.2)
end

function hideQuests()
	questsShown = false
	questOverlay.Visible = false
end

questClose.Activated:Connect(hideQuests)
questBtn.Activated:Connect(showQuests)
end -- do (Quest-Overlay)

-- =====================================================================
-- ===================== SAISON-BESTENLISTE ===========================
-- =====================================================================
-- Woechentliche globale Rangliste: zeigt Top-10 + eigene Punkte + Restzeit der
-- Saison + Belohnungsstufen. Die Daten kommen on-demand vom Server (RemoteFunction,
-- serverseitig gecacht). In ein do...end gekapselt, um Top-Level-Register zu sparen.
-- Saison-Overlay-Steuerung gebuendelt in EINER Top-Level-Tabelle (spart Register):
--   seasonOv.shown  — ist das Overlay sichtbar?
--   seasonOv.render() / seasonOv.hide() — von showScreen/langBtn aufgerufen.
local seasonOv = { shown = false }
do
	local RequestLeaderboardFn = Remotes:WaitForChild("RequestLeaderboard")
	local seasonData = nil -- zuletzt vom Server geholte Bestenliste/Saison-Daten

	-- "Saison" — woechentliche globale Bestenliste mit Punkten + End-Belohnung.
	local seasonBtn = Instance.new("TextButton")
	seasonBtn.Size = UDim2.new(0, 96, 0, 40)
	seasonBtn.Position = UDim2.new(0.5, 216, 0, 98)
	seasonBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 200)
	seasonBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	seasonBtn.Font = Enum.Font.GothamBold
	seasonBtn.TextSize = 15
	seasonBtn.Text = "🏆 Saison"
	seasonBtn.Parent = lobbyScreen
	mkCorner(seasonBtn, 10)

	local seasonOverlay = Instance.new("Frame")
	seasonOverlay.Size = UDim2.new(1, 0, 1, 0)
	seasonOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
	seasonOverlay.BackgroundTransparency = 0.25
	seasonOverlay.BorderSizePixel = 0
	seasonOverlay.Visible = false
	seasonOverlay.ZIndex = 100
	seasonOverlay.Parent = root

	local seasonCard = Instance.new("Frame")
	seasonCard.Size = UDim2.new(0, 560, 0, 500)
	seasonCard.Position = UDim2.new(0.5, -280, 0.5, -250)
	seasonCard.BackgroundColor3 = COL_DARK
	seasonCard.BorderSizePixel = 0
	seasonCard.ZIndex = 101
	seasonCard.Parent = seasonOverlay
	mkCorner(seasonCard, 16)
	local seasonStroke = Instance.new("UIStroke")
	seasonStroke.Color = Color3.fromRGB(150, 120, 230)
	seasonStroke.Thickness = 2
	seasonStroke.Parent = seasonCard

	local seasonTitle = Instance.new("TextLabel")
	seasonTitle.Size = UDim2.new(1, -48, 0, 30)
	seasonTitle.Position = UDim2.new(0, 24, 0, 16)
	seasonTitle.BackgroundTransparency = 1
	seasonTitle.Font = Enum.Font.GothamBold
	seasonTitle.TextSize = 23
	seasonTitle.TextColor3 = Color3.fromRGB(190, 170, 255)
	seasonTitle.TextXAlignment = Enum.TextXAlignment.Left
	seasonTitle.Text = "🏆 Saison"
	seasonTitle.ZIndex = 102
	seasonTitle.Parent = seasonCard

	-- Restzeit + eigene Punkte.
	local seasonInfo = Instance.new("TextLabel")
	seasonInfo.Size = UDim2.new(1, -48, 0, 18)
	seasonInfo.Position = UDim2.new(0, 24, 0, 46)
	seasonInfo.BackgroundTransparency = 1
	seasonInfo.Font = Enum.Font.Gotham
	seasonInfo.TextSize = 13
	seasonInfo.TextColor3 = Color3.fromRGB(160, 170, 185)
	seasonInfo.TextXAlignment = Enum.TextXAlignment.Left
	seasonInfo.Text = ""
	seasonInfo.ZIndex = 102
	seasonInfo.Parent = seasonCard

	local seasonClose = Instance.new("TextButton")
	seasonClose.Size = UDim2.new(0, 36, 0, 36)
	seasonClose.Position = UDim2.new(1, -44, 0, 14)
	seasonClose.BackgroundTransparency = 1
	seasonClose.Font = Enum.Font.GothamBold
	seasonClose.TextSize = 24
	seasonClose.TextColor3 = Color3.fromRGB(150, 160, 175)
	seasonClose.Text = "✕"
	seasonClose.ZIndex = 103
	seasonClose.Parent = seasonCard

	-- Liste der Top-Spieler (scrollbar).
	local seasonList = Instance.new("ScrollingFrame")
	seasonList.Size = UDim2.new(1, -32, 1, -150)
	seasonList.Position = UDim2.new(0, 16, 0, 74)
	seasonList.BackgroundTransparency = 1
	seasonList.BorderSizePixel = 0
	seasonList.ScrollBarThickness = 6
	seasonList.CanvasSize = UDim2.new(0, 0, 0, 0)
	seasonList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	seasonList.ZIndex = 102
	seasonList.Parent = seasonCard
	local seasonLayout = Instance.new("UIListLayout")
	seasonLayout.FillDirection = Enum.FillDirection.Vertical
	seasonLayout.Padding = UDim.new(0, 6)
	seasonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	seasonLayout.Parent = seasonList

	-- Fusszeile: naechste Belohnungsstufe / Belohnungs-Hinweis.
	local seasonFoot = Instance.new("TextLabel")
	seasonFoot.Size = UDim2.new(1, -48, 0, 56)
	seasonFoot.Position = UDim2.new(0, 24, 1, -68)
	seasonFoot.BackgroundTransparency = 1
	seasonFoot.Font = Enum.Font.Gotham
	seasonFoot.TextSize = 12
	seasonFoot.TextColor3 = Color3.fromRGB(150, 160, 175)
	seasonFoot.TextXAlignment = Enum.TextXAlignment.Left
	seasonFoot.TextYAlignment = Enum.TextYAlignment.Top
	seasonFoot.TextWrapped = true
	seasonFoot.Text = ""
	seasonFoot.ZIndex = 102
	seasonFoot.Parent = seasonCard

	-- Naechste erreichbare Belohnungsstufe ueber den eigenen Punkten (oder Top-Stufe).
	local function nextRewardText(points)
		local rewards = seasonData and seasonData.rewards
		if type(rewards) ~= "table" then
			return ""
		end
		-- REWARDS sind absteigend nach minPoints sortiert; finde die naechsthoehere.
		local nextR = nil
		for _, r in rewards do
			if points < r.minPoints then
				if nextR == nil or r.minPoints < nextR.minPoints then
					nextR = r
				end
			end
		end
		if nextR then
			local nm = if lang == "de" then nextR.name else (nextR.nameEn or nextR.name)
			local need = nextR.minPoints - points
			return if lang == "de"
				then `Noch {need} Punkte bis Stufe „{nm}" (+{nextR.chips} 🪙).`
				else `{need} more points to reach "{nm}" (+{nextR.chips} 🪙).`
		end
		return if lang == "de"
			then "Höchste Belohnungsstufe erreicht! 🏆"
			else "Top reward tier reached! 🏆"
	end

	-- Baut die Bestenliste neu auf (aus seasonData).
	local function renderSeason()
		seasonTitle.Text = if seasonData and seasonData.season
			then (if lang == "de" then `🏆 Saison #{seasonData.season.number}` else `🏆 Season #{seasonData.season.number}`)
			else (if lang == "de" then "🏆 Saison" else "🏆 Season")
		if seasonData and seasonData.season then
			local s = seasonData.season
			seasonInfo.Text = if lang == "de"
				then `Endet in {fmtDuration(s.secondsLeft)}   ·   Deine Punkte: {s.points}`
				else `Ends in {fmtDuration(s.secondsLeft)}   ·   Your points: {s.points}`
			seasonFoot.Text = nextRewardText(s.points or 0)
		else
			seasonInfo.Text = if lang == "de" then "Lade Bestenliste …" else "Loading leaderboard …"
			seasonFoot.Text = ""
		end
		for _, ch in seasonList:GetChildren() do
			if not ch:IsA("UIListLayout") then
				ch:Destroy()
			end
		end
		local top = (seasonData and seasonData.top) or {}
		local myId = seasonData and seasonData.me and seasonData.me.userId
		if #top == 0 then
			local note = Instance.new("TextLabel")
			note.Size = UDim2.new(1, -16, 0, 50)
			note.BackgroundTransparency = 1
			note.Font = Enum.Font.Gotham
			note.TextSize = 15
			note.TextColor3 = Color3.fromRGB(170, 180, 195)
			note.TextWrapped = true
			note.LayoutOrder = 1
			note.ZIndex = 103
			note.Text = if lang == "de"
				then "Noch keine Einträge in dieser Saison. Spiel ein Match und sei der Erste! 🐄"
				else "No entries yet this season. Play a match and be the first! 🐄"
			note.Parent = seasonList
			return
		end
		for i, e in top do
			local mine = tostring(e.userId) == tostring(myId)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 38)
			row.BackgroundColor3 = if mine then Color3.fromRGB(70, 60, 120) else Color3.fromRGB(38, 44, 56)
			row.BorderSizePixel = 0
			row.LayoutOrder = i
			row.ZIndex = 102
			row.Parent = seasonList
			mkCorner(row, 8)

			local rankLbl = Instance.new("TextLabel")
			rankLbl.Size = UDim2.new(0, 44, 1, 0)
			rankLbl.Position = UDim2.new(0, 8, 0, 0)
			rankLbl.BackgroundTransparency = 1
			rankLbl.Font = Enum.Font.GothamBold
			rankLbl.TextSize = 16
			rankLbl.TextColor3 = if e.rank == 1 then COL_GOLD elseif e.rank and e.rank <= 3 then Color3.fromRGB(200, 200, 210) else COL_TEXT
			local medal = if e.rank == 1 then "🥇" elseif e.rank == 2 then "🥈" elseif e.rank == 3 then "🥉" else `#{e.rank}`
			rankLbl.Text = medal
			rankLbl.ZIndex = 103
			rankLbl.Parent = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -190, 1, 0)
			nameLbl.Position = UDim2.new(0, 56, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = if mine then Enum.Font.GothamBold else Enum.Font.Gotham
			nameLbl.TextSize = 15
			nameLbl.TextColor3 = COL_TEXT
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Text = e.name or "Spieler"
			nameLbl.ZIndex = 103
			nameLbl.Parent = row

			local ptsLbl = Instance.new("TextLabel")
			ptsLbl.Size = UDim2.new(0, 120, 1, 0)
			ptsLbl.Position = UDim2.new(1, -128, 0, 0)
			ptsLbl.BackgroundTransparency = 1
			ptsLbl.Font = Enum.Font.GothamBold
			ptsLbl.TextSize = 15
			ptsLbl.TextColor3 = Color3.fromRGB(190, 170, 255)
			ptsLbl.TextXAlignment = Enum.TextXAlignment.Right
			ptsLbl.Text = if lang == "de" then `{e.points} Pkt` else `{e.points} pts`
			ptsLbl.ZIndex = 103
			ptsLbl.Parent = row
		end
	end

	-- Holt die Bestenliste vom Server (RemoteFunction yieldet -> in task.spawn).
	local function refreshSeason()
		task.spawn(function()
			local ok, res = pcall(function()
				return RequestLeaderboardFn:InvokeServer()
			end)
			if ok and type(res) == "table" then
				seasonData = res
				if seasonOv.shown then
					renderSeason()
				end
			end
		end)
	end

	local function showSeason()
		seasonOv.shown = true
		renderSeason() -- erst mit alten/Platzhalter-Daten, dann Refresh
		refreshSeason()
		seasonOverlay.Visible = true
		scaleIn(seasonCard, 0.85, 0.2)
	end

	local function hideSeason()
		seasonOv.shown = false
		seasonOverlay.Visible = false
	end

	seasonClose.Activated:Connect(hideSeason)
	seasonBtn.Activated:Connect(showSeason)
	-- Nach aussen reichen (showScreen/langBtn): render/hide ueber die Tabelle.
	seasonOv.render = renderSeason
	seasonOv.hide = hideSeason
end -- do (Saison-Overlay)

-- =====================================================================
-- ============================ FREUNDE ===============================
-- =====================================================================
-- Viraler Wachstums-Hebel: Spieler laden Freunde ein. Tritt ein NEUER Spieler
-- ueber die Einladung bei, bekommen BEIDE Spass-Chips/XP. Die Anbindung an Roblox
-- (SocialService-Einladung) liegt hier im Client; die Belohnungs-Gutschrift im
-- Server (ueber LaunchData "ref:<UserId>"). In ein do...end gekapselt, um
-- Top-Level-Register zu sparen — Steuerung gebuendelt in EINER Tabelle:
--   friendsOv.shown — sichtbar?  friendsOv.render()/hide() — von aussen aufgerufen.
local friendsOv = { shown = false }
do
	local SocialService = game:GetService("SocialService")
	local localPlayer = Players.LocalPlayer

	-- "Freunde" — Einladungen + Empfehlungs-Belohnungen.
	local friendsBtn = Instance.new("TextButton")
	friendsBtn.Size = UDim2.new(0, 96, 0, 40)
	friendsBtn.Position = UDim2.new(0.5, -312, 0, 146)
	friendsBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 110)
	friendsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	friendsBtn.Font = Enum.Font.GothamBold
	friendsBtn.TextSize = 15
	friendsBtn.Text = "👥 Freunde"
	friendsBtn.Parent = lobbyScreen
	mkCorner(friendsBtn, 10)

	local friendsOverlay = Instance.new("Frame")
	friendsOverlay.Size = UDim2.new(1, 0, 1, 0)
	friendsOverlay.BackgroundColor3 = Color3.fromRGB(6, 9, 14)
	friendsOverlay.BackgroundTransparency = 0.25
	friendsOverlay.BorderSizePixel = 0
	friendsOverlay.Visible = false
	friendsOverlay.ZIndex = 100
	friendsOverlay.Parent = root

	local friendsCard = Instance.new("Frame")
	friendsCard.Size = UDim2.new(0, 460, 0, 420)
	friendsCard.Position = UDim2.new(0.5, -230, 0.5, -210)
	friendsCard.BackgroundColor3 = COL_DARK
	friendsCard.BorderSizePixel = 0
	friendsCard.ZIndex = 101
	friendsCard.Parent = friendsOverlay
	mkCorner(friendsCard, 16)
	local friendsStroke = Instance.new("UIStroke")
	friendsStroke.Color = Color3.fromRGB(90, 200, 140)
	friendsStroke.Thickness = 2
	friendsStroke.Parent = friendsCard

	local friendsTitle = Instance.new("TextLabel")
	friendsTitle.Size = UDim2.new(1, -48, 0, 30)
	friendsTitle.Position = UDim2.new(0, 24, 0, 16)
	friendsTitle.BackgroundTransparency = 1
	friendsTitle.Font = Enum.Font.GothamBold
	friendsTitle.TextSize = 23
	friendsTitle.TextColor3 = Color3.fromRGB(150, 230, 185)
	friendsTitle.TextXAlignment = Enum.TextXAlignment.Left
	friendsTitle.Text = "👥 Freunde einladen"
	friendsTitle.ZIndex = 102
	friendsTitle.Parent = friendsCard

	local friendsClose = Instance.new("TextButton")
	friendsClose.Size = UDim2.new(0, 36, 0, 36)
	friendsClose.Position = UDim2.new(1, -44, 0, 14)
	friendsClose.BackgroundTransparency = 1
	friendsClose.Font = Enum.Font.GothamBold
	friendsClose.TextSize = 24
	friendsClose.TextColor3 = Color3.fromRGB(150, 160, 175)
	friendsClose.Text = "✕"
	friendsClose.ZIndex = 103
	friendsClose.Parent = friendsCard

	-- Erklaertext: was bringt das Einladen?
	local friendsBlurb = Instance.new("TextLabel")
	friendsBlurb.Size = UDim2.new(1, -48, 0, 96)
	friendsBlurb.Position = UDim2.new(0, 24, 0, 58)
	friendsBlurb.BackgroundTransparency = 1
	friendsBlurb.Font = Enum.Font.Gotham
	friendsBlurb.TextSize = 15
	friendsBlurb.TextColor3 = Color3.fromRGB(200, 210, 220)
	friendsBlurb.TextXAlignment = Enum.TextXAlignment.Left
	friendsBlurb.TextYAlignment = Enum.TextYAlignment.Top
	friendsBlurb.TextWrapped = true
	friendsBlurb.Text = ""
	friendsBlurb.ZIndex = 102
	friendsBlurb.Parent = friendsCard

	-- Fortschritt: Anzahl geworbener Freunde.
	local friendsCount = Instance.new("TextLabel")
	friendsCount.Size = UDim2.new(1, -48, 0, 28)
	friendsCount.Position = UDim2.new(0, 24, 0, 168)
	friendsCount.BackgroundTransparency = 1
	friendsCount.Font = Enum.Font.GothamBold
	friendsCount.TextSize = 18
	friendsCount.TextColor3 = COL_GOLD
	friendsCount.TextXAlignment = Enum.TextXAlignment.Left
	friendsCount.Text = ""
	friendsCount.ZIndex = 102
	friendsCount.Parent = friendsCard

	-- Hinweis fuer bereits Geworbene / Status.
	local friendsNote = Instance.new("TextLabel")
	friendsNote.Size = UDim2.new(1, -48, 0, 40)
	friendsNote.Position = UDim2.new(0, 24, 0, 200)
	friendsNote.BackgroundTransparency = 1
	friendsNote.Font = Enum.Font.Gotham
	friendsNote.TextSize = 13
	friendsNote.TextColor3 = Color3.fromRGB(150, 160, 175)
	friendsNote.TextXAlignment = Enum.TextXAlignment.Left
	friendsNote.TextYAlignment = Enum.TextYAlignment.Top
	friendsNote.TextWrapped = true
	friendsNote.Text = ""
	friendsNote.ZIndex = 102
	friendsNote.Parent = friendsCard

	-- Einladen-Button (oeffnet den Roblox-Einladungsdialog mit Ref-LaunchData).
	local inviteBtn = Instance.new("TextButton")
	inviteBtn.Size = UDim2.new(1, -48, 0, 52)
	inviteBtn.Position = UDim2.new(0, 24, 1, -76)
	inviteBtn.BackgroundColor3 = Color3.fromRGB(60, 170, 115)
	inviteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	inviteBtn.Font = Enum.Font.GothamBold
	inviteBtn.TextSize = 18
	inviteBtn.Text = "👥 Freunde einladen"
	inviteBtn.ZIndex = 103
	inviteBtn.Parent = friendsCard
	mkCorner(inviteBtn, 10)

	-- Oeffnet den Roblox-Einladungsdialog. Die LaunchData traegt die eigene UserId
	-- als Empfehlungs-Kennung ("ref:<UserId>"), die der Server beim Beitritt des
	-- Eingeladenen ausliest und beiden Seiten die Belohnung gutschreibt.
	local function promptInvite()
		local canInvite = false
		local okCan = pcall(function()
			canInvite = SocialService:CanSendGameInviteAsync(localPlayer)
		end)
		if not (okCan and canInvite) then
			showToast(if lang == "de"
				then "Einladungen sind hier gerade nicht verfuegbar."
				else "Invites are not available right now.")
			return
		end
		local sent = pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = if lang == "de"
				then "Spiel KuhPoker mit mir – ihr bekommt beide Gratis-Chips! 🐄🪙"
				else "Play KuhPoker with me – you both get free chips! 🐄🪙"
			options.LaunchData = "ref:" .. tostring(localPlayer.UserId)
			SocialService:PromptGameInvite(localPlayer, options)
		end)
		if not sent then
			-- Aelteres API ohne ExperienceInviteOptions: einfacher Aufruf als Fallback.
			pcall(function()
				SocialService:PromptGameInvite(localPlayer)
			end)
		end
	end

	-- Baut den Freundes-Inhalt aus dem aktuellen Profil neu auf.
	local function renderFriends()
		local fr = (myProfile and myProfile.friends) or { invitesAccepted = 0, wasReferred = false }
		local n = fr.invitesAccepted or 0
		friendsBlurb.Text = if lang == "de"
			then "Lade Freunde ein! Tritt ein neuer Spieler über deine Einladung bei, bekommt ihr BEIDE Gratis-Chips & XP — reiner Spaß, kein Echtgeld.\n\n• Du bekommst pro neuem Freund Chips + XP.\n• Dein Freund bekommt einen Willkommensbonus."
			else "Invite friends! When a new player joins via your invite, you BOTH get free chips & XP — just for fun, no real money.\n\n• You earn chips + XP per new friend.\n• Your friend gets a welcome bonus."
		friendsCount.Text = if lang == "de"
			then `🎉 Geworbene Freunde: {n}`
			else `🎉 Friends referred: {n}`
		if fr.wasReferred then
			friendsNote.Text = if lang == "de"
				then "Du bist selbst über eine Einladung beigetreten — danke! 💚"
				else "You joined via an invite yourself — thanks! 💚"
		else
			friendsNote.Text = if lang == "de"
				then "Tipp: Je mehr Freunde mitspielen, desto mehr Spaß (und Chips)!"
				else "Tip: the more friends play, the more fun (and chips)!"
		end
	end

	local function showFriends()
		friendsOv.shown = true
		renderFriends()
		friendsOverlay.Visible = true
		scaleIn(friendsCard, 0.85, 0.2)
	end

	local function hideFriends()
		friendsOv.shown = false
		friendsOverlay.Visible = false
	end

	-- Willkommensbonus-Toast fuer einen ueber eine Einladung beigetretenen Spieler.
	local function friendRewardToast(r)
		if not (r and r.chips) then
			return
		end
		local xpPart = if r.xp and r.xp > 0 then ` · +{r.xp} XP` else ""
		showToast(if lang == "de"
			then `👥 Willkommensbonus (per Einladung): +{r.chips} 🪙{xpPart}`
			else `👥 Welcome bonus (via invite): +{r.chips} 🪙{xpPart}`)
	end

	friendsClose.Activated:Connect(hideFriends)
	friendsBtn.Activated:Connect(showFriends)
	inviteBtn.Activated:Connect(promptInvite)
	-- Nach aussen reichen (showScreen/langBtn/Profil-Update): render/hide/toast.
	friendsOv.render = renderFriends
	friendsOv.hide = hideFriends
	friendsOv.toast = friendRewardToast
end -- do (Freunde-Overlay)

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
	b.Activated:Connect(function()
		playSound("click")
	end)
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
local function mkCard(parent, card, hidden: boolean, animate: boolean)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 64, 0, 84)
	f.BackgroundColor3 = if hidden then COL_CARD_BACK else COL_CARD
	f.BorderSizePixel = 0
	f.Parent = parent
	mkCorner(f, 8)
	if animate then
		scaleIn(f, 0.4, 0.24)
	end
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
	helpBtn.Visible = name == "lobby"
	-- Kosmetik-/Shop-Menue schliesst sich, sobald man die Lobby verlaesst.
	if name ~= "lobby" then
		if cosmeticsShown then
			hideCosmetics()
		end
		if shopShown then
			hideShop()
		end
		if questsShown then
			hideQuests()
		end
		if seasonOv.shown then
			seasonOv.hide()
		end
		if friendsOv.shown then
			friendsOv.hide()
		end
	end
end

local function renderProfile(prof)
	if not prof then
		return
	end
	myProfile = prof
	profileName.Text = (prof.name or "Spieler") .. (if prof.vip then ` {Monetization.VIP.tag} VIP` else "")
	profileWallet.Text = `🪙 {prof.wallet or 0}`
	profileStats.Text = string.format(
		(if lang == "de"
			then "Matches gewonnen: %d   ·   Haende gewonnen: %d   ·   Groesster Pot: %d 🪙"
			else "Matches won: %d   ·   Hands won: %d   ·   Biggest pot: %d 🪙"),
		prof.matchesWon or 0,
		prof.handsWon or 0,
		prof.biggestPot or 0
	)
	-- Level + XP-Balken aus der reinen Progressions-Logik ableiten.
	local pr = Progression.progress(prof.xp or 0)
	levelBadge.Text = `Lv {pr.level}`
	xpBarFill.Size = UDim2.new(pr.pct, 0, 1, 0)
	if pr.max then
		xpBarText.Text = if lang == "de" then "MAX" else "MAX"
	else
		xpBarText.Text = `{pr.xpInLevel} / {pr.xpToNext} XP`
	end
	-- Quest-Hinweis-Punkt: Anzahl abholbereiter Quests (fertig, nicht abgeholt).
	local claimable = 0
	for _, q in (prof.quests or {}) do
		if q.done and not q.claimed then
			claimable += 1
		end
	end
	local questBadge = questBtn:FindFirstChild("QuestBadge")
	if questBadge then
		questBadge.Text = tostring(claimable)
		questBadge.Visible = claimable > 0
	end
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

	-- Pot mit Count-up (steigt sichtbar auf den neuen Wert).
	do
		local target = view.totalPot or 0
		potCountGen += 1
		local myGen = potCountGen
		if potShown == target then
			potLabel.Text = `Pot: {target} 🪙`
		else
			if target > potShown then
				playSound("chip")
			end
			task.spawn(function()
				local steps = 12
				local start = potShown
				local diff = target - start
				for i = 1, steps do
					if myGen ~= potCountGen then
						return
					end
					local v = math.floor(start + diff * (i / steps) + 0.5)
					potShown = v
					potLabel.Text = `Pot: {v} 🪙`
					task.wait(0.02)
				end
				if myGen == potCountGen then
					potShown = target
					potLabel.Text = `Pot: {target} 🪙`
				end
			end)
		end
	end

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

	-- Tisch-Thema (Filz-Farbe) gemaess der Vorliebe des Betrachters.
	if view.tableThemeColor then
		felt.BackgroundColor3 = rgbColor(view.tableThemeColor)
	end

	-- Community (nur neu hinzugekommene Karten einblenden + Deal-Sound)
	clear(community)
	local comLen = #view.community
	local newCards = comLen > prevCommunityLen and comLen <= 5
	for i, c in view.community do
		mkCard(community, c, false, newCards and i > prevCommunityLen)
	end
	if newCards then
		playSound("deal")
	end
	prevCommunityLen = comLen

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

	-- "Du bist am Zug": einmaliger Puls + Sound beim Wechsel auf true.
	local yourTurn = view.yourTurn == true
	if yourTurn and not prevYourTurn then
		pulse(actionBar)
		playSound("turn")
	end
	prevYourTurn = yourTurn

	-- Gewinn-Sound, wenn ICH das Match gewinne (nur einmal pro Match).
	if view.matchOver then
		if not winSoundPlayed and view.matchWinnerId == (me and me.id) then
			playSound("win")
		end
		winSoundPlayed = true
	else
		winSoundPlayed = false
	end

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
		-- Avatar-Rahmen (Kosmetik): farbiger Ring um das Kopfbild.
		if p.frameColor then
			local frameStroke = Instance.new("UIStroke")
			frameStroke.Color = rgbColor(p.frameColor)
			frameStroke.Thickness = 3
			frameStroke.Parent = av
		end

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -42, 0, 18)
		nm.Position = UDim2.new(0, 4, 0, 2)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = 13
		nm.TextColor3 = if p.folded then Color3.fromRGB(130, 130, 130) else COL_TEXT
		nm.TextXAlignment = Enum.TextXAlignment.Left
		local tags = ""
		if p.vip then
			tags ..= " " .. Monetization.VIP.tag
		end
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
		elseif not view.waiting and not view.matchOver and not p.folded and p.backColor then
			-- Gegner: zwei kleine, verdeckte Karten in ihrer gewaehlten Rueckseiten-Farbe.
			for c = 1, 2 do
				local back = Instance.new("Frame")
				back.Size = UDim2.new(0, 14, 0, 20)
				back.Position = UDim2.new(0, 4 + (c - 1) * 17, 0, 40)
				back.BackgroundColor3 = rgbColor(p.backColor)
				back.BorderSizePixel = 0
				back.Parent = seat
				mkCorner(back, 3)
			end
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
	if tutorialOverlay.Visible then
		renderTutStep()
	end
	if cosmeticsShown then
		renderCosmetics()
	end
	if shopShown then
		renderShop()
	end
	if questsShown then
		renderQuests()
	end
	if seasonOv.shown then
		seasonOv.render()
	end
	if friendsOv.shown then
		friendsOv.render()
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
		-- Saison-Belohnung (beim Saison-Wechsel gutgeschrieben), falls gemeldet.
		showSeasonRewardToast(view.seasonReward)
		-- Willkommensbonus, falls der Spieler ueber eine Einladung beigetreten ist.
		friendsOv.toast(view.friendReward)
		-- Einsteiger-Tutorial beim allerersten Login automatisch zeigen.
		if view.tutorialDone == false and not tutorialShownThisSession then
			tutorialShownThisSession = true
			showTutorial()
		end
	elseif view.screen == "profile" then
		-- Profil-Update (z. B. nach Match-Ende) — Screen nicht wechseln.
		renderProfile(view.profile)
		if currentScreen == "lobby" then
			renderLobby()
		end
		if cosmeticsShown then
			renderCosmetics()
		end
		if shopShown then
			renderShop()
		end
		if questsShown then
			renderQuests()
		end
		if friendsOv.shown then
			friendsOv.render()
		end
		-- Kauf-Bestaetigung (Chips), falls der Server eine meldet.
		if view.purchase and view.purchase.chips then
			showPurchaseToast(view.purchase.chips)
		end
		-- Quest-Belohnung abgeholt, falls der Server eine meldet.
		if view.questReward and view.questReward.chips then
			showQuestRewardToast(view.questReward)
		end
		-- Saison-Belohnung (Saison-Wechsel waehrend der Sitzung), falls gemeldet.
		if view.seasonReward then
			showSeasonRewardToast(view.seasonReward)
		end
	else
		-- Tisch-Sicht
		lastView = view
		showScreen("table")
		renderTable(view)
	end
end)

renderLobby()
