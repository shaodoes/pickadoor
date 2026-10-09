--[[
	Reward stations, client side: the three glowing rings in the reading hall and their panels.

	  * Ring detection: standing on a station's ring (workspace.Lobby.Stations.*, attributes Station +
	    RingRadius, child part Ring) opens that station's panel and sets LocalPlayer attribute
	    AtStation = "Daily" | "Wheel" | "Challenges". Stepping off closes it and clears AtStation.
	    Closing the panel yourself while still on the ring latches that station: it won't re-open
	    until you step off and back on.
	  * ScreenGui "RewardsUI" with three UIKit panels: "DailyPanel" (7-day streak calendar + CLAIM),
	    "WheelPanel" (the Wheel of Fate, spun in sync with the 3D wheel from the server's start time)
	    and "ChallengesPanel" (Mr. Ashby's ledger: 3 daily + 3 weekly challenges).
	  * BindableEvent script.Parent.OpenChallenges (created here): fire it to open the ledger.
	    Fires script.Parent.TalkArchivist (created by Archivist.client, may be missing) from TALK.
	  * A bobbing "!" BillboardGui "Badge" over each station's LabelAnchor while something is waiting.

	All rules, tables and maths come from Shared.Rewards; the server decides everything.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local Sfx = require(Shared.Sfx)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Colors, Face = UIKit.Colors, UIKit.Face
local CURRENCY = Config.CurrencyName
local IS_STUDIO = RunService:IsStudio()

local BRASS = Colors.gold
local BRASS_DARK = Color3.fromRGB(150, 112, 56)
local BRASS_LIGHT = Color3.fromRGB(240, 206, 140)

local snapshot: any = nil -- latest profile snapshot from the server

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local gui = UIKit.new("ScreenGui", {
	Name = "RewardsUI",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Toasts go through the lobby HUD's holder when it exists so they stack with the server's Notify toasts
-- instead of drawing on top of them.
local function toast(message: string, kind: string?)
	local lobbyGui = playerGui:FindFirstChild("LobbyUI")
	UIKit.toast(if lobbyGui and lobbyGui:IsA("ScreenGui") then lobbyGui else gui, message, kind)
end

local function text(props: { [string]: any })
	local merged = {
		BackgroundTransparency = 1,
		FontFace = Face.body,
		TextSize = 18,
		TextColor3 = Colors.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("TextLabel", merged)
end

local function circle(): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- Recolour a UIKit.icon (its pieces are frames, strokes and the odd label).
local function tint(icon: Instance, color: Color3)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") then
			d.Color = color
		elseif d:IsA("TextLabel") then
			d.TextColor3 = color
		end
	end
end

local function buttonContent(button: GuiButton): Instance?
	local face = button:FindFirstChild("Face")
	return face and face:FindFirstChild("Content")
end

-- Swap (or remove, with nil) the icon inside a UIKit.button's face.
local function setIcon(button: GuiButton, name: string?, color: Color3, size: number)
	local content = buttonContent(button)
	if not content then
		return
	end
	local old = content:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	if name then
		local icon = UIKit.icon(name, color, size)
		icon.LayoutOrder = 1
		icon.Parent = content
	end
end

-- Restyle a UIKit.button in place (face via the BaseColor attribute UIKit.animate listens to).
local function paint(button: GuiButton, styleName: string)
	local style = UIKit.Styles[styleName] or UIKit.Styles.ink
	button:SetAttribute("BaseColor", style.face)
	local face = button:FindFirstChild("Face")
	local stroke = face and face:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.trim
	end
	local content = buttonContent(button)
	local label = content and content:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = style.text
	end
	local icon = content and content:FindFirstChild("Icon")
	if icon then
		tint(icon, style.text)
	end
end

-- Set a button's caption, style and icon in one go (icon colour follows the style's text colour).
local function restyle(button: GuiButton, caption: string, styleName: string, icon: string?, iconSize: number?)
	local style = UIKit.Styles[styleName] or UIKit.Styles.ink
	button.Text = caption
	setIcon(button, icon, style.text, iconSize or 20)
	paint(button, styleName)
end

-- Little gold diamonds that burst upwards from `origin` inside `parent` and fade.
local function sparkles(parent: GuiObject, origin: UDim2, count: number, spread: number?)
	local s = spread or 1
	for _ = 1, count do
		local size = math.random(5, 10)
		local bit = UIKit.new("Frame", {
			Name = "Sparkle",
			BackgroundColor3 = if math.random() < 0.3 then Colors.paperLight else Colors.goldBright,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = origin,
			Size = UDim2.fromOffset(size, size),
			Rotation = 45,
			ZIndex = 30,
			Parent = parent,
		}, { UIKit.corner(2) })
		local life = 0.7 + math.random() * 0.6
		local goal = origin + UDim2.fromOffset(math.random(-70, 70) * s, -math.random(50, 150) * s)
		UIKit.tween(bit, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal,
			Rotation = 45 + math.random(-180, 180),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		})
		task.delay(life + 0.05, function()
			bit:Destroy()
		end)
	end
end

local function itemName(id: string): string
	local def = Items.get(id)
	return def and def.name or id
end

------------------------------------------------------------------------------------------
-- Panels + open / close bookkeeping
------------------------------------------------------------------------------------------
local dailyPanel, dailyContent = UIKit.panel(gui, "Daily Reward", UDim2.fromOffset(720, 430))
local wheelPanel, wheelContent = UIKit.panel(gui, "Wheel of Fate", UDim2.fromOffset(760, 470))
local challengePanel, challengeContent = UIKit.panel(gui, "Challenges", UDim2.fromOffset(700, 500))
dailyPanel.Name = "DailyPanel"
wheelPanel.Name = "WheelPanel"
challengePanel.Name = "ChallengesPanel"

local panelsByStation: { [string]: Frame } = {
	Daily = dailyPanel,
	Wheel = wheelPanel,
	Challenges = challengePanel,
}

local currentStation: string? = nil -- the ring we're standing on
local latched: { [string]: boolean } = {} -- closed by the player while still on the ring

local function hideLobbyPanels()
	local lobbyGui = playerGui:FindFirstChild("LobbyUI")
	if not lobbyGui then
		return
	end
	for _, child in lobbyGui:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute("Open") == true then
			UIKit.hide(child)
		end
	end
end

local function openPanel(panel: Frame)
	hideLobbyPanels()
	for _, other in panelsByStation do
		if other ~= panel then
			UIKit.hide(other)
		end
	end
	UIKit.show(panel)
end

local function hideAll()
	for _, panel in panelsByStation do
		UIKit.hide(panel)
	end
end

-- Closing a station's panel any way at all (X, another panel, TALK) while on its ring latches it.
for name, panel in panelsByStation do
	panel:GetAttributeChangedSignal("Open"):Connect(function()
		if panel:GetAttribute("Open") ~= true and currentStation == name then
			latched[name] = true
		end
	end)
end

-- Opening one of the lobby HUD's panels (Shop, Lanterns, ...) puts ours away.
task.spawn(function()
	local lobbyGui = playerGui:WaitForChild("LobbyUI", 30)
	if not lobbyGui then
		return
	end
	local function watch(child: Instance)
		if not child:IsA("Frame") then
			return
		end
		-- UIKit.panel parents the frame before it sets Open, so listen for any Open change
		child.AttributeChanged:Connect(function(attr)
			if attr == "Open" and child:GetAttribute("Open") == true then
				hideAll()
			end
		end)
	end
	for _, child in lobbyGui:GetChildren() do
		watch(child)
	end
	lobbyGui.ChildAdded:Connect(watch)
end)

-- Keys balance chip in a panel header (left of the close button), like the shop's.
local balanceLabels: { TextLabel } = {}
local function headerBalance(panel: Frame)
	local header = panel:FindFirstChild("Header", true)
	if not header then
		return
	end
	local holder = UIKit.new("Frame", {
		Name = "Balance",
		BackgroundColor3 = Colors.inkSoft,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		ZIndex = 2,
		Parent = header,
	}, {
		UIKit.corner(17),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }),
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local icon = UIKit.icon("key", Colors.gold, 18)
	icon.LayoutOrder = 1
	icon.Parent = holder
	table.insert(
		balanceLabels,
		text({
			Name = "Amount",
			Text = "...",
			FontFace = Face.bold,
			TextSize = 20,
			TextColor3 = Colors.paper,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			LayoutOrder = 2,
			Parent = holder,
		})
	)
end
headerBalance(wheelPanel)

-- Small muted Studio-only debug button.
local function debugButton(parent: Instance, caption: string, action: string, position: UDim2, anchor: Vector2?)
	if not IS_STUDIO then
		return nil
	end
	local button = UIKit.button(caption, {
		Name = "Debug_" .. action,
		AnchorPoint = anchor or Vector2.new(0, 0),
		Position = position,
		Size = UDim2.fromOffset(124, 28),
		TextSize = 13,
		Parent = parent,
	}, { style = "muted", radius = 8, depth = 2, tooltip = "Studio only" })
	button.Activated:Connect(function()
		Remotes.get("RewardsDebug"):FireServer(action)
	end)
	return button
end

------------------------------------------------------------------------------------------
-- DAILY REWARD: 7-day streak calendar
------------------------------------------------------------------------------------------
local CONTENT_W = 680 -- dailyContent width (720 - 2 * 20)
local CARD_GAP, BIG_GAP = 8, 12
local BIG_W, BIG_H = 148, 170
local SMALL_H = 150
local smallCount = #Rewards.Daily - 1
local SMALL_W = (CONTENT_W - BIG_W - BIG_GAP - (smallCount - 1) * CARD_GAP) / smallCount

type DayCard = {
	day: number,
	slot: Frame, -- positioned holder (UIScale for the pop)
	scale: UIScale,
	glow: Frame,
	face: Frame,
	stroke: UIStroke,
	labels: { TextLabel }, -- text that follows the card's ink/paper state
	icons: { Frame }, -- icons that follow it too
	check: Frame,
	pill: TextLabel,
	stamp: TextLabel,
	state: string,
}

local cards: { DayCard } = {}

-- A little treasure chest drawn with frames (walnut box, brass bands, gold lock plate).
local function chestIcon(parent: Instance, width: number, position: UDim2)
	local h = math.floor(width * 0.78)
	local f = UIKit.new("Frame", {
		Name = "Chest",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(width, h),
		ZIndex = 3,
		Parent = parent,
	})
	local walnut, walnutDark = Color3.fromRGB(110, 70, 42), Color3.fromRGB(80, 50, 30)
	local function piece(color: Color3, x: number, y: number, w: number, hh: number, radius: number?, z: number?)
		local p = UIKit.new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, hh),
			ZIndex = z or 3,
			Parent = f,
		})
		if radius then
			UIKit.corner(radius).Parent = p
		end
		return p
	end
	piece(walnut, 0, 0, 1, 0.46, math.floor(width * 0.16)) -- domed lid
	piece(walnut, 0, 0.28, 1, 0.18) -- squares off the lid's lower corners
	piece(walnutDark, 0, 0.44, 1, 0.56, 4) -- box
	piece(BRASS, 0, 0.4, 1, 0.07, nil, 4) -- lip band
	piece(BRASS, 0.14, 0, 0.08, 1, 2, 4) -- straps
	piece(BRASS, 0.78, 0, 0.08, 1, 2, 4)
	local plate = piece(Colors.goldBright, 0.39, 0.32, 0.22, 0.3, 3, 5) -- lock plate
	UIKit.stroke(BRASS_DARK, 1.5, 0).Parent = plate
	piece(Colors.ink, 0.475, 0.4, 0.05, 0.12, 2, 6) -- keyhole
	return f
end

local function buildDayCard(index: number): DayCard
	local def = Rewards.Daily[index]
	local big = index == #Rewards.Daily
	local w, h = if big then BIG_W else SMALL_W, if big then BIG_H else SMALL_H
	local x = if big then CONTENT_W - BIG_W else (index - 1) * (SMALL_W + CARD_GAP)
	local y = if big then 0 else (BIG_H - SMALL_H) / 2

	local slot = UIKit.new("Frame", {
		Name = "Day" .. index,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 1,
		Parent = dailyContent,
	})
	local scale = UIKit.new("UIScale", { Parent = slot })
	local glow = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundColor3 = Colors.goldBright,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 16, 1, 16),
		ZIndex = 1,
		Parent = slot,
	}, { UIKit.corner(18) })
	UIKit.shadow(slot, 12, 3, 0.7)
	local face = UIKit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = Colors.paperDark,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = slot,
	}, { UIKit.corner(12), UIKit.sheen(0.4) })
	local stroke = UIKit.stroke(Colors.ink, 1.5, 0.84)
	stroke.Parent = face

	local labels, icons = {}, {}
	local function label(props: { [string]: any })
		props.TextXAlignment = Enum.TextXAlignment.Center
		props.ZIndex = 3
		props.Parent = face
		local l = text(props)
		table.insert(labels, l)
		return l
	end

	label({
		Name = "DayLabel",
		Text = "DAY " .. index,
		FontFace = Face.semi,
		TextSize = 15,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
	})
	if big then
		chestIcon(face, 66, UDim2.new(0.5, 0, 0, 32))
		label({
			Name = "Amount",
			Text = string.format("+%d %s", def.keys, string.upper(CURRENCY)),
			FontFace = Face.bold,
			TextSize = 20,
			Position = UDim2.fromOffset(0, 88),
			Size = UDim2.new(1, 0, 0, 22),
		})
		local extras = {}
		if def.spins then
			table.insert(extras, string.format("+%d SPIN%s", def.spins, def.spins == 1 and "" or "S"))
		end
		for id, count in def.items or {} do
			table.insert(extras, string.format("+%d %s", count, string.upper(itemName(id))))
		end
		for i, line in extras do
			label({
				Name = "Extra" .. i,
				Text = line,
				FontFace = Face.semi,
				TextSize = 14,
				Position = UDim2.fromOffset(0, 110 + (i - 1) * 17),
				Size = UDim2.new(1, 0, 0, 16),
			})
		end
	else
		local key = UIKit.icon("key", BRASS, 30)
		key.AnchorPoint = Vector2.new(0.5, 0)
		key.Position = UDim2.new(0.5, 0, 0, 40)
		key.ZIndex = 3
		key.Parent = face
		table.insert(icons, key)
		label({
			Name = "Amount",
			Text = "+" .. def.keys,
			FontFace = Face.bold,
			TextSize = 26,
			Position = UDim2.fromOffset(0, 76),
			Size = UDim2.new(1, 0, 0, 28),
		})
		label({
			Name = "Unit",
			Text = string.upper(CURRENCY),
			FontFace = Face.semi,
			TextSize = 12,
			Position = UDim2.fromOffset(0, 103),
			Size = UDim2.new(1, 0, 0, 14),
		})
	end

	local pill = text({
		Name = "Pill",
		Text = "TODAY",
		FontFace = Face.bold,
		TextSize = 12,
		TextColor3 = Colors.paperLight,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Colors.accent,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.new(1, -16, 0, 18),
		Visible = false,
		ZIndex = 4,
		Parent = face,
	})
	UIKit.corner(9).Parent = pill

	-- green tick badge hanging off the top-right corner
	local check = UIKit.new("Frame", {
		Name = "Check",
		BackgroundColor3 = Colors.green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(24, 24),
		Visible = false,
		ZIndex = 5,
		Parent = slot,
	}, { circle(), UIKit.stroke(Colors.paperLight, 2, 0) })
	local tick = UIKit.icon("check", Colors.paperLight, 14)
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.Parent = check

	-- the CLAIMED stamp that thumps down on a fresh claim
	local stamp = text({
		Name = "Stamp",
		Text = "CLAIMED",
		FontFace = Face.bold,
		TextSize = if big then 26 else 18,
		TextColor3 = Colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = Colors.paperLight,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 0, 30),
		Rotation = -14,
		TextTransparency = 1,
		ZIndex = 6,
		Parent = slot,
	})
	UIKit.new("UIScale", { Parent = stamp })

	return {
		day = index,
		slot = slot,
		scale = scale,
		glow = glow,
		face = face,
		stroke = stroke,
		labels = labels,
		icons = icons,
		check = check,
		pill = pill,
		stamp = stamp,
		state = "",
	}
