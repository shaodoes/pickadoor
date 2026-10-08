-- Trial overlay: the big PICK A DOOR countdown, fate reveal, and trial timer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors, Fonts = UIKit.Colors, UIKit.Fonts

local gui = UIKit.new("ScreenGui", {
	Name = "TrialUI",
	ResetOnSpawn = false,
	Parent = player:WaitForChild("PlayerGui"),
})

local headline = UIKit.label({
	Font = Fonts.title,
	TextSize = 64,
	TextColor3 = Colors.text,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.4,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 40),
	Size = UDim2.fromOffset(800, 70),
	Parent = gui,
})
local subline = UIKit.label({
	Font = Fonts.body,
	TextSize = 28,
	TextColor3 = Colors.muted,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.6,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 112),
	Size = UDim2.fromOffset(800, 40),
	Parent = gui,
})
local reviveLabel = UIKit.label({
	Font = Fonts.ui,
	TextSize = 18,
	TextColor3 = Colors.gold,
	Position = UDim2.new(0, 16, 1, -40),
	Size = UDim2.fromOffset(300, 30),
	Parent = gui,
})

local function mmss(seconds: number)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function render()
	local phase = workspace:GetAttribute("Phase")
	local t = workspace:GetAttribute("TimeLeft") or 0
	if phase == "Pick" then
		headline.Text = "PICK A DOOR"
		headline.TextColor3 = Colors.text
		subline.Text = string.format(
			"%d    -    I: %d   II: %d",
			t,
			workspace:GetAttribute("VotesLeft") or 0,
			workspace:GetAttribute("VotesRight") or 0
		)
	elseif phase == "Reveal" or phase == "Trial" then
		local kind = workspace:GetAttribute("FateKind")
		headline.Text = workspace:GetAttribute("FateName") or ""
		headline.TextColor3 = kind == "Hunt" and Color3.fromRGB(220, 70, 60) or Colors.gold
		subline.Text = phase == "Reveal" and (workspace:GetAttribute("FateBlurb") or "")
			or string.format(
				"%s  -  %s left  (trial maps coming soon)",
				kind == "Hunt" and "SURVIVE" or "EXPLORE",
				mmss(t)
			)
	elseif phase == "Return" then
		headline.Text = "Back to the library..."
		headline.TextColor3 = Colors.text
		subline.Text = tostring(t)
	else
		headline.Text = "Waiting for your party..."
		headline.TextColor3 = Colors.muted
		subline.Text = ""
	end
	local revives = player:GetAttribute("RevivesLeft") or 0
	reviveLabel.Text = revives > 0 and string.format("REVIVE READY (%d)", revives) or ""
end

for _, name in { "Phase", "TimeLeft", "VotesLeft", "VotesRight", "FateName" } do
	workspace:GetAttributeChangedSignal(name):Connect(render)
end
player:GetAttributeChangedSignal("RevivesLeft"):Connect(render)
Remotes.get("Notify").OnClientEvent:Connect(function(text)
	UIKit.toast(gui, text)
end)
render()
