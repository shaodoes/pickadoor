--[[
	The door room, from inside your own head (DoorRoomFlow is the server half; Shared.DoorPick the
	shared timeline).

	  Waiting   black, "Waiting for your party..."
	  Pick      fade in from black into a locked first-person view facing the doors (red Left, blue
	            Right); PICK A DOOR and the countdown at the top (UIKit style); the voice line
	            Config.Sounds.PickADoorVoice plays and is always subtitled (just the timed subtitle while
	            its id is 0). Walk into a door to choose it.
	  commit    (DoorEvent, to you alone) "open": the camera looks down, a first-person hand reaches out
	            and grips the handle, the handle turns, the leaf swings into the black (server), the
	            camera rises; "breathe" (someone opened it already): stop, look down, breathe, look up.
	            Then you step through into the black, the screen goes black, and the server puts you in
	            your world; the screen fades back in (Main shows the reveal card).
	  glitch    (DoorEvent) you didn't reach a door in time: static, tearing, colour-split flashes,
	            glitch audio, the room's walls and doors jitter, then black (the server kills you; you
	            come back at the Hold).
	First person is locked while your Status is Door / Committing / Glitch; anywhere else the camera is
	the default one.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DoorPick = require(Shared:WaitForChild("DoorPick"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local UIKit = require(Shared:WaitForChild("UIKit"))
local Worlds = require(Shared:WaitForChild("Worlds"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local Viewmodel = require(script.Parent:WaitForChild("Viewmodel"))

local player = Players.LocalPlayer
local C = UIKit.Colors
local doorRoom = workspace:WaitForChild("Trial"):WaitForChild("DoorRoom")
local doorsFolder = doorRoom:WaitForChild("Doors")

local VOICE_TEXT = "Pick a door. The door you choose will determine your fate for the next 24 hours."

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function tween(inst: Instance, time: number, goal: { [string]: any })
	local t = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Sine), goal)
	t:Play()
	return t
end

-- A Config.Sounds entry that has an asset id (0 = not set yet: skipped, the subtitle stands in).
local function playIf(name: string, jitter: number?)
	local def = Config.Sounds[name]
	if def and def.id ~= 0 then
		Sfx.play(name, jitter or 0)
	end
end

------------------------------------------------------------------------------------------
-- First person, controls
------------------------------------------------------------------------------------------
local defaultMode = player.CameraMode
local defaultMin = player.CameraMinZoomDistance
local defaultMax = player.CameraMaxZoomDistance
if defaultMode == Enum.CameraMode.LockFirstPerson or defaultMax <= 0.5 then
	defaultMode = StarterPlayer.CameraMode
	defaultMax = math.max(StarterPlayer.CameraMaxZoomDistance, 12)
	defaultMin = StarterPlayer.CameraMinZoomDistance
end
local locked = false

local WORLD_ZOOM = 10 -- leaving the door room: the camera pulls back out to this distance

local function firstPerson(on: boolean)
	if on == locked then
		return
	end
	locked = on
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMode = defaultMode
		player.CameraMaxZoomDistance = defaultMax
		-- a raised minimum for a moment pushes the camera back out of the head, then it's free again
		player.CameraMinZoomDistance = math.min(WORLD_ZOOM, defaultMax)
		task.delay(0.1, function()
			if not locked then
				player.CameraMinZoomDistance = defaultMin
			end
		end)
	end
end

local function lockControls(): () -> ()
	local ok, controls = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return module and (require(module) :: any):GetControls()
	end)
	if ok and controls then
		controls:Disable()
		return function()
			controls:Enable()
		end
	end
	return function() end
end

-- Every part of our own character, see-through to us (the camera sits inside the head).
local function hideBody(character: Model?, hidden: boolean)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		elseif d:IsA("BillboardGui") then
			-- (a held lantern's halo would hang in front of the camera)
			if hidden and d.Enabled then
				d:SetAttribute("SequenceHidden", true)
				d.Enabled = false
			elseif not hidden and d:GetAttribute("SequenceHidden") then
				d:SetAttribute("SequenceHidden", nil)
				d.Enabled = true
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- PICK A DOOR (top centre, the new glass style)
------------------------------------------------------------------------------------------
local ui = UIKit.new("ScreenGui", {
	Name = "DoorRoomUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	Parent = player:WaitForChild("PlayerGui"),
})
local holder = UIKit.new("Frame", {
	Name = "Pick",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(760, 210),
	Visible = false,
	Parent = ui,
})
UIKit.fit(holder)
local kicker = UIKit.new("TextLabel", {
	Name = "Kicker",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 22),
	FontFace = UIKit.Face.uiSemi,
	TextSize = 17,
	TextColor3 = C.accentGlow,
	Text = "RED  OR  BLUE",
	TextTransparency = 1,
	Parent = holder,
})
local title = UIKit.new("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 22),
	Size = UDim2.new(1, 0, 0, 84),
	FontFace = UIKit.Face.display,
	TextSize = 78,
	TextColor3 = C.paperLight,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 1,
	Text = "PICK A DOOR",
	TextTransparency = 1,
	Parent = holder,
})
local timerPill = UIKit.new("TextLabel", {
	Name = "Timer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 116),
	Size = UDim2.fromOffset(104, 46),
	FontFace = UIKit.Face.ui,
	TextSize = 28,
	TextColor3 = C.paper,
	Text = "15",
	TextTransparency = 1,
	Parent = holder,
})
UIKit.glass(timerPill, { flat = true, radius = 23 })
local pillStroke = timerPill:FindFirstChildOfClass("UIStroke")
local pillScale = UIKit.new("UIScale", { Parent = timerPill })
local hint = UIKit.new("TextLabel", {
	Name = "Hint",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 172),
	Size = UDim2.new(1, 0, 0, 26),
	FontFace = UIKit.Face.body,
	TextSize = 20,
	TextColor3 = C.paper,
	Text = "Walk up to the door you trust.",
	TextTransparency = 1,
	Parent = holder,
})

