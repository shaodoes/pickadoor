--[[
	Mr. Ashby, the archivist, on the client (ArchivistService builds him at the Challenges desk):
	  * his head follows you when you're near; left alone he bends over the ledger and writes
	  * ghostly touches: faint cold motes drifting off him and a slow waver in his cold light
	  * stepping onto the challenges ring (LocalPlayer attribute AtStation = "Challenges") gets a
	    whispered greeting in a paper bubble over his head and the scratch of his pen
	  * BindableEvent TalkArchivist (created here, in script.Parent) starts his dialogue
	    (DialogueTrees.Archivist); its "openChallenges" action fires OpenChallenges (Rewards.client)
	All of it is local and visual only.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dialogue = require(Shared.Dialogue)
local DialogueTrees = require(Shared.DialogueTrees)
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors = UIKit.Colors

local LOOK_RANGE = 24 -- studs: he looks up from the ledger at you inside this
local TRACK_RATE = 2.5 -- head smoothing per second: unhurried
local WRITE_PITCH = math.rad(-28) -- looking down at the ledger on the desk
local BUBBLE_HOLD = 3.5 -- seconds a whispered greeting stays up
local BUBBLE_COOLDOWN = 8 -- don't greet again for this long (stepping on and off the ring)
local GHOST = Color3.fromRGB(150, 228, 232)
local SERIF_ITALIC =
	Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)

-- The trigger for his dialogue exists even if the rig never shows up, so firing it never hangs.
local talkEvent = script.Parent:FindFirstChild("TalkArchivist")
if not talkEvent then
	talkEvent = Instance.new("BindableEvent")
	talkEvent.Name = "TalkArchivist"
	talkEvent.Parent = script.Parent
end

local lobby = workspace:WaitForChild("Lobby")
local rig = lobby:WaitForChild("Archivist", 30)
if not rig then
	warn("[Archivist] no archivist in the lobby")
	return
end
local head = rig:WaitForChild("Head", 10) :: BasePart?
local upperTorso = rig:WaitForChild("UpperTorso", 10) :: BasePart?
local root = rig:WaitForChild("HumanoidRootPart", 10) :: BasePart?
if not head or not upperTorso or not root then
	warn("[Archivist] the archivist rig is incomplete")
	return
end
local neck = head:WaitForChild("Neck", 10)

------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------
local talking = false
local writingUntil = 0 -- head bowed over the ledger until then
local rng = Random.new()

-- the spot on the desk where the ledger lies (desk top ~3.1 studs, ~1.7 studs in front of him)
local function ledgerPoint(): Vector3
	local p = (root.CFrame * CFrame.new(0, 0, -1.7)).Position
	return Vector3.new(p.X, 3.2, p.Z)
end

local function scratch()
	Sfx.at(ledgerPoint(), "LedgerScratch", { jitter = 0.1 })
end

local function playerHead(): BasePart?
	local character = player.Character
	local myHead = character and character:FindFirstChild("Head") :: BasePart?
	if myHead and (myHead.Position - head.Position).Magnitude < LOOK_RANGE then
		return myHead
	end
	return nil
end

------------------------------------------------------------------------------------------
-- Head tracking (same technique as Guide.client): newer rigs joint the head with an
-- AnimationConstraint (turn its torso-side attachment), classic rigs with a Motor6D (turn C0).
------------------------------------------------------------------------------------------
if neck and (neck:IsA("AnimationConstraint") or neck:IsA("Motor6D")) then
	local neckAttachment = if neck:IsA("AnimationConstraint") then neck.Attachment0 else nil
	local neckRest: CFrame = if neckAttachment then neckAttachment.CFrame else (neck :: Motor6D).C0
	local yaw, pitch = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local targetYaw, targetPitch = 0, 0
		local myHead = playerHead()
		if os.clock() < writingUntil and not talking then
			-- bent over the ledger, the pen moving a little
			targetPitch = WRITE_PITCH
			targetYaw = math.rad(4) * math.sin(os.clock() * 1.7)
		elseif myHead then
			local rel = upperTorso.CFrame:PointToObjectSpace(myHead.Position)
			local neckY = neckRest.Position.Y
			targetYaw = math.clamp(math.atan2(-rel.X, -rel.Z), math.rad(-65), math.rad(65))
			targetPitch =
				math.clamp(math.atan2(rel.Y - neckY, Vector2.new(rel.X, rel.Z).Magnitude), math.rad(-25), math.rad(22))
		end
		local alpha = math.min(dt * TRACK_RATE, 1)
		yaw += (targetYaw - yaw) * alpha
		pitch += (targetPitch - pitch) * alpha
		local pose = neckRest * CFrame.Angles(pitch, yaw, 0)
		if neckAttachment then
			neckAttachment.CFrame = pose
		else
			(neck :: Motor6D).C0 = pose
		end
	end)
end

-- Now and then he goes back to his writing, unless someone is talking to him or standing close.
task.spawn(function()
	while rig.Parent do
		task.wait(rng:NextNumber(7, 16))
		local myHead = playerHead()
		local close = myHead and (myHead.Position - head.Position).Magnitude < 10
		if not talking and not close then
			writingUntil = os.clock() + rng:NextNumber(2.5, 4.5)
			task.wait(0.6)
			if os.clock() < writingUntil and (myHead or rng:NextNumber() < 0.5) then
				scratch() -- only worth the sound when someone's around to hear it (it's positional anyway)
			end
		end
	end
end)

