--[[
	TrialBuilder: the trial place's door room, built from primitives under one Model named "Trial", plus
	the empty Trial.Worlds folder the worlds are moved into when they're played (WorldHost builds each
	world lazily with its Worlds/<Module>.luau builder and TrialKit; see Shared.Worlds for the list).

	Layout (local coordinates; `opts.offset` shifts everything, so the room can be previewed inside the
	lobby place far away from the library):
	  DoorRoom   40 x 44 x 15 around the origin. Two doors in the -Z wall: Doors.Left (red, x -8) and
	             Doors.Right (blue, x +8). Each has a Leaf the server swings open (DoorRoomFlow) with a
	             lever Handle and a blank brass Plaque on it, a Zone just in front of it (walking into it
	             commits you to that door) and a pitch-black void behind it. Spawn (SpawnLocation) and
	             Hold (where the dead and finished wait) at +Z. One hanging bulb; "PICK A DOOR" sprayed
	             on the wall above the doors in the lobby's stencil style.

	Names / attributes other code relies on:
	  Trial.DoorRoom.Doors.<Left|Right> (attribute Color "Red" | "Blue"): .Zone, .Leaf (attributes
	    HingeX, SwingAngle, HingeSide), .Handle / .Rose / .Plaque (Swing = true: moved with the leaf),
	    .Void.Blocker (stops anyone walking in until the door is open), .Stand (where the opener stands)
	  Trial.DoorRoom.Spawn (SpawnLocation), Trial.DoorRoom.Hold
	  Lights tagged "Flicker" (TrialKit.flicker): true = blinks, "furnace" = breathes (DoorRoomFlow's loop)
	  Marker parts (Spawn / Hold / Arrive): the CFrame is where a character's pivot goes.
]]
local Lighting = game:GetService("Lighting")

local TrialKit = require(script.Parent.TrialKit)

local TrialBuilder = {}

local C = TrialKit.C
local DETAIL = TrialKit.DETAIL
local INVISIBLE = TrialKit.INVISIBLE
local BLOCKER = TrialKit.BLOCKER

------------------------------------------------------------------------------------------
-- The Door Room
------------------------------------------------------------------------------------------
local ROOM_W, ROOM_D, ROOM_H = 40, 44, 15
local WALL_Z = -ROOM_D / 2 -- the doors' wall (centre of its 1-stud thickness)
local DOOR_W, DOOR_H = 6, 9 -- the leaf
local OPENING = 8 -- wall opening width (jambs fill the sides)
local HANDLE_Y = 3.3 -- the lever handle's height above the floor (low: you look down to it)

local PAINTS = {
	Red = { leaf = Color3.fromRGB(132, 28, 24), panel = Color3.fromRGB(150, 36, 30), line = Color3.fromRGB(82, 16, 14) },
	Blue = {
		leaf = Color3.fromRGB(30, 54, 118),
		panel = Color3.fromRGB(38, 66, 138),
		line = Color3.fromRGB(16, 28, 66),
	},
}

-- Painted panels drawn on the leaf so they swing with it.
local function leafFace(leaf: BasePart, paint)
	local pps = 40
	local gui = TrialKit.surfaceGui(leaf, pps)
	gui.LightInfluence = 0.9
	gui.Brightness = 0.2
	local W, H = DOOR_W * pps, DOOR_H * pps
	for _, spec in { { 0.08, 0.36 }, { 0.5, 0.42 } } do
		local panel = TrialKit.frame(
			gui,
			"Panel",
			UDim2.fromOffset(W * 0.14, H * spec[1]),
			UDim2.fromOffset(W * 0.72, H * spec[2]),
			paint.panel,
			1,
			1
		)
		local stroke = Instance.new("UIStroke")
		stroke.Color = paint.line
		stroke.Thickness = 4
		stroke.Transparency = 0.2
		stroke.Parent = panel
		local inner =
			TrialKit.frame(panel, "Inner", UDim2.fromOffset(6, 6), UDim2.new(1, -12, 1, -12), paint.panel, 0.4, 1)
		TrialKit.round(inner, UDim.new(0, 3))
	end
	-- grime climbing from the floor
	local grime = TrialKit.frame(
		gui,
		"Grime",
		UDim2.fromOffset(0, H * 0.84),
		UDim2.fromOffset(W, H * 0.16),
		Color3.fromRGB(40, 30, 26),
		0.55,
		2
	)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(1, 0.1)
	fade.Parent = grime
