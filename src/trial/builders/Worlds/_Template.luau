--[[
	_Template: the copy-me world builder. A world is three files with the same module name:
	  src/trial/builders/Worlds/<M>.luau   this: the map (server, built once, lazily, then cached)
	  src/trial/server/Worlds/<M>.luau     the rules: start(ctx) -> controller (see server/_Template)
	  src/trial/client/Worlds/<M>.luau     local effects: enter(ctx) -> cleanup (see client/_Template)
	and a catalogue entry in Shared.Worlds with play.module = "<M>" and playable = true.

	Contract:
	  Builder.build(parent: Instance, origin: Vector3, kit) -> Model
	    `kit` is TrialKit.at(origin): build in LOCAL coordinates through kit.box / kit.model / ...
	    (origin is passed too for anything that needs world space, e.g. terrain). Parent everything to
	    one Model created with kit.model(parent, "World"); WorldHost renames it to the world's id.
	  The model must contain:
	    Arrive     kit.marker: where players are placed (pivot 3 studs up, facing LookVector)
	    Exit       kit.exitDoor: the way out (danger worlds: works once the last objective is done)
	  and may contain:
	    FollowDoor kit.followDoor (lounges: FOLLOW THEM IN, into the round's dangerous world)
	    Guide      Folder of kit.guideNode parts (the blue path's fallback graph, links by name)
	    Pickups    Folder of kit.pickup keys (lounges);  Collectible  a part (lounges, Lounge.luau)
	    step targets: any parts the server module's steps point at (by name)
	  Own lights: TrialKit.pointLight (+ TrialKit.flicker to make them blink); the client's WorldMood
	  sets Lighting from the catalogue's play.mood while you're inside.
	  Keep it under ~1,500 parts; worlds sit 500 studs apart (Config.Worlds.slotSpacing), so stay
	  within about 200 studs of the origin.
]]
local TrialKit = require(script.Parent.Parent.TrialKit)

local Template = {}

local C = TrialKit.C

function Template.build(parent: Instance, _origin: Vector3, kit): Model
	local room = kit.model(parent, "World")
	local W, D, H = 30, 40, 12

	-- shell: floor, ceiling, four walls
	kit.box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(0, -0.5, 0), C.concrete, Enum.Material.Concrete)
	kit.box(room, "Ceiling", Vector3.new(W, 1, D), Vector3.new(0, H + 0.5, 0), C.ceiling, Enum.Material.Concrete)
	for _, s in { -1, 1 } do
		kit.box(
			room,
			"Wall",
			Vector3.new(1, H, D),
			Vector3.new(s * (W / 2 + 0.5), H / 2, 0),
			C.block,
			Enum.Material.Concrete
		)
		kit.box(
			room,
			"Wall",
			Vector3.new(W + 2, H, 1),
			Vector3.new(0, H / 2, s * (D / 2 + 0.5)),
			C.block,
			Enum.Material.Concrete
		)
	end
	kit.hangingBulb(room, Vector3.new(0, H - 3, 6), H, 40, 1.4, true)
	kit.hangingBulb(room, Vector3.new(0, H - 3, -12), H, 40, 1.2, true)

	-- step 1's target: a red button on a post (the server module puts the prompt on it)
	kit.box(room, "Post", Vector3.new(1, 3, 1), Vector3.new(8, 1.5, -6), C.steel, Enum.Material.Metal)
	kit.box(
		room,
		"Button",
		Vector3.new(0.8, 0.3, 0.8),
		Vector3.new(8, 3.15, -6),
		Color3.fromRGB(200, 40, 30),
		Enum.Material.Neon
	)

	-- the way out (step 2 is "reach the exit"; the prompt works after it)
	kit.exitDoor(room, CFrame.new(0, 0, -D / 2) * CFrame.Angles(0, math.pi, 0))
	kit.marker(room, "ExitZone", CFrame.new(0, 3, -D / 2 + 4))

	-- guide graph: Arrive -> middle -> button / exit
	local guide = Instance.new("Folder")
	guide.Name = "Guide"
	guide.Parent = room
	kit.guideNode(guide, "A", Vector3.new(0, 0.5, 14), { "B" })
	kit.guideNode(guide, "B", Vector3.new(0, 0.5, 0), { "A", "C", "D" })
	kit.guideNode(guide, "C", Vector3.new(6, 0.5, -6), { "B" })
	kit.guideNode(guide, "D", Vector3.new(0, 0.5, -16), { "B" })

	kit.marker(room, "Arrive", CFrame.new(0, 3, 15))
	return room
end

return Template
