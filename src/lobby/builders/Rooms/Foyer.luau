--[[
	The arrival foyer (floor y = 6): you come down the old wooden stairs from the house, land by the
	spawn, and look straight across the foyer and down the wide concrete stair into the reading hall.
	Also here: the chalkboard leaderboard, the patch-notes board, the Librarian and his lectern (Npcs/Librarian),
	and the store's storefront on the left wall (built by Rooms/Shop).
]]
local Builders = script.Parent.Parent
local Kit = require(Builders.Kit)
local Layout = require(Builders.Layout)
local Furniture = require(Builders.Furniture)
local Clutter = require(Builders.Clutter)
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local signageModule = Builders:FindFirstChild("Signage")
local Signage = signageModule and require(signageModule)
local roomSignsModule = Builders:FindFirstChild("SignageRooms")
local SignageRooms = roomSignsModule and require(roomSignsModule)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL

local Foyer = {}

local ROOM = Layout.Rooms.Foyer
local Y = ROOM.y
local CEIL = ROOM.y + ROOM.h

-- Old wooden stairs from the house, along the front wall, rising toward +X to a door up in the shaft.
Foyer.HOUSE_STAIR = { x0 = 6, x1 = ROOM.x1, z0 = 59.5, z1 = ROOM.z1 } -- ceiling hole over it

