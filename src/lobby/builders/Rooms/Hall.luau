--[[
	The reading hall (floor y = 0): the heart of the library. Big windows on the -X wall look out onto
	the flooded natatorium; study desks under green-shaded lamps, armchairs turned to the water,
	bookcases, angular concrete pillars carrying the beams, planters. The grand stair comes down at the
	front-right, the arch to the door hall is at the back, the workshop stair is through the +X wall.
	The walkway from the stair foot (x 4..20, z 30) to the arch (x -9..9, z -20) stays clear.
]]
local Builders = script.Parent.Parent
local Kit = require(Builders.Kit)
local Layout = require(Builders.Layout)
local Furniture = require(Builders.Furniture)
local Clutter = require(Builders.Clutter)
local signageModule = Builders:FindFirstChild("Signage")
local Signage = signageModule and require(signageModule)

local box = Kit.box

local Hall = {}

local ROOM = Layout.Rooms.Hall
local Y = ROOM.y
local CEIL = ROOM.y + ROOM.h

local function rug(model: Instance, pos: Vector3, size: Vector2, yaw: number, color: Color3, border: Color3)
	local cf = CFrame.new(pos.X, Y, pos.Z) * CFrame.Angles(0, yaw, 0)
	box(
		model,
		"Rug",
		Vector3.new(size.X, 0.07, size.Y),
		cf * CFrame.new(0, 0.045, 0),
		color,
		Enum.Material.Carpet,
		{ CanCollide = false, CastShadow = false }
	)
	box(
		model,
		"RugBorder",
		Vector3.new(size.X + 0.7, 0.06, size.Y + 0.7),
		cf * CFrame.new(0, 0.035, 0),
		border,
		Enum.Material.Carpet,
		Kit.DETAIL
	)
end