end

for i = 1, #Rewards.Daily do
	cards[i] = buildDayCard(i)
end

-- streak line + rule
local streakLabel = text({
	Name = "Streak",
	Text = "",
	FontFace = Face.bold,
	TextSize = 20,
	Position = UDim2.fromOffset(2, BIG_H + 12),
	Size = UDim2.fromOffset(300, 24),
	Parent = dailyContent,
})
text({
	Name = "Rule",
	Text = "Miss a day and the streak starts over.",
	FontFace = Face.body,
	TextSize = 16,
	TextColor3 = Colors.inkMuted,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -2, 0, BIG_H + 14),
	Size = UDim2.fromOffset(360, 22),
	Parent = dailyContent,
})
UIKit.new("Frame", {
	Name = "Divider",
	BackgroundColor3 = Colors.ink,
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, BIG_H + 44),
	Size = UDim2.new(1, 0, 0, 1),
	Parent = dailyContent,
})

local claimButton = UIKit.button("CLAIM", {
	Name = "Claim",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, BIG_H + 60),
	Size = UDim2.fromOffset(380, 58),
	TextSize = 26,
	Parent = dailyContent,
}, { style = "green", icon = "key", iconSize = 24, radius = 14, depth = 4 })

debugButton(dailyContent, "DEBUG +1 DAY", "nextDay", UDim2.new(0, 0, 1, -28))
debugButton(dailyContent, "SKIP 2 DAYS", "skipDay", UDim2.new(0, 132, 1, -28))