end

-- One door in the -Z wall at `x`: jambs, header, a Leaf hinged on `hingeSide` (-1 = its -X edge,
-- +1 = its +X edge) that swings into a pitch-black void, its lever handle and plaque, and the Zone / Mat
-- in front of it.
local function buildDoor(parent: Instance, kit, name: string, x: number, colorName: string, hingeSide: number)
	local door = kit.model(parent, name)
	door:SetAttribute("Color", colorName)
	local paint = PAINTS[colorName]
	local frameColor = Color3.fromRGB(64, 50, 38)
	for _, s in { -1, 1 } do
		kit.box(
			door,
			"Jamb",
			Vector3.new(1, DOOR_H + 0.5, 1.2),
			Vector3.new(x + s * (DOOR_W / 2 + 0.5), (DOOR_H + 0.5) / 2, WALL_Z),
			frameColor,
			Enum.Material.Wood
		)
	end
	kit.box(
		door,
		"Header",
		Vector3.new(OPENING + 1, 1, 1.2),
		Vector3.new(x, DOOR_H + 0.5 + 0.5, WALL_Z),
		frameColor,
		Enum.Material.Wood
	)
	-- a small caged lamp over each door, so the two colours read from the spawn in the dark
	local sconce = kit.box(
		door,
		"Sconce",
		Vector3.new(0.5, 0.5, 0.5),
		Vector3.new(x, DOOR_H + 1.75, WALL_Z + 0.9),
		C.bulb,
		Enum.Material.Neon,
		DETAIL
	)
	sconce.Shape = Enum.PartType.Ball
	sconce.Transparency = 0.3
	TrialKit.halo(sconce, 2.2)
	TrialKit.flicker(TrialKit.pointLight(sconce, 16, 0.9, false, C.cage), true, 0.006)
	-- rotated 180 degrees so the leaf's Front face (and its SurfaceGui) looks into the room (+Z)
	local leafCf = CFrame.new(x, DOOR_H / 2, WALL_Z) * CFrame.Angles(0, math.pi, 0)
	local leaf = kit.box(door, "Leaf", Vector3.new(DOOR_W, DOOR_H, 0.4), leafCf, paint.leaf, Enum.Material.Wood)
	-- hinge in the leaf's own frame (its +X is the world's -X after the half turn); it swings into the void
	leaf:SetAttribute("HingeX", -hingeSide * DOOR_W / 2)
	leaf:SetAttribute("HingeSide", hingeSide)
	leaf:SetAttribute("SwingAngle", math.rad(-hingeSide * 95)) -- just past square: clears the void's side wall
	leaf:SetAttribute("Swing", true)
	leafFace(leaf, paint)

	-- lever handle on the latch side: a round rose and a lever pointing back toward the hinge
	local latch = hingeSide * (DOOR_W / 2 - 0.65)
	local roseCf = leafCf * CFrame.new(latch, HANDLE_Y - DOOR_H / 2, -0.26)
	local rose = kit.cylinder(door, "Rose", 0.12, 0.42, roseCf, "z", C.brass, Enum.Material.Metal, DETAIL)
	rose:SetAttribute("Swing", true)
	local handle = kit.box(
		door,
		"Handle",
		Vector3.new(0.85, 0.14, 0.16),
		roseCf * CFrame.new(-hingeSide * 0.36, 0, -0.16),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	handle:SetAttribute("Swing", true)
	-- (the client turns it about the Rose: a cylinder, so its X axis is the leaf normal through its centre)
	-- a blank brass plaque at eye level: the committing player's client stamps their world on it
	local plaque = kit.box(
		door,
		"Plaque",
		Vector3.new(2.2, 0.7, 0.06),
		leafCf * CFrame.new(0, 1.9, -0.23),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	plaque:SetAttribute("Swing", true)

	-- the void: a black box behind the opening (Neon black never catches light, so it reads as nothing),
	-- and a blocker so nobody walks in until the door is open
	local void = kit.model(door, "Void")
	local vd, vw, vh = 12, OPENING, DOOR_H + 1
	local vz = WALL_Z - 0.5 - vd / 2
	local black = { Material = Enum.Material.Neon }
	kit.box(void, "Floor", Vector3.new(vw + 2, 1, vd), Vector3.new(x, -0.5, vz), Color3.new(), nil, black)
	kit.box(void, "Ceiling", Vector3.new(vw + 2, 1, vd), Vector3.new(x, vh + 0.5, vz), Color3.new(), nil, black)
	kit.box(
		void,
		"Back",
		Vector3.new(vw + 2, vh + 2, 1),
		Vector3.new(x, vh / 2, WALL_Z - 0.5 - vd - 0.5),
		Color3.new(),
		nil,
		black
	)
	for _, s in { -1, 1 } do
		kit.box(
			void,
			"Side",
			Vector3.new(1, vh + 2, vd),
			Vector3.new(x + s * (vw / 2 + 0.5), vh / 2, vz),
			Color3.new(),
			nil,
			black
		)
	end
	kit.box(void, "Blocker", Vector3.new(OPENING, vh, 0.4), Vector3.new(x, vh / 2, WALL_Z - 0.8), C.void, nil, BLOCKER)

	-- walking into the Zone commits you to this door; the opener is then stepped up to Stand
	kit.box(
		door,
		"Zone",
		Vector3.new(OPENING - 1, 8, 4.6),
		Vector3.new(x, 4, WALL_Z + 0.6 + 2.3),
		Color3.new(1, 1, 1),
		nil,
		INVISIBLE
	)
	kit.marker(door, "Stand", CFrame.new(x - hingeSide * 1.5, 3, WALL_Z + 2.3))
	kit.box(
		door,
		"Mat",
		Vector3.new(7, 0.1, 5),
		Vector3.new(x, 0.05, WALL_Z + 3),
		Color3.fromRGB(70, 52, 40),
		Enum.Material.Fabric,
		DETAIL
	)
	return door
end

local function buildDoorRoom(parent: Instance, kit)
	local room = kit.model(parent, "DoorRoom")
	local W, D, H = ROOM_W, ROOM_D, ROOM_H

	kit.box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(0, -0.5, 0), C.carpet, Enum.Material.Carpet)
	-- worn track from the spawn to the doors
	kit.box(
		room,
		"Worn",
		Vector3.new(14, 0.04, D - 8),
		Vector3.new(0, 0.02, -2),
		C.carpetWorn,
		Enum.Material.Carpet,
		DETAIL
	)
	kit.box(room, "Ceiling", Vector3.new(W, 1, D), Vector3.new(0, H + 0.5, 0), C.plaster)
	kit.box(room, "Stain", Vector3.new(9, 0.04, 7), Vector3.new(6, H - 0.02, -4), C.stain, nil, DETAIL)

	-- side walls and the +Z wall are whole; the -Z wall is built around the two openings
	for _, s in { -1, 1 } do
		kit.box(
			room,
			"Wall",
			Vector3.new(1, H, D),
			Vector3.new(s * (W / 2 + 0.5), H / 2, 0),
			C.wallpaper,
			Enum.Material.Fabric
		)
	end
	kit.box(
		room,
		"Wall",
		Vector3.new(W + 2, H, 1),
		Vector3.new(0, H / 2, D / 2 + 0.5),
		C.wallpaper,
		Enum.Material.Fabric
	)
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
		kit.box(
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
		kit.box(
			room,
			"Wall",
			Vector3.new(OPENING, H - top, 1),
			Vector3.new(x, (H + top) / 2, WALL_Z),
			C.wallpaper,
			Enum.Material.Fabric
		)
	end

	-- wallpaper: faded vertical stripes, a dark wainscot and a picture rail all round
	local stripes = kit.model(room, "Wallpaper")
	for x = -W / 2 + 2, W / 2 - 2, 3 do
		if math.abs(x - doorX[1]) > OPENING / 2 + 0.6 and math.abs(x - doorX[2]) > OPENING / 2 + 0.6 then
			kit.box(
				stripes,
				"Stripe",
				Vector3.new(0.9, H, 0.04),
				Vector3.new(x, H / 2, WALL_Z + 0.52),
				C.wallpaperStripe,
				Enum.Material.Fabric,
				DETAIL
			)
		end
		kit.box(
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
			kit.box(
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
	local trim = kit.model(room, "Trim")
	local wainscotH, railY = 3, 3.1
	for _, s in { -1, 1 } do
		kit.box(
			trim,
			"Wainscot",
			Vector3.new(0.12, wainscotH, D),
			Vector3.new(s * (W / 2 - 0.06), wainscotH / 2, 0),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
			trim,
			"Rail",
			Vector3.new(0.2, 0.16, D),
			Vector3.new(s * (W / 2 - 0.1), railY, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
			trim,
			"PictureRail",
			Vector3.new(0.14, 0.14, D),
			Vector3.new(s * (W / 2 - 0.07), H - 0.8, 0),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	kit.box(
		trim,
		"Wainscot",
		Vector3.new(W, wainscotH, 0.12),
		Vector3.new(0, wainscotH / 2, D / 2 - 0.06),
		C.wood,
		Enum.Material.Wood,
		DETAIL
	)
	kit.box(
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
		kit.box(
			trim,
			"Wainscot",
			Vector3.new(x1 - x0, wainscotH, 0.12),
			Vector3.new((x0 + x1) / 2, wainscotH / 2, WALL_Z + 0.56),
			C.wood,
			Enum.Material.Wood,
			DETAIL
		)
		kit.box(
			trim,
			"Rail",
			Vector3.new(x1 - x0, 0.16, 0.2),
			Vector3.new((x0 + x1) / 2, railY, WALL_Z + 0.6),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	kit.box(
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
	buildDoor(doors, kit, "Left", doorX[1], "Red", -1)
	buildDoor(doors, kit, "Right", doorX[2], "Blue", 1)

	-- the one bulb, hung low between the spawn and the doors so the doors are what you see
	kit.hangingBulb(room, Vector3.new(0, 10.2, -6), H, 48, 1.5, true)

	-- PICK A DOOR, sprayed on the wall above the doors, facing the room (+Z)
	kit.stencil(
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
	spawnPoint.CFrame = kit.place(CFrame.new(0, 0.1, D / 2 - 6))
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = room
	-- where the dead and the finished wait out the round (by the back wall, facing the doors)
	kit.marker(room, "Hold", CFrame.new(0, 3, D / 2 - 3))
	return room
end

------------------------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------------------------
export type BuildOpts = { parent: Instance?, offset: Vector3? }

function TrialBuilder.build(opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
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
	buildDoorRoom(trial, TrialKit.at(o.offset or Vector3.zero))
	local worlds = Instance.new("Folder")
	worlds.Name = "Worlds"
	worlds.Parent = trial
	trial.Parent = parent

	-- A preview inside another place must not touch that place's Lighting. (Inside a world the client's
	-- WorldMood takes over; this is the door room's look, and WorldMood.DoorRoom repeats it: keep in step.)
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
	return trial
end

return TrialBuilder
