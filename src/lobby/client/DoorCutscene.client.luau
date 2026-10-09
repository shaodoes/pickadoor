--[[
	The door-entry cutscene, from inside the party (code-authored in place of a Moon Animator track).
	Starts when the server sets this player's CutscenePad attribute and runs on the shared DoorEntry
	timeline (t = 0 at the pad's CutsceneStart, server time), so a whole party sees it in step:

	  0.0 - 2.0  shot 1  over the party's shoulders, slow push in while the door creaks fully open
	  2.0 - 4.5  shot 2  low side angle: the party walks through one after another (this client walks
	             its own character; the server issues the same MoveTo path as a fallback)
	  4.5 - 5.6  shot 3  hold on the empty doorway; the light gutters; the door slams (shake + boom); black
	  5.75 -     title   "PICK A DOOR" sprayed on in red over black, until the server teleports us or, in
	             Studio, puts us back at the pad's Exit and clears CutscenePad (we fade back in)

	Meanwhile: controls locked, HUD (every other ScreenGui, core GUI, proximity prompts) hidden, letterbox
	bars in, music and ambience ducked. Door / light / fog / slam SFX and the party fading into the dark
	are DoorFX's (onlookers see those too).
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cutscene = require(Shared:WaitForChild("Cutscene"))
local DoorEntry = require(Shared:WaitForChild("DoorEntry"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local pads = workspace:WaitForChild("Lobby"):WaitForChild("Pads")

local SPRAY_FONT = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)
local LABEL_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local PAINT = Color3.fromRGB(196, 34, 28) -- same spray red as the wall stencil (Signage)
local PAINT_DARK = Color3.fromRGB(72, 14, 12)
local CREAM = Color3.fromRGB(238, 226, 200)

local HIDE_CORE = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.Backpack,
}

local function tween(
	inst: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		goal
	)
	tw:Play()
	return tw
end

------------------------------------------------------------------------------------------
-- Lock / hide / duck (each returns its own undo)
------------------------------------------------------------------------------------------
local function hideHud(): () -> ()
	local hidden: { ScreenGui } = {}
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and string.sub(g.Name, 1, 9) ~= "Cutscene_" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local core: { [Enum.CoreGuiType]: boolean } = {}
	for _, kind in HIDE_CORE do
		local ok, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
		if ok then
			core[kind] = was
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
		end
	end
	local prompts = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false
	return function()
		for _, g in hidden do
			if g.Parent then
				g.Enabled = true
			end
		end
		for kind, was in core do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, was)
		end
		ProximityPromptService.Enabled = prompts
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

local function duckAudio(): () -> ()
	local music = Sfx.group("Music")
	local ambience = Sfx.group("Ambience")
	local m, a = music.Volume, ambience.Volume
	tween(music, 0.8, { Volume = m * 0.15 }, Enum.EasingStyle.Sine)
	tween(ambience, 0.8, { Volume = a * 0.55 }, Enum.EasingStyle.Sine)
	return function()
		tween(music, 1.5, { Volume = m }, Enum.EasingStyle.Sine)
		tween(ambience, 1.5, { Volume = a }, Enum.EasingStyle.Sine)
	end
end

------------------------------------------------------------------------------------------
-- Camera: three shots in the door's frame (centre of the opening on the floor, +Z out into the hall).
-- The side shot always sits on the hall's +X side of the door: the leaf hinges on -X and swings out,
-- so from +X it frames the doorway instead of blocking it.
------------------------------------------------------------------------------------------
local function buildShots(pad: Instance): { Cutscene.Shot }
	local f = DoorEntry.frame(pad)
	local function p(x: number, y: number, z: number): Vector3
		return f:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local over = Cutscene.track({
		{ t = 0, pos = p(2.2, 8.6, 17.5), look = p(0, 4.1, 0), fov = 62 },
		{ t = 1.1, pos = p(1.5, 7.6, 14.2), look = p(0, 4.3, -0.5), fov = 57 },
		{ t = 2.0, pos = p(0.9, 6.9, 11.8), look = p(0, 4.4, -1.6), fov = 52, roll = math.rad(-1) },
	}, { ease = Cutscene.bezier(0.3, 0, 0.35, 1) })
	local side = Cutscene.track({
		{ t = 0, pos = p(6.2, 1.35, 4.8), look = p(-0.6, 3.4, -0.6), fov = 56, roll = math.rad(2) },
		{ t = 2.5, pos = p(5.2, 1.1, 3.1), look = p(-0.4, 3.9, -1.8), fov = 49, roll = math.rad(1) },
	}, { ease = Cutscene.ease.quadOut })
	local doorway = Cutscene.track({
		{ t = 0, pos = p(0.4, 4.7, 10.8), look = p(0, 4.2, -1), fov = 48 },
		{ t = 1.5, pos = p(0.2, 4.5, 9.3), look = p(0, 4.2, -1.6), fov = 45 },
	}, { ease = Cutscene.ease.sineInOut })
	return {
		{ start = -10, track = over }, -- also covers the short lead-in before t = 0
		{ start = DoorEntry.SHOT2, track = side },
		{ start = DoorEntry.SHOT3, track = doorway },
	}
end

------------------------------------------------------------------------------------------
-- Title card: PICK A DOOR sprayed on over black (misregistered dark coat, overspray, runs)
------------------------------------------------------------------------------------------
local function titleCard(parent: Instance, subtitle: string): Frame
	local holder = Instance.new("Frame")
	holder.Name = "TitleCard"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 20
	holder.Parent = parent

	local box = Instance.new("Frame")
	box.Name = "Lettering"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.44)
	box.Size = UDim2.fromScale(0.78, 0.2)
	box.Rotation = -2
	box.ZIndex = 20
	box.Parent = holder
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 5
	aspect.Parent = box

	local reveals: { UIGradient } = {}
	local function layer(name: string, color: Color3, offset: Vector2, scale: number, transparency: number, z: number)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		label.Size = UDim2.fromScale(scale, scale)
		label.FontFace = SPRAY_FONT
		label.TextScaled = true
		label.Text = "PICK A DOOR"
		label.TextColor3 = color
		label.TextTransparency = transparency
		label.ZIndex = z
		label.Parent = box
		-- sprayed on left to right: a soft edge sweeps across
		local reveal = Instance.new("UIGradient")
		reveal.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.46, 0),
			NumberSequenceKeypoint.new(0.54, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		reveal.Offset = Vector2.new(-1, 0)
		reveal.Parent = label
		table.insert(reveals, reveal)
		return label
	end
	layer("Overspray", PAINT, Vector2.new(0, 0), 1.08, 0.86, 21)
	layer("Overspray2", PAINT, Vector2.new(2, -1), 1.04, 0.8, 21)
	layer("FirstCoat", PAINT_DARK, Vector2.new(5, 4), 1, 0, 22)
	local main = layer("Paint", PAINT, Vector2.zero, 1, 0, 23)
	for i, reveal in reveals do
		task.delay((i - 1) * 0.02, function()
			tween(reveal, 0.55, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end)
	end

	-- runs: paint dribbling down from under the letters once it's on
	local rng = Random.new()
	for i = 1, 8 do
		local x = 0.08 + (i - 1) / 7 * 0.84 + rng:NextNumber(-0.03, 0.03)
		local run = Instance.new("Frame")
		run.Name = "Run"
		run.BorderSizePixel = 0
		run.BackgroundColor3 = PAINT
		run.Position = UDim2.fromScale(x, rng:NextNumber(0.72, 0.86))
		run.Size = UDim2.fromOffset(rng:NextInteger(2, 4), 0)
		run.ZIndex = 22
		run.Parent = box
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = run
		task.delay(0.1 + x * 0.55, function()
			tween(
				run,
				rng:NextNumber(1.2, 2.4),
				{ Size = UDim2.new(0, run.Size.X.Offset, 0.25, rng:NextInteger(8, 50)) },
				Enum.EasingStyle.Sine
			)
		end)
	end

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.6)
	sub.Size = UDim2.fromScale(0.6, 0.04)
	sub.FontFace = LABEL_FONT
	sub.TextScaled = true
	sub.Text = subtitle
	sub.Visible = subtitle ~= ""
	sub.TextColor3 = CREAM
	sub.TextTransparency = 1
	sub.ZIndex = 23
	sub.Parent = holder
	task.delay(0.7, function()
		tween(sub, 0.6, { TextTransparency = 0.25 }, Enum.EasingStyle.Sine)
	end)

	-- one misprint flicker, like the wall stencil
	task.delay(1.1, function()
		if main.Parent then
			main.Text = "YOU PICKED"
			main.Position = UDim2.new(0.5, 6, 0.5, -3)
			task.delay(0.09, function()
				main.Text = "PICK A DOOR"
				main.Position = UDim2.fromScale(0.5, 0.5)
			end)
		end
	end)
	return holder
end

------------------------------------------------------------------------------------------
-- Walking our own character in (the client owns its physics, so this is the reliable half)
------------------------------------------------------------------------------------------
type Session = {
	pad: Instance,
	start: number,
	director: any,
	undo: { () -> () },
	conn: RBXScriptConnection?,
	fired: { [string]: boolean },
	title: Frame?,
	savedSpeed: number?,
	humanoid: Humanoid?,
}
local active: Session? = nil

local function walkIn(session: Session, slot: number, count: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	session.humanoid = humanoid
	session.savedSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = DoorEntry.WALK_SPEED
	for _, point in DoorEntry.walkPoints(session.pad, slot, count) do
		humanoid:MoveTo(point)
		local t0 = os.clock()
		while os.clock() - t0 < 1.4 do
			task.wait()
			if active ~= session or humanoid.Health <= 0 or not root.Parent then
				return
			end
			if ((root.Position - point) * Vector3.new(1, 0, 1)).Magnitude < 1 then
				break
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Session
------------------------------------------------------------------------------------------
local function finish(session: Session)
	if active ~= session then
		return
	end
	active = nil
	if session.conn then
		session.conn:Disconnect()
	end
	local humanoid = session.humanoid
	if humanoid and humanoid.Parent then
		if session.savedSpeed and humanoid.WalkSpeed == DoorEntry.WALK_SPEED then
			humanoid.WalkSpeed = session.savedSpeed
		end
		local root = humanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			humanoid:MoveTo(root.Position) -- cancel any leftover walk
		end
	end
	local director = session.director
	director:stopCamera()
	if session.title then
		for _, obj in session.title:GetDescendants() do
			if obj:IsA("TextLabel") then
				tween(obj, 0.35, { TextTransparency = 1 })
			elseif obj:IsA("Frame") and obj.BackgroundTransparency < 1 then
				tween(obj, 0.35, { BackgroundTransparency = 1 })
			end
		end
	end
	for i = #session.undo, 1, -1 do
		session.undo[i]()
	end
	task.delay(0.25, function()
		director:letterbox(false, 0.6)
		director:fade(0, 0.7)
	end)
	task.delay(1.4, function()
		director:destroy()
	end)
end

local function begin(pad: Instance)
	if active then
		finish(active)
	end
	-- the server stamps CutsceneStart before CutscenePad; give replication a moment just in case
	local start = pad:GetAttribute("CutsceneStart")
	local waited = 0
	while typeof(start) ~= "number" and waited < 1 do
		waited += task.wait()
		start = pad:GetAttribute("CutsceneStart")
	end
	if player:GetAttribute("CutscenePad") ~= pad.Name or (active and active.pad == pad) then
		return -- cleared (or already started) while we waited
	end
	if typeof(start) ~= "number" then
		start = workspace:GetServerTimeNow()
	end
	local function clock(): number
		return workspace:GetServerTimeNow() - (start :: number)
	end

	local director = Cutscene.new("DoorEntry")
	local session: Session = {
		pad = pad,
		start = start :: number,
		director = director,
		undo = {},
		conn = nil,
		fired = {},
		title = nil,
	}
	active = session
	table.insert(session.undo, hideHud())
	table.insert(session.undo, lockControls())
	table.insert(session.undo, duckAudio())
	director:letterbox(true, 0.6)
	director:run(buildShots(pad), clock)

	local slot = player:GetAttribute("CutsceneSlot") or 1
	local count = pad:GetAttribute("CutsceneCount") or 1

	local function at(name: string, t: number, ct: number, fn: () -> ())
		if ct >= t and not session.fired[name] then
			session.fired[name] = true
			fn()
		end
	end
	session.conn = RunService.Heartbeat:Connect(function()
		local ct = clock()
		at("walk", DoorEntry.walkStart(slot), ct, function()
			task.spawn(walkIn, session, slot, count)
		end)
		at("slam", DoorEntry.SLAM, ct, function()
			director:shake(0.045, 0.55, 20)
			Sfx.play("CutsceneBoom", 0.03)
		end)
		at("black", DoorEntry.BLACK, ct, function()
			director:fade(1, 0.08)
		end)
		at("title", DoorEntry.TITLE, ct, function()
			session.title = titleCard(director.gui, "") -- no subtitle under PICK A DOOR
			Sfx.play("TitleSpray", 0.05)
			Sfx.play("CutsceneSting", 0)
		end)
		-- the server always clears CutscenePad; this is only a safety net if that never arrives
		if ct > DoorEntry.LENGTH + 25 then
			finish(session)
		end
	end)
end

local function onAttribute()
	local padName = player:GetAttribute("CutscenePad")
	if typeof(padName) == "string" then
		local pad = pads:FindFirstChild(padName)
		if pad and not (active and active.pad == pad) then
			task.spawn(begin, pad)
		end
	elseif active then
		finish(active)
	end
end
player:GetAttributeChangedSignal("CutscenePad"):Connect(onAttribute)
onAttribute()