local dailyBusy = false
local todayCard: DayCard? = nil -- the card that pulses while claimable

local function setCardState(card: DayCard, state: string)
	card.state = state
	local claimed = state == "claimed" or state == "todayClaimed"
	local inkCard = claimed
	card.face.BackgroundColor3 = if state == "today"
		then Colors.cream
		elseif inkCard then Colors.ink
		else Colors.paperDark
	local fg = if state == "today" then Colors.ink elseif inkCard then Colors.muted else Colors.inkMuted
	for _, l in card.labels do
		l.TextColor3 = fg
	end
	for _, icon in card.icons do
		tint(icon, if state == "today" then BRASS_DARK elseif inkCard then Colors.muted else Colors.inkMuted)
	end
	card.check.Visible = claimed
	card.pill.Visible = state == "today" or state == "todayClaimed"
	card.pill.BackgroundColor3 = if state == "todayClaimed" then Colors.green else Colors.accent
	card.pill.Text = if state == "todayClaimed" then "OPENED" else "TODAY"
	if state == "today" then
		card.stroke.Color = Colors.goldBright
		card.stroke.Thickness = 3
		card.stroke.Transparency = 0
	elseif state == "todayClaimed" then
		card.stroke.Color = Colors.green
		card.stroke.Thickness = 2.5
		card.stroke.Transparency = 0.1
	else
		card.stroke.Color = Colors.ink
		card.stroke.Thickness = 1.5
		card.stroke.Transparency = if inkCard then 0.5 else 0.84
	end
	if state ~= "today" then
		card.glow.BackgroundTransparency = 1
	end
	card.slot.ZIndex = if state == "today" then 2 else 1
end

local function dailyCountdownCaption(): string
	return "COME BACK IN " .. Rewards.formatDuration(Rewards.secondsToNextDay())
end

local function updateDaily()
	local st = Rewards.dailyState(snapshot and snapshot.Daily)
	todayCard = nil
	for _, card in cards do
		local state
		if card.day < st.day then
			state = "claimed"
		elseif card.day == st.day then
			state = if st.claimedToday then "todayClaimed" else "today"
		else
			state = "future"
		end
		if not snapshot then
			state = "future"
		end
		setCardState(card, state)
		if state == "today" then
			todayCard = card
		end
	end
	local streak = if st.claimedToday then st.day else st.streak
	streakLabel.Text = string.format("STREAK  %d / %d", if snapshot then streak else 0, #Rewards.Daily)
	if snapshot and st.claimable then
		restyle(claimButton, string.format("CLAIM DAY %d", st.day), "green", "key", 24)
	else
		restyle(claimButton, if snapshot then dailyCountdownCaption() else "...", "muted", nil)
	end
end

-- The claimed card thumps: stamp slams down, the card pops, sparkles fly.
local function celebrateDay(day: number)
	local card = cards[day]
	if not card then
		return
	end
	card.slot.ZIndex = 3
	card.scale.Scale = 1.14
	UIKit.tween(card.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	local stampScale = card.stamp:FindFirstChildOfClass("UIScale")
	if stampScale then
		stampScale.Scale = 2.4
		UIKit.tween(stampScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end
	card.stamp.TextTransparency = 0
	card.stamp.TextStrokeTransparency = 0.4
	task.delay(1.8, function()
		UIKit.tween(card.stamp, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		card.slot.ZIndex = 1
	end)
	sparkles(card.slot, UDim2.fromScale(0.5, 0.45), 26, 1.2)
end

claimButton.Activated:Connect(function()
	if dailyBusy or not snapshot then
		return
	end
	local st = Rewards.dailyState(snapshot.Daily)
	if not st.claimable then
		toast("Already opened today. Come back in " .. Rewards.formatDuration(Rewards.secondsToNextDay()) .. ".")
		return
	end
	dailyBusy = true
	local ok, res = pcall(function()
		return Remotes.get("ClaimDaily"):InvokeServer()
	end)
	dailyBusy = false
	if not ok or type(res) ~= "table" or not res.ok then
		toast(type(res) == "table" and tostring(res.message) or "The chest won't budge. Try again.", "error")
		return
	end
	celebrateDay(tonumber(res.day) or st.day)
	task.delay(0.25, function()
		toast(tostring(res.message), "success")
	end)
end)

------------------------------------------------------------------------------------------
-- WHEEL OF FATE: the wheel
------------------------------------------------------------------------------------------
-- Wedges are isosceles triangles, each split into two right triangles: a frame whose UIGradient has a
-- hard transparency edge along its diagonal (UIGradient rotates in pixel space, so the angle is taken
-- from the box's aspect). Each segment is two narrow wedges so the gap between the chord and the
-- rim stays ~2 px, hidden under a dark ring line and the brass rim. Everything that turns lives in
-- the Rotor; GuiObject.Rotation is clockwise and inherited by children.
local WHEEL = 352 -- outer diameter (brass rim included)
local RO = WHEEL / 2 -- outer radius
local RS = RO - 12 -- segment radius (the rim shows outside it)
local HUB = 68
local SEG = Rewards.SegmentAngle
local SUBS = 2 -- wedges per segment

local HARD_EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.505, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- One half of a downward-pointing isosceles triangle (apex at the bottom inner corner).
local function triangleHalf(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, right: boolean)
	local f = UIKit.new("Frame", {
		Name = "Tri",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Parent = parent,
	})
	local angle = math.deg(math.atan(w / h))
	-- right half keeps its upper-left triangle, left half its upper-right one
	UIKit.new("UIGradient", {
		Rotation = if right then angle else 180 - angle,
		Transparency = HARD_EDGE,
		Parent = f,
	})
	return f
end

-- A wedge of the wheel centred on `centerDeg` (clockwise from 12 o'clock), `halfDeg` either side.
local function wedge(parent: Instance, centerDeg: number, halfDeg: number, radius: number, color: Color3, z: number)
	local holder = UIKit.new("Frame", {
		Name = "Wedge",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		Rotation = centerDeg,
		ZIndex = z,
		Parent = parent,
	})
	local h = radius * math.cos(math.rad(halfDeg))
	local hw = radius * math.sin(math.rad(halfDeg))
	local top = radius - h
	local tris = {
		triangleHalf(holder, radius - hw, top, hw, h, color, false),
		triangleHalf(holder, radius, top, hw, h, color, true),
	}
	-- a seam filler down the middle (the two halves meet on a fractional pixel)
	table.insert(
		tris,
		UIKit.new("Frame", {
			Name = "Seam",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(radius - 1, top + 2),
			Size = UDim2.fromOffset(2, h - HUB / 2),
			Parent = holder,
		})
	)
	for _, t in tris do
		t.ZIndex = z
	end
	return holder, tris
end

-- A frame of the rotor's size rotated to `deg`, for things placed along a radius.
local function spoke(parent: Instance, deg: number, z: number): Frame
	return UIKit.new("Frame", {
		Name = "Spoke",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL, WHEEL),
		Rotation = deg,
		ZIndex = z,
		Parent = parent,
	})
end

local wheelHolder = UIKit.new("Frame", {
	Name = "Wheel",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(6, 18),
	Size = UDim2.fromOffset(WHEEL, WHEEL),
	Parent = wheelContent,
})
UIKit.shadow(wheelHolder, 999, 6, 1)

-- brass rim: a full brass disc behind the segments, top-lit, with a dark outer edge
UIKit.new("Frame", {
	Name = "Rim",
	BackgroundColor3 = BRASS,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
	Parent = wheelHolder,
}, {
	circle(),
	UIKit.stroke(Colors.ink, 2, 0.2),
	UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BRASS_LIGHT),
			ColorSequenceKeypoint.new(0.5, BRASS),
			ColorSequenceKeypoint.new(1, BRASS_DARK),
		}),
	}),
})

