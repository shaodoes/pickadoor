--[[
	Builds the lobby: a basement that someone turned into a library. Low joist ceiling, pipes and
	ducts, concrete floor, painted cinderblock, steel posts, bare bulbs. Bookcases and metal racks
	of boxed books. Six mismatched doors set into the back wall that shouldn't be there.

	Run from the Studio command bar (or MCP) to bake it into the place:
		require(game.ServerStorage.Builders.LobbyBuilder).build()
	The lobby server also calls build() at runtime if Workspace.Lobby is missing.

	Layout (top-down, +Z is the front, -Z is the door wall):
		front-right   open wooden stairs down from the ground-floor door (spawn on the landing)
		front-left    checkout desk + card catalogs (Shop)
		left wall     workbench + pegboard of lanterns (Lanterns); reading nook at the back
		right wall    chalkboard leaderboard; furnace + water heater at the back
		middle        rug-covered walkway under the steel girder; rows of bookcases and racks
		back wall     Wing A (Solo/Duo/Squad) | clock + "PICK A DOOR" stencil | Wing B
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)

local LobbyBuilder = {}

local HALF_X, HALF_Z, CEILING = 50, 70, 16

local C = {
	concrete = Color3.fromRGB(104, 98, 90),
	block = Color3.fromRGB(150, 140, 122), -- painted cinderblock
	blockLow = Color3.fromRGB(96, 86, 74), -- grime band along the floor
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
	warm = Color3.fromRGB(255, 166, 86),
	bulb = Color3.fromRGB(255, 214, 160),
	paint = Color3.fromRGB(214, 204, 182),
	redPaint = Color3.fromRGB(150, 40, 32),
	chalkboard = Color3.fromRGB(36, 48, 40),
	window = Color3.fromRGB(110, 140, 190),
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

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, font: Enum.Font?, color: Color3?)
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

-- Bare bulb hanging on a cord from the joists.
local function bareBulb(parent: Instance, pos: Vector3, range: number, brightness: number, shadows: boolean)
	local model = folder(parent, "Bulb")
	box(
		model,
		"Cord",
		Vector3.new(0.08, CEILING - pos.Y, 0.08),
		Vector3.new(pos.X, (CEILING + pos.Y) / 2, pos.Z),
		Color3.fromRGB(20, 20, 20),
		nil,
		DETAIL
	)
	box(
		model,
		"Socket",
		Vector3.new(0.3, 0.35, 0.3),
		pos + Vector3.new(0, 0.45, 0),
		Color3.fromRGB(30, 28, 26),
		Enum.Material.Metal,
		DETAIL
	)
	local bulb = box(model, "Glass", Vector3.new(0.45, 0.6, 0.45), pos, C.bulb, Enum.Material.Neon, DETAIL)
	bulb.Shape = Enum.PartType.Ball
	pointLight(bulb, range, brightness, shadows)
	return model, bulb
end

-- Wall-mounted caged work light (faces +Z of `cf`).
local function cagedLight(parent: Instance, cf: CFrame, range: number, brightness: number)
	local model = folder(parent, "CagedLight")
	box(model, "Mount", Vector3.new(0.6, 0.6, 0.3), cf, C.steel, Enum.Material.Metal, DETAIL)
	local bulb =
		box(model, "Bulb", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, 0, 0.5), C.bulb, Enum.Material.Neon, DETAIL)
	bulb.Shape = Enum.PartType.Ball
	for _, a in { 0, 90 } do
		box(
			model,
			"Cage",
			Vector3.new(0.08, 0.8, 0.8),
			cf * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, 0, math.rad(a)),
			Color3.fromRGB(30, 30, 30),
			Enum.Material.Metal,
			DETAIL
		)
	end
	pointLight(bulb, range, brightness, false)
	return model
end

------------------------------------------------------------------------------------------
-- Shell: concrete floor, cinderblock walls, joists, girder + posts, ducts, pipes, stairwell
------------------------------------------------------------------------------------------
local STAIR = { x0 = 24, x1 = 50, z0 = 60, z1 = HALF_Z } -- opening in the ceiling over the stairs

