--[[
	Trial overlay, in the lobby's spray-stencil language: the huge PICK A DOOR and its countdown, the
	reveal, the round timer and the FOLLOW THEM IN button. Everything is driven by attributes that
	DoorRoomFlow sets: workspace.Phase / TimeLeft / Revealed and the local player's Side / Picked /
	Alive / RevivesLeft. The items hotbar and the lantern FX are separate LocalScripts beside this one.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local C = UIKit.Colors

local PAINT = Color3.fromRGB(196, 34, 28) -- the lobby's spray red
local PAINT_DARK = Color3.fromRGB(72, 14, 12) -- the misregistered under-coat
local CREAM = Color3.fromRGB(238, 226, 200)
local SPRAY = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)
local rng = Random.new()

local gui = UIKit.new("ScreenGui", {
	Name = "TrialUI",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})
local holder = UIKit.new("Frame", {
	Name = "Holder",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.fromOffset(900, 420),
	Parent = gui,
})
UIKit.fit(holder)

------------------------------------------------------------------------------------------
-- Sprayed text: two rings of faint mist copies, a dark under-coat 3 px off, the main coat with
-- patchy density, the whole thing a touch off level. Returns a setter so the text can change.
------------------------------------------------------------------------------------------
local function patchy(): NumberSequence
	local keys = { NumberSequenceKeypoint.new(0, rng:NextNumber(0.05, 0.15)) }
	local t = 0
	while t < 0.8 and #keys < 16 do
		t += rng:NextNumber(0.1, 0.22)
		if t >= 0.95 then
			break
		end
		table.insert(keys, NumberSequenceKeypoint.new(t, rng:NextNumber(0, 0.2)))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, rng:NextNumber(0.05, 0.15)))
	return NumberSequence.new(keys)
end

local function spray(parent: Instance, name: string, px: number, pos: UDim2, size: UDim2)
	local box = UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = pos,
		Size = size,
		Rotation = rng:NextNumber(-1.6, 1.6),
		Parent = parent,
	})
	local layers: { TextLabel } = {}
	local tinted: { TextLabel } = {}
	local function layer(z: number, color: Color3, transparency: number, dx: number, dy: number)
		local l = UIKit.new("TextLabel", {
			BackgroundTransparency = 1,
			FontFace = SPRAY,
			Text = "",
			TextScaled = true,
			TextColor3 = color,
			TextTransparency = transparency,
			Position = UDim2.fromOffset(dx, dy),
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
			Parent = box,
		})
		table.insert(layers, l)
		return l
	end
	for ring, spec in { { 0.035, 0.86 }, { 0.075, 0.93 } } do
		local r = math.max(2, px * spec[1])
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + ring * 0.4
			table.insert(tinted, layer(1, PAINT, spec[2], math.cos(a) * r, math.sin(a) * r))
		end
	end
	local under = layer(2, PAINT_DARK, 0.15, 3, 3)
	UIKit.new("UIGradient", { Transparency = patchy(), Parent = under })
	local main = layer(3, PAINT, 0, 0, 0)
	table.insert(tinted, main)
	UIKit.new("UIGradient", {
		Transparency = patchy(),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0.8, 0.76, 0.76)),
			ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.7, Color3.new(0.93, 0.9, 0.9)),
			ColorSequenceKeypoint.new(1, Color3.new(0.76, 0.72, 0.72)),
		}),
		Parent = main,
	})
	local current = ""
	return {
		box = box,
		main = main,
		set = function(text: string, color: Color3?)
			if text ~= current then
				current = text
				for _, l in layers do
					l.Text = text
				end
			end
			local col = color or PAINT
			for _, l in tinted do
				l.TextColor3 = col
			end
			-- the under-coat follows the colour: dark red under red, warm brown under cream
			under.TextColor3 = col == PAINT and PAINT_DARK or Color3.fromRGB(60, 42, 30)
		end,
	}
end