local rotor = UIKit.new("Frame", {
	Name = "Rotor",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
	Parent = wheelHolder,
})

local glowTris: { { Frame } } = {} -- per segment: the cream overlay that pulses on a win
local segLabels: { TextLabel } = {}
local half = SEG / SUBS / 2
for i, seg in Rewards.Wheel do
	local center = (i - 1) * SEG
	local fill = seg.color:Lerp(Color3.new(1, 1, 1), 0.06)
	glowTris[i] = {}
	for k = 1, SUBS do
		local subCenter = center - SEG / 2 + (k - 0.5) * SEG / SUBS
		-- a hair of overlap between the sub-wedges of one segment hides their seam
		wedge(rotor, subCenter, half + 0.35, RS, fill, 1)
		local _, tris = wedge(rotor, subCenter, half + 0.35, RS, Colors.paperLight, 2)
		for _, t in tris do
			t.BackgroundTransparency = 1
			table.insert(glowTris[i], t)
		end
	end
	-- icon near the rim and the label inside it, upright along the radius
	local arm = spoke(rotor, center, 4)
	local iconSize = 26
	local icon = UIKit.icon(seg.icon or "key", Colors.paperLight, iconSize)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(RO, RO - RS * 0.84)
	icon.ZIndex = 4
	icon.Parent = arm
	local labelRadius = RS * 0.64
	local labelWidth = 2 * labelRadius * math.tan(math.rad(SEG / 2)) * 0.92
	segLabels[i] = text({
		Name = "Label",
		Text = seg.label,
		FontFace = Face.bold,
		TextScaled = true,
		TextColor3 = Colors.paperLight,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = Colors.shadow,
		TextStrokeTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(RO, RO - labelRadius),
		Size = UDim2.fromOffset(labelWidth, 20),
		ZIndex = 4,
		Parent = arm,
	})
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 9, Parent = segLabels[i] })
	UIKit.new("UIScale", { Parent = segLabels[i] })
end

-- brass dividers with a stud on the rim at every boundary
for i = 1, #Rewards.Wheel do
	local arm = spoke(rotor, (i - 1) * SEG + SEG / 2, 3)
	UIKit.new("Frame", {
		Name = "Divider",
		BackgroundColor3 = BRASS,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(RO, RO - RS),
		Size = UDim2.fromOffset(3, RS - HUB / 2 + 4),
		ZIndex = 3,
		Parent = arm,
	}, { UIKit.stroke(BRASS_DARK, 1, 0.4) })
	UIKit.new("Frame", {
		Name = "Stud",
		BackgroundColor3 = BRASS_LIGHT,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(RO, (RO - RS) / 2),
		Size = UDim2.fromOffset(9, 9),
		ZIndex = 3,
		Parent = arm,
	}, { circle(), UIKit.stroke(BRASS_DARK, 1.5, 0) })
end

-- hub: a brass knob with a keyhole (it turns with the wheel)
local hub = UIKit.new("Frame", {
	Name = "Hub",
	BackgroundColor3 = BRASS,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(HUB, HUB),
	ZIndex = 5,
	Parent = rotor,
}, {
	circle(),
	UIKit.stroke(Colors.ink, 2, 0.2),
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BRASS_LIGHT, BRASS_DARK) }),
})
UIKit.new("Frame", {
	Name = "Boss",
	BackgroundColor3 = BRASS_DARK,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(HUB - 22, HUB - 22),
	ZIndex = 5,
	Parent = hub,
}, {
	circle(),
	UIKit.stroke(BRASS_LIGHT, 1.5, 0.3),
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BRASS_DARK, BRASS) }),
})
UIKit.new("Frame", {
	Name = "KeyholeTop",
	BackgroundColor3 = Colors.ink,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -4),
	Size = UDim2.fromOffset(11, 11),
	ZIndex = 6,
	Parent = hub,
}, { circle() })
UIKit.new("Frame", {
	Name = "KeyholeSlot",
	BackgroundColor3 = Colors.ink,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, -2),
	Size = UDim2.fromOffset(5, 13),
	ZIndex = 6,
	Parent = hub,
}, { UIKit.corner(2) })