local titleShown = false
local function showTitle(on: boolean)
	if on == titleShown then
		return
	end
	titleShown = on
	if on then
		holder.Visible = true
		tween(kicker, 0.6, { TextTransparency = 0.1 })
		tween(title, 0.6, { TextTransparency = 0, TextStrokeTransparency = 0.7 })
		tween(timerPill, 0.6, { TextTransparency = 0, BackgroundTransparency = UIKit.Theme.glassAlpha })
		tween(hint, 0.8, { TextTransparency = 0.3 })
	else
		for _, label in { kicker, title, hint } do
			tween(label, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		tween(timerPill, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.delay(0.4, function()
			if not titleShown then
				holder.Visible = false
			end
		end)
	end
end
timerPill.BackgroundTransparency = 1

local lastTick = -1
local function setTimer(t: number)
	timerPill.Text = tostring(t)
	if t == lastTick or t <= 0 then
		lastTick = t
		return
	end
	lastTick = t
	local hot = t <= 3
	timerPill.TextColor3 = if hot then C.creamHot else C.paper
	if pillStroke then
		pillStroke.Color = if hot then C.danger else C.line
	end
	pillScale.Scale = 1.15
	TweenService:Create(pillScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	if titleShown then
		if hot then
			playIf("PickTickHot")
		else
			playIf("PickTick", 0.04)
		end
	end
end

------------------------------------------------------------------------------------------
-- Door helpers
------------------------------------------------------------------------------------------
type DoorParts = {
	model: Instance,
	leaf: BasePart,
	handle: BasePart,
	rose: BasePart,
	plaque: BasePart,
	stand: BasePart,
	closed: CFrame,
}
local function doorParts(name: string): DoorParts?
	local model = doorsFolder:FindFirstChild(name)
	if not model then
		return nil
	end
	local leaf = model:FindFirstChild("Leaf") :: BasePart
	local closed = leaf:GetAttribute("ClosedCFrame")
	return {
		model = model,
		leaf = leaf,
		handle = model:FindFirstChild("Handle") :: BasePart,
		rose = model:FindFirstChild("Rose") :: BasePart,
		plaque = model:FindFirstChild("Plaque") :: BasePart,
		stand = model:FindFirstChild("Stand") :: BasePart,
		closed = if typeof(closed) == "CFrame" then closed else leaf.CFrame,
	}
end

-- Stamp the world's name onto the door's blank brass plaque (only this client sees it).
local function stampPlaque(plaque: BasePart, text: string)
	local old = plaque:FindFirstChild("Stamp")
	if old then
		old:Destroy()
	end
	local gui = UIKit.new("SurfaceGui", {
		Name = "Stamp",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 120,
		LightInfluence = 0.8,
		Parent = plaque,
	})
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = UIKit.Face.serif,
		TextScaled = true,
		Text = string.upper(text),
		TextColor3 = Color3.fromRGB(52, 34, 14),
		TextTransparency = 1,
		Parent = gui,
	}, { UIKit.new("UIPadding", { PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) }) })
	tween(label, 0.25, { TextTransparency = 0.05 })
