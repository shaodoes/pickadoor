--[[
	Builder for the Studio test world "_test_lounge" (Shared.Worlds): the old trial SafeRoom, a warm
	sitting room, wrapped as a world to prove the lounge pipeline. Contract (every Worlds/<Module>.luau
	builder): build(parent, origin, kit) -> Model, all positions through `kit` (TrialKit.at(origin)).

	Contents: Arrive, Exit (kit.exitDoor), FollowDoor (kit.followDoor), Pickups (kit.pickup keys) and a
	Collectible part (Lounge.luau puts the prompt on it). No Guide folder: a lounge never escalates.
]]
local TrialKit = require(script.Parent.Parent.TrialKit)

local TestLounge = {}

local C = TrialKit.C
local DETAIL = TrialKit.DETAIL
local INVISIBLE = TrialKit.INVISIBLE

local SAFE_W, SAFE_D, SAFE_H = 26, 22, 10

local function armchair(kit, parent: Instance, cf: CFrame)
	local chair = kit.model(parent, "Armchair")
	local fabric = Enum.Material.Fabric
	kit.box(chair, "Seat", Vector3.new(3, 1.4, 3), cf * CFrame.new(0, 0.7, 0), C.chair, fabric)
	kit.box(chair, "Cushion", Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 1.6, -0.1), C.chairLight, fabric, DETAIL)
	kit.box(chair, "Back", Vector3.new(3, 3.2, 0.8), cf * CFrame.new(0, 2.4, 1.3), C.chair, fabric)
	for _, s in { -1, 1 } do
		kit.box(chair, "Arm", Vector3.new(0.6, 2.1, 3), cf * CFrame.new(s * 1.5, 1.45, 0.1), C.chair, fabric)
	end
	return chair
end

