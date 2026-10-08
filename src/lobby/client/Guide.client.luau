-- The Librarian's side of things on the client:
--   * its head turns to follow you while you're nearby
--   * a bobbing "!" over it until you've heard the introduction once
--   * the dialogue box: typewritten lines, click / E / Space to continue
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors, Fonts = UIKit.Colors, UIKit.Fonts

local LINES = {
	"Oh. Another one found the stairs.",
	"This is the library. Nobody remembers building it down here. You can stay as long as you like... but the doors will want you eventually.",
	"See the mats along the back wall? Stand on one. Solo, Duo, or Squad. Bring friends if you have them.",
	"When the count runs out, the door opens. Behind it are two more doors, and ten seconds to choose.",
	"Some lead somewhere kind. Warm rooms. Gifts. " .. Config.CurrencyName .. ".",
	"Some lead somewhere that is... occupied. Keep moving, keep quiet, and stay alive until it lets you go.",
	"Whatever you bring back, spend at my desk. Or take it to the workbench for a better lantern.",
	"Your lantern is the one thing that goes through the door with you. Look after it.",
	"That's all I can tell you. Pick a door. They're all listening.",
}
local CHARS_PER_SECOND = 45

local lobby = workspace:WaitForChild("Lobby")
local guide = lobby:WaitForChild("Guide", 30)
if not guide then
	warn("[Guide] no guide in the lobby")
	return
end
local head = guide:WaitForChild("Head")
local upperTorso = guide:WaitForChild("UpperTorso")
local neck = head:WaitForChild("Neck")
local prompt = guide:WaitForChild("HumanoidRootPart"):WaitForChild("ProximityPrompt") :: ProximityPrompt
-- Newer rigs joint the head with an AnimationConstraint (turn its torso-side attachment);
-- classic rigs use a Motor6D (turn its C0). Either way it's a local, visual-only change.
local neckAttachment = neck:IsA("AnimationConstraint") and neck.Attachment0 or nil
local neckRest = if neckAttachment then neckAttachment.CFrame else neck.C0

------------------------------------------------------------------------------------------
-- Head tracking
------------------------------------------------------------------------------------------
local yaw, pitch = 0, 0
RunService.RenderStepped:Connect(function(dt)
	local targetYaw, targetPitch = 0, 0
	local character = player.Character
	local myHead = character and character:FindFirstChild("Head")
	if myHead and (myHead.Position - head.Position).Magnitude < 28 then
		local rel = upperTorso.CFrame:PointToObjectSpace(myHead.Position)
		local neckY = neckRest.Position.Y
		targetYaw = math.clamp(math.atan2(-rel.X, -rel.Z), math.rad(-70), math.rad(70))
		targetPitch =
			math.clamp(math.atan2(rel.Y - neckY, Vector2.new(rel.X, rel.Z).Magnitude), math.rad(-25), math.rad(20))
	end
	local alpha = math.min(dt * 4, 1)
	yaw += (targetYaw - yaw) * alpha
	pitch += (targetPitch - pitch) * alpha
	local pose = neckRest * CFrame.Angles(pitch, yaw, 0)
	if neckAttachment then
		neckAttachment.CFrame = pose
	else
		neck.C0 = pose
	end
end)

------------------------------------------------------------------------------------------
-- "!" marker until the introduction has been heard
------------------------------------------------------------------------------------------
local marker = UIKit.new("BillboardGui", {
	Name = "NewMarker",
	Size = UDim2.fromOffset(40, 50),
	StudsOffset = Vector3.new(0, 3.6, 0),
	AlwaysOnTop = true,
	LightInfluence = 0,
	Enabled = false,
	Parent = head,
})
local bang = UIKit.label({
	Text = "!",
	Font = Fonts.title,
	TextScaled = true,
	TextColor3 = Colors.goldBright,
	TextStrokeTransparency = 0.3,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
	Parent = marker,
})
RunService.RenderStepped:Connect(function()
	if marker.Enabled then
		bang.Position = UDim2.fromOffset(0, math.sin(os.clock() * 3) * 5)
	end
end)

------------------------------------------------------------------------------------------
-- Dialogue box
------------------------------------------------------------------------------------------
local gui = UIKit.new("ScreenGui", {
	Name = "GuideUI",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})
