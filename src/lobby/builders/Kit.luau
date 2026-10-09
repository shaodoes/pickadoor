--[[
	Shared building kit for the lobby builders: palette, part helpers, lights, props.

	Conventions
	  * World units are studs; +Y up. Every builder works in world space unless it says otherwise.
	  * prop(parent, name, cf, scale) clones ServerStorage.Props[name] (pivot at bottom centre,
	    FrontYaw attribute turns its front toward -Z), so the prop's front faces cf's -Z (LookVector).
	  * anchor(parent, kind, cf, size, attrs) drops an invisible marker part with attribute FX = kind.
	    Client effect scripts (AtmosFX, AmbientSound) find these and build the effect locally.
]]
local ServerStorage = game:GetService("ServerStorage")

local Kit = {}

Kit.C = {
	concrete = Color3.fromRGB(104, 98, 90),
	block = Color3.fromRGB(132, 137, 144), -- smooth painted concrete, cool grey-blue (reference)
	blockLow = Color3.fromRGB(70, 74, 80), -- grime band along the floor
	wainscot = Color3.fromRGB(84, 90, 98),
	rail = Color3.fromRGB(60, 64, 70),
	seam = Color3.fromRGB(96, 100, 108),
	ceiling = Color3.fromRGB(112, 116, 122),
	joist = Color3.fromRGB(92, 66, 44),
	wood = Color3.fromRGB(78, 52, 34),
	darkWood = Color3.fromRGB(48, 32, 22),
	midWood = Color3.fromRGB(112, 78, 50),
	steel = Color3.fromRGB(70, 70, 72),
	rust = Color3.fromRGB(120, 52, 36),
	duct = Color3.fromRGB(150, 150, 146),
	pipe = Color3.fromRGB(150, 96, 60), -- copper
	cardboard = Color3.fromRGB(156, 118, 78),
	brass = Color3.fromRGB(150, 112, 56),
	warm = Color3.fromRGB(255, 184, 122), -- lamp light: warm but not orange
	bulb = Color3.fromRGB(255, 172, 100), -- warm amber, not white
	paint = Color3.fromRGB(214, 204, 182),
	redPaint = Color3.fromRGB(150, 40, 32),
	chalkboard = Color3.fromRGB(36, 48, 40),
	tileFloor = Color3.fromRGB(128, 122, 112),
	grout = Color3.fromRGB(96, 90, 82),
	-- natatorium
	tile = Color3.fromRGB(118, 146, 146),
	tileDeep = Color3.fromRGB(40, 70, 74),
	coldLight = Color3.fromRGB(140, 190, 200),
	glass = Color3.fromRGB(170, 200, 205),
}
local C = Kit.C

Kit.BOOK_COLORS = {
	Color3.fromRGB(96, 30, 26),
	Color3.fromRGB(58, 40, 28),
	Color3.fromRGB(40, 54, 44),
	Color3.fromRGB(34, 40, 62),
	Color3.fromRGB(120, 84, 46),
	Color3.fromRGB(70, 22, 30),
	Color3.fromRGB(140, 118, 84),
	Color3.fromRGB(28, 26, 24),
}

-- One shared, seeded generator so every rebuild lays out the same clutter.
Kit.rng = Random.new(1337)
function Kit.reseed(seed: number?)
	Kit.rng = Random.new(seed or 1337)
end

