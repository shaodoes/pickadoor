--[[
	TrialBuilder: the whole trial map, built from primitives under one Model named "Trial".

	Layout (local coordinates; `opts.offset` shifts everything, so the map can be previewed inside the
	lobby place far away from the library):
	  DoorRoom        40 x 44 x 15 around the origin. Two doors in the -Z wall (Doors.Left at x -8,
	                  Doors.Right at x +8, numerals I / II), each with a Zone the player stands in to
	                  pick it, a Leaf the server swings open (DoorRoomFlow) and a black void behind it.
	                  Spawn (SpawnLocation) at +Z. One hanging bulb; "PICK A DOOR" sprayed on the wall
	                  above the doors in the lobby's stencil style.
	  SafeRoom        at x +120: a warm sitting room (fireplace, lamp, armchairs, rug, bookshelf), the
	                  FOLLOW THEM IN door (ProximityPrompt with attribute Panel = "FollowIn") and an
	                  Arrive part where the server places the players who picked the right door.
	  ThreatCorridor  at x -120: 120 studs of dark corridor along Z with alcoves, flickering caged
	                  lights (Light attribute Flicker = true), doors that never open, a locked chest
	                  (Lockable, for the lockpicks), Arrive (+Z end), End (-Z end) and the Stalker: a
	                  tall black humanoid tagged "Entity" (attribute EntityName = "The Follower") that
	                  src/trial/server/Stalker.luau drives.

	Names / attributes other code relies on:
	  Trial.DoorRoom.Doors.<Left|Right>.Zone, .Leaf (attributes HingeX, SwingAngle) and every part
	    with attribute Swing = true (moved together with the leaf by DoorRoomFlow)
	  Trial.DoorRoom.Spawn (SpawnLocation)
	  Trial.SafeRoom.Arrive, Trial.SafeRoom.FollowDoor.Slab.ProximityPrompt (Panel = "FollowIn")
	  Trial.ThreatCorridor.Arrive / .End / .Stalker (Humanoid, HumanoidRootPart, UpperTorso, Head,
	    EyeL, EyeR with PointLights)
	  Lights with attribute Flicker: true = blinks, "furnace" = breathes (DoorRoomFlow runs the loop)
	  Arrive / End parts: the CFrame is where a character's pivot goes (3 studs up, facing LookVector).
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")

local TrialBuilder = {}

------------------------------------------------------------------------------------------
-- Palette and part helpers (the trial place can't require the lobby's Kit: separate place)
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

-- Set per build; every helper adds it, so the builders below work in local coordinates.
local OFFSET = Vector3.zero

local function place(cf): CFrame
	if typeof(cf) == "CFrame" then
		return cf + OFFSET
	end
	return CFrame.new(cf + OFFSET)
end

local function box(parent: Instance, name: string, size: Vector3, cf, color: Color3, material: Enum.Material?, extra)
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

-- Cylinder whose axis runs along `axis` ("x", "y" or "z") of `cf`.
local AXIS = {
	x = CFrame.new(),
	y = CFrame.Angles(0, 0, math.rad(90)),
	z = CFrame.Angles(0, math.rad(90), 0),
}
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
	local part = box(parent, name, Vector3.new(length, diameter, diameter), base * AXIS[axis], color, material, extra)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

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

type StencilOpts = { color: Color3?, runs: number?, glow: boolean? }

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

------------------------------------------------------------------------------------------
-- Lights
------------------------------------------------------------------------------------------
-- Bare bulb in a frosted globe on a cord from the ceiling. Returns the glowing core (holds the light).
local function hangingBulb(
	parent: Instance,
	pos: Vector3,
	ceilingY: number,
	range: number,
	brightness: number,
	flicker: boolean
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
	if flicker then
		light:SetAttribute("Flicker", true)
		light:SetAttribute("FlickerRate", 0.012) -- a blink every ten seconds or so, not a strobe
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
		local light = pointLight(bulb, range, brightness, false, C.cage)
		light:SetAttribute("Flicker", true)
	end
	return lamp
end

------------------------------------------------------------------------------------------
-- The Door Room
------------------------------------------------------------------------------------------
local ROOM_W, ROOM_D, ROOM_H = 40, 44, 15
local WALL_Z = -ROOM_D / 2 -- the doors' wall (centre of its 1-stud thickness)
local DOOR_W, DOOR_H = 6, 9 -- the leaf
local OPENING = 8 -- wall opening width (jambs fill the sides)

-- Painted wood panels and the sprayed numeral, drawn on the leaf so they swing with it.
local function leafFace(leaf: BasePart, numeral: string, rng: Random)
	local pps = 40
	local gui = surfaceGui(leaf, pps)
	gui.LightInfluence = 0.9
	gui.Brightness = 0.2
	local W, H = DOOR_W * pps, DOOR_H * pps
	for _, spec in { { 0.08, 0.36 }, { 0.5, 0.42 } } do
		local panel = frame(
			gui,
			"Panel",
			UDim2.fromOffset(W * 0.14, H * spec[1]),
			UDim2.fromOffset(W * 0.72, H * spec[2]),
			C.doorPaint,
			1,
			1
		)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(120, 108, 92)
		stroke.Thickness = 4
		stroke.Transparency = 0.25
		stroke.Parent = panel
		local inner = frame(
			panel,
			"Inner",
			UDim2.fromOffset(6, 6),
			UDim2.new(1, -12, 1, -12),
			Color3.fromRGB(176, 166, 148),
			0.5,
			1
		)
		round(inner, UDim.new(0, 3))
	end
	-- the door's number, sprayed through a stencil onto the upper panel
	sprayText(gui, numeral, PAINT, UDim2.fromOffset(W * 0.2, H * 0.1), UDim2.fromOffset(W * 0.6, H * 0.3), H * 0.3, rng)
	-- grime climbing from the floor
	local grime = frame(
		gui,
		"Grime",
		UDim2.fromOffset(0, H * 0.84),
		UDim2.fromOffset(W, H * 0.16),
		Color3.fromRGB(60, 50, 40),
		0.55,
		2
	)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(1, 0.1)
	fade.Parent = grime
end

-- One door in the -Z wall at `x`: jambs, header, a Leaf hinged on `hingeSide` (-1 = its -X edge,
-- +1 = its +X edge) that swings inward into a pitch-black void, and the Zone / Mat in front of it.
local function buildDoor(parent: Instance, name: string, x: number, numeral: string, hingeSide: number)
	local door = model(parent, name)
	local frameColor = Color3.fromRGB(64, 50, 38)
	for _, s in { -1, 1 } do
		box(
			door,
			"Jamb",
			Vector3.new(1, DOOR_H + 0.5, 1.2),
			Vector3.new(x + s * (DOOR_W / 2 + 0.5), (DOOR_H + 0.5) / 2, WALL_Z),
			frameColor,
			Enum.Material.Wood
		)
	end
	box(
		door,
		"Header",
		Vector3.new(OPENING + 1, 1, 1.2),
		Vector3.new(x, DOOR_H + 0.5 + 0.5, WALL_Z),
		frameColor,
		Enum.Material.Wood
	)
	-- rotated 180 degrees so the leaf's Front face (and its SurfaceGui) looks into the room (+Z)
	local leafCf = CFrame.new(x, DOOR_H / 2, WALL_Z) * CFrame.Angles(0, math.pi, 0)
	local leaf = box(door, "Leaf", Vector3.new(DOOR_W, DOOR_H, 0.4), leafCf, C.doorPaint, Enum.Material.Wood)
	-- hinge in the leaf's own frame (its +X is the world's -X after the half turn); swing inward (+Z world)
	leaf:SetAttribute("HingeX", -hingeSide * DOOR_W / 2)
	leaf:SetAttribute("SwingAngle", math.rad(-hingeSide * 95)) -- just past square: clears the void's side wall
	leaf:SetAttribute("Swing", true)
	leafFace(leaf, numeral, rngFor(numeral, leafCf))
	local knob = box(
		door,
		"Knob",
		Vector3.new(0.4, 0.4, 0.4),
		leafCf * CFrame.new(hingeSide * (DOOR_W / 2 - 0.6), -0.2, -0.35),
		C.brass,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
	)
	knob:SetAttribute("Swing", true)

	-- the void: a black box behind the opening, and a blocker so nobody walks in while it stands open
	local void = model(door, "Void")
	local vd, vw, vh = 10, OPENING, DOOR_H + 1
	local vz = WALL_Z - 0.5 - vd / 2
	box(void, "Floor", Vector3.new(vw + 2, 1, vd), Vector3.new(x, -0.5, vz), C.void)
	box(void, "Ceiling", Vector3.new(vw + 2, 1, vd), Vector3.new(x, vh + 0.5, vz), C.void)
	box(void, "Back", Vector3.new(vw + 2, vh + 2, 1), Vector3.new(x, vh / 2, WALL_Z - 0.5 - vd - 0.5), C.void)
	for _, s in { -1, 1 } do
		box(void, "Side", Vector3.new(1, vh + 2, vd), Vector3.new(x + s * (vw / 2 + 0.5), vh / 2, vz), C.void)
	end
	box(void, "Blocker", Vector3.new(OPENING, vh, 0.4), Vector3.new(x, vh / 2, WALL_Z - 0.8), C.void, nil, BLOCKER)

	box(door, "Zone", Vector3.new(12, 8, 12), Vector3.new(x, 4, WALL_Z + 7.5), Color3.new(1, 1, 1), nil, INVISIBLE)
	box(
		door,
		"Mat",
		Vector3.new(9, 0.1, 9),
		Vector3.new(x, 0.05, WALL_Z + 7.5),
		Color3.fromRGB(70, 52, 40),
		Enum.Material.Fabric,
		DETAIL
	)
	return door
end

local function buildDoorRoom(parent: Instance)
	local room = model(parent, "DoorRoom")
	local W, D, H = ROOM_W, ROOM_D, ROOM_H

	box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(0, -0.5, 0), C.carpet, Enum.Material.Carpet)
	-- worn track from the spawn to the doors
	box(
		room,
		"Worn",
		Vector3.new(14, 0.04, D - 8),
		Vector3.new(0, 0.02, -2),
		C.carpetWorn,
		Enum.Material.Carpet,
		DETAIL
	)
	box(room, "Ceiling", Vector3.new(W, 1, D), Vector3.new(0, H + 0.5, 0), C.plaster)
	box(room, "Stain", Vector3.new(9, 0.04, 7), Vector3.new(6, H - 0.02, -4), C.stain, nil, DETAIL)

	-- side walls and the +Z wall are whole; the -Z wall is built around the two openings
	for _, s in { -1, 1 } do
		box(
			room,
			"Wall",
			Vector3.new(1, H, D),
			Vector3.new(s * (W / 2 + 0.5), H / 2, 0),
			C.wallpaper,
			Enum.Material.Fabric
		)
	end
	box(room, "Wall", Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, D / 2 + 0.5), C.wallpaper, Enum.Material.Fabric)
	local doorX = { -8, 8 }
	local edges = {
		-W / 2 - 1,
		doorX[1] - OPENING / 2,
		doorX[1] + OPENING / 2,
		doorX[2] - OPENING / 2,
		doorX[2] + OPENING / 2,
		W / 2 + 1,
	}
	for i = 1, 5, 2 do
		local x0, x1 = edges[i], edges[i + 1]
		box(
			room,
			"Wall",
			Vector3.new(x1 - x0, H, 1),
			Vector3.new((x0 + x1) / 2, H / 2, WALL_Z),
			C.wallpaper,
			Enum.Material.Fabric
		)
	end
	for _, x in doorX do
		local top = DOOR_H + 1.5
		box(
			room,
			"Wall",
			Vector3.new(OPENING, H - top, 1),
			Vector3.new(x, (H + top) / 2, WALL_Z),
			C.wallpaper,
			Enum.Material.Fabric
		)
	end

	-- wallpaper: faded vertical stripes, a dark wainscot and a picture rail all round
	local stripes = model(room, "Wallpaper")
	for x = -W / 2 + 2, W / 2 - 2, 3 do
		if math.abs(x - doorX[1]) > OPENING / 2 + 0.6 and math.abs(x - doorX[2]) > OPENING / 2 + 0.6 then
			box(
				stripes,
				"Stripe",
				Vector3.new(0.9, H, 0.04),
				Vector3.new(x, H / 2, WALL_Z + 0.52),
				C.wallpaperStripe,
				Enum.Material.Fabric,
				DETAIL
			)
		end
		box(
			stripes,
			"Stripe",
			Vector3.new(0.9, H, 0.04),
			Vector3.new(x, H / 2, D / 2 - 0.02),
			C.wallpaperStripe,
			Enum.Material.Fabric,
			DETAIL
		)
	end
	for z = -D / 2 + 2, D / 2 - 2, 3 do
		for _, s in { -1, 1 } do
			box(
				stripes,
				"Stripe",
				Vector3.new(0.04, H, 0.9),
				Vector3.new(s * (W / 2 - 0.02), H / 2, z),
				C.wallpaperStripe,
				Enum.Material.Fabric,
				DETAIL
			)
		end
	end
	local trim = model(room, "Trim")
	local wainscotH, railY = 3, 3.1
	for _, s in { -1, 1 } do
		box(
			trim,
			"Wainscot",
			Vector3.new(0.12, wainscotH, D),
			Vector3.new(s * (W / 2 - 0.06), wainscotH / 2, 0),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			trim,
			"Rail",
			Vector3.new(0.2, 0.16, D),
			Vector3.new(s * (W / 2 - 0.1), railY, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			trim,
			"PictureRail",
			Vector3.new(0.14, 0.14, D),
			Vector3.new(s * (W / 2 - 0.07), H - 0.8, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	box(
		trim,
		"Wainscot",
		Vector3.new(W, wainscotH, 0.12),
		Vector3.new(0, wainscotH / 2, D / 2 - 0.06),
		C.wood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		trim,
		"Rail",
		Vector3.new(W, 0.16, 0.2),
		Vector3.new(0, railY, D / 2 - 0.1),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	for i = 1, 5, 2 do
		local x0, x1 = math.max(edges[i], -W / 2), math.min(edges[i + 1], W / 2)
		box(
			trim,
			"Wainscot",
			Vector3.new(x1 - x0, wainscotH, 0.12),
			Vector3.new((x0 + x1) / 2, wainscotH / 2, WALL_Z + 0.56),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			trim,
			"Rail",
			Vector3.new(x1 - x0, 0.16, 0.2),
			Vector3.new((x0 + x1) / 2, railY, WALL_Z + 0.6),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	box(
		trim,
		"PictureRail",
		Vector3.new(W, 0.14, 0.14),
		Vector3.new(0, H - 0.8, WALL_Z + 0.57),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)

	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = room
	buildDoor(doors, "Left", doorX[1], "I", -1)
	buildDoor(doors, "Right", doorX[2], "II", 1)

	-- the one bulb, hung low between the spawn and the doors so the doors are what you see
	hangingBulb(room, Vector3.new(0, 10.2, -6), H, 48, 1.5, true)

	-- PICK A DOOR, sprayed on the wall above the doors, facing the room (+Z)
	stencil(
		room,
		"Stencil",
		CFrame.new(0, 12.4, WALL_Z + 0.56) * CFrame.Angles(0, math.pi, 0),
		22,
		3,
		"PICK A DOOR",
		{ runs = 9 }
	)

	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "Spawn"
	spawnPoint.Anchored = true
	spawnPoint.Size = Vector3.new(10, 0.2, 6)
	spawnPoint.CFrame = place(CFrame.new(0, 0.1, D / 2 - 6))
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = room
	return room
end

------------------------------------------------------------------------------------------
-- The Safe Room
------------------------------------------------------------------------------------------
local SAFE_X = 120
local SAFE_W, SAFE_D, SAFE_H = 26, 22, 10

local function armchair(parent: Instance, cf: CFrame)
	local chair = model(parent, "Armchair")
	local fabric = Enum.Material.Fabric
	box(chair, "Seat", Vector3.new(3, 1.4, 3), cf * CFrame.new(0, 0.7, 0), C.chair, fabric)
	box(chair, "Cushion", Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 1.6, -0.1), C.chairLight, fabric, DETAIL)
	box(chair, "Back", Vector3.new(3, 3.2, 0.8), cf * CFrame.new(0, 2.4, 1.3), C.chair, fabric)
	for _, s in { -1, 1 } do
		box(chair, "Arm", Vector3.new(0.6, 2.1, 3), cf * CFrame.new(s * 1.5, 1.45, 0.1), C.chair, fabric)
	end
	return chair
end

local function bookshelf(parent: Instance, cf: CFrame, rng: Random)
	local shelf = model(parent, "Bookshelf")
	local w, h, d = 10, 8, 1.4
	local wood = Enum.Material.Wood
	box(shelf, "Back", Vector3.new(w, h, 0.2), cf * CFrame.new(0, h / 2, d / 2 - 0.1), C.darkWood, wood, DETAIL)
	for _, s in { -1, 1 } do
		box(shelf, "Side", Vector3.new(0.3, h, d), cf * CFrame.new(s * (w / 2 - 0.15), h / 2, 0), C.wood, wood)
	end
	box(shelf, "Top", Vector3.new(w, 0.3, d), cf * CFrame.new(0, h - 0.15, 0), C.wood, wood)
	local palette = {
		Color3.fromRGB(96, 30, 26),
		Color3.fromRGB(58, 40, 28),
		Color3.fromRGB(40, 54, 44),
		Color3.fromRGB(34, 40, 62),
		Color3.fromRGB(120, 84, 46),
		Color3.fromRGB(140, 118, 84),
		Color3.fromRGB(28, 26, 24),
	}
	for _, y in { 0.15, 2.15, 4.15, 6.15 } do
		box(shelf, "Shelf", Vector3.new(w - 0.6, 0.2, d - 0.2), cf * CFrame.new(0, y, 0), C.wood, wood)
		local x = -w / 2 + 0.5
		while x < w / 2 - 0.9 do
			local bw = rng:NextNumber(0.3, 0.7)
			local bh = rng:NextNumber(1.1, 1.7)
			box(
				shelf,
				"Book",
				Vector3.new(bw, bh, rng:NextNumber(0.8, 1.1)),
				cf * CFrame.new(x + bw / 2, y + 0.1 + bh / 2, rng:NextNumber(-0.05, 0.1)),
				palette[rng:NextInteger(1, #palette)],
				Enum.Material.SmoothPlastic,
				DETAIL
			)
			x += bw + rng:NextNumber(0, 0.08)
			if rng:NextNumber() < 0.12 then
				x += rng:NextNumber(0.4, 1) -- a gap where a book was taken
			end
		end
	end
	return shelf
end

local function fireplace(parent: Instance, cf: CFrame)
	-- cf: centre of the hearth on the wall's inner face, LookVector into the room
	local fp = model(parent, "Fireplace")
	for _, s in { -1, 1 } do
		box(fp, "Pillar", Vector3.new(1.2, 5, 1.2), cf * CFrame.new(s * 2.6, 2.5, -0.6), C.brick, Enum.Material.Brick)
	end
	box(fp, "Mantel", Vector3.new(7, 0.5, 1.6), cf * CFrame.new(0, 5.25, -0.8), C.darkWood, Enum.Material.Wood)
	box(fp, "Lintel", Vector3.new(6.4, 1, 1), cf * CFrame.new(0, 4.5, -0.5), C.brick, Enum.Material.Brick)
	box(fp, "Firebox", Vector3.new(4, 4, 0.3), cf * CFrame.new(0, 2, -0.16), Color3.fromRGB(12, 10, 10), nil, DETAIL)
	box(fp, "Hearth", Vector3.new(7, 0.2, 2.8), cf * CFrame.new(0, 0.1, -1.2), C.slate, Enum.Material.Slate)
	for _, s in { -0.35, 0.35 } do
		cylinder(fp, "Log", 2.4, 0.6, cf * CFrame.new(0, 0.5, -0.4 + s), "x", C.darkWood, Enum.Material.Wood, DETAIL)
	end
	for i = 1, 4 do
		local ember = box(
			fp,
			"Ember",
			Vector3.new(0.5, 0.4, 0.5),
			cf * CFrame.new(-1 + i * 0.5, 0.25, -0.1 + (i % 2) * 0.3),
			C.ember,
			Enum.Material.Neon,
			DETAIL
		)
		ember.Transparency = 0.2
	end
	local flame = box(fp, "Flame", Vector3.new(2.6, 0.2, 1.2), cf * CFrame.new(0, 0.8, -0.3), C.ember, nil, INVISIBLE)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 60)
	fire.SecondaryColor = Color3.fromRGB(140, 40, 20)
	fire.Parent = flame
	local light = pointLight(flame, 26, 1.5, true, C.fire)
	light:SetAttribute("Flicker", "furnace")
	-- a dim painting over the mantel
	box(fp, "Frame", Vector3.new(2.6, 2, 0.12), cf * CFrame.new(0, 7.2, -0.08), C.darkWood, Enum.Material.Wood, DETAIL)
	box(
		fp,
		"Canvas",
		Vector3.new(2.2, 1.6, 0.06),
		cf * CFrame.new(0, 7.2, -0.16),
		Color3.fromRGB(70, 74, 60),
		Enum.Material.Fabric,
		DETAIL
	)
	return fp
end

local function floorLamp(parent: Instance, pos: Vector3)
	local lamp = model(parent, "FloorLamp")
	cylinder(lamp, "Base", 0.15, 1.4, pos + Vector3.new(0, 0.075, 0), "y", C.darkWood, Enum.Material.Metal, DETAIL)
	box(lamp, "Pole", Vector3.new(0.16, 5.3, 0.16), pos + Vector3.new(0, 2.8, 0), C.brass, Enum.Material.Metal, DETAIL)
	cylinder(
		lamp,
		"Shade",
		1.6,
		2.3,
		pos + Vector3.new(0, 5.9, 0),
		"y",
		Color3.fromRGB(236, 206, 156),
		Enum.Material.Fabric,
		{
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	local core = cylinder(
		lamp,
		"Core",
		1.3,
		1.7,
		pos + Vector3.new(0, 5.9, 0),
		"y",
		Color3.fromRGB(255, 200, 130),
		Enum.Material.Neon,
		DETAIL
	)
	core.Transparency = 0.35
	halo(core, 3.2)
	pointLight(core, 30, 1.2, true, C.warm)
	return lamp
end

-- The FOLLOW THEM IN door: dark steel, cold light above it, the words sprayed across it.
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
	box(door, "Header", Vector3.new(w + 1.6, 0.8, 0.8), cf * CFrame.new(0, h + 0.8, -0.1), C.steel, Enum.Material.Metal)
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

local function buildSafeRoom(parent: Instance)
	local room = model(parent, "SafeRoom")
	local rng = Random.new(2024)
	local X, W, D, H = SAFE_X, SAFE_W, SAFE_D, SAFE_H
	box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(X, -0.5, 0), C.planks, Enum.Material.WoodPlanks)
	box(room, "Ceiling", Vector3.new(W, 1, D), Vector3.new(X, H + 0.5, 0), Color3.fromRGB(140, 128, 110))
	for _, s in { -1, 1 } do
		box(
			room,
			"Wall",
			Vector3.new(1, H, D + 2),
			Vector3.new(X + s * (W / 2 + 0.5), H / 2, 0),
			C.warmPaper,
			Enum.Material.Fabric
		)
		box(
			room,
			"Wall",
			Vector3.new(W, H, 1),
			Vector3.new(X, H / 2, s * (D / 2 + 0.5)),
			C.warmPaper,
			Enum.Material.Fabric
		)
		-- wainscot and rail
		box(
			room,
			"Wainscot",
			Vector3.new(0.12, 3, D),
			Vector3.new(X + s * (W / 2 - 0.06), 1.5, 0),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			room,
			"Wainscot",
			Vector3.new(W, 3, 0.12),
			Vector3.new(X, 1.5, s * (D / 2 - 0.06)),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			room,
			"Rail",
			Vector3.new(0.2, 0.16, D),
			Vector3.new(X + s * (W / 2 - 0.1), 3.1, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			room,
			"Rail",
			Vector3.new(W, 0.16, 0.2),
			Vector3.new(X, 3.1, s * (D / 2 - 0.1)),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end

	-- rug with a border, in front of the fire
	box(room, "Rug", Vector3.new(12, 0.08, 9), Vector3.new(X - 4, 0.04, 0), C.rug, Enum.Material.Fabric, DETAIL)
	box(room, "RugTrim", Vector3.new(11, 0.02, 8), Vector3.new(X - 4, 0.09, 0), C.rugTrim, Enum.Material.Fabric, DETAIL)
	box(room, "RugField", Vector3.new(10, 0.02, 7), Vector3.new(X - 4, 0.1, 0), C.rug, Enum.Material.Fabric, DETAIL)

	-- the fire on the -X wall; chairs face it
	fireplace(room, CFrame.new(X - W / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	for _, z in { -4.2, 4.2 } do
		armchair(room, CFrame.new(X - 6.5, 0, z) * CFrame.Angles(0, math.pi / 2, 0))
	end
	local table_ = model(room, "SideTable")
	box(table_, "Top", Vector3.new(1.6, 0.15, 1.6), Vector3.new(X - 6.5, 1.9, 0), C.darkWood, Enum.Material.Wood)
	box(
		table_,
		"Leg",
		Vector3.new(0.25, 1.8, 0.25),
		Vector3.new(X - 6.5, 0.95, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		table_,
		"Foot",
		Vector3.new(0.9, 0.15, 0.9),
		Vector3.new(X - 6.5, 0.075, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		table_,
		"Book",
		Vector3.new(0.9, 0.18, 1.2),
		CFrame.new(X - 6.6, 2.07, 0.1) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(96, 30, 26),
		nil,
		DETAIL
	)
	cylinder(
		table_,
		"Cup",
		0.45,
		0.4,
		Vector3.new(X - 6.1, 2.2, -0.45),
		"y",
		Color3.fromRGB(226, 222, 210),
		Enum.Material.SmoothPlastic,
		DETAIL
	)

	floorLamp(room, Vector3.new(X + 9.5, 0, 8))
	bookshelf(room, CFrame.new(X + 2, 0, D / 2 - 0.7), rng) -- its back (+Z) against the +Z wall

	-- a night window on the +X wall: a cold pane, nothing to see
	local win = model(room, "Window")
	local pane = box(
		win,
		"Pane",
		Vector3.new(0.2, 4, 5),
		Vector3.new(X + W / 2 - 0.1, 5.5, -4),
		Color3.fromRGB(34, 44, 64),
		Enum.Material.Neon,
		DETAIL
	)
	pane.Transparency = 0.25
	for _, dz in { -2.5, 0, 2.5 } do
		box(
			win,
			"Mullion",
			Vector3.new(0.3, 4.2, 0.2),
			Vector3.new(X + W / 2 - 0.15, 5.5, -4 + dz),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for _, dy in { -2.1, 0, 2.1 } do
		box(
			win,
			"Mullion",
			Vector3.new(0.3, 0.2, 5.2),
			Vector3.new(X + W / 2 - 0.15, 5.5 + dy, -4),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	pointLight(pane, 8, 0.25, false, Color3.fromRGB(90, 110, 160))

	-- the other door, on the -Z wall, facing +Z into the room
	followDoor(room, CFrame.new(X, 0, -D / 2) * CFrame.Angles(0, math.pi, 0))

	-- where the server puts the players who picked the right door (facing the other door)
	box(room, "Arrive", Vector3.new(1, 1, 1), CFrame.new(X, 3, 3), Color3.new(1, 1, 1), nil, INVISIBLE)
	return room
end

------------------------------------------------------------------------------------------
-- The Threat Corridor and its Stalker
------------------------------------------------------------------------------------------
local THREAT_X = -120
local COR_W, COR_H, COR_L = 10, 11, 120
local ALCOVE_W, ALCOVE_D, ALCOVE_H = 6, 5, 9

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
	local lid =
		box(c, "Lid", Vector3.new(w + 0.1, 0.4, d + 0.1), cf * CFrame.new(0, h + 0.2, 0), C.wood, Enum.Material.Wood)
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
local function buildStalker(parent: Instance, cf: CFrame)
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
		local eye = part(s < 0 and "EyeL" or "EyeR", Vector3.new(0.26, 0.12, 0.1), CFrame.new(s * 0.32, 8.95, -0.72), {
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
	stalker:SetAttribute("EntityName", "The Follower")
	stalker:SetAttribute("Stunned", false)
	CollectionService:AddTag(stalker, "Entity")
	return stalker
end

local function buildThreatCorridor(parent: Instance)
	local corridor = model(parent, "ThreatCorridor")
	local rng = Random.new(666)
	local X, W, H, L = THREAT_X, COR_W, COR_H, COR_L
	local concrete = Enum.Material.Concrete

	box(corridor, "Floor", Vector3.new(W + 2, 1, L + 2), Vector3.new(X, -0.5, 0), C.concrete, concrete)
	box(corridor, "Ceiling", Vector3.new(W + 2, 1, L + 2), Vector3.new(X, H + 0.5, 0), C.ceiling, concrete)
	for _, s in { -1, 1 } do
		box(corridor, "EndWall", Vector3.new(W + 2, H, 1), Vector3.new(X, H / 2, s * (L / 2 + 0.5)), C.block, concrete)
	end
	-- pipes along the ceiling
	cylinder(corridor, "Pipe", L, 0.5, Vector3.new(X - 3.4, H - 0.6, 0), "z", C.pipe, Enum.Material.Metal, DETAIL)
	cylinder(corridor, "Pipe", L, 0.8, Vector3.new(X - 2.6, H - 0.9, 0), "z", C.duct, Enum.Material.Metal, DETAIL)

	-- alcoves alternate sides; each side wall is built in segments around them
	local alcoves = {} -- { side, z }
	for i, z in { -50, -30, -10, 10, 30, 50 } do
		table.insert(alcoves, { side = (i % 2 == 0) and 1 or -1, z = z })
	end
	for _, s in { -1, 1 } do
		local wallX = X + s * (W / 2 + 0.5)
		local cuts = {}
		for _, a in alcoves do
			if a.side == s then
				table.insert(cuts, a.z)
			end
		end
		table.sort(cuts)
		local z0 = -L / 2
		for _, zc in cuts do
			local z1 = zc - ALCOVE_W / 2
			box(
				corridor,
				"Wall",
				Vector3.new(1, H, z1 - z0),
				Vector3.new(wallX, H / 2, (z0 + z1) / 2),
				C.block,
				concrete
			)
			box(
				corridor,
				"Wall",
				Vector3.new(1, H - ALCOVE_H, ALCOVE_W),
				Vector3.new(wallX, (H + ALCOVE_H) / 2, zc),
				C.block,
				concrete
			)
			z0 = zc + ALCOVE_W / 2
		end
		box(
			corridor,
			"Wall",
			Vector3.new(1, H, L / 2 - z0),
			Vector3.new(wallX, H / 2, (z0 + L / 2) / 2),
			C.block,
			concrete
		)
		-- grime band along the floor and a darker line at waist height
		box(
			corridor,
			"Grime",
			Vector3.new(0.06, 1.4, L),
			Vector3.new(X + s * (W / 2 - 0.03), 0.7, 0),
			C.grime,
			concrete,
			DETAIL
		)
		box(
			corridor,
			"Line",
			Vector3.new(0.06, 0.2, L),
			Vector3.new(X + s * (W / 2 - 0.03), 3.4, 0),
			C.grime,
			concrete,
			DETAIL
		)
	end

	local chestPlaced = false
	for i, a in alcoves do
		local nook = model(corridor, "Alcove")
		local s = a.side
		local inner = X + s * (W / 2) -- the corridor wall's inner face
		local cx = inner + s * ALCOVE_D / 2
		box(nook, "Floor", Vector3.new(ALCOVE_D, 1, ALCOVE_W), Vector3.new(cx, -0.5, a.z), C.concrete, concrete)
		box(
			nook,
			"Ceiling",
			Vector3.new(ALCOVE_D, 1, ALCOVE_W),
			Vector3.new(cx, ALCOVE_H + 0.5, a.z),
			C.ceiling,
			concrete
		)
		box(
			nook,
			"Back",
			Vector3.new(1, ALCOVE_H + 2, ALCOVE_W + 2),
			Vector3.new(inner + s * (ALCOVE_D + 0.5), ALCOVE_H / 2, a.z),
			C.block,
			concrete
		)
		for _, e in { -1, 1 } do
			box(
				nook,
				"Side",
				Vector3.new(ALCOVE_D + 1, ALCOVE_H + 2, 1),
				Vector3.new(cx + s * 0.5, ALCOVE_H / 2, a.z + e * (ALCOVE_W / 2 + 0.5)),
				C.block,
				concrete
			)
		end
		-- a door in the back wall that never opens
		local doorX = inner + s * (ALCOVE_D - 0.2)
		local facing = CFrame.new(doorX, 0, a.z) * CFrame.Angles(0, s > 0 and math.pi / 2 or -math.pi / 2, 0) -- LookVector toward the corridor
		for _, e in { -1, 1 } do
			box(
				nook,
				"Jamb",
				Vector3.new(0.6, 7.2, 0.6),
				facing * CFrame.new(e * 2.3, 3.6, 0),
				C.darkWood,
				Enum.Material.Wood
			)
		end
		box(nook, "Header", Vector3.new(5.2, 0.6, 0.6), facing * CFrame.new(0, 7.5, 0), C.darkWood, Enum.Material.Wood)
		box(
			nook,
			"Slab",
			Vector3.new(4, 7, 0.3),
			facing * CFrame.new(0, 3.5, 0.1),
			Color3.fromRGB(58, 44, 36),
			Enum.Material.Wood
		)
		box(
			nook,
			"Knob",
			Vector3.new(0.35, 0.35, 0.35),
			facing * CFrame.new(1.4, 3.4, -0.2),
			C.brass,
			Enum.Material.Metal,
			{
				Shape = Enum.PartType.Ball,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
		if i == 3 and not chestPlaced then
			chestPlaced = true
			chest(nook, facing * CFrame.new(1.6, 0, -1.6) * CFrame.Angles(0, math.pi, 0), "trial_corridor_chest", 15)
		end
	end

	-- caged work lights alternate sides; two of them are dead
	for i, z in { -52, -37, -22, -7, 8, 23, 38, 53 } do
		local s = (i % 2 == 0) and 1 or -1
		local out = Vector3.new(-s, 0, 0)
		cagedLight(corridor, Vector3.new(X + s * (W / 2), 8.6, z), out, 20, 1.0, i == 3 or i == 6)
	end

	-- scattered paper, and something sprayed by whoever came before
	local litter = model(corridor, "Litter")
	for _ = 1, 16 do
		box(
			litter,
			"Paper",
			Vector3.new(1.1, 0.02, 1.4),
			CFrame.new(X + rng:NextNumber(-4, 4), 0.01, rng:NextNumber(-56, 56))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			C.paper,
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
	stencil(
		corridor,
		"Stencil",
		CFrame.new(X + W / 2 - 0.01, 6.2, 44) * CFrame.Angles(0, math.pi / 2, 0),
		7,
		1.3,
		"IT FOLLOWS",
		{ runs = 4 }
	)
	stencil(
		corridor,
		"Stencil",
		CFrame.new(X - W / 2 + 0.01, 6.4, -20) * CFrame.Angles(0, -math.pi / 2, 0),
		9,
		1.3,
		"DON'T LOOK BACK",
		{ runs = 5 }
	)

	-- players arrive at the +Z end looking down the corridor; the stalker waits at the -Z end
	box(corridor, "Arrive", Vector3.new(1, 1, 1), CFrame.new(X, 3, L / 2 - 6), Color3.new(1, 1, 1), nil, INVISIBLE)
	local endCf = CFrame.new(X, 3, -L / 2 + 5) * CFrame.Angles(0, math.pi, 0)
	box(corridor, "End", Vector3.new(1, 1, 1), endCf, Color3.new(1, 1, 1), nil, INVISIBLE)
	buildStalker(corridor, CFrame.new(X, 0, -L / 2 + 5) * CFrame.Angles(0, math.pi, 0))
	return corridor
end

------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------
export type BuildOpts = { parent: Instance?, offset: Vector3? }

function TrialBuilder.build(opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
	OFFSET = o.offset or Vector3.zero
	local parent = o.parent or workspace
	local existing = parent:FindFirstChild("Trial")
	if existing then
		existing:Destroy()
	end
	if not o.offset then
		for _, name in { "Baseplate", "SpawnLocation" } do
			local default = workspace:FindFirstChild(name)
			if default then
				default:Destroy()
			end
		end
	end

	local trial = Instance.new("Model")
	trial.Name = "Trial"
	buildDoorRoom(trial)
	buildSafeRoom(trial)
	buildThreatCorridor(trial)
	trial.Parent = parent

	-- A preview inside another place must not touch that place's Lighting.
	if not o.offset then
		-- Technology is engine-protected from scripts; set Lighting.Technology = Future in Studio.
		pcall(function()
			Lighting.Technology = Enum.Technology.Future
		end)
		Lighting.ClockTime = 0
		Lighting.Brightness = 0
		Lighting.Ambient = Color3.fromRGB(16, 14, 12)
		Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 10)
		Lighting.GlobalShadows = true
		Lighting.FogColor = Color3.fromRGB(6, 6, 8)
		Lighting.FogStart = 40
		Lighting.FogEnd = 160
	end
	OFFSET = Vector3.zero
	return trial
end

return TrialBuilder
