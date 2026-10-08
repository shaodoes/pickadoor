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
