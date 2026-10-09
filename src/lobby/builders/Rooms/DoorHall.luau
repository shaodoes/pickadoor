--[[
	The door hall (floor y = 0), through the arch at the back of the reading hall: six mismatched
	doors set into the far wall (z = -60), each in a real hole with nothing but black behind it.
	Wing A (Solo/Duo/Squad) | the stopped clock and "PICK A DOOR" | Wing B.

	Instance contract (scripts depend on it): Lobby.Pads.<Wing>_<Mode> with Zone (+Counter), Exit, Sign
	(SurfaceGui.Title/Status) + Plaque (3D), Leaf (attribute Hinge), UnderGlow (Leak), FloorSpill, Fog (Fog);
	Lobby.Queue.Stencil (SurfaceGui.Label, Glow, Drip) + StencilSign (3D), Lobby.Queue.Clock (Face.Glow, hands, Center).
]]
local Builders = script.Parent.Parent
local Kit = require(Builders.Kit)
local Layout = require(Builders.Layout)
local Furniture = require(Builders.Furniture)
local Clutter = require(Builders.Clutter)
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local signageModule = Builders:FindFirstChild("Signage")
local Signage = signageModule and require(signageModule)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local DoorHall = {}

local ROOM = Layout.Rooms.DoorHall
local Y = ROOM.y
local CEIL = ROOM.y + ROOM.h
local WALL_Z = Layout.DoorWallZ

