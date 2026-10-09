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
-- with its object just behind it. Kept off the stair->arch walkway, the workshop path and the desks:
--   Challenges the archivist's desk in the alcove between the two study desks, facing +X: the one
--              spot on the left that the (-8, 17.5) pillar hides from neither the stair foot nor the
--              walkway. The desk assembly (desk + card catalogue on its +Z end) spans z ~-0.25..4.4,
--              x -19.2..-18.0; he stands 1.75 behind it, clear of the nook rug (x <= -21.15).
--   Wheel      back-right, dead ahead from the stair, a big centrepiece turned toward its ring; its
--              plinth stays inside the back wall (z >= -19.8) and left of the reading table (x <= 20.2)
--   Daily      out in the open in the middle of the hall, just left of the stair->arch walkway: in
--              view from the stair foot (and from the top of the grand stair). The ring sits between
--              the walkway (x >= ~4 here) and the front-left pillar (-8, 17.5); the chest stands on its
--              -X side, turned to face the ring and the players coming down from the stair.
-- ring = floor centre (y = hall floor), object = floor-level CFrame whose -Z (LookVector) is the front.
-- radius = the ring's bright rim AND the client trigger (Rewards.client: inside radius enters, +1 stays).
Layout.Stations = {
	Daily = {
		ring = Vector3.new(-2.3, 0, 11.6),
		radius = 4.7,
		object = CFrame.lookAt(Vector3.new(-8.6, 0, 10.4), Vector3.new(-2.3, 0, 11.6)),
	},
	Wheel = {
		ring = Vector3.new(12.6, 0, -9.8),
		radius = 4.7,
		object = CFrame.lookAt(Vector3.new(14, 0, -16.5), Vector3.new(12.6, 0, -9.8)),
	},
	Challenges = {
		ring = Vector3.new(-12, 0, 2.2),
		radius = 4.6,
		object = CFrame.lookAt(Vector3.new(-18.6, 0, 1.4), Vector3.new(-10, 0, 1.4)), -- the desk
		npc = CFrame.lookAt(Vector3.new(-20.35, 0, 1.4), Vector3.new(-10, 0, 1.4)), -- stands behind it
	},
}

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