-- Non-colliding detail part that doesn't cast shadows (books, trim, small props).
Kit.DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
Kit.INVISIBLE = { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local PROPS = ServerStorage:FindFirstChild("Props")
function Kit.hasProp(name: string): boolean
	return PROPS ~= nil and PROPS:FindFirstChild(name) ~= nil
end

-- Clone a mesh prop so its front faces cf's -Z, base on cf's position. Returns nil if missing.
function Kit.prop(parent: Instance, name: string, cf: CFrame, scale: number?): Model?
	local source = PROPS and PROPS:FindFirstChild(name)
	if not source then
		return nil
	end
	local model = source:Clone()
	if scale and scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	model:PivotTo(cf * CFrame.Angles(0, model:GetAttribute("FrontYaw") or 0, 0))
	model.Parent = parent
	return model
end

-- Generic anchored part. `cf` may be a CFrame or a Vector3 position.
function Kit.box(parent: Instance, name: string, size: Vector3, cf, color: Color3, material: Enum.Material?, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
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

-- Anchored wedge (slope rises toward -Z of cf, high edge at the back/-Z... standard Roblox WedgePart:
-- the sloped face points toward +Y/-Z; the vertical face is on +Z).
function Kit.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	extra
)
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	for key, value in extra or {} do
		part[key] = value
	end
	part.Parent = parent
	return part
end

-- Cylinder whose axis runs along `axis` ("x", "y" or "z").
local AXIS = {
	x = CFrame.new(),
	y = CFrame.Angles(0, 0, math.rad(90)),
	z = CFrame.Angles(0, math.rad(90), 0),
}
function Kit.cylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	pos: Vector3,
	axis: string,
	color: Color3,
	material: Enum.Material?,
	extra
)
	local part = Kit.box(
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(pos) * AXIS[axis],
		color,
		material,
		extra
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

function Kit.folder(parent: Instance, name: string)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.pointLight(parent: Instance, range: number, brightness: number, shadows: boolean, color: Color3?)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows
	light.Color = color or C.warm
	light.Parent = parent
	return light
end

function Kit.surfaceText(part: BasePart, face: Enum.NormalId, text: string, font: Enum.Font?, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.SpecialElite
	label.Text = text
	label.TextColor3 = color or C.paint
	label.TextScaled = true
	label.Parent = gui
	return gui, label
end

function Kit.prompt(part: BasePart, objectText: string, actionText: string, panel: string)
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = objectText
	p.ActionText = actionText
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p:SetAttribute("Panel", panel)
	p.Parent = part
	return p
end

-- Invisible marker for client-side effects / sounds. `kind` goes into attribute FX.
function Kit.anchor(parent: Instance, kind: string, cf, size: Vector3?, attrs: { [string]: any }?)
	local part =
		Kit.box(parent, "FX_" .. kind, size or Vector3.new(0.4, 0.4, 0.4), cf, Color3.new(1, 1, 1), nil, Kit.INVISIBLE)
	part:SetAttribute("FX", kind)
	for key, value in attrs or {} do
		part:SetAttribute(key, value)
	end
	return part
end

-- Soft glow sprite around a light so you see a warm bloom, not the bulb: concentric circles in a
-- BillboardGui, fading outward to fake a radial falloff (no image asset needed).
function Kit.halo(part: BasePart, studs: number, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Halo"
	gui.Size = UDim2.fromScale(studs, studs) -- billboard scale is in studs
	gui.LightInfluence = 0
	gui.Brightness = 1.3 -- the core ring stacks to ~87% opaque near-white: above ~1.4 it blooms flat white
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
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = ring
	end
	return gui
end

local GLOW = Color3.fromRGB(255, 128, 48) -- deep amber; Neon renders much paler than its colour
Kit.GLOW = GLOW

-- Hanging lamp: ceiling rose at `ceilingY`, braided cord, brass fitting, then either an enamel
-- "shade" that throws a pool of light down, or a frosted "globe" that glows all round.
-- `pos` is the bulb. Returns the model and the glowing core (which carries the light).
function Kit.bareBulb(
	parent: Instance,
	pos: Vector3,
	range: number,
	brightness: number,
	shadows: boolean,
	style: string?,
	ceilingY: number
)
	local box = Kit.box
	local model = Kit.folder(parent, "Lamp")
	local vertical = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; roll them upright
	local brass = Color3.fromRGB(140, 104, 56)
	local fittingY = pos.Y + (style == "shade" and 1.0 or 0.85)
	local noCollide = { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false }
	box(
		model,
		"Rose",
		Vector3.new(0.2, 0.8, 0.8),
		CFrame.new(pos.X, ceilingY - 0.1, pos.Z) * vertical,
		brass,
		Enum.Material.Metal,
		noCollide
	)
	box(
		model,
		"Cord",
		Vector3.new(0.07, ceilingY - fittingY, 0.07),
		Vector3.new(pos.X, (ceilingY + fittingY) / 2, pos.Z),
		Color3.fromRGB(30, 24, 20),
		Enum.Material.Fabric,
		Kit.DETAIL
	)
	box(
		model,
		"Fitting",
		Vector3.new(0.4, 0.34, 0.34),
		CFrame.new(pos.X, fittingY, pos.Z) * vertical,
		brass,
		Enum.Material.Metal,
		noCollide
	)

	local core = box(model, "Core", Vector3.new(0.5, 0.5, 0.5), pos, GLOW, Enum.Material.Neon, Kit.DETAIL)
	core.Shape = Enum.PartType.Ball
	core.Transparency = 0.35
	Kit.halo(core, style == "shade" and 2.6 or 3.6)
	if style == "shade" then
		-- stepped enamel cone, dark green outside, lit warm inside
		local enamel = Color3.fromRGB(34, 56, 44)
		for i, spec in { { 0.75, 0.7 }, { 0.52, 1.2 }, { 0.3, 1.7 }, { 0.1, 2.1 } } do
			box(
				model,
				"Shade",
				Vector3.new(i == 4 and 0.14 or 0.24, spec[2], spec[2]),
				CFrame.new(pos + Vector3.new(0, spec[1], 0)) * vertical,
				enamel,
				Enum.Material.SmoothPlastic,
				{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
			)
		end
		box(
			model,
			"ShadeInner",
			Vector3.new(0.05, 1.5, 1.5),
			CFrame.new(pos + Vector3.new(0, 0.18, 0)) * vertical,
			Color3.fromRGB(255, 196, 130),
			Enum.Material.Neon,
			{
				Shape = Enum.PartType.Cylinder,
				Transparency = 0.35,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 115
		spot.Range = range
		spot.Brightness = brightness * 1.3
		spot.Color = C.warm
		spot.Shadows = shadows
		spot.Parent = core
		Kit.pointLight(core, range * 0.55, brightness * 0.35, false)
	else
		-- frosted glass globe around the glowing core
		box(model, "Globe", Vector3.new(1.3, 1.3, 1.3), pos, Color3.fromRGB(255, 224, 182), Enum.Material.Glass, {
			Shape = Enum.PartType.Ball,
			Transparency = 0.22, -- frosted enough that the bulb inside is just a glow
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		box(
			model,
			"GlobeCollar",
			Vector3.new(0.18, 0.6, 0.6),
			CFrame.new(pos + Vector3.new(0, 0.66, 0)) * vertical,
			brass,
			Enum.Material.Metal,
			noCollide
		)
		Kit.pointLight(core, range, brightness, shadows)
	end
	return model, core
end

-- Wall-mounted caged work light (faces +Z of `cf`).
function Kit.cagedLight(parent: Instance, cf: CFrame, range: number, brightness: number)
	local box = Kit.box
	local model = Kit.folder(parent, "CagedLight")
	box(model, "Mount", Vector3.new(0.6, 0.6, 0.3), cf, C.steel, Enum.Material.Metal, Kit.DETAIL)
	local bulb = box(
		model,
		"Bulb",
		Vector3.new(0.5, 0.5, 0.5),
		cf * CFrame.new(0, 0, 0.5),
		C.bulb,
		Enum.Material.Neon,
		Kit.DETAIL
	)
	bulb.Shape = Enum.PartType.Ball
	bulb.Transparency = 0.35
	Kit.halo(bulb, 2.4)
	for _, a in { 0, 90 } do
		box(
			model,
			"Cage",
			Vector3.new(0.08, 0.8, 0.8),
			cf * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, 0, math.rad(a)),
			Color3.fromRGB(30, 30, 30),
			Enum.Material.Metal,
			Kit.DETAIL
		)
	end
	Kit.pointLight(bulb, range, brightness, false)
	return model
end

return Kit