local DOOR_STYLES = {
	-- `leak` is the light that seeps from under each door; every door is different
	{
		color = Color3.fromRGB(64, 40, 28),
		material = Enum.Material.Wood,
		panels = true,
		leak = Color3.fromRGB(255, 170, 90),
	},
	{
		color = Color3.fromRGB(110, 112, 110),
		material = Enum.Material.Metal,
		bar = true,
		leak = Color3.fromRGB(120, 220, 210),
	},
	{
		color = Color3.fromRGB(70, 96, 72),
		material = Enum.Material.WoodPlanks,
		panels = true,
		leak = Color3.fromRGB(170, 230, 110),
	},
	{
		color = Color3.fromRGB(70, 82, 104),
		material = Enum.Material.WoodPlanks,
		panels = true,
		leak = Color3.fromRGB(215, 225, 255),
	},
	{
		color = Color3.fromRGB(120, 116, 104),
		material = Enum.Material.Metal,
		bar = true,
		leak = Color3.fromRGB(175, 120, 255),
	},
	{
		color = Color3.fromRGB(110, 40, 32),
		material = Enum.Material.Wood,
		panels = true,
		leak = Color3.fromRGB(255, 60, 50),
	},
}

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Fallback lettering if the Signage module isn't there: flat SurfaceGui text.
local function plainSign(parent: Instance, name: string, cf: CFrame, w: number, h: number)
	local part = box(
		parent,
		name,
		Vector3.new(w, h, 0.05),
		cf * CFrame.new(0, 0, -0.03) * CFrame.Angles(0, math.pi, 0),
		C.block,
		nil,
		INVISIBLE
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = part
	return part, gui
end

local function buildPad(parent: Instance, queue: Instance, wing: string, mode: string, x: number, style)
	local spec = Config.Modes[mode]
	local pad = Kit.folder(parent, wing .. "_" .. mode)
	pad:SetAttribute("Mode", mode)
	pad:SetAttribute("Capacity", spec.capacity)
	pad:SetAttribute("Count", 0)
	pad:SetAttribute("TimeLeft", 0)
	pad:SetAttribute("Launching", false)
	local wallZ = WALL_Z

	-- wooden casing on the wall face around the hole
	for _, s in { -1, 1 } do
		box(
			pad,
			"Jamb",
			Vector3.new(0.7, 9.6, 0.5),
			Vector3.new(x + s * 2.95, 4.8, wallZ + 0.2),
			C.wood,
			Enum.Material.Wood
		)
	end
	box(pad, "Header", Vector3.new(6.6, 0.7, 0.5), Vector3.new(x, 9.55, wallZ + 0.2), C.wood, Enum.Material.Wood)
	box(
		pad,
		"Cornice",
		Vector3.new(7.2, 0.3, 0.7),
		Vector3.new(x, 10.05, wallZ + 0.3),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)

	-- what's behind the door: a short black passage to nothing
	box(
		pad,
		"Void",
		Vector3.new(5.4, 9.2, 0.1),
		Vector3.new(x, 4.6, wallZ - 3.9),
		Color3.fromRGB(2, 2, 3),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	for _, s in { -1, 1 } do
		box(
			pad,
			"VoidSide",
			Vector3.new(0.1, 9.2, 3.9),
			Vector3.new(x + s * 2.65, 4.6, wallZ - 1.95),
			Color3.fromRGB(6, 6, 8),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
	box(
		pad,
		"VoidTop",
		Vector3.new(5.4, 0.1, 3.9),
		Vector3.new(x, 9.15, wallZ - 1.95),
		Color3.fromRGB(6, 6, 8),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	box(
		pad,
		"VoidFloor",
		Vector3.new(5.4, 0.1, 3.9),
		Vector3.new(x, 0.02, wallZ - 1.95),
		Color3.fromRGB(8, 8, 10),
		Enum.Material.SmoothPlastic,
		DETAIL
	)

	local seam = box(
		pad,
		"UnderGlow",
		Vector3.new(5, 0.16, 0.06),
		Vector3.new(x, 0.08, wallZ + 0.06),
		style.leak,
		Enum.Material.Neon,
		DETAIL
	)
	local leak = Kit.pointLight(seam, 9, 0.6, false, style.leak)
	leak.Name = "Leak"
	local spill = box(
		pad,
		"FloorSpill",
		Vector3.new(4.8, 0.02, 1.4),
		Vector3.new(x, 0.02, wallZ + 1),
		style.leak,
		Enum.Material.Neon,
		DETAIL
	)
	spill.Transparency = 0.85

	-- the door leaf hangs on its left hinge, lifted a little so light shows underneath;
	-- the client swings and rattles it as Leaf:PivotTo(hinge * rotation)
	local leaf = Kit.folder(pad, "Leaf")
	box(leaf, "Door", Vector3.new(5.2, 8.8, 0.3), Vector3.new(x, 4.6, wallZ + 0.15), style.color, style.material)
	if style.panels then
		for _, dy in { 2.5, 6.7 } do
			box(
				leaf,
				"DoorPanel",
				Vector3.new(3.8, 3, 0.12),
				Vector3.new(x, dy, wallZ + 0.36),
				style.color:Lerp(Color3.new(0, 0, 0), 0.15),
				style.material,
				DETAIL
			)
		end
		box(
			leaf,
			"Knob",
			Vector3.new(0.35, 0.35, 0.35),
			Vector3.new(x + 2, 4.4, wallZ + 0.45),
			C.brass,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Ball, CanCollide = false }
		)
		box(
			leaf,
			"KeyPlate",
			Vector3.new(0.3, 0.7, 0.06),
			Vector3.new(x + 2, 4.2, wallZ + 0.33),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	if style.bar then
		box(
			leaf,
			"PushBar",
			Vector3.new(3.8, 0.3, 0.3),
			Vector3.new(x, 4.2, wallZ + 0.45),
			Color3.fromRGB(60, 60, 60),
			Enum.Material.Metal,
			DETAIL
		)
		box(
			leaf,
			"WireWindow",
			Vector3.new(1.2, 1.8, 0.1),
			Vector3.new(x, 6.8, wallZ + 0.33),
			Color3.fromRGB(30, 34, 38),
			Enum.Material.Glass,
			DETAIL
		)
		box(
			leaf,
			"KickPlate",
			Vector3.new(5, 1, 0.06),
			Vector3.new(x, 0.7, wallZ + 0.33),
			Color3.fromRGB(90, 90, 92),
			Enum.Material.DiamondPlate,
			DETAIL
		)
	end
	leaf.WorldPivot = CFrame.new(x - 2.6, 4.6, wallZ + 0.15)
	leaf:SetAttribute("Hinge", leaf.WorldPivot)

	box(
		pad,
		"Threshold",
		Vector3.new(6, 0.1, 1),
		Vector3.new(x, 0.05, wallZ + 0.8),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)

	-- low fog seeping out from under the door, tinted by its light
	local fogSource =
		box(pad, "Fog", Vector3.new(4.6, 0.2, 0.2), Vector3.new(x, 0.15, wallZ + 0.5), C.block, nil, INVISIBLE)
	local fog = Instance.new("ParticleEmitter")
	fog.Name = "Fog"
	fog.Texture = SMOKE_TEXTURE
	fog.EmissionDirection = Enum.NormalId.Back -- +Z, into the room
	fog.Rate = 2
	fog.Lifetime = NumberRange.new(3, 5)
	fog.Speed = NumberRange.new(0.4, 1)
	fog.SpreadAngle = Vector2.new(35, 5)
	fog.Acceleration = Vector3.new(0, -0.05, 0)
	fog.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3) })
	fog.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})
	fog.Color = ColorSequence.new(style.leak:Lerp(Color3.new(1, 1, 1), 0.5))
	fog.LightEmission = 0.25
	fog.LightInfluence = 0.6
	fog.RotSpeed = NumberRange.new(-10, 10)
	fog.Rotation = NumberRange.new(0, 360)
	fog.Parent = fogSource

	local light =
		Kit.cagedLight(queue, CFrame.new(x + 3.9, 8.6, wallZ + 0.15) * CFrame.Angles(math.rad(-20), 0, 0), 11, 0.6)
	light.Name = "DoorLight"

	-- the label above the door: Sign.SurfaceGui.Title / Status
	local signCf = CFrame.lookAt(Vector3.new(x, 11.9, wallZ), Vector3.new(x, 11.9, wallZ + 5))
	if Signage and Signage.doorPlaque then
		Signage.doorPlaque(pad, signCf, mode, spec.capacity, spec.color)
	elseif Signage and Signage.doorSign then
		Signage.doorSign(pad, signCf, mode, spec.capacity)
	else
		local sign, gui = plainSign(pad, "Sign", signCf, 6, 2.2)
		sign.Parent = pad
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.BackgroundTransparency = 1
		titleLabel.Size = UDim2.fromScale(1, 0.58)
		titleLabel.Font = Enum.Font.SpecialElite
		titleLabel.TextScaled = true
		titleLabel.TextColor3 = C.redPaint
		titleLabel.Text = string.upper(mode)
		titleLabel.Parent = gui
		local status = Instance.new("TextLabel")
		status.Name = "Status"
		status.BackgroundTransparency = 1
		status.Position = UDim2.fromScale(0, 0.58)
		status.Size = UDim2.fromScale(1, 0.42)
		status.Font = Enum.Font.SpecialElite
		status.TextScaled = true
		status.TextColor3 = Color3.fromRGB(50, 44, 38)
		status.Text = string.format("0 / %d", spec.capacity)
		status.Parent = gui
	end

	-- doormat players stand on, plus the invisible zone and exit point used by QueueService
	local padZ = wallZ + 6
	box(
		pad,
		"Rug",
		Vector3.new(7, 0.12, 5),
		Vector3.new(x, 0.06, padZ),
		spec.color,
		Enum.Material.Carpet,
		{ CanCollide = false }
	)
	box(
		pad,
		"RugBorder",
		Vector3.new(7.6, 0.1, 5.6),
		Vector3.new(x, 0.05, padZ),
		Color3.fromRGB(46, 36, 28),
		Enum.Material.Carpet,
		DETAIL
	)
	local zone = box(pad, "Zone", Vector3.new(7, 8, 6), Vector3.new(x, 4, padZ), Color3.new(1, 1, 1), nil, INVISIBLE)
	box(pad, "Exit", Vector3.new(1, 1, 1), Vector3.new(x, 3, padZ + 9), Color3.new(1, 1, 1), nil, INVISIBLE)

	-- floating counter over the mat: one ring per seat, filled in by DoorFX as players step on
	local counter = Instance.new("BillboardGui")
	counter.Name = "Counter"
	counter.Size = UDim2.fromOffset(160, 50)
	counter.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	counter.MaxDistance = 55
	counter.LightInfluence = 0
	counter.Parent = zone
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.new(1, 0, 0, 22)
	dots.Parent = counter
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = dots
	for i = 1, spec.capacity do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.LayoutOrder = i
		dot.Size = UDim2.fromOffset(18, 18)
		dot.BackgroundColor3 = Color3.fromRGB(240, 222, 190)
		dot.BackgroundTransparency = 1
		dot.Parent = dots
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = dot
		local ring = Instance.new("UIStroke")
		ring.Color = Color3.fromRGB(240, 222, 190)
		ring.Thickness = 2
		ring.Parent = dot
	end
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.BackgroundTransparency = 1
	countLabel.Position = UDim2.fromOffset(0, 24)
	countLabel.Size = UDim2.new(1, 0, 0, 24)
	countLabel.Font = Enum.Font.Oswald
	countLabel.TextScaled = true
	countLabel.TextColor3 = Color3.fromRGB(240, 222, 190)
	countLabel.TextStrokeTransparency = 0.6
	countLabel.Text = string.format("0 / %d", spec.capacity)
	countLabel.Parent = counter
	return pad