local function houseStairs(model: Instance)
	local steps, run = 16, 1.1
	local rise = ROOM.h / steps
	local zA, zB = 60.6, 65.6
	local zc = (zA + zB) / 2
	local xBottom = 7
	for i = 1, steps do
		local x = xBottom + (i - 0.5) * run
		box(
			model,
			"Tread",
			Vector3.new(run + 0.12, 0.3, zB - zA),
			Vector3.new(x, Y + i * rise - 0.15, zc),
			C.midWood,
			Enum.Material.WoodPlanks
		)
		box(
			model,
			"Riser",
			Vector3.new(0.12, rise - 0.3, zB - zA - 0.2),
			Vector3.new(x - run / 2 + 0.06, Y + (i - 0.5) * rise - 0.15, zc),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	local xTop = xBottom + steps * run
	box(
		model,
		"Landing",
		Vector3.new(ROOM.x1 - xTop, 1, zB - zA + 0.8),
		Vector3.new((xTop + ROOM.x1) / 2, CEIL - 0.5, zc + 0.4),
		C.midWood,
		Enum.Material.WoodPlanks
	)

	-- stringers + a handrail on the open side, with balusters
	local bottom, top = Vector3.new(xBottom, Y, zA - 0.2), Vector3.new(xTop, CEIL, zA - 0.2)
	local mid, len = (bottom + top) / 2, (top - bottom).Magnitude
	for _, dz in { 0, zB - zA + 0.4 } do
		box(
			model,
			"Stringer",
			Vector3.new(0.35, 1.1, len),
			CFrame.lookAt(mid + Vector3.new(0, 0, dz), top + Vector3.new(0, 0, dz)),
			C.darkWood,
			Enum.Material.Wood
		)
	end
	box(
		model,
		"Handrail",
		Vector3.new(0.3, 0.3, len),
		CFrame.lookAt(mid + Vector3.new(0, 3.2, -0.3), top + Vector3.new(0, 3.2, -0.3)),
		C.wood,
		Enum.Material.Wood
	)
	for i = 0, 8 do
		local p = bottom:Lerp(top, i / 8) + Vector3.new(0, 1.6, -0.3)
		box(model, "Baluster", Vector3.new(0.22, 3.2, 0.22), p, C.darkWood, Enum.Material.Wood, DETAIL)
	end
	box(
		model,
		"Newel",
		Vector3.new(0.5, 4.2, 0.5),
		Vector3.new(xBottom - 0.2, Y + 2.1, zA - 0.3),
		C.wood,
		Enum.Material.Wood
	)

	-- the stairwell shaft above the ceiling, lit from the house upstairs
	local hs = Foyer.HOUSE_STAIR
	local shaftTop = CEIL + 11
	local sx, sz = (hs.x0 + hs.x1) / 2, (hs.z0 + hs.z1) / 2
	local sw, sd, sh = hs.x1 - hs.x0 + 2, hs.z1 - hs.z0 + 2, shaftTop - CEIL
	local sy = (CEIL + shaftTop) / 2
	box(model, "ShaftWall", Vector3.new(sw, sh, 1), Vector3.new(sx, sy, hs.z0 - 0.5), C.block, Enum.Material.Plaster)
	box(model, "ShaftWall", Vector3.new(sw, sh, 1), Vector3.new(sx, sy, hs.z1 + 0.5), C.block, Enum.Material.Plaster)
	box(model, "ShaftWall", Vector3.new(1, sh, sd), Vector3.new(hs.x0 - 0.5, sy, sz), C.block, Enum.Material.Plaster)
	box(model, "ShaftWall", Vector3.new(1, sh, sd), Vector3.new(hs.x1 + 0.5, sy, sz), C.block, Enum.Material.Plaster)
	box(
		model,
		"ShaftCeiling",
		Vector3.new(sw, 1, sd),
		Vector3.new(sx, shaftTop + 0.5, sz),
		C.ceiling,
		Enum.Material.Plaster
	)
	-- the door back up into the house, shut, with light under it
	box(
		model,
		"UpstairsDoor",
		Vector3.new(0.4, 7.6, 3.8),
		Vector3.new(hs.x1 - 0.2, CEIL + 3.9, zc),
		C.darkWood,
		Enum.Material.Wood
	)
	box(
		model,
		"DoorFrame",
		Vector3.new(0.3, 8.3, 4.6),
		Vector3.new(hs.x1 - 0.05, CEIL + 4.15, zc),
		C.wood,
		Enum.Material.Wood,
		DETAIL
	)
	local gap = box(
		model,
		"DoorGap",
		Vector3.new(0.1, 0.1, 3.6),
		Vector3.new(hs.x1 - 0.42, CEIL + 0.05, zc),
		Color3.fromRGB(255, 210, 160),
		Enum.Material.Neon,
		DETAIL
	)
	Kit.pointLight(gap, 8, 0.6, false, Color3.fromRGB(255, 210, 160))
	Kit.bareBulb(model, Vector3.new(hs.x0 + 12, shaftTop - 2.5, zc), 24, 1.4, true, "globe", shaftTop)

	-- storage under the stairs, where the headroom is: boxes resting on the floor and on each other
	local under = CFrame.new(18.5, Y, zc) * CFrame.Angles(0, 0.25, 0)
	if Furniture.boxes then
		Furniture.boxes(model, under, 3)
	else
		Kit.prop(model, "BoxTaped", under, 1.1)
		Kit.prop(model, "BoxOpen", CFrame.new(21.8, Y, zc - 0.4) * CFrame.Angles(0, -0.4, 0))
	end
	Kit.prop(model, "BooksPile", CFrame.new(14.5, Y, zc + 0.6) * CFrame.Angles(0, 2, 0), 0.8)
end

-- The wide concrete stair down into the reading hall (z 42 -> 30, y 6 -> 0), in the Stair corridor.
local function grandStair(model: Instance)
	local s = Layout.Rooms.Stair
	local width = s.x1 - s.x0
	local xc = (s.x0 + s.x1) / 2
	local steps = 12
	local rise, run = (Y - s.y) / steps, (s.z1 - s.z0) / steps
	local stone = Color3.fromRGB(142, 144, 148)
	for i = 0, steps - 1 do
		local z0 = s.z0 + i * run
		local topY = s.y + (i + 1) * rise
		box(
			model,
			"Step",
			Vector3.new(width, topY - (s.y - 1), run),
			Vector3.new(xc, (topY + s.y - 1) / 2, z0 + run / 2),
			stone,
			Enum.Material.Concrete
		)
		box(
			model,
			"Nosing",
			Vector3.new(width - 0.4, 0.06, 0.35),
			Vector3.new(xc, topY + 0.01, z0 + 0.2),
			Color3.fromRGB(70, 72, 76),
			Enum.Material.DiamondPlate,
			DETAIL
		)
	end
	-- raking wainscot, rail and handrails on both side walls
	local slope = math.atan2(Y - s.y, s.z1 - s.z0)
	local len = math.sqrt((Y - s.y) ^ 2 + (s.z1 - s.z0) ^ 2)
	local midZ, midY = (s.z0 + s.z1) / 2, (s.y + Y) / 2
	for _, x in { s.x0, s.x1 } do
		local inward = x == s.x0 and 1 or -1
		local function along(offsetX: number, height: number)
			return CFrame.new(x + inward * offsetX, midY + height, midZ) * CFrame.Angles(-slope, 0, 0)
		end
		box(
			model,
			"Wainscot",
			Vector3.new(0.16, 4, len + 2),
			along(0.08, 2),
			C.wainscot,
			Enum.Material.Concrete,
			DETAIL
		)
		box(model, "Rail", Vector3.new(0.3, 0.25, len + 2), along(0.15, 4), C.rail, Enum.Material.Metal, DETAIL)
		local rail = Kit.box(
			model,
			"Handrail",
			Vector3.new(len + 1, 0.22, 0.22),
			along(0.55, 3.1) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(150, 152, 156),
			Enum.Material.Metal,
			{
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
				CastShadow = false,
			}
		)
		rail.Name = "Handrail"
		for t = -0.4, 0.4, 0.4 do
			box(
				model,
				"RailBracket",
				Vector3.new(0.5, 0.12, 0.12),
				along(0.3, 3.1) * CFrame.new(0, 0, t * len),
				Color3.fromRGB(110, 112, 116),
				Enum.Material.Metal,
				DETAIL
			)
		end
	end
	-- glow strips under the nosings would be too much; one hanging lamp over the middle of the flight
	Kit.bareBulb(model, Vector3.new(xc, s.y + s.h - 4.5, midZ), 22, 1.1, true, "globe", s.y + s.h)
end

-- Chalkboard "hall of records" on the right wall (Leaderboard.Board.SurfaceGui with Keys/Trials rows).
local function leaderboard(root: Instance)
	local board = Kit.folder(root, "Leaderboard")
	local z = 51
	local x = ROOM.x1
	local pos = Vector3.new(x - 0.25, Y + 7.5, z)
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
	-- a picture light on a brass arm above the board
	for _, dz in { -4, 4 } do
		box(
			board,
			"LampArm",
			Vector3.new(1.4, 0.12, 0.12),
			pos + Vector3.new(-0.45, 4.3, dz),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		local hood = box(
			board,
			"LampHood",
			Vector3.new(0.5, 0.35, 3),
			pos + Vector3.new(-1.2, 4.2, dz),
			Color3.fromRGB(34, 56, 44),
			Enum.Material.Metal,
			DETAIL
		)
		local glow = box(
			board,
			"LampGlow",
			Vector3.new(0.3, 0.06, 2.6),
			pos + Vector3.new(-1.2, 4.0, dz),
			Color3.fromRGB(255, 200, 140),
			Enum.Material.Neon,
			DETAIL
		)
		glow.Transparency = 0.2
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 100
		spot.Range = 9
		spot.Brightness = 1.4
		spot.Color = C.warm
		spot.Parent = hood
	end
	-- carved header with brass letters, between the lamp hoods (z 48.7..53.3) and under the downstand
	-- beam (bottom y 18.6) and the wall cornice (y ~18.7 at the wall)
	if SignageRooms then
		SignageRooms.recordsHeader(board, Vector3.new(x, Y + 12.05, z), -Vector3.xAxis)
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
	return board
end

-- Cork board of patch notes beside the stair opening, facing the room (+Z).
local function noticeBoard(model: Instance)
	local cf = CFrame.lookAt(Vector3.new(25.5, Y + 6.5, ROOM.z0 + 0.15), Vector3.new(25.5, Y + 6.5, ROOM.z0 + 5))
	box(model, "Corkboard", Vector3.new(6, 4.2, 0.2), cf, Color3.fromRGB(150, 110, 70), Enum.Material.Cardboard)
	box(
		model,
		"CorkFrame",
		Vector3.new(6.4, 4.6, 0.15),
		cf * CFrame.new(0, 0, 0.06),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	local notice = box(
		model,
		"PatchNotes",
		Vector3.new(3.6, 3.4, 0.02),
		cf * CFrame.new(-0.9, 0, -0.12) * CFrame.Angles(0, 0, math.rad(-2)),
		Color3.fromRGB(232, 226, 208),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 90
	gui.LightInfluence = 1
	gui.Parent = notice
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0.07, 0.05)
	text.Size = UDim2.fromScale(0.86, 0.9)
	text.Font = Enum.Font.SpecialElite
	text.TextScaled = true
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextColor3 = Clutter.INK
	text.Text =
		"10/08 - THE LIBRARY OPENS\n\n- Pick a door. Any door.\n- Lanterns are fixed up in the workshop, past the reading room.\n- The store is open.\n- Something has been moving the papers at night."
	text.Parent = gui
	for _, offset in { Vector3.new(-2.5, 1.5, -0.15), Vector3.new(0.7, 1.55, -0.15), Vector3.new(2, 0.4, -0.15) } do
		box(
			model,
			"Pin",
			Vector3.new(0.18, 0.18, 0.18),
			cf * CFrame.new(offset),
			C.redPaint,
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false }
		)
	end
	Clutter.wallNote(
		model,
		(cf * CFrame.new(1.7, -0.6, -0.12)).Position,
		cf.LookVector,
		"who keeps opening the red door?"
	)
end

function Foyer.build(root: Instance)
	local model = Kit.folder(root, "Foyer")
	houseStairs(model)
	grandStair(model)
	leaderboard(root)
	noticeBoard(model)

	-- spawn: at the foot of the house stairs, facing straight down the foyer to the grand stair
	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "Spawn"
	spawnPoint.Anchored = true
	spawnPoint.Size = Vector3.new(4, 0.2, 4)
	spawnPoint.CFrame = Layout.Spawn
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.CanQuery = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = model

	-- doormat at the spawn and a runner down to the stair
	box(
		model,
		"Runner",
		Vector3.new(7, 0.06, 12),
		Vector3.new(12, Y + 0.04, 49.5),
		Color3.fromRGB(78, 34, 28),
		Enum.Material.Carpet,
		{ CanCollide = false, CastShadow = false }
	)
	box(
		model,
		"RunnerBorder",
		Vector3.new(7.6, 0.05, 12.6),
		Vector3.new(12, Y + 0.035, 49.5),
		Color3.fromRGB(52, 28, 22),
		Enum.Material.Carpet,
		DETAIL
	)

	-- concrete planter pedestals flanking the top of the grand stair (reference)
	for _, x in { 22.4 } do -- (the shop storefront dresses the left side)
		if Furniture.planterPillar then
			Furniture.planterPillar(model, Vector3.new(x, Y, 44.6), 7)
		end
	end
	-- a bench under the leaderboard, a couple of potted plants, boxes of returns by the shop door
	if Furniture.bench then
		Furniture.bench(model, CFrame.new(23.5, Y, 51) * CFrame.Angles(0, math.rad(-90), 0), 8)
	end
	Kit.prop(model, "PalmVase", CFrame.new(-0.2, Y, 64.6), 0.85)
	Kit.prop(model, "Fern", CFrame.new(28.6, Y, 43.6), 1.1)

	-- room sign over the stair opening, on the foyer side: a theatre-marquee lightbox
	if SignageRooms then
		SignageRooms.readingRoom(model, Vector3.new(12, Y + 11.5, ROOM.z0), Vector3.zAxis)
	elseif Signage and Signage.wallSign then
		Signage.wallSign(
			model,
			CFrame.lookAt(Vector3.new(12, Y + 11.8, ROOM.z0 + 0.06), Vector3.new(12, Y + 11.8, ROOM.z0 + 5)),
			"READING ROOM",
			{ style = "plaque", width = 9, height = 1.6, arrow = "down" }
		)
	end

	-- papers and notes
	Clutter.papers(
		model,
		{ ROOM.x0, ROOM.x1, ROOM.z0, 59 },
		Y,
		22,
		{ { 20, 27, 46, 56 } },
		{ Vector3.new(12, Y, 55), Vector3.new(12, Y, 43) }
	)
	Clutter.noteCluster(model, Vector3.new(ROOM.x1, Y + 7, 61), Vector3.new(-1, 0, 0), 3)
	Clutter.wallNote(model, Vector3.new(ROOM.x0, Y + 6, 62), Vector3.new(1, 0, 0), "SHHH")
	Kit.anchor(model, "LampDust", CFrame.new(12, Y + 6, 50), Vector3.new(16, 8, 14))
	Kit.anchor(model, "Hum", CFrame.new(12, CEIL - 0.5, 50))
	return model
end

return Foyer
