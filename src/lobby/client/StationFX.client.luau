--[[
	Reward-station VFX (client-only, everyone sees them). Reads the world built by
	builders/Rooms/Stations.luau and the attributes RewardsService sets:

	  rings     every station's floor ring breathes (rim / inner band / haze / light, ~3.6 s, each
	            station a little out of step) and lets a few slow motes rise in its colour; the
	            floating label bobs gently.
	  chest     DailyStation.OpenSeq changes -> unlatch, the lid swings up about Lid.LidHinge with a
	            creak, the gold glow and light come up, sparkles burst and a few coins and keys float
	            up out of it; ~4 s later the lid drops shut again.
	  wheel     WheelStation.SpinSeq changes -> the Rotor turns from its current angle by
	            Rewards.spinTravel(from, SpinIndex, SpinOffset) clockwise, eased with Rewards.spinEase
	            over Rewards.SpinDuration from SpinStart (server time), so every client lands together.
	            A tick at the pointer (WheelTick3D, at most ~25/s) and a flapper kick for every segment
	            boundary that passes; the winning segment glows when it settles. A fresh client parks
	            the rotor at Rewards.restAngle(SpinIndex, SpinOffset).

	Only plain property writes per frame; motion is local (the server never moves these parts).
	Missing pieces are skipped: if Lobby.Stations never appears the script just ends.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local lobby = workspace:WaitForChild("Lobby", 60)
local stations = lobby and lobby:WaitForChild("Stations", 30)
if not stations then
	return
end

local TEX_MOTE = "rbxasset://textures/particles/explosion01_implosion_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GOLD = Color3.fromRGB(255, 196, 92)
local COIN = Color3.fromRGB(220, 170, 70)
local PULSE_PERIOD = 3.6
local CULL = 90 -- studs: rings further than this from the camera don't animate

local fxFolder = Instance.new("Folder")
fxFolder.Name = "StationFX"
fxFolder.Parent = workspace

local function ns(points: { number }): NumberSequence
	local keys = {}
	for i = 1, #points, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keys)
end

-- An invisible, inert local part (emitter hosts, floaters).
local function localPart(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end

------------------------------------------------------------------------------------------
-- Rings
------------------------------------------------------------------------------------------
type RingFX = {
	rim: BasePart,
	band: BasePart?,
	haze: BasePart?,
	hazeSize: Vector3,
	light: PointLight?,
	label: BillboardGui?,
	labelBase: Vector3,
	phase: number,
	pos: Vector3,
}
local rings: { RingFX } = {}

local function setupRing(model: Instance, phase: number, color: Color3)
	local rim = model:WaitForChild("Ring", 10) :: BasePart?
	if not rim then
		return
	end
	local haze = model:FindFirstChild("RingHaze") :: BasePart?
	local anchor = model:FindFirstChild("LabelAnchor")
	local label = anchor and anchor:FindFirstChild("Label") :: BillboardGui?
	local fx: RingFX = {
		rim = rim,
		band = model:FindFirstChild("RingBand") :: BasePart?,
		haze = haze,
		hazeSize = if haze then haze.Size else Vector3.one,
		light = rim:FindFirstChild("RingLight", true) :: PointLight?,
		label = label,
		labelBase = if label then label.StudsOffset else Vector3.zero,
		phase = phase,
		pos = rim.Position,
	}
	table.insert(rings, fx)

	-- slow motes drifting up off the ring: spread over its inner disc, the rate following its area
	-- (2.5/s on a radius-3 ring, ~5/s on the big ones), the motes a touch larger and taller-rising
	local radius = tonumber(model:GetAttribute("RingRadius")) or 3
	local k = math.clamp(radius / 3, 0.6, 2)
	local area = localPart(
		"RingMotes",
		Vector3.new(radius * 1.4, 0.1, radius * 1.4),
		CFrame.new(rim.Position + Vector3.new(0, 0.12, 0))
	)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = TEX_MOTE
	motes.Color = ColorSequence.new(color)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Brightness = 1.6
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Rate = 2.5 * k * k
	motes.Lifetime = NumberRange.new(3, 5)
	motes.Speed = NumberRange.new(0.3, 0.65 * math.sqrt(k))
	motes.SpreadAngle = Vector2.new(12, 12)
	motes.Acceleration = Vector3.new(0, 0.04, 0)
	motes.Drag = 0.3
	local m = math.sqrt(k)
	motes.Size = ns({ 0, 0, 0.2, 0.12 * m, 0.8, 0.09 * m, 1, 0 })
	motes.Transparency = ns({ 0, 1, 0.25, 0.35, 0.75, 0.5, 1, 1 })
	motes.Parent = area
end

local function stepRings(t: number, camPos: Vector3)
	for _, r in rings do
		if (r.pos - camPos).Magnitude > CULL then
			continue
		end
		local s = 0.5 + 0.5 * math.sin(t * (2 * math.pi / PULSE_PERIOD) + r.phase)
		r.rim.Transparency = 0.12 + 0.3 * (1 - s)
		if r.band then
			r.band.Transparency = 0.22 + 0.4 * s -- the inner band breathes against the rim
		end
		if r.haze then
			local grow = 0.95 + 0.09 * s
			r.haze.Size = Vector3.new(r.hazeSize.X, r.hazeSize.Y * grow, r.hazeSize.Z * grow)
			r.haze.Transparency = 0.88 - 0.1 * s
		end
		if r.light then
			r.light.Brightness = 0.3 + 0.25 * s
		end
		if r.label then
			r.label.StudsOffset = r.labelBase + Vector3.new(0, 0.1 * math.sin(t * 1.1 + r.phase), 0)
		end
	end
end

------------------------------------------------------------------------------------------
-- Floaters: coins and little keys that rise out of the chest, spin and fade
------------------------------------------------------------------------------------------
type Floater = {
	obj: PVInstance,
	parts: { BasePart },
	from: CFrame,
	vel: Vector3,
	spin: number,
	t0: number,
	life: number,
}
local floaters: { Floater } = {}

local function makeCoin(scale: number): Part
	local p = localPart("Coin", Vector3.new(0.04, 0.26, 0.26) * scale, CFrame.new())
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = COIN
	return p
end

local function makeKey(scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Key"
	local shaft = localPart("Shaft", Vector3.new(0.42, 0.06, 0.04) * scale, CFrame.new())
	local bit = localPart("Bit", Vector3.new(0.06, 0.14, 0.04) * scale, CFrame.new(0.18 * scale, -0.07 * scale, 0))
	local bow = localPart(
		"Bow",
		Vector3.new(0.04, 0.2, 0.2) * scale,
		CFrame.new(-0.27 * scale, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	)
	bow.Shape = Enum.PartType.Cylinder
	for _, p in { shaft, bit, bow } do
		p.Material = Enum.Material.Neon
		p.Color = COIN
		p.Parent = model
	end
	model.PrimaryPart = shaft
	model.Parent = fxFolder
	return model
end

-- `scale` = the chest's size relative to its 2.2-wide design (spread and lift grow with it).
local function launch(obj: PVInstance, origin: Vector3, rng: Random, scale: number)
	local parts = {}
	if obj:IsA("BasePart") then
		table.insert(parts, obj)
	else
		for _, d in obj:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	table.insert(floaters, {
		obj = obj,
		parts = parts,
		from = CFrame.new(
			origin + Vector3.new(rng:NextNumber(-0.6, 0.6) * scale, 0, rng:NextNumber(-0.3, 0.3) * scale)
		) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
		vel = Vector3.new(
			rng:NextNumber(-0.35, 0.35) * scale,
			rng:NextNumber(1.4, 2.2) * math.sqrt(scale),
			rng:NextNumber(-0.35, 0.35) * scale
		),
		spin = rng:NextNumber(4, 7) * (if rng:NextNumber() < 0.5 then -1 else 1),
		t0 = os.clock(),
		life = rng:NextNumber(1.3, 1.9),
	})
end

local function stepFloaters(now: number)
	for i = #floaters, 1, -1 do
		local f = floaters[i]
		local age = now - f.t0
		if age >= f.life then
			f.obj:Destroy()
			table.remove(floaters, i)
			continue
		end
		local k = age / f.life
		local rise = f.vel * age - Vector3.new(0, 0.35 * age * age, 0) -- eases off as it climbs
		f.obj:PivotTo(f.from * CFrame.new(rise) * CFrame.Angles(0, f.spin * age, 0) * CFrame.Angles(0, 0, 0.3))
		local transparency = if k < 0.15 then 1 - k / 0.15 else math.max(0, (k - 0.55) / 0.45)
		for _, p in f.parts do
			p.Transparency = transparency
		end
	end
end

------------------------------------------------------------------------------------------
-- Daily chest
------------------------------------------------------------------------------------------
local function setupChest(model: Instance)
	local chest = model:WaitForChild("Chest", 10)
	local lid = chest and chest:WaitForChild("Lid", 10)
	local hinge = lid and lid:WaitForChild("LidHinge", 10) :: BasePart?
	if not (chest and lid and hinge) then
		return
	end
	local lidModel = lid :: Model
	local hingeCF = hinge.CFrame
	local rel = hingeCF:ToObjectSpace(lidModel:GetPivot())
	local glow = chest:FindFirstChild("Glow") :: BasePart?
	local light = glow and glow:FindFirstChild("GlowLight") :: PointLight?
	local plate = (chest:FindFirstChild("LockPlate") or chest:FindFirstChild("Body") or hinge) :: BasePart
	local OPEN = 105
	-- the chest's size relative to its 2.2 x 1.4 design (built 1.7x): every offset/size below scales by it
	local body = chest:FindFirstChild("Body") :: BasePart?
	local scale = if body then math.clamp(body.Size.X / 2.2, 0.5, 3) else 1
	local depth = if body then body.Size.Z else 1.4 * scale

	local driver = Instance.new("NumberValue")
	driver.Changed:Connect(function(v: number)
		lidModel:PivotTo(hingeCF * CFrame.Angles(math.rad(OPEN * v), 0, 0) * rel)
	end)
	local tween: Tween? = nil
	local function swing(to: number, duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(driver, TweenInfo.new(duration, style, direction), { Value = to })
		tween:Play()
	end

	-- the burst: golden sparkles thrown up and out, then slower glints drifting up
	-- the middle of the open chest's mouth (the hinge is on the back-top edge)
	local top = hingeCF.Position + hingeCF:VectorToWorldSpace(Vector3.new(0, 0.1 * scale, -depth / 2))
	local host = localPart("ChestBurst", Vector3.new(1.4, 0.2, 0.8) * scale, hingeCF.Rotation + top)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = TEX_SPARKLE
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), GOLD)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Brightness = 2
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.Rate = 0
	sparkles.Lifetime = NumberRange.new(0.7, 1.3)
	sparkles.Speed = NumberRange.new(4 * math.sqrt(scale), 7.5 * math.sqrt(scale))
	sparkles.SpreadAngle = Vector2.new(35, 35)
	sparkles.Acceleration = Vector3.new(0, -7, 0)
	sparkles.Drag = 1.2
	sparkles.Size = ns({ 0, 0.28 * scale, 1, 0 })
	sparkles.Transparency = ns({ 0, 0, 0.7, 0.2, 1, 1 })
	sparkles.RotSpeed = NumberRange.new(-180, 180)
	sparkles.Parent = host
	local glints = sparkles:Clone()
	glints.Texture = TEX_MOTE
	glints.Lifetime = NumberRange.new(1.6, 2.6)
	glints.Speed = NumberRange.new(1 * math.sqrt(scale), 2 * math.sqrt(scale))
	glints.SpreadAngle = Vector2.new(20, 20)
	glints.Acceleration = Vector3.new(0, 0.3, 0)
	glints.Size = ns({ 0, 0, 0.15, 0.22 * scale, 1, 0 })
	glints.Parent = host

	local rng = Random.new()
	local token = 0
	local function open()
		token += 1
		local mine = token
		Sfx.at(plate, "ChestUnlatch")
		-- the lid gives a little as the latch lets go
		swing(0.04, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.wait(0.3)
		if mine ~= token then
			return
		end
		Sfx.at(hinge, "ChestCreak")
		swing(1, 0.95, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if glow then
			TweenService:Create(glow, TweenInfo.new(0.45), { Transparency = 0.55 }):Play()
		end
		if light then
			light.Brightness = 0
			light.Enabled = true
			TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 2.2 }):Play()
		end
		task.wait(0.2)
		if mine ~= token then
			return
		end
		sparkles:Emit(60)
		glints:Emit(18)
		for i = 1, 9 do
			launch(if i <= 2 then makeKey(scale) else makeCoin(scale), top, rng, scale)
		end

		task.wait(4)
		if mine ~= token then
			return
		end
		Sfx.at(hinge, "ChestCreak", { speed = 1.15, volume = 0.3 })
		swing(0, 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if glow then
			TweenService:Create(glow, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		if light then
			TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		end
		task.wait(0.55)
		if mine == token and light then
			light.Enabled = false
		end
	end

	model:GetAttributeChangedSignal("OpenSeq"):Connect(function()
		task.spawn(open)
	end)
end

------------------------------------------------------------------------------------------
-- Wheel of Fate
------------------------------------------------------------------------------------------
type Spin = { from: number, travel: number, start: number, index: number }
type SegPart = { part: BasePart, color: Color3, material: Enum.Material }
local wheel = {
	ready = false,
	angle = 0,
	spin = nil :: Spin?,
	tickIndex = 0,
	lastTick = 0,
	flap = 0,
}
local setRotor: (number) -> () = function() end
local setFlap: (number) -> () = function() end
local tipPart: BasePart? = nil
local segments: { [number]: { SegPart } } = {}
local glowToken = 0

local SEG = Rewards.SegmentAngle
local HALF = SEG / 2

local function boundaryIndex(angle: number): number
	-- a segment boundary sits under the pointer whenever the rotor angle is HALF (mod SEG)
	return math.floor((angle - HALF) / SEG)
end

local function restoreSegments()
	for _, list in segments do
		for _, s in list do
			s.part.Material = s.material
			s.part.Color = s.color
		end
	end
end

local function winGlow(index: number)
	glowToken += 1
	local mine = glowToken
	local list = segments[index]
	if not list then
		return
	end
	task.spawn(function()
		for blink = 1, 4 do
			if mine ~= glowToken then
				return
			end
			for _, s in list do
				s.part.Material = Enum.Material.Neon
				s.part.Color = s.color:Lerp(Color3.new(1, 1, 1), 0.12)
			end
			task.wait(if blink == 4 then 1.6 else 0.22)
			if mine ~= glowToken then
				return
			end
			for _, s in list do
				s.part.Material = s.material
				s.part.Color = s.color
			end
			task.wait(0.14)
		end
	end)
end

local function setupWheel(model: Instance)
	local rotor = model:WaitForChild("Rotor", 10) :: Model?
	local hub = rotor and rotor:WaitForChild("Hub", 10) :: BasePart?
	if not (rotor and hub) then
		return
	end
	local hubCF = hub.CFrame
	local rel = hubCF:ToObjectSpace(rotor:GetPivot())
	setRotor = function(deg: number)
		-- +Z rotation in the hub's frame is clockwise as seen from the front (LookVector side)
		rotor:PivotTo(hubCF * CFrame.Angles(0, 0, math.rad(deg)) * rel)
	end
	for _, d in rotor:GetDescendants() do
		local i = d:GetAttribute("Segment")
		if d:IsA("BasePart") and d.Name == "Segment" and type(i) == "number" then
			segments[i] = segments[i] or {}
			table.insert(segments[i], { part = d, color = d.Color, material = d.Material })
		end
	end

	local pointer = model:FindFirstChild("Pointer") :: Model?
	local pivot = pointer and pointer:FindFirstChild("PointerHinge") :: BasePart?
	if pointer and pivot then
		local pivotCF = pivot.CFrame
		local prel = pivotCF:ToObjectSpace(pointer:GetPivot())
		tipPart = (pointer:FindFirstChild("PointerTip") or pivot) :: BasePart
		setFlap = function(k: number)
			-- negative turn swings the tip to the viewer's right, the way the pegs shove it
			pointer:PivotTo(pivotCF * CFrame.Angles(0, 0, math.rad(-20 * k)) * prel)
		end
	end

	local index = tonumber(model:GetAttribute("SpinIndex"))
	if index then
		wheel.angle = Rewards.restAngle(index, tonumber(model:GetAttribute("SpinOffset")) or 0)
		setRotor(wheel.angle)
	end
	wheel.ready = true

	model:GetAttributeChangedSignal("SpinSeq"):Connect(function()
		-- the server sets SpinIndex / SpinOffset / SpinStart alongside; read them once they've all landed
		task.defer(function()
			local idx = tonumber(model:GetAttribute("SpinIndex"))
			if not idx then
				return
			end
			glowToken += 1
			restoreSegments()
			local from = wheel.angle % 360
			wheel.spin = {
				from = from,
				travel = Rewards.spinTravel(from, idx, tonumber(model:GetAttribute("SpinOffset")) or 0),
				start = tonumber(model:GetAttribute("SpinStart")) or workspace:GetServerTimeNow(),
				index = idx,
			}
			wheel.tickIndex = boundaryIndex(from)
		end)
	end)
end

local function stepWheel(dt: number, now: number)
	local spin = wheel.spin
	if spin then
		local alpha = (workspace:GetServerTimeNow() - spin.start) / Rewards.SpinDuration
		local angle = spin.from + spin.travel * Rewards.spinEase(alpha)
		if alpha >= 1 then
			angle = (spin.from + spin.travel) % 360
			wheel.spin = nil
			winGlow(spin.index)
		else
			local b = boundaryIndex(angle)
			if b ~= wheel.tickIndex then
				wheel.tickIndex = b
				wheel.flap = 1
				if now - wheel.lastTick >= 0.04 and tipPart then
					wheel.lastTick = now
					Sfx.at(tipPart, "WheelTick3D")
				end
			end
		end
		wheel.angle = angle
		setRotor(angle)
	end
	if wheel.flap > 0 then
		wheel.flap = if wheel.flap < 0.01 then 0 else wheel.flap * math.exp(-dt * 12)
		setFlap(wheel.flap)
	end
end

------------------------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------------------------
local SPECS = {
	{ name = "DailyStation", station = "Daily", phase = 0 },
	{ name = "WheelStation", station = "Wheel", phase = 2.1 },
	{ name = "ChallengeStation", station = "Challenges", phase = 4.2 },
}
for _, spec in SPECS do
	task.spawn(function()
		local model = stations:WaitForChild(spec.name, 15)
		if not model then
			return
		end
		local info = Rewards.Stations[spec.station]
		setupRing(model, spec.phase, if info then info.color else GOLD)
		if spec.station == "Daily" then
			setupChest(model)
		elseif spec.station == "Wheel" then
			setupWheel(model)
		end
	end)
end

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	if camera then
		stepRings(now, camera.CFrame.Position)
	end
	if wheel.ready then
		stepWheel(dt, now)
	end
	if #floaters > 0 then
		stepFloaters(now)
	end
end)