end

local function buildClock(queue: Instance, center: Vector3)
	local clock = Kit.folder(queue, "Clock")
	local facing = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z, so its round face points into the room
	box(
		clock,
		"Rim",
		Vector3.new(0.25, 3.4, 3.4),
		CFrame.new(center + Vector3.new(0, 0, 0.12)) * facing,
		C.darkWood,
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false }
	)
	local face = box(
		clock,
		"Face",
		Vector3.new(0.3, 3, 3),
		CFrame.new(center + Vector3.new(0, 0, 0.2)) * facing,
		Color3.fromRGB(226, 216, 196),
		Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false }
	)
	local glow = Kit.pointLight(face, 6, 0.35, false, Color3.fromRGB(255, 230, 190))
	glow.Name = "Glow"
	for h = 0, 11 do
		local a = h / 12 * math.pi * 2
		local len = h % 3 == 0 and 0.32 or 0.18
		box(
			clock,
			"Tick",
			Vector3.new(0.06, len, 0.02),
			CFrame.new(center + Vector3.new(math.sin(a) * 1.25, math.cos(a) * 1.25, 0.37)) * CFrame.Angles(0, 0, -a),
			Color3.fromRGB(30, 26, 22),
			nil,
			DETAIL
		)
	end
	-- hands are positioned by the client every frame; these are just their resting poses
	local function hand(name, size, color, z, angle)
		local part = box(
			clock,
			name,
			size,
			CFrame.new(center + Vector3.new(0, 0, z)) * CFrame.Angles(0, 0, -angle) * CFrame.new(0, size.Y * 0.4, 0),
			color,
			nil,
			DETAIL
		)
		part:SetAttribute("Length", size.Y)
		part:SetAttribute("Depth", z)
		return part
	end
	hand("HandHour", Vector3.new(0.12, 0.8, 0.04), Color3.fromRGB(20, 20, 20), 0.39, math.rad(20))
	hand("HandMinute", Vector3.new(0.08, 1.2, 0.04), Color3.fromRGB(20, 20, 20), 0.42, math.rad(300))
	hand("HandSecond", Vector3.new(0.04, 1.3, 0.03), C.redPaint, 0.45, 0)
	box(
		clock,
		"Pin",
		Vector3.new(0.18, 0.18, 0.18),
		center + Vector3.new(0, 0, 0.47),
		C.brass,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false }
	)
	box(
		clock,
		"Glass",
		Vector3.new(0.05, 3, 3),
		CFrame.new(center + Vector3.new(0, 0, 0.5)) * facing,
		Color3.fromRGB(220, 230, 230),
		Enum.Material.Glass,
		{
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.85,
			CanCollide = false,
			CastShadow = false,
		}
	)
	clock:SetAttribute("Center", center)
	Kit.anchor(clock, "Clock", CFrame.new(center + Vector3.new(0, 0, 0.6)))
	return clock
