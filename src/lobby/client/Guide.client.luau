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
local Colors, Face = UIKit.Colors, UIKit.Face

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
	Size = UDim2.fromOffset(46, 46),
	StudsOffset = Vector3.new(0, 3.6, 0),
	AlwaysOnTop = true,
	LightInfluence = 0,
	Enabled = false,
	Parent = head,
})
-- a cream badge with a red ring and an ink "!", bobbing gently
local bang = UIKit.new("TextLabel", {
	Text = "!",
	FontFace = Face.bold,
	TextScaled = true,
	TextColor3 = Colors.ink,
	BackgroundColor3 = Colors.cream,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(36, 36),
	Parent = marker,
}, {
	UIKit.corner(18),
	UIKit.stroke(Colors.accent, 3),
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
})
RunService.RenderStepped:Connect(function()
	if marker.Enabled then
		bang.Position = UDim2.new(0.5, 0, 0.5, math.sin(os.clock() * 3) * 5)
	end
end)

------------------------------------------------------------------------------------------
-- Dialogue box: a sheet of cream paper with a red name tab, typewritten body text,
-- progress pips and NEXT / SKIP. The whole box is a button (click anywhere to continue).
------------------------------------------------------------------------------------------
local gui = UIKit.new("ScreenGui", {
	Name = "GuideUI",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
local box = UIKit.new("TextButton", {
	Name = "Dialogue",
	Text = "",
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.fromOffset(760, 176),
	Visible = false,
	Parent = gui,
})
local boxFit = UIKit.fit(box)
UIKit.shadow(box, 16, 8, 1)
local sheet = UIKit.new("Frame", {
	Name = "Sheet",
	BackgroundColor3 = Colors.paper,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 1,
	Parent = box,
}, { UIKit.corner(16), UIKit.stroke(Colors.ink, 2, 0.35), UIKit.sheen(0.35) })
-- name tab hanging over the top edge
UIKit.new("TextLabel", {
	Name = "Speaker",
	Text = "THE LIBRARIAN",
	FontFace = Face.bold,
	TextSize = 18,
	TextColor3 = Colors.paperLight,
	BackgroundColor3 = Colors.accent,
	Position = UDim2.fromOffset(22, -16),
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 32),
	ZIndex = 3,
	Parent = sheet,
}, {
	UIKit.corner(8),
	UIKit.stroke(Colors.accentDark, 1.5, 0.3),
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
})
local body = UIKit.new("TextLabel", {
	Name = "Body",
	Text = "",
	BackgroundTransparency = 1,
	FontFace = Face.serif,
	TextSize = 21,
	LineHeight = 1.15,
	TextColor3 = Colors.ink,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(26, 30),
	Size = UDim2.new(1, -52, 1, -86),
	Parent = sheet,
})
-- one pip per line; the current one is red and wider
local pips = UIKit.new("Frame", {
	Name = "Progress",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 26, 1, -32),
	Size = UDim2.fromOffset(260, 10),
	Parent = sheet,
}, {
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local pipFrames = {}
for i = 1, #LINES do
	pipFrames[i] = UIKit.new("Frame", {
		LayoutOrder = i,
		BackgroundColor3 = Colors.paperDark,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(8, 8),
		Parent = pips,
	}, { UIKit.corner(4) })
end
local nextButton = UIKit.button("NEXT", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -14),
	Size = UDim2.fromOffset(118, 40),
	ZIndex = 2,
	Parent = sheet,
}, { style = "ink", icon = "play", iconSize = 14 })
local skipButton = UIKit.button("SKIP", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -148, 1, -14),
	Size = UDim2.fromOffset(92, 40),
	ZIndex = 2,
	Parent = sheet,
}, { style = "paper" })

local function setProgress(index: number)
	for i, pip in pipFrames do
		local current = i == index
		UIKit.tween(pip, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Size = UDim2.fromOffset(current and 22 or 8, 8),
			BackgroundColor3 = current and Colors.accent or i < index and Colors.inkMuted or Colors.paperDark,
		})
	end
end

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
	Sfx.play("PanelClose", 0.04)
	local t = UIKit.tween(
		boxFit,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = UIKit.fitScale() * 0.9 }
	)
	t.Completed:Connect(function()
		if not talking then
			box.Visible = false
			boxFit.Scale = UIKit.fitScale()
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
	setProgress(index)
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
	boxFit.Scale = UIKit.fitScale() * 0.9
	UIKit.tween(boxFit, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = UIKit.fitScale() })
	sheet.Position = UDim2.fromOffset(0, 24)
	UIKit.tween(sheet, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new() })
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

-- he waves at you when you come near, until you've talked to him this session
local waveTrack = nil
local talkedThisSession = false
prompt.Triggered:Connect(function()
	talkedThisSession = true
end)
task.spawn(function()
	local animator = guide:FindFirstChildOfClass("Humanoid") and guide.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local wave = Instance.new("Animation")
	wave.AnimationId = "rbxassetid://507770239" -- default R15 wave
	local ok, track = pcall(animator.LoadAnimation, animator, wave)
	if not ok then
		return
	end
	waveTrack = track
	local lastWave = 0
	while true do
		task.wait(1)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = root and (root.Position - head.Position).Magnitude < 22
		if near and not talkedThisSession and not talking and os.clock() - lastWave > 9 then
			lastWave = os.clock()
			waveTrack:Play(0.2)
		end
	end
end)

-- first visit: point the player at the guide
local data = Remotes.get("GetData"):InvokeServer()
if data and not data.SeenGuide then
	marker.Enabled = true
	task.delay(2.5, function()
		UIKit.toast(gui, "Someone is waiting for you among the shelves. Walk up and press E to talk.")
	end)
end