local box = UIKit.new("TextButton", {
	Name = "Dialogue",
	Text = "",
	AutoButtonColor = false,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.fromOffset(760, 170),
	BackgroundColor3 = Colors.panel,
	BackgroundTransparency = 0.04,
	Visible = false,
	Parent = gui,
}, { UIKit.corner(10), UIKit.stroke(Colors.gold, 2), UIKit.sheen() })
local boxScale = UIKit.new("UIScale", { Parent = box })
UIKit.label({
	Text = "the librarian",
	Font = Enum.Font.SpecialElite,
	TextSize = 24,
	TextColor3 = Colors.gold,
	Position = UDim2.fromOffset(24, 12),
	Size = UDim2.new(1, -48, 0, 28),
	Parent = box,
})
local body = UIKit.label({
	Text = "",
	Font = Fonts.body,
	TextSize = 24,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(24, 46),
	Size = UDim2.new(1, -48, 1, -96),
	Parent = box,
})
local progress = UIKit.label({
	Text = "",
	Font = Fonts.ui,
	TextSize = 16,
	TextColor3 = Colors.muted,
	Position = UDim2.new(0, 24, 1, -38),
	Size = UDim2.fromOffset(120, 24),
	Parent = box,
})
local nextButton = UIKit.button("NEXT", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -12),
	Size = UDim2.fromOffset(110, 36),
	Parent = box,
})
local skipButton = UIKit.button("SKIP", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -136, 1, -12),
	Size = UDim2.fromOffset(90, 36),
	BackgroundColor3 = Colors.bg,
	Parent = box,
})

local talking = false
local lineIndex = 0
local typing = false
local typeToken = 0

local function finish()
	if not talking then
		return
	end
	talking = false
	typeToken += 1
	local t =
		UIKit.tween(boxScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
	t.Completed:Connect(function()
		if not talking then
			box.Visible = false
		end
	end)
	prompt.Enabled = true
	if marker.Enabled then
		marker.Enabled = false
		Remotes.get("GuideSeen"):FireServer()
	end
end

local function showLine(index: number)
	lineIndex = index
	local text = LINES[index]
	body.Text = text
	body.MaxVisibleGraphemes = 0
	progress.Text = string.format("%d / %d", index, #LINES)
	nextButton.Text = index == #LINES and "CLOSE" or "NEXT"
	typing = true
	typeToken += 1
	local token = typeToken
	task.spawn(function()
		local shown = 0
		local total = utf8.len(text) or #text
		while shown < total and token == typeToken do
			shown += 1
			body.MaxVisibleGraphemes = shown
			if shown % 3 == 1 and text:sub(shown, shown) ~= " " then
				Sfx.play("Type", 0.15)
			end
			local ch = text:sub(shown, shown)
			-- linger on punctuation like someone thinking
			task.wait((ch == "." or ch == "?" or ch == ",") and 0.18 or 1 / CHARS_PER_SECOND)
		end
		if token == typeToken then
			body.MaxVisibleGraphemes = -1
			typing = false
		end
	end)
end

local function advance()
	if not talking then
		return
	end
	if typing then
		-- first press finishes the line, the next one moves on
		typeToken += 1
		body.MaxVisibleGraphemes = -1
		typing = false
	elseif lineIndex < #LINES then
		showLine(lineIndex + 1)
	else
		finish()
	end
end

local function start()
	if talking then
		return
	end
	talking = true
	prompt.Enabled = false
	box.Visible = true
	boxScale.Scale = 0.9
	UIKit.tween(boxScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 })
	Sfx.play("PanelOpen", 0.04)
	showLine(1)
end

box.Activated:Connect(advance)
nextButton.Activated:Connect(advance)
skipButton.Activated:Connect(finish)
UserInputService.InputBegan:Connect(function(input, processed)
	if not talking or processed then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Return
	then
		advance()
	end
end)

-- walking away ends the conversation
RunService.Heartbeat:Connect(function()
	if not talking then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - head.Position).Magnitude > 30 then
		finish()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(triggered)
	if triggered == prompt then
		start()
	end
end)
script.Parent:WaitForChild("OpenGuide").Event:Connect(start)

-- first visit: point the player at the guide
local data = Remotes.get("GetData"):InvokeServer()
if data and not data.SeenGuide then
	marker.Enabled = true
	task.delay(2.5, function()
		UIKit.toast(gui, "Someone is waiting for you among the shelves. Walk up and press E to talk.")
	end)
end