end

local function buildStencil(queue: Instance)
	if Signage and Signage.heroStencil then
		-- the hero sign: two lines between the inner plaques (x +-6.65), DOOR clear of the clock,
		-- PICK A under the copper pipe (bottom y 16.05)
		Signage.heroStencil(queue, Vector3.new(0, 12.23, WALL_Z), Vector3.zAxis, 12.2)
		return
	end
	local cf = CFrame.lookAt(Vector3.new(0, 12.6, WALL_Z), Vector3.new(0, 12.6, WALL_Z + 5))
		* CFrame.Angles(0, 0, math.rad(-1.5))
	if Signage and Signage.stencil then
		Signage.stencil(queue, cf, 15, 2.8, "PICK A DOOR")
		return
	end
	local stencil, gui = plainSign(queue, "Stencil", cf, 11, 2)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = C.redPaint
	label.Text = "PICK A DOOR"
	label.Parent = gui
	local glow = Kit.pointLight(stencil, 9, 0.25, false, Color3.fromRGB(255, 50, 40))
	glow.Name = "Glow"
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Drip"
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.Rate = 1.2
	drip.Lifetime = NumberRange.new(0.6, 1)
	drip.Speed = NumberRange.new(0, 0.2)
	drip.Acceleration = Vector3.new(0, -14, 0)
	drip.Size = NumberSequence.new(0.07)
	drip.Color = ColorSequence.new(C.redPaint)
	drip.Parent = stencil