local function buildShell(root: Instance)
	local shell = folder(root, "Shell")
	local W, D = HALF_X * 2, HALF_Z * 2
	box(shell, "Floor", Vector3.new(W + 4, 2, D + 4), Vector3.new(0, -1, 0), C.concrete, Enum.Material.Concrete)

	-- ceiling with a hole for the stairwell
	local function ceiling(x0, x1, z0, z1)
		box(
			shell,
			"Ceiling",
			Vector3.new(x1 - x0, 1, z1 - z0),
			Vector3.new((x0 + x1) / 2, CEILING + 0.5, (z0 + z1) / 2),
			C.joist,
			Enum.Material.WoodPlanks
		)
	end
	ceiling(-HALF_X - 2, STAIR.x0, -HALF_Z - 2, HALF_Z + 2)
	ceiling(STAIR.x0, HALF_X + 2, -HALF_Z - 2, STAIR.z0)

	-- cinderblock walls with a grime band and a few water stains
	local wallH = CEILING + 1
	for _, s in { -1, 1 } do
		box(
			shell,
			"WallX",
			Vector3.new(2, wallH, D + 4),
			Vector3.new(s * (HALF_X + 1), wallH / 2, 0),
			C.block,
			Enum.Material.Brick
		)
		box(
			shell,
			"WallZ",
			Vector3.new(W + 4, wallH, 2),
			Vector3.new(0, wallH / 2, s * (HALF_Z + 1)),
			C.block,
			Enum.Material.Brick
		)
		box(
			shell,
			"GrimeX",
			Vector3.new(0.2, 1.4, D),
			Vector3.new(s * (HALF_X - 0.1), 0.7, 0),
			C.blockLow,
			Enum.Material.Concrete,
			DETAIL
		)
		box(
			shell,
			"GrimeZ",
			Vector3.new(W, 1.4, 0.2),
			Vector3.new(0, 0.7, s * (HALF_Z - 0.1)),
			C.blockLow,
			Enum.Material.Concrete,
			DETAIL
		)
	end
	for _, spec in { { -1, 22, 5 }, { -1, -12, 3 }, { 1, 0, 4 }, { 1, -52, 6 } } do
		box(
			shell,
			"WaterStain",
			Vector3.new(0.1, spec[3] * 1.6, spec[3]),
			Vector3.new(spec[1] * (HALF_X - 0.05), CEILING - spec[3] * 0.8, spec[2]),
			Color3.fromRGB(90, 84, 70),
			Enum.Material.Concrete,
			{
				Transparency = 0.45,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
	end

	-- floor joists every 3 studs, running side to side
	for z = -HALF_Z + 1.5, HALF_Z - 1.5, 3 do
		local overStairs = z > STAIR.z0 and z < STAIR.z1
		local x1 = overStairs and STAIR.x0 or HALF_X
		box(
			shell,
			"Joist",
			Vector3.new(x1 + HALF_X, 1.2, 0.5),
			Vector3.new((x1 - HALF_X) / 2, CEILING - 0.6, z),
			C.joist,
			Enum.Material.Wood,
			DETAIL
		)
	end

	-- steel girder down the middle, carried by rust-red lally columns
	box(
		shell,
		"Girder",
		Vector3.new(1.2, 1.4, D),
		Vector3.new(0, CEILING - 1.9, 0),
		C.steel,
		Enum.Material.Metal,
		{ CanCollide = false }
	)
	box(
		shell,
		"GirderFlange",
		Vector3.new(2, 0.2, D),
		Vector3.new(0, CEILING - 2.6, 0),
		C.steel,
		Enum.Material.Metal,
		DETAIL
	)
	for _, z in { 50, 26, 2, -22, -46 } do
		box(
			shell,
			"LallyColumn",
			Vector3.new(CEILING - 2.7, 0.7, 0.7),
			CFrame.new(0, (CEILING - 2.7) / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
			C.rust,
			Enum.Material.Metal,
			{
				Shape = Enum.PartType.Cylinder,
			}
		)
		box(
			shell,
			"ColumnPlate",
			Vector3.new(1.4, 0.2, 1.4),
			Vector3.new(0, 0.1, z),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
	end

	-- HVAC duct and pipes along the length (cylinders run along X by default; yaw 90 to run along Z)
	local alongZ = CFrame.Angles(0, math.rad(90), 0)
	box(
		shell,
		"Duct",
		Vector3.new(3.2, 2, D - 30),
		Vector3.new(-9, CEILING - 2.2, -15),
		C.duct,
		Enum.Material.Metal,
		{ CanCollide = false }
	)
	for z = -40, 50, 15 do
		box(
			shell,
			"DuctSeam",
			Vector3.new(3.4, 2.2, 0.2),
			Vector3.new(-9, CEILING - 2.2, z),
			Color3.fromRGB(120, 120, 116),
			Enum.Material.Metal,
			DETAIL
		)
	end
	box(
		shell,
		"DuctBranch",
		Vector3.new(28, 1.6, 2.4),
		Vector3.new(-25, CEILING - 2.2, 10),
		C.duct,
		Enum.Material.Metal,
		DETAIL
	)
	for _, spec in
		{
			{ 9, CEILING - 1.8, 0.8, C.pipe, HALF_Z },
			{ 10.4, CEILING - 1.7, 0.5, C.pipe, HALF_Z },
			{ 30, CEILING - 1.6, 1.1, C.steel, STAIR.z0 - 1 }, -- turns up into the floor above before the stairwell
		}
	do
		local zEnd = spec[5]
		box(
			shell,
			"Pipe",
			Vector3.new(zEnd + HALF_Z, spec[3], spec[3]),
			CFrame.new(spec[1], spec[2], (zEnd - HALF_Z) / 2) * alongZ,
			spec[4],
			Enum.Material.Metal,
			{
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
				CastShadow = false,
			}
		)
	end
	box(
		shell,
		"PipeElbow",
		Vector3.new(0.9 + 1.1, 1.1, 1.1),
		CFrame.new(30, CEILING - 0.9, STAIR.z0 - 1) * CFrame.Angles(0, 0, math.rad(90)),
		C.steel,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		}
	)
	-- pipe across the back wall, above the doors
	box(
		shell,
		"BackPipe",
		Vector3.new(W, 0.7, 0.7),
		CFrame.new(0, CEILING - 1.7, -HALF_Z + 0.8),
		C.pipe,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		}
	)

	-- window wells high on both side walls: thin cold moonlight against the warm bulbs
	for _, s in { -1, 1 } do
		for _, z in { -36, 22 } do
			local glass = box(
				shell,
				"WindowWell",
				Vector3.new(0.3, 2.2, 5),
				Vector3.new(s * (HALF_X - 0.15), CEILING - 2, z),
				C.window,
				Enum.Material.Glass,
				{
					Transparency = 0.2,
					CanCollide = false,
				}
			)
			box(
				shell,
				"WindowFrame",
				Vector3.new(0.5, 2.8, 5.6),
				Vector3.new(s * (HALF_X - 0.05), CEILING - 2, z),
				C.darkWood,
				Enum.Material.Wood,
				DETAIL
			)
			local light = Instance.new("SurfaceLight")
			light.Face = s < 0 and Enum.NormalId.Right or Enum.NormalId.Left
			light.Color = Color3.fromRGB(120, 150, 215)
			light.Brightness = 0.7
			light.Range = 14
			light.Angle = 70
			light.Parent = glass
		end
	end
end

------------------------------------------------------------------------------------------
-- Stairs: open wooden stairs down from the ground floor door
------------------------------------------------------------------------------------------
local function buildStairs(root: Instance)
	local stairs = folder(root, "Stairs")
	local zA, zB = 62, 68 -- tread width
	local zc = (zA + zB) / 2
	local steps, run = 15, 1.2
	local xBottom = STAIR.x0 + 2
	for i = 1, steps do
		local x = xBottom + (i - 0.5) * run
		box(
			stairs,
			"Tread",
			Vector3.new(run + 0.1, 0.3, zB - zA),
			Vector3.new(x, i - 0.15, zc),
			C.midWood,
			Enum.Material.WoodPlanks
		)
	end
	local xTop = xBottom + steps * run
	box(
		stairs,
		"Landing",
		Vector3.new(HALF_X - xTop, 1, zB - zA + 2),
		Vector3.new((xTop + HALF_X) / 2, CEILING - 0.5, zc),
		C.midWood,
		Enum.Material.WoodPlanks
	)

	-- stringers + railing along the open side
	local bottom, top = Vector3.new(xBottom, 0, zA - 0.2), Vector3.new(xTop, steps, zA - 0.2)
	local mid, len = (bottom + top) / 2, (top - bottom).Magnitude
	for _, dz in { 0, zB - zA + 0.4 } do
		box(
			stairs,
			"Stringer",
			Vector3.new(0.3, 1, len),
			CFrame.lookAt(mid + Vector3.new(0, 0, dz), top + Vector3.new(0, 0, dz)),
			C.darkWood,
			Enum.Material.Wood
		)
	end
	box(
		stairs,
		"Handrail",
		Vector3.new(0.3, 0.3, len),
		CFrame.lookAt(mid + Vector3.new(0, 3.2, -0.3), top + Vector3.new(0, 3.2, -0.3)),
		C.wood,
		Enum.Material.Wood
	)
	for i = 0, 5 do
		local p = bottom:Lerp(top, i / 5) + Vector3.new(0, 1.6, -0.3)
		box(stairs, "Post", Vector3.new(0.25, 3.2, 0.25), p, C.darkWood, Enum.Material.Wood, DETAIL)
	end

	-- the stairwell shaft above the ceiling, lit from the house upstairs
	local shaftTop = CEILING + 12
	box(
		stairs,
		"ShaftWall",
		Vector3.new(HALF_X - STAIR.x0 + 2, shaftTop - CEILING, 1),
		Vector3.new((STAIR.x0 + HALF_X) / 2 + 1, (CEILING + shaftTop) / 2, STAIR.z0 - 0.5),
		C.block,
		Enum.Material.Plaster
	)
	box(
		stairs,
		"ShaftWall",
		Vector3.new(1, shaftTop - CEILING, STAIR.z1 - STAIR.z0 + 2),
		Vector3.new(STAIR.x0 - 0.5, (CEILING + shaftTop) / 2, (STAIR.z0 + STAIR.z1) / 2),
		C.block,
		Enum.Material.Plaster
	)
	box(
		stairs,
		"ShaftWall",
		Vector3.new(1, shaftTop - CEILING, STAIR.z1 - STAIR.z0 + 2),
		Vector3.new(HALF_X + 0.5, (CEILING + shaftTop) / 2, (STAIR.z0 + STAIR.z1) / 2),
		C.block,
		Enum.Material.Plaster
	)
	box(
		stairs,
		"ShaftWall",
		Vector3.new(HALF_X - STAIR.x0 + 2, shaftTop - CEILING, 1),
		Vector3.new((STAIR.x0 + HALF_X) / 2 + 1, (CEILING + shaftTop) / 2, STAIR.z1 + 0.5),
		C.block,
		Enum.Material.Plaster
	)
	box(
		stairs,
		"ShaftCeiling",
		Vector3.new(HALF_X - STAIR.x0 + 2, 1, STAIR.z1 - STAIR.z0 + 2),
		Vector3.new((STAIR.x0 + HALF_X) / 2 + 1, shaftTop + 0.5, (STAIR.z0 + STAIR.z1) / 2),
		C.block,
		Enum.Material.Plaster
	)
	box(
		stairs,
		"UpstairsDoor",
		Vector3.new(0.4, 8, 4),
		Vector3.new(HALF_X - 0.2, CEILING + 4, zc),
		C.darkWood,
		Enum.Material.Wood
	)
	box(
		stairs,
		"DoorFrame",
		Vector3.new(0.3, 8.6, 4.8),
		Vector3.new(HALF_X - 0.05, CEILING + 4.3, zc),
		C.wood,
		Enum.Material.Wood,
		DETAIL
	)
	bareBulb(stairs, Vector3.new(40, shaftTop - 2.5, zc), 26, 1.8, true)

	-- clutter under the stairs
	for i, spec in { { 30, 1.5, 65, 3 }, { 33.2, 1.25, 64.2, 2.5 }, { 30.4, 3.6, 65.2, 1.5 } } do
		box(
			stairs,
			"Box",
			Vector3.new(spec[4], spec[4], spec[4]),
			CFrame.new(spec[1], spec[2], spec[3]) * CFrame.Angles(0, math.rad(i * 13), 0),
			C.cardboard,
			Enum.Material.Cardboard
		)
	end

	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "Spawn"
	spawnPoint.Anchored = true
	spawnPoint.Size = Vector3.new(4, 0.2, 4)
	-- on the landing, facing -X so players look down the stairs into the basement
	spawnPoint.CFrame = CFrame.new((xTop + HALF_X) / 2, CEILING + 0.1, zc) * CFrame.Angles(0, math.rad(90), 0)
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.CanQuery = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = stairs
end

------------------------------------------------------------------------------------------
-- Shelving: wooden bookcases and metal racks of boxed books
------------------------------------------------------------------------------------------
local function fillBooks(parent: Instance, at, length: number, y: number, zCenter: number, depth: number)
	local x = -length / 2 + 0.2
	while x < length / 2 - 0.4 do
		local width = math.min(rng:NextNumber(1.1, 3.0), length / 2 - 0.2 - x)
		local roll = rng:NextNumber()
		if roll > 0.12 then
			local h = rng:NextNumber(1.3, 2.0)
			local lean = roll > 0.92 and math.rad(rng:NextNumber(-14, 14)) or 0
			box(
				parent,
				"Books",
				Vector3.new(width - 0.05, h, depth),
				at(x + width / 2, y + h / 2, zCenter) * CFrame.Angles(0, 0, lean),
				BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)],
				Enum.Material.Fabric,
				DETAIL
			)
		end
		x += width
	end
