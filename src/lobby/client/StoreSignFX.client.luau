--[[
	The STORE sign's VFX (client-only). Finds Lobby...Storefront.StoreSign (built by
	builders/Rooms/Shop.luau, buildStoreSign) and animates it from the part names and attributes set
	there; rebuilt or re-streamed signs are picked up again.

	  pulse     the violet rim behind every letter, the halos and the sign's lights breathe (~3.8 s)
	  sweep     every ~7.5 s a slanted sheen slides across the panel and each letter's neon face
	            brightens toward white as it passes
	  flicker   now and then one letter stutters (and sometimes drops out for a beat with its rim)
	  LEDs      the recessed strips run a slow chase, top row rightward, bottom row leftward
	  chevrons  the three chevrons each side light in turn toward the name, then all together
	  haze      faint violet haze and a few motes drift up from under the sign
	  eyes      rarely, two pale eyes open in the O, blink once, and are gone

	Only plain property writes per frame, no allocations; beyond CULL studs nothing runs and the sign
	is put back to its built state. Effects the client creates live in workspace.StoreSignFX.
]]
local RunService = game:GetService("RunService")

local TEX = {
	soft = "rbxassetid://111717994998860", -- bell-shaped across X, constant along Y (as AtmosFX)
	mote = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local CULL = 90
local PULSE = 3.8 -- seconds per breath
local SWEEP_EVERY, SWEEP_TIME = 7.5, 1.7
local WHITE = Color3.fromRGB(246, 242, 255)
local LED_DIM = Color3.fromRGB(70, 34, 130)
local LED_HOT = Color3.fromRGB(180, 130, 255)
local FLICKER = { 0.05, 0.08, 0.04, 0.2, 0.06 } -- alternating out / lit durations
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
fxFolder.Name = "StoreSignFX"
fxFolder.Parent = workspace

local state = nil -- the sign currently animated

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

------------------------------------------------------------------------------------------
-- Setup / teardown
------------------------------------------------------------------------------------------
local function teardown()
	local s = state
	if not s then
		return
	end
	state = nil
	s.reset(s)
	for _, inst in s.made do
		inst:Destroy()
	end
end

local function setup(sign: Model)
	teardown()
	local view = sign.WorldPivot
	local W = sign:GetAttribute("Width") or 19
	local H = sign:GetAttribute("Height") or 3.7
	local D = sign:GetAttribute("Depth") or 0.5
	local s = {
		sign = sign,
		view = view,
		W = W,
		H = H,
		letters = {},
		leds = {},
		chevrons = {},
		eyes = {},
		halos = {},
		lights = {},
		made = {},
		active = false,
		flicker = { letter = nil, step = 0, next = os.clock() + rng:NextNumber(6, 16) },
		eyesAt = os.clock() + rng:NextNumber(20, 45),
		eyesStart = -1,
	}

	for _, child in sign:GetChildren() do
		local index = child:GetAttribute("Letter")
		if child:IsA("Model") and index then
			local letter = { u = child:GetAttribute("U") or 0, faces = {}, glows = {}, halo = nil, out = false }
			for _, d in child:GetDescendants() do
				if d.Name == "Face" and d:IsA("BasePart") then
					table.insert(letter.faces, { part = d, color = d.Color })
				elseif d.Name == "Glow" and d:IsA("BasePart") then
					table.insert(letter.glows, { part = d, transparency = d.Transparency })
				elseif d.Name == "Halo" and d:IsA("BillboardGui") then
					letter.halo = { gui = d, brightness = d.Brightness }
				end
			end
			s.letters[index] = letter
		end
	end
	for _, d in sign:GetDescendants() do
		if d.Name == "LedSeg" and d:IsA("BasePart") then
			table.insert(s.leds, {
				part = d,
				color = d.Color,
				row = d:GetAttribute("Row") or 1,
				index = d:GetAttribute("Index") or 1,
				u = d:GetAttribute("U") or 0,
			})
		elseif d.Name == "Chevron" and d:IsA("BasePart") then
			table.insert(s.chevrons, { part = d, color = d.Color, step = d:GetAttribute("Step") or 1 })
		elseif d.Name == "Eye" and d:IsA("BasePart") then
			table.insert(s.eyes, { part = d, gui = d:FindFirstChild("EyeHalo") })
		elseif d:IsA("Light") then
			table.insert(s.lights, { light = d, brightness = d.Brightness })
		elseif d.Name == "Halo" and d:IsA("BillboardGui") and not (d.Parent and d.Parent.Name == "HaloAnchor") then
			table.insert(s.halos, { gui = d, brightness = d.Brightness })
		end
	end

	-- the sheen: two camera-facing additive beams (a wide soft one and a bright core) whose ends
	-- slide across the panel, slanted, in front of the letters
	local holder = hiddenPart("Sheen", Vector3.new(0.2, 0.2, 0.2), view)
	table.insert(s.made, holder)
	local z = D / 2 + 0.42 + 0.12
	s.sheenZ = z
	s.a0 = Instance.new("Attachment")
	s.a0.Parent = holder
	s.a1 = Instance.new("Attachment")
	s.a1.Parent = holder
	s.beams = {}
	for _, spec in { { 1.4, 0.82 }, { 0.32, 0.6 } } do
		local b = Instance.new("Beam")
		b.Attachment0 = s.a0
		b.Attachment1 = s.a1
		b.Width0, b.Width1 = spec[1], spec[1]
		b.Texture = TEX.soft
		b.TextureMode = Enum.TextureMode.Stretch
		b.Color = ColorSequence.new(Color3.fromRGB(214, 190, 255))
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Segments = 8
		-- fade in and out along its length so it never shows hard ends at the panel's edges
		b.Transparency = ns({ 0, 1, 0.2, spec[2], 0.8, spec[2], 1, 1 })
		b.Enabled = false
		b.Parent = holder
		table.insert(s.beams, b)
	end

	-- haze and motes rising from under the sign
	local hazeSrc = sign:FindFirstChild("HazeVolume")
	local hazeCf = hazeSrc and hazeSrc.CFrame or view * CFrame.new(0, -H / 2 - 1, D / 2 + 0.7)
	local hazeSize = hazeSrc and hazeSrc.Size or Vector3.new(W - 2, 0.6, 1.2)
	local volume = hiddenPart("Haze", hazeSize, hazeCf)
	table.insert(s.made, volume)
	local function emitter(props: { [string]: any }): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Top
		e.LightInfluence = 0
		for key, value in props do
			e[key] = value
		end
		e.Enabled = false
		e.Parent = volume
		return e
	end
	s.emitters = {
		{
			emitter({
				Texture = TEX.smoke,
				Rate = 3,
				Lifetime = NumberRange.new(4, 6),
				Speed = NumberRange.new(0.25, 0.6),
				SpreadAngle = Vector2.new(12, 12),
				Acceleration = Vector3.new(0, 0.12, 0),
				Drag = 0.4,
				Size = ns({ 0, 1.2, 1, 3.2 }),
				Transparency = ns({ 0, 1, 0.3, 0.93, 0.7, 0.95, 1, 1 }),
				RotSpeed = NumberRange.new(-12, 12),
				Rotation = NumberRange.new(0, 360),
				Color = ColorSequence.new(Color3.fromRGB(150, 90, 255)),
				LightEmission = 0.6,
			}),
			3,
		},
		{
			emitter({
				Texture = TEX.mote,
				Rate = 5,
				Lifetime = NumberRange.new(2.5, 4.5),
				Speed = NumberRange.new(0.4, 0.9),
				SpreadAngle = Vector2.new(20, 20),
				Drag = 0.5,
				Size = ns({ 0, 0.05, 0.5, 0.08, 1, 0.02 }),
				Transparency = ns({ 0, 1, 0.2, 0.3, 0.8, 0.4, 1, 1 }),
				Color = ColorSequence.new(Color3.fromRGB(200, 170, 255)),
				LightEmission = 1,
				Brightness = 2,
			}),
			5,
		},
	}

	-- put the sign back exactly as it was built
	s.reset = function(self)
		for _, letter in self.letters do
			letter.out = false
			for _, f in letter.faces do
				f.part.Color = f.color
			end
			for _, g in letter.glows do
				g.part.Transparency = g.transparency
			end
			if letter.halo then
				letter.halo.gui.Brightness = letter.halo.brightness
			end
		end
		for _, l in self.leds do
			l.part.Color = l.color
		end
		for _, c in self.chevrons do
			c.part.Color = c.color
		end
		for _, eye in self.eyes do
			eye.part.Transparency = 1
			if eye.gui then
				eye.gui.Enabled = false
			end
		end
		for _, h in self.halos do
			h.gui.Brightness = h.brightness
		end
		for _, l in self.lights do
			l.light.Brightness = l.brightness
		end
		self.flicker.letter, self.flicker.step = nil, 0
		self.eyesStart = -1
		for _, b in self.beams do
			b.Enabled = false
		end
		for _, pair in self.emitters do
			pair[1].Enabled = false
		end
	end
	state = s
end

------------------------------------------------------------------------------------------
-- Per frame
------------------------------------------------------------------------------------------
local function setActive(s, on: boolean)
	s.active = on
	if not on then
		s.reset(s)
		return
	end
	local q = quality()
	for _, pair in s.emitters do
		pair[1].Rate = pair[2] * (0.3 + 0.7 * q)
		pair[1].Enabled = true
	end
end

local function stepFlicker(s, t: number)
	local f = s.flicker
	if t < f.next or #s.letters == 0 then
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
		f.next = t + rng:NextNumber(9, 24)
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
		s.eyesAt = t + rng:NextNumber(25, 55)
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

local cullTimer = 0
local lastEyes = -1
local function step(dt: number)
	local s = state
	if not s then
		return
	end
	if not s.sign.Parent then
		teardown()
		return
	end
	local camera = workspace.CurrentCamera
	cullTimer -= dt
	if cullTimer <= 0 and camera then
		cullTimer = 0.25
		local near = (camera.CFrame.Position - s.view.Position).Magnitude < CULL
		if near ~= s.active then
			setActive(s, near)
		end
	end
	if not s.active then
		return
	end
	local t = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi / PULSE)
	local W, H = s.W, s.H

	-- sweep position along the panel (nil between sweeps)
	local sweepU = nil
	local sp = (t % SWEEP_EVERY) / SWEEP_TIME
	if sp <= 1 then
		local eased = sp * sp * (3 - 2 * sp)
		sweepU = -W / 2 - 1.5 + (W + 3) * eased
		local slant = 0.9
		s.a0.CFrame = CFrame.new(sweepU + slant, H / 2 + 0.2, s.sheenZ)
		s.a1.CFrame = CFrame.new(sweepU - slant, -H / 2 - 0.2, s.sheenZ)
		for _, b in s.beams do
			b.Enabled = true
		end
	elseif s.beams[1].Enabled then
		for _, b in s.beams do
			b.Enabled = false
		end
	end

	stepFlicker(s, t)

	-- letters: neon faces brighten under the sheen, rims breathe, a flickering letter goes out
	local anyOut = false
	for _, letter in s.letters do
		local boost = if sweepU then math.max(0, 1 - math.abs(letter.u - sweepU) / 1.8) else 0
		if letter.out then
			anyOut = true
			for _, f in letter.faces do
				f.part.Color = f.color:Lerp(Color3.new(0, 0, 0), 0.6)
			end
			for _, g in letter.glows do
				g.part.Transparency = 0.9
			end
			if letter.halo then
				letter.halo.gui.Brightness = letter.halo.brightness * 0.2
			end
		else
			for _, f in letter.faces do
				f.part.Color = f.color:Lerp(WHITE, boost * 0.6 + pulse * 0.08)
			end
			for _, g in letter.glows do
				g.part.Transparency = math.clamp(g.transparency + 0.1 - 0.16 * pulse - 0.2 * boost, 0, 1)
			end
			if letter.halo then
				letter.halo.gui.Brightness = letter.halo.brightness * (0.75 + 0.35 * pulse + 0.6 * boost)
			end
		end
	end

	-- LED chase (top row rightward, bottom leftward), lifted by the sheen too
	for _, l in s.leds do
		local dir = if l.row == 1 then -1 else 1
		local w = 0.5 + 0.5 * math.sin(t * 2.4 + dir * l.index * 0.55)
		local boost = if sweepU then math.max(0, 1 - math.abs(l.u - sweepU) / 1.5) else 0
		l.part.Color = LED_DIM:Lerp(LED_HOT, math.min(w * w * 0.85 + 0.15 + boost * 0.5, 1))
	end

	-- chevrons: outer, middle, inner, then all lit for a beat
	local phase = math.floor(t * 2.2) % 5
	for _, c in s.chevrons do
		local lit = phase >= 3 or (3 - phase) == c.step
		c.part.Color = if lit then c.color else c.color:Lerp(Color3.new(0, 0, 0), 0.75)
	end

	-- eyes in the O
	local a = eyesAlpha(s, t)
	if a ~= lastEyes then
		lastEyes = a
		for _, eye in s.eyes do
			eye.part.Transparency = 1 - a * 0.9
			if eye.gui then
				eye.gui.Enabled = a > 0.05
			end
		end
	end

	-- halos and lights breathe with the rims; a letter dropping out dims the sign's light a touch
	for _, h in s.halos do
		h.gui.Brightness = h.brightness * (0.8 + 0.3 * pulse)
	end
	local lightK = (0.9 + 0.15 * pulse) * (if anyOut then 0.85 else 1)
	for _, l in s.lights do
		l.light.Brightness = l.brightness * lightK
	end
end

------------------------------------------------------------------------------------------
-- Finding the sign
------------------------------------------------------------------------------------------
local function consider(inst: Instance)
	if inst.Name == "StoreSign" and inst:IsA("Model") and (not state or state.sign ~= inst) then
		-- let the rest of the model replicate in before reading it
		task.defer(function()
			if inst.Parent then
				setup(inst)
			end
		end)
	end
end

local function watchLobby(lobby: Instance)
	for _, d in lobby:GetDescendants() do
		consider(d)
	end
	lobby.DescendantAdded:Connect(consider)
end

local lobby = workspace:FindFirstChild("Lobby")
if lobby then
	watchLobby(lobby)
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Lobby" then
		watchLobby(child)
	end
end)

gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	if state and state.active then
		setActive(state, true)
	end
end)

RunService.RenderStepped:Connect(step)
