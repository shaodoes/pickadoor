--[[
	Screen: the trial's full-screen layer, shared by the client scripts (one instance per client).

	  Screen.fade(alpha, time?)          the black: 1 = fully black, 0 = clear (starts black: you
	                                     arrive in the trial from black)
	  Screen.alpha() -> number           where the black is heading
	  Screen.status(text?)               a small line in the middle of the black (nil hides it)
	  Screen.caption(text, seconds?)     a subtitle line at the bottom (every voice line / sound cue)
	  Screen.vignette(strength, time?)   darkened edges, 0..1
	  Screen.glitch(seconds)             static, tearing bars and colour-split flashes for `seconds`
	  Screen.gui                         the ScreenGui (DisplayOrder 30, above the overlay)
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UIKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit"))

local Screen = {}

local C = UIKit.Colors
local player = Players.LocalPlayer

local gui = UIKit.new("ScreenGui", {
	Name = "TrialScreen",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
Screen.gui = gui

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Sine), goal)
	t:Play()
	return t
end

------------------------------------------------------------------------------------------
-- Vignette: four edge bands fading in from the borders
------------------------------------------------------------------------------------------
local vignette = UIKit.new("Frame", {
	Name = "Vignette",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
	Parent = gui,
})
local vignetteBands: { Frame } = {}
for _, spec in
	{
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.32), 90 },
		{ UDim2.fromScale(0, 0.68), UDim2.fromScale(1, 0.32), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.26, 1), 0 },
		{ UDim2.fromScale(0.74, 0), UDim2.fromScale(0.26, 1), 180 },
	}
do
	local band = UIKit.new("Frame", {
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = spec[1],
		Size = spec[2],
		Parent = vignette,
	}, {
		UIKit.new("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	table.insert(vignetteBands, band)
end

function Screen.vignette(strength: number, time: number?)
	for _, band in vignetteBands do
		tween(band, time or 0.6, { BackgroundTransparency = 1 - math.clamp(strength, 0, 1) * 0.85 })
	end
end

------------------------------------------------------------------------------------------
-- Glitch layer (built once, hidden)
------------------------------------------------------------------------------------------
local glitchLayer = UIKit.new("Frame", {
	Name = "Glitch",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})
local COLS, ROWS = 32, 18
local noise: { Frame } = {}
for y = 0, ROWS - 1 do
	for x = 0, COLS - 1 do
		table.insert(
			noise,
			UIKit.new("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(0.5, 0.5, 0.5),
				Position = UDim2.fromScale(x / COLS, y / ROWS),
				Size = UDim2.fromScale(1 / COLS + 0.002, 1 / ROWS + 0.002),
				ZIndex = 2,
				Parent = glitchLayer,
			})
		)
	end
end
local tears: { Frame } = {}
for i = 1, 7 do
	table.insert(
		tears,
		UIKit.new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(255, 40, 60) else Color3.fromRGB(40, 230, 255),
			ZIndex = 3,
			Parent = glitchLayer,
		})
	)
end

------------------------------------------------------------------------------------------
-- The black, its status line, the caption
------------------------------------------------------------------------------------------
local black = UIKit.new("Frame", {
	Name = "Black",
	BackgroundColor3 = Color3.new(),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 10,
	Parent = gui,
})
local statusLabel = UIKit.new("TextLabel", {
	Name = "Status",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(700, 30),
	FontFace = UIKit.Face.uiSemi,
	TextSize = 20,
	TextColor3 = C.inkMuted,
	TextTransparency = 1,
	Text = "",
	ZIndex = 11,
	Parent = gui,
})
UIKit.fit(statusLabel)

local captionHolder = UIKit.new("Frame", {
	Name = "Caption",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.fromOffset(860, 60),
	ZIndex = 12,
	Parent = gui,
})
UIKit.fit(captionHolder)
local caption = UIKit.new("TextLabel", {
	Name = "Line",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	FontFace = UIKit.Face.body,
	TextSize = 22,
	TextColor3 = C.paper,
	TextTransparency = 1,
	TextWrapped = false,
	Text = "",
	ZIndex = 12,
	Parent = captionHolder,
}, {
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}),
})
UIKit.glass(caption, { flat = true, alpha = 1, line = 1 })
caption.BackgroundTransparency = 1

local fadeTarget = 0
function Screen.fade(alpha: number, time: number?)
	fadeTarget = alpha
	if (time or 0) <= 0 then
		black.BackgroundTransparency = 1 - alpha
	else
		tween(black, time :: number, { BackgroundTransparency = 1 - alpha })
	end
end
-- start black: you arrive from the lobby's black screen
Screen.fade(1, 0)

function Screen.alpha(): number
	return fadeTarget
end

function Screen.status(text: string?)
	if text then
		statusLabel.Text = text
		tween(statusLabel, 0.5, { TextTransparency = 0.2 })
	else
		tween(statusLabel, 0.4, { TextTransparency = 1 })
	end
end

local captionToken = 0
function Screen.caption(text: string, seconds: number?)
	captionToken += 1
	local token = captionToken
	caption.Text = text
	tween(caption, 0.25, { TextTransparency = 0, BackgroundTransparency = 0.25 })
	task.delay(seconds or 3, function()
		if captionToken == token then
			tween(caption, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
		end
	end)
end

-- Static, tearing bars and colour-split flashes for `seconds` (the room glitching out).
function Screen.glitch(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "GlitchSplit"
	cc.Parent = Lighting
	glitchLayer.Visible = true
	local rng = Random.new()
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / seconds, 0, 1)
		if a >= 1 then
			conn:Disconnect()
			glitchLayer.Visible = false
			cc:Destroy()
			return
		end
		-- static thickens toward the end
		local base = 0.92 - a * 0.6
		for _, cell in noise do
			local v = rng:NextNumber()
			cell.BackgroundColor3 = Color3.new(v, v, v)
			cell.BackgroundTransparency = math.clamp(base + rng:NextNumber(-0.06, 0.06), 0, 1)
		end
		-- horizontal tears jump about
		for _, bar in tears do
			if rng:NextNumber() < 0.5 then
				bar.Visible = rng:NextNumber() < 0.35 + a * 0.5
				bar.Position = UDim2.fromScale(rng:NextNumber(-0.2, 0.1), rng:NextNumber())
				bar.Size = UDim2.fromScale(rng:NextNumber(0.6, 1.3), rng:NextNumber(0.004, 0.05))
				bar.BackgroundTransparency = rng:NextNumber(0.2, 0.7)
			end
		end
		-- colour split: the picture flips red / cyan in hard flashes
		local flash = rng:NextNumber()
		if flash < 0.18 then
			cc.TintColor = Color3.fromRGB(255, 90, 110)
			cc.Contrast = 0.5
			cc.Saturation = 0.6
		elseif flash < 0.36 then
			cc.TintColor = Color3.fromRGB(90, 255, 255)
			cc.Contrast = 0.4
			cc.Saturation = -0.4
		else
			cc.TintColor = Color3.new(1, 1, 1)
			cc.Contrast = a * 0.3
			cc.Saturation = -a
		end
	end)
end

return Screen
