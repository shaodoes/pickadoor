--[[
	Atmospheric VFX (client-only). Builders drop invisible FX anchors (Kit.anchor: a Part with attribute
	FX = kind); this script finds them, including ones streamed in or rebuilt later, and dresses each one
	with soft, frame-rate effects: Beams for light, ParticleEmitters for motes/steam/embers/mist, and a
	little per-frame animation for flames, drips and caustics.

	Kinds handled (attributes in brackets are optional):
	  WindowShaft  Size = (width, height, ~0.2) on the window's inner face, forward = into the room.
	               [Color, Length = 18, Tilt = 0 (extra degrees the shaft dips below forward)]
	  Caustics     a panel whose forward face receives rippling water light. [Color]
	  LampDust     a volume of dust motes hanging in a lamp's light. [Color]
	  Candle       position = top of the wick. Flame, glow, flickering light, faint smoke wisp.
	  Steam        a leak; forward = jet direction.
	  Drip         on a ceiling; drops fall to whatever is below, splash and ripple. [Interval]
	  Embers       a volume at a furnace mouth; forward = outward.
	  PoolMist     a volume over the natatorium water.
	  any BasePart with attribute NeonFlicker = true flickers now and then.
	Plus, without anchors:
	  door gaps       every Lobby.Pads.<pad>.UnderGlow gets a fan of light across the floor that
	                  follows the brightness DoorFX gives UnderGlow.Leak (DoorFX's instances are only read)

	Cost: everything is pooled per anchor and built once. Every 0.25 s each effect is culled by the
	camera's distance to its bounds (beams/emitters/lights disabled beyond ~80 studs); per-frame work
	only touches nearby effects and only sets plain properties (no per-frame allocations). Emitter
	rates and optional layers scale with the player's graphics quality.
]]
local RunService = game:GetService("RunService")

local FX = {}

-- Beam textures map the image's X across the beam's width and its Y along the length (top = Attachment0).
-- Creator Store images (plain transparent gradients/light shapes, resolved from their decals):
local TEX = {
	soft = "rbxassetid://111717994998860", -- bell-shaped across X, constant along Y: soft-edged beam
	mote = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- small round soft dot
	glow = "rbxasset://textures/particles/explosion01_core_main.dds", -- broad round glow
	cone = "rbxassetid://16533771361", -- soft cone of light spreading down from a point
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	causticSheet = "rbxassetid://10008391264", -- 8x8 flipbook of tiling caustics, 128 px cells
}

local CULL = 80 -- studs from the camera to an effect's bounds
local SHAFT_ALPHA = 0.32 -- peak opacity of each overlapping window-shaft beam
local rng = Random.new()
local noise = math.noise

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
-- NumberSequence from flat {time, value, time, value, ...}
local function ns(points: { number }): NumberSequence
	local keys = {}
	for i = 1, #points, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function cs(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props or {} do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function attachment(parent: Instance, worldPos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Parent = parent
	a.WorldPosition = worldPos
	return a
end

-- Additive light beam. `fade` is the peak opacity; it fades in over the first few % and out at the end.
local function beam(
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	w0: number,
	w1: number,
	color: Color3,
	fade: number,
	texture: string?
)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = w0
	b.Width1 = w1
	b.Color = ColorSequence.new(color)
	b.Texture = texture or TEX.soft
	b.TextureMode = Enum.TextureMode.Stretch
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 12 -- transparency is sampled per segment vertex; 1 segment would only see both (clear) ends
	b.Transparency = ns({ 0, 1, 0.06, 1 - fade, 0.5, 1 - fade * 0.55, 1, 1 })
	b.Parent = parent
	return b
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

------------------------------------------------------------------------------------------
-- Quality: 0.1 .. 1 from the player's saved graphics level (Automatic counts as fairly high)
------------------------------------------------------------------------------------------
local gameSettings = UserSettings():GetService("UserGameSettings")
local function readQuality(): number
	local level = gameSettings.SavedQualityLevel
	if level == Enum.SavedQualitySetting.Automatic then
		return 0.75
	end
	return math.clamp(level.Value / 10, 0.1, 1)
end
FX.quality = readQuality()
local function rateScale(): number
	return 0.3 + 0.7 * FX.quality
end
local function extrasOn(): boolean
	return FX.quality >= 0.45
end

------------------------------------------------------------------------------------------
-- Effect registry and culling
------------------------------------------------------------------------------------------
--[[ An effect record:
	source   the instance it was made for (anchor part, Lamp model, pad, flicker part)
	cf, size bounds used for distance culling; cull = max distance
	model    a Model holding every instance the effect created (destroyed on teardown)
	toggles  instances with an Enabled property, switched by culling
	extras   optional instances, only on at higher graphics quality
	emitters { {emitter, baseRate} } whose rate follows the quality
	update   optional function(e, t, dt), called every frame while the effect is in range
]]
local effects = {}
local bySource: { [Instance]: any } = {}
FX.parent = nil :: Instance?
FX.rayParams = RaycastParams.new()
FX.rayParams.FilterType = Enum.RaycastFilterType.Exclude
FX.rayParams.IgnoreWater = true

local function newEffect(source: Instance, name: string, cf: CFrame, size: Vector3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = FX.parent
	return {
		source = source,
		cf = cf,
		size = size,
		cull = CULL,
		model = model,
		toggles = {},
		extras = {},
		emitters = {},
		active = true,
		seed = rng:NextNumber(0, 1000),
	}
end

local function applyActive(e, on: boolean)
	e.active = on
	local extras = extrasOn()
	for _, inst in e.toggles do
		inst.Enabled = on and (not e.extras[inst] or extras)
	end
	for _, pair in e.emitters do
		pair[1].Rate = pair[2] * rateScale()
	end
	if e.onActive then
		e.onActive(e, on)
	end
end

local function track(e, inst: Instance, extra: boolean?)
	table.insert(e.toggles, inst)
	if extra then
		e.extras[inst] = true
	end
	if inst:IsA("ParticleEmitter") then
		table.insert(e.emitters, { inst, inst.Rate })
	end
	return inst
end

-- Distance from a point to an oriented box.
local function boxDistance(cf: CFrame, size: Vector3, p: Vector3): number
	local l = cf:PointToObjectSpace(p)
	local h = size / 2
	local dx = math.max(math.abs(l.X) - h.X, 0)
	local dy = math.max(math.abs(l.Y) - h.Y, 0)
	local dz = math.max(math.abs(l.Z) - h.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function register(e)
	table.insert(effects, e)
	bySource[e.source] = e
	applyActive(e, true)
	return e
end

function FX.remove(source: Instance)
	local e = bySource[source]
	if not e then
		return
	end
	bySource[source] = nil
	local i = table.find(effects, e)
	if i then
		effects[i] = effects[#effects]
		effects[#effects] = nil
	end
	if e.cleanup then
		e.cleanup(e)
	end
	e.model:Destroy()
end

------------------------------------------------------------------------------------------
-- WindowShaft: soft volumetric light from the natatorium windows
------------------------------------------------------------------------------------------
local function windowShaft(a: BasePart)
	local color = a:GetAttribute("Color") or Color3.fromRGB(150, 200, 215)
	local length = a:GetAttribute("Length") or 18 -- attrs: Color, Length, Tilt, Strength
	local tilt = math.rad(a:GetAttribute("Tilt") or 0)
	local strength = a:GetAttribute("Strength") or 1 -- scales every layer (weaker shafts for small/high windows)
	local cf = a.CFrame
	local w, h = a.Size.X, a.Size.Y
	local dir = (cf * CFrame.Angles(-tilt, 0, 0)).LookVector
	local spread = 1.15 -- the shaft widens a little as it goes

	-- stop where the light lands (floor, furniture) so the ribbons never slice visibly into it
	local landing = workspace:Raycast(cf.Position + dir * 0.5, dir * length, FX.rayParams)
	if landing then
		length = math.max((landing.Position - cf.Position).Magnitude, 4)
	end

	local centre = cf.Position + dir * length / 2
	local e =
		newEffect(a, "WindowShaft", CFrame.lookAt(centre, centre + dir), Vector3.new(w * spread, h * spread, length))
	local holder = part(e.model, "Shaft", Vector3.new(0.2, 0.2, 0.2), cf, HIDDEN)

	-- Camera-facing beams with soft-edged textures overlap into one glowing volume: wide soft fills
	-- for the body of the shaft and streaky ray layers on top. Each starts just inside the glass and
	-- fades in over its first stretch, so no hard edge shows where it meets the window.
	local back = dir * -0.1
	local across = w >= h and cf.RightVector or cf.UpVector
	local long, short = math.max(w, h), math.min(w, h)
	e.beams = {}
	local function layer(
		offset: number,
		w0: number,
		w1: number,
		fade: number,
		texture: string,
		tint: number,
		speed: number,
		extra: boolean
	)
		local p0 = cf.Position + across * offset - back
		local p1 = cf.Position + dir * length + across * offset * spread
		local b = beam(
			holder,
			attachment(holder, p0),
			attachment(holder, p1),
			w0,
			w1,
			color:Lerp(Color3.new(1, 1, 1), tint),
			fade,
			texture
		)
		b.Transparency = ns({ 0, 1, 0.08, 1 - fade, 0.45, 1 - fade * 0.6, 0.8, 1 - fade * 0.15, 1, 1 })
		track(e, b, extra)
		table.insert(e.beams, { b = b, base = strength, speed = speed, phase = rng:NextNumber(0, 100) })
	end
	layer(0, long * 1.05, long * 1.05 * spread, SHAFT_ALPHA, TEX.soft, 0, 0.15, false)
	if long > short * 1.3 then
		layer(-long * 0.25, short * 1.2, short * 1.2 * spread, SHAFT_ALPHA * 0.8, TEX.soft, 0, 0.2, true)
		layer(long * 0.25, short * 1.2, short * 1.2 * spread, SHAFT_ALPHA * 0.8, TEX.soft, 0, 0.2, true)
	end
	-- thin brighter streaks (light through the glazing bars and ripples), each shimmering on its own
	local streaks = math.clamp(math.round(long / 1.6), 3, 6)
	for i = 1, streaks do
		local offset = ((i - 0.5) / streaks - 0.5) * long * 0.85
		local width = rng:NextNumber(0.5, 1.3)
		layer(offset + rng:NextNumber(-0.4, 0.4), width, width * 1.6, SHAFT_ALPHA * 1.1, TEX.soft, 0.3, 0.6, i % 2 == 0)
	end

	-- a faint pool of window light where the shaft lands, lying flat on that surface
	if landing then
		local n = landing.Normal
		local along = (dir - n * dir:Dot(n))
		along = along.Magnitude > 0.05 and along.Unit or n:Cross(cf.RightVector).Unit
		local side = n:Cross(along).Unit
		local function flatAt(p: Vector3)
			local at = Instance.new("Attachment")
			at.Parent = holder
			at.WorldCFrame = CFrame.fromMatrix(p + n * 0.05, along, side)
			return at
		end
		local patchLen = math.clamp(h / math.max(math.abs(dir:Dot(n)), 0.25), 3, 12)
		local hit = landing.Position + along * patchLen * 0.1
		local pool = beam(
			holder,
			flatAt(hit - along * patchLen / 2),
			flatAt(hit + along * patchLen / 2),
			w * 1.1,
			w * 1.25,
			color,
			SHAFT_ALPHA,
			TEX.soft
		)
		pool.FaceCamera = false
		pool.Transparency = ns({ 0, 1, 0.3, 1 - SHAFT_ALPHA * 0.9, 0.7, 1 - SHAFT_ALPHA * 0.9, 1, 1 })
		track(e, pool)
		table.insert(e.beams, { b = pool, base = strength, speed = 0.15, phase = rng:NextNumber(0, 100) })
	end

	-- dust motes drifting slowly through the light
	local volume = part(
		e.model,
		"Motes",
		Vector3.new(w, h, length * 0.75),
		CFrame.lookAt(cf.Position + dir * length * 0.4, cf.Position + dir * length),
		HIDDEN
	)
	e.motes = track(
		e,
		emitter(volume, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Texture = TEX.mote,
			Rate = math.clamp(w * h * length / 60, 3, 14),
			Lifetime = NumberRange.new(5, 9),
			Speed = NumberRange.new(0.02, 0.12),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 0.6,
			Size = ns({ 0, 0.03, 0.5, 0.05, 1, 0.03 }),
			Transparency = ns({ 0, 1, 0.25, 0.35, 0.75, 0.35, 1, 1 }),
			Color = cs(color:Lerp(Color3.new(1, 1, 1), 0.5)),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 1,
		})
	)

	e.update = function(self, t: number)
		for _, s in self.beams do
			-- slow uneven breathing, like light through moving water
			s.b.Brightness = s.base * (0.82 + 0.3 * noise(t * s.speed, s.phase))
		end
		self.motes.Acceleration = Vector3.new(
			noise(t * 0.1, self.seed) * 0.06,
			noise(t * 0.1, self.seed + 9) * 0.03,
			noise(t * 0.1, self.seed + 19) * 0.06
		)
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Caustics: animated rippling water light on a panel
------------------------------------------------------------------------------------------
local CAUSTIC_TILE = 7 -- studs per flipbook tile
local CAUSTIC_FPS = 14

local function caustics(a: BasePart)
	local color = a:GetAttribute("Color") or Color3.fromRGB(150, 215, 225)
	local cf = a.CFrame * CFrame.new(0, 0, -(a.Size.Z / 2 + 0.03))
	local w, h = a.Size.X, a.Size.Y
	local e = newEffect(a, "Caustics", cf, Vector3.new(w, h, 1))
	local surface = part(e.model, "Caustics", Vector3.new(w, h, 0.05), cf, HIDDEN)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.ClipsDescendants = true
	gui.Parent = surface
	track(e, gui)

	-- two layers of tiles at different scales and phases interfere like real caustics;
	-- each sits in nested CanvasGroups whose gradients feather the panel's edges
	local function feathered(parent: Instance, rotation: number)
		local group = Instance.new("CanvasGroup")
		group.Size = UDim2.fromScale(1, 1)
		group.BackgroundTransparency = 1
		group.Parent = parent
		local g = Instance.new("UIGradient")
		g.Rotation = rotation
		g.Transparency = ns({ 0, 1, 0.22, 0, 0.78, 0, 1, 1 })
		g.Parent = group
		return group
	end
	local outer = feathered(gui, 0)
	local inner = feathered(outer, 90)
	e.group = outer
	e.layers = {}
	for layer, spec in
		{ { tile = CAUSTIC_TILE, alpha = 0.15, phase = 0 }, { tile = CAUSTIC_TILE * 1.37, alpha = 0.55, phase = 29 } }
	do
		local tiles = {}
		local nx, ny = math.ceil(w / spec.tile) + 1, math.ceil(h / spec.tile) + 1
		for i = 0, nx - 1 do
			for k = 0, ny - 1 do
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Image = TEX.causticSheet
				img.ImageRectSize = Vector2.new(128, 128)
				img.ImageColor3 = color
				img.ImageTransparency = spec.alpha
				img.Size = UDim2.fromScale(spec.tile / w, spec.tile / h)
				img.Position = UDim2.fromScale(i * spec.tile / w, k * spec.tile / h)
				img.ZIndex = layer
				img.Parent = inner
				table.insert(tiles, img)
			end
		end
		table.insert(e.layers, { tiles = tiles, phase = spec.phase, frame = -1, spec = spec, nx = nx, ny = ny })
	end

	-- the light the water throws, swelling with the ripples
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 100
	light.Range = math.clamp(math.max(w, h) * 0.8, 6, 14)
	light.Brightness = 0.35
	light.Color = color
	light.Shadows = false
	light.Parent = surface
	track(e, light, true)
	e.light = light

	e.update = function(self, t: number)
		for li, layer in self.layers do
			local frame = math.floor(t * CAUSTIC_FPS + layer.phase) % 64
			if frame ~= layer.frame then
				layer.frame = frame
				local offset = Vector2.new((frame % 8) * 128, math.floor(frame / 8) * 128)
				for _, img in layer.tiles do
					img.ImageRectOffset = offset
				end
			end
			-- the second layer drifts slowly across the first
			if li == 2 then
				local tile = layer.spec.tile
				local sx = (t * 0.25 % tile) / w
				local sy = (t * 0.11 % tile) / h
				for idx, img in layer.tiles do
					local i, k = (idx - 1) // layer.ny, (idx - 1) % layer.ny
					img.Position = UDim2.fromScale((i - 1) * tile / w + sx, (k - 1) * tile / h + sy)
				end
			end
		end
		local swell = noise(t * 0.4, self.seed)
		self.group.GroupTransparency = 0.25 - swell * 0.2
		self.light.Brightness = 0.35 + swell * 0.2
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- LampDust: motes hanging in a lamp's light
------------------------------------------------------------------------------------------
local function lampDust(a: BasePart)
	local color = a:GetAttribute("Color") or Color3.fromRGB(255, 226, 186)
	local e = newEffect(a, "LampDust", a.CFrame, a.Size)
	local volume = part(e.model, "Motes", a.Size, a.CFrame, HIDDEN)
	local vol = a.Size.X * a.Size.Y * a.Size.Z
	e.motes = track(
		e,
		emitter(volume, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Texture = TEX.mote,
			Rate = math.clamp(vol / 50, 2, 10),
			Lifetime = NumberRange.new(6, 10),
			Speed = NumberRange.new(0.02, 0.1),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 0.6,
			Size = ns({ 0, 0.025, 0.5, 0.045, 1, 0.025 }),
			Transparency = ns({ 0, 1, 0.3, 0.45, 0.7, 0.45, 1, 1 }),
			Color = cs(color),
			LightEmission = 0.8,
			LightInfluence = 0.4, -- brighter where the lamp actually lights them
			Brightness = 1,
		})
	)
	e.update = function(self, t: number)
		self.motes.Acceleration = Vector3.new(
			noise(t * 0.12, self.seed) * 0.05,
			noise(t * 0.1, self.seed + 5) * 0.03 - 0.005,
			noise(t * 0.12, self.seed + 11) * 0.05
		)
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Candle: layered flame, glow, flickering light, faint smoke wisp
------------------------------------------------------------------------------------------
local function candle(a: BasePart)
	local pos = a.Position
	local e = newEffect(a, "Candle", CFrame.new(pos), Vector3.new(1, 1, 1))
	e.cull = 60
	local function flame(name: string, color: Color3, transparency: number, scale: Vector3)
		local p = part(e.model, name, Vector3.new(1, 1, 1), CFrame.new(pos), {
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = transparency,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = scale
		mesh.Parent = p
		return p, mesh
	end
	e.outer, e.outerMesh = flame("FlameOuter", Color3.fromRGB(255, 120, 30), 0.45, Vector3.new(0.13, 0.34, 0.13))
	e.inner, e.innerMesh = flame("FlameInner", Color3.fromRGB(255, 226, 160), 0.15, Vector3.new(0.065, 0.17, 0.065))

	local glow = Instance.new("BillboardGui")
	glow.Size = UDim2.fromScale(1.6, 1.6)
	glow.LightInfluence = 0
	glow.Brightness = 1.2
	glow.MaxDistance = 60
	glow.Adornee = e.outer
	glow.Parent = e.outer
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = TEX.glow
	img.ImageColor3 = Color3.fromRGB(255, 160, 80)
	img.ImageTransparency = 0.72
	img.Parent = glow
	track(e, glow)
	e.glow = img

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 90)
	light.Range = a:GetAttribute("Range") or 9
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = e.outer
	track(e, light)
	e.light = light

	local wisp = attachment(e.outer, pos + Vector3.new(0, 0.4, 0))
	track(
		e,
		emitter(wisp, {
			Texture = TEX.smoke,
			EmissionDirection = Enum.NormalId.Top,
			Rate = 1.4,
			Lifetime = NumberRange.new(2, 3.2),
			Speed = NumberRange.new(0.5, 0.9),
			SpreadAngle = Vector2.new(6, 6),
			Acceleration = Vector3.new(0, 0.25, 0),
			Drag = 0.8,
			Size = ns({ 0, 0.06, 1, 0.55 }),
			Transparency = ns({ 0, 1, 0.15, 0.88, 1, 1 }),
			RotSpeed = NumberRange.new(-40, 40),
			Rotation = NumberRange.new(0, 360),
			Color = cs(Color3.fromRGB(190, 186, 180)),
			LightInfluence = 1,
		}),
		true
	)

	e.update = function(self, t: number)
		local s = self.seed
		local flick = noise(t * 7, s) * 0.6 + noise(t * 19, s + 3) * 0.4 -- -1..1-ish
		local swayX = noise(t * 1.3, s + 7) * 0.5 + noise(t * 9, s + 8) * 0.12
		local swayZ = noise(t * 1.1, s + 9) * 0.5 + noise(t * 8, s + 10) * 0.12
		local stretch = 1 + flick * 0.12
		local tiltCF = CFrame.Angles(swayZ * 0.25, 0, -swayX * 0.25)
		self.outer.CFrame = CFrame.new(pos) * tiltCF * CFrame.new(0, 0.15 * stretch, 0)
		self.inner.CFrame = CFrame.new(pos) * tiltCF * CFrame.new(0, 0.085 * stretch, 0)
		self.outerMesh.Scale = Vector3.new(0.13, 0.34 * stretch, 0.13)
		self.innerMesh.Scale = Vector3.new(0.065, 0.17 * stretch, 0.065)
		self.light.Brightness = 0.9 * (1 + flick * 0.25)
		self.glow.ImageTransparency = 0.72 - flick * 0.06
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Steam: a hissing jet with the odd puff
------------------------------------------------------------------------------------------
local STEAM_COLOR = Color3.fromRGB(222, 226, 230)
local function steam(a: BasePart)
	local cf = a.CFrame
	local e = newEffect(a, "Steam", cf * CFrame.new(0, 0, -3), Vector3.new(3, 3, 6))
	local nozzle = part(e.model, "Nozzle", Vector3.new(0.15, 0.15, 0.15), cf, HIDDEN)
	e.jet = track(
		e,
		emitter(nozzle, {
			Texture = TEX.smoke,
			EmissionDirection = Enum.NormalId.Front,
			Rate = 26,
			Lifetime = NumberRange.new(0.55, 1),
			Speed = NumberRange.new(7, 10),
			SpreadAngle = Vector2.new(7, 7),
			Drag = 3,
			Acceleration = Vector3.new(0, 1.6, 0),
			Size = ns({ 0, 0.12, 0.4, 0.7, 1, 1.6 }),
			Transparency = ns({ 0, 0.62, 0.3, 0.72, 1, 1 }),
			RotSpeed = NumberRange.new(-60, 60),
			Rotation = NumberRange.new(0, 360),
			Color = cs(STEAM_COLOR),
			LightEmission = 0.08,
			LightInfluence = 0.9,
		})
	)
	e.puffs = track(
		e,
		emitter(nozzle, {
			Texture = TEX.smoke,
			EmissionDirection = Enum.NormalId.Front,
			Rate = 0,
			Lifetime = NumberRange.new(1.4, 2.4),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(25, 25),
			Drag = 1.3,
			Acceleration = Vector3.new(0, 0.9, 0),
			Size = ns({ 0, 0.4, 1, 3 }),
			Transparency = ns({ 0, 0.78, 1, 1 }),
			RotSpeed = NumberRange.new(-25, 25),
			Rotation = NumberRange.new(0, 360),
			Color = cs(STEAM_COLOR),
			LightEmission = 0.05,
			LightInfluence = 0.9,
		}),
		true
	)
	e.nextPuff = 0
	e.update = function(self, t: number)
		-- the hiss wavers, and every few seconds the pipe coughs out a puff
		self.jet.Rate = (24 + noise(t * 2, self.seed) * 10) * rateScale()
		if t >= self.nextPuff then
			self.nextPuff = t + rng:NextNumber(2.5, 6)
			if self.puffs.Enabled then
				self.puffs:Emit(rng:NextInteger(3, 6))
			end
		end
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Drip: a bead swells on the ceiling, falls, splashes and rings out on the surface below
------------------------------------------------------------------------------------------
local GRAVITY = 70
local WATER = Color3.fromRGB(196, 214, 222)
local function drip(a: BasePart)
	local top = a.Position
	local hit = workspace:Raycast(top - Vector3.new(0, 0.3, 0), Vector3.new(0, -60, 0), FX.rayParams)
	local floorPos = hit and hit.Position or top - Vector3.new(0, 20, 0)
	local normal = hit and hit.Normal or Vector3.yAxis
	local e = newEffect(a, "Drip", CFrame.new((top + floorPos) / 2), Vector3.new(3, top.Y - floorPos.Y + 1, 3))
	e.cull = 60
	e.top, e.floorPos, e.landed = top, floorPos, hit ~= nil

	local function droplet(name: string)
		local p = part(e.model, name, Vector3.new(1, 1, 1), CFrame.new(top), {
			Material = Enum.Material.Glass,
			Color = WATER,
			Transparency = 1,
			Reflectance = 0.25,
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(0.1, 0.1, 0.1)
		mesh.Parent = p
		return p, mesh
	end
	e.bead, e.beadMesh = droplet("Bead")
	e.drop, e.dropMesh = droplet("Drop")

	-- splash and ripple sit on the surface, aligned to it
	local right = math.abs(normal.Y) > 0.9 and Vector3.xAxis or normal:Cross(Vector3.yAxis).Unit
	local surfaceCF = CFrame.fromMatrix(floorPos + normal * 0.03, right, normal)
	local base = part(e.model, "Ripple", Vector3.new(3, 0.02, 3), surfaceCF, HIDDEN)
	local splashAt = Instance.new("Attachment")
	splashAt.Parent = base
	e.splash = track(
		e,
		emitter(splashAt, {
			Texture = TEX.mote,
			EmissionDirection = Enum.NormalId.Top,
			Rate = 0,
			Lifetime = NumberRange.new(0.22, 0.42),
			Speed = NumberRange.new(2.5, 4.5),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -45, 0),
			Size = ns({ 0, 0.07, 1, 0.03 }),
			Transparency = ns({ 0, 0.15, 1, 1 }),
			Color = cs(WATER),
			LightEmission = 0.3,
			LightInfluence = 0.8,
		})
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.5
	gui.Brightness = 1.4
	gui.Parent = base
	track(e, gui)
	e.rings = {}
	for _ = 1, 2 do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(214, 228, 232)
		stroke.Thickness = 2.5
		stroke.Parent = ring
		table.insert(e.rings, { frame = ring, stroke = stroke, start = -1 })
	end

	local interval = a:GetAttribute("Interval")
	e.state, e.stateT = "wait", os.clock() + rng:NextNumber(0, 3)
	e.update = function(self, t: number, dt: number)
		if self.state == "wait" then
			if t >= self.stateT then
				self.state, self.stateT = "form", t
				self.bead.Transparency = 0.25
			end
		elseif self.state == "form" then
			-- the bead swells on the ceiling, sagging a little before it lets go
			local k = math.min((t - self.stateT) / 1.4, 1)
			local r = 0.04 + 0.08 * k
			self.beadMesh.Scale = Vector3.new(r, r * (1 + k * 0.5), r)
			self.bead.CFrame = CFrame.new(self.top - Vector3.new(0, r * 0.6, 0))
			if k >= 1 then
				self.state, self.vel, self.y = "fall", 0, self.top.Y - 0.15
				self.bead.Transparency = 1
				self.drop.Transparency = 0.25
			end
		elseif self.state == "fall" then
			self.vel += GRAVITY * dt
			self.y -= self.vel * dt
			local stretch = math.min(1 + self.vel * 0.05, 2.4)
			self.dropMesh.Scale = Vector3.new(0.09, 0.11 * stretch, 0.09)
			self.drop.CFrame = CFrame.new(self.top.X, self.y, self.top.Z)
			if self.y <= self.floorPos.Y + 0.05 then
				self.drop.Transparency = 1
				if self.landed then
					self.splash:Emit(rng:NextInteger(5, 9))
					self.rings[1].start, self.rings[2].start = t, t + 0.18
				end
				self.state = "wait"
				self.stateT = t + (interval or rng:NextNumber(1.8, 5))
			end
		end
		for _, ring in self.rings do
			if ring.start >= 0 then
				local k = (t - ring.start) / 1.1
				if k >= 1 then
					ring.start = -1
					ring.frame.Visible = false
				elseif k >= 0 then
					local eased = 1 - (1 - k) ^ 2
					local s = 0.08 + 0.92 * eased
					ring.frame.Visible = true
					ring.frame.Size = UDim2.fromScale(s, s)
					ring.stroke.Transparency = 0.25 + 0.75 * k
					ring.stroke.Thickness = 3 - 2 * k
				end
			end
		end
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Embers: sparks drifting up and out of a furnace mouth, with a heat haze
------------------------------------------------------------------------------------------
local function embers(a: BasePart)
	local cf = a.CFrame
	local e = newEffect(a, "Embers", cf * CFrame.new(0, 2, -2), a.Size + Vector3.new(4, 6, 4))
	local mouth = part(e.model, "Mouth", a.Size, cf, HIDDEN)
	e.sparks = track(
		e,
		emitter(mouth, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			EmissionDirection = Enum.NormalId.Front,
			Texture = TEX.mote,
			Rate = 7,
			Lifetime = NumberRange.new(1.6, 3.4),
			Speed = NumberRange.new(1.2, 3),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(0, 2.6, 0),
			Drag = 0.7,
			Size = ns({ 0, 0.1, 0.5, 0.07, 1, 0 }),
			Transparency = ns({ 0, 0, 0.75, 0.15, 1, 1 }),
			Color = cs(Color3.fromRGB(255, 226, 150), Color3.fromRGB(255, 128, 40), Color3.fromRGB(170, 36, 12)),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 4,
		})
	)
	track(
		e,
		emitter(mouth, {
			Texture = TEX.smoke,
			EmissionDirection = Enum.NormalId.Top,
			Rate = 3,
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(15, 15),
			Size = ns({ 0, 0.8, 1, 2.6 }),
			Transparency = ns({ 0, 1, 0.3, 0.93, 1, 1 }),
			RotSpeed = NumberRange.new(-30, 30),
			Rotation = NumberRange.new(0, 360),
			Color = cs(Color3.fromRGB(255, 170, 110)),
			LightEmission = 0.4,
			LightInfluence = 0.2,
		}),
		true
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 50)
	light.Range = 10
	light.Brightness = 0.6
	light.Shadows = false
	light.Parent = mouth
	track(e, light, true)
	e.light = light
	e.update = function(self, t: number)
		local s = self.seed
		self.sparks.Acceleration =
			Vector3.new(noise(t * 0.7, s) * 1.6, 2.6 + noise(t * 0.9, s + 4), noise(t * 0.7, s + 8) * 1.6)
		self.light.Brightness = 0.6 + noise(t * 5, s + 2) * 0.25 + noise(t * 13, s + 6) * 0.1
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- PoolMist: thin mist breathing over the natatorium water
------------------------------------------------------------------------------------------
local function poolMist(a: BasePart)
	local e = newEffect(a, "PoolMist", a.CFrame, a.Size)
	e.cull = 160
	local volume = part(e.model, "Mist", a.Size, a.CFrame, HIDDEN)
	local area = a.Size.X * a.Size.Z
	e.mist = track(
		e,
		emitter(volume, {
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Texture = TEX.smoke,
			Rate = math.clamp(area / 120, 2, 18),
			Lifetime = NumberRange.new(12, 18),
			Speed = NumberRange.new(0.05, 0.25),
			SpreadAngle = Vector2.new(180, 10),
			Acceleration = Vector3.new(0.05, 0, 0.02),
			Size = ns({ 0, 6, 1, 12 }),
			Transparency = ns({ 0, 1, 0.3, 0.9, 0.7, 0.9, 1, 1 }),
			RotSpeed = NumberRange.new(-4, 4),
			Rotation = NumberRange.new(0, 360),
			Color = cs(a:GetAttribute("Color") or Color3.fromRGB(176, 208, 212)),
			LightEmission = 0.15,
			LightInfluence = 0.5,
		})
	)
	return register(e)
end

------------------------------------------------------------------------------------------
-- NeonFlicker: a rare, subtle stutter in a sign or tube
------------------------------------------------------------------------------------------
local FLICKER_PATTERN = { 0.05, 0.08, 0.04, 0.22, 0.06 } -- alternating dim / lit durations
local function neonFlicker(p: BasePart)
	local e = newEffect(p, "NeonFlicker", p.CFrame, p.Size)
	e.cull = 70
	e.color = p.Color
	e.dim = p.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	e.lights = {}
	for _, l in p:GetChildren() do
		if l:IsA("Light") then
			table.insert(e.lights, { light = l, base = l.Brightness })
		end
	end
	e.next = os.clock() + rng:NextNumber(4, 30)
	e.step = 0
	local function set(self, dim: boolean)
		p.Color = dim and self.dim or self.color
		for _, l in self.lights do
			l.light.Brightness = dim and l.base * 0.35 or l.base
		end
	end
	e.update = function(self, t: number)
		if t < self.next then
			return
		end
		-- walk the pattern: odd steps dim, even steps lit
		self.step += 1
		if self.step > #FLICKER_PATTERN then
			self.step = 0
			set(self, false)
			self.next = t + rng:NextNumber(12, 40)
			return
		end
		set(self, self.step % 2 == 1)
		self.next = t + FLICKER_PATTERN[self.step] * rng:NextNumber(0.7, 1.4)
	end
	e.onActive = function(self, on)
		if not on then
			self.step = 0
			set(self, false)
		end
	end
	e.cleanup = function(self)
		if p.Parent then
			set(self, false)
		end
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Pendant lamps: a faint volumetric cone of light under each Lamp's core
------------------------------------------------------------------------------------------
local function _lampCone(lamp: Instance, core: BasePart)
	local light = core:FindFirstChildOfClass("SpotLight") or core:FindFirstChildOfClass("PointLight")
	if not light then
		return nil
	end
	local shade = lamp:FindFirstChild("Shade") ~= nil
	local pos = core.Position
	local hit = workspace:Raycast(pos - Vector3.new(0, 0.8, 0), Vector3.new(0, -30, 0), FX.rayParams)
	local floorY = hit and hit.Position.Y or pos.Y - 10
	local len = pos.Y - floorY
	if len < 3 then
		return nil
	end
	local e = newEffect(lamp, "LampCone", CFrame.new(pos.X, (pos.Y + floorY) / 2, pos.Z), Vector3.new(8, len, 8))
	local holder = part(e.model, "Cone", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), HIDDEN)
	local a0 = attachment(holder, pos - Vector3.new(0, shade and 0.5 or 0.7, 0))
	local a1 = attachment(holder, Vector3.new(pos.X, floorY + 1.2, pos.Z))
	local color = light.Color
	-- the cone texture draws the spreading light itself; a soft fill underneath gives it body
	local spreadW = math.min(len * (shade and 1.0 or 0.75), 11)
	local cone = beam(holder, a0, a1, spreadW * 0.55, spreadW, color, 1, TEX.cone)
	local fade = shade and 0.55 or 0.3
	cone.Transparency = ns({ 0, 1, 0.06, 1 - fade, 0.6, 1 - fade * 0.7, 0.92, 1, 1, 1 })
	local fill = beam(holder, a0, a1, spreadW * 0.25, spreadW * 0.8, color, shade and 0.07 or 0.04)
	e.beams = { track(e, cone), track(e, fill, true) }
	e.light, e.base = light, math.max(light.Brightness, 0.01)
	e.update = function(self)
		-- follow whatever else animates the lamp (flicker scripts), so the cone dies with the bulb
		local k = math.clamp(self.light.Brightness / self.base, 0, 1.5)
		for _, b in self.beams do
			b.Brightness = k
		end
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Door gaps: light fanning across the floor from under each door, driven by DoorFX's Leak light
------------------------------------------------------------------------------------------
local function doorGlow(pad: Instance, glow: BasePart)
	local leak = glow:FindFirstChild("Leak")
	local color = glow.Color
	local right = glow.CFrame.RightVector
	if math.abs(glow.Size.Z) > math.abs(glow.Size.X) then
		right = glow.CFrame.LookVector
	end
	-- "out" is horizontal and perpendicular to the gap, pointing at the room (toward the spill/threshold)
	local out = Vector3.new(0, 1, 0):Cross(right).Unit
	local ref = pad:FindFirstChild("FloorSpill") or pad:FindFirstChild("Threshold") or pad:FindFirstChild("Zone")
	local refPos = ref and (ref:IsA("BasePart") and ref.Position or ref:IsA("Model") and ref:GetPivot().Position)
	if refPos then
		if (refPos - glow.Position):Dot(out) < 0 then
			out = -out
		end
	elseif out.Z < 0 then
		out = -out
	end
	local width = math.max(glow.Size.X, glow.Size.Z)
	local floorY = glow.Position.Y - glow.Size.Y / 2 + 0.1
	local origin = Vector3.new(glow.Position.X, floorY, glow.Position.Z)
	local e =
		newEffect(pad, "DoorGlow", CFrame.lookAt(origin + out * 3, origin + out * 6), Vector3.new(width * 2, 3, 6))
	local holder = part(e.model, "Fan", Vector3.new(0.2, 0.2, 0.2), CFrame.new(origin), HIDDEN)

	-- flat on the floor: a non-camera-facing beam spreads its width along its attachments' Y axis,
	-- so give them X = along the beam and Y = across the gap (horizontal)
	local flat = CFrame.fromMatrix(Vector3.zero, out, right)
	local function flatAttachment(p: Vector3)
		local at = Instance.new("Attachment")
		at.Parent = holder
		at.WorldCFrame = CFrame.new(p) * flat
		return at
	end
	local fan = beam(
		holder,
		flatAttachment(origin + out * 0.15),
		flatAttachment(origin + out * 4.2),
		width * 0.95,
		width * 1.5,
		color,
		0.25
	)
	fan.FaceCamera = false
	-- subtle: a soft spill that fades fast, not a lit slab across the mat
	fan.Transparency = ns({ 0, 0.62, 0.15, 0.72, 0.45, 0.88, 0.8, 0.97, 1, 1 })
	-- a low haze hugging the floor in front of the gap
	local hazeA = attachment(holder, origin + Vector3.new(0, 0.25, 0) + out * 0.1)
	local hazeB = attachment(holder, origin + Vector3.new(0, 0.35, 0) + out * 3)
	local haze = beam(holder, hazeA, hazeB, 0.5, 1.6, color, 0.18)
	haze.Width0, haze.Width1 = width * 0.25, width * 0.7
	e.beams = { track(e, fan), track(e, haze, true) }
	e.leak, e.glow = leak, glow
	e.update = function(self)
		if not self.leak or not self.leak.Parent then
			self.leak = self.glow:FindFirstChild("Leak")
			if not self.leak then
				return
			end
		end
		-- DoorFX swings Leak.Brightness ~0.2 (idle) .. 2.2 (launching)
		local k = math.clamp(self.leak.Brightness / 2.4, 0.05, 1)
		for _, b in self.beams do
			b.Brightness = k
		end
	end
	return register(e)
end

------------------------------------------------------------------------------------------
-- Dispatch and watching
------------------------------------------------------------------------------------------
local KINDS = {
	WindowShaft = windowShaft,
	Caustics = caustics,
	LampDust = lampDust,
	Candle = candle,
	Steam = steam,
	Drip = drip,
	Embers = embers,
	PoolMist = poolMist,
}
FX.KINDS = KINDS

local function safely(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[AtmosFX]", err)
	end
end

-- Set up whatever effect `inst` calls for (no-op if it isn't one, or already has one).
function FX.consider(inst: Instance)
	if bySource[inst] then
		return
	end
	if inst:IsA("BasePart") then
		local kind = inst:GetAttribute("FX")
		local make = kind and KINDS[kind]
		if make then
			safely(make, inst)
		elseif inst:GetAttribute("NeonFlicker") == true then
			safely(neonFlicker, inst)
		-- (pendant lamps no longer get a volumetric cone under the bulb: it read as unnatural;
		-- they rely on their halo glow and real light. _lampCone is kept but unused.)
		elseif inst.Name == "UnderGlow" then
			local pad = inst.Parent
			if pad and pad.Parent and pad.Parent.Name == "Pads" and not bySource[pad] then
				safely(doorGlow, pad, inst)
			end
		end
	end
end

-- Anchors are keyed by themselves, lamps and doors by their model; either one leaving tears it down.
local function sourceGone(inst: Instance)
	if bySource[inst] then
		FX.remove(inst)
	elseif (inst.Name == "Core" or inst.Name == "UnderGlow") and inst.Parent and bySource[inst.Parent] then
		FX.remove(inst.Parent)
	end
end

-- Scan `root` now and keep watching it. Returns the connections.
function FX.watch(root: Instance): { RBXScriptConnection }
	for _, d in root:GetDescendants() do
		FX.consider(d)
	end
	return {
		root.DescendantAdded:Connect(function(d)
			-- attributes may be set right after parenting; look once this frame settles
			task.defer(FX.consider, d)
		end),
		root.DescendantRemoving:Connect(sourceGone),
	}
end

function FX.setQuality(q: number)
	FX.quality = q
	for _, e in effects do
		applyActive(e, e.active)
	end
end

local cullTimer = 0
-- Advance everything by dt; `camPos` drives culling.
function FX.step(dt: number, t: number, camPos: Vector3)
	cullTimer -= dt
	if cullTimer <= 0 then
		cullTimer = 0.25
		for _, e in effects do
			local on = boxDistance(e.cf, e.size, camPos) < e.cull
			if on ~= e.active then
				applyActive(e, on)
			end
		end
	end
	for _, e in effects do
		if e.active and e.update then
			e.update(e, t, dt)
		end
	end
end

function FX.clear()
	for i = #effects, 1, -1 do
		FX.remove(effects[i].source)
	end
end

FX.effects = effects

-- BOOT (tests cut the script here) -------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "AtmosFX"
fxFolder.Parent = workspace
FX.parent = fxFolder
FX.rayParams.FilterDescendantsInstances = { fxFolder }

gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	FX.setQuality(readQuality())
end)

local function watchLobby(lobby: Instance)
	local conns = FX.watch(lobby)
	lobby.AncestryChanged:Connect(function()
		if not lobby:IsDescendantOf(workspace) then
			for _, c in conns do
				c:Disconnect()
			end
			FX.clear()
		end
	end)
end
watchLobby(workspace:WaitForChild("Lobby"))
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Lobby" then
		watchLobby(child)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if camera then
		FX.step(dt, os.clock(), camera.CFrame.Position)
	end
end)
