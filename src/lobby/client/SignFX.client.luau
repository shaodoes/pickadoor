--[[
	Generic sign VFX (client-only). Animates every Model tagged "SignFX" (built by
	builders/Signage.luau and the room builders; see the SignFX contract there). The STORE sign is not
	tagged: it keeps its own StoreSignFX.

	  pulse     Glow rims, Halo billboards, Edge trim and every Light breathe (Pulse s per breath,
	            PulseAmt deep). With Tension (written client-side by DoorFX) it turns into a quickening
	            lub-dub heartbeat and everything burns brighter.
	  sweep     every Sweep s a soft sheen (two camera-facing beams) slides across the sign and lifts the
	            letter faces toward white; "holo" signs get a horizontal scan band rising bottom to top
	            and a faint per-letter shimmer instead.
	  flicker   now and then one letter stutters (Flicker = mean seconds; Tension shortens it). A new
	            Blink stamp drops every letter out for a beat and leaves one dark a little longer.
	  ghost     ObjectValue "Ghost" -> a TextLabel DoorFX retexts for glitches: while its Text differs
	            from its GhostBase attribute the 3D letters cut out (one or two jump off-register) and
	            the label shows in their place.
	  haze      HazeVolume emits "haze" | "dust" | "motes" | "embers" (HazeRate overrides the rate).
	  drips     every DripRun part drips a paint drop now and then from its bottom end (more with Tension).
	  bob/sway  floating signs bob and drift (Bob studs); hanging signs swing about SwayPivot (Sway deg).
	  chase     LedSeg rows chase (Row 1 rightward, others leftward); Bulb marquees run every third bulb
	            with the odd bulb popping dark; Chevrons light in turn toward the name, then all.
	  edge      Edge trim breathes; on "plaque" signs it heats toward red with Tension and blinks at the end.
	  eyes      rarely, Eye balls fade in, blink once and are gone.

	Only near signs (Cull, default 90 studs, checked every 0.25 s) do per-frame work; a culled sign is
	put back exactly as built. Effects the client creates live in workspace.SignFX.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "SignFX"
local TEX = {
	soft = "rbxassetid://111717994998860", -- bell-shaped across X, constant along Y (as AtmosFX)
	mote = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
}

local CULL = 90
local WHITE = Color3.fromRGB(250, 246, 240)
local BLACK = Color3.new(0, 0, 0)
local HOT = Color3.fromRGB(230, 50, 40)
local WARM = Color3.fromRGB(255, 184, 122)
local FLICKER = { 0.05, 0.08, 0.04, 0.2, 0.06 } -- alternating out / lit durations
local ATTR_EVERY = 1 / 15
local rng = Random.new()

local gameSettings = UserSettings():GetService("UserGameSettings")
local function quality(): number
	local level = gameSettings.SavedQualityLevel
	if level == Enum.SavedQualitySetting.Automatic then
		return 0.75
	end
	return math.clamp(level.Value / 10, 0.1, 1)
end

local function ns(points: { number }): NumberSequence
	local keys = {}
	for i = 1, #points, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keys)
end

local fxFolder = Instance.new("Folder")
fxFolder.Name = "SignFX"
fxFolder.Parent = workspace

local signs = {} -- [Model] = state

local function hiddenPart(name: string, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end

local function num(model: Instance, name: string, default: number): number
	local v = model:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

------------------------------------------------------------------------------------------
-- Haze presets
------------------------------------------------------------------------------------------
local function hazeProps(kind: string, accent: Color3): ({ [string]: any }?, number)
	if kind == "haze" then
		return {
			Texture = TEX.smoke,
			Lifetime = NumberRange.new(4, 6),
			Speed = NumberRange.new(0.2, 0.5),
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(0, 0.1, 0),
			Drag = 0.4,
			Size = ns({ 0, 1, 1, 3 }),
			Transparency = ns({ 0, 1, 0.3, 0.94, 0.7, 0.96, 1, 1 }),
			RotSpeed = NumberRange.new(-12, 12),
			Rotation = NumberRange.new(0, 360),
			Color = ColorSequence.new(accent),
			LightEmission = 0.5,
		},
			3
	elseif kind == "dust" then
		return {
			Texture = TEX.mote,
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(0.05, 0.2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -0.02, 0),
			Drag = 1,
			Size = ns({ 0, 0.04, 0.5, 0.06, 1, 0.03 }),
			Transparency = ns({ 0, 1, 0.25, 0.35, 0.75, 0.4, 1, 1 }),
			Color = ColorSequence.new(Color3.fromRGB(255, 226, 180)),
			LightEmission = 0.4,
			LightInfluence = 1,
		},
			6
	elseif kind == "motes" then
		return {
			Texture = TEX.mote,
			Lifetime = NumberRange.new(2.5, 4.5),
			Speed = NumberRange.new(0.3, 0.8),
			SpreadAngle = Vector2.new(20, 20),
			Drag = 0.5,
			Size = ns({ 0, 0.05, 0.5, 0.08, 1, 0.02 }),
			Transparency = ns({ 0, 1, 0.2, 0.3, 0.8, 0.4, 1, 1 }),
			Color = ColorSequence.new(accent:Lerp(Color3.new(1, 1, 1), 0.3)),
			LightEmission = 1,
			Brightness = 2,
		},
			5
	elseif kind == "embers" then
		return {
			Texture = TEX.spark,
			Lifetime = NumberRange.new(1.5, 3),
			Speed = NumberRange.new(0.5, 1.2),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, 0.3, 0),
			Drag = 0.6,
			Size = ns({ 0, 0.06, 0.2, 0.1, 0.35, 0.05, 0.5, 0.09, 0.7, 0.04, 1, 0 }),
			Transparency = ns({ 0, 0.2, 0.7, 0.4, 1, 1 }),
			Color = ColorSequence.new(Color3.fromRGB(255, 170, 70), Color3.fromRGB(220, 70, 30)),
			LightEmission = 1,
			Brightness = 2,
		},
			4
	end
	return nil, 0
end

------------------------------------------------------------------------------------------
-- Setup / teardown
------------------------------------------------------------------------------------------
local function reset(s)
	for _, letter in s.letters do
		letter.out = false
		for _, f in letter.faces do
			f.part.Color = f.color
			f.part.Transparency = f.transparency
		end
		for _, g in letter.glows do
			g.part.Transparency = g.transparency
		end
		for _, h in letter.halos do
			h.gui.Brightness = h.brightness
		end
	end
	if s.ghostOn then
		s.ghostOn = false
		for _, p in s.letterParts do
			p.LocalTransparencyModifier = 0
		end
		for _, sh in s.shifted do
			if sh.model.Parent then
				sh.model:PivotTo(sh.model:GetPivot() * sh.undo)
			end
		end
		table.clear(s.shifted)
	end
	if s.ghost and s.ghost.Parent then
		s.ghost.TextTransparency = 1
		s.ghost.TextStrokeTransparency = 1
	end
	for _, l in s.leds do
		l.part.Color = l.color
	end
	for _, b in s.bulbs do
		b.part.Color = b.color
	end
	for _, c in s.chevrons do
		c.part.Color = c.color
	end
	for _, e in s.edges do
		e.part.Color = e.color
	end
	for _, eye in s.eyes do
		eye.part.Transparency = 1
		if eye.gui then
			eye.gui.Enabled = false
		end
	end
	s.eyesStart = -1
	s.lastEyes = -1
	for _, h in s.halos do
		h.gui.Brightness = h.brightness
	end
	for _, l in s.lights do
		l.light.Brightness = l.brightness
	end
	s.flicker.letter, s.flicker.step = nil, 0
	s.blinkUntil, s.blinkLetter = 0, nil
	for _, b in s.beams do
		b.Enabled = false
	end
	for _, e in s.emitters do
		e.emitter.Enabled = false
	end
	if s.moves and s.model.Parent then
		s.model:PivotTo(s.basePivot)
	end
end

local function teardown(model: Model)
	local s = signs[model]
	if not s then
		return
	end
	signs[model] = nil
	pcall(reset, s)
	for _, inst in s.made do
		inst:Destroy()
	end
end

local function setup(model: Model)
	teardown(model)
	local view = model.WorldPivot
	local W = num(model, "Width", model:GetExtentsSize().X)
	local H = num(model, "Height", model:GetExtentsSize().Y)
	local style = model:GetAttribute("SignStyle")
	local s = {
		model = model,
		view = view,
		basePivot = view,
		W = W,
		H = H,
		style = if typeof(style) == "string" then style else "",
		holo = style == "holo",
		plaque = style == "plaque",
		cull = num(model, "Cull", CULL),
		pulsePeriod = num(model, "Pulse", 0),
		pulseAmt = num(model, "PulseAmt", 0.5),
		sweepEvery = num(model, "Sweep", 0),
		flickerMean = num(model, "Flicker", 0),
		chase = num(model, "Chase", 1),
		bob = num(model, "Bob", 0),
		sway = num(model, "Sway", 0),
		phase = rng:NextNumber(0, 6.28),
		letters = {},
		letterParts = {},
		shifted = {},
		leds = {},
		bulbs = {},
		chevrons = {},
		edges = {},
		eyes = {},
		halos = {},
		lights = {},
		drips = {},
		emitters = {},
		beams = {},
		made = {},
		active = false,
		cullTimer = rng:NextNumber(0, 0.25),
		attrTimer = 0,
		tension = 0,
		blinkStamp = model:GetAttribute("Blink"),
		blinkUntil = 0,
		blinkLetter = nil,
		pulsePhase = 0,
		flicker = { letter = nil, step = 0, long = false, next = os.clock() + rng:NextNumber(4, 12) },
		eyesAt = os.clock() + rng:NextNumber(30, 70),
		eyesStart = -1,
		lastEyes = -1,
		popBulb = nil,
		popUntil = 0,
		popAt = os.clock() + rng:NextNumber(6, 15),
		ghost = nil,
		ghostBase = "",
		ghostOn = false,
		moves = false,
	}
	s.moves = s.bob > 0 or s.sway > 0
	local swayPivot = model:GetAttribute("SwayPivot")
	s.swayPivot = if typeof(swayPivot) == "CFrame" then swayPivot else view
	if s.flickerMean > 0 then
		s.flicker.next = os.clock() + rng:NextNumber(0.3, 1) * s.flickerMean
	end

	-- letters
	local letterOf = {} -- [Model] = letter
	for _, child in model:GetChildren() do
		local index = child:GetAttribute("Letter")
		if child:IsA("Model") and typeof(index) == "number" then
			local letter = {
				model = child,
				index = index,
				u = num(child, "U", 0),
				v = num(child, "V", 0),
				faces = {},
				glows = {},
				halos = {},
				out = false,
			}
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(s.letterParts, d)
					if d.Name == "Face" then
						table.insert(letter.faces, { part = d, color = d.Color, transparency = d.Transparency })
					elseif d.Name == "Glow" then
						table.insert(letter.glows, { part = d, transparency = d.Transparency })
					end
				elseif d:IsA("BillboardGui") and d.Name == "Halo" then
					table.insert(letter.halos, { gui = d, brightness = d.Brightness })
				end
			end
			letterOf[child] = letter
			table.insert(s.letters, letter)
		end
	end

	local accent = model:GetAttribute("Accent")
	local firstGlow: Color3? = nil
	for _, d in model:GetDescendants() do
		local name = d.Name
		if d:IsA("BasePart") then
			if name == "LedSeg" then
				table.insert(s.leds, {
					part = d,
					color = d.Color,
					dim = d.Color:Lerp(BLACK, 0.55),
					hot = d.Color:Lerp(Color3.new(1, 1, 1), 0.35),
					row = num(d, "Row", 1),
					index = num(d, "Index", 1),
					u = num(d, "U", 0),
				})
			elseif name == "Bulb" then
				table.insert(s.bulbs, { part = d, color = d.Color, index = num(d, "Index", #s.bulbs + 1) })
			elseif name == "Chevron" then
				table.insert(s.chevrons, { part = d, color = d.Color, step = num(d, "Step", 1) })
			elseif name == "Edge" then
				table.insert(s.edges, { part = d, color = d.Color })
				firstGlow = firstGlow or d.Color
			elseif name == "Eye" then
				local gui = d:FindFirstChild("EyeHalo")
				table.insert(s.eyes, { part = d, gui = if gui and gui:IsA("BillboardGui") then gui else nil })
			elseif name == "DripRun" then
				table.insert(s.drips, d)
			elseif name == "Glow" and not firstGlow then
				firstGlow = d.Color
			end
		elseif d:IsA("Light") then
			table.insert(s.lights, { light = d, brightness = d.Brightness })
		elseif d:IsA("BillboardGui") and name == "Halo" then
			-- halos inside a letter belong to it (they dim with it); the rest breathe with the sign
			local owner = d:FindFirstAncestorWhichIsA("Model")
			if not (owner and letterOf[owner]) then
				table.insert(s.halos, { gui = d, brightness = d.Brightness })
			end
		end
	end
	s.accent = if typeof(accent) == "Color3" then accent else (firstGlow or WARM)

	-- ghost label (glitch words shown in place of the 3D letters)
	local ghostRef = model:FindFirstChild("Ghost")
	if ghostRef and ghostRef:IsA("ObjectValue") and ghostRef.Value and ghostRef.Value:IsA("TextLabel") then
		local label = ghostRef.Value :: TextLabel
		local base = label:GetAttribute("GhostBase")
		s.ghost = label
		s.ghostBase = if typeof(base) == "string" then base else label.Text
	end

	-- the sheen: two camera-facing additive beams whose ends slide across the sign
	if s.sweepEvery > 0 then
		local holder = hiddenPart("Sheen", Vector3.new(0.2, 0.2, 0.2), view)
		table.insert(s.made, holder)
		s.holder = holder
		s.sheenZ = num(model, "Depth", 0.8) + 0.12
		s.sweepTime = math.clamp(W / 11, 1.1, 1.9)
		s.a0 = Instance.new("Attachment")
		s.a0.Parent = holder
		s.a1 = Instance.new("Attachment")
		s.a1.Parent = holder
		local sweepColor = model:GetAttribute("SweepColor")
		local color = if typeof(sweepColor) == "Color3" then sweepColor else s.accent:Lerp(Color3.new(1, 1, 1), 0.6)
		local k = if s.holo then math.clamp(H / 6, 0.12, 0.5) else math.clamp(H / 3.7, 0.3, 1.2)
		for _, spec in { { 1.4 * k, 0.82 }, { 0.32 * k, 0.6 } } do
			local b = Instance.new("Beam")
			b.Attachment0 = s.a0
			b.Attachment1 = s.a1
			b.Width0, b.Width1 = spec[1], spec[1]
			b.Texture = TEX.soft
			b.TextureMode = Enum.TextureMode.Stretch
			b.Color = ColorSequence.new(color)
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 8
			b.Transparency = ns({ 0, 1, 0.2, spec[2], 0.8, spec[2], 1, 1 })
			b.Enabled = false
			b.Parent = holder
			table.insert(s.beams, b)
		end
	end

	-- haze from the volume
	local hazeKind = model:GetAttribute("Haze")
	local hazeSrc = model:FindFirstChild("HazeVolume")
	if typeof(hazeKind) == "string" and hazeSrc and hazeSrc:IsA("BasePart") then
		local props, rate = hazeProps(hazeKind, s.accent)
		if props then
			local volume = hiddenPart("Haze", hazeSrc.Size, hazeSrc.CFrame)
			table.insert(s.made, volume)
			local e = Instance.new("ParticleEmitter")
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.EmissionDirection = Enum.NormalId.Top
			e.LightInfluence = 0
			for key, value in props do
				(e :: any)[key] = value
			end
			e.Enabled = false
			e.Parent = volume
			table.insert(s.emitters, { emitter = e, rate = num(model, "HazeRate", rate), drip = false })
		end
	end

	-- paint drops falling from the bottom of every run
	for _, run in s.drips do
		local bottom = run.Position - run.CFrame.UpVector * (run.Size.Y / 2)
		local src = hiddenPart("DripSource", Vector3.new(0.1, 0.05, 0.1), CFrame.new(bottom))
		table.insert(s.made, src)
		local e = Instance.new("ParticleEmitter")
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(0, 0.2)
		e.Acceleration = Vector3.new(0, -14, 0)
		e.Size = ns({ 0, 0.05, 1, 0.04 })
		e.Squash = NumberSequence.new(-1.2) -- stretched into drops
		e.Color = ColorSequence.new(run.Color)
		e.LightEmission = 0
		e.LightInfluence = 1
		e.Transparency = ns({ 0, 0, 1, 0.3 })
		e.Enabled = false
		e.Parent = src
		table.insert(s.emitters, { emitter = e, rate = rng:NextNumber(0.15, 0.3), drip = true })
	end

	signs[model] = s
end

------------------------------------------------------------------------------------------
-- Per frame
------------------------------------------------------------------------------------------
local function applyRates(s)
	local q = 0.3 + 0.7 * quality()
	for _, e in s.emitters do
		local r = e.rate
		if e.drip then
			r = e.rate + s.tension * 1.3
		end
		e.emitter.Rate = r * q
	end
end

local function setActive(s, on: boolean)
	s.active = on
	if not on then
		reset(s)
		return
	end
	applyRates(s)
	for _, e in s.emitters do
		e.emitter.Enabled = true
	end
end

local function stepFlicker(s, t: number)
	local f = s.flicker
	if s.flickerMean <= 0 or t < f.next or #s.letters == 0 then
		return
	end
	if not f.letter then
		f.letter = s.letters[rng:NextInteger(1, #s.letters)]
		f.step = 0
		f.long = rng:NextNumber() < 0.3 -- sometimes it drops out for a beat before it catches
	end
	f.step += 1
	if f.step > #FLICKER then
		f.letter.out = false
		f.letter, f.step = nil, 0
		f.next = t + rng:NextNumber(0.5, 1.5) * s.flickerMean / (1 + s.tension * 3)
		return
	end
	f.letter.out = f.step % 2 == 1
	local hold = FLICKER[f.step] * rng:NextNumber(0.7, 1.4)
	if f.long and f.step == 3 then
		hold = rng:NextNumber(0.45, 0.8)
	end
	f.next = t + hold
end

local function eyesAlpha(s, t: number): number
	-- 0 = shut, 1 = open: fade in, hold, a quick blink, hold, fade out
	if s.eyesStart < 0 then
		if t >= s.eyesAt then
			s.eyesStart = t
		else
			return 0
		end
	end
	local k = t - s.eyesStart
	if k > 2.6 then
		s.eyesStart = -1
		s.eyesAt = t + rng:NextNumber(30, 70) / (1 + s.tension * 2)
		return 0
	end
	if k < 0.35 then
		return k / 0.35
	elseif k > 1.25 and k < 1.4 then
		return 0
	elseif k > 2.2 then
		return (2.6 - k) / 0.4
	end
	return 1
end

-- lub-dub: two thumps early in each beat, then rest
local function heartbeat(phase: number): number
	local a = (phase - 0.1) / 0.05
	local b = (phase - 0.3) / 0.06
	return math.min(1, math.exp(-a * a) + 0.7 * math.exp(-b * b))
end

local function updateGhost(s)
	local label = s.ghost
	if not label or not label.Parent then
		return
	end
	local on = label.Text ~= s.ghostBase
	if on == s.ghostOn then
		return
	end
	s.ghostOn = on
	if on then
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.6
		for _, p in s.letterParts do
			p.LocalTransparencyModifier = 1
		end
		-- one or two letters jump off-register (seen as they come back)
		for _ = 1, math.min(#s.letters, rng:NextInteger(1, 2)) do
			local letter = s.letters[rng:NextInteger(1, #s.letters)]
			local offset = CFrame.new(rng:NextNumber(-0.07, 0.07), rng:NextNumber(-0.05, 0.05), 0)
			letter.model:PivotTo(letter.model:GetPivot() * offset)
			table.insert(s.shifted, { model = letter.model, undo = offset:Inverse() })
		end
	else
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
		for _, p in s.letterParts do
			p.LocalTransparencyModifier = 0
		end
		-- the shifted letters settle back after a beat
		local shifted = table.clone(s.shifted)
		table.clear(s.shifted)
		task.delay(0.12, function()
			for _, sh in shifted do
				if sh.model.Parent then
					sh.model:PivotTo(sh.model:GetPivot() * sh.undo)
				end
			end
		end)
	end
end

local function stepSign(s, t: number, dt: number, camPos: Vector3?)
	s.cullTimer -= dt
	if s.cullTimer <= 0 and camPos then
		s.cullTimer = 0.25
		local near = (camPos - s.basePivot.Position).Magnitude < s.cull
		if near ~= s.active then
			setActive(s, near)
		end
	end
	if not s.active then
		return
	end
	local model = s.model

	-- attributes DoorFX writes client-side (tension, blink)
	s.attrTimer -= dt
	if s.attrTimer <= 0 then
		s.attrTimer = ATTR_EVERY
		local tension = math.clamp(num(model, "Tension", 0), 0, 1)
		if math.abs(tension - s.tension) > 0.02 then
			s.tension = tension
			applyRates(s)
		end
		local blink = model:GetAttribute("Blink")
		if blink ~= s.blinkStamp then
			s.blinkStamp = blink
			s.blinkUntil = t + 0.08
			if #s.letters > 0 then
				s.blinkLetter = s.letters[rng:NextInteger(1, #s.letters)]
				s.blinkLetterUntil = t + 0.48
			end
		end
	end
	local tension = s.tension

	-- breath / heartbeat (k in -0.5..0.5 scaled by PulseAmt)
	local period = s.pulsePeriod
	if period <= 0 and tension > 0 then
		period = 1.6
	end
	local p = 0.5
	if period > 0 then
		local beat = period / (1 + 2 * tension)
		s.pulsePhase = (s.pulsePhase + dt / beat) % 1
		if tension > 0 then
			p = heartbeat(s.pulsePhase)
		else
			p = 0.5 + 0.5 * math.sin(s.pulsePhase * 2 * math.pi)
		end
	end
	local k = (p - 0.5) * s.pulseAmt * 2

	-- bob / sway
	if s.moves then
		local pivot = s.basePivot
		if s.bob > 0 then
			pivot = pivot
				* CFrame.new(0, s.bob * math.sin(t * 1.1 + s.phase), 0)
				* CFrame.Angles(0, math.rad(1.5) * math.sin(t * 0.37 + s.phase), 0)
		end
		if s.sway > 0 then
			local a = math.rad(s.sway)
			local rot = CFrame.Angles(a * math.sin(t * 0.7 + s.phase), 0, a * 0.35 * math.sin(t * 0.53 + 1 + s.phase))
			pivot = s.swayPivot * rot * s.swayPivot:Inverse() * pivot
		end
		model:PivotTo(pivot)
		if s.holder then
			s.holder.CFrame = pivot
		end
	end

	-- sweep
	local sweepU, sweepV = nil, nil
	if s.sweepEvery > 0 then
		local sp = ((t + s.phase) % s.sweepEvery) / s.sweepTime
		if sp <= 1 then
			local eased = sp * sp * (3 - 2 * sp)
			local W, H, z = s.W, s.H, s.sheenZ
			if s.holo then
				sweepV = -H / 2 - 0.3 + (H + 0.6) * eased
				s.a0.CFrame = CFrame.new(-W / 2 - 0.4, sweepV, z)
				s.a1.CFrame = CFrame.new(W / 2 + 0.4, sweepV, z)
			else
				sweepU = -W / 2 - 1.5 + (W + 3) * eased
				local slant = math.min(0.9, H * 0.25)
				s.a0.CFrame = CFrame.new(sweepU + slant, H / 2 + 0.2, z)
				s.a1.CFrame = CFrame.new(sweepU - slant, -H / 2 - 0.2, z)
			end
			if not s.beams[1].Enabled then
				for _, b in s.beams do
					b.Enabled = true
				end
			end
		elseif s.beams[1].Enabled then
			for _, b in s.beams do
				b.Enabled = false
			end
		end
	end

	stepFlicker(s, t)
	updateGhost(s)

	-- letters
	local allOut = t < s.blinkUntil
	local blinkLetter = if s.blinkLetter and t < (s.blinkLetterUntil or 0) then s.blinkLetter else nil
	local anyOut = allOut
	local glowLift = 0.25 * tension
	local reach = math.max(1.2, s.H * 0.5)
	for i, letter in s.letters do
		local boost = 0
		if sweepU then
			boost = math.max(0, 1 - math.abs(letter.u - sweepU) / reach)
		elseif sweepV then
			boost = math.max(0, 1 - math.abs(letter.v - sweepV) / math.max(0.3, s.H * 0.4))
		end
		if allOut or letter.out or letter == blinkLetter then
			anyOut = true
			for _, f in letter.faces do
				f.part.Color = f.color:Lerp(BLACK, 0.6)
			end
			for _, g in letter.glows do
				g.part.Transparency = 0.92
			end
			for _, h in letter.halos do
				h.gui.Brightness = h.brightness * 0.2
			end
		else
			for _, f in letter.faces do
				f.part.Color = f.color:Lerp(WHITE, math.clamp(boost * 0.6 + math.max(0, k) * 0.1, 0, 1))
				if s.holo then
					f.part.Transparency = math.clamp(f.transparency + 0.15 * math.noise(t * 3, i * 1.7, s.phase), 0, 1)
				end
			end
			for _, g in letter.glows do
				g.part.Transparency = math.clamp(g.transparency - k * 0.3 - glowLift - 0.2 * boost, 0, 1)
			end
			for _, h in letter.halos do
				h.gui.Brightness = h.brightness * (1 + k * 0.6 + tension * 0.5 + 0.6 * boost)
			end
		end
	end

	-- LED chase
	if #s.leds > 0 then
		local speed = s.chase
		for _, l in s.leds do
			local dir = if l.row == 1 then -1 else 1
			local w = 0.5 + 0.5 * math.sin(t * 2.4 * speed + dir * l.index * 0.55)
			local boost = if sweepU then math.max(0, 1 - math.abs(l.u - sweepU) / 1.5) else 0
			l.part.Color = l.dim:Lerp(l.hot, math.min(w * w * 0.85 + 0.15 + boost * 0.5, 1))
		end
	end

	-- marquee bulbs: every third lit, marching; now and then one pops dark for a second
	if #s.bulbs > 0 then
		if t >= s.popAt then
			s.popBulb = s.bulbs[rng:NextInteger(1, #s.bulbs)]
			s.popUntil = t + rng:NextNumber(0.6, 1.2)
			s.popAt = t + rng:NextNumber(6, 15)
		end
		local step = math.floor(t * 4 * s.chase)
		for _, b in s.bulbs do
			local lit = (b.index - step) % 3 == 0
			if b == s.popBulb and t < s.popUntil then
				b.part.Color = b.color:Lerp(BLACK, 0.85)
			elseif lit then
				b.part.Color = b.color:Lerp(WHITE, 0.15 + math.max(0, k) * 0.2)
			else
				b.part.Color = b.color:Lerp(BLACK, 0.6)
			end
		end
	end

	-- chevrons: outer, middle, inner, then all lit for a beat
	if #s.chevrons > 0 then
		local phase = math.floor(t * 2.2) % 5
		for _, c in s.chevrons do
			local lit = phase >= 3 or (3 - phase) == c.step
			c.part.Color = if lit then c.color else c.color:Lerp(BLACK, 0.75)
		end
	end

	-- edge trim
	if #s.edges > 0 then
		local blinkOff = s.plaque and tension > 0.8 and math.sin(t * 2 * math.pi * 5) < 0
		for _, e in s.edges do
			local c = e.color:Lerp(WHITE, math.clamp(math.max(0, k) * 0.35, 0, 1))
			if s.plaque and tension > 0 then
				c = c:Lerp(HOT, tension)
				if blinkOff then
					c = c:Lerp(BLACK, 0.6)
				end
			end
			e.part.Color = c
		end
	end

	-- eyes
	if #s.eyes > 0 then
		local a = eyesAlpha(s, t)
		if a ~= s.lastEyes then
			s.lastEyes = a
			for _, eye in s.eyes do
				eye.part.Transparency = 1 - a * 0.9
				if eye.gui then
					eye.gui.Enabled = a > 0.05
				end
			end
		end
	end

	-- halos and lights breathe; a letter dropping out dims the sign's light a touch
	for _, h in s.halos do
		h.gui.Brightness = h.brightness * (1 + k * 0.5 + tension * 0.5)
	end
	local lightK = (1 + k * 0.6 + tension * 0.8) * (if anyOut then 0.8 else 1)
	for _, l in s.lights do
		l.light.Brightness = l.brightness * lightK
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local t = os.clock()
	for model, s in signs do
		if not model.Parent then
			teardown(model)
		else
			stepSign(s, t, dt, camPos)
		end
	end
end

------------------------------------------------------------------------------------------
-- Finding signs
------------------------------------------------------------------------------------------
local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	-- let the rest of the model replicate in before reading it
	task.defer(function()
		if inst.Parent and inst:HasTag(TAG) then
			setup(inst)
		end
	end)
end

for _, inst in CollectionService:GetTagged(TAG) do
	consider(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(consider)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	if inst:IsA("Model") then
		teardown(inst)
	end
end)

gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	for _, s in signs do
		if s.active then
			applyRates(s)
		end
	end
end)

RunService.RenderStepped:Connect(step)