end

------------------------------------------------------------------------------------------
-- The commit sequence
------------------------------------------------------------------------------------------
local active: any = nil -- the running sequence's token
local restoreControls: (() -> ())? = nil

-- the other trial HUDs (items hotbar, overlay) step aside during the door sequence
local function setHud(visible: boolean)
	for _, name in { "ItemsUI", "TrialUI" } do
		local g = player.PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			g.Enabled = visible
		end
	end
end

local function endSequence()
	active = nil
	setHud(true)
	RunService:UnbindFromRenderStep("DoorRoomSequence")
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	hideBody(character, false)
	Screen.vignette(0, 0.3)
	if restoreControls then
		restoreControls()
		restoreControls = nil
	end
end

local function runCommit(data)
	local parts = doorParts(data.door)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not parts or not humanoid or not root then
		return
	end
	local token = {}
	active = token
	showTitle(false)
	setHud(false)
	restoreControls = lockControls()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local world = Worlds.get(data.world)
	local opening = data.mode == "open"
	local t0, stepT = data.t0, data.stepAt - data.t0

	local closed = parts.closed
	local out = Vector3.new(closed.LookVector.X, 0, closed.LookVector.Z).Unit -- from the door into the room
	local center = closed.Position -- the leaf's centre (4.5 up)
	local hingeSide = parts.leaf:GetAttribute("HingeSide") or 1
	local side = -hingeSide -- the handle is on the latch side: reach with that hand
	local standAt = if opening then parts.stand.Position else center + out * 2.8
	humanoid:MoveTo(Vector3.new(standAt.X, root.Position.Y, standAt.Z))
	local voidPoint = Vector3.new(center.X, root.Position.Y, center.Z) - out * 6.5

	-- the lever turns about the rose (its X axis is the leaf normal); pick the way that lowers its end
	local handleRest = parts.handle.CFrame
	local pivot = parts.rose.Position
	local axis = parts.rose.CFrame.XVector
	local lever = parts.handle.Position - pivot
	local turnSign = if CFrame.fromAxisAngle(axis, 0.6):VectorToWorldSpace(lever).Y
			< CFrame.fromAxisAngle(axis, -0.6):VectorToWorldSpace(lever).Y
		then 1
		else -1
	local TURN_ANGLE = math.rad(38)

	local arm = if opening then Viewmodel.new(character, side) else nil
	local stamped, stepped, breathed = false, false, false

	RunService:BindToRenderStep("DoorRoomSequence", Enum.RenderPriority.Camera.Value + 1, function()
		if active ~= token then
			return
		end
		local t = workspace:GetServerTimeNow() - t0
		hideBody(character, true)
		local head = character:FindFirstChild("Head") :: BasePart?
		local eye = (if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)) + Vector3.new(0, 0.15, 0)
		local ahead = Vector3.new(center.X, eye.Y, center.Z)
		local deep = Vector3.new(center.X, eye.Y - 0.4, center.Z) - out * 10
		local look
		if opening then
			local down = smooth(t / DoorPick.LOOK_DOWN)
			local up = smooth((t - DoorPick.RISE) / (DoorPick.OPEN_LEN - DoorPick.RISE))
			look = ahead:Lerp(parts.handle.Position, down * 0.9):Lerp(deep, up)
		else
			local down = smooth(t / 0.7)
			local up = smooth((t - (DoorPick.BREATHE_LEN - 0.7)) / 0.7)
			local floor = Vector3.new(center.X, root.Position.Y - 3, center.Z) + out * 0.6
			look = ahead:Lerp(floor, down * 0.85):Lerp(deep, up)
			-- slow breathing: the view rises and sinks
			local held = down * (1 - up)
			eye += Vector3.new(0, math.sin(t * math.pi * 2 / 1.7) * 0.08 * held, 0)
			if not breathed and t > 0.4 then
				breathed = true
				playIf("Breath")
				Screen.caption("[A slow breath.]", 2)
				Screen.vignette(0.55, 0.6)
				task.delay(DoorPick.BREATHE_LEN - 0.9, function()
					if active == token then
						Screen.vignette(0, 0.8)
					end
				end)
			end
		end
		if t >= stepT then
			look = deep
		end
		camera.CFrame = CFrame.lookAt(eye, look)

		-- the hand: reach, grip, turn, let go
		if arm then
			local cam = camera.CFrame
			-- the arm comes in from low on the handle's side, so the hand isn't hidden behind the sleeve
			local shoulder = cam:PointToWorldSpace(Vector3.new(side * 1.25, -1.45, 0.2))
			local rest = cam:PointToWorldSpace(Vector3.new(side * 0.8, -1.7, -0.3))
			local turn = smooth((t - DoorPick.GRIP - 0.05) / (DoorPick.TURN - DoorPick.GRIP - 0.05))
			if t < DoorPick.LEAF_AT then
				-- (the server's swing takes the handle over from LEAF_AT; it springs back as it goes)
				parts.handle.CFrame = CFrame.new(pivot)
					* CFrame.fromAxisAngle(axis, turnSign * TURN_ANGLE * turn)
					* CFrame.new(-pivot)
					* handleRest
			end
			local grip = parts.handle.Position + Vector3.new(0, 0.08, 0)
			local towardGrip = (grip - shoulder).Unit
			local gripWrist = grip - towardGrip * 0.42
			local reach = smooth((t - DoorPick.LOOK_DOWN * 0.4) / (DoorPick.GRIP - DoorPick.LOOK_DOWN * 0.4))
			local release = smooth((t - DoorPick.LEAF_AT - 0.05) / 0.7)
			local wrist = rest:Lerp(gripWrist, reach):Lerp(rest, release)
			local curl = smooth((t - DoorPick.GRIP + 0.3) / 0.3) * (1 - release)
			arm.pose(shoulder, wrist, curl)
			arm.show(release < 0.99)
			if not stamped and t >= DoorPick.GRIP then
				stamped = true
				playIf("HandleTurn", 0.05)
				if world then
					stampPlaque(parts.plaque, world.name)
				end
			end
		elseif not stamped and world then
			stamped = true
			stampPlaque(parts.plaque, world.name)
		end

		-- the step into the black
		if not stepped and t >= stepT then
			stepped = true
			if arm then
				arm.destroy()
				arm = nil
			end
			humanoid:MoveTo(voidPoint)
			playIf("VoidStep")
			task.delay(math.max(0, DoorPick.STEP_LEN - DoorPick.FADE_TIME), function()
				if active == token then
					Screen.fade(1, DoorPick.FADE_TIME)
				end
			end)
		end
	end)

	-- safety: if the world never arrives, give the camera back
	task.delay(stepT + DoorPick.STEP_LEN + 6, function()
		if active == token then
			if arm then
				arm.destroy()
			end
			endSequence()
			Screen.fade(0, 0.6)
		end
	end)
