--[[
	Builds the basement library lobby into Workspace.Lobby and sets up Lighting.

	Run from the Studio command bar (or MCP) to bake it into the place:
		require(game.ServerStorage.Builders.LobbyBuilder).build()
	The lobby server also calls build() at runtime if Workspace.Lobby is missing.

	Layout (top-down, +Z is the entrance, -Z is the door wall):
		z = +100  entrance stairs + spawn
		z ~ +72   shop desk (left)      lantern bench (right)
		z +60..-30 central carpet aisle with arches; book stacks either side;
		           reading nooks under basement windows (left); mezzanine + leaderboard (right)
		z = -100  door wall: Wing A (Solo/Duo/Squad) | PICK A DOOR clock | Wing B (Solo/Duo/Squad)
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)

local LobbyBuilder = {}

local HALF_X, HALF_Z, CEILING = 60, 100, 32

local C = {
	floor = Color3.fromRGB(86, 50, 32),
	wood = Color3.fromRGB(62, 38, 25),
	darkWood = Color3.fromRGB(38, 24, 16),
	midWood = Color3.fromRGB(96, 60, 38),
	trim = Color3.fromRGB(156, 116, 58),
	carpet = Color3.fromRGB(116, 30, 27),
	brick = Color3.fromRGB(74, 50, 40),
	metal = Color3.fromRGB(36, 33, 30),
	brass = Color3.fromRGB(150, 112, 56),
	warm = Color3.fromRGB(255, 168, 88),
	glow = Color3.fromRGB(255, 212, 150),
	window = Color3.fromRGB(110, 140, 190),
	fabric = Color3.fromRGB(110, 36, 34),
	marble = Color3.fromRGB(96, 86, 80),
	screen = Color3.fromRGB(70, 200, 165),
}

local BOOK_COLORS = {
	Color3.fromRGB(96, 30, 26),
	Color3.fromRGB(58, 40, 28),
	Color3.fromRGB(40, 54, 44),
	Color3.fromRGB(34, 40, 62),
	Color3.fromRGB(120, 84, 46),
	Color3.fromRGB(70, 22, 30),
	Color3.fromRGB(140, 118, 84),
	Color3.fromRGB(28, 26, 24),
}

local rng = Random.new(1337)

-- Generic anchored part. `cf` may be a CFrame or a Vector3 position.
local function box(parent: Instance, name: string, size: Vector3, cf, color: Color3, material: Enum.Material?, extra)
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

-- Non-colliding detail part that doesn't cast shadows (books, trim, small props).
local DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

local function folder(parent: Instance, name: string)
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent
	return f
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

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, textSize: number?, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Garamond
	label.Text = text
	label.TextColor3 = color or C.glow
	label.TextScaled = textSize == nil
	if textSize then
		label.TextSize = textSize
	end
	label.Parent = gui
	return gui, label
end

local function prompt(part: BasePart, objectText: string, actionText: string, panel: string)
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

------------------------------------------------------------------------------------------
-- Shell: floor, walls, ceiling, beams, pipes, basement windows
------------------------------------------------------------------------------------------
local function buildShell(root: Instance)
	local shell = folder(root, "Shell")
	box(
		shell,
		"Floor",
		Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4),
		Vector3.new(0, -1, 0),
		C.floor,
		Enum.Material.WoodPlanks
	)
	box(
		shell,
		"Ceiling",
		Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4),
		Vector3.new(0, CEILING + 1, 0),
		C.darkWood,
		Enum.Material.Wood
	)

	local wallH = CEILING + 2
	for _, s in { -1, 1 } do
		box(
			shell,
			"WallX",
			Vector3.new(2, wallH, HALF_Z * 2 + 4),
			Vector3.new(s * (HALF_X + 1), wallH / 2 - 1, 0),
			C.wood,
			Enum.Material.WoodPlanks
		)
		box(
			shell,
			"WallZ",
			Vector3.new(HALF_X * 2 + 4, wallH, 2),
			Vector3.new(0, wallH / 2 - 1, s * (HALF_Z + 1)),
			C.wood,
			Enum.Material.WoodPlanks
		)
		-- brick wainscot band + brass rail
		box(
			shell,
			"BrickX",
			Vector3.new(0.4, 8, HALF_Z * 2),
			Vector3.new(s * (HALF_X - 0.2), 4, 0),
			C.brick,
			Enum.Material.Brick,
			DETAIL
		)
		box(
			shell,
			"BrickZ",
			Vector3.new(HALF_X * 2, 8, 0.4),
			Vector3.new(0, 4, s * (HALF_Z - 0.2)),
			C.brick,
			Enum.Material.Brick,
			DETAIL
		)
		box(
			shell,
			"RailX",
			Vector3.new(0.6, 0.4, HALF_Z * 2),
			Vector3.new(s * (HALF_X - 0.3), 8.2, 0),
			C.trim,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			shell,
			"RailZ",
			Vector3.new(HALF_X * 2, 0.4, 0.6),
			Vector3.new(0, 8.2, s * (HALF_Z - 0.3)),
			C.trim,
			Enum.Material.Wood,
			DETAIL
		)
	end

	-- heavy cross beams + two long beams: low, oppressive basement ceiling
	for z = -96, 96, 12 do
		box(
			shell,
			"Beam",
			Vector3.new(HALF_X * 2, 1.6, 1.6),
			Vector3.new(0, CEILING - 0.8, z),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for _, x in { -22, 22 } do
		box(
			shell,
			"LongBeam",
			Vector3.new(1.6, 1.6, HALF_Z * 2),
			Vector3.new(x, CEILING - 2.4, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end

	-- exposed pipes (cylinders run along X by default; yaw 90deg to run along Z)
	local alongZ = CFrame.Angles(0, math.rad(90), 0)
	for _, spec in { { -34, 29.6, 1.3 }, { -31, 29.9, 0.7 }, { 34, 29.6, 1.3 } } do
		box(
			shell,
			"Pipe",
			Vector3.new(HALF_Z * 2, spec[3], spec[3]),
			CFrame.new(spec[1], spec[2], 0) * alongZ,
			C.metal,
			Enum.Material.Metal,
			{
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
				CastShadow = false,
			}
		)
	end

	-- small high basement windows on the left wall: cold moonlight against the warm lamps
	for _, z in { -60, -30, 0, 30, 60 } do
		local glass = box(
			shell,
			"BasementWindow",
			Vector3.new(0.3, 3.6, 8),
			Vector3.new(-HALF_X + 0.15, 26, z),
			C.window,
			Enum.Material.Glass,
			{
				Transparency = 0.15,
				CanCollide = false,
			}
		)
		for _, dz in { -4.2, 4.2 } do
			box(
				shell,
				"WindowFrame",
				Vector3.new(0.6, 4.4, 0.4),
				Vector3.new(-HALF_X + 0.3, 26, z + dz),
				C.darkWood,
				Enum.Material.Wood,
				DETAIL
			)
		end
		for _, dy in { -2, 2 } do
			box(
				shell,
				"WindowFrame",
				Vector3.new(0.6, 0.4, 8.8),
				Vector3.new(-HALF_X + 0.3, 26 + dy, z),
				C.darkWood,
				Enum.Material.Wood,
				DETAIL
			)
		end
		box(
			shell,
			"WindowBar",
			Vector3.new(0.5, 3.6, 0.2),
			Vector3.new(-HALF_X + 0.3, 26, z),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Right
		light.Color = Color3.fromRGB(120, 150, 215)
		light.Brightness = 0.9
		light.Range = 20
		light.Angle = 70
		light.Shadows = true
		light.Parent = glass
	end
end

------------------------------------------------------------------------------------------
-- Bookshelves
------------------------------------------------------------------------------------------
-- A shelf unit centered at `cf` (base on floor), long along local X, books facing local +Z
-- (and -Z too when double-sided).
local function shelfUnit(
	parent: Instance,
	cf: CFrame,
	length: number,
	height: number,
	depth: number,
	doubleSided: boolean
)
	local unit = folder(parent, "Bookshelf")
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	box(
		unit,
		"Back",
		Vector3.new(length, height, 0.3),
		at(0, height / 2, doubleSided and 0 or -depth / 2 + 0.15),
		C.darkWood,
		Enum.Material.Wood
	)
	for _, s in { -1, 1 } do
		box(
			unit,
			"Side",
			Vector3.new(0.6, height, depth),
			at(s * (length / 2 + 0.3), height / 2, 0),
			C.wood,
			Enum.Material.Wood
		)
	end
	box(unit, "Top", Vector3.new(length + 1.4, 0.6, depth + 0.4), at(0, height + 0.3, 0), C.wood, Enum.Material.Wood)
	box(unit, "Plinth", Vector3.new(length, 0.6, depth), at(0, 0.3, 0), C.darkWood, Enum.Material.Wood)

	local levels = math.floor((height - 0.6) / 2.6)
	local sides = doubleSided and { 1, -1 } or { 1 }
	for level = 0, levels - 1 do
		local y = 0.6 + level * 2.6
		if level > 0 then
			box(
				unit,
				"Shelf",
				Vector3.new(length, 0.25, depth),
				at(0, y, 0),
				C.wood,
				Enum.Material.Wood,
				{ CastShadow = false }
			)
		end
		for _, side in sides do
			local bookDepth = doubleSided and (depth / 2 - 0.45) or (depth - 0.7)
			local zCenter = doubleSided and side * (0.15 + bookDepth / 2 + 0.1) or 0.25
			local x = -length / 2 + 0.2
			while x < length / 2 - 0.4 do
				local width = rng:NextNumber(1.1, 3.0)
				width = math.min(width, length / 2 - 0.2 - x)
				if rng:NextNumber() > 0.1 then
					local h = rng:NextNumber(1.4, 2.2)
					box(
						unit,
						"Books",
						Vector3.new(width - 0.05, h, bookDepth),
						at(x + width / 2, y + 0.125 + h / 2, zCenter),
						BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)],
						Enum.Material.Fabric,
						DETAIL
					)
				end
				x += width
			end
		end
	end
	return unit
end

local function buildStacks(root: Instance)
	local stacks = folder(root, "Stacks")
	-- freestanding double-sided stacks either side of the aisle, perpendicular to it
	for _, s in { -1, 1 } do
		for _, z in { 56, 42, 28, 14, 0, -14, -28 } do
			shelfUnit(stacks, CFrame.new(s * 25, 0, z), 24, 14, 3.2, true)
		end
	end
	-- tall wall shelves on the left wall (facing +X) and the entrance wall
	local faceRight = CFrame.Angles(0, math.rad(90), 0)
	for _, z in { 76, 44, 12, -20, -52 } do
		shelfUnit(stacks, CFrame.new(-HALF_X + 1.8, 0, z) * faceRight, 28, 20, 2.6, false)
	end
	local faceBack = CFrame.Angles(0, math.rad(180), 0)
	for _, x in { -36, 24 } do
		shelfUnit(stacks, CFrame.new(x, 0, HALF_Z - 1.8) * faceBack, 22, 20, 2.6, false)
	end
end

------------------------------------------------------------------------------------------
-- Central aisle: carpet runner, arches, chandeliers, lamp posts
------------------------------------------------------------------------------------------
local function chandelier(parent: Instance, pos: Vector3)
	local model = folder(parent, "Chandelier")
	box(
		model,
		"Chain",
		Vector3.new(0.2, CEILING - pos.Y, 0.2),
		Vector3.new(pos.X, (CEILING + pos.Y) / 2, pos.Z),
		C.metal,
		Enum.Material.Metal,
		DETAIL
	)
	local hub = box(
		model,
		"Hub",
		Vector3.new(1.2, 1.2, 1.2),
		pos,
		C.brass,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false }
	)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local offset = Vector3.new(math.cos(a) * 2.4, -0.4, math.sin(a) * 2.4)
		box(
			model,
			"Arm",
			Vector3.new(2.4, 0.15, 0.15),
			CFrame.lookAt(pos + offset / 2, pos + offset) * CFrame.Angles(0, math.rad(90), 0),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			model,
			"Candle",
			Vector3.new(0.25, 0.5, 0.25),
			pos + offset + Vector3.new(0, 0.3, 0),
			C.glow,
			Enum.Material.Neon,
			DETAIL
		)
	end
	pointLight(hub, 30, 1.7, true)
end

local function lampPost(parent: Instance, pos: Vector3)
	local model = folder(parent, "LampPost")
	box(model, "Base", Vector3.new(1.1, 0.4, 1.1), pos + Vector3.new(0, 0.2, 0), C.metal, Enum.Material.Metal)
	box(
		model,
		"Pole",
		Vector3.new(5, 0.45, 0.45),
		CFrame.new(pos + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.metal,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }
	)
	local head =
		box(model, "Lamp", Vector3.new(0.9, 1.1, 0.9), pos + Vector3.new(0, 5.7, 0), C.glow, Enum.Material.Neon, DETAIL)
	box(model, "Cap", Vector3.new(1.2, 0.25, 1.2), pos + Vector3.new(0, 6.35, 0), C.metal, Enum.Material.Metal, DETAIL)
	pointLight(head, 15, 1.1, false)
end

local function buildAisle(root: Instance)
	local aisle = folder(root, "Aisle")
	local zFront, zBack = 82, -90
	local len, mid = zFront - zBack, (zFront + zBack) / 2
	box(
		aisle,
		"Carpet",
		Vector3.new(16, 0.1, len),
		Vector3.new(0, 0.05, mid),
		C.carpet,
		Enum.Material.Fabric,
		{ CanCollide = false }
	)
	for _, s in { -1, 1 } do
		box(
			aisle,
			"CarpetBorder",
			Vector3.new(0.6, 0.12, len),
			Vector3.new(s * 8.3, 0.06, mid),
			C.trim,
			Enum.Material.Fabric,
			DETAIL
		)
	end

	-- semicircular arches (radius 10) over the aisle
	local radius, springY, segments = 10, 18, 12
	for z = 70, -50, -20 do
		local arch = folder(aisle, "Arch")
		for _, s in { -1, 1 } do
			box(
				arch,
				"Pillar",
				Vector3.new(2.4, springY, 2.4),
				Vector3.new(s * radius, springY / 2, z),
				C.wood,
				Enum.Material.Wood
			)
			box(
				arch,
				"PillarBase",
				Vector3.new(3, 1, 3),
				Vector3.new(s * radius, 0.5, z),
				C.darkWood,
				Enum.Material.Wood
			)
			box(
				arch,
				"Capital",
				Vector3.new(3, 0.6, 3),
				Vector3.new(s * radius, springY, z),
				C.trim,
				Enum.Material.Wood,
				DETAIL
			)
		end
		local chord = 2 * radius * math.sin(math.pi / (2 * segments))
		for i = 0, segments - 1 do
			local a = math.pi * (i + 0.5) / segments
			local pos = Vector3.new(math.cos(a) * radius, springY + math.sin(a) * radius, z)
			box(
				arch,
				"ArchSegment",
				Vector3.new(chord + 0.35, 1.6, 2.4),
				CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2),
				C.wood,
				Enum.Material.Wood,
				{ CanCollide = false }
			)
		end
		if z > -50 then
			chandelier(aisle, Vector3.new(0, 23, z - 10))
		end
	end

	for z = 60, -40, -20 do
		for _, s in { -1, 1 } do
			lampPost(aisle, Vector3.new(s * 9.3, 0, z))
		end
	end