-- static dressing over the rotor: a dark line where the segments meet the rim, and a lamp-lit sheen
UIKit.new("Frame", {
	Name = "RimLine",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RS * 2 - 5, RS * 2 - 5),
	ZIndex = 3,
	Parent = wheelHolder,
}, { circle(), UIKit.stroke(Colors.ink, 3, 0.25) })
UIKit.new("Frame", {
	Name = "Sheen",
	BackgroundColor3 = Color3.fromRGB(255, 240, 214),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(RS * 2 - 6, RS * 2 - 6),
	ZIndex = 4,
	Parent = wheelHolder,
}, {
	circle(),
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- the pointer: a red diamond under a brass cap, fixed at 12 o'clock
local pointer = UIKit.new("Frame", {
	Name = "Pointer",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -18),
	Size = UDim2.fromOffset(36, 50),
	ZIndex = 6,
	Parent = wheelHolder,
})
UIKit.new("Frame", {
	Name = "Diamond",
	BackgroundColor3 = Colors.accent,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(18, 26),
	Size = UDim2.fromOffset(24, 24),
	Rotation = 45,
	ZIndex = 6,
	Parent = pointer,
}, {
	UIKit.corner(3),
	UIKit.stroke(BRASS_LIGHT, 2, 0),
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Colors.creamHot, Colors.accentDark) }),
})
UIKit.new("Frame", {
	Name = "Cap",
	BackgroundColor3 = BRASS,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(18, 12),
	Size = UDim2.fromOffset(22, 22),
	ZIndex = 7,
	Parent = pointer,
}, {
	circle(),
	UIKit.stroke(Colors.ink, 2, 0.2),
	UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BRASS_LIGHT, BRASS_DARK) }),
})

local wheelAngle = 0 -- the rotor's resting rotation (degrees, 0..360)
local function setWheelAngle(angle: number)
	wheelAngle = angle % 360
	rotor.Rotation = wheelAngle
end

local function flickPointer()
	pointer.Rotation = -16
	UIKit.tween(pointer, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 })
end

local glowToken = 0
local function clearGlow()
	glowToken += 1
	for _, tris in glowTris do
		for _, t in tris do
			t.BackgroundTransparency = 1
		end
	end
end

-- The winning segment flashes cream a few times, then keeps a soft glow; its label throbs.
local function glowSegment(index: number)
	clearGlow()
	local mine = glowToken
	local tris = glowTris[index]
	local label = segLabels[index]
	local labelScale = label and label:FindFirstChildOfClass("UIScale")
	task.spawn(function()
		for _ = 1, 3 do
			if glowToken ~= mine then
				return
			end
			for _, t in tris do
				UIKit.tween(t, TweenInfo.new(0.18), { BackgroundTransparency = 0.45 })
			end
			if labelScale then
				UIKit.tween(labelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1.3 })
			end
			task.wait(0.2)
			for _, t in tris do
				UIKit.tween(t, TweenInfo.new(0.25), { BackgroundTransparency = 0.85 })
			end
			if labelScale then
				UIKit.tween(labelScale, TweenInfo.new(0.25), { Scale = 1 })
			end
			task.wait(0.27)
		end
	end)
end

------------------------------------------------------------------------------------------
-- WHEEL OF FATE: the side column
------------------------------------------------------------------------------------------
local SIDE_X = WHEEL + 30
local side = UIKit.new("Frame", {
	Name = "Side",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(SIDE_X, 0),
	Size = UDim2.new(1, -SIDE_X, 1, 0),
	Parent = wheelContent,
})

local spinsCard = UIKit.new("Frame", {
	Name = "Spins",
	BackgroundColor3 = Colors.ink,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 96),
	Parent = side,
}, { UIKit.corner(12), UIKit.stroke(Colors.paper, 1.5, 0.82), UIKit.sheen(0.5) })
local spinsCount = text({
	Name = "Count",
	Text = "-",
	FontFace = Face.bold,
	TextSize = 60,
	TextColor3 = Colors.goldBright,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(6, 0),
	Size = UDim2.fromOffset(78, 96),
	Parent = spinsCard,
})
local spinsCaption = text({
	Name = "Caption",
	Text = "SPINS AVAILABLE",
	FontFace = Face.bold,
	TextSize = 20,
	TextColor3 = Colors.paper,
	Position = UDim2.fromOffset(92, 16),
	Size = UDim2.new(1, -104, 0, 24),
	Parent = spinsCard,
})
local freeStatus = text({
	Name = "Free",
	Text = "",
	FontFace = Face.body,
	TextSize = 16,
	TextColor3 = Colors.muted,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(92, 44),
	Size = UDim2.new(1, -104, 0, 44),
	Parent = spinsCard,
})

local spinButton = UIKit.button("SPIN", {
	Name = "Spin",
	Position = UDim2.fromOffset(0, 108),
	Size = UDim2.new(1, 0, 0, 58),
	TextSize = 28,
	Parent = side,
}, { style = "green", icon = "play", iconSize = 24, radius = 14, depth = 4 })

local buyButton = UIKit.button(string.format("BUY A SPIN — %d %s", Rewards.SpinCost, string.upper(CURRENCY)), {
	Name = "BuySpin",
	Position = UDim2.fromOffset(0, 176),
	Size = UDim2.new(1, 0, 0, 46),
	TextSize = 19,
	Parent = side,
}, { style = "ink", icon = "key", iconSize = 20, radius = 12 })

-- result card (swaps with the odds table)
local resultCard = UIKit.new("Frame", {
	Name = "Result",
	BackgroundColor3 = Colors.paperLight,
	Position = UDim2.fromOffset(0, 234),
	Size = UDim2.new(1, 0, 0, 106),
	Parent = side,
}, { UIKit.corner(12) })
local resultStroke = UIKit.stroke(Colors.ink, 1.5, 0.84)
resultStroke.Parent = resultCard
local resultTile = UIKit.new("Frame", {
	Name = "Chip",
	BackgroundColor3 = Colors.ink,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(52, 52),
	Parent = resultCard,
}, { UIKit.corner(12) })
text({
	Name = "Caption",
	Text = "THE WHEEL SAYS",
	FontFace = Face.semi,
	TextSize = 13,
	TextColor3 = Colors.inkMuted,
	Position = UDim2.fromOffset(78, 12),
	Size = UDim2.new(1, -90, 0, 16),
	Parent = resultCard,
})
local resultText = text({
	Name = "Text",
	Text = "Spin it and see what fate keeps in the drawer.",
	FontFace = Face.bodyBold,
	TextSize = 18,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(78, 32),
	Size = UDim2.new(1, -90, 1, -40),
	Parent = resultCard,
})
local function setResultIcon(name: string, color: Color3)
	local old = resultTile:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local icon = UIKit.icon(name, color, 30)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = resultTile
end
setResultIcon("help", Colors.gold)

-- odds table
local oddsCard = UIKit.new("Frame", {
	Name = "Odds",
	BackgroundColor3 = Colors.paperLight,
	Position = UDim2.fromOffset(0, 234),
	Size = UDim2.new(1, 0, 0, 106),
	Visible = false,
	Parent = side,
}, {
	UIKit.corner(12),
	UIKit.stroke(Colors.ink, 1.5, 0.84),
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}),
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 17),
		CellPadding = UDim2.fromOffset(16, 1),
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local function segmentName(seg: Rewards.Segment): string
	if seg.kind == "keys" then
		return string.format("%d %s", seg.amount, CURRENCY)
	elseif seg.kind == "item" then
		return itemName(seg.item :: string)
	elseif seg.kind == "spin" then
		return "Free spin"
	end
	return "Lantern"
end
-- grid fills column by column, so rows = ceil(n / 2)
local odds = Rewards.odds()
for i, seg in Rewards.Wheel do
	local cell = UIKit.new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Parent = oddsCard })
	text({
		Text = segmentName(seg),
		FontFace = Face.body,
		TextSize = 14,
		TextColor3 = Colors.inkSoft,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -40, 1, 0),
		Parent = cell,
	})
	text({
		Text = string.format("%d%%", math.round(odds[i])),
		FontFace = Face.semi,
		TextSize = 14,
		TextColor3 = Colors.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 40, 1, 0),
		Parent = cell,
	})
