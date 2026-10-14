--[[
	TrialKit: the part / light / lettering helpers every trial builder uses (the door room in
	TrialBuilder and each world in Worlds/<Module>.luau). Lifted out of TrialBuilder so worlds can be
	built anywhere: the trial place can't require the lobby's Kit (it needs the lobby's ServerStorage).

	  local kit = TrialKit.at(origin)   -- every position below is relative to `origin` (a Vector3)
	  kit.box(parent, name, size, cf | Vector3, color, material?, extraProps?) -> Part
	  kit.cylinder(parent, name, length, diameter, cf | Vector3, axis "x"|"y"|"z", color, material?, extra?)
	  kit.model(parent, name) -> Model
	  kit.marker(parent, name, cf) -> invisible 1x1x1 part (Arrive / End / step targets: the CFrame is
	      where a character's pivot goes, 3 studs up, facing LookVector)
	  kit.stencil(parent, name, cf, width, height, text, { color?, runs?, glow? }) -> sprayed lettering
	  kit.hangingBulb(parent, pos, ceilingY, range, brightness, flicker) -> core part (holds the light)
	  kit.cagedLight(parent, pos, out, range, brightness, dead) -> Model
	  kit.flicker(light, kind?, rate?)   kind true = blinks, "furnace" = breathes (DoorRoomFlow's loop,
	      found by the CollectionService tag "Flicker"; worlds built later are picked up too)
	  kit.chest(parent, cf, lockId, reward) -> Model, lockPart (a Lockable chest: ItemService's lockpicks)
	  kit.figure(parent, cf, name?) -> Model: a tall black humanoid tagged "Entity" for Stalker.start
	  kit.followDoor(parent, cf) -> Model: the FOLLOW THEM IN door (lounges; WorldHost wires its prompt)
	  kit.exitDoor(parent, cf, text?) -> Model "Exit" with Slab.ProximityPrompt (WorldHost wires it)
	  kit.guideNode(folder, name, pos, links) -> invisible node part (attribute Links = "a,b,c")
	  kit.pickup(parent, name, pos) -> a small floating key (Lounge.luau pays and hides it per player)
	  kit.prompt(part, action, object?, hold?) -> ProximityPrompt (MaxActivationDistance 9, no line of sight)

	Module-level (no origin needed): TrialKit.C (palette), DETAIL / INVISIBLE / BLOCKER (prop tables),
	PAINT / PAINT_DARK, pointLight, halo, surfaceGui, frame, round, rngFor, sprayText.
]]
local CollectionService = game:GetService("CollectionService")
local TextService = game:GetService("TextService")

local TrialKit = {}

------------------------------------------------------------------------------------------
-- Palette and prop tables
------------------------------------------------------------------------------------------
local C = {
	-- door room: a faded, nicotine-yellow antechamber
	wallpaper = Color3.fromRGB(164, 150, 114),
	wallpaperStripe = Color3.fromRGB(150, 136, 102),
	plaster = Color3.fromRGB(148, 144, 130),
	stain = Color3.fromRGB(118, 108, 90),
	carpet = Color3.fromRGB(92, 74, 56),
	carpetWorn = Color3.fromRGB(80, 64, 48),
	wood = Color3.fromRGB(74, 52, 36),
	darkWood = Color3.fromRGB(46, 32, 22),
	doorPaint = Color3.fromRGB(196, 186, 168),
	brass = Color3.fromRGB(150, 112, 56),
	void = Color3.fromRGB(6, 6, 8),
	-- safe room: warm and lived in
	warmPaper = Color3.fromRGB(172, 138, 104),
	planks = Color3.fromRGB(96, 66, 42),
	rug = Color3.fromRGB(128, 44, 38),
	rugTrim = Color3.fromRGB(170, 132, 78),
	chair = Color3.fromRGB(110, 52, 42),
	chairLight = Color3.fromRGB(128, 64, 52),
	brick = Color3.fromRGB(112, 72, 58),
	slate = Color3.fromRGB(80, 76, 70),
	ember = Color3.fromRGB(255, 110, 30),
	steel = Color3.fromRGB(40, 42, 48),
	-- threat corridor: cold, grey, forgotten
	concrete = Color3.fromRGB(54, 52, 50),
	block = Color3.fromRGB(74, 76, 82),
	grime = Color3.fromRGB(44, 44, 46),
	ceiling = Color3.fromRGB(44, 46, 50),
	pipe = Color3.fromRGB(110, 70, 50),
	duct = Color3.fromRGB(60, 62, 66),
	paper = Color3.fromRGB(200, 190, 160),
	-- light
	warm = Color3.fromRGB(255, 190, 122),
	bulb = Color3.fromRGB(255, 172, 100),
	cold = Color3.fromRGB(150, 170, 210),
	fire = Color3.fromRGB(255, 150, 70),
	cage = Color3.fromRGB(255, 196, 140),
	glow = Color3.fromRGB(255, 128, 48), -- deep amber; Neon renders much paler than its colour
}

local DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local INVISIBLE = { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local BLOCKER = { Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false }

local PAINT = Color3.fromRGB(196, 34, 28) -- the lobby's spray red
local PAINT_DARK = Color3.fromRGB(72, 14, 12) -- the misregistered first coat / dried runs
local SPRAY_FONT = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)

-- Cylinder axes: a Part cylinder runs along its X, so turn it onto the axis asked for.
local AXIS = {
	x = CFrame.new(),
	y = CFrame.Angles(0, 0, math.rad(90)),
	z = CFrame.Angles(0, math.rad(90), 0),
}

------------------------------------------------------------------------------------------
-- Lights and GUI helpers (no position: these attach to parts that already exist)
------------------------------------------------------------------------------------------
local function pointLight(parent: Instance, range: number, brightness: number, shadows: boolean, color: Color3?)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows
	light.Color = color or C.warm
	light.Parent = parent
	return light
end

-- Soft glow sprite around a light so you see a warm bloom, not the bulb (same recipe as the lobby).
local function halo(part: BasePart, studs: number, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Halo"
	gui.Size = UDim2.fromScale(studs, studs)
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 120
	gui.Parent = part
	for i, spec in { { 1, 0.95 }, { 0.78, 0.92 }, { 0.58, 0.88 }, { 0.4, 0.8 }, { 0.24, 0.62 }, { 0.12, 0.35 } } do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(spec[1], spec[1])
		ring.BackgroundColor3 = (color or Color3.fromRGB(255, 176, 104)):Lerp(
			Color3.fromRGB(255, 236, 200),
			(i - 1) / 6
		)
		ring.BackgroundTransparency = spec[2]
		ring.BorderSizePixel = 0
		ring.ZIndex = i
		ring.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ring
	end
	return gui
end

local function surfaceGui(part: BasePart, pps: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.7
	gui.Brightness = 0.55 -- wet paint holds a little light; keeps it readable in the dark
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = part
	return gui
end

local function frame(
	parent: Instance,
	name: string,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	transparency: number?,
	z: number?
)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

-- Mark a light for DoorRoomFlow's flicker loop: true = blinks (its core part and Halo go dark with it),
-- "furnace" = breathes. `rate` = chance per 0.12 s tick to blink.
local function flicker(light: Light, kind: any?, rate: number?)
	light:SetAttribute("Flicker", if kind == nil then true else kind)
	if rate then
		light:SetAttribute("FlickerRate", rate)
	end
	CollectionService:AddTag(light, "Flicker")
end

------------------------------------------------------------------------------------------
-- Spray-stencil lettering (a compact cousin of the lobby's Signage.stencil)
------------------------------------------------------------------------------------------
-- Deterministic per-sign randomness, so rebuilds look the same and each sign is still different.
local function rngFor(str: string, cf: CFrame): Random
	local seed = 0
	for i = 1, #str do
		seed = (seed * 31 + string.byte(str, i)) % 2147483647
	end
	local p = cf.Position
	return Random.new(seed + math.floor(p.X * 7 + p.Y * 13 + p.Z * 17))
end

-- Pixel width of `str` at `size` (falls back to an estimate if the text service isn't available).
local function measure(str: string, size: number): number
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = str
		params.Font = SPRAY_FONT
		params.Size = size
		params.Width = 100000
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and bounds then
		return bounds.X
	end
	return #str * size * 0.5
end

local function sprayLabel(gui: Instance, name: string, str: string, color: Color3, z: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = SPRAY_FONT
	label.Text = str
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = z
	label.Parent = gui
	return label
end

-- Transparency along the lettering: patchy paint density cut by the thin bridges a stencil needs to
-- hold the middles of its letters in place (NumberSequence allows 20 keypoints at most).
local function patchy(rng: Random): NumberSequence
	local keys = { NumberSequenceKeypoint.new(0, rng:NextNumber(0.05, 0.15)) }
	local t = 0
	while t < 0.84 and #keys < 15 do
		t += rng:NextNumber(0.09, 0.2)
		if t >= 0.93 then
			break
		end
		if rng:NextNumber() < 0.3 then
			table.insert(keys, NumberSequenceKeypoint.new(t, rng:NextNumber(0, 0.1)))
			table.insert(keys, NumberSequenceKeypoint.new(t + 0.004, 0.9))
			table.insert(keys, NumberSequenceKeypoint.new(t + 0.012, 0.9))
			table.insert(keys, NumberSequenceKeypoint.new(t + 0.016, rng:NextNumber(0, 0.1)))
			t += 0.02
		else
			table.insert(keys, NumberSequenceKeypoint.new(t, rng:NextNumber(0, 0.22)))
		end
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, rng:NextNumber(0.05, 0.15)))
	return NumberSequence.new(keys)
end

-- The paint layers of one line of sprayed text at pos/size (pixels; `px` is the box height):
-- two rings of faint copies (overspray mist), a darker misregistered under-coat, the main coat.
local function sprayText(gui: Instance, str: string, color: Color3, pos: UDim2, size: UDim2, px: number, rng: Random)
	local function layer(name: string, z: number, col: Color3, transparency: number, dx: number, dy: number)
		local l = sprayLabel(gui, name, str, col, z)
		l.Position = pos + UDim2.fromOffset(dx, dy)
		l.Size = size
		l.TextTransparency = transparency
		return l
	end
	for ring, spec in { { 0.035, 0.86 }, { 0.075, 0.93 } } do
		local r = math.max(2, px * spec[1])
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + ring * 0.4
			layer("Mist", 1, color, spec[2], math.cos(a) * r, math.sin(a) * r)
		end
	end
	local under = layer("Under", 2, PAINT_DARK, 0.15, math.max(1, px * 0.03), math.max(1, px * 0.035))
	under.Rotation = rng:NextNumber(-0.8, 0.8)
	local underCut = Instance.new("UIGradient")
	underCut.Transparency = patchy(rng)
	underCut.Parent = under

	local main = layer("Label", 3, color, 0, 0, 0)
	local paint = Instance.new("UIGradient")
	paint.Transparency = patchy(rng)
	-- lighter where the can passed closest, deeper at the ends of each stroke (multiplies the colour)
	paint.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.78, 0.74, 0.74)),
		ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.7, Color3.new(0.93, 0.9, 0.9)),
		ColorSequenceKeypoint.new(1, Color3.new(0.74, 0.7, 0.7)),
	})
	paint.Parent = main
	return main
end

-- Runs of paint hanging under the lettering, a bead at the end of each.
local function runs(
	gui: Instance,
	x0: number,
	x1: number,
	baseY: number,
	maxLen: number,
	color: Color3,
	rng: Random,
	count: number
)
	for _ = 1, count do
		local x = rng:NextNumber(x0, x1)
		local w = rng:NextNumber(2.5, 5)
		local len = maxLen * rng:NextNumber(0.2, 1) ^ 1.5
		local run = frame(gui, "Run", UDim2.fromOffset(x - w / 2, baseY - 6), UDim2.fromOffset(w, len + 6), color, 0, 2)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.6, 0.55, 0.55))
		fade.Parent = run
		round(run, UDim.new(0.5, 0))
		local bead = frame(
			gui,
			"Bead",
			UDim2.fromOffset(x - w * 0.95, baseY + len - w * 1.4),
			UDim2.fromOffset(w * 1.9, w * 2.3),
			color:Lerp(PAINT_DARK, 0.45),
			0,
			2
		)
		round(bead, UDim.new(1, 0))
	end