end

-- Bookcase centered at `cf` (base on floor), long along local X, books facing local +Z (and -Z if doubleSided).
local function bookcase(
	parent: Instance,
	cf: CFrame,
	length: number,
	height: number,
	depth: number,
	doubleSided: boolean
)
	local unit = folder(parent, "Bookcase")
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
			Vector3.new(0.5, height, depth),
			at(s * (length / 2 + 0.25), height / 2, 0),
			C.wood,
			Enum.Material.Wood
		)
	end
	box(unit, "Top", Vector3.new(length + 1, 0.4, depth + 0.2), at(0, height + 0.2, 0), C.wood, Enum.Material.Wood)
	box(unit, "Plinth", Vector3.new(length, 0.5, depth), at(0, 0.25, 0), C.darkWood, Enum.Material.Wood)
	local levels = math.floor((height - 0.5) / 2.4)
	for level = 0, levels - 1 do
		local y = 0.5 + level * 2.4
		if level > 0 then
			box(
				unit,
				"Shelf",
				Vector3.new(length, 0.2, depth),
				at(0, y, 0),
				C.wood,
				Enum.Material.Wood,
				{ CastShadow = false }
			)
		end
		local y0 = y + 0.1
		if doubleSided then
			local bookDepth = depth / 2 - 0.45
			for _, side in { 1, -1 } do
				fillBooks(unit, at, length, y0, side * (0.15 + bookDepth / 2 + 0.1), bookDepth)
			end
		else
			fillBooks(unit, at, length, y0, 0.25, depth - 0.7)
		end
	end
	-- odd things on top: a box, a book pile
	if rng:NextNumber() > 0.4 then
		box(
			unit,
			"Box",
			Vector3.new(2, 1.4, 1.6),
			at(rng:NextNumber(-length / 3, length / 3), height + 1.1, 0),
			C.cardboard,
			Enum.Material.Cardboard
		)
	end
	return unit