end

local oddsLink = UIKit.new("TextButton", {
	Name = "OddsLink",
	Text = "SHOW ODDS",
	FontFace = Face.semi,
	TextSize = 14,
	TextColor3 = Colors.inkMuted,
	TextXAlignment = Enum.TextXAlignment.Right,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 348),
	Size = UDim2.fromOffset(120, 22),
	Parent = side,
})
UIKit.new("Frame", {
	Name = "Underline",
	BackgroundColor3 = Colors.inkMuted,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(1, 1),
	Size = UDim2.fromOffset(78, 1),
	Parent = oddsLink,
})
oddsLink.MouseEnter:Connect(function()
	oddsLink.TextColor3 = Colors.ink
end)
oddsLink.MouseLeave:Connect(function()
	oddsLink.TextColor3 = Colors.inkMuted
end)
oddsLink.Activated:Connect(function()
	Sfx.play("Click")
	oddsCard.Visible = not oddsCard.Visible
	resultCard.Visible = not oddsCard.Visible
	oddsLink.Text = if oddsCard.Visible then "HIDE ODDS" else "SHOW ODDS"
end)

local spinning = false

local function updateFreeStatus()
	if not snapshot then
		freeStatus.Text = ""
	elseif Rewards.freeSpinReady(snapshot.Spins) then
		freeStatus.Text = "Free spin ready."
		freeStatus.TextColor3 = Color3.fromRGB(150, 206, 140)
	else
		freeStatus.Text = "Next free spin in " .. Rewards.formatDuration(Rewards.secondsToNextDay()) .. "."
		freeStatus.TextColor3 = Colors.muted
	end
end

local function updateWheelSide()
	local spins = snapshot and snapshot.Spins
	local available = if snapshot then Rewards.spinsAvailable(spins) else 0
	local free = snapshot ~= nil and Rewards.freeSpinReady(spins)
	local keys = snapshot and tonumber(snapshot.Keys) or 0
	spinsCount.Text = if snapshot then tostring(available) else "-"
	spinsCount.TextColor3 = if available > 0 then Colors.goldBright else Colors.muted
	spinsCaption.Text = if available == 1 then "SPIN AVAILABLE" else "SPINS AVAILABLE"
	updateFreeStatus()
	if spinning then
		restyle(spinButton, "SPINNING...", "muted", nil)
	elseif available > 0 then
		restyle(spinButton, if free then "SPIN  (FREE)" else "SPIN", "green", "play", 24)
	else
		restyle(spinButton, "NO SPINS LEFT", "muted", nil)
	end
	local canBuy = snapshot ~= nil and not spinning and keys >= Rewards.SpinCost
	restyle(
		buyButton,
		string.format("BUY A SPIN — %d %s", Rewards.SpinCost, string.upper(CURRENCY)),
		if canBuy then "ink" else "muted",
		"key",
		20
	)
	for _, label in balanceLabels do
		label.Text = if snapshot then tostring(keys) else "..."
	end
end

-- Animate the UI wheel to the server's result, in step with the 3D wheel (same start time and curve).
local function playSpin(res: any)
	local index = math.clamp(math.floor(tonumber(res.index) or 1), 1, #Rewards.Wheel)
	local offset = tonumber(res.offset) or 0
	local start = tonumber(res.start) or workspace:GetServerTimeNow()
	local from = wheelAngle
	local travel = Rewards.spinTravel(from, index, offset)
	local lastBoundary = math.floor((from - SEG / 2) / SEG)
	local lastTick = 0
	clearGlow()
	resultText.Text = "The wheel is turning..."
	setResultIcon("help", Colors.gold)

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - start
		local alpha = math.clamp(elapsed / Rewards.SpinDuration, 0, 1)
		local angle = from + travel * Rewards.spinEase(alpha)
		rotor.Rotation = angle % 360
		-- a boundary is under the pointer whenever the rotation is a half segment off a centre
		local boundary = math.floor((angle - SEG / 2) / SEG)
		if boundary ~= lastBoundary then
			lastBoundary = boundary
			local now = os.clock()
			if UIKit.isOpen(wheelPanel) and now - lastTick > 0.04 then
				lastTick = now
				Sfx.play("WheelTick", 0.05)
				flickPointer()
			end
		end
		if alpha < 1 then
			return
		end
		conn:Disconnect()
		setWheelAngle(from + travel)
		spinning = false
		local reward = type(res.reward) == "table" and res.reward or {}
		local message = tostring(reward.text or res.message or "")
		local seg = Rewards.Wheel[index]
		resultText.Text = message
		setResultIcon(seg.icon or "key", Colors.goldBright)
		resultStroke.Color = Colors.gold
		resultStroke.Transparency = 0.1
		UIKit.tween(resultStroke, TweenInfo.new(1.6), { Transparency = 0.84 })
		task.delay(1.6, function()
			resultStroke.Color = Colors.ink
		end)
		if UIKit.isOpen(wheelPanel) then
			Sfx.play("WheelWin", 0.02)
			glowSegment(index)
			sparkles(wheelHolder, UDim2.new(0.5, 0, 0, 10), 22, 0.9)
		end
		toast(message, "success")
		updateWheelSide()
	end)
end

local function spin(buy: boolean)
	if spinning or not snapshot then
		return
	end
	if buy then
		if (tonumber(snapshot.Keys) or 0) < Rewards.SpinCost then
			toast(string.format("A spin costs %d %s.", Rewards.SpinCost, CURRENCY), "error")
			return
		end
	elseif Rewards.spinsAvailable(snapshot.Spins) <= 0 then
		toast(
			string.format(
				"No spins left. Buy one for %d %s, or come back in %s.",
				Rewards.SpinCost,
				CURRENCY,
				Rewards.formatDuration(Rewards.secondsToNextDay())
			),
			"error"
		)
		return
	end
	spinning = true
	updateWheelSide()
	local ok, res = pcall(function()
		return Remotes.get("SpinWheel"):InvokeServer(buy)
	end)
	if not ok or type(res) ~= "table" or not res.ok then
		spinning = false
		updateWheelSide()
		toast(type(res) == "table" and tostring(res.message) or "The wheel is stuck. Try again.", "error")
		return
	end
	playSpin(res)
end

spinButton.Activated:Connect(function()
	spin(false)
end)
buyButton.Activated:Connect(function()
	spin(true)
end)

------------------------------------------------------------------------------------------
-- CHALLENGES: Mr. Ashby's ledger
------------------------------------------------------------------------------------------
text({
	Name = "Keeper",
	Text = string.format("Kept by %s, the Archivist. Finish a line, then claim it here.", Rewards.ArchivistName),
	FontFace = Face.body,
	TextSize = 16,
	TextColor3 = Colors.inkMuted,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Size = UDim2.new(1, if IS_STUDIO then -250 else -120, 0, 34),
	Parent = challengeContent,
})
local talkButton = UIKit.button("TALK", {
	Name = "Talk",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -4, 0, 0),
	Size = UDim2.fromOffset(104, 34),
	TextSize = 17,
	Parent = challengeContent,
}, { style = "ink", icon = "help", iconSize = 16, radius = 10, depth = 2 })
debugButton(challengeContent, "DEBUG +1 DAY", "nextDay", UDim2.new(1, -116, 0, 3), Vector2.new(1, 0))