end

local function splatter(gui: Instance, w: number, h: number, color: Color3, rng: Random, count: number, avoid: Rect)
	for _ = 1, count do
		local x, y = rng:NextNumber(0, w), rng:NextNumber(0, h)
		if x > avoid.Min.X and x < avoid.Max.X and y > avoid.Min.Y and y < avoid.Max.Y then
			continue
		end
		local d = rng:NextNumber(1.5, 4.5)
		local dot =
			frame(gui, "Speck", UDim2.fromOffset(x, y), UDim2.fromOffset(d, d), color, rng:NextNumber(0.05, 0.5), 1)
		round(dot, UDim.new(1, 0))
	end
end

------------------------------------------------------------------------------------------
-- A kit at an origin: every helper that places a part adds `origin`
------------------------------------------------------------------------------------------
function TrialKit.at(origin: Vector3)
	local kit = {}
	local function place(cf): CFrame
		if typeof(cf) == "CFrame" then
			return cf + origin
		end
		return CFrame.new(cf + origin)
	end

	local function box(
		parent: Instance,
		name: string,
		size: Vector3,
		cf,
		color: Color3,
		material: Enum.Material?,
		extra
	)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = place(cf)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		for key, value in extra or {} do
			part[key] = value
		end
		part.Parent = parent
		return part
	end

	local function cylinder(
		parent: Instance,
		name: string,
		length: number,
		diameter: number,
		cf,
		axis: string,
		color: Color3,
		material: Enum.Material?,
		extra
	)
		local base = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
		local part =
			box(parent, name, Vector3.new(length, diameter, diameter), base * AXIS[axis], color, material, extra)
		part.Shape = Enum.PartType.Cylinder
		return part
	end

	local function model(parent: Instance, name: string): Model
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = parent
		return m
	end

	-- Sprayed lettering centred on `cf` (width x height studs of lettering, LookVector pointing out of the
	-- wall into the room), with mist, runs hanging below and splatter around it. Returns the carrier part.
	local function stencil(
		parent: Instance,
		name: string,
		cf: CFrame,
		width: number,
		height: number,
		str: string,
		opts: StencilOpts?
	)
		local o: StencilOpts = opts or {}
		local color = o.color or PAINT
		local rng = rngFor(str, cf)
		local pps = math.clamp(math.floor(110 / height), 20, 100)
		local margin = height * 0.18
		local drop = height * 1.2
		local tilt = cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-1.2, 1.2)))
		local carrier = box(
			parent,
			name,
			Vector3.new(width + margin * 2, height + margin * 2 + drop, 0.02),
			tilt * CFrame.new(0, -drop / 2, -0.02),
			C.void,
			nil,
			INVISIBLE
		)
		local gui = surfaceGui(carrier, pps)
		local m = margin * pps
		local w, h = width * pps, height * pps
		local W, H = (width + margin * 2) * pps, (height + margin * 2 + drop) * pps

		-- the ink extent TextScaled will land on, for the runs and the splatter-free zone
		local wAt100 = math.max(1, measure(str, 100))
		local size = math.min(100, math.floor(math.min(w / wAt100 * 100, h / 1.05)))
		local inkW = wAt100 * size / 100
		local inkL = m + (w - inkW) / 2

		sprayText(gui, str, color, UDim2.fromOffset(m, m), UDim2.fromOffset(w, h), h, rng)
		local baseY = m + h / 2 + size * 0.36
		runs(
			gui,
			inkL,
			inkL + inkW,
			baseY,
			drop * pps * 0.85,
			color:Lerp(PAINT_DARK, 0.15),
			rng,
			o.runs or math.floor(#str * 0.8)
		)
		splatter(gui, W, H - drop * pps, color, rng, math.floor(width * 4), Rect.new(inkL, m, inkL + inkW, m + h))

		if o.glow ~= false then
			local glow = pointLight(carrier, math.max(8, width * 0.8), 0.22, false, Color3.fromRGB(255, 50, 40))
			glow.Name = "Glow"
		end
		return carrier
	end

	-- Bare bulb in a frosted globe on a cord from the ceiling. Returns the glowing core (holds the light).
	local function hangingBulb(
		parent: Instance,
		pos: Vector3,
		ceilingY: number,
		range: number,
		brightness: number,
		blinks: boolean
	)
		local lamp = model(parent, "Lamp")
		local vertical = CFrame.Angles(0, 0, math.rad(90))
		local brass = Color3.fromRGB(140, 104, 56)
		local fittingY = pos.Y + 0.85
		local noCollide = { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false }
		box(
			lamp,
			"Rose",
			Vector3.new(0.2, 0.8, 0.8),
			CFrame.new(pos.X, ceilingY - 0.1, pos.Z) * vertical,
			brass,
			Enum.Material.Metal,
			noCollide
		)
		box(
			lamp,
			"Cord",
			Vector3.new(0.07, ceilingY - fittingY, 0.07),
			Vector3.new(pos.X, (ceilingY + fittingY) / 2, pos.Z),
			Color3.fromRGB(30, 24, 20),
			Enum.Material.Fabric,
			DETAIL
		)
		box(
			lamp,
			"Fitting",
			Vector3.new(0.4, 0.34, 0.34),
			CFrame.new(pos.X, fittingY, pos.Z) * vertical,
			brass,
			Enum.Material.Metal,
			noCollide
		)
		local core = box(lamp, "Core", Vector3.new(0.5, 0.5, 0.5), pos, C.glow, Enum.Material.Neon, DETAIL)
		core.Shape = Enum.PartType.Ball
		core.Transparency = 0.35
		halo(core, 3.6)
		box(lamp, "Globe", Vector3.new(1.3, 1.3, 1.3), pos, Color3.fromRGB(255, 224, 182), Enum.Material.Glass, {
			Shape = Enum.PartType.Ball,
			Transparency = 0.22,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		box(
			lamp,
			"GlobeCollar",
			Vector3.new(0.18, 0.6, 0.6),
			CFrame.new(pos + Vector3.new(0, 0.66, 0)) * vertical,
			brass,
			Enum.Material.Metal,
			noCollide
		)
		local light = pointLight(core, range, brightness, true)
		if blinks then
			flicker(light, true, 0.012) -- a blink every ten seconds or so, not a strobe
		end
		return core
	end

	-- Wall-mounted caged work light. `pos` is on the wall, `out` the unit direction into the room.
	-- Dead ones keep the cage but no bulb light: gaps of darkness between the pools.
	local function cagedLight(
		parent: Instance,
		pos: Vector3,
		out: Vector3,
		range: number,
		brightness: number,
		dead: boolean
	)
		local lamp = model(parent, "CagedLight")
		local cf = CFrame.lookAt(pos, pos - out) -- LookVector = -out, so +Z of the part points into the room
		box(lamp, "Mount", Vector3.new(0.6, 0.6, 0.3), cf, C.duct, Enum.Material.Metal, DETAIL)
		local bulb = box(
			lamp,
			"Bulb",
			Vector3.new(0.5, 0.5, 0.5),
			cf * CFrame.new(0, 0, 0.5),
			dead and Color3.fromRGB(70, 64, 58) or C.bulb,
			dead and Enum.Material.Glass or Enum.Material.Neon,
			DETAIL
		)
		bulb.Shape = Enum.PartType.Ball
		bulb.Transparency = 0.35
		for _, a in { 0, 90 } do
			box(
				lamp,
				"Cage",
				Vector3.new(0.08, 0.8, 0.8),
				cf * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, 0, math.rad(a)),
				Color3.fromRGB(30, 30, 30),
				Enum.Material.Metal,
				DETAIL
			)
		end
		if not dead then
			halo(bulb, 2.4)
			flicker(pointLight(bulb, range, brightness, false, C.cage))
		end
		return lamp
	end

	local function followDoor(parent: Instance, cf: CFrame)
		-- cf: centre of the door on the wall's inner face at floor level, LookVector into the room
		local door = model(parent, "FollowDoor")
		local w, h = 6, 8
		for _, s in { -1, 1 } do
			box(
				door,
				"Jamb",
				Vector3.new(0.8, h + 0.4, 0.8),
				cf * CFrame.new(s * (w / 2 + 0.4), (h + 0.4) / 2, -0.1),
				C.steel,
				Enum.Material.Metal
			)
		end
		box(
			door,
			"Header",
			Vector3.new(w + 1.6, 0.8, 0.8),
			cf * CFrame.new(0, h + 0.8, -0.1),
			C.steel,
			Enum.Material.Metal
		)
		local slab = box(
			door,
			"Slab",
			Vector3.new(w, h, 0.4),
			cf * CFrame.new(0, h / 2, -0.1),
			Color3.fromRGB(30, 32, 36),
			Enum.Material.DiamondPlate
		)
		for _, y in { 2.2, 5.8 } do
			box(
				door,
				"Band",
				Vector3.new(w - 0.4, 0.5, 0.1),
				cf * CFrame.new(0, y, -0.35),
				C.steel,
				Enum.Material.Metal,
				DETAIL
			)
		end
		box(door, "Knob", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(2.3, 3, -0.5), C.brass, Enum.Material.Metal, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		stencil(door, "Lettering", cf * CFrame.new(0, 4.6, -0.31), 5.2, 1.2, "FOLLOW THEM IN", { runs = 5 })
		local coldLight = box(
			door,
			"ColdLight",
			Vector3.new(0.4, 0.2, 0.4),
			cf * CFrame.new(0, h + 1.5, -1),
			C.cold,
			Enum.Material.Neon,
			DETAIL
		)
		pointLight(coldLight, 11, 0.55, false, C.cold)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "The other door"
		prompt.ActionText = "FOLLOW THEM IN"
		prompt.HoldDuration = 1 -- a deliberate choice, not a bump
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Panel", "FollowIn")
		prompt.Parent = slab
		return door
	end

	-- A locked chest the lockpicks can open (contract in BRIEF_BATCH2: Lockable + LockId/Reward,
	-- Lid with a Hinge CFrame, Lock part hosting the prompt). `cf` is the chest's base centre.
	local function chest(parent: Instance, cf: CFrame, lockId: string, reward: number)
		local c = model(parent, "Chest")
		local w, h, d = 2.6, 1.3, 1.6
		local body = box(c, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), C.darkWood, Enum.Material.Wood)
		for _, s in { -1, 1 } do
			box(
				c,
				"Band",
				Vector3.new(0.12, h + 0.04, d + 0.08),
				cf * CFrame.new(s * 0.8, h / 2, 0),
				C.duct,
				Enum.Material.Metal,
				DETAIL
			)
		end
		local lid = box(
			c,
			"Lid",
			Vector3.new(w + 0.1, 0.4, d + 0.1),
			cf * CFrame.new(0, h + 0.2, 0),
			C.wood,
			Enum.Material.Wood
		)
		-- hinge along the lid's back edge (its +Z side), world space so the server can swing it open
		lid:SetAttribute("Hinge", lid.CFrame * CFrame.new(0, -0.2, d / 2))
		local lock = box(
			c,
			"Lock",
			Vector3.new(0.5, 0.5, 0.2),
			cf * CFrame.new(0, h - 0.1, -d / 2 - 0.1),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		c.PrimaryPart = body
		c:SetAttribute("LockId", lockId)
		c:SetAttribute("Reward", reward)
		CollectionService:AddTag(c, "Lockable")
		return c, lock
	end

	-- A tall black figure with two points of light for eyes. Built from parts welded to a
	-- HumanoidRootPart so Humanoid:MoveTo drives it; R15 rig type so HipHeight is honoured.
	local function figure(parent: Instance, cf: CFrame, entityName: string?)
		local stalker = model(parent, "Stalker")
		local skin = Color3.fromRGB(12, 10, 12)
		local fabric = Enum.Material.Fabric
		local root = box(stalker, "HumanoidRootPart", Vector3.new(2, 2, 1), cf * CFrame.new(0, 5, 0), skin, nil, {
			Transparency = 1,
			CastShadow = false,
		})
		local limb = { CanCollide = false, CanQuery = true, CanTouch = true, Massless = true }
		local function part(name: string, size: Vector3, offset: CFrame, extra)
			local p = box(stalker, name, size, cf * offset, skin, fabric, limb)
			for key, value in extra or {} do
				p[key] = value
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			return p
		end
		part("LowerTorso", Vector3.new(2.4, 1.4, 1.2), CFrame.new(0, 4.3, 0))
		part("UpperTorso", Vector3.new(2.6, 3, 1.4), CFrame.new(0, 6.2, 0))
		local head = part("Head", Vector3.new(1.4, 1.9, 1.4), CFrame.new(0, 8.7, 0))
		head.Shape = Enum.PartType.Block
		for _, s in { -1, 1 } do
			part(
				s < 0 and "LeftArm" or "RightArm",
				Vector3.new(0.7, 4.4, 0.7),
				CFrame.new(s * 1.65, 5.6, 0),
				{ CastShadow = false }
			)
			part(
				s < 0 and "LeftLeg" or "RightLeg",
				Vector3.new(0.9, 4, 0.9),
				CFrame.new(s * 0.6, 2, 0),
				{ CastShadow = false }
			)
			local eye =
				part(s < 0 and "EyeL" or "EyeR", Vector3.new(0.26, 0.12, 0.1), CFrame.new(s * 0.32, 8.95, -0.72), {
					Color = Color3.fromRGB(240, 246, 255),
					Material = Enum.Material.Neon,
					CastShadow = false,
				})
			local light = pointLight(eye, 7, 0.5, false, Color3.fromRGB(200, 220, 255))
			light.Name = "Light"
		end
		-- unanchored for the Humanoid; the server keeps it on the ground via HipHeight
		for _, p in stalker:GetChildren() do
			if p:IsA("BasePart") then
				p.Anchored = false
			end
		end

		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.HipHeight = 4 -- root bottom sits 4 studs up: the legs reach the floor
		humanoid.WalkSpeed = 11
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
		humanoid.AutoRotate = true
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
		humanoid.RequiresNeck = false -- welded head, no Neck joint: don't die for it
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
		humanoid.Parent = stalker

		stalker.PrimaryPart = root
		stalker:SetAttribute("EntityName", entityName or "The Follower")
		stalker:SetAttribute("Stunned", false)
		CollectionService:AddTag(stalker, "Entity")
		return stalker
	end

	-- An invisible 1x1x1 marker: Arrive / End / step targets (the CFrame is where a pivot goes).
	local function marker(parent: Instance, name: string, cf): BasePart
		return box(parent, name, Vector3.new(1, 1, 1), cf, Color3.new(1, 1, 1), nil, INVISIBLE)
	end

	-- A ProximityPrompt that works the way every trial prompt does: close, no line of sight needed.
	local function prompt(part: BasePart, action: string, object: string?, hold: number?): ProximityPrompt
		local p = Instance.new("ProximityPrompt")
		p.ActionText = action
		p.ObjectText = object or ""
		p.HoldDuration = hold or 0
		p.MaxActivationDistance = 9
		p.RequiresLineOfSight = false
		p.Parent = part
		return p
	end

	-- The way out of a world: a pale door with a glowing sign above it. WorldHost wires the prompt on
	-- Exit.Slab (danger worlds: only once the last objective step is done). cf: centre of the door on
	-- the wall's inner face at floor level, LookVector into the room.
	local function exitDoor(parent: Instance, cf: CFrame, text: string?): Model
		local door = model(parent, "Exit")
		local w, h = 5, 8
		for _, s in { -1, 1 } do
			box(
				door,
				"Jamb",
				Vector3.new(0.6, h + 0.3, 0.8),
				cf * CFrame.new(s * (w / 2 + 0.3), (h + 0.3) / 2, -0.1),
				C.darkWood,
				Enum.Material.Wood
			)
		end
		box(
			door,
			"Header",
			Vector3.new(w + 1.2, 0.6, 0.8),
			cf * CFrame.new(0, h + 0.6, -0.1),
			C.darkWood,
			Enum.Material.Wood
		)
		local slab = box(
			door,
			"Slab",
			Vector3.new(w, h, 0.3),
			cf * CFrame.new(0, h / 2, -0.1),
			Color3.fromRGB(210, 204, 190),
			Enum.Material.Wood
		)
		local sign = box(
			door,
			"Sign",
			Vector3.new(2.6, 0.7, 0.12),
			cf * CFrame.new(0, h + 1.5, -0.3),
			Color3.fromRGB(40, 220, 120),
			Enum.Material.Neon,
			DETAIL
		)
		pointLight(sign, 8, 0.6, false, Color3.fromRGB(60, 255, 140))
		local gui = surfaceGui(sign, 60)
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = text or "EXIT"
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(10, 40, 20)
		label.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
		label.Parent = gui
		prompt(slab, "Leave", text or "Exit", 0.6)
		return door
	end

	-- One node of a world's authored guide graph (the blue path's fallback when pathfinding fails).
	local function guideNode(folder: Instance, name: string, pos: Vector3, links: { string }): BasePart
		local node = marker(folder, name, pos)
		node:SetAttribute("Links", table.concat(links, ","))
		return node
	end

	-- A small brass key turning slowly in the air (Lounge.luau pays it out and hides it per player).
	local function pickup(parent: Instance, name: string, pos: Vector3): BasePart
		local key = box(parent, name, Vector3.new(0.3, 1.1, 0.12), pos, C.brass, Enum.Material.Metal, {
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		local bow = box(
			key,
			"Bow",
			Vector3.new(0.6, 0.6, 0.12),
			pos + Vector3.new(0, 0.7, 0),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		bow.Shape = Enum.PartType.Cylinder
		bow.CFrame *= CFrame.Angles(0, math.rad(90), 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = key
		weld.Part1 = bow
		weld.Parent = key
		pointLight(key, 6, 0.7, false, Color3.fromRGB(255, 210, 120))
		key:SetAttribute("Pickup", true)
		CollectionService:AddTag(key, "KeyPickup")
		return key
	end

	kit.origin = origin
	kit.place = place
	kit.box = box
	kit.cylinder = cylinder
	kit.model = model
	kit.marker = marker
	kit.prompt = prompt
	kit.stencil = stencil
	kit.hangingBulb = hangingBulb
	kit.cagedLight = cagedLight
	kit.followDoor = followDoor
	kit.chest = chest
	kit.figure = figure
	kit.exitDoor = exitDoor
	kit.guideNode = guideNode
	kit.pickup = pickup
	return setmetatable(kit, { __index = TrialKit })
end

TrialKit.C = C
TrialKit.DETAIL = DETAIL
TrialKit.INVISIBLE = INVISIBLE
TrialKit.BLOCKER = BLOCKER
TrialKit.PAINT = PAINT
TrialKit.PAINT_DARK = PAINT_DARK
TrialKit.pointLight = pointLight
TrialKit.halo = halo
TrialKit.surfaceGui = surfaceGui
TrialKit.frame = frame
TrialKit.round = round
TrialKit.rngFor = rngFor
TrialKit.sprayText = sprayText
TrialKit.flicker = flicker

return TrialKit