------------------------------------------------------------------------------------------
-- Layout: kicker line, headline stencil, a thin cream rule, the big number, a subline, the button
------------------------------------------------------------------------------------------
-- (FontFace is set after creation: UIKit.label also sets Font, and property order isn't guaranteed)
local kicker = UIKit.label({
	Name = "Kicker",
	TextSize = 24,
	TextColor3 = CREAM,
	TextTransparency = 0.1,
	TextStrokeTransparency = 0.7,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(900, 28),
	Parent = holder,
})
kicker.FontFace = UIKit.Face.semi
local headline = spray(holder, "Headline", 112, UDim2.new(0.5, 0, 0, 30), UDim2.fromOffset(900, 112))
local rule = UIKit.new("Frame", {
	Name = "Rule",
	BackgroundColor3 = CREAM,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 152),
	Size = UDim2.fromOffset(320, 2),
	Parent = holder,
})

-- the countdown number: a stencilled numeral with its own under-coat, popped by a UIScale
local countBox = UIKit.new("Frame", {
	Name = "Count",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 240),
	Size = UDim2.fromOffset(480, 150),
	Parent = holder,
})
local countScale = UIKit.new("UIScale", { Parent = countBox })
local countUnder = UIKit.new("TextLabel", {
	Name = "Under",
	BackgroundTransparency = 1,
	FontFace = SPRAY,
	Text = "",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(60, 42, 30),
	TextTransparency = 0.2,
	Position = UDim2.fromOffset(4, 4),
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
	Parent = countBox,
})
local countMain = UIKit.new("TextLabel", {
	Name = "Main",
	BackgroundTransparency = 1,
	FontFace = SPRAY,
	Text = "",
	TextScaled = true,
	TextColor3 = CREAM,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 3,
	Parent = countBox,
})
UIKit.new("UIGradient", { Transparency = patchy(), Parent = countMain })

local sub = UIKit.label({
	Name = "Sub",
	TextSize = 24,
	TextColor3 = CREAM,
	TextTransparency = 0.15,
	TextStrokeTransparency = 0.7,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 322),
	Size = UDim2.fromOffset(900, 30),
	Parent = holder,
})
sub.FontFace = UIKit.Face.semi

local followButton = UIKit.button("FOLLOW THEM IN", {
	Name = "FollowIn",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 362),
	Size = UDim2.fromOffset(250, 48),
	TextSize = 22,
	Visible = false,
	Parent = holder,
}, { style = "accent", icon = "play", tooltip = "Into the dark, after the others. No way back." })
followButton.Activated:Connect(function()
	Remotes.get("FollowIn"):FireServer()
end)

------------------------------------------------------------------------------------------
-- Sounds
------------------------------------------------------------------------------------------
local uiSounds: { [string]: Sound } = {}
-- A UI sound at a chosen pitch (Sfx.play only jitters around 1): the hot ticks play lower.
local function playUi(name: string, speed: number)
	local def = Config.Sounds[name]
	if not def or def.id == 0 then
		return
	end
	local sound = uiSounds[name]
	if not sound then
		sound = Sfx.make(SoundService, name) :: Sound
		uiSounds[name] = sound
	end
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
end