end

------------------------------------------------------------------------------------------
-- The glitch-out
------------------------------------------------------------------------------------------
local function runGlitch()
	showTitle(false)
	local token = {}
	active = token
	restoreControls = lockControls()
	local length = DoorPick.GLITCH_LEN
	Screen.glitch(length)
	Screen.caption("[The room comes apart.]", length)
	playIf("GlitchBurst", 0.2)
	for i = 1, 4 do
		task.delay(i * length / 5 + math.random() * 0.2, function()
			playIf("GlitchBurst", 0.3)
		end)
	end
	task.delay(length - 0.5, function()
		playIf("GlitchRing")
	end)

	-- the room jitters around you (local only; doors that are standing open are left alone)
	local jitter: { { part: BasePart, cf: CFrame } } = {}
	for _, d in doorRoom:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local door = d:FindFirstAncestorWhichIsA("Model")
			local swinging = d:GetAttribute("Swing") and door and door:GetAttribute("Open")
			if not swinging and (d.Size.Magnitude > 2 or d:GetAttribute("Swing")) then
				table.insert(jitter, { part = d, cf = d.CFrame })
			end
		end
	end
	local camera = workspace.CurrentCamera
	local fov = camera.FieldOfView
	local start = os.clock()
	local rng = Random.new()
	RunService:BindToRenderStep("DoorRoomGlitch", Enum.RenderPriority.Camera.Value + 1, function()
		local a = math.clamp((os.clock() - start) / length, 0, 1)
		local k = 0.15 + a * 0.85
		for _, j in jitter do
			if rng:NextNumber() < 0.35 then
				j.part.CFrame = j.cf
					* CFrame.new(
						rng:NextNumber(-0.4, 0.4) * k,
						rng:NextNumber(-0.3, 0.3) * k,
						rng:NextNumber(-0.4, 0.4) * k
					)
			end
		end
		camera.CFrame *= CFrame.Angles(
			rng:NextNumber(-0.03, 0.03) * k,
			rng:NextNumber(-0.04, 0.04) * k,
			rng:NextNumber(-0.06, 0.06) * k
		)
		camera.FieldOfView = fov + rng:NextNumber(-12, 18) * k
	end)
	task.delay(length, function()
		RunService:UnbindFromRenderStep("DoorRoomGlitch")
		for _, j in jitter do
			j.part.CFrame = j.cf
		end
		camera.FieldOfView = fov
		Screen.fade(1, 0.08)
		if active == token then
			active = nil
			if restoreControls then
				restoreControls()
				restoreControls = nil
			end
		end
	end)