local function bookshelf(kit, parent: Instance, cf: CFrame, rng: Random)
	local shelf = kit.model(parent, "Bookshelf")
	local w, h, d = 10, 8, 1.4
	local wood = Enum.Material.Wood
	kit.box(shelf, "Back", Vector3.new(w, h, 0.2), cf * CFrame.new(0, h / 2, d / 2 - 0.1), C.darkWood, wood, DETAIL)
	for _, s in { -1, 1 } do
		kit.box(shelf, "Side", Vector3.new(0.3, h, d), cf * CFrame.new(s * (w / 2 - 0.15), h / 2, 0), C.wood, wood)
	end
	kit.box(shelf, "Top", Vector3.new(w, 0.3, d), cf * CFrame.new(0, h - 0.15, 0), C.wood, wood)
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
		kit.box(shelf, "Shelf", Vector3.new(w - 0.6, 0.2, d - 0.2), cf * CFrame.new(0, y, 0), C.wood, wood)
		local x = -w / 2 + 0.5
		while x < w / 2 - 0.9 do
			local bw = rng:NextNumber(0.3, 0.7)
			local bh = rng:NextNumber(1.1, 1.7)
			kit.box(
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

local function fireplace(kit, parent: Instance, cf: CFrame)
	-- cf: centre of the hearth on the wall's inner face, LookVector into the room
	local fp = kit.model(parent, "Fireplace")
	for _, s in { -1, 1 } do
		kit.box(
			fp,
			"Pillar",
			Vector3.new(1.2, 5, 1.2),
			cf * CFrame.new(s * 2.6, 2.5, -0.6),
			C.brick,
			Enum.Material.Brick
		)
	end
	kit.box(fp, "Mantel", Vector3.new(7, 0.5, 1.6), cf * CFrame.new(0, 5.25, -0.8), C.darkWood, Enum.Material.Wood)
	kit.box(fp, "Lintel", Vector3.new(6.4, 1, 1), cf * CFrame.new(0, 4.5, -0.5), C.brick, Enum.Material.Brick)
	kit.box(
		fp,
		"Firebox",
		Vector3.new(4, 4, 0.3),
		cf * CFrame.new(0, 2, -0.16),
		Color3.fromRGB(12, 10, 10),
		nil,
		DETAIL
	)
	kit.box(fp, "Hearth", Vector3.new(7, 0.2, 2.8), cf * CFrame.new(0, 0.1, -1.2), C.slate, Enum.Material.Slate)
	for _, s in { -0.35, 0.35 } do
		kit.cylinder(
			fp,
			"Log",
			2.4,
			0.6,
			cf * CFrame.new(0, 0.5, -0.4 + s),
			"x",
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for i = 1, 4 do
		local ember = kit.box(
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
	local flame =
		kit.box(fp, "Flame", Vector3.new(2.6, 0.2, 1.2), cf * CFrame.new(0, 0.8, -0.3), C.ember, nil, INVISIBLE)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 60)
	fire.SecondaryColor = Color3.fromRGB(140, 40, 20)
	fire.Parent = flame
	TrialKit.flicker(TrialKit.pointLight(flame, 26, 1.5, true, C.fire), "furnace")
	-- a dim painting over the mantel
	kit.box(
		fp,
		"Frame",
		Vector3.new(2.6, 2, 0.12),
		cf * CFrame.new(0, 7.2, -0.08),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	kit.box(
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

local function floorLamp(kit, parent: Instance, pos: Vector3)
	local lamp = kit.model(parent, "FloorLamp")
	kit.cylinder(lamp, "Base", 0.15, 1.4, pos + Vector3.new(0, 0.075, 0), "y", C.darkWood, Enum.Material.Metal, DETAIL)
	kit.box(
		lamp,
		"Pole",
		Vector3.new(0.16, 5.3, 0.16),
		pos + Vector3.new(0, 2.8, 0),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	kit.cylinder(
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
	local core = kit.cylinder(
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
	TrialKit.halo(core, 3.2)
	TrialKit.pointLight(core, 30, 1.2, true, C.warm)
	return lamp
end

-- The FOLLOW THEM IN door: dark steel, cold light above it, the words sprayed across it.

function TestLounge.build(parent: Instance, _origin: Vector3, kit): Model
	local room = kit.model(parent, "World")
	local rng = Random.new(2024)
	local X, W, D, H = 0, SAFE_W, SAFE_D, SAFE_H
	kit.box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(X, -0.5, 0), C.planks, Enum.Material.WoodPlanks)
	kit.box(room, "Ceiling", Vector3.new(W, 1, D), Vector3.new(X, H + 0.5, 0), Color3.fromRGB(140, 128, 110))
	for _, s in { -1, 1 } do
		kit.box(
			room,
			"Wall",
			Vector3.new(1, H, D + 2),
			Vector3.new(X + s * (W / 2 + 0.5), H / 2, 0),
			C.warmPaper,
			Enum.Material.Fabric
		)
		kit.box(
			room,
			"Wall",
			Vector3.new(W, H, 1),
			Vector3.new(X, H / 2, s * (D / 2 + 0.5)),
			C.warmPaper,
			Enum.Material.Fabric
		)
		-- wainscot and rail
		kit.box(
			room,
			"Wainscot",
			Vector3.new(0.12, 3, D),
			Vector3.new(X + s * (W / 2 - 0.06), 1.5, 0),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
			room,
			"Wainscot",
			Vector3.new(W, 3, 0.12),
			Vector3.new(X, 1.5, s * (D / 2 - 0.06)),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
			room,
			"Rail",
			Vector3.new(0.2, 0.16, D),
			Vector3.new(X + s * (W / 2 - 0.1), 3.1, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
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
	kit.box(room, "Rug", Vector3.new(12, 0.08, 9), Vector3.new(X - 4, 0.04, 0), C.rug, Enum.Material.Fabric, DETAIL)
	kit.box(
		room,
		"RugTrim",
		Vector3.new(11, 0.02, 8),
		Vector3.new(X - 4, 0.09, 0),
		C.rugTrim,
		Enum.Material.Fabric,
		DETAIL
	)
	kit.box(room, "RugField", Vector3.new(10, 0.02, 7), Vector3.new(X - 4, 0.1, 0), C.rug, Enum.Material.Fabric, DETAIL)

	-- the fire on the -X wall; chairs face it
	fireplace(kit, room, CFrame.new(X - W / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	for _, z in { -4.2, 4.2 } do
		armchair(kit, room, CFrame.new(X - 6.5, 0, z) * CFrame.Angles(0, math.pi / 2, 0))
	end
	local table_ = kit.model(room, "SideTable")
	kit.box(table_, "Top", Vector3.new(1.6, 0.15, 1.6), Vector3.new(X - 6.5, 1.9, 0), C.darkWood, Enum.Material.Wood)
	kit.box(
		table_,
		"Leg",
		Vector3.new(0.25, 1.8, 0.25),
		Vector3.new(X - 6.5, 0.95, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	kit.box(
		table_,
		"Foot",
		Vector3.new(0.9, 0.15, 0.9),
		Vector3.new(X - 6.5, 0.075, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	kit.box(
		table_,
		"Book",
		Vector3.new(0.9, 0.18, 1.2),
		CFrame.new(X - 6.6, 2.07, 0.1) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(96, 30, 26),
		nil,
		DETAIL
	)
	kit.cylinder(
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

	floorLamp(kit, room, Vector3.new(X + 9.5, 0, 8))
	bookshelf(kit, room, CFrame.new(X + 2, 0, D / 2 - 0.7), rng) -- its back (+Z) against the +Z wall

	-- a night window on the +X wall: a cold pane, nothing to see
	local win = kit.model(room, "Window")
	local pane = kit.box(
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
		kit.box(
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
		kit.box(
			win,
			"Mullion",
			Vector3.new(0.3, 0.2, 5.2),
			Vector3.new(X + W / 2 - 0.15, 5.5 + dy, -4),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	TrialKit.pointLight(pane, 8, 0.25, false, Color3.fromRGB(90, 110, 160))

	-- the other door, on the -Z wall, facing +Z into the room
	kit.followDoor(room, CFrame.new(X, 0, -D / 2) * CFrame.Angles(0, math.pi, 0))

	-- the way out, on the +X wall beside the window
	kit.exitDoor(room, CFrame.new(X + W / 2, 0, 5) * CFrame.Angles(0, math.pi / 2, 0), "LEAVE")

	-- key pickups around the room, and the collectible (a brass bell) on the mantel
	local pickups = Instance.new("Folder")
	pickups.Name = "Pickups"
	pickups.Parent = room
	for i, pos in
		{
			Vector3.new(X - 9, 1.6, -8),
			Vector3.new(X + 9, 1.6, -8),
			Vector3.new(X + 2, 6.9, D / 2 - 1.2),
			Vector3.new(X - 6.5, 2.8, 0),
		}
	do
		kit.pickup(pickups, "Key" .. i, pos)
	end
	local bell = kit.cylinder(
		room,
		"Collectible",
		0.7,
		0.8,
		Vector3.new(X - W / 2 + 0.8, 5.95, 2),
		"y",
		C.brass,
		Enum.Material.Metal,
		{
			CanCollide = false,
			CastShadow = false,
		}
	)
	TrialKit.pointLight(bell, 5, 0.5, false, Color3.fromRGB(255, 210, 140))

	-- where the server puts the players who come in (facing the other door)
	kit.marker(room, "Arrive", CFrame.new(X, 3, 3))
	return room
end

return TestLounge
