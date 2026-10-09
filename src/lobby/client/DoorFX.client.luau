-- Door wall VFX (client-only, so every player sees their own glitches):
--   doors     light leaks from underneath and builds with the pad countdown; the door rattles
--             near zero and swings open onto black when the party leaves
--   plaques   titles above the doors glitch to other words (their shadow layer jumps with them);
--             the count and its black strip pulse red in the last seconds
--   PICK A DOOR breathes a red glow (light + overspray halo), drips, and occasionally says something
--             else; every paint layer jumps off-register together
-- Optional decoration from Signage is found by attribute: GUI children tagged SignLayer move/retext
-- with the main label, SignHalo ones breathe. Anything missing is simply skipped.
--   clock     the second hand ticks and slips back; while any pad counts down the hands run backwards
--   entry     when a party goes through (pad CutsceneStart), everyone sees the same thing on the shared
--             DoorEntry timeline: the door creaks fully open, light pours out, fog rolls over the threshold,
--             the party walks in and fades into the black, the light gutters and the door slams (onlookers
--             close by get a small camera jolt; the party's own camera is DoorCutscene's)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DoorEntry = require(Shared:WaitForChild("DoorEntry"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local localPlayer = Players.LocalPlayer

local lobby = workspace:WaitForChild("Lobby")
local pads = lobby:WaitForChild("Pads")
local queue = lobby:WaitForChild("Queue")

local HOT_RED = Color3.fromRGB(230, 50, 40)

local LABEL_GLITCHES = {
	Solo = { "ALONE", "S0LO", "JUST YOU" },
	Duo = { "BOTH", "DU0", "ONE OF YOU" },
	Squad = { "ALL OF YOU", "SQU4D", "NOT ALL" },
}
local STENCIL_GLITCHES = { "ONLY ONE OPENS", "PICK ONE", "YOU ALREADY DID", "DON'T", "PICK  A  DOOR" }

-- Decorative layers that travel with a label: siblings tagged SignLayer, with their resting state.
type Layer = { obj: GuiObject, pos: UDim2, text: string? }
local function layersOf(label: TextLabel): { Layer }
	local out = {}
	local gui = label.Parent
	if not gui then
		return out
	end
	for _, child in gui:GetChildren() do
		if child ~= label and child:IsA("GuiObject") and child:GetAttribute("SignLayer") then
			table.insert(out, {
				obj = child,
				pos = child.Position,
				text = if child:IsA("TextLabel") then child.Text else nil,
			})
		end
	end
	return out
end

-- Swap a label's text for a moment, nudged off-register like a misprint; its paint layers jump with it.
local function glitch(label: TextLabel, options: { string }, original: string, basePosition: UDim2, layers: { Layer }?)
	local word = options[math.random(#options)]
	local offset = UDim2.fromOffset(math.random(-8, 8), math.random(-4, 4))
	label.Text = word
	label.Position = basePosition + offset
	for _, layer in layers or {} do
		layer.obj.Position = layer.pos + offset
		if layer.text then
			(layer.obj :: TextLabel).Text = word
		end
	end
	task.delay(0.08 + math.random() * 0.2, function()
		label.Text = original
		label.Position = basePosition
		for _, layer in layers or {} do
			layer.obj.Position = layer.pos
			if layer.text then
				(layer.obj :: TextLabel).Text = layer.text
			end
		end
	end)
end

------------------------------------------------------------------------------------------
-- Door entry: onlooker camera jolt, and party members fading into the black as they go through
------------------------------------------------------------------------------------------
local jolt = { amp = 0, dur = 1, t0 = -math.huge, seed = 0 }
local function onlookerJolt(amp: number, duration: number)
	jolt.amp, jolt.dur, jolt.t0, jolt.seed = amp, duration, os.clock(), math.random() * 100
end

-- character -> how far it has faded (0 visible .. 1 gone)
local swallowed: { [Model]: number } = {}

local function setCharacterFade(character: Model, alpha: number)
	for _, obj in character:GetDescendants() do
		if obj:IsA("BasePart") or obj:IsA("Decal") then
			obj.LocalTransparencyModifier = alpha
		end
	end
end

-- After the camera scripts (their transparency controller would otherwise reset the local character).
RunService:BindToRenderStep("DoorEntryFX", Enum.RenderPriority.Camera.Value + 3, function(dt)
	-- onlookers' small jolt when a door slams nearby (additive on top of the normal camera this frame)
	local age = os.clock() - jolt.t0
	if age < jolt.dur then
		local k = jolt.amp * (1 - age / jolt.dur) ^ 2
		local x = age * 22
		local cam = workspace.CurrentCamera
		cam.CFrame *= CFrame.Angles(
			math.noise(x, jolt.seed, 0) * k,
			math.noise(x, jolt.seed, 7) * k,
			math.noise(x, jolt.seed, 14) * k * 0.5
		)
	end

	-- party members are swallowed by the dark once they are through the opening
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local padName = player:GetAttribute("CutscenePad")
		local character = player.Character
		if typeof(padName) ~= "string" or not character then
			continue
		end
		local pad = pads:FindFirstChild(padName)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pad or not root or typeof(pad:GetAttribute("CutsceneStart")) ~= "number" then
			continue
		end
		seen[character] = true
		local target = if DoorEntry.inside(pad, root.Position, 0.5) then 1 else 0
		local previous = swallowed[character] or 0
		local current = previous + math.clamp(target - previous, -dt * 3, dt * 1.8)
		swallowed[character] = current
		if current > 0 or previous > 0 then
			setCharacterFade(character, current)
		end
	end
	for character in swallowed do
		if not seen[character] then
			swallowed[character] = nil
			if character.Parent then
				setCharacterFade(character, 0)
			end
		end
	end
end)

------------------------------------------------------------------------------------------
-- Doors
------------------------------------------------------------------------------------------
local doors = {}
for _, pad in pads:GetChildren() do
	local leaf = pad:WaitForChild("Leaf")
	local gui = pad:WaitForChild("Sign"):WaitForChild("SurfaceGui")
	local title = gui:WaitForChild("Title")
	local status = gui:WaitForChild("Status")
	local mode = pad:GetAttribute("Mode")
	local fog = pad:WaitForChild("Fog"):WaitForChild("Fog")
	-- light pouring out of the black passage while the door stands open (client-only, off otherwise)
	local pour: SpotLight? = nil
	local void = pad:FindFirstChild("Void")
	if void and void:IsA("BasePart") then
		local leakColor = (pad:WaitForChild("UnderGlow"):WaitForChild("Leak") :: PointLight).Color
		local light = Instance.new("SpotLight")
		light.Name = "EntryPour"
		light.Face = Enum.NormalId.Back -- +Z, out through the doorway into the hall
		light.Angle = 75
		light.Range = 26
		light.Brightness = 0
		light.Shadows = true
		light.Color = leakColor:Lerp(Color3.new(1, 1, 1), 0.35)
		light.Enabled = false
		light.Parent = void
		pour = light
	end
	table.insert(doors, {
		pad = pad,
		leaf = leaf,
		hinge = leaf:GetAttribute("Hinge") or leaf:GetPivot(),
		leak = pad:WaitForChild("UnderGlow"):WaitForChild("Leak"),
		spill = pad:WaitForChild("FloorSpill"),
		fog = fog,
		fogSpeed = fog.Speed,
		pour = pour,
		inScene = false,
		gutteredFor = nil :: number?,
		slammedFor = nil :: number?,
		title = title,
		titleText = title.Text,
		titlePos = title.Position,
		titleLayers = layersOf(title),
		status = status,
		statusColor = status.TextColor3,
		strip = gui:FindFirstChild("StatusStrip"), -- optional black strip behind the count
		stripColor = gui:FindFirstChild("StatusStrip") and gui.StatusStrip.BackgroundColor3,
		hot = false,
		counter = pad:WaitForChild("Zone"):WaitForChild("Counter"),
		shownCount = -1,
		glitches = LABEL_GLITCHES[mode] or { "?" },
		nextGlitch = os.clock() + 3 + math.random() * 10,
		open = 0,
		lastAngle = 0,
		seed = math.random() * 1000,
	})
end

-- 0 when nobody is queued; ramps 0.25 -> 1 as the countdown runs out.
local function tensionOf(pad: Instance): number
	if (pad:GetAttribute("Count") or 0) == 0 then
		return 0
	end
	local timeLeft = pad:GetAttribute("TimeLeft") or Config.QueueCountdown
	return 0.25 + 0.75 * math.clamp(1 - timeLeft / Config.QueueCountdown, 0, 1)
end

local function updateDoor(d, t: number, dt: number): number
	local pad = d.pad
	local tension = tensionOf(pad)
	local launching = pad:GetAttribute("Launching") == true
	local timeLeft = pad:GetAttribute("TimeLeft") or 0
	local start = pad:GetAttribute("CutsceneStart")
	local scene = launching and typeof(start) == "number"
	local ct = if scene then workspace:GetServerTimeNow() - start else 0

	-- light under the door: a slow uneven breathing that swells with the countdown
	local breathe = math.noise(t * 1.3, d.seed) * 0.35
	if scene then
		-- the door-entry sequence: light floods out of the opening, gutters, dies with the slam
		local l = DoorEntry.light(ct, d.seed)
		local after = ct >= DoorEntry.SLAM
		d.leak.Brightness = if after then 0.35 else 0.6 + l * 3.4
		d.leak.Range = 10 + l * 9
		d.spill.Transparency = 0.85 - l * 0.6
		if d.pour then
			d.pour.Enabled = l > 0.01
			d.pour.Brightness = l * 6
		end
		-- fog rolls out over the threshold while it's open; the slam blows one last puff out
		local puff = after and ct < DoorEntry.SLAM + 0.5
		d.fog.Rate = if puff then 90 elseif after then 3 else 12 + l * 55
		local push = if puff then 3 else l * 2
		d.fog.Speed = NumberRange.new(0.5 + push, 1.2 + push * 1.4)
		d.inScene = true

		if ct >= DoorEntry.GUTTER and d.gutteredFor ~= start then
			d.gutteredFor = start
			if ct < DoorEntry.SLAM then
				Sfx.at(d.leak.Parent, "DoorGutter", { jitter = 0.08 })
			end
		end
		if ct >= DoorEntry.SLAM and d.slammedFor ~= start then
			d.slammedFor = start
			if ct < DoorEntry.SLAM + 1 then -- don't replay it for someone who just joined
				Sfx.at(d.leak.Parent, "DoorSlam", { jitter = 0.04 })
				-- cut AmbientSound's long opening squeak off with the slam
				local point = workspace.Terrain:FindFirstChild("DoorSound_" .. pad.Name)
				for _, sound in if point then point:GetChildren() else {} do
					if sound:IsA("Sound") and sound.Name == "DoorOpen" then
						sound:Stop()
					end
				end
				local cam = workspace.CurrentCamera
				local dist = (cam.CFrame.Position - d.hinge.Position).Magnitude
				if dist < 45 and not localPlayer:GetAttribute("CutscenePad") then
					onlookerJolt(0.02 * (1 - dist / 45) + 0.004, 0.45)
				end
			end
		end
	else
		if d.inScene then
			d.inScene = false
			d.fog.Speed = d.fogSpeed
			if d.pour then
				d.pour.Enabled = false
			end
		end
		d.leak.Brightness = launching and 2.2 or (0.5 + breathe + tension * 1.4)
		d.leak.Range = launching and 13 or (9 + tension * 4)
		d.spill.Transparency = launching and 0.45 or (0.86 - tension * 0.35)
		d.fog.Rate = launching and 25 or (2 + tension * 10)
	end

	-- the leaf: rattles harder as time runs out, swings open when the party leaves
	-- (all the way, on the DoorEntry timeline, when there's a cutscene; the old 32 degree peek otherwise)
	local angle
	if scene then
		d.open = 0
		angle = -DoorEntry.doorAngle(ct)
	else
		d.open += ((launching and 1 or 0) - d.open) * math.min(dt * 2.5, 1)
		local rattle = 0
		if tension > 0 then
			local strength = (timeLeft <= 5 and 0.05 or 0.012) * tension
			rattle = math.noise(t * 22, d.seed) * strength
		end
		angle = -d.open * math.rad(32) + rattle
	end
	if math.abs(angle - d.lastAngle) > 1e-4 then
		d.leaf:PivotTo(d.hinge * CFrame.Angles(0, angle, 0))
		d.lastAngle = angle
	end

	-- floating counter: fill one ring per player; it throbs while the door is about to open
	local count = pad:GetAttribute("Count") or 0
	if count ~= d.shownCount then
		d.shownCount = count
		for _, dot in d.counter.Dots:GetChildren() do
			if dot:IsA("Frame") then
				dot.BackgroundTransparency = dot.LayoutOrder <= count and 0 or 1
			end
		end
		d.counter.Count.Text = string.format("%d / %d", count, pad:GetAttribute("Capacity") or 0)
	end
	local throb = (tension > 0 and timeLeft <= 5 or launching) and (1 + math.sin(t * 12) * 0.06) or 1
	d.counter.Size = UDim2.fromOffset(160 * throb, 50 * throb)

	-- the count pulses red in the last five seconds
	if tension > 0 and timeLeft <= 5 then
		local beat = (math.sin(t * 10) + 1) / 2
		d.status.TextColor3 = d.statusColor:Lerp(HOT_RED, beat)
		if d.strip then
			d.strip.BackgroundColor3 = d.stripColor:Lerp(Color3.fromRGB(70, 8, 6), beat)
		end
		d.hot = true
	elseif d.hot then
		d.status.TextColor3 = d.statusColor
		if d.strip then
			d.strip.BackgroundColor3 = d.stripColor
		end
		d.hot = false
	end

	-- the label above glitches now and then, more often while someone is waiting
	if t >= d.nextGlitch then
		glitch(d.title, d.glitches, d.titleText, d.titlePos, d.titleLayers)
		d.nextGlitch = t + (5 + math.random() * 14) / (1 + tension * 3)
	end
	return tension
end

------------------------------------------------------------------------------------------
-- PICK A DOOR stencil
------------------------------------------------------------------------------------------
local stencil = queue:WaitForChild("Stencil")
local stencilLabel = stencil:WaitForChild("SurfaceGui"):WaitForChild("Label")
local stencilGlow = stencil:WaitForChild("Glow")
local stencilDrip = stencil:WaitForChild("Drip")
local stencilText, stencilPos = stencilLabel.Text, stencilLabel.Position
local stencilBaseColor = stencilLabel.TextColor3
local stencilLayers = layersOf(stencilLabel)
local nextStencilGlitch = os.clock() + 6

-- overspray halo layers breathe with the glow (updated at ~15 Hz: plenty for a slow pulse)
local halos = {}
for _, layer in stencilLayers do
	local base = layer.obj:GetAttribute("SignHalo")
	if typeof(base) == "number" and layer.obj:IsA("TextLabel") then
		table.insert(halos, { label = layer.obj, base = base })
	end
end
local nextHaloUpdate = 0

local function updateStencil(t: number, tension: number)
	local pulse = (math.sin(t * 0.9) + 1) / 2
	stencilGlow.Brightness = 0.15 + pulse * 0.3 + tension * 0.8
	stencilLabel.TextColor3 = stencilBaseColor:Lerp(HOT_RED, pulse * 0.35 + tension * 0.5)
	stencilDrip.Rate = 1.2 + tension * 6
	if t >= nextHaloUpdate and #halos > 0 then
		nextHaloUpdate = t + 1 / 15
		-- denser mist at the peak of each breath and as the countdown runs out
		local thicken = math.clamp(pulse * 0.5 + tension * 0.6, 0, 1)
		for _, h in halos do
			h.label.TextTransparency = h.base - (h.base - 0.6) * thicken * 0.5
		end
	end
	if t >= nextStencilGlitch then
		if math.random() < 0.3 then
			-- a quick flicker instead of different words
			stencilLabel.TextTransparency = 0.7
			task.delay(0.06, function()
				stencilLabel.TextTransparency = 0
			end)
		else
			glitch(stencilLabel, STENCIL_GLITCHES, stencilText, stencilPos, stencilLayers)
		end
		nextStencilGlitch = t + (8 + math.random() * 14) / (1 + tension * 2)
	end
end

------------------------------------------------------------------------------------------
-- Clock
------------------------------------------------------------------------------------------
local clock = queue:WaitForChild("Clock")
local center = clock:GetAttribute("Center")
local clockGlow = clock:WaitForChild("Face"):WaitForChild("Glow")
local hands = {
	hour = clock:WaitForChild("HandHour"),
	minute = clock:WaitForChild("HandMinute"),
	second = clock:WaitForChild("HandSecond"),
}
local hourAngle, minuteAngle = math.rad(20), math.rad(300) -- stopped at about ten to one
local STUCK = { 0, 1, 2, 1 } -- tick, tick, tick, back

local function placeHand(part: BasePart, angle: number)
	local depth = part:GetAttribute("Depth")
	local length = part:GetAttribute("Length")
	part.CFrame = CFrame.new(center + Vector3.new(0, 0, depth))
		* CFrame.Angles(0, 0, -angle)
		* CFrame.new(0, length * 0.4, 0)
end

local function updateClock(t: number, dt: number, tension: number)
	-- second hand: ticks forward, but every fourth second it slips back one
	local sec = math.floor(t)
	local shown = math.floor(sec / 4) * 2 + STUCK[sec % 4 + 1]
	local settle = math.clamp((t - sec) * 12, 0, 1) -- snap into each tick
	local secondAngle = (shown - 1 + settle) / 60 * math.pi * 2
	if tension > 0 then
		-- while a door is counting down, time runs backwards
		minuteAngle -= dt * (1 + tension * 7)
		hourAngle -= dt * (1 + tension * 7) / 12
		secondAngle = -t * (4 + tension * 10)
	end
	placeHand(hands.second, secondAngle)
	placeHand(hands.minute, minuteAngle)
	placeHand(hands.hour, hourAngle)
	clockGlow.Brightness = 0.3 + tension * 0.9
end

------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local maxTension = 0
	for _, d in doors do
		maxTension = math.max(maxTension, updateDoor(d, t, dt))
	end
	updateStencil(t, maxTension)
	updateClock(t, dt, maxTension)
end)