end

Remotes.get("DoorEvent").OnClientEvent:Connect(function(kind, data)
	if kind == "commit" and typeof(data) == "table" then
		task.spawn(runCommit, data)
	elseif kind == "glitch" then
		task.spawn(runGlitch)
	end
end)

------------------------------------------------------------------------------------------
-- Phases and status
------------------------------------------------------------------------------------------
local lastPhase: string? = nil
local lastStatus: string? = nil

-- Turn the first-person camera to face the doors (once, before the camera scripts run).
local facing = false
local function faceDoors()
	if facing then
		return
	end
	facing = true
	RunService:BindToRenderStep("DoorRoomFace", Enum.RenderPriority.Camera.Value - 1, function()
		RunService:UnbindFromRenderStep("DoorRoomFace")
		facing = false
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head then
			local camera = workspace.CurrentCamera
			camera.CFrame = CFrame.lookAt(head.Position, head.Position + Vector3.new(0, 0, -1))
		end
	end)
end

local function startPick()
	Screen.status(nil)
	faceDoors()
	task.delay(0.35, function()
		Screen.fade(0, 1.4)
	end)
	task.delay(0.7, function()
		if player:GetAttribute("Status") ~= "Door" or workspace:GetAttribute("Phase") ~= "Pick" then
			return
		end
		showTitle(true)
		playIf("PickChime", 0.02)
		local voice = Config.Sounds.PickADoorVoice
		playIf("PickADoorVoice")
		Screen.caption(VOICE_TEXT, voice.length or 5)
	end)
end

local function update()
	local phase = workspace:GetAttribute("Phase") or "Waiting"
	local status = player:GetAttribute("Status") or "Door"
	local phaseChanged, statusChanged = phase ~= lastPhase, status ~= lastStatus
	local previousStatus = lastStatus
	lastPhase, lastStatus = phase, status

	firstPerson(status == "Door" or status == "Committing" or status == "Glitch")
	if status ~= "Door" then
		showTitle(false)
	end

	if status == "Door" and phase == "Waiting" then
		if phaseChanged or statusChanged then
			Screen.fade(1, 0.5)
			Screen.status("Waiting for your party...")
		end
	elseif status == "Door" and phase == "Pick" then
		if phaseChanged then
			startPick()
		end
		setTimer(workspace:GetAttribute("TimeLeft") or 0)
	end

	if statusChanged then
		if status == "In" then
			-- arrived in a world: give the camera back and fade in
			if active then
				endSequence()
			end
			firstPerson(false)
			task.delay(0.35, function()
				Screen.fade(0, 0.8)
			end)
		elseif status == "Escaped" then
			Screen.fade(1, 0.15)
			task.delay(0.5, function()
				Screen.fade(0, 0.8)
			end)
		elseif status == "Spectating" or (status == "Dead" and previousStatus ~= "Glitch") then
			Screen.status(nil)
		end
	end

	if phase == "Return" and (workspace:GetAttribute("TimeLeft") or 0) <= 1 then
		Screen.fade(1, 0.9)
	end
end

for _, name in { "Phase", "TimeLeft" } do
	workspace:GetAttributeChangedSignal(name):Connect(update)
end
player:GetAttributeChangedSignal("Status"):Connect(update)

-- a new body: back from the dead (the Hold) or a respawn during Pick: fade in unless we're waiting
player.CharacterAdded:Connect(function()
	task.wait(0.6)
	local status = player:GetAttribute("Status")
	local phase = workspace:GetAttribute("Phase")
	if status == "Door" and phase ~= "Pick" then
		return
	end
	if status == "Door" then
		faceDoors()
	end
	Screen.status(nil)
	Screen.fade(0, 0.8)
end)

update()
if workspace:GetAttribute("Phase") ~= "Waiting" and player:GetAttribute("Status") ~= "Door" then
	Screen.fade(0, 0.8) -- joined mid-round: no black hold
elseif workspace:GetAttribute("Phase") == "Pick" then
	startPick()
end