local talkEvent: BindableEvent? = nil
task.spawn(function()
	local found = script.Parent:WaitForChild("TalkArchivist", 5)
	if found and found:IsA("BindableEvent") then
		talkEvent = found
	end
end)
talkButton.Activated:Connect(function()
	UIKit.hide(challengePanel)
	local event = talkEvent or script.Parent:FindFirstChild("TalkArchivist")
	if event and event:IsA("BindableEvent") then
		event:Fire()
	else
		toast(Rewards.ArchivistName .. " is buried in his ledgers. Try again in a moment.")
	end
end)

local ledger = UIKit.scrollList(challengeContent, {
	Name = "Ledger",
	Position = UDim2.fromOffset(0, 46),
	Size = UDim2.new(1, 0, 1, -46),
})

local function sectionHeader(order: number): TextLabel
	local holder = UIKit.new("Frame", {
		Name = "Section",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = ledger,
	})
	return text({
		Text = "",
		FontFace = Face.semi,
		TextSize = 15,
		TextColor3 = Colors.inkMuted,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
end

type ChallengeRow = {
	scope: string,
	slot: number,
	frame: Frame,
	stroke: UIStroke,
	tile: Frame,
	title: TextLabel,
	fill: Frame,
	count: TextLabel,
	rewards: Frame,
	button: GuiButton,
	busy: boolean,
}

local ROW_H = 68
local BUTTON_W = 132

local function rewardChip(parent: Instance, order: number, icon: string, caption: string, bg: Color3)
	local chip = UIKit.new("Frame", {
		Name = "Reward",
		BackgroundColor3 = bg,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = order,
		Parent = parent,
	}, {
		UIKit.corner(10),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 9) }),
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local glyph = UIKit.icon(icon, Colors.goldBright, 13)
	glyph.LayoutOrder = 1
	glyph.Parent = chip
	text({
		Text = caption,
		FontFace = Face.bold,
		TextSize = 14,
		TextColor3 = Colors.paperLight,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 2,
		Parent = chip,
	})
	return chip
end

local rows: { ChallengeRow } = {}
local sectionLabels: { [string]: TextLabel } = {}

local function setTileIcon(tile: Frame, name: string, color: Color3)
	local old = tile:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local glyph = UIKit.icon(name, color, 28)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = tile
end

local function buildRow(scope: string, slotIndex: number, order: number): ChallengeRow
	local frame = UIKit.new("Frame", {
		Name = string.format("%s%d", scope, slotIndex),
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, ROW_H),
		BackgroundColor3 = Colors.paperLight,
		Parent = ledger,
	}, { UIKit.corner(12) })
	UIKit.hoverRow(frame) -- before the stroke goes on, so it only animates the paper (the stroke shows state)
	local stroke = UIKit.stroke(Colors.ink, 1.5, 0.84)
	stroke.Parent = frame
	local tile = UIKit.new("Frame", {
		Name = "Chip",
		BackgroundColor3 = Colors.ink,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		Parent = frame,
	}, { UIKit.corner(12) })
	local title = text({
		Name = "Title",
		Text = "",
		FontFace = Face.bold,
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(72, 8),
		Size = UDim2.new(1, -(72 + BUTTON_W + 26), 0, 26),
		Parent = frame,
	})
	local track = UIKit.new("Frame", {
		Name = "Progress",
		BackgroundColor3 = Colors.paperDark,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(72, 42),
		Size = UDim2.fromOffset(150, 10),
		Parent = frame,
	}, { UIKit.corner(5), UIKit.stroke(Colors.ink, 1, 0.85) })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Colors.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { UIKit.corner(5) })
	local count = text({
		Name = "Count",
		Text = "",
		FontFace = Face.semi,
		TextSize = 14,
		TextColor3 = Colors.inkMuted,
		Position = UDim2.fromOffset(230, 37),
		Size = UDim2.fromOffset(54, 20),
		Parent = frame,
	})
	local rewards = UIKit.new("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(286, 37),
		Size = UDim2.new(1, -(286 + BUTTON_W + 26), 0, 20),
		Parent = frame,
	}, {
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local button = UIKit.button("CLAIM", {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_W, 42),
		TextSize = 18,
		Parent = frame,
	}, { style = "muted", radius = 10 })

	local row: ChallengeRow = {
		scope = scope,
		slot = slotIndex,
		frame = frame,
		stroke = stroke,
		tile = tile,
		title = title,
		fill = fill,
		count = count,
		rewards = rewards,
		button = button,
		busy = false,
	}
	button.Activated:Connect(function()
		local set = snapshot and snapshot.Challenges and snapshot.Challenges[scope]
		local slot = type(set) == "table" and set[slotIndex]
		local def = slot and Rewards.challenge(slot.id)
		if row.busy or not slot or not def then
			return
		end
		if slot.claimed then
			toast("Already paid out.")
			return
		elseif not Rewards.slotClaimable(slot) then
			toast(string.format("Not yet: %d / %d.", tonumber(slot.progress) or 0, def.target))
			return
		end
		row.busy = true
		local ok, res = pcall(function()
			return Remotes.get("ClaimChallenge"):InvokeServer(scope, slotIndex)
		end)
		row.busy = false
		if not ok or type(res) ~= "table" or not res.ok then
			toast(type(res) == "table" and tostring(res.message) or "The ledger won't open. Try again.", "error")
			return
		end
		sparkles(frame, UDim2.new(1, -14 - BUTTON_W / 2, 0.5, 0), 18, 0.8)
		task.delay(0.2, function()
			toast(tostring(res.message), "success")
		end)
	end)
	return row
end

sectionLabels.daily = sectionHeader(0)
for i = 1, Rewards.ChallengesPerSet do
	table.insert(rows, buildRow("daily", i, i))
end
sectionLabels.weekly = sectionHeader(10)
for i = 1, Rewards.ChallengesPerSet do
	table.insert(rows, buildRow("weekly", i, 10 + i))
end
local emptyNote = text({
	Name = "Empty",
	Text = "Mr. Ashby is still sharpening his pencil...",
	TextSize = 16,
	TextColor3 = Colors.inkMuted,
	LayoutOrder = 100,
	Size = UDim2.new(1, -12, 0, 30),
	Visible = false,
	Parent = ledger,
})

local function updateSectionHeaders()
	sectionLabels.daily.Text = "DAILY — resets in " .. Rewards.formatDuration(Rewards.secondsToNextDay())
	sectionLabels.weekly.Text = "WEEKLY — resets in " .. Rewards.formatDuration(Rewards.secondsToNextWeek())
end

local function updateChallenges()
	local ch = snapshot and snapshot.Challenges
	local any = false
	for _, row in rows do
		local set = type(ch) == "table" and ch[row.scope]
		local slot = type(set) == "table" and set[row.slot]
		local def = slot and Rewards.challenge(slot.id)
		row.frame.Visible = def ~= nil
		if def then
			any = true
			local progress = math.min(tonumber(slot.progress) or 0, def.target)
			local claimable = Rewards.slotClaimable(slot)
			row.title.Text = def.text
			row.title.TextColor3 = if slot.claimed then Colors.inkMuted else Colors.ink
			row.fill.Size = UDim2.fromScale(progress / def.target, 1)
			row.fill.BackgroundColor3 = if progress >= def.target then Colors.green else Colors.gold
			row.count.Text = string.format("%d / %d", progress, def.target)
			for _, child in row.rewards:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			rewardChip(row.rewards, 1, "key", tostring(def.keys), Colors.ink)
			if def.spins then
				rewardChip(row.rewards, 2, "play", string.format("+%d SPIN", def.spins), Colors.accent)
			end
			if slot.claimed then
				row.tile.BackgroundColor3 = Colors.paperDark
				setTileIcon(row.tile, "check", Colors.inkMuted)
				row.stroke.Color, row.stroke.Thickness, row.stroke.Transparency = Colors.ink, 1.5, 0.84
				restyle(row.button, "CLAIMED", "muted", "check", 16)
			elseif claimable then
				row.tile.BackgroundColor3 = Colors.green
				setTileIcon(row.tile, "key", Colors.goldBright)
				row.stroke.Color, row.stroke.Thickness, row.stroke.Transparency = Colors.green, 2, 0.2
				restyle(row.button, "CLAIM", "green", "key", 18)
			else
				row.tile.BackgroundColor3 = Colors.ink
				setTileIcon(row.tile, "key", Colors.gold)
				row.stroke.Color, row.stroke.Thickness, row.stroke.Transparency = Colors.ink, 1.5, 0.84
				restyle(row.button, "NOT YET", "muted", "lock", 16)
			end
		end
	end
	emptyNote.Visible = not any
	updateSectionHeaders()