end

function DoorHall.build(root: Instance)
	local model = Kit.folder(root, "DoorHall")
	local queue = Kit.folder(root, "Queue")
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = root

	-- mirrored wings: Solo on the outside, Squad nearest the clock
	local styleIndex = { A = { 1, 2, 3 }, B = { 6, 5, 4 } }
	for wing, xs in Layout.DoorXs do
		for i, mode in Config.ModeOrder do
			buildPad(pads, queue, wing, mode, xs[i], DOOR_STYLES[styleIndex[wing][i]])
		end
	end

	-- the stopped clock over an old cast-iron radiator, and PICK A DOOR above
	buildClock(queue, Vector3.new(0, 6.6, WALL_Z))
	for i = -4, 4 do
		box(
			queue,
			"RadiatorFin",
			Vector3.new(0.4, 2.6, 0.9),
			Vector3.new(i * 0.55, 1.6, WALL_Z + 0.9),
			Color3.fromRGB(150, 140, 120),
			Enum.Material.Metal,
			DETAIL
		)
	end
	box(
		queue,
		"RadiatorPipe",
		Vector3.new(5.2, 0.3, 0.3),
		Vector3.new(0, 0.4, WALL_Z + 0.9),
		C.pipe,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		queue,
		"RadiatorFoot",
		Vector3.new(5.2, 0.3, 1.1),
		Vector3.new(0, 0.15, WALL_Z + 0.9),
		Color3.fromRGB(110, 102, 88),
		Enum.Material.Metal,
		DETAIL
	)
	buildStencil(queue)

	-- dust hanging in the light in front of the doors
	local dustVolume = box(
		queue,
		"Dust",
		Vector3.new(ROOM.x1 - ROOM.x0 - 4, 9, 12),
		Vector3.new(0, 6, WALL_Z + 7),
		C.block,
		nil,
		INVISIBLE
	)
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate = 14
	dust.Lifetime = NumberRange.new(6, 10)
	dust.Speed = NumberRange.new(0, 0.1)
	dust.Acceleration = Vector3.new(0, -0.02, 0)
	dust.Drag = 1
	dust.Size = NumberSequence.new(0.06)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 230, 190))
	dust.LightEmission = 0.4
	dust.LightInfluence = 1
	dust.Parent = dustVolume

	-- one bulb in front of the doors that won't stay on
	local _, bulb = Kit.bareBulb(queue, Vector3.new(5, CEIL - 5.5, WALL_Z + 13), 24, 1.2, true, "globe", CEIL)
	bulb:FindFirstChildOfClass("PointLight"):SetAttribute("Flicker", "bulb")
	Kit.bareBulb(model, Vector3.new(-22, CEIL - 6, WALL_Z + 14), 22, 0.9, false, "globe", CEIL)
	Kit.bareBulb(model, Vector3.new(22, CEIL - 6, WALL_Z + 14), 22, 0.9, false, "globe", CEIL)

	-- benches along the side walls facing in, planters by the arch, lost-property boxes in a corner
	if Furniture.bench then
		for _, s in { -1, 1 } do
			local x = s * (ROOM.x1 - 1.6)
			Furniture.bench(model, CFrame.lookAt(Vector3.new(x, Y, -42), Vector3.new(0, Y, -42)), 8)
		end
	end
	if Furniture.planterPillar then
		for _, s in { -1, 1 } do
			Furniture.planterPillar(model, Vector3.new(s * 13, Y, ROOM.z1 - 2.2), 7)
		end
	end
	if Furniture.boxes then
		Furniture.boxes(model, CFrame.new(ROOM.x1 - 3, Y, ROOM.z1 - 3) * CFrame.Angles(0, 0.6, 0), 3)
	end
	Kit.prop(model, "PalmVase", CFrame.new(ROOM.x0 + 2, Y, ROOM.z1 - 2), 0.9)

	-- notes pinned between the doors, papers fanned out toward them
	for _, x in { -24, -14, 4.5, 14, 24 } do
		Clutter.wallNote(model, Vector3.new(x, Kit.rng:NextNumber(5.5, 8), WALL_Z), Vector3.new(0, 0, 1))
	end
	Clutter.noteCluster(model, Vector3.new(ROOM.x0, Y + 6, -38), Vector3.new(1, 0, 0), 4)
	Clutter.noteCluster(model, Vector3.new(ROOM.x1, Y + 6.5, -30), Vector3.new(-1, 0, 0), 3)
	Clutter.papers(
		model,
		{ ROOM.x0, ROOM.x1, ROOM.z0 + 9, ROOM.z1 },
		Y,
		34,
		{},
		{ Vector3.new(0, Y, -26), Vector3.new(0, Y, -50) }
	)

	Kit.anchor(model, "Drip", CFrame.new(-31, CEIL - 0.1, -52))
	Kit.anchor(model, "Drip", CFrame.new(16, CEIL - 0.1, -33))
	Kit.anchor(model, "Hum", CFrame.new(0, CEIL - 0.5, -40))
	Kit.anchor(model, "Pipes", CFrame.new(-20, CEIL - 1, -30))
	-- an old copper pipe across the back wall, above the doors, with a weeping joint
	Kit.cylinder(
		model,
		"BackPipe",
		ROOM.x1 - ROOM.x0,
		0.7,
		Vector3.new(0, CEIL - 1.6, WALL_Z + 0.9),
		"x",
		C.pipe,
		Enum.Material.Metal,
		{ CanCollide = false }
	)
	for _, x in { -30, -15, 0, 15, 30 } do
		box(
			model,
			"PipeClamp",
			Vector3.new(0.3, 1.8, 0.9),
			Vector3.new(x, CEIL - 1.25, WALL_Z + 0.5),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
	end
	Kit.anchor(
		model,
		"Steam",
		CFrame.lookAt(Vector3.new(-12, CEIL - 1.6, WALL_Z + 1.3), Vector3.new(-12, CEIL - 3, WALL_Z + 4))
	)
	return model
end

return DoorHall
