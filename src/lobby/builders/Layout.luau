--[[
	The lobby floor plan (world coordinates, studs). Rooms are interior bounds; walls are WALL thick
	and sit OUTSIDE these bounds. +Z is the front (arrival), -Z the back (the doors).

	                       +Z (front)
	        ┌──────────── SHOP ─────────┐┌──────────── FOYER (spawn) ──────────┐
	        │ x -30..-6  z 42..66  y=+6 ││ x -2..30   z 42..66  y=+6           │
	        │                     door ═╡╞═ (x -6..-2, z 48..58)  house stairs │
	        └───────────────────────────┘└──────┐ grand stair ┌──────────────── ┘
	                                            │ x 4..20      │  down 6 studs (z 42 -> 30)
	   ┌──────────────────── READING HALL ──────┘ z 30..42     └──────────────┐
	   │ x -32..32  z -20..30  y=0     windows (natatorium) on the -X wall    │══ doorway x 32..36,
	   │                                                                       │   z -2..6, stairs down
	   └──────────────────┐   arch x -9..9 (z -24..-20)   ┌───────────────────┘   to WORKSHOP
	 ┌────────────────────┘                               └───────────────────┐   x 36..62 z -14..18 y=-5
	 │ DOOR HALL  x -36..36  z -60..-24  y=0       six doors on the z=-60 wall │
	 └─────────────────────────────────────────────────────────────────────────┘
]]
local Layout = {}

Layout.WALL = 4

-- Each room: interior x0..x1, z0..z1, floor y, ceiling height above the floor.
Layout.Rooms = {
	Foyer = { x0 = -2, x1 = 30, z0 = 42, z1 = 66, y = 6, h = 14 },
	Shop = { x0 = -30, x1 = -6, z0 = 42, z1 = 66, y = 6, h = 13 },
	Stair = { x0 = 4, x1 = 20, z0 = 30, z1 = 42, y = 0, h = 19 }, -- grand stair corridor, top y=6 at z=42
	Hall = { x0 = -32, x1 = 32, z0 = -20, z1 = 30, y = 0, h = 16 },
	DoorHall = { x0 = -36, x1 = 36, z0 = -60, z1 = -24, y = 0, h = 18 },
	Workshop = { x0 = 36, x1 = 62, z0 = -14, z1 = 18, y = -5, h = 14 },
}

-- Openings between rooms (wall-through holes). axis "x" = hole in a wall that runs along X (normal Z).
Layout.Openings = {
	ShopDoor = { axis = "z", x0 = -6, x1 = -2, z0 = 47, z1 = 59, y0 = 6, y1 = 16 }, -- shop <-> foyer
	StairTop = { axis = "x", x0 = 4, x1 = 20, z0 = 38, z1 = 42, y0 = 0, y1 = 16 }, -- foyer -> stair (top step z=42)
	StairFoot = { axis = "x", x0 = 4, x1 = 20, z0 = 30, z1 = 34, y0 = 0, y1 = 13 }, -- stair -> hall
	Arch = { axis = "x", x0 = -9, x1 = 9, z0 = -24, z1 = -20, y0 = 0, y1 = 13 }, -- hall -> door hall
	WorkshopDoor = { axis = "z", x0 = 32, x1 = 36, z0 = -2, z1 = 6, y0 = 0, y1 = 9 }, -- hall -> workshop
}

Layout.Spawn = CFrame.new(12, 6.1, 51) -- faces -Z, straight down the grand stair
Layout.Guide = { position = Vector3.new(4.5, 6, 45.5), facing = Vector3.new(12, 6, 51) }
-- The shopkeeper stands behind the gift-shop counter (counter x = -20.8, z 47.5..58.5), facing the customers (+X).
-- Keep the floor behind the counter (x -25..-22, z 50..56) clear of props.
-- (the shop's marble floor is laid 0.1 above the slab, so he stands at y = 6.1)
Layout.Shopkeeper = { position = Vector3.new(-23.4, 6.1, 53.2), facing = Vector3.new(-12, 6.1, 53.2) }

-- Reading-hall reward stations: a glowing ring on the floor (walk onto it to open that station's UI)
-- with its object just behind it. Spread round the edges so the middle of the hall (the rug) and the
-- arch stay open: nothing stands between the stair foot and the doorway to the door hall.
--   Wheel      the left aisle, in the gap between the two study desks (z -5 / 9 at x -21..-13), its
--              frame (11.7 wide, 14.3 tall) facing the walkway, turned 12 degrees toward the stair;
--              the ring (6.84 in front) sits in the gap between the left pillars. Any more turn puts
--              the ring onto the front desk's chairs.
--   Daily      the right side of the hall, mirrored with Challenges across z = 2 (the centreline
--   Challenges of the workshop doorway, z -2..6), so the pair flank the path to the workshop. Both
--              rings sit at x 12.7: clear of the stair->arch walkway on their left and 4.7 off the
--              right pillar (20, -7.5) on their right. Each object stands 6.3 back from its ring at
--              65 degrees off +X (away from the path), turned to face it: the chest toward the stair,
--              the desk (+ card catalogue on its local +X end) toward the arch. He stands 1.75
--              behind his desk.
-- ring = floor centre (y = hall floor), object = floor-level CFrame whose -Z (LookVector) is the front.
-- radius = the ring's bright rim AND the client trigger (Rewards.client: inside radius enters, +1 stays).
Layout.Stations = {
	Daily = {
		ring = Vector3.new(12.7, 0, 11),
		radius = 4.7,
		object = CFrame.lookAt(Vector3.new(15.3625, 0, 16.7097), Vector3.new(12.7, 0, 11)),
	},
	Wheel = {
		ring = Vector3.new(-11.8095, 0, 3.4221),
		radius = 4.7,
		object = CFrame.lookAt(Vector3.new(-18.5, 0, 2), Vector3.new(-11.8095, 0, 3.4221)),
	},
	Challenges = {
		ring = Vector3.new(12.7, 0, -7),
		radius = 4.7,
		object = CFrame.lookAt(Vector3.new(15.3625, 0, -12.7097), Vector3.new(12.7, 0, -7)), -- the desk
	},
}
-- he stands 1.75 behind his desk, facing the same way
Layout.Stations.Challenges.npc = Layout.Stations.Challenges.object * CFrame.new(0, 0, 1.75)

-- Door wall
Layout.DoorWallZ = -60
Layout.DoorXs = { A = { -29, -19, -9 }, B = { 29, 19, 9 } }
-- each door sits in a real hole in the back wall, so an opening door shows depth (a black void)
Layout.DoorOpenings = {}
for wing, xs in Layout.DoorXs do
	for i, x in xs do
		local name = "Door" .. wing .. i
		Layout.Openings[name] =
			{ axis = "x", x0 = x - 2.7, x1 = x + 2.7, z0 = -64, z1 = -60, y0 = 0, y1 = 9.2, noReveal = true }
		table.insert(Layout.DoorOpenings, name)
	end
end
table.sort(Layout.DoorOpenings)

-- Natatorium (outside, seen through the reading hall's -X windows)
Layout.HallWindows = { y0 = 5, y1 = 12, list = { { z = -8, w = 10 }, { z = 8, w = 10 }, { z = 22, w = 8 } } }

return Layout