end

-- Steel utility rack with cardboard boxes of books and loose piles.
local function metalRack(parent: Instance, cf: CFrame, length: number, height: number, depth: number)
	local unit = folder(parent, "Rack")
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				unit,
				"Upright",
				Vector3.new(0.25, height, 0.25),
				at(sx * length / 2, height / 2, sz * depth / 2),
				C.steel,
				Enum.Material.Metal
			)
		end
	end
	for i = 0, 3 do
		local y = 0.4 + i * (height - 0.6) / 3
		box(
			unit,
			"Shelf",
			Vector3.new(length, 0.15, depth),
			at(0, y, 0),
			Color3.fromRGB(88, 88, 88),
			Enum.Material.DiamondPlate
		)
		local x = -length / 2 + 0.3
		while x < length / 2 - 1 do
			local w = math.min(rng:NextNumber(1.6, 2.6), length / 2 - 0.3 - x)
			local roll = rng:NextNumber()
			if roll < 0.55 then
				local h = rng:NextNumber(1.1, 1.6)
				box(
					unit,
					"Box",
					Vector3.new(w - 0.1, h, depth - 0.3),
					at(x + w / 2, y + 0.08 + h / 2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0),
					C.cardboard:Lerp(Color3.new(0.3, 0.25, 0.2), rng:NextNumber(0, 0.4)),
					Enum.Material.Cardboard,
					DETAIL
				)
			elseif roll < 0.85 then
				local pile = rng:NextInteger(2, 5)
				for k = 1, pile do
					box(
						unit,
						"Book",
						Vector3.new(w * 0.7, 0.28, depth * 0.6),
						at(x + w / 2, y + 0.08 + (k - 0.5) * 0.29, 0)
							* CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0),
						BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)],
						Enum.Material.Fabric,
						DETAIL
					)
				end
			end
			x += w
		end
	end
	return unit
end