local function pop(hot: boolean)
	countScale.Scale = 1.25
	TweenService:Create(countScale, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	if hot then
		countMain.TextColor3 = PAINT
		TweenService:Create(countMain, TweenInfo.new(0.6), { TextColor3 = C.creamHot }):Play()
	else
		countMain.TextColor3 = CREAM
	end
end

local function setCount(text: string)
	countMain.Text = text
	countUnder.Text = text
end

------------------------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------------------------
local function mmss(seconds: number)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local lastPhase, lastTime = nil, nil

local function render()
	local phase = workspace:GetAttribute("Phase") or "Waiting"
	local t = workspace:GetAttribute("TimeLeft") or 0
	local side = player:GetAttribute("Side") or "Door"
	local alive = player:GetAttribute("Alive") ~= false
	local revealed = workspace:GetAttribute("Revealed")
	local numeral = revealed == "Left" and "I" or revealed == "Right" and "II" or "?"
	local revives = player:GetAttribute("RevivesLeft") or 0
	local phaseChanged = phase ~= lastPhase
	local timeChanged = t ~= lastTime
	lastPhase, lastTime = phase, t

	followButton.Visible = false
	kicker.Text = ""
	rule.Visible = true

	if phase == "Pick" then
		headline.set("PICK A DOOR", PAINT)
		setCount(tostring(t))
		sub.Text = "Stand at the door you trust."
		if phaseChanged then
			Sfx.play("PickChime", 0.02)
			if Config.Sounds.PickADoorVoice.id ~= 0 then
				Sfx.play("PickADoorVoice", 0)
			end
			countMain.TextColor3 = CREAM
		end
		if timeChanged and t > 0 then
			if t <= 3 then
				playUi("PickTickHot", 0.75)
			else
				Sfx.play("PickTick")
			end
			pop(t <= 3)
		end
	elseif phase == "Resolve" or phase == "Reveal" then
		kicker.Text = string.format("THE RIGHT DOOR WAS %s", numeral)
		setCount("")
		if side == "Safe" then
			headline.set("YOU'RE SAFE.", CREAM)
			sub.Text = "For now."
		elseif side == "Threat" then
			headline.set("WRONG DOOR", PAINT)
			sub.Text = "Something is in here with you."
		else
			headline.set("", PAINT)
			sub.Text = "The doors are open."
		end
	elseif phase == "Round" then
		countMain.TextColor3 = CREAM
		if not alive then
			headline.set("YOU DIDN'T MAKE IT", PAINT)
			setCount(mmss(t))
			sub.Text = "Watch from the warm side."
		elseif side == "Threat" then
			headline.set("WRONG DOOR", PAINT)
			setCount("SURVIVE  " .. mmss(t))
			sub.Text = revives > 0 and "Keep moving.  Revive ready." or "Keep moving."
		elseif side == "Safe" then
			headline.set("YOU'RE SAFE.", CREAM)
			setCount(mmss(t))
			sub.Text = "For now."
			followButton.Visible = true
		else
			headline.set("", PAINT)
			setCount(mmss(t))
			sub.Text = "You missed the doors. Wait for the next round."
		end
	elseif phase == "Reward" then
		setCount("")
		if side == "Door" then
			headline.set("", PAINT)
			sub.Text = "Next time, pick a door."
		elseif not alive then
			headline.set("YOU DIDN'T MAKE IT", PAINT)
			sub.Text = "No keys this time."
		elseif side == "Threat" then
			headline.set("YOU SURVIVED", CREAM)
			sub.Text = string.format("+%d %s", Config.Rewards.Hunt, Config.CurrencyName)
		else
			headline.set("THE RIGHT DOOR", CREAM)
			sub.Text = string.format("+%d %s", Config.Rewards.Blessing, Config.CurrencyName)
		end
	elseif phase == "Return" then
		headline.set("BACK TO THE LIBRARY", CREAM)
		setCount(tostring(t))
		sub.Text = ""
	else
		headline.set("WAITING FOR YOUR PARTY", CREAM)
		rule.Visible = false
		setCount("")
		sub.Text = "The doors are listening."
	end
end

for _, name in { "Phase", "TimeLeft", "Revealed" } do
	workspace:GetAttributeChangedSignal(name):Connect(render)
end
for _, name in { "Side", "Alive", "RevivesLeft" } do
	player:GetAttributeChangedSignal(name):Connect(render)
end

-- Toasts go top-right so they never sit on the stencil.
Remotes.get("Notify").OnClientEvent:Connect(function(text)
	UIKit.toast(gui, text)
	local toasts = gui:FindFirstChild("Toasts")
	if toasts then
		toasts.AnchorPoint = Vector2.new(1, 0)
		toasts.Position = UDim2.new(1, -16, 0, 80)
	end
end)

render()
