-- The Librarian's side of things on the client:
--   * its head turns to follow you while you're nearby
--   * a bobbing "!" over it until you've heard the introduction once
--   * the introduction itself runs through the shared Dialogue box (DialogueTrees.Librarian)
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dialogue = require(Shared.Dialogue)
local DialogueTrees = require(Shared.DialogueTrees)
local Remotes = require(Shared.Remotes)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors, Face = UIKit.Colors, UIKit.Face

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

-- toasts only; the dialogue box lives in Dialogue's own ScreenGui
local gui = UIKit.new("ScreenGui", {
	Name = "GuideUI",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

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
-- The introduction (Dialogue handles the box, keys, click-to-continue and walking away)
------------------------------------------------------------------------------------------
local talking = false

local function start()
	if talking then
		return
	end
	talking = true
	prompt.Enabled = false
	Dialogue.start(DialogueTrees.Librarian, {
		anchor = head,
		onClose = function()
			talking = false
			prompt.Enabled = true
			if marker.Enabled then
				marker.Enabled = false
				Remotes.get("GuideSeen"):FireServer()
			end
		end,
	})
end

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