------------------------------------------------------------------------------------------
-- Ghost VFX: faint cold motes drifting up and off him, and a slow waver in his light
------------------------------------------------------------------------------------------
-- parented straight to the torso so the Box shape spawns them through its volume
local motes = Instance.new("ParticleEmitter")
motes.Name = "GhostMotes"
motes.Texture = "rbxasset://textures/particles/explosion01_implosion_main.dds" -- small soft dot
motes.Shape = Enum.ParticleEmitterShape.Box
motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
motes.Rate = 2.5
motes.Lifetime = NumberRange.new(3, 5.5)
motes.Speed = NumberRange.new(0.05, 0.25)
motes.SpreadAngle = Vector2.new(180, 180)
motes.Acceleration = Vector3.new(0, 0.18, 0)
motes.Drag = 0.5
motes.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.03),
	NumberSequenceKeypoint.new(0.5, 0.07),
	NumberSequenceKeypoint.new(1, 0.02),
})
motes.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.55),
	NumberSequenceKeypoint.new(0.7, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})
motes.Color = ColorSequence.new(GHOST)
motes.LightEmission = 1
motes.LightInfluence = 0
motes.Parent = upperTorso

local ghostLight = upperTorso:FindFirstChild("GhostLight") :: PointLight?
if ghostLight then
	local base = ghostLight.Brightness
	local dipUntil = 0
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local waver = 0.82 + 0.18 * math.noise(t * 0.6, 3.7)
		if t < dipUntil then
			waver *= 0.35 -- he thins out for a moment
		elseif rng:NextNumber() < 0.0015 then
			dipUntil = t + rng:NextNumber(0.08, 0.25)
		end
		ghostLight.Brightness = base * waver
	end)
end

------------------------------------------------------------------------------------------
-- Whispered greeting when you step onto his ring
------------------------------------------------------------------------------------------
local nameTag = head:FindFirstChild("NameTag") :: BillboardGui?
local bubbleToken = 0
local lastGreeting = 0
local lastLine: string? = nil

local function pickLine(): string?
	local lines = DialogueTrees.ArchivistGreetings
	if type(lines) ~= "table" or #lines == 0 then
		return nil
	end
	local line = lines[rng:NextInteger(1, #lines)]
	if line == lastLine and #lines > 1 then
		line = lines[(table.find(lines, line) :: number) % #lines + 1]
	end
	lastLine = line
	return line
end

local function whisper(text: string)
	bubbleToken += 1
	local token = bubbleToken
	local old = head:FindFirstChild("Whisper")
	if old then
		old:Destroy()
	end
	local gui = UIKit.new("BillboardGui", {
		Name = "Whisper",
		Size = UDim2.fromOffset(250, 74),
		StudsOffset = Vector3.new(0, 2.6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 50,
		Parent = head,
	})
	local group = UIKit.new("CanvasGroup", {
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 6),
		Parent = gui,
	})
	-- cream paper card with a little tail pointing down at him
	UIKit.new("Frame", {
		Name = "Tail",
		BackgroundColor3 = Colors.paper,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(12, 12),
		Rotation = 45,
		Parent = group,
	}, { UIKit.stroke(Colors.ink, 1.5, 0.45) })
	UIKit.new("Frame", {
		Name = "Card",
		BackgroundColor3 = Colors.paper,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -12),
		Parent = group,
	}, {
		UIKit.corner(10),
		UIKit.stroke(Colors.ink, 1.5, 0.45),
		UIKit.new("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
		UIKit.new("TextLabel", {
			Name = "Line",
			Text = text,
			FontFace = SERIF_ITALIC,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = Colors.ink,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}),
	})
	if nameTag then
		nameTag.Enabled = false -- the bubble sits where his name would
	end
	UIKit.tween(group, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		GroupTransparency = 0,
		Position = UDim2.new(),
	})
	task.delay(BUBBLE_HOLD, function()
		if token ~= bubbleToken or not gui.Parent then
			return
		end
		local fade = UIKit.tween(group, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {
			GroupTransparency = 1,
			Position = UDim2.fromOffset(0, -6),
		})
		if fade then
			fade.Completed:Wait()
		else
			task.wait(0.7)
		end
		if token == bubbleToken then
			gui:Destroy()
			if nameTag then
				nameTag.Enabled = true
			end
		end
	end)
end

player:GetAttributeChangedSignal("AtStation"):Connect(function()
	if player:GetAttribute("AtStation") ~= "Challenges" then
		return
	end
	local now = os.clock()
	if now - lastGreeting < BUBBLE_COOLDOWN or talking then
		return
	end
	lastGreeting = now
	local line = pickLine()
	if line then
		whisper(line)
	end
	-- he makes a note of your arrival
	writingUntil = math.max(writingUntil, os.clock() + 0.3)
	task.delay(rng:NextNumber(0.5, 1), scratch)
end)

------------------------------------------------------------------------------------------
-- Talking (TalkArchivist -> DialogueTrees.Archivist)
------------------------------------------------------------------------------------------
local function fireEvent(name: string)
	local event = script.Parent:FindFirstChild(name) or script.Parent:WaitForChild(name, 5)
	if event and event:IsA("BindableEvent") then
		event:Fire()
	else
		warn("[Archivist] no " .. name .. " event to fire")
	end
end

local function talk()
	if talking then
		return
	end
	local tree = DialogueTrees.Archivist
	if not tree then
		warn("[Archivist] no dialogue tree")
		return
	end
	talking = true
	writingUntil = 0 -- look up from the ledger
	local ok, err = pcall(Dialogue.start, tree, {
		anchor = head,
		onAction = function(action: string)
			if action == "openChallenges" then
				fireEvent("OpenChallenges")
			end
		end,
		onClose = function()
			talking = false
			Remotes.get("Talked"):FireServer("Archivist")
		end,
	})
	if not ok then
		warn("[Archivist] dialogue failed: " .. tostring(err))
		talking = false
	end
end

talkEvent.Event:Connect(talk)