end

------------------------------------------------------------------------------------------
-- Furniture
------------------------------------------------------------------------------------------
local function chair(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local model = folder(parent, "Chair")
	box(model, "Seat", Vector3.new(1.8, 0.3, 1.8), cf * CFrame.new(0, 1.8, 0), C.wood, Enum.Material.Wood)
	box(model, "Back", Vector3.new(1.8, 2.2, 0.3), cf * CFrame.new(0, 3, 0.8), C.wood, Enum.Material.Wood)
	for _, x in { -0.75, 0.75 } do
		for _, z in { -0.75, 0.75 } do
			box(
				model,
				"Leg",
				Vector3.new(0.22, 1.7, 0.22),
				cf * CFrame.new(x, 0.85, z),
				C.darkWood,
				Enum.Material.Wood,
				DETAIL
			)
		end
	end
end

local function bankerLamp(parent: Instance, pos: Vector3)
	box(
		parent,
		"LampBase",
		Vector3.new(0.6, 0.15, 0.6),
		pos + Vector3.new(0, 0.08, 0),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		parent,
		"LampStem",
		Vector3.new(0.12, 0.9, 0.12),
		pos + Vector3.new(0, 0.55, 0),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local shade = box(
		parent,
		"LampShade",
		Vector3.new(1.1, 0.35, 0.5),
		pos + Vector3.new(0, 1.05, 0),
		Color3.fromRGB(40, 110, 70),
		Enum.Material.Glass,
		DETAIL
	)
	box(
		parent,
		"LampBulb",
		Vector3.new(0.8, 0.12, 0.3),
		pos + Vector3.new(0, 0.85, 0),
		C.glow,
		Enum.Material.Neon,
		DETAIL
	)
	pointLight(shade, 9, 1, false)
end

local function readingTable(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local model = folder(parent, "ReadingTable")
	box(model, "Top", Vector3.new(7, 0.35, 3.6), cf * CFrame.new(0, 3, 0), C.midWood, Enum.Material.Wood)
	for _, x in { -3.1, 3.1 } do
		for _, z in { -1.4, 1.4 } do
			box(
				model,
				"Leg",
				Vector3.new(0.35, 2.85, 0.35),
				cf * CFrame.new(x, 1.43, z),
				C.darkWood,
				Enum.Material.Wood
			)
		end
	end
	bankerLamp(model, (cf * CFrame.new(1.8, 3.18, 0)).Position)
	box(
		model,
		"OpenBook",
		Vector3.new(1.4, 0.12, 1),
		cf * CFrame.new(-1.2, 3.23, 0.4) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(225, 210, 180),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	for _, side in { -1, 1 } do
		chair(model, (cf * CFrame.new(-1.6, 0, side * 2.6)).Position, yaw + (side > 0 and 0 or math.pi))
		chair(model, (cf * CFrame.new(1.6, 0, side * 2.6)).Position, yaw + (side > 0 and 0 or math.pi))
	end
end

local function sofa(parent: Instance, cf: CFrame)
	local model = folder(parent, "Sofa")
	box(model, "Seat", Vector3.new(6, 1.4, 2.8), cf * CFrame.new(0, 0.9, 0), C.fabric, Enum.Material.Fabric)
	box(model, "Back", Vector3.new(6, 2.4, 0.8), cf * CFrame.new(0, 2, 1.2), C.fabric, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		box(model, "Arm", Vector3.new(0.8, 2, 2.8), cf * CFrame.new(s * 3.2, 1.2, 0), C.fabric, Enum.Material.Fabric)
	end
	box(model, "Feet", Vector3.new(6.6, 0.2, 2.6), cf * CFrame.new(0, 0.1, 0), C.darkWood, Enum.Material.Wood, DETAIL)
end

local function railing(parent: Instance, from: Vector3, to: Vector3, height: number)
	local dir = to - from
	local len = dir.Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	box(parent, "Handrail", Vector3.new(0.45, 0.3, len), cf + Vector3.new(0, height, 0), C.trim, Enum.Material.Wood)
	box(
		parent,
		"Bottomrail",
		Vector3.new(0.3, 0.25, len),
		cf + Vector3.new(0, 0.4, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	local count = math.floor(len / 2.2)
	for i = 0, count do
		local p = from + dir * (i / count)
		box(
			parent,
			"Baluster",
			Vector3.new(0.25, height, 0.25),
			p + Vector3.new(0, height / 2, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
end

------------------------------------------------------------------------------------------
-- Areas
------------------------------------------------------------------------------------------
local function buildReadingNooks(root: Instance)
	local nooks = folder(root, "Reading")
	for _, z in { 58, 28, -4, -36 } do
		readingTable(nooks, Vector3.new(-47, 0, z), math.rad(90))
	end
	for _, x in { -26, 26 } do
		readingTable(nooks, Vector3.new(x, 0, -48), 0)
	end
end

local function buildMezzanine(root: Instance)
	local mez = folder(root, "Mezzanine")
	local deckY, x0, x1, z0, z1 = 12, 40, HALF_X, -24, 80
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	box(
		mez,
		"Deck",
		Vector3.new(x1 - x0, 1, z1 - z0),
		Vector3.new(cx, deckY - 0.5, cz),
		C.floor,
		Enum.Material.WoodPlanks
	)
	box(
		mez,
		"Fascia",
		Vector3.new(0.6, 1.6, z1 - z0),
		Vector3.new(x0 - 0.3, deckY - 0.8, cz),
		C.trim,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		mez,
		"Runner",
		Vector3.new(6, 0.1, z1 - z0 - 6),
		Vector3.new(cx - 3, deckY + 0.05, cz),
		C.carpet,
		Enum.Material.Fabric,
		DETAIL
	)
	for _, z in { z0 + 2, 6, 30, 54, z1 - 2 } do
		box(
			mez,
			"Column",
			Vector3.new(1.6, deckY - 1, 1.6),
			Vector3.new(x0 + 1, (deckY - 1) / 2, z),
			C.wood,
			Enum.Material.Wood
		)
	end

	-- stairs come down toward the entrance (z+), 12 steps of 1 stud
	local stairX0, stairX1 = 44, 56
	for k = 1, deckY do
		local zc = z1 + 15 - (k - 0.5) * 1.25
		box(
			mez,
			"Step",
			Vector3.new(stairX1 - stairX0, k, 1.25),
			Vector3.new((stairX0 + stairX1) / 2, k / 2, zc),
			C.midWood,
			Enum.Material.WoodPlanks
		)
	end
	railing(mez, Vector3.new(stairX0, 1, z1 + 15), Vector3.new(stairX0, deckY + 1, z1), 3.2)

	railing(mez, Vector3.new(x0 + 0.3, deckY, z0), Vector3.new(x0 + 0.3, deckY, z1), 3.4)
	railing(mez, Vector3.new(x0, deckY, z0 + 0.3), Vector3.new(x1, deckY, z0 + 0.3), 3.4)
	railing(mez, Vector3.new(x0, deckY, z1 - 0.3), Vector3.new(stairX0, deckY, z1 - 0.3), 3.4)

	local faceAisle = CFrame.Angles(0, math.rad(-90), 0)
	sofa(mez, CFrame.new(52, deckY, 62) * CFrame.Angles(0, math.rad(90), 0))
	sofa(mez, CFrame.new(52, deckY, 6) * CFrame.Angles(0, math.rad(90), 0))
	shelfUnit(mez, CFrame.new(HALF_X - 1.6, deckY, 66) * faceAisle, 22, 16, 2.4, false)
	shelfUnit(mez, CFrame.new(HALF_X - 1.6, deckY, -6) * faceAisle, 22, 16, 2.4, false)
	for _, z in { 46, 14 } do
		local lampPos = Vector3.new(44, deckY, z)
		box(
			mez,
			"FloorLampPole",
			Vector3.new(0.3, 5, 0.3),
			lampPos + Vector3.new(0, 2.5, 0),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		local shade = box(
			mez,
			"FloorLampShade",
			Vector3.new(1.6, 1.2, 1.6),
			lampPos + Vector3.new(0, 5.4, 0),
			Color3.fromRGB(230, 190, 140),
			Enum.Material.Fabric,
			DETAIL
		)
		pointLight(shade, 14, 1, false)
	end

	-- underneath: a dim storage nook with crates
	for i, z in { 60, 64, 20, 23 } do
		box(
			mez,
			"Crate",
			Vector3.new(3, 3, 3),
			CFrame.new(54, 1.5 + (i % 2) * 0, z) * CFrame.Angles(0, math.rad(i * 17), 0),
			C.midWood,
			Enum.Material.WoodPlanks
		)
	end
	local bulb =
		box(mez, "NookBulb", Vector3.new(0.5, 0.6, 0.5), Vector3.new(52, 10.2, 40), C.glow, Enum.Material.Neon, DETAIL)
	pointLight(bulb, 12, 0.6, true)
end

local function buildLeaderboard(root: Instance)
	local board = folder(root, "Leaderboard")
	local pos = Vector3.new(HALF_X - 0.3, 21, 30)
	local face = box(board, "Board", Vector3.new(0.4, 11, 22), pos, Color3.fromRGB(22, 15, 11), Enum.Material.Wood)
	for _, dz in { -11.3, 11.3 } do
		box(
			board,
			"Frame",
			Vector3.new(0.7, 12, 0.6),
			pos + Vector3.new(-0.1, 0, dz),
			C.trim,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for _, dy in { -5.8, 5.8 } do
		box(
			board,
			"Frame",
			Vector3.new(0.7, 0.6, 23.2),
			pos + Vector3.new(-0.1, dy, 0),
			C.trim,
			Enum.Material.Wood,
			DETAIL
		)
	end
	local lamp = box(
		board,
		"PictureLight",
		Vector3.new(0.6, 0.4, 14),
		pos + Vector3.new(-1, 6.6, 0),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 100
	spot.Range = 14
	spot.Brightness = 1.4
	spot.Color = C.warm
	spot.Parent = lamp

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.5
	gui.Parent = face

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.03)
	title.Size = UDim2.fromScale(1, 0.13)
	title.Font = Enum.Font.Garamond
	title.TextScaled = true
	title.TextColor3 = C.trim
	title.Text = "HALL OF RECORDS"
	title.Parent = gui

	for col, spec in { { "Keys", "Most " .. Config.CurrencyName }, { "Trials", "Trials Survived" } } do
		local column = Instance.new("Frame")
		column.Name = spec[1]
		column.BackgroundTransparency = 1
		column.Position = UDim2.fromScale((col - 1) * 0.5 + 0.03, 0.18)
		column.Size = UDim2.fromScale(0.44, 0.8)
		column.Parent = gui
		local heading = Instance.new("TextLabel")
		heading.Name = "Heading"
		heading.BackgroundTransparency = 1
		heading.Size = UDim2.fromScale(1, 0.1)
		heading.Font = Enum.Font.Garamond
		heading.TextScaled = true
		heading.TextColor3 = C.glow
		heading.Text = spec[2]
		heading.Parent = column
		for row = 1, 10 do
			local label = Instance.new("TextLabel")
			label.Name = "Row" .. row
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0, 0.12 + (row - 1) * 0.088)
			label.Size = UDim2.fromScale(1, 0.08)
			label.Font = Enum.Font.Garamond
			label.TextScaled = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Color3.fromRGB(225, 205, 170)
			label.Text = string.format("%d.  ---", row)
			label.Parent = column
		end
	end
end

local function buildShop(root: Instance)
	local shop = folder(root, "Shop")
	local cx, cz = -30, 72
	-- librarian's front desk facing the aisle (+X)
	box(shop, "DeskBody", Vector3.new(3, 3.4, 14), Vector3.new(cx, 1.7, cz), C.darkWood, Enum.Material.Wood)
	local top =
		box(shop, "DeskTop", Vector3.new(3.8, 0.3, 14.8), Vector3.new(cx, 3.55, cz), C.marble, Enum.Material.Marble)
	box(shop, "DeskWing", Vector3.new(8, 3.4, 3), Vector3.new(cx - 5.5, 1.7, cz - 5.5), C.darkWood, Enum.Material.Wood)
	box(
		shop,
		"DeskWingTop",
		Vector3.new(8.8, 0.3, 3.8),
		Vector3.new(cx - 5.5, 3.55, cz - 5.5),
		C.marble,
		Enum.Material.Marble
	)
	for i = -2, 2 do
		box(
			shop,
			"Drawer",
			Vector3.new(0.15, 1.2, 2.2),
			Vector3.new(cx + 1.55, 2.2, cz + i * 2.7),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			shop,
			"Knob",
			Vector3.new(0.2, 0.2, 0.5),
			Vector3.new(cx + 1.65, 2.2, cz + i * 2.7),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	-- old computer terminal (green glow, like the reference desk)
	box(
		shop,
		"Monitor",
		Vector3.new(1.4, 1.5, 1.8),
		Vector3.new(cx - 0.4, 4.45, cz - 3),
		Color3.fromRGB(50, 46, 40),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	local screen = box(
		shop,
		"Screen",
		Vector3.new(0.05, 1.1, 1.4),
		Vector3.new(cx + 0.33, 4.5, cz - 3),
		C.screen,
		Enum.Material.Neon,
		DETAIL
	)
	pointLight(screen, 6, 0.8, false, C.screen)
	bankerLamp(shop, Vector3.new(cx, 3.7, cz + 4))
	for i = 0, 3 do
		box(
			shop,
			"BookPile",
			Vector3.new(1.4, 0.35, 1),
			Vector3.new(cx - 0.3, 3.88 + i * 0.36, cz + 1 + (i % 2) * 0.15),
			BOOK_COLORS[i + 1],
			Enum.Material.Fabric,
			DETAIL
		)
	end
	shelfUnit(shop, CFrame.new(cx - 6, 0, cz + 2) * CFrame.Angles(0, math.rad(90), 0), 12, 10, 2.4, false)

	local sign = box(
		shop,
		"Sign",
		Vector3.new(0.3, 2.2, 8),
		Vector3.new(cx + 0.5, 11, cz),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		shop,
		"SignChain",
		Vector3.new(0.1, CEILING - 12, 0.1),
		Vector3.new(cx + 0.5, (CEILING + 12) / 2, cz),
		C.metal,
		Enum.Material.Metal,
		DETAIL
	)
	surfaceText(sign, Enum.NormalId.Right, "SHOP", nil, C.trim)
	surfaceText(sign, Enum.NormalId.Left, "SHOP", nil, C.trim)
	prompt(top, "Librarian's Desk", "Browse Shop", "Shop")
end

local function buildLanternBench(root: Instance)
	local bench = folder(root, "LanternBench")
	local cx, cz = 30, 70
	local top = box(bench, "Top", Vector3.new(3.6, 0.4, 12), Vector3.new(cx, 3, cz), C.midWood, Enum.Material.Wood)
	for _, dz in { -5.4, 5.4 } do
		for _, dx in { -1.4, 1.4 } do
			box(
				bench,
				"Leg",
				Vector3.new(0.4, 2.8, 0.4),
				Vector3.new(cx + dx, 1.4, cz + dz),
				C.darkWood,
				Enum.Material.Wood
			)
		end
	end
	for i, def in Lanterns.List do
		local z = cz - 5 + (i - 1) * (10 / math.max(#Lanterns.List - 1, 1))
		local lantern = LanternBuilder.buildModel(def.id, true)
		lantern:PivotTo(CFrame.new(cx, 3.2, z) * CFrame.Angles(0, math.rad(rng:NextInteger(-30, 30)), 0))
		lantern.Parent = bench
	end
	local sign = box(
		bench,
		"Sign",
		Vector3.new(0.3, 2.2, 9),
		Vector3.new(cx - 0.5, 11, cz),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		bench,
		"SignChain",
		Vector3.new(0.1, CEILING - 12, 0.1),
		Vector3.new(cx - 0.5, (CEILING + 12) / 2, cz),
		C.metal,
		Enum.Material.Metal,
		DETAIL
	)
	surfaceText(sign, Enum.NormalId.Left, "LANTERNS", nil, C.trim)
	surfaceText(sign, Enum.NormalId.Right, "LANTERNS", nil, C.trim)
	prompt(top, "Lantern Bench", "Customize Lantern", "Lanterns")
end

local function buildEntrance(root: Instance)
	local entrance = folder(root, "Entrance")
	local steps = 7
	for k = 1, steps do
		box(
			entrance,
			"Step",
			Vector3.new(12, k, 1),
			Vector3.new(0, k / 2, HALF_Z - steps - 0.5 + k),
			C.midWood,
			Enum.Material.WoodPlanks
		)
	end
	box(
		entrance,
		"Landing",
		Vector3.new(12, steps, 2),
		Vector3.new(0, steps / 2, HALF_Z - 1),
		C.midWood,
		Enum.Material.WoodPlanks
	)
	box(
		entrance,
		"Door",
		Vector3.new(6, 10, 0.4),
		Vector3.new(0, steps + 5, HALF_Z - 0.2),
		C.darkWood,
		Enum.Material.Wood
	)
	box(
		entrance,
		"DoorFrame",
		Vector3.new(7.6, 11, 0.3),
		Vector3.new(0, steps + 5.3, HALF_Z - 0.05),
		C.trim,
		Enum.Material.Wood,
		DETAIL
	)
	local exitSign = box(
		entrance,
		"ExitSign",
		Vector3.new(2.4, 0.8, 0.2),
		Vector3.new(0, steps + 11.4, HALF_Z - 0.3),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	surfaceText(exitSign, Enum.NormalId.Front, "NO EXIT", nil, Color3.fromRGB(200, 60, 50))
	local bulb = box(
		entrance,
		"Bulb",
		Vector3.new(0.5, 0.6, 0.5),
		Vector3.new(0, steps + 12.6, HALF_Z - 1.2),
		C.glow,
		Enum.Material.Neon,
		DETAIL
	)
	pointLight(bulb, 14, 0.8, true)

	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "Spawn"
	spawnPoint.Anchored = true
	spawnPoint.Size = Vector3.new(10, 0.2, 6)
	spawnPoint.CFrame = CFrame.new(0, 0.11, HALF_Z - 14) -- faces -Z, down the aisle
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.CanQuery = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = entrance
end

------------------------------------------------------------------------------------------
-- Door wall: two wings of Solo / Duo / Squad queue pads
------------------------------------------------------------------------------------------
local function buildPad(parent: Instance, wing: string, mode: string, x: number)
	local spec = Config.Modes[mode]
	local pad = folder(parent, wing .. "_" .. mode)
	pad:SetAttribute("Mode", mode)
	pad:SetAttribute("Capacity", spec.capacity)
	pad:SetAttribute("Count", 0)
	pad:SetAttribute("TimeLeft", 0)
	local wallZ = -HALF_Z

	-- doorway
	for _, s in { -1, 1 } do
		box(pad, "Jamb", Vector3.new(1.2, 12, 1.6), Vector3.new(x + s * 4, 6, wallZ + 0.8), C.wood, Enum.Material.Wood)
	end
	box(pad, "Header", Vector3.new(9.4, 1.6, 1.8), Vector3.new(x, 12.8, wallZ + 0.9), C.wood, Enum.Material.Wood)
	box(
		pad,
		"Door",
		Vector3.new(6.8, 11.4, 0.4),
		Vector3.new(x, 5.7, wallZ + 0.3),
		Color3.fromRGB(44, 27, 19),
		Enum.Material.Wood
	)
	for _, dy in { 2.8, 8.2 } do
		box(
			pad,
			"DoorPanel",
			Vector3.new(4.8, 3.6, 0.15),
			Vector3.new(x, dy, wallZ + 0.55),
			Color3.fromRGB(56, 35, 24),
			Enum.Material.Wood,
			DETAIL
		)
	end
	box(
		pad,
		"Knob",
		Vector3.new(0.4, 0.4, 0.4),
		Vector3.new(x + 2.5, 5.3, wallZ + 0.7),
		C.brass,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false }
	)
	for _, s in { -1, 1 } do
		local sconce = box(
			pad,
			"Sconce",
			Vector3.new(0.5, 0.8, 0.5),
			Vector3.new(x + s * 5.4, 9, wallZ + 0.5),
			C.glow,
			Enum.Material.Neon,
			DETAIL
		)
		pointLight(sconce, 10, 0.9, false)
	end

	-- sign above the door, faces the room (+Z = Back face)
	local sign = box(
		pad,
		"Sign",
		Vector3.new(8, 2.6, 0.3),
		Vector3.new(x, 15.4, wallZ + 0.3),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.4
	gui.Parent = sign
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.55)
	titleLabel.Font = Enum.Font.Garamond
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = C.trim
	titleLabel.Text = string.upper(mode)
	titleLabel.Parent = gui
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromScale(0, 0.55)
	status.Size = UDim2.fromScale(1, 0.45)
	status.Font = Enum.Font.Garamond
	status.TextScaled = true
	status.TextColor3 = C.glow
	status.Text = string.format("0 / %d", spec.capacity)
	status.Parent = gui

	-- rug pad players stand on, plus the invisible zone and exit point used by QueueService
	local padZ = wallZ + 8
	box(
		pad,
		"Rug",
		Vector3.new(10, 0.15, 8),
		Vector3.new(x, 0.08, padZ),
		spec.color,
		Enum.Material.Fabric,
		{ CanCollide = false }
	)
	box(
		pad,
		"RugBorder",
		Vector3.new(10.8, 0.12, 8.8),
		Vector3.new(x, 0.06, padZ),
		C.trim,
		Enum.Material.Fabric,
		DETAIL
	)
	box(pad, "Zone", Vector3.new(10, 8, 8), Vector3.new(x, 4, padZ), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	box(
		pad,
		"Exit",
		Vector3.new(1, 1, 1),
		Vector3.new(x, 3, padZ + 10),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}
	)
	return pad
end

local function buildDoorWall(root: Instance)
	local queue = folder(root, "Queue")
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = root

	local wings = { A = { -50, -34, -18 }, B = { 18, 34, 50 } }
	for wing, xs in wings do
		for i, mode in Config.ModeOrder do
			buildPad(pads, wing, mode, xs[i])
		end
	end

	-- centerpiece between the wings: grandfather clock under the title board
	local wallZ = -HALF_Z
	box(queue, "ClockCase", Vector3.new(4, 11, 2.2), Vector3.new(0, 5.5, wallZ + 1.4), C.darkWood, Enum.Material.Wood)
	box(
		queue,
		"ClockHood",
		Vector3.new(4.8, 1, 2.6),
		Vector3.new(0, 11.5, wallZ + 1.4),
		C.trim,
		Enum.Material.Wood,
		DETAIL
	)
	local clockFace = box(
		queue,
		"ClockFace",
		Vector3.new(0.2, 3, 3),
		CFrame.new(0, 8.6, wallZ + 2.55) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(235, 220, 190),
		Enum.Material.SmoothPlastic,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		}
	)
	pointLight(clockFace, 6, 0.4, false)
	box(
		queue,
		"HandHour",
		Vector3.new(0.12, 0.9, 0.05),
		CFrame.new(0, 8.85, wallZ + 2.7) * CFrame.Angles(0, 0, math.rad(-20)),
		C.metal,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		queue,
		"HandMinute",
		Vector3.new(0.08, 1.3, 0.05),
		CFrame.new(0.3, 8.6, wallZ + 2.7) * CFrame.Angles(0, 0, math.rad(-110)),
		C.metal,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		queue,
		"Pendulum",
		Vector3.new(0.12, 3, 0.1),
		Vector3.new(0, 4.8, wallZ + 2.55),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)

	local title = box(
		queue,
		"TitleBoard",
		Vector3.new(18, 4.4, 0.4),
		Vector3.new(0, 17, wallZ + 0.3),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	surfaceText(title, Enum.NormalId.Back, "PICK A DOOR", nil, C.trim)
	local titleLamp = box(
		queue,
		"TitleLamp",
		Vector3.new(10, 0.3, 0.6),
		Vector3.new(0, 19.6, wallZ + 1.2),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 110
	spot.Range = 12
	spot.Brightness = 1.2
	spot.Color = C.warm
	spot.Parent = titleLamp

	for _, s in { -1, 1 } do
		local wingSign = box(
			queue,
			"WingLabelBoard",
			Vector3.new(14, 2, 0.3),
			Vector3.new(s * 34, 20, wallZ + 0.3),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		surfaceText(wingSign, Enum.NormalId.Back, s < 0 and "WING A" or "WING B", nil, C.glow)
	end
end

------------------------------------------------------------------------------------------
-- Lighting: dark, warm, hazy. Future tech so every lamp casts real light.
------------------------------------------------------------------------------------------
local function setupLighting()
	Lighting.Technology = Enum.Technology.Future
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(14, 9, 6)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 8, 7)
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.25

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.38
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(70, 48, 32)
	atmosphere.Decay = Color3.fromRGB(30, 20, 14)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 236, 214)
	cc.Contrast = 0.12
	cc.Saturation = -0.05
	cc.Brightness = 0.02
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
end

function LobbyBuilder.build()
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local default = workspace:FindFirstChild(name)
		if default then
			default:Destroy()
		end
	end

	local root = Instance.new("Model")
	root.Name = "Lobby"
	buildShell(root)
	buildAisle(root)
	buildStacks(root)
	buildReadingNooks(root)
	buildMezzanine(root)
	buildLeaderboard(root)
	buildShop(root)
	buildLanternBench(root)
	buildEntrance(root)
	buildDoorWall(root)
	root.Parent = workspace

	setupLighting()
	return root
end

return LobbyBuilder