function Hall.build(root: Instance)
	local model = Kit.folder(root, "Hall")
	local faceE, faceW = CFrame.Angles(0, math.rad(-90), 0), CFrame.Angles(0, math.rad(90), 0) -- fronts toward +X / -X
	local faceN = CFrame.Angles(0, math.pi, 0) -- fronts toward +Z / -Z

	-- structure: four angular concrete pillars under the beams, flanking the walkway
	for _, p in
		{ Vector3.new(-8, Y, -7.5), Vector3.new(-8, Y, 17.5), Vector3.new(20, Y, -7.5), Vector3.new(20, Y, 17.5) }
	do
		if Furniture.pillar then
			Furniture.pillar(model, p, ROOM.h)
		end
	end

	-- the window side: wall shelves between the windows, armchairs turned toward the water
	Furniture.wallShelves(model, CFrame.new(ROOM.x0 + 0.9, Y, -16.5) * faceE, 6)
	Furniture.wallShelves(model, CFrame.new(ROOM.x0 + 0.9, Y, 0) * faceE, 6)
	for _, w in Layout.HallWindows.list do
		local wz = w.z
		local base = Vector3.new(ROOM.x0 + 6.5, Y, wz)
		Furniture.armchair(model, CFrame.lookAt(base + Vector3.new(0, 0, -2.6), Vector3.new(ROOM.x0, Y, wz - 1)))
		Furniture.armchair(model, CFrame.lookAt(base + Vector3.new(0, 0, 2.6), Vector3.new(ROOM.x0, Y, wz + 1)))
		local topY = Furniture.sideTable and Furniture.sideTable(model, CFrame.new(base + Vector3.new(1.2, 0, 0)))
		if topY then
			if wz == 8 then
				Kit.anchor(model, "Candle", CFrame.new(base + Vector3.new(1.2, topY - Y + 0.9, 0.4)))
				box(
					model,
					"CandleStick",
					Vector3.new(0.22, 0.9, 0.22),
					base + Vector3.new(1.2, topY - Y + 0.45, 0.4),
					Color3.fromRGB(236, 226, 200),
					Enum.Material.SmoothPlastic,
					Kit.DETAIL
				)
			else
				Furniture.bookPile(model, base + Vector3.new(1.2, topY - Y, 0), 2)
			end
		end
	end
	rug(
		model,
		Vector3.new(ROOM.x0 + 7, 0, 8),
		Vector2.new(9, 13),
		0,
		Color3.fromRGB(92, 44, 32),
		Color3.fromRGB(60, 30, 22)
	)
	if Furniture.floorLamp then
		Furniture.floorLamp(model, Vector3.new(ROOM.x0 + 3, Y, 14.5))
		Furniture.floorLamp(model, Vector3.new(ROOM.x0 + 3, Y, -1.5))
	end

	-- left middle: two long study desks with green banker lamps, chairs on both sides
	for _, z in { -11, 15 } do
		local cf = CFrame.new(-17, Y, z) * faceE -- desk runs along Z
		if Furniture.studyDesk then
			Furniture.studyDesk(model, cf, 12, 6)
		else
			Furniture.readingTable(model, cf)
		end
		Kit.bareBulb(model, Vector3.new(-17, CEIL - 5, z - 3.5), 16, 0.9, z < 0, "shade", CEIL)
		Kit.bareBulb(model, Vector3.new(-17, CEIL - 5, z + 3.5), 16, 0.9, false, "shade", CEIL)
		Kit.anchor(model, "LampDust", CFrame.new(-17, Y + 7, z), Vector3.new(8, 8, 12))
	end

	-- right side: freestanding double-sided bookcases with a reading table between
	Furniture.bookcase(model, CFrame.new(26, Y, 25.4) * faceE, 7, 9.4, 3, true) -- books face the walkway
	Furniture.readingTable(model, CFrame.new(24.5, Y, 11) * faceE)
	Furniture.readingTable(model, CFrame.new(24.5, Y, -11) * faceE)
	Kit.bareBulb(model, Vector3.new(24.5, CEIL - 5.2, 11), 18, 1, true, "shade", CEIL)
	Kit.bareBulb(model, Vector3.new(24.5, CEIL - 5.2, -11), 18, 1, false, "shade", CEIL)
	Kit.prop(model, "Fern", CFrame.new(26, Y + 9.8, 24) * CFrame.Angles(0, 0.7, 0))
	-- against the +X wall: shelves either side of the workshop doorway
	Furniture.wallShelves(model, CFrame.new(ROOM.x1 - 0.9, Y, -12.5) * faceW, 12)
	Furniture.wallShelves(model, CFrame.new(ROOM.x1 - 0.9, Y, 14) * faceW, 12)
	-- along the front wall, left of the stair foot
	Furniture.wallShelves(model, CFrame.new(-16, Y, ROOM.z1 - 0.9) * faceN, 18)
	Furniture.metalRack(model, CFrame.new(-2, Y, ROOM.z1 - 1.6) * faceN, 7, 8, 2.4)

	-- the walkway: rugs, planters, pendant globes, a book cart and a returns trolley
	rug(model, Vector3.new(8, 0, 20), Vector2.new(10, 14), 0.04, Color3.fromRGB(88, 64, 40), Color3.fromRGB(60, 30, 22))
	rug(model, Vector3.new(2, 0, 2), Vector2.new(11, 15), -0.05, Color3.fromRGB(78, 34, 28), Color3.fromRGB(56, 28, 22))
	for _, p in { Vector3.new(1.5, Y, 27), Vector3.new(22.5, Y, 27) } do
		if Furniture.planterPillar then
			Furniture.planterPillar(model, p, 6)
		end
	end
	if Furniture.planter then
		Furniture.planter(model, CFrame.new(-13, Y, ROOM.z0 + 1.6), 8)
		Furniture.planter(model, CFrame.new(13, Y, ROOM.z0 + 1.6), 8)
	end
	for _, z in { 22, 8, -6 } do
		Kit.bareBulb(model, Vector3.new(5, CEIL - 4.2, z), 22, 1.1, z == 8, "globe", CEIL)
	end
	Furniture.bookPile(model, Vector3.new(-4, Y, 6), 6)
	Furniture.bookPile(model, Vector3.new(19.5, Y, -16.5), 5) -- clear of the Wheel of Fate
	if Furniture.boxes then
		Furniture.boxes(model, CFrame.new(ROOM.x1 - 3, Y, 9.5) * CFrame.Angles(0, 0.3, 0), 2)
	end

	-- signs: over the arch to the doors, and by the workshop doorway
	if Signage and Signage.wallSign then
		local arch = Layout.Openings.Arch
		Signage.wallSign(
			model,
			CFrame.lookAt(Vector3.new(0, arch.y1 + 1.5, ROOM.z0 + 0.06), Vector3.new(0, arch.y1 + 1.5, ROOM.z0 + 5)),
			"THE DOORS",
			{ style = "plaque", width = 11, height = 2.2, arrow = "down" }
		)
		local wd = Layout.Openings.WorkshopDoor
		Signage.wallSign(
			model,
			CFrame.lookAt(
				Vector3.new(ROOM.x1 - 0.06, wd.y1 + 1.3, (wd.z0 + wd.z1) / 2),
				Vector3.new(ROOM.x1 - 5, wd.y1 + 1.3, (wd.z0 + wd.z1) / 2)
			),
			"WORKSHOP",
			{ style = "stencil", width = 7, height = 1.5, arrow = "down" }
		)
	end

	-- papers: a trail from the stair foot to the arch, sheets everywhere else; notes on the walls
	local blocked = {
		{ -21, -13, -19, -3 },
		{ -21, -13, 7, 23 }, -- study desks
		{ 24, 28, 21, 30 }, -- bookcase
		{ 21, 28, 6, 16 },
		{ 21, 28, -16, -6 }, -- reading tables
		{ -32, -22, -20, 30 }, -- window nook
		{ -21, -12.8, -2, 5 }, -- reward stations (Layout.Stations): daily chest + ring
		{ 10, 19, -17, -6.8 }, -- Wheel of Fate + ring
		{ -14, -7.2, 19.4, 29 }, -- archivist's desk, catalogue + ring
	}
	Clutter.papers(
		model,
		{ ROOM.x0, ROOM.x1, ROOM.z0, ROOM.z1 },
		Y,
		55,
		blocked,
		{ Vector3.new(12, Y, 28), Vector3.new(0, Y, -19) }
	)
	Clutter.wallNote(model, Vector3.new(ROOM.x0, Y + 7, 28), Vector3.new(1, 0, 0))
	Clutter.noteCluster(model, Vector3.new(-6, Y + 7, ROOM.z1), Vector3.new(0, 0, -1), 3)
	Clutter.noteCluster(model, Vector3.new(ROOM.x1, Y + 6.5, 8.5), Vector3.new(-1, 0, 0), 2)
	Clutter.noteCluster(model, Vector3.new(-16, Y + 8, ROOM.z0), Vector3.new(0, 0, 1), 3)

	-- atmosphere markers
	Kit.anchor(model, "LampDust", CFrame.new(5, Y + 7, 8), Vector3.new(14, 9, 30))
	Kit.anchor(model, "Drip", CFrame.new(-28, CEIL - 0.1, 24))
	Kit.anchor(model, "Pipes", CFrame.new(0, CEIL - 1, 0))
	return model
end

return Hall