local function bookPile(parent: Instance, pos: Vector3, count: number)
	for k = 1, count do
		box(
			parent,
			"FloorBook",
			Vector3.new(rng:NextNumber(1.2, 1.7), 0.3, rng:NextNumber(0.9, 1.2)),
			CFrame.new(pos + Vector3.new(0, (k - 0.5) * 0.31, 0))
				* CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0),
			BOOK_COLORS[rng:NextInteger(1, #BOOK_COLORS)],
			Enum.Material.Fabric,
			DETAIL
		)
	end
end

local function buildStacks(root: Instance)
	local stacks = folder(root, "Stacks")
	-- rows either side of the walkway; bookcases and racks alternate irregularly
	local function row(x: number, z: number)
		local cf = CFrame.new(x, 0, z)
		if rng:NextNumber() < 0.68 then
			bookcase(stacks, cf, 13, 9.4, 3, true)
		else
			metalRack(stacks, cf, 13, 8, 2.6)
		end
	end
	for _, s in { -1, 1 } do
		for _, z in { 44, 32, 20, 8, -4, -16 } do
			row(s * 15, z)
		end
		for _, z in { 26, 14, 2 } do
			row(s * 33, z)
		end
	end
	-- single-sided bookcases against the walls
	local faceRight, faceLeft, faceBack =
		CFrame.Angles(0, math.rad(90), 0), CFrame.Angles(0, math.rad(-90), 0), CFrame.Angles(0, math.rad(180), 0)
	bookcase(stacks, CFrame.new(-HALF_X + 1.4, 0, 14) * faceRight, 22, 11, 2.4, false)
	bookcase(stacks, CFrame.new(HALF_X - 1.4, 0, 10) * faceLeft, 20, 11, 2.4, false)
	bookcase(stacks, CFrame.new(-6, 0, HALF_Z - 1.4) * faceBack, 16, 11, 2.4, false)
	metalRack(stacks, CFrame.new(10, 0, HALF_Z - 1.6) * faceBack, 10, 8, 2.4)

	for _, p in
		{
			Vector3.new(-6, 0, 38),
			Vector3.new(7, 0, 14),
			Vector3.new(-24, 0, 26),
			Vector3.new(24, 0, -10),
			Vector3.new(-7, 0, -22),
			Vector3.new(41, 0, 20),
		}
	do
		bookPile(stacks, p, rng:NextInteger(3, 7))
	end

	-- bulbs: down the walkway (with shadows) and over the gaps between rows
	for _, z in { 56, 44, 32, 20, 8, -4, -16, -28 } do
		bareBulb(stacks, Vector3.new(2.2, CEILING - 4.2, z + 6), 18, 1.1, true)
	end
	for _, s in { -1, 1 } do
		for _, z in { 38, 14, -10 } do
			bareBulb(stacks, Vector3.new(s * 15, CEILING - 3.6, z), 15, 0.8, false)
		end
		for _, z in { 20, 8 } do
			bareBulb(stacks, Vector3.new(s * 33, CEILING - 3.6, z), 14, 0.7, false)
		end
	end

	-- worn rugs overlapping down the walkway
	for i, spec in
		{
			{ 50, 9, 12, 0.05 },
			{ 34, 8, 14, -0.04 },
			{ 16, 9, 12, 0.03 },
			{ -2, 8, 13, -0.06 },
			{ -20, 9, 12, 0.04 },
			{ -36, 8, 12, 0 },
		}
	do
		local color = (i % 2 == 0) and Color3.fromRGB(78, 34, 28) or Color3.fromRGB(88, 64, 40)
		box(
			stacks,
			"Rug",
			Vector3.new(spec[2], 0.06 + i * 0.005, spec[3]),
			CFrame.new(0, 0.03 + i * 0.005, spec[1]) * CFrame.Angles(0, spec[4], 0),
			color,
			Enum.Material.Carpet,
			{ CanCollide = false, CastShadow = false }
		)
		box(
			stacks,
			"RugBorder",
			Vector3.new(spec[2] + 0.6, 0.05 + i * 0.005, spec[3] + 0.6),
			CFrame.new(0, 0.025 + i * 0.005, spec[1]) * CFrame.Angles(0, spec[4], 0),
			Color3.fromRGB(60, 30, 22),
			Enum.Material.Carpet,
			DETAIL
		)
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

local function armchair(parent: Instance, cf: CFrame, color: Color3)
	local model = folder(parent, "Armchair")
	box(model, "Seat", Vector3.new(3.2, 1.6, 3), cf * CFrame.new(0, 1, 0), color, Enum.Material.Fabric)
	box(model, "Back", Vector3.new(3.2, 3, 0.8), cf * CFrame.new(0, 2.3, 1.2), color, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		box(model, "Arm", Vector3.new(0.6, 2.1, 3), cf * CFrame.new(s * 1.6, 1.3, 0), color, Enum.Material.Fabric)
	end
end

local function deskLamp(parent: Instance, pos: Vector3, range: number?)
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
		C.bulb,
		Enum.Material.Neon,
		DETAIL
	)
	pointLight(shade, range or 9, 1, false)
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
	deskLamp(model, (cf * CFrame.new(1.8, 3.18, 0)).Position)
	bookPile(model, (cf * CFrame.new(-1.6, 3.18, 0.3)).Position, 3)
	for _, side in { -1, 1 } do
		chair(model, (cf * CFrame.new(-1.6, 0, side * 2.6)).Position, yaw + (side > 0 and 0 or math.pi))
		chair(model, (cf * CFrame.new(1.6, 0, side * 2.6)).Position, yaw + (side > 0 and 0 or math.pi))
	end
end

------------------------------------------------------------------------------------------
-- Areas
------------------------------------------------------------------------------------------
local function buildShop(root: Instance)
	local shop = folder(root, "Shop")
	local cx, cz = -30, 56
	-- old wooden desk used as a checkout counter, facing the walkway (+X)
	box(shop, "DeskBody", Vector3.new(3, 3.4, 10), Vector3.new(cx, 1.7, cz), C.wood, Enum.Material.Wood)
	local top =
		box(shop, "DeskTop", Vector3.new(3.6, 0.3, 10.6), Vector3.new(cx, 3.55, cz), C.midWood, Enum.Material.Wood)
	for i = -1, 1 do
		box(
			shop,
			"Drawer",
			Vector3.new(0.15, 1.2, 2.6),
			Vector3.new(cx + 1.55, 2.2, cz + i * 3.2),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			shop,
			"Pull",
			Vector3.new(0.2, 0.2, 0.7),
			Vector3.new(cx + 1.65, 2.2, cz + i * 3.2),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	-- card catalog cabinet behind the desk
	local catX = cx - 4.5
	box(shop, "CatalogBody", Vector3.new(2.6, 6, 8), Vector3.new(catX, 3, cz), C.midWood, Enum.Material.Wood)
	for row = 0, 6 do
		for col = 0, 4 do
			local y, z = 0.9 + row * 0.75, cz - 3.2 + col * 1.6
			box(
				shop,
				"CatalogDrawer",
				Vector3.new(0.12, 0.62, 1.45),
				Vector3.new(catX + 1.31, y, z),
				C.wood,
				Enum.Material.Wood,
				DETAIL
			)
			box(
				shop,
				"Label",
				Vector3.new(0.05, 0.2, 0.5),
				Vector3.new(catX + 1.39, y + 0.1, z),
				Color3.fromRGB(220, 210, 180),
				nil,
				DETAIL
			)
		end
	end
	-- desk clutter: cash box, bell, ledger, lamp
	box(
		shop,
		"CashBox",
		Vector3.new(1.2, 0.6, 1.6),
		Vector3.new(cx - 0.2, 4, cz - 2.5),
		Color3.fromRGB(60, 80, 64),
		Enum.Material.Metal,
		DETAIL
	)
	box(
		shop,
		"Bell",
		Vector3.new(0.5, 0.35, 0.5),
		Vector3.new(cx + 1, 3.88, cz + 0.5),
		C.brass,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball, CanCollide = false }
	)
	box(
		shop,
		"Ledger",
		Vector3.new(1.4, 0.2, 2),
		Vector3.new(cx + 0.2, 3.8, cz + 2.2),
		Color3.fromRGB(80, 30, 26),
		Enum.Material.Fabric,
		DETAIL
	)
	deskLamp(shop, Vector3.new(cx - 0.6, 3.7, cz + 4))

	-- hand-painted plank sign hanging from the joists
	local sign = box(
		shop,
		"Sign",
		Vector3.new(0.3, 1.8, 7),
		Vector3.new(cx + 1, 10.5, cz),
		C.midWood,
		Enum.Material.WoodPlanks,
		DETAIL
	)
	for _, dz in { -3, 3 } do
		box(
			shop,
			"SignChain",
			Vector3.new(0.08, CEILING - 11.4, 0.08),
			Vector3.new(cx + 1, (CEILING + 11.4) / 2, cz + dz),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
	end
	surfaceText(sign, Enum.NormalId.Right, "SHOP", Enum.Font.SpecialElite, Color3.fromRGB(40, 26, 18))
	surfaceText(sign, Enum.NormalId.Left, "SHOP", Enum.Font.SpecialElite, Color3.fromRGB(40, 26, 18))
	bareBulb(shop, Vector3.new(cx + 2.5, 9, cz - 3), 18, 1.2, true)
	prompt(top, "Checkout Desk", "Browse Shop", "Shop")
end

local function buildWorkbench(root: Instance)
	local bench = folder(root, "LanternBench")
	local wx, cz = -HALF_X, 40
	local benchX = wx + 2.2
	-- heavy workbench against the left wall
	local top =
		box(bench, "Top", Vector3.new(4, 0.5, 12), Vector3.new(benchX, 3.25, cz), C.midWood, Enum.Material.WoodPlanks)
	for _, dz in { -5.6, 5.6 } do
		for _, dx in { -1.6, 1.6 } do
			box(
				bench,
				"Leg",
				Vector3.new(0.5, 3, 0.5),
				Vector3.new(benchX + dx, 1.5, cz + dz),
				C.darkWood,
				Enum.Material.Wood
			)
		end
	end
	box(bench, "LowerShelf", Vector3.new(3.6, 0.3, 11.4), Vector3.new(benchX, 0.8, cz), C.wood, Enum.Material.Wood)
	box(
		bench,
		"Toolbox",
		Vector3.new(1.6, 1, 2.6),
		Vector3.new(benchX, 1.45, cz - 3),
		C.redPaint,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		bench,
		"Vise",
		Vector3.new(1, 0.8, 0.8),
		Vector3.new(benchX + 1.6, 3.9, cz + 5),
		Color3.fromRGB(50, 70, 90),
		Enum.Material.Metal,
		DETAIL
	)

	-- pegboard with lanterns hanging on hooks
	local board = box(
		bench,
		"Pegboard",
		Vector3.new(0.2, 6, 12),
		Vector3.new(wx + 0.2, 7.5, cz),
		Color3.fromRGB(150, 116, 80),
		Enum.Material.Wood
	)
	board.CastShadow = false
	local count = #Lanterns.List
	for i, def in Lanterns.List do
		local z = cz - 4.8 + (i - 1) * (9.6 / math.max(count - 1, 1))
		local hookY = 9.6
		box(
			bench,
			"Hook",
			Vector3.new(0.9, 0.1, 0.1),
			Vector3.new(wx + 0.75, hookY, z),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
		local lantern = LanternBuilder.buildModel(def.id, true)
		-- ring centre sits on the hook; lantern hangs below, off the board
		lantern:PivotTo(CFrame.new(wx + 1.1, hookY - 2.4, z) * CFrame.Angles(0, math.rad(90), 0))
		local light = lantern:FindFirstChild("Light", true)
		if light then
			light.Brightness *= 0.3
			light.Range = 7
			light.Shadows = false
		end
		lantern.Parent = bench
	end
	cagedLight(
		bench,
		CFrame.new(wx + 0.3, 11.5, cz) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-30), 0, 0),
		16,
		1
	)

	local sign = box(
		bench,
		"Sign",
		Vector3.new(0.1, 1.2, 6),
		Vector3.new(wx + 0.35, 12.8, cz),
		C.paint,
		Enum.Material.Plaster,
		DETAIL
	)
	surfaceText(sign, Enum.NormalId.Right, "LANTERNS", Enum.Font.SpecialElite, Color3.fromRGB(40, 30, 24))
	prompt(top, "Workbench", "Customize Lantern", "Lanterns")
end

local function buildReadingNook(root: Instance)
	local nook = folder(root, "Reading")
	local cx, cz = -40, -34
	box(
		nook,
		"Rug",
		Vector3.new(12, 0.08, 10),
		Vector3.new(cx, 0.04, cz),
		Color3.fromRGB(92, 44, 32),
		Enum.Material.Carpet,
		{ CanCollide = false }
	)
	armchair(nook, CFrame.new(cx - 3, 0, cz + 2) * CFrame.Angles(0, math.rad(200), 0), Color3.fromRGB(96, 70, 46))
	armchair(nook, CFrame.new(cx + 3, 0, cz + 2) * CFrame.Angles(0, math.rad(160), 0), Color3.fromRGB(70, 40, 36))
	box(nook, "SideTable", Vector3.new(1.8, 2.2, 1.8), Vector3.new(cx, 1.1, cz + 3.5), C.darkWood, Enum.Material.Wood)
	deskLamp(nook, Vector3.new(cx, 2.2, cz + 3.5), 12)
	box(
		nook,
		"FloorLampPole",
		Vector3.new(0.25, 6, 0.25),
		Vector3.new(cx - 6, 3, cz - 3),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local shade = box(
		nook,
		"FloorLampShade",
		Vector3.new(1.6, 1.2, 1.6),
		Vector3.new(cx - 6, 6.5, cz - 3),
		Color3.fromRGB(230, 190, 140),
		Enum.Material.Fabric,
		DETAIL
	)
	pointLight(shade, 14, 0.9, true)
	bookPile(nook, Vector3.new(cx + 5, 0, cz - 3), 6)
	bookPile(nook, Vector3.new(cx + 6.2, 0, cz - 1.6), 4)

	readingTable(nook, Vector3.new(-22, 0, -32), 0)
	readingTable(nook, Vector3.new(22, 0, -32), 0)
end

local function buildFurnace(root: Instance)
	local corner = folder(root, "Furnace")
	local fx, fz = HALF_X - 5, -32
	box(corner, "Body", Vector3.new(6, 7, 5), Vector3.new(fx, 3.5, fz), Color3.fromRGB(58, 56, 52), Enum.Material.Metal)
	local grate = box(
		corner,
		"Grate",
		Vector3.new(0.1, 1.6, 2.4),
		Vector3.new(fx - 3.05, 2, fz),
		Color3.fromRGB(255, 110, 40),
		Enum.Material.Neon,
		DETAIL
	)
	for i = -2, 2 do
		box(
			corner,
			"GrateBar",
			Vector3.new(0.12, 1.7, 0.12),
			Vector3.new(fx - 3.1, 2, fz + i * 0.5),
			Color3.fromRGB(30, 28, 26),
			Enum.Material.Metal,
			DETAIL
		)
	end
	local glow = pointLight(grate, 18, 1.4, true, Color3.fromRGB(255, 120, 50))
	glow:SetAttribute("Flicker", "furnace")
	box(
		corner,
		"Flue",
		Vector3.new(CEILING - 7, 1.4, 1.4),
		CFrame.new(fx, (CEILING + 7) / 2, fz) * CFrame.Angles(0, 0, math.rad(90)),
		C.steel,
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	box(
		corner,
		"WaterHeater",
		Vector3.new(6, 3, 3),
		CFrame.new(fx + 1, 3, fz - 7) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(190, 186, 176),
		Enum.Material.Metal,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	box(
		corner,
		"FuseBox",
		Vector3.new(0.4, 2.4, 1.8),
		Vector3.new(HALF_X - 0.2, 6, fz + 7),
		Color3.fromRGB(120, 120, 114),
		Enum.Material.Metal,
		DETAIL
	)
	box(
		corner,
		"Drain",
		Vector3.new(1, 0.04, 1),
		Vector3.new(fx - 6, 0.02, fz - 4),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.DiamondPlate,
		DETAIL
	)
end

local function buildLeaderboard(root: Instance)
	local board = folder(root, "Leaderboard")
	local pos = Vector3.new(HALF_X - 0.25, 7.5, 40)
	local face = box(board, "Board", Vector3.new(0.3, 7, 14), pos, C.chalkboard, Enum.Material.Slate)
	for _, dz in { -7.2, 7.2 } do
		box(
			board,
			"Frame",
			Vector3.new(0.5, 7.6, 0.4),
			pos + Vector3.new(-0.1, 0, dz),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for _, dy in { -3.7, 3.7 } do
		box(
			board,
			"Frame",
			Vector3.new(0.5, 0.4, 14.8),
			pos + Vector3.new(-0.1, dy, 0),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	box(
		board,
		"Ledge",
		Vector3.new(0.8, 0.15, 14),
		pos + Vector3.new(-0.5, -3.85, 0),
		C.wood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		board,
		"Chalk",
		Vector3.new(0.2, 0.15, 0.6),
		pos + Vector3.new(-0.6, -3.7, 3),
		Color3.fromRGB(235, 235, 225),
		nil,
		DETAIL
	)
	cagedLight(
		board,
		CFrame.new(HALF_X - 0.2, 12.2, 40) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(math.rad(-35), 0, 0),
		14,
		1
	)
	for _, z in { 36, 44 } do
		chair(board, Vector3.new(HALF_X - 9, 0, z), math.rad(-90))
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.8
	gui.Parent = face
	local chalk = Color3.fromRGB(232, 232, 220)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.03)
	title.Size = UDim2.fromScale(1, 0.14)
	title.Font = Enum.Font.IndieFlower
	title.TextScaled = true
	title.TextColor3 = chalk
	title.Text = "hall of records"
	title.Parent = gui

	for col, spec in { { "Keys", "most " .. string.lower(Config.CurrencyName) }, { "Trials", "trials survived" } } do
		local column = Instance.new("Frame")
		column.Name = spec[1]
		column.BackgroundTransparency = 1
		column.Position = UDim2.fromScale((col - 1) * 0.5 + 0.04, 0.19)
		column.Size = UDim2.fromScale(0.42, 0.78)
		column.Parent = gui
		local heading = Instance.new("TextLabel")
		heading.Name = "Heading"
		heading.BackgroundTransparency = 1
		heading.Size = UDim2.fromScale(1, 0.11)
		heading.Font = Enum.Font.IndieFlower
		heading.TextScaled = true
		heading.TextColor3 = Color3.fromRGB(240, 220, 150)
		heading.Text = spec[2]
		heading.Parent = column
		for row = 1, 10 do
			local label = Instance.new("TextLabel")
			label.Name = "Row" .. row
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0, 0.13 + (row - 1) * 0.087)
			label.Size = UDim2.fromScale(1, 0.08)
			label.Font = Enum.Font.IndieFlower
			label.TextScaled = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = chalk
			label.Text = string.format("%d.  ---", row)
			label.Parent = column
		end
	end
end

------------------------------------------------------------------------------------------
-- Door wall: six mismatched doors that shouldn't be in a basement
------------------------------------------------------------------------------------------
local DOOR_STYLES = {
	{ color = Color3.fromRGB(64, 40, 28), material = Enum.Material.Wood, panels = true }, -- old panel door
	{ color = Color3.fromRGB(110, 112, 110), material = Enum.Material.Metal, bar = true }, -- steel utility door
	{ color = Color3.fromRGB(70, 96, 72), material = Enum.Material.WoodPlanks, panels = true }, -- faded green
	{ color = Color3.fromRGB(70, 82, 104), material = Enum.Material.WoodPlanks, panels = true }, -- faded blue
	{ color = Color3.fromRGB(120, 116, 104), material = Enum.Material.Metal, bar = true },
	{ color = Color3.fromRGB(110, 40, 32), material = Enum.Material.Wood, panels = true }, -- red
}

local function buildPad(parent: Instance, queue: Instance, wing: string, mode: string, x: number, style)
	local spec = Config.Modes[mode]
	local pad = folder(parent, wing .. "_" .. mode)
	pad:SetAttribute("Mode", mode)
	pad:SetAttribute("Capacity", spec.capacity)
	pad:SetAttribute("Count", 0)
	pad:SetAttribute("TimeLeft", 0)
	local wallZ = -HALF_Z

	-- door set into the block wall
	for _, s in { -1, 1 } do
		box(
			pad,
			"Jamb",
			Vector3.new(0.6, 9, 0.8),
			Vector3.new(x + s * 2.9, 4.5, wallZ + 0.4),
			C.wood,
			Enum.Material.Wood
		)
	end
	box(pad, "Header", Vector3.new(6.4, 0.6, 0.8), Vector3.new(x, 9.3, wallZ + 0.4), C.wood, Enum.Material.Wood)
	box(pad, "Door", Vector3.new(5.2, 9, 0.3), Vector3.new(x, 4.5, wallZ + 0.15), style.color, style.material)
	if style.panels then
		for _, dy in { 2.4, 6.6 } do
			box(
				pad,
				"DoorPanel",
				Vector3.new(3.8, 3, 0.12),
				Vector3.new(x, dy, wallZ + 0.36),
				style.color:Lerp(Color3.new(0, 0, 0), 0.15),
				style.material,
				DETAIL
			)
		end
		box(
			pad,
			"Knob",
			Vector3.new(0.35, 0.35, 0.35),
			Vector3.new(x + 2, 4.4, wallZ + 0.45),
			C.brass,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Ball, CanCollide = false }
		)
	end
	if style.bar then
		box(
			pad,
			"PushBar",
			Vector3.new(3.8, 0.3, 0.3),
			Vector3.new(x, 4.2, wallZ + 0.45),
			Color3.fromRGB(60, 60, 60),
			Enum.Material.Metal,
			DETAIL
		)
		box(
			pad,
			"WireWindow",
			Vector3.new(1.2, 1.8, 0.1),
			Vector3.new(x, 6.8, wallZ + 0.33),
			Color3.fromRGB(30, 34, 38),
			Enum.Material.Glass,
			DETAIL
		)
	end
	box(
		pad,
		"Threshold",
		Vector3.new(6, 0.1, 1),
		Vector3.new(x, 0.05, wallZ + 0.8),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local light = cagedLight(queue, CFrame.new(x + 4, 8.6, wallZ + 0.15) * CFrame.Angles(math.rad(-20), 0, 0), 16, 1.1)
	light.Name = "DoorLight"

	-- stencilled straight onto the cinderblock above the door (faces +Z = Back face)
	local sign =
		box(pad, "Sign", Vector3.new(6, 2.2, 0.05), Vector3.new(x, 11.6, wallZ + 0.03), C.block, Enum.Material.Brick, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = sign
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
	box(pad, "Zone", Vector3.new(7, 8, 6), Vector3.new(x, 4, padZ), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	box(pad, "Exit", Vector3.new(1, 1, 1), Vector3.new(x, 3, padZ + 9), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	return pad
end

local function buildDoorWall(root: Instance)
	local queue = folder(root, "Queue")
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = root

	-- mirrored wings: Solo on the outside, Squad nearest the clock
	local wings = { A = { -40, -26, -12 }, B = { 40, 26, 12 } }
	local styleIndex = { A = { 1, 2, 3 }, B = { 6, 5, 4 } }
	for wing, xs in wings do
		for i, mode in Config.ModeOrder do
			buildPad(pads, queue, wing, mode, xs[i], DOOR_STYLES[styleIndex[wing][i]])
		end
	end

	local wallZ = -HALF_Z
	-- wall clock that has stopped, over an old cast-iron radiator
	box(
		queue,
		"ClockFace",
		Vector3.new(0.3, 3, 3),
		CFrame.new(0, 8, wallZ + 0.2) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(226, 216, 196),
		Enum.Material.SmoothPlastic,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		}
	)
	box(
		queue,
		"ClockRim",
		Vector3.new(0.25, 3.4, 3.4),
		CFrame.new(0, 8, wallZ + 0.12) * CFrame.Angles(0, math.rad(90), 0),
		C.darkWood,
		Enum.Material.Wood,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
		}
	)
	box(
		queue,
		"HandHour",
		Vector3.new(0.12, 0.8, 0.05),
		CFrame.new(0.15, 8.3, wallZ + 0.4) * CFrame.Angles(0, 0, math.rad(-20)),
		Color3.fromRGB(20, 20, 20),
		nil,
		DETAIL
	)
	box(
		queue,
		"HandMinute",
		Vector3.new(0.08, 1.2, 0.05),
		CFrame.new(-0.3, 8.2, wallZ + 0.4) * CFrame.Angles(0, 0, math.rad(60)),
		Color3.fromRGB(20, 20, 20),
		nil,
		DETAIL
	)
	for i = -4, 4 do
		box(
			queue,
			"RadiatorFin",
			Vector3.new(0.4, 2.6, 0.9),
			Vector3.new(i * 0.55, 1.6, wallZ + 0.9),
			Color3.fromRGB(150, 140, 120),
			Enum.Material.Metal,
			DETAIL
		)
	end
	box(
		queue,
		"RadiatorPipe",
		Vector3.new(5.2, 0.3, 0.3),
		Vector3.new(0, 0.4, wallZ + 0.9),
		C.pipe,
		Enum.Material.Metal,
		DETAIL
	)

	-- red stencil, painted a little crooked
	local stencil = box(
		queue,
		"Stencil",
		Vector3.new(16, 2.6, 0.05),
		CFrame.new(0, 12.2, wallZ + 0.03) * CFrame.Angles(0, 0, math.rad(-1.5)),
		C.block,
		Enum.Material.Brick,
		{
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	surfaceText(stencil, Enum.NormalId.Back, "PICK A DOOR", Enum.Font.SpecialElite, C.redPaint)
	-- one bulb in front of the doors that won't stay on
	local _, bulb = bareBulb(queue, Vector3.new(0, CEILING - 4.5, wallZ + 12), 22, 1.2, true)
	bulb:FindFirstChildOfClass("PointLight"):SetAttribute("Flicker", "bulb")
end

------------------------------------------------------------------------------------------
-- Lighting: dark, warm, dusty
------------------------------------------------------------------------------------------
local function setupLighting()
	-- Technology is engine-protected from scripts; set Lighting.Technology = Future in Studio.
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(16, 12, 9)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 9, 8)
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.3

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.42
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(66, 52, 40)
	atmosphere.Decay = Color3.fromRGB(30, 24, 18)
	atmosphere.Glare = 0
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 238, 220)
	cc.Contrast = 0.1
	cc.Saturation = -0.12
	cc.Brightness = 0.02
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.5
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
	buildStairs(root)
	buildStacks(root)
	buildShop(root)
	buildWorkbench(root)
	buildReadingNook(root)
	buildFurnace(root)
	buildLeaderboard(root)
	buildDoorWall(root)
	root.Parent = workspace

	setupLighting()
	return root
end

return LobbyBuilder
