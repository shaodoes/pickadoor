--[[
	Builder for the Studio test world "_test_hunt" (Shared.Worlds): the old trial ThreatCorridor (120
	studs of dark corridor, alcoves, caged lights, a Lockable chest and The Follower), wrapped as a world
	to prove the escape pipeline. Contract: build(parent, origin, kit) -> Model (see _Template.luau).

	Contents: Arrive (+Z end), End (-Z end: the Stalker's home and objective 2), Crate (objective 1),
	Stalker (kit.figure), Exit (kit.exitDoor in the -Z end wall), Guide (node graph for the blue path).
]]
local TrialKit = require(script.Parent.Parent.TrialKit)

local TestHunt = {}

local C = TrialKit.C
local DETAIL = TrialKit.DETAIL

local COR_W, COR_H, COR_L = 10, 11, 120
local ALCOVE_W, ALCOVE_D, ALCOVE_H = 6, 5, 9

function TestHunt.build(parent: Instance, _origin: Vector3, kit): Model
	local corridor = kit.model(parent, "World")
	local rng = Random.new(666)
	local X, W, H, L = 0, COR_W, COR_H, COR_L
	local concrete = Enum.Material.Concrete

	kit.box(corridor, "Floor", Vector3.new(W + 2, 1, L + 2), Vector3.new(X, -0.5, 0), C.concrete, concrete)
	kit.box(corridor, "Ceiling", Vector3.new(W + 2, 1, L + 2), Vector3.new(X, H + 0.5, 0), C.ceiling, concrete)
	for _, s in { -1, 1 } do
		kit.box(
			corridor,
			"EndWall",
			Vector3.new(W + 2, H, 1),
			Vector3.new(X, H / 2, s * (L / 2 + 0.5)),
			C.block,
			concrete
		)
	end
	-- pipes along the ceiling
	kit.cylinder(corridor, "Pipe", L, 0.5, Vector3.new(X - 3.4, H - 0.6, 0), "z", C.pipe, Enum.Material.Metal, DETAIL)
	kit.cylinder(corridor, "Pipe", L, 0.8, Vector3.new(X - 2.6, H - 0.9, 0), "z", C.duct, Enum.Material.Metal, DETAIL)

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
			kit.box(
				corridor,
				"Wall",
				Vector3.new(1, H, z1 - z0),
				Vector3.new(wallX, H / 2, (z0 + z1) / 2),
				C.block,
				concrete
			)
			kit.box(
				corridor,
				"Wall",
				Vector3.new(1, H - ALCOVE_H, ALCOVE_W),
				Vector3.new(wallX, (H + ALCOVE_H) / 2, zc),
				C.block,
				concrete
			)
			z0 = zc + ALCOVE_W / 2
		end
		kit.box(
			corridor,
			"Wall",
			Vector3.new(1, H, L / 2 - z0),
			Vector3.new(wallX, H / 2, (z0 + L / 2) / 2),
			C.block,
			concrete
		)
		-- grime band along the floor and a darker line at waist height
		kit.box(
			corridor,
			"Grime",
			Vector3.new(0.06, 1.4, L),
			Vector3.new(X + s * (W / 2 - 0.03), 0.7, 0),
			C.grime,
			concrete,
			DETAIL
		)
		kit.box(
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
		local nook = kit.model(corridor, "Alcove")
		local s = a.side
		local inner = X + s * (W / 2) -- the corridor wall's inner face
		local cx = inner + s * ALCOVE_D / 2
		kit.box(nook, "Floor", Vector3.new(ALCOVE_D, 1, ALCOVE_W), Vector3.new(cx, -0.5, a.z), C.concrete, concrete)
		kit.box(
			nook,
			"Ceiling",
			Vector3.new(ALCOVE_D, 1, ALCOVE_W),
			Vector3.new(cx, ALCOVE_H + 0.5, a.z),
			C.ceiling,
			concrete
		)
		kit.box(
			nook,
			"Back",
			Vector3.new(1, ALCOVE_H + 2, ALCOVE_W + 2),
			Vector3.new(inner + s * (ALCOVE_D + 0.5), ALCOVE_H / 2, a.z),
			C.block,
			concrete
		)
		for _, e in { -1, 1 } do
			kit.box(
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
			kit.box(
				nook,
				"Jamb",
				Vector3.new(0.6, 7.2, 0.6),
				facing * CFrame.new(e * 2.3, 3.6, 0),
				C.darkWood,
				Enum.Material.Wood
			)
		end
		kit.box(
			nook,
			"Header",
			Vector3.new(5.2, 0.6, 0.6),
			facing * CFrame.new(0, 7.5, 0),
			C.darkWood,
			Enum.Material.Wood
		)
		kit.box(
			nook,
			"Slab",
			Vector3.new(4, 7, 0.3),
			facing * CFrame.new(0, 3.5, 0.1),
			Color3.fromRGB(58, 44, 36),
			Enum.Material.Wood
		)
		kit.box(
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
			kit.chest(
				nook,
				facing * CFrame.new(1.6, 0, -1.6) * CFrame.Angles(0, math.pi, 0),
				"trial_corridor_chest",
				15
			)
		elseif i == 2 then
			-- objective 1: the crate with the key in it (Objectives puts the Search prompt on it)
			local crate = kit.box(
				corridor,
				"Crate",
				Vector3.new(2.4, 2, 2.4),
				facing * CFrame.new(-1.4, 1, -1.8),
				Color3.fromRGB(110, 80, 50),
				Enum.Material.WoodPlanks
			)
			TrialKit.pointLight(crate, 6, 0.35, false, Color3.fromRGB(255, 200, 140))
		end
	end

	-- caged work lights alternate sides; two of them are dead
	for i, z in { -52, -37, -22, -7, 8, 23, 38, 53 } do
		local s = (i % 2 == 0) and 1 or -1
		local out = Vector3.new(-s, 0, 0)
		kit.cagedLight(corridor, Vector3.new(X + s * (W / 2), 8.6, z), out, 20, 1.0, i == 3 or i == 6)
	end

	-- scattered paper, and something sprayed by whoever came before
	local litter = kit.model(corridor, "Litter")
	for _ = 1, 16 do
		kit.box(
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
	kit.stencil(
		corridor,
		"Stencil",
		CFrame.new(X + W / 2 - 0.01, 6.2, 44) * CFrame.Angles(0, math.pi / 2, 0),
		7,
		1.3,
		"IT FOLLOWS",
		{ runs = 4 }
	)
	kit.stencil(
		corridor,
		"Stencil",
		CFrame.new(X - W / 2 + 0.01, 6.4, -20) * CFrame.Angles(0, -math.pi / 2, 0),
		9,
		1.3,
		"DON'T LOOK BACK",
		{ runs = 5 }
	)

	-- players arrive at the +Z end looking down the corridor; the stalker waits at the -Z end
	kit.marker(corridor, "Arrive", CFrame.new(X, 3, L / 2 - 6))
	kit.marker(corridor, "End", CFrame.new(X, 3, -L / 2 + 5) * CFrame.Angles(0, math.pi, 0))
	kit.figure(corridor, CFrame.new(X, 0, -L / 2 + 5) * CFrame.Angles(0, math.pi, 0)).Name = "Stalker"
	-- the way out, in the far end wall (opens once both steps are done)
	kit.exitDoor(corridor, CFrame.new(X, 0, -L / 2) * CFrame.Angles(0, math.pi, 0))

	-- the guide graph: a spine down the middle of the corridor and a spur into the crate's alcove
	local guide = Instance.new("Folder")
	guide.Name = "Guide"
	guide.Parent = corridor
	local spineZ = { 54, 36, 18, 0, -18, -30, -42, -55 }
	local spine = {}
	for i in spineZ do
		spine[i] = "N" .. i
	end
	for i, z in spineZ do
		local links = {}
		if spine[i - 1] then
			table.insert(links, spine[i - 1])
		end
		if spine[i + 1] then
			table.insert(links, spine[i + 1])
		end
		if z == -30 then
			table.insert(links, "Crate")
		end
		kit.guideNode(guide, spine[i], Vector3.new(X, 0.5, z), links)
	end
	kit.guideNode(guide, "Crate", Vector3.new(X + W / 2 + 1.5, 0.5, -30), { "N6" })
	return corridor
end

return TestHunt