end

-- The archivist's dialogue opens the ledger through this (always opens, never toggles).
local openChallenges = Instance.new("BindableEvent")
openChallenges.Name = "OpenChallenges"
openChallenges.Parent = script.Parent
openChallenges.Event:Connect(function()
	openPanel(challengePanel)
end)

------------------------------------------------------------------------------------------
-- Stations: ring detection + "!" badges
------------------------------------------------------------------------------------------
local stationModels: { [string]: Instance } = {}
local badges: { [string]: { gui: BillboardGui, bang: TextLabel } } = {}

local function refreshBadges()
	local waiting = Rewards.badges(snapshot)
	for name, badge in badges do
		badge.gui.Enabled = (waiting :: any)[name] == true
	end
end

local function makeBadge(name: string, model: Instance)
	task.spawn(function()
		local anchor = model:WaitForChild("LabelAnchor", 15)
		if not anchor or badges[name] then
			return
		end
		local bb = UIKit.new("BillboardGui", {
			Name = "Badge",
			Size = UDim2.fromOffset(46, 46),
			StudsOffset = Vector3.new(0, 2.4, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 60,
			Enabled = false,
		})
		-- sit just above the title billboard: when it's sized in pixels, share its centre and make our
		-- canvas tall enough that the "!" lands above its top edge at any distance
		local label = anchor:FindFirstChild("Label")
		if label and label:IsA("BillboardGui") then
			if label.Size.Y.Scale == 0 then
				local labelH = label.Size.Y.Offset
				bb.StudsOffset = label.StudsOffset
				bb.StudsOffsetWorldSpace = label.StudsOffsetWorldSpace
				bb.Size = UDim2.fromOffset(46, labelH + 2 * 50)
			else
				bb.StudsOffset = label.StudsOffset + Vector3.new(0, label.Size.Y.Scale / 2 + 1.2, 0)
				bb.StudsOffsetWorldSpace = label.StudsOffsetWorldSpace
			end
		end
		-- a cream badge with a red ring and an ink "!", bobbing gently (as over the Librarian)
		local bang = UIKit.new("TextLabel", {
			Text = "!",
			FontFace = Face.bold,
			TextScaled = true,
			TextColor3 = Colors.ink,
			BackgroundColor3 = Colors.cream,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 23),
			Size = UDim2.fromOffset(36, 36),
			Parent = bb,
		}, {
			UIKit.corner(18),
			UIKit.stroke(Colors.accent, 3),
			UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
		})
		bb.Parent = anchor
		badges[name] = { gui = bb, bang = bang }
		refreshBadges()
	end)
end

local function addStation(model: Instance)
	local name = model:GetAttribute("Station")
	if type(name) ~= "string" or not panelsByStation[name] then
		return
	end
	stationModels[name] = model
	makeBadge(name, model)
	if name == "Wheel" and not spinning then
		-- start the UI wheel where the 3D one rests
		local index = model:GetAttribute("SpinIndex")
		if type(index) == "number" then
			setWheelAngle(Rewards.restAngle(index, tonumber(model:GetAttribute("SpinOffset")) or 0))
		end
	end
end

local function rootPosition(): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

local function onRing(model: Instance, position: Vector3, margin: number): boolean
	local ring = model:FindFirstChild("Ring")
	if not ring or not ring:IsA("BasePart") then
		return false
	end
	local radius = tonumber(model:GetAttribute("RingRadius")) or 5
	local d = position - ring.Position
	return Vector2.new(d.X, d.Z).Magnitude <= radius + margin and math.abs(d.Y) < 5
end

local function enterStation(name: string)
	player:SetAttribute("AtStation", name)
	latched[name] = nil
	local panel = panelsByStation[name]
	if panel and not UIKit.isOpen(panel) then
		openPanel(panel)
	end
end

local function leaveStation(name: string)
	player:SetAttribute("AtStation", nil)
	local panel = panelsByStation[name]
	if panel then
		UIKit.hide(panel)
	end
	latched[name] = nil
end

local function checkRings()
	local position = rootPosition()
	local found: string? = nil
	if position then
		-- a little hysteresis on the ring you're already on, so its edge doesn't flicker the panel
		local currentModel = currentStation and stationModels[currentStation]
		if currentModel and onRing(currentModel, position, 1) then
			found = currentStation
		else
			for name, model in stationModels do
				if model.Parent and onRing(model, position, 0) then
					found = name
					break
				end
			end
		end
	end
	if found == currentStation then
		return
	end
	local previous = currentStation
	currentStation = nil
	if previous then
		leaveStation(previous)
	end
	currentStation = found
	if found and not latched[found] then
		enterStation(found)
	end
end

task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local folder = lobby and lobby:WaitForChild("Stations", 30)
	if not folder then
		return -- no stations in this build of the lobby: nothing to detect
	end
	for _, model in folder:GetChildren() do
		addStation(model)
	end
	folder.ChildAdded:Connect(addStation)
	while true do
		checkRings()
		task.wait(0.1)
	end
end)

------------------------------------------------------------------------------------------
-- Per-frame dressing: bobbing badges, the pulsing "today" card
------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, badge in badges do
		if badge.gui.Enabled then
			badge.bang.Position = UDim2.new(0.5, 0, 0, 23 + math.sin(t * 3) * 5)
		end
	end
	local card = todayCard
	if card and dailyPanel.Visible then
		local wave = (math.sin(t * 4) + 1) / 2
		card.stroke.Transparency = 0.45 * (1 - wave)
		card.glow.BackgroundTransparency = 0.55 + 0.35 * (1 - wave)
	end
end)

------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------
local function refreshAll()
	updateDaily()
	updateWheelSide()
	updateChallenges()
	refreshBadges()
end

Remotes.get("DataUpdated").OnClientEvent:Connect(function(data)
	snapshot = data
	refreshAll()
end)

refreshAll()
task.spawn(function()
	local ok, data = pcall(function()
		return Remotes.get("GetData"):InvokeServer()
	end)
	if ok and data and snapshot == nil then
		snapshot = data
		refreshAll()
	end
end)

-- countdowns tick every second; the badges are re-checked every 10 s and whenever the day turns
task.spawn(function()
	local lastDay = Rewards.today()
	local lastBadges = 0
	while true do
		task.wait(1)
		local today = Rewards.today()
		if today ~= lastDay then
			lastDay = today
			refreshAll()
		else
			if snapshot and not Rewards.dailyState(snapshot.Daily).claimable then
				claimButton.Text = dailyCountdownCaption()
			end
			updateFreeStatus()
			updateSectionHeaders()
		end
		if os.clock() - lastBadges >= 10 then
			lastBadges = os.clock()
			refreshBadges()
		end
	end
end)
