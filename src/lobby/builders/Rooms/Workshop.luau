--[[
	The Workshop: the basement's boiler room, taken over as a lantern workshop.

	Down a short timber stair from the reading hall's east doorway. Built like an old mine gallery:
	plank-lined walls and ceiling, heavy timber "sets" (posts + caps + knee braces), a plank floor,
	brick fire-wall behind the furnace and a patch of the old stone foundation showing through.

	  south wall   cast-iron furnace (glowing grate, flue into the ceiling), coal bin, log stack,
	               copper boiler tank in the corner with gauges, a valve and a leaking joint
	  north wall   the lantern bench: pegboard with every lantern, tools, vise, stool, "LANTERNS"
	  east wall    stone patch under a caged work light, barrels, shelves of oil and candles
	  north-west   a lattice storage cage full of crates

	Everything is in world coordinates from Layout.Rooms.Workshop. The shell (concrete slab, walls,
	ceiling) comes from Shell.buildRoom; this module only lines and furnishes it.
	Public API: Workshop.build(root: Instance) -> Model ("Workshop" under root).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.Kit)
local Layout = require(script.Parent.Parent.Layout)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)
local RING_H = LanternBuilder.RingHeight or 2.4 -- ring centre above the lantern base

local C = Kit.C
local box = Kit.box
local cyl = Kit.cylinder
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local WOOD = Enum.Material.Wood
local PLANKS = Enum.Material.WoodPlanks
local METAL = Enum.Material.Metal

local R = Layout.Rooms.Workshop
local DOOR = Layout.Openings.WorkshopDoor
local X0, X1, Z0, Z1 = R.x0, R.x1, R.z0, R.z1
local FY = R.y -- top of the concrete slab
local CY = R.y + R.h -- underside of the concrete ceiling
local FLOOR = FY + 0.2 -- walking surface: plank floor laid over the slab (and over any shell tiles)
local CEIL = CY - 0.2 -- underside of the ceiling boards
local TOP = DOOR.y0 -- the hall floor / top landing

-- Wall lining: boards stand LINE off the concrete (clearing the shell's wainscot and rail), LT thick.
local LINE, LT = 0.3, 0.3
local IN = LINE + 0.05 + LT -- lining face, measured from the wall face
local RH = 0.92 -- board row height

-- Stair: a landing at hall level, then straight down eastward to the floor.
local SZ0, SZ1 = DOOR.z0 - 0.8, DOOR.z1 + 0.8 -- tread extent (a little wider than the doorway)
local SZC = (SZ0 + SZ1) / 2
local LAND_X1 = X0 + 3.5
local STEPS = 9
local RISE = (TOP - FLOOR) / (STEPS + 1) -- ~0.49; the 10th "step" is the floor
local RUN = 1.2

-- Timber framing
local SET_ZS = { -8, 10 } -- caps spanning X (posts on the west and east walls)
local BEAM_XS = { 44, 54 } -- longitudinal beams along Z (posts on the south and north walls)
local CAP_H, BEAM_H = 1.2, 0.9

local TONES = {
	Color3.fromRGB(104, 70, 44),
	Color3.fromRGB(92, 62, 40),
	Color3.fromRGB(116, 80, 50),
	Color3.fromRGB(82, 54, 34),
	Color3.fromRGB(126, 88, 56),
	Color3.fromRGB(98, 68, 46),
	Color3.fromRGB(74, 50, 32),
}
local FLOOR_TONES = {
	Color3.fromRGB(86, 62, 44),
	Color3.fromRGB(76, 54, 38),
	Color3.fromRGB(96, 70, 48),
	Color3.fromRGB(68, 50, 36),
	Color3.fromRGB(90, 64, 42),
}
local TIMBER = Color3.fromRGB(64, 44, 30)
local IRON = Color3.fromRGB(40, 38, 36)
local COPPER = Color3.fromRGB(124, 76, 50)
local ROPE = Color3.fromRGB(150, 124, 84)
local GLOW = Color3.fromRGB(255, 110, 40)

-- Own generator so the room lays out the same regardless of what was built before it.
local rng = Random.new(2718)

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function shade(color: Color3, amount: number): Color3
	local k = rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(color.R + k, 0, 1), math.clamp(color.G + k, 0, 1), math.clamp(color.B + k, 0, 1))
end

-- Box stretched from a to b (w across, h up).
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	w: number,
	h: number,
	color,
	material,
	extra
)
	local dir = b - a
	local up = math.abs(dir.Unit.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	return box(
		parent,
		name,
		Vector3.new(w, h, dir.Magnitude),
		CFrame.lookAt((a + b) / 2, b, up),
		color,
		material,
		extra
	)
end

-- Polygon ring in cf's local X-Y plane (rope loops, valve wheels, barrel-free hoops).
local function ring(
	parent: Instance,
	name: string,
	cf: CFrame,
	radius: number,
	thick: number,
	sides: number,
	color,
	material
)
	local chord = 2 * radius * math.sin(math.pi / sides)
	for i = 0, sides - 1 do
		local a = (i + 0.5) * 2 * math.pi / sides
		box(
			parent,
			name,
			Vector3.new(chord + thick * 0.6, thick, thick),
			cf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2),
			color,
			material,
			DETAIL
		)
	end
end

local function timber(parent: Instance, name: string, size: Vector3, cf, extra)
	return box(parent, name, size, cf, shade(TIMBER, 0.03), WOOD, extra)
end

local function chain(parent: Instance, top: Vector3, bottom: Vector3)
	local len = (top - bottom).Magnitude
	local n = math.max(1, math.floor(len / 0.3))
	for i = 0, n - 1 do
		local p = top:Lerp(bottom, (i + 0.5) / n)
		box(
			parent,
			"Link",
			Vector3.new(0.14, len / n + 0.08, 0.05),
			CFrame.new(p) * CFrame.Angles(0, (i % 2) * math.pi / 2, 0),
			IRON,
			METAL,
			DETAIL
		)
	end
end

-- Round dial gauge on a surface; `facing` points out of the dial.
local function gauge(parent: Instance, pos: Vector3, facing: Vector3, d: number, needle: number)
	local cf = CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, math.pi / 2, 0) -- local +X = facing
	local cylinder = { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false }
	box(parent, "GaugeRim", Vector3.new(0.2, d, d), cf, C.brass, METAL, cylinder)
	box(
		parent,
		"GaugeFace",
		Vector3.new(0.05, d * 0.8, d * 0.8),
		cf * CFrame.new(0.09, 0, 0),
		Color3.fromRGB(198, 188, 164),
		nil,
		cylinder
	)
	box(
		parent,
		"GaugeNeedle",
		Vector3.new(0.03, d * 0.34, 0.04),
		cf * CFrame.new(0.13, 0, 0) * CFrame.Angles(needle, 0, 0) * CFrame.new(0, d * 0.16, 0),
		Color3.fromRGB(150, 24, 20),
		nil,
		DETAIL
	)
end

-- Handwheel valve on a stem rising from `pos`.
local function valve(parent: Instance, pos: Vector3, up: number)
	cyl(parent, "ValveStem", up, 0.16, pos + Vector3.new(0, up / 2, 0), "y", C.brass, METAL, DETAIL)
	local hub = CFrame.new(pos + Vector3.new(0, up, 0))
	ring(parent, "Wheel", hub * CFrame.Angles(math.pi / 2, 0, 0), 0.42, 0.09, 8, Color3.fromRGB(140, 30, 24), METAL)
	for _, a in { 0, math.pi / 2 } do
		box(
			parent,
			"Spoke",
			Vector3.new(0.84, 0.06, 0.06),
			hub * CFrame.Angles(0, a, 0),
			Color3.fromRGB(140, 30, 24),
			METAL,
			DETAIL
		)
	end
end

-- Wooden crate standing on `cf` (base centre). Body collides; the battens are detail.
local function crate(parent: Instance, cf: CFrame, size: Vector3, color: Color3?)
	local model = Kit.folder(parent, "Crate")
	local base = shade(color or Color3.fromRGB(122, 90, 58), 0.04)
	local frame = base:Lerp(Color3.new(0, 0, 0), 0.3)
	box(model, "Body", size, cf * CFrame.new(0, size.Y / 2, 0), base, PLANKS)
	local w, h, d = size.X / 2, size.Y, size.Z / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				model,
				"Corner",
				Vector3.new(0.24, h, 0.24),
				cf * CFrame.new(sx * (w - 0.08), h / 2, sz * (d - 0.08)),
				frame,
				WOOD,
				DETAIL
			)
		end
	end
	for _, sz in { -1, 1 } do
		for _, y in { h - 0.14 } do
			box(
				model,
				"Rail",
				Vector3.new(size.X, 0.24, 0.12),
				cf * CFrame.new(0, y, sz * (d + 0.02)),
				frame,
				WOOD,
				DETAIL
			)
		end
		local diag = math.sqrt(size.X * size.X + h * h) - 0.4
		box(
			model,
			"Brace",
			Vector3.new(diag, 0.22, 0.1),
			cf * CFrame.new(0, h / 2, sz * (d + 0.03)) * CFrame.Angles(0, 0, sz * math.atan2(h, size.X)),
			frame,
			WOOD,
			DETAIL
		)
	end
	return model
end

-- Barrel standing at `pos` (base centre).
local function barrel(parent: Instance, pos: Vector3, h: number, dia: number, color: Color3?)
	local model = Kit.folder(parent, "Barrel")
	local staves = shade(color or Color3.fromRGB(104, 66, 38), 0.03)
	cyl(model, "Body", h, dia, pos + Vector3.new(0, h / 2, 0), "y", staves, WOOD)
	cyl(model, "Belly", h * 0.5, dia + 0.16, pos + Vector3.new(0, h / 2, 0), "y", staves, WOOD, DETAIL)
	for _, f in { 0.12, 0.5, 0.88 } do
		local bulge = (f > 0.2 and f < 0.8) and 0.2 or 0.06
		cyl(model, "Hoop", 0.16, dia + bulge, pos + Vector3.new(0, h * f, 0), "y", IRON, METAL, DETAIL)
	end
	cyl(
		model,
		"Lid",
		0.06,
		dia - 0.2,
		pos + Vector3.new(0, h + 0.02, 0),
		"y",
		staves:Lerp(Color3.new(0, 0, 0), 0.35),
		WOOD,
		DETAIL
	)
	return model
end

-- Coil of rope lying flat at `pos`.
local function ropeCoil(parent: Instance, pos: Vector3, radius: number)
	-- cheap: stacked turns as short cylinders with a dark hole in the middle
	local model = Kit.folder(parent, "RopeCoil")
	for i = 0, 2 do
		cyl(
			model,
			"Rope",
			0.22,
			(radius - i * 0.06) * 2 + 0.22,
			pos + Vector3.new(0, 0.11 + i * 0.2, 0),
			"y",
			shade(ROPE, 0.04),
			Enum.Material.Fabric,
			i > 0 and DETAIL or nil
		)
	end
	cyl(
		model,
		"Hole",
		0.04,
		radius * 0.9,
		pos + Vector3.new(0, 0.63, 0),
		"y",
		Color3.fromRGB(30, 24, 18),
		Enum.Material.Fabric,
		DETAIL
	)
	return model
end

------------------------------------------------------------------------------------------
-- Lining: plank floor, plank walls with brick/stone patches, plank ceiling, timber sets
------------------------------------------------------------------------------------------
local SPAN = { S = { X0, X1 }, N = { X0, X1 }, W = { Z0, Z1 }, E = { Z0, Z1 } }

-- CFrame of a point on a wall: u along the wall, v height, d out from the wall face into the room.
local function wallCF(wall: string, u: number, v: number, d: number): CFrame
	if wall == "S" then
		return CFrame.new(u, v, Z0 + d)
	elseif wall == "N" then
		return CFrame.new(u, v, Z1 - d)
	elseif wall == "W" then
		return CFrame.new(X0 + d, v, u)
	end
	return CFrame.new(X1 - d, v, u)
end

local function wallSize(wall: string, len: number, h: number, t: number): Vector3
	if wall == "S" or wall == "N" then
		return Vector3.new(len, h, t)
	end
	return Vector3.new(t, h, len)
end

local function row(k: number): number
	return FLOOR + k * RH
end

-- Subtract holes {u0,u1} from the interval list.
local function subtract(free, u0: number, u1: number)
	local out = {}
	for _, iv in free do
		if u1 <= iv[1] or u0 >= iv[2] then
			table.insert(out, iv)
		else
			if u0 > iv[1] then
				table.insert(out, { iv[1], u0 })
			end
			if u1 < iv[2] then
				table.insert(out, { u1, iv[2] })
			end
		end
	end
	return out
end

-- Horizontal boards in rows, broken at random lengths, skipping `holes` ({u0,u1,v0,v1}).
local function lineWall(parent: Instance, wall: string, holes)
	local u0, u1 = SPAN[wall][1], SPAN[wall][2]
	-- dark backing so the gaps between boards read as shadow lines, not grey concrete
	local backing = { { u0, u1 } }
	for _, hole in holes do
		if hole.full then
			backing = subtract(backing, hole.u0, hole.u1)
		end
	end
	for _, iv in backing do
		box(
			parent,
			"Backing",
			wallSize(wall, iv[2] - iv[1], CEIL - FY, 0.05),
			wallCF(wall, (iv[1] + iv[2]) / 2, (FY + CEIL) / 2, LINE + 0.025),
			Color3.fromRGB(28, 20, 14),
			WOOD,
			DETAIL
		)
	end
	local v = FLOOR
	while v < CEIL - 0.05 do
		local vb = math.min(v + RH, CEIL)
		local free = { { u0, u1 } }
		for _, hole in holes do
			if hole.v0 < vb - 0.01 and hole.v1 > v + 0.01 then
				free = subtract(free, hole.u0, hole.u1)
			end
		end
		for _, iv in free do
			local a = iv[1]
			while a < iv[2] - 0.05 do
				local len = math.min(rng:NextNumber(5, 12), iv[2] - a)
				if iv[2] - (a + len) < 1.2 then
					len = iv[2] - a
				end
				box(
					parent,
					"Board",
					wallSize(wall, len - 0.05, vb - v - 0.07, LT),
					wallCF(wall, a + len / 2, (v + vb) / 2, LINE + 0.05 + LT / 2 + rng:NextNumber(-0.04, 0.04)),
					pick(TONES),
					WOOD,
					{ CastShadow = false }
				)
				a += len
			end
		end
		v = vb
	end
end

-- Masonry showing through a gap in the boards, with a few loose blocks breaking the straight edge.
local function masonry(parent: Instance, wall: string, hole, color: Color3, material: Enum.Material)
	local w, h = hole.u1 - hole.u0, hole.v1 - hole.v0
	local uc, vc = (hole.u0 + hole.u1) / 2, (hole.v0 + hole.v1) / 2
	box(
		parent,
		"Masonry",
		wallSize(wall, w, h, IN - 0.08),
		wallCF(wall, uc, vc, (IN - 0.08) / 2),
		color,
		material,
		{ CastShadow = false }
	)
	for i = 1, 12 do
		local side = i % 4
		local u, v
		if side == 0 then
			u, v = rng:NextNumber(hole.u0, hole.u1), hole.v1
		elseif side == 1 then
			u, v = hole.u0, rng:NextNumber(hole.v0 + 0.5, hole.v1)
		elseif side == 2 then
			u, v = hole.u1, rng:NextNumber(hole.v0 + 0.5, hole.v1)
		else
			u, v = rng:NextNumber(hole.u0, hole.u1), hole.v0
		end
		if v > FLOOR + 0.3 then
			box(
				parent,
				"Stone",
				wallSize(wall, rng:NextNumber(0.8, 1.6), rng:NextNumber(0.5, 0.8), 0.25),
				wallCF(wall, u, v, IN + 0.05),
				shade(color, 0.04),
				material,
				DETAIL
			)
		end
	end
end

local function buildLining(model: Instance)
	local lining = Kit.folder(model, "Lining")

	-- plank floor, boards running toward the stair, butt joints staggered
	local z = Z0
	while z < Z1 - 0.01 do
		local width = math.min(1.15, Z1 - z)
		local x = X0
		while x < X1 - 0.01 do
			local len = math.min(rng:NextNumber(8, 16), X1 - x)
			if X1 - (x + len) < 2 then
				len = X1 - x
			end
			box(
				lining,
				"FloorBoard",
				Vector3.new(len - 0.04, 0.2, width - 0.05),
				Vector3.new(x + len / 2, FY + 0.1, z + width / 2),
				pick(FLOOR_TONES),
				WOOD,
				{ CastShadow = false }
			)
			x += len
		end
		z += width
	end
	-- dark gaps between the floor boards
	box(
		lining,
		"FloorGaps",
		Vector3.new(X1 - X0, 0.15, Z1 - Z0),
		Vector3.new((X0 + X1) / 2, FY + 0.075, (Z0 + Z1) / 2),
		Color3.fromRGB(26, 18, 12),
		WOOD,
		{
			CastShadow = false,
			CanCollide = false,
			CanQuery = false,
		}
	)

	-- walls
	local brick = { u0 = 44.6, u1 = 53.4, v0 = FY, v1 = row(10) } -- fire wall behind the furnace
	local stone = { u0 = -1.2, u1 = 5.6, v0 = row(2), v1 = row(9) } -- old foundation on the east wall
	local stair = { u0 = SZ0, u1 = SZ1, v0 = FY, v1 = CY, full = true } -- doorway + landing
	lineWall(lining, "S", { brick })
	lineWall(lining, "N", {})
	lineWall(lining, "W", { stair })
	lineWall(lining, "E", { stone })
	masonry(lining, "S", brick, Color3.fromRGB(110, 58, 44), Enum.Material.Brick)
	masonry(lining, "E", stone, Color3.fromRGB(104, 90, 74), Enum.Material.Cobblestone)
	-- soot above the furnace
	box(
		lining,
		"Soot",
		Vector3.new(5, 4.5, 0.05),
		Vector3.new(49, row(8), Z0 + IN - 0.04),
		Color3.fromRGB(20, 16, 14),
		Enum.Material.Slate,
		{ Transparency = 0.35, CanCollide = false, CanQuery = false, CastShadow = false }
	)

	-- ceiling boards across the room, small joists along it
	local zc = Z0
	while zc < Z1 - 0.01 do
		local width = math.min(1.6, Z1 - zc)
		box(
			lining,
			"CeilingBoard",
			Vector3.new(X1 - X0, 0.2, width - 0.06),
			Vector3.new((X0 + X1) / 2, CY - 0.1, zc + width / 2),
			shade(TONES[4], 0.03),
			WOOD,
			{ CastShadow = false }
		)
		zc += width
	end
	box(
		lining,
		"CeilingGaps",
		Vector3.new(X1 - X0, 0.05, Z1 - Z0),
		Vector3.new((X0 + X1) / 2, CY - 0.025, (Z0 + Z1) / 2),
		Color3.fromRGB(20, 14, 10),
		WOOD,
		DETAIL
	)
	for _, x in { 40.5, 47.5, 58.5 } do -- clear of the flue and the lamp roses
		timber(
			lining,
			"Joist",
			Vector3.new(0.5, 0.5, Z1 - Z0 - 2 * IN),
			Vector3.new(x, CEIL - 0.25, (Z0 + Z1) / 2),
			{ CastShadow = false }
		)
	end
end

local function buildFraming(model: Instance)
	local frame = Kit.folder(model, "Framing")
	local capY = CEIL - CAP_H -- underside of the caps
	local beamY = CEIL - BEAM_H -- underside of the longitudinal beams
	-- caps across the room, posts against the west and east walls, knee braces at each top
	for _, z in SET_ZS do
		timber(frame, "Cap", Vector3.new(X1 - X0 - 2 * IN, CAP_H, 1.1), Vector3.new((X0 + X1) / 2, capY + CAP_H / 2, z))
		for _, side in { -1, 1 } do
			local x = side < 0 and X0 + IN + 0.55 or X1 - IN - 0.55
			timber(frame, "Post", Vector3.new(1.1, capY - FLOOR, 1.1), Vector3.new(x, (FLOOR + capY) / 2, z))
			beam(
				frame,
				"Brace",
				Vector3.new(x, capY - 2, z),
				Vector3.new(x - side * 2, capY + 0.1, z),
				0.5,
				0.6,
				shade(TIMBER, 0.03),
				WOOD
			)
		end
	end
	-- longitudinal beams, posts against the south and north walls
	for _, x in BEAM_XS do
		timber(
			frame,
			"Beam",
			Vector3.new(BEAM_H, BEAM_H, Z1 - Z0 - 2 * IN),
			Vector3.new(x, beamY + BEAM_H / 2, (Z0 + Z1) / 2)
		)
		for _, side in { -1, 1 } do
			local z = side < 0 and Z0 + IN + 0.55 or Z1 - IN - 0.55
			timber(frame, "Post", Vector3.new(1.1, beamY - FLOOR, 1.1), Vector3.new(x, (FLOOR + beamY) / 2, z))
			beam(
				frame,
				"Brace",
				Vector3.new(x, beamY - 2, z),
				Vector3.new(x, beamY + 0.1, z - side * 2),
				0.5,
				0.6,
				shade(TIMBER, 0.03),
				WOOD
			)
			-- iron strap where post meets beam
			box(frame, "Strap", Vector3.new(1.2, 0.25, 1.2), Vector3.new(x, beamY - 0.4, z), IRON, METAL, DETAIL)
		end
	end
end

------------------------------------------------------------------------------------------
-- Stair: landing at hall level, nine steps down, closed stringers, timber posts and rails
------------------------------------------------------------------------------------------
local function nosingY(x: number): number
	return TOP - (x - LAND_X1) * RISE / RUN
end

local function buildStair(model: Instance)
	local stair = Kit.folder(model, "Stair")
	local width = SZ1 - SZ0

	-- landing: solid crib under a plank deck, flush with the hall floor
	box(
		stair,
		"LandingCrib",
		Vector3.new(LAND_X1 - X0, TOP - 0.15 - FY, width),
		Vector3.new((X0 + LAND_X1) / 2, (FY + TOP - 0.15) / 2, SZC),
		TIMBER,
		PLANKS
	)
	local n = 8
	for i = 0, n - 1 do
		box(
			stair,
			"Deck",
			Vector3.new(LAND_X1 - X0, 0.15, width / n - 0.05),
			Vector3.new((X0 + LAND_X1) / 2, TOP - 0.075, SZ0 + (i + 0.5) * width / n),
			pick(TONES),
			WOOD
		)
	end

	-- steps: a solid block under each tread so there is never a gap to catch a foot
	for i = 1, STEPS do
		local a = LAND_X1 + (i - 1) * RUN
		local t = TOP - i * RISE
		box(
			stair,
			"Riser",
			Vector3.new(RUN, t - 0.15 - FY, width),
			Vector3.new(a + RUN / 2, (FY + t - 0.15) / 2, SZC),
			shade(TONES[7], 0.02),
			WOOD
		)
		box(
			stair,
			"Tread",
			Vector3.new(RUN + 0.12, 0.15, width + 0.1),
			Vector3.new(a + RUN / 2 + 0.06, t - 0.075, SZC),
			pick(TONES),
			WOOD
		)
	end

	-- closed stringers: a plank-clad wedge down each side, capped with a heavy stringer beam
	local length = (TOP - FY) * RUN / RISE -- where the nosing line meets the slab
	local top, bottom = Vector3.new(LAND_X1, TOP + 0.25, 0), Vector3.new(LAND_X1 + length, FY + 0.25, 0)
	for _, side in { -1, 1 } do
		local z = side < 0 and SZ0 - 0.15 or SZ1 + 0.15
		local center = Vector3.new(LAND_X1 + length / 2, (FY + TOP) / 2, z)
		Kit.wedge(
			stair,
			"Skirt",
			Vector3.new(0.3, TOP - FY, length),
			CFrame.lookAt(center, center + Vector3.xAxis),
			TONES[2],
			PLANKS
		)
		local zs = side < 0 and SZ0 - 0.45 or SZ1 + 0.45
		beam(
			stair,
			"Stringer",
			top + Vector3.new(0, 0, zs),
			bottom + Vector3.new(-1.2, 0, zs),
			0.4,
			0.9,
			shade(TIMBER, 0.03),
			WOOD
		)
		-- landing sides
		box(
			stair,
			"LandingFascia",
			Vector3.new(LAND_X1 - X0, 0.9, 0.4),
			Vector3.new((X0 + LAND_X1) / 2, TOP - 0.2, zs),
			shade(TIMBER, 0.03),
			WOOD
		)
	end

	-- railings: heavy posts from the floor, handrail and mid rail following the nosing line
	-- last post where the nosing line meets the floor, a step's length past the foot
	local postXs = { X0 + 0.9, LAND_X1, LAND_X1 + 3 * RUN, LAND_X1 + 6 * RUN, LAND_X1 + (STEPS + 1) * RUN }
	for _, side in { -1, 1 } do
		local zp = side < 0 and SZ0 - 0.6 or SZ1 + 0.6
		local railTops = {}
		for k, x in postXs do
			local deck = x <= LAND_X1 and TOP or math.max(FLOOR, nosingY(x))
			local topY = deck + 3.3
			local bottomY = FLOOR -- every post stands on the floor, like pit props
			local w = (k == 2 or k == #postXs) and 0.75 or 0.55
			timber(stair, "RailPost", Vector3.new(w, topY - bottomY, w), Vector3.new(x, (topY + bottomY) / 2, zp))
			box(
				stair,
				"PostCap",
				Vector3.new(w + 0.15, 0.15, w + 0.15),
				Vector3.new(x, topY + 0.07, zp),
				shade(TIMBER, 0.03),
				WOOD,
				DETAIL
			)
			railTops[k] = Vector3.new(x, deck, zp)
		end
		for k = 1, #railTops - 1 do
			local a, b = railTops[k], railTops[k + 1]
			-- the last span lands on the floor; follow the nosing line down to it
			for _, h in { 3.0, 1.5 } do
				beam(
					stair,
					h > 2 and "Handrail" or "MidRail",
					a + Vector3.new(0, h, 0),
					b + Vector3.new(0, h, 0),
					h > 2 and 0.35 or 0.25,
					h > 2 and 0.3 or 0.25,
					h > 2 and C.wood or shade(TIMBER, 0.03),
					WOOD
				)
			end
		end
	end

	-- mine-portal frame around the doorway
	for _, z in { DOOR.z0 - 0.4, DOOR.z1 + 0.4 } do
		timber(stair, "DoorPost", Vector3.new(0.8, CY - TOP, 0.8), Vector3.new(X0 + 0.4, (TOP + CY) / 2, z))
	end
	timber(stair, "DoorHeader", Vector3.new(0.9, 0.8, SZ1 - SZ0 + 0.4), Vector3.new(X0 + 0.45, CY - 0.4, SZC))
	-- iron edge strips on the treads catch the light
	for i = 1, STEPS do
		local x = LAND_X1 + i * RUN + 0.06
		box(
			stair,
			"Nosing",
			Vector3.new(0.12, 0.06, width),
			Vector3.new(x, TOP - i * RISE - 0.02, SZC),
			IRON,
			METAL,
			DETAIL
		)
	end
end

------------------------------------------------------------------------------------------
-- Hanging lights
------------------------------------------------------------------------------------------
local function hangLantern(
	parent: Instance,
	id: string,
	x: number,
	z: number,
	ringY: number,
	brightness: number,
	range: number,
	shadows: boolean
)
	local hung = Kit.folder(parent, "HangingLantern")
	local lantern = LanternBuilder.buildModel(id, true)
	local pivotY = lantern:GetPivot().Position.Y -- base -> handle centre
	lantern:PivotTo(CFrame.new(x, ringY - RING_H + pivotY, z) * CFrame.Angles(0, math.rad(25), 0))
	lantern.Parent = hung
	local light = lantern:FindFirstChild("Light", true)
	if light then
		light.Brightness = brightness
		light.Range = range
		light.Shadows = shadows
		light.Color = C.warm
	end
	local beamY = CEIL - BEAM_H
	box(hung, "Hook", Vector3.new(0.5, 0.12, 0.5), Vector3.new(x, beamY - 0.06, z), IRON, METAL, DETAIL)
	chain(hung, Vector3.new(x, beamY - 0.1, z), Vector3.new(x, ringY + 0.3, z))
	return hung
end

------------------------------------------------------------------------------------------
-- Furnace, boiler, pipes
------------------------------------------------------------------------------------------
local FX, FZ = 49, -11 -- furnace centre (footprint), mouth faces +Z
local FF = FZ + 1.9 -- front face
local TX, TZ, TD = 58.6, -10.2, 3.6 -- boiler tank

local function buildFurnace(model: Instance)
	local furnace = Kit.folder(model, "Furnace")
	local iron = Color3.fromRGB(48, 45, 42)
	local band = Color3.fromRGB(30, 28, 27)
	local bodyY0 = FLOOR + 1.0
	local bodyY1 = FLOOR + 4.6

	box(
		furnace,
		"Hearth",
		Vector3.new(6.4, 0.5, 5.4),
		Vector3.new(FX, FLOOR + 0.25, FZ + 0.4),
		Color3.fromRGB(96, 52, 40),
		Enum.Material.Brick
	)
	for _, sx in { -1.8, 1.8 } do
		for _, sz in { -1.5, 1.5 } do
			cyl(furnace, "Foot", 0.5, 0.7, Vector3.new(FX + sx, FLOOR + 0.75, FZ + sz), "y", band, METAL)
		end
	end
	box(
		furnace,
		"Body",
		Vector3.new(4.4, bodyY1 - bodyY0, 3.8),
		Vector3.new(FX, (bodyY0 + bodyY1) / 2, FZ),
		iron,
		METAL
	)
	cyl(furnace, "Dome", 4.4, 3.8, Vector3.new(FX, bodyY1, FZ), "x", iron, METAL)
	for _, y in { bodyY0 + 0.25, bodyY1 - 0.2 } do
		box(furnace, "Band", Vector3.new(4.56, 0.24, 3.96), Vector3.new(FX, y, FZ), band, METAL, DETAIL)
		for k = -3, 3 do
			local rivet = box(
				furnace,
				"Rivet",
				Vector3.new(0.16, 0.16, 0.16),
				Vector3.new(FX + k * 0.62, y, FF + 0.1),
				band,
				METAL,
				DETAIL
			)
			rivet.Shape = Enum.PartType.Ball
		end
	end
	for _, dx in { -2.15, 2.15 } do
		cyl(furnace, "DomeRib", 0.22, 3.96, Vector3.new(FX + dx, bodyY1, FZ), "x", band, METAL, DETAIL)
	end
	-- rust streaks
	for _, dx in { -1.5, 0.9 } do
		box(
			furnace,
			"Rust",
			Vector3.new(0.35, 1.6, 0.04),
			Vector3.new(FX + dx, bodyY0 + 1.0, FF + 0.02),
			C.rust,
			Enum.Material.CorrodedMetal,
			{ Transparency = 0.3, CanCollide = false, CanQuery = false, CastShadow = false }
		)
	end

	-- firebox mouth: iron frame, the glowing coals behind a grate, the door swung open
	local mouthY = FLOOR + 2.75
	box(furnace, "MouthFrame", Vector3.new(2.8, 2.1, 0.25), Vector3.new(FX, mouthY, FF + 0.12), band, METAL)
	local coals = box(
		furnace,
		"Coals",
		Vector3.new(2.1, 1.4, 0.1),
		Vector3.new(FX, mouthY, FF + 0.27),
		GLOW,
		Enum.Material.Neon,
		DETAIL
	)
	coals.Transparency = 0.1
	box(
		furnace,
		"CoalsHot",
		Vector3.new(1.4, 0.5, 0.1),
		Vector3.new(FX, mouthY - 0.35, FF + 0.29),
		Color3.fromRGB(255, 170, 70),
		Enum.Material.Neon,
		DETAIL
	)
	for k = -3, 3 do
		box(
			furnace,
			"GrateBar",
			Vector3.new(0.1, 1.5, 0.1),
			Vector3.new(FX + k * 0.3, mouthY, FF + 0.38),
			band,
			METAL,
			DETAIL
		)
	end
	for _, dy in { -0.72, 0.72 } do
		box(
			furnace,
			"GrateRail",
			Vector3.new(2.2, 0.12, 0.12),
			Vector3.new(FX, mouthY + dy, FF + 0.38),
			band,
			METAL,
			DETAIL
		)
	end
	local hinge = Vector3.new(FX - 1.25, mouthY, FF + 0.3)
	local door = CFrame.new(hinge) * CFrame.Angles(0, math.rad(-105), 0)
	box(furnace, "FireDoor", Vector3.new(1.15, 1.55, 0.14), door * CFrame.new(0.6, 0, 0), iron, METAL, DETAIL)
	box(furnace, "DoorPanel", Vector3.new(0.8, 1.15, 0.06), door * CFrame.new(0.6, 0, 0.1), band, METAL, DETAIL)
	cyl(furnace, "DoorLatch", 0.5, 0.12, (door * CFrame.new(1.0, 0, 0.2)).Position, "y", C.brass, METAL, DETAIL)
	for _, dy in { -0.55, 0.55 } do
		cyl(furnace, "Hinge", 0.3, 0.16, hinge + Vector3.new(0, dy, 0), "y", band, METAL, DETAIL)
	end
	-- ash door below, latched shut, with spilled ash
	box(furnace, "AshDoor", Vector3.new(1.8, 0.55, 0.12), Vector3.new(FX, bodyY0 + 0.6, FF + 0.06), band, METAL, DETAIL)
	cyl(furnace, "AshHandle", 0.6, 0.1, Vector3.new(FX, bodyY0 + 0.6, FF + 0.2), "x", C.brass, METAL, DETAIL)
	box(
		furnace,
		"Ash",
		Vector3.new(2.4, 0.03, 1.4),
		Vector3.new(FX + 0.2, FLOOR + 0.515, FF + 0.55),
		Color3.fromRGB(70, 66, 62),
		Enum.Material.Sand,
		DETAIL
	)
	box(
		furnace,
		"Scorch",
		Vector3.new(4.2, 0.02, 2.4),
		Vector3.new(FX, FLOOR + 0.01, FF + 2.1),
		Color3.fromRGB(24, 20, 18),
		Enum.Material.Slate,
		{
			Transparency = 0.45,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	-- brass maker's plate and a temperature gauge on the dome
	local up = math.rad(35)
	local normal = Vector3.new(0, math.sin(up), math.cos(up))
	local platePos = Vector3.new(FX, bodyY1, FZ) + normal * 1.93
	local plate = box(
		furnace,
		"Plate",
		Vector3.new(1.6, 0.5, 0.06),
		CFrame.lookAt(platePos, platePos + normal),
		C.brass,
		METAL,
		DETAIL
	)
	Kit.surfaceText(plate, Enum.NormalId.Front, "HEARTHWELL No.4", Enum.Font.Fondamento, Color3.fromRGB(50, 34, 16))
	gauge(furnace, Vector3.new(FX + 1.6, bodyY1 + 0.3, FF + 0.08), Vector3.zAxis, 0.7, math.rad(-50))

	-- flue: up out of the back of the dome and through the ceiling, with a damper
	local flueZ = FZ - 1.2
	local flueY0 = bodyY1 + 1.2
	cyl(furnace, "FlueCollar", 0.5, 1.6, Vector3.new(FX, flueY0, flueZ), "y", band, METAL)
	cyl(
		furnace,
		"Flue",
		CY - flueY0,
		1.25,
		Vector3.new(FX, (flueY0 + CY) / 2, flueZ),
		"y",
		Color3.fromRGB(58, 56, 54),
		METAL
	)
	for _, y in { flueY0 + 2, flueY0 + 4.5 } do
		cyl(furnace, "FlueJoint", 0.18, 1.38, Vector3.new(FX, y, flueZ), "y", band, METAL, DETAIL)
	end
	cyl(furnace, "Damper", 1.8, 0.1, Vector3.new(FX + 0.9, flueY0 + 3.2, flueZ), "x", band, METAL, DETAIL)
	cyl(furnace, "CeilingCollar", 0.3, 2, Vector3.new(FX, CEIL - 0.15, flueZ), "y", band, METAL, DETAIL)

	-- the light comes from just outside the mouth so the body doesn't swallow its shadows
	local glow =
		box(furnace, "Glow", Vector3.new(0.2, 0.2, 0.2), Vector3.new(FX, mouthY - 0.1, FF + 0.9), GLOW, nil, INVISIBLE)
	local light = Kit.pointLight(glow, 22, 1.7, true, Color3.fromRGB(255, 120, 50))
	light:SetAttribute("Flicker", "furnace")
	local fill = Kit.pointLight(glow, 9, 0.6, false, Color3.fromRGB(255, 100, 40))
	fill:SetAttribute("Flicker", "furnace")
	Kit.anchor(
		furnace,
		"Embers",
		CFrame.lookAt(Vector3.new(FX, mouthY, FF + 0.5), Vector3.new(FX, mouthY, FF + 2)),
		Vector3.new(2, 1.4, 1.2)
	)
	Kit.anchor(furnace, "Furnace", CFrame.new(FX, FLOOR + 3, FZ))

	-- coal bin, shovel and scuttle on the left, a stack of logs in the corner
	local bin = Kit.folder(furnace, "CoalBin")
	local bx0, bx1, bz0, bz1 = 39.2, 42.8, Z0 + IN + 0.05, Z0 + IN + 3
	local bh = 1.6
	for _, s in { { bx0, bz0, bx1, bz0 }, { bx0, bz1, bx1, bz1 }, { bx0, bz0, bx0, bz1 }, { bx1, bz0, bx1, bz1 } } do
		local alongX = s[2] == s[4]
		local size = alongX and Vector3.new(bx1 - bx0 + 0.25, bh, 0.25) or Vector3.new(0.25, bh, bz1 - bz0 + 0.25)
		box(
			bin,
			"BinSide",
			size,
			Vector3.new((s[1] + s[3]) / 2, FLOOR + bh / 2, (s[2] + s[4]) / 2),
			pick(TONES),
			PLANKS
		)
	end
	box(
		bin,
		"Coal",
		Vector3.new(bx1 - bx0 - 0.2, 1.1, bz1 - bz0 - 0.2),
		Vector3.new((bx0 + bx1) / 2, FLOOR + 0.55, (bz0 + bz1) / 2),
		Color3.fromRGB(22, 21, 20),
		Enum.Material.Slate
	)
	for _ = 1, 9 do
		local lump = box(
			bin,
			"Lump",
			Vector3.new(0.5, 0.5, 0.5) * rng:NextNumber(0.7, 1.3),
			CFrame.new(rng:NextNumber(bx0 + 0.4, bx1 - 0.4), FLOOR + 1.15, rng:NextNumber(bz0 + 0.4, bz1 - 0.4))
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			Color3.fromRGB(26, 25, 24),
			Enum.Material.Slate,
			DETAIL
		)
		lump.Shape = Enum.PartType.Ball
	end
	-- shovel leaning against the bin's front
	local shovelFoot = Vector3.new(41.8, FLOOR, bz1 + 1.3)
	local shovelTop = Vector3.new(41.4, FLOOR + bh + 2.2, bz1 + 0.15)
	beam(bin, "ShovelHaft", shovelFoot + Vector3.new(0, 0.9, -0.2), shovelTop, 0.12, 0.12, C.midWood, WOOD, DETAIL)
	box(
		bin,
		"ShovelBlade",
		Vector3.new(0.75, 0.06, 0.9),
		CFrame.new(shovelFoot + Vector3.new(0, 0.35, -0.1)) * CFrame.Angles(math.rad(-65), 0, 0),
		IRON,
		METAL,
		DETAIL
	)
	-- coal scuttle by the furnace door
	cyl(bin, "Scuttle", 0.9, 1, Vector3.new(FX + 3.1, FLOOR + 0.45, FF + 0.6), "y", Color3.fromRGB(36, 40, 38), METAL)
	box(
		bin,
		"ScuttleCoal",
		Vector3.new(0.7, 0.2, 0.7),
		Vector3.new(FX + 3.1, FLOOR + 0.92, FF + 0.6),
		Color3.fromRGB(22, 21, 20),
		Enum.Material.Slate,
		DETAIL
	)
	beam(
		bin,
		"Poker",
		Vector3.new(FX + 2.5, FLOOR + 0.05, FF + 0.4),
		Vector3.new(FX + 2.3, FLOOR + 3.4, FF - 0.15),
		0.08,
		0.08,
		band,
		METAL,
		DETAIL
	)
	-- logs, three-two-one
	local lx = X0 + IN + 0.9
	local k = 0
	for layer, count in { 3, 2, 1 } do
		for j = 1, count do
			k += 1
			local x = lx + (j - (count + 1) / 2) * 0.62 + 0.62
			cyl(
				bin,
				"Log",
				3.0,
				0.6,
				Vector3.new(x, FLOOR + 0.3 + (layer - 1) * 0.52, Z0 + IN + 1.7),
				"z",
				shade(Color3.fromRGB(92, 66, 46), 0.04),
				WOOD,
				k > 3 and DETAIL or nil
			)
		end
	end
end

local function buildBoiler(model: Instance)
	local boiler = Kit.folder(model, "Boiler")
	local band = Color3.fromRGB(40, 36, 32)
	local y0 = FLOOR + 0.8
	local y1 = FLOOR + 7.0
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3 + 0.4
		box(
			boiler,
			"Leg",
			Vector3.new(0.4, 0.85, 0.4),
			Vector3.new(TX + math.cos(a) * 1.3, FLOOR + 0.42, TZ + math.sin(a) * 1.3),
			band,
			METAL
		)
	end
	cyl(boiler, "Tank", y1 - y0, TD, Vector3.new(TX, (y0 + y1) / 2, TZ), "y", COPPER, METAL)
	local dome = box(boiler, "Dome", Vector3.new(TD, TD, TD), Vector3.new(TX, y1 - 0.6, TZ), COPPER, METAL)
	dome.Shape = Enum.PartType.Ball
	for _, y in { y0 + 0.2, y0 + 2.4, y0 + 4.6, y1 - 0.1 } do
		cyl(boiler, "Band", 0.22, TD + 0.12, Vector3.new(TX, y, TZ), "y", band, METAL, DETAIL)
	end
	-- verdigris streaks
	for _, a in { 2.3, 3.4 } do
		local p = Vector3.new(TX + math.cos(a) * (TD / 2), y0 + 3, TZ + math.sin(a) * (TD / 2))
		box(
			boiler,
			"Verdigris",
			Vector3.new(0.5, 3, 0.05),
			CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))),
			Color3.fromRGB(78, 130, 108),
			Enum.Material.CorrodedMetal,
			{
				Transparency = 0.25,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
	end
	-- dials facing the room
	local face = Vector3.new(-0.75, 0, 0.66).Unit
	gauge(boiler, Vector3.new(TX, y0 + 3.6, TZ) + face * (TD / 2 + 0.08), face, 1.0, math.rad(35))
	gauge(
		boiler,
		Vector3.new(TX, y0 + 2.5, TZ) + Vector3.new(-0.95, 0, 0.3).Unit * (TD / 2 + 0.08),
		Vector3.new(-0.95, 0, 0.3).Unit,
		0.6,
		math.rad(-80)
	)
	local label = box(
		boiler,
		"Label",
		Vector3.new(1.4, 0.7, 0.05),
		CFrame.lookAt(Vector3.new(TX, y0 + 1.4, TZ) + face * (TD / 2 + 0.03), Vector3.new(TX, y0 + 1.4, TZ) + face * 3),
		Color3.fromRGB(200, 190, 160),
		nil,
		DETAIL
	)
	Kit.surfaceText(
		label,
		Enum.NormalId.Front,
		"DANGER\nHOT WATER",
		Enum.Font.SpecialElite,
		Color3.fromRGB(150, 30, 24)
	)
	-- relief valve on top, hissing
	local relief = Vector3.new(TX + 0.6, y1 + 1.15, TZ + 0.4)
	cyl(boiler, "Relief", 0.6, 0.3, relief, "y", C.brass, METAL, DETAIL)
	Kit.anchor(
		boiler,
		"Steam",
		CFrame.lookAt(relief + Vector3.new(0, 0.35, 0), relief + Vector3.new(0.2, 2, 0.3)),
		Vector3.new(0.3, 0.3, 0.3)
	)
	Kit.anchor(boiler, "Boiler", CFrame.new(TX, y0 + 3, TZ))
	box(
		boiler,
		"OilStain",
		Vector3.new(4.8, 0.02, 4.2),
		Vector3.new(TX - 0.5, FLOOR + 0.01, TZ + 0.4),
		Color3.fromRGB(22, 18, 14),
		Enum.Material.Glass,
		{
			Transparency = 0.5,
			Reflectance = 0.08,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)

	-- pipe runs hung from the ceiling along the south side, both feeding the tank
	local copperZ, steelZ = Z0 + 2.8, Z0 + 3.5
	local copperY, steelY = CEIL - 1.9, CEIL - 1.3
	local xa, xb = X0 + IN, X1 - IN
	cyl(boiler, "CopperPipe", xb - xa, 0.42, Vector3.new((xa + xb) / 2, copperY, copperZ), "x", COPPER, METAL)
	cyl(
		boiler,
		"SteelPipe",
		TX - xa,
		0.6,
		Vector3.new((xa + TX) / 2, steelY, steelZ),
		"x",
		Color3.fromRGB(110, 108, 102),
		METAL
	)
	for x = xa + 2.5, xb - 1, 5 do
		-- hanger rods to the ceiling
		box(
			boiler,
			"Hanger",
			Vector3.new(0.08, CEIL - copperY, 0.08),
			Vector3.new(x, (CEIL + copperY) / 2, copperZ),
			IRON,
			METAL,
			DETAIL
		)
		if x < TX then
			box(
				boiler,
				"Hanger",
				Vector3.new(0.08, CEIL - steelY, 0.08),
				Vector3.new(x + 0.6, (CEIL + steelY) / 2, steelZ),
				IRON,
				METAL,
				DETAIL
			)
		end
		cyl(
			boiler,
			"Coupling",
			0.3,
			0.56,
			Vector3.new(x + 1.2, copperY, copperZ),
			"x",
			COPPER:Lerp(Color3.new(0, 0, 0), 0.25),
			METAL,
			DETAIL
		)
	end
	-- steel riser from the tank dome up into the run
	local riserX, riserZ = TX - 0.2, steelZ
	cyl(
		boiler,
		"Riser",
		steelY - (y1 + 0.6),
		0.6,
		Vector3.new(riserX, (steelY + y1 + 0.6) / 2, riserZ),
		"y",
		Color3.fromRGB(110, 108, 102),
		METAL
	)
	local elbow = box(
		boiler,
		"Elbow",
		Vector3.new(0.8, 0.8, 0.8),
		Vector3.new(riserX, steelY, riserZ),
		Color3.fromRGB(90, 88, 84),
		METAL,
		DETAIL
	)
	elbow.Shape = Enum.PartType.Ball
	-- copper drop into the tank top
	local dropX = TX - 1.1
	cyl(boiler, "CopperDrop", copperY - y1, 0.42, Vector3.new(dropX, (copperY + y1) / 2, copperZ), "y", COPPER, METAL)
	cyl(boiler, "DropFlange", 0.2, 0.7, Vector3.new(dropX, y1 + 1.4, copperZ), "y", C.brass, METAL, DETAIL)
	-- the leaky joint: a flange on the copper run, weeping steam toward the room
	local leak = Vector3.new(55.6, copperY, copperZ)
	cyl(boiler, "LeakFlange", 0.22, 0.75, leak, "x", C.brass, METAL, DETAIL)
	box(
		boiler,
		"Rag",
		Vector3.new(0.5, 0.6, 0.5),
		leak + Vector3.new(0.35, -0.1, 0),
		Color3.fromRGB(150, 140, 120),
		Enum.Material.Fabric,
		DETAIL
	)
	Kit.anchor(
		boiler,
		"Steam",
		CFrame.lookAt(leak + Vector3.new(0, -0.1, 0.3), leak + Vector3.new(0.2, -0.8, 1.6)),
		Vector3.new(0.3, 0.3, 0.3)
	)
	Kit.anchor(boiler, "Pipes", CFrame.new((xa + xb) / 2, copperY, copperZ))
	-- low pipe from furnace to tank with a handwheel valve and a gauge
	local lowY, lowZ = FLOOR + 3.4, TZ - 0.4
	local fx1 = FX + 2.2
	local tx0 = TX - TD / 2 + 0.2
	cyl(
		boiler,
		"FeedPipe",
		tx0 - fx1,
		0.5,
		Vector3.new((fx1 + tx0) / 2, lowY, lowZ),
		"x",
		Color3.fromRGB(86, 84, 80),
		METAL
	)
	cyl(boiler, "ValveBody", 0.7, 0.75, Vector3.new(54.8, lowY, lowZ), "x", C.brass, METAL, DETAIL)
	valve(boiler, Vector3.new(54.8, lowY + 0.3, lowZ), 0.6)
	cyl(boiler, "GaugeStem", 0.6, 0.14, Vector3.new(53.0, lowY + 0.5, lowZ), "y", C.brass, METAL, DETAIL)
	gauge(boiler, Vector3.new(53.0, lowY + 1.05, lowZ + 0.05), Vector3.zAxis, 0.7, math.rad(20))
	-- a red fuel can beside the tank
	local can = Kit.folder(boiler, "FuelCan")
	box(
		can,
		"Can",
		Vector3.new(1.0, 1.4, 0.6),
		CFrame.new(TX - 2.7, FLOOR + 0.7, TZ + 2.4) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(150, 36, 28),
		METAL
	)
	box(
		can,
		"Handle",
		Vector3.new(0.7, 0.12, 0.14),
		CFrame.new(TX - 2.7, FLOOR + 1.5, TZ + 2.4) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(120, 28, 22),
		METAL,
		DETAIL
	)
end

------------------------------------------------------------------------------------------
-- Lantern bench
------------------------------------------------------------------------------------------
local BX = 49 -- bench centre
local BENCH_TOP = FLOOR + 3.2
local BACK = Z1 - IN -- lining face behind the bench

local function buildBench(model: Instance)
	local bench = Kit.folder(model, "LanternBench")
	local x0, x1 = BX - 4, BX + 4
	local z0 = BACK - 3.05

	-- heavy top: three thick boards
	local benchTop
	for i = 0, 2 do
		local part = box(
			bench,
			i == 0 and "BenchTop" or "TopBoard",
			Vector3.new(x1 - x0, 0.45, 0.98),
			Vector3.new(BX, BENCH_TOP - 0.225, z0 + 0.5 + i * 1.0),
			pick(TONES),
			WOOD
		)
		if i == 0 then
			benchTop = part
		end
	end
	box(
		bench,
		"Apron",
		Vector3.new(x1 - x0, 0.6, 0.15),
		Vector3.new(BX, BENCH_TOP - 0.75, z0 + 0.1),
		shade(TIMBER, 0.03),
		WOOD
	)
	for _, x in { x0 + 0.45, x1 - 0.45 } do
		for _, z in { z0 + 0.45, BACK - 0.4 } do
			timber(
				bench,
				"Leg",
				Vector3.new(0.7, BENCH_TOP - 0.45 - FLOOR, 0.7),
				Vector3.new(x, (FLOOR + BENCH_TOP - 0.45) / 2, z)
			)
		end
		box(
			bench,
			"Stretcher",
			Vector3.new(0.4, 0.4, BACK - z0 - 0.6),
			Vector3.new(x, FLOOR + 0.55, (z0 + BACK) / 2),
			shade(TIMBER, 0.03),
			WOOD,
			DETAIL
		)
	end
	box(
		bench,
		"Shelf",
		Vector3.new(x1 - x0 - 1.1, 0.25, BACK - z0 - 0.5),
		Vector3.new(BX, FLOOR + 0.9, (z0 + BACK) / 2 + 0.1),
		pick(TONES),
		PLANKS
	)
	Kit.prompt(benchTop, "Workbench", "Customize Lantern", "Lanterns")

	-- under the bench: toolbox, paint tins, a crate of glass
	local shelfY = FLOOR + 1.025
	box(
		bench,
		"Toolbox",
		Vector3.new(2.2, 1.0, 1.2),
		Vector3.new(BX - 2.3, shelfY + 0.5, BACK - 1.4),
		C.redPaint,
		METAL,
		DETAIL
	)
	box(
		bench,
		"ToolboxLid",
		Vector3.new(2.25, 0.12, 1.25),
		Vector3.new(BX - 2.3, shelfY + 1.04, BACK - 1.4),
		Color3.fromRGB(120, 32, 26),
		METAL,
		DETAIL
	)
	for i, x in { BX + 0.2, BX + 0.9 } do
		cyl(
			bench,
			"PaintTin",
			0.8,
			0.7,
			Vector3.new(x, shelfY + 0.4, BACK - 1.0 - i * 0.3),
			"y",
			Color3.fromRGB(150, 150, 140),
			METAL,
			DETAIL
		)
	end
	crate(bench, CFrame.new(BX + 2.5, shelfY, BACK - 1.4), Vector3.new(1.8, 1.4, 1.6))

	-- on the bench: vise, glass panes, candles, oil can, hammer, half-built lantern frame
	local vise = Color3.fromRGB(56, 76, 94)
	local vx, vz = x1 - 0.9, z0 + 0.15
	box(bench, "ViseBase", Vector3.new(0.9, 0.3, 0.9), Vector3.new(vx, BENCH_TOP + 0.15, vz + 0.3), vise, METAL, DETAIL)
	box(
		bench,
		"ViseBody",
		Vector3.new(0.7, 0.55, 1.1),
		Vector3.new(vx, BENCH_TOP + 0.55, vz + 0.2),
		vise,
		METAL,
		DETAIL
	)
	for _, dz in { -0.4, 0.05 } do
		box(
			bench,
			"ViseJaw",
			Vector3.new(1.0, 0.45, 0.14),
			Vector3.new(vx, BENCH_TOP + 0.95, vz + dz),
			vise:Lerp(Color3.new(0, 0, 0), 0.3),
			METAL,
			DETAIL
		)
	end
	cyl(bench, "ViseScrew", 1.0, 0.14, Vector3.new(vx, BENCH_TOP + 0.6, vz - 0.65), "z", C.steel, METAL, DETAIL)
	cyl(bench, "ViseBar", 1.1, 0.08, Vector3.new(vx, BENCH_TOP + 0.6, vz - 1.1), "x", C.steel, METAL, DETAIL)
	for i = 0, 2 do
		box(
			bench,
			"GlassPane",
			Vector3.new(0.9, 0.04, 1.1),
			CFrame.new(BX - 3.1 + i * 0.05, BENCH_TOP + 0.03 + i * 0.045, z0 + 1.2) * CFrame.Angles(0, i * 0.12, 0),
			Color3.fromRGB(220, 230, 220),
			Enum.Material.Glass,
			{ Transparency = 0.45, CanCollide = false, CanQuery = false, CastShadow = false }
		)
	end
	local candleBox = box(
		bench,
		"CandleBox",
		Vector3.new(1.2, 0.5, 0.8),
		CFrame.new(BX - 1.3, BENCH_TOP + 0.25, BACK - 0.7) * CFrame.Angles(0, 0.15, 0),
		Color3.fromRGB(196, 170, 120),
		Enum.Material.Cardboard,
		DETAIL
	)
	Kit.surfaceText(candleBox, Enum.NormalId.Front, "CANDLES", Enum.Font.SpecialElite, Color3.fromRGB(60, 40, 24))
	for i = 0, 3 do
		cyl(
			bench,
			"Candle",
			0.9,
			0.18,
			Vector3.new(BX - 1.9 + i * 0.05, BENCH_TOP + 0.09, z0 + 0.6 + i * 0.2),
			"x",
			Color3.fromRGB(236, 226, 200),
			nil,
			DETAIL
		)
	end
	cyl(
		bench,
		"OilCan",
		0.6,
		0.6,
		Vector3.new(BX + 1.4, BENCH_TOP + 0.3, BACK - 0.7),
		"y",
		Color3.fromRGB(70, 96, 70),
		METAL,
		DETAIL
	)
	beam(
		bench,
		"OilSpout",
		Vector3.new(BX + 1.4, BENCH_TOP + 0.6, BACK - 0.7),
		Vector3.new(BX + 1.4, BENCH_TOP + 1.1, BACK - 1.4),
		0.07,
		0.07,
		C.brass,
		METAL,
		DETAIL
	)
	box(
		bench,
		"HammerHandle",
		Vector3.new(1.2, 0.12, 0.16),
		CFrame.new(BX + 0.6, BENCH_TOP + 0.08, z0 + 0.7) * CFrame.Angles(0, 0.5, 0),
		C.midWood,
		WOOD,
		DETAIL
	)
	box(
		bench,
		"HammerHead",
		Vector3.new(0.18, 0.18, 0.6),
		CFrame.new(BX + 0.6, BENCH_TOP + 0.1, z0 + 0.7) * CFrame.Angles(0, 0.5, 0) * CFrame.new(0.6, 0, 0),
		IRON,
		METAL,
		DETAIL
	)
	-- a lantern frame mid-repair: base, corner posts, no glass
	local fx, fz = BX - 0.2, z0 + 1.6
	box(
		bench,
		"FrameBase",
		Vector3.new(0.95, 0.15, 0.95),
		Vector3.new(fx, BENCH_TOP + 0.08, fz),
		Color3.fromRGB(110, 60, 40),
		METAL,
		DETAIL
	)
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		box(
			bench,
			"FramePost",
			Vector3.new(0.1, 1.0, 0.1),
			Vector3.new(fx + c[1] * 0.4, BENCH_TOP + 0.65, fz + c[2] * 0.4),
			Color3.fromRGB(150, 90, 60),
			METAL,
			DETAIL
		)
	end
	-- wood shavings on the floor in front
	for _ = 1, 6 do
		box(
			bench,
			"Shaving",
			Vector3.new(rng:NextNumber(0.2, 0.4), 0.02, rng:NextNumber(0.1, 0.2)),
			CFrame.new(BX + rng:NextNumber(-3.5, 3.5), FLOOR + 0.01, z0 - rng:NextNumber(0.3, 2.2))
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Color3.fromRGB(150, 112, 70),
			WOOD,
			DETAIL
		)
	end

	-- pegboard in a timber frame, every lantern on a hook
	local pb0, pb1 = BENCH_TOP + 0.3, BENCH_TOP + 5.6
	local px0, px1 = x0 + 0.2, x1 - 0.2
	box(
		bench,
		"Pegboard",
		Vector3.new(px1 - px0, pb1 - pb0, 0.12),
		Vector3.new(BX, (pb0 + pb1) / 2, BACK - 0.06),
		Color3.fromRGB(150, 116, 80),
		Enum.Material.Cardboard,
		{ CastShadow = false }
	)
	for _, y in { pb0, pb1 } do
		timber(
			bench,
			"PegFrame",
			Vector3.new(px1 - px0 + 0.5, 0.3, 0.25),
			Vector3.new(BX, y, BACK - 0.12),
			{ CastShadow = false }
		)
	end
	for _, x in { px0, px1 } do
		timber(
			bench,
			"PegFrame",
			Vector3.new(0.3, pb1 - pb0, 0.25),
			Vector3.new(x, (pb0 + pb1) / 2, BACK - 0.12),
			{ CastShadow = false }
		)
	end
	local hookY = pb1 - 0.55
	local count = #Lanterns.List
	local spacing = math.min(1.45, (px1 - px0 - 1.4) / math.max(count - 1, 1))
	for i, def in Lanterns.List do
		local x = BX + (i - (count + 1) / 2) * spacing
		cyl(bench, "Hook", 0.9, 0.08, Vector3.new(x, hookY, BACK - 0.55), "z", C.steel, METAL, DETAIL)
		local lantern = LanternBuilder.buildModel(def.id, true)
		local pivotY = lantern:GetPivot().Position.Y
		local ringY = hookY - 0.3
		lantern:PivotTo(CFrame.new(x, ringY - RING_H + pivotY, BACK - 0.8))
		local light = lantern:FindFirstChild("Light", true)
		if light then
			light.Brightness *= 0.3
			light.Range = 7
			light.Shadows = false
		end
		lantern.Parent = bench
		-- price tag under each one, with a strip in the lantern's rarity colour along its top edge
		local tagY = ringY - RING_H - 0.3
		local tag = box(
			bench,
			"Tag",
			Vector3.new(0.55, 0.32, 0.03),
			Vector3.new(x, tagY, BACK - 0.14),
			Color3.fromRGB(226, 214, 184),
			nil,
			DETAIL
		)
		Kit.surfaceText(
			tag,
			Enum.NormalId.Front,
			def.price > 0 and tostring(def.price) or "FREE",
			Enum.Font.SpecialElite,
			Color3.fromRGB(60, 40, 30)
		)
		box(
			bench,
			"RarityTag",
			Vector3.new(0.55, 0.07, 0.035),
			Vector3.new(x, tagY + 0.195, BACK - 0.14),
			Lanterns.rarityColor(def.rarity),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
	-- tools hung below the lanterns
	local toolY = pb0 + 0.75
	local toolZ = BACK - 0.16
	local tools = {
		{ "Saw", Vector3.new(1.8, 0.55, 0.04), -3.0, C.steel },
		{ "SawHandle", Vector3.new(0.45, 0.6, 0.06), -3.95, C.midWood },
		{ "Wrench", Vector3.new(0.14, 1.2, 0.05), -1.9, C.steel },
		{ "Wrench", Vector3.new(0.14, 0.9, 0.05), -1.6, C.steel },
		{ "Screwdriver", Vector3.new(0.1, 0.9, 0.05), -1.2, Color3.fromRGB(150, 40, 30) },
		{ "Screwdriver", Vector3.new(0.1, 0.8, 0.05), -0.95, Color3.fromRGB(200, 160, 40) },
		{ "Pliers", Vector3.new(0.25, 0.9, 0.05), 1.0, Color3.fromRGB(40, 60, 120) },
		{ "Snips", Vector3.new(0.3, 1.0, 0.05), 1.5, Color3.fromRGB(120, 30, 26) },
		{ "File", Vector3.new(0.12, 1.1, 0.05), 2.0, C.steel },
		{ "Mallet", Vector3.new(0.12, 1.0, 0.05), 2.6, C.midWood },
		{ "MalletHead", Vector3.new(0.7, 0.35, 0.3), 2.6, Color3.fromRGB(130, 96, 60) },
	}
	for _, t in tools do
		local y = toolY + (t[1] == "MalletHead" and 0.5 or 0)
		box(bench, t[1], t[2], Vector3.new(BX + t[3], y, toolZ), t[4], t[1]:find("Saw") and METAL or nil, DETAIL)
	end
	-- sketches pinned at the top corners
	for i, spec in { { -3.2, 0.12 }, { 3.1, -0.08 } } do
		local sheet = box(
			bench,
			"Sketch",
			Vector3.new(0.9, 1.15, 0.02),
			CFrame.new(BX + spec[1], pb1 - 0.8, BACK - 0.14) * CFrame.Angles(0, 0, spec[2]),
			Color3.fromRGB(222, 212, 186),
			nil,
			DETAIL
		)
		Kit.surfaceText(
			sheet,
			Enum.NormalId.Front,
			i == 1 and "wick\n+3mm\n?" or "no.5\nglass\nred",
			Enum.Font.IndieFlower,
			Color3.fromRGB(50, 50, 70)
		)
	end

	-- painted sign above (3D lettering from SignageRooms when it's there)
	local roomSigns = script.Parent.Parent:FindFirstChild("SignageRooms")
	if roomSigns then
		-- the board's back on the lining, facing into the room (-Z), with the same slight tilt
		require(roomSigns).benchLanterns(
			bench,
			CFrame.lookAt(Vector3.new(BX, pb1 + 1.1, BACK - 0.03), Vector3.new(BX, pb1 + 1.1, BACK - 5))
				* CFrame.Angles(0, 0, math.rad(1.5))
		)
	else
		local sign = box(
			bench,
			"Sign",
			Vector3.new(6.2, 1.25, 0.18),
			CFrame.new(BX, pb1 + 1.1, BACK - 0.12) * CFrame.Angles(0, 0, math.rad(-1.5)),
			Color3.fromRGB(44, 64, 52),
			WOOD,
			DETAIL
		)
		Kit.surfaceText(sign, Enum.NormalId.Front, "LANTERNS", Enum.Font.SpecialElite, Color3.fromRGB(226, 212, 176))
	end

	-- enamel shade lamp over the bench (one of the room's three shadow-casting lights)
	Kit.bareBulb(bench, Vector3.new(BX, FLOOR + 7.6, BACK - 2.2), 16, 1.5, true, "shade", CEIL)

	-- fitting stand: a round iron plate with a brass post and a turntable top, a lantern standing on it
	-- under a cold task lamp. The Model carries `LanternId` and `Mount` (CFrame of the lantern's base)
	-- so a server service can swap `DisplayStand.Lantern` for the player's equipped one.
	do
		local stand = Kit.folder(bench, "DisplayStand")
		local sx2, sz2 = BX + 1.9, z0 + 1.1
		cyl(stand, "Plate", 0.08, 1.3, Vector3.new(sx2, BENCH_TOP + 0.04, sz2), "y", IRON, METAL, DETAIL)
		cyl(stand, "Post", 0.5, 0.12, Vector3.new(sx2, BENCH_TOP + 0.33, sz2), "y", C.brass, METAL, DETAIL)
		cyl(stand, "Turntable", 0.06, 0.9, Vector3.new(sx2, BENCH_TOP + 0.61, sz2), "y", C.brass, METAL, DETAIL)
		-- door toward the player (the lantern's +X pane), base on the turntable
		local mount = CFrame.new(sx2, BENCH_TOP + 0.64, sz2) * CFrame.Angles(0, math.pi / 2, 0)
		stand:SetAttribute("LanternId", Lanterns.DefaultId)
		stand:SetAttribute("Mount", mount)
		local shown = LanternBuilder.buildModel(Lanterns.DefaultId, true)
		shown.Name = "Lantern"
		shown:PivotTo(mount * CFrame.new(0, shown:GetPivot().Position.Y, 0))
		local light = shown:FindFirstChild("Light", true)
		if light then
			light.Brightness *= 0.5
			light.Range = 8
			light.Shadows = false
		end
		shown.Parent = stand

		-- articulated task lamp on a weighted base at the bench's end, its shade aimed at the stand
		local lamp = Kit.folder(bench, "TaskLamp")
		local base = Vector3.new(x1 - 0.4, BENCH_TOP + 0.05, z0 + 1.45)
		local elbow = Vector3.new(x1 - 1.0, BENCH_TOP + 2.7, z0 + 1.3)
		local head = Vector3.new(sx2 + 0.25, BENCH_TOP + 4.3, sz2 + 0.05)
		cyl(lamp, "LampBase", 0.1, 0.6, base, "y", IRON, METAL, DETAIL)
		beam(lamp, "LampArm", base + Vector3.new(0, 0.05, 0), elbow, 0.08, 0.08, IRON, METAL, DETAIL)
		box(lamp, "Elbow", Vector3.new(0.16, 0.16, 0.16), elbow, C.brass, METAL, {
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		beam(lamp, "LampArm", elbow, head, 0.08, 0.08, IRON, METAL, DETAIL)
		local aim = Vector3.new(sx2, BENCH_TOP + 0.64, sz2)
		local shadeCF = CFrame.lookAt(head, aim) * CFrame.Angles(0, math.pi / 2, 0) -- local +X = toward the stand
		box(lamp, "Shade", Vector3.new(0.45, 0.7, 0.7), shadeCF, Color3.fromRGB(44, 50, 56), METAL, {
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		local cold = Color3.fromRGB(205, 226, 255)
		local bulb = box(
			lamp,
			"Bulb",
			Vector3.new(0.22, 0.22, 0.22),
			shadeCF * CFrame.new(0.18, 0, 0),
			cold,
			Enum.Material.Neon,
			{ Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
		)
		Kit.halo(bulb, 1.3, cold)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right
		spot.Angle = 48
		spot.Range = 7
		spot.Brightness = 2.4
		spot.Color = cold
		spot.Shadows = false
		spot.Parent = bulb

		-- a magnifier dangling from the lamp arm on a short chain
		local hang = elbow:Lerp(head, 0.45)
		local ringAt = hang - Vector3.new(0, 0.95, 0)
		chain(lamp, hang, ringAt + Vector3.new(0, 0.32, 0))
		ring(lamp, "MagnifierRim", CFrame.new(ringAt) * CFrame.Angles(0, math.rad(20), 0), 0.3, 0.06, 6, C.brass, METAL)
		box(
			lamp,
			"MagnifierGlass",
			Vector3.new(0.03, 0.52, 0.52),
			CFrame.new(ringAt) * CFrame.Angles(0, math.rad(20), 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(205, 228, 232),
			Enum.Material.Glass,
			{
				Shape = Enum.PartType.Cylinder,
				Transparency = 0.5,
				Reflectance = 0.2,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}
		)
		box(
			lamp,
			"MagnifierHandle",
			Vector3.new(0.09, 0.42, 0.09),
			CFrame.new(ringAt - Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(20), 0),
			C.darkWood,
			WOOD,
			DETAIL
		)
	end

	-- stool turned to the bench
	local stool = Kit.folder(bench, "Stool")
	local sx, sz = BX + 0.4, z0 - 1.6
	cyl(stool, "Seat", 0.22, 1.5, Vector3.new(sx, FLOOR + 2.4, sz), "y", C.midWood, WOOD)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		beam(
			stool,
			"StoolLeg",
			Vector3.new(sx + math.cos(a) * 0.85, FLOOR, sz + math.sin(a) * 0.85),
			Vector3.new(sx + math.cos(a) * 0.45, FLOOR + 2.3, sz + math.sin(a) * 0.45),
			0.16,
			0.16,
			C.darkWood,
			WOOD,
			DETAIL
		)
	end
	ring(
		stool,
		"Footring",
		CFrame.new(sx, FLOOR + 0.8, sz) * CFrame.Angles(math.pi / 2, 0, 0),
		0.72,
		0.08,
		8,
		IRON,
		METAL
	)
end

------------------------------------------------------------------------------------------
-- Storage, clutter, lights
------------------------------------------------------------------------------------------
-- Diagonal lattice screen from (a) to (b) along the floor, `h` tall.
local function lattice(parent: Instance, a: Vector3, b: Vector3, h: number)
	local screen = Kit.folder(parent, "Lattice")
	local along = (b - a).Unit
	local w = (b - a).Magnitude
	local function at(u: number, v: number): Vector3
		return a + along * u + Vector3.new(0, v, 0)
	end
	local yaw = math.atan2(-along.Z, along.X)
	for _, u in { 0, w } do
		timber(screen, "LatticePost", Vector3.new(0.4, h, 0.4), at(u, h / 2))
	end
	for _, v in { 0.15, h - 0.15 } do
		box(
			screen,
			"LatticeRail",
			Vector3.new(w, 0.3, 0.3),
			CFrame.new(at(w / 2, v)) * CFrame.Angles(0, yaw, 0),
			shade(TIMBER, 0.03),
			WOOD
		)
	end
	-- 45-degree slats both ways, each clipped to the panel: line u = c + t (or c - t) at height t
	local s = 1.1
	local slat = Color3.fromRGB(110, 78, 50)
	local noCollide = { CanCollide = false, CanQuery = false }
	local c = -h + s / 2
	while c < w do
		local t0, t1 = math.max(0, -c), math.min(h, w - c)
		if t1 - t0 > 0.3 then
			beam(screen, "Slat", at(c + t0, t0), at(c + t1, t1), 0.08, 0.22, slat, WOOD, noCollide)
		end
		c += s
	end
	c = s / 2
	while c < w + h do
		local t0, t1 = math.max(0, c - w), math.min(h, c)
		if t1 - t0 > 0.3 then
			beam(screen, "Slat", at(c - t0, t0), at(c - t1, t1), 0.08, 0.22, slat, WOOD, noCollide)
		end
		c += s
	end
	-- invisible wall so nobody walks through the slats
	box(
		screen,
		"Blocker",
		Vector3.new(w, h, 0.3),
		CFrame.new(at(w / 2, h / 2)) * CFrame.Angles(0, yaw, 0),
		Color3.new(),
		nil,
		{
			Transparency = 1,
			CastShadow = false,
		}
	)
	return screen
end

local function buildStorage(model: Instance)
	local store = Kit.folder(model, "Storage")
	local wx = X0 + IN -- west lining face
	local ex = X1 - IN -- east lining face
	local nz = Z1 - IN -- north lining face

	-- north-west: lattice cage of crates, lit by a dim globe
	local cageX, cageZ = 42.4, 11.8
	lattice(store, Vector3.new(wx, FLOOR, cageZ), Vector3.new(cageX - 2, FLOOR, cageZ), 6.5)
	lattice(store, Vector3.new(cageX, FLOOR, nz), Vector3.new(cageX, FLOOR, cageZ + 2.2), 6.5)
	timber(store, "CagePost", Vector3.new(0.5, 6.5, 0.5), Vector3.new(cageX, FLOOR + 3.25, cageZ))
	crate(store, CFrame.new(wx + 1.6, FLOOR, nz - 1.5) * CFrame.Angles(0, 0.1, 0), Vector3.new(2.6, 2.4, 2.6))
	crate(store, CFrame.new(wx + 1.5, FLOOR + 2.4, nz - 1.4) * CFrame.Angles(0, -0.2, 0), Vector3.new(2.0, 1.8, 2.0))
	crate(store, CFrame.new(wx + 4.3, FLOOR, nz - 1.6) * CFrame.Angles(0, -0.05, 0), Vector3.new(2.2, 2.0, 2.4))
	barrel(store, Vector3.new(wx + 1.4, FLOOR, cageZ + 1.6), 2.8, 1.8)
	Kit.bareBulb(store, Vector3.new(wx + 3, CEIL - 2.2, nz - 2.8), 12, 0.5, false, "globe", CEIL)
	-- pickaxe leaning on the cage
	local pickFoot = Vector3.new(cageX - 2.6, FLOOR, cageZ - 0.6)
	local pickTop = Vector3.new(cageX - 2.4, FLOOR + 3.4, cageZ - 0.2)
	beam(store, "PickHaft", pickFoot, pickTop, 0.14, 0.14, C.midWood, WOOD, DETAIL)
	box(
		store,
		"PickHead",
		Vector3.new(1.8, 0.18, 0.18),
		CFrame.lookAt(pickTop, pickTop + Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, 0.15),
		IRON,
		METAL,
		DETAIL
	)

	-- west wall beside the landing: rope coil on a peg, a small crate, bucket under a drip
	local pegZ = SZ1 + 1.7
	cyl(store, "Peg", 0.8, 0.18, Vector3.new(wx + 0.4, FLOOR + 5.6, pegZ), "x", C.darkWood, WOOD, DETAIL)
	for i = 0, 1 do
		ring(
			store,
			"HungRope",
			CFrame.new(wx + 0.3 + i * 0.18, FLOOR + 4.8, pegZ + i * 0.1) * CFrame.Angles(0, math.pi / 2, 0.2 * i),
			0.85 - i * 0.08,
			0.18,
			10,
			shade(ROPE, 0.03),
			Enum.Material.Fabric
		)
	end
	local bucket = Kit.folder(store, "Bucket")
	local bucketPos = Vector3.new(41, FLOOR, SZ1 + 2.2)
	cyl(bucket, "Bucket", 1.0, 1.0, bucketPos + Vector3.new(0, 0.5, 0), "y", Color3.fromRGB(120, 122, 118), METAL)
	cyl(
		bucket,
		"Water",
		0.05,
		0.85,
		bucketPos + Vector3.new(0, 0.85, 0),
		"y",
		Color3.fromRGB(40, 54, 58),
		Enum.Material.Glass,
		{
			Transparency = 0.2,
			Reflectance = 0.15,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	Kit.anchor(store, "Drip", CFrame.new(bucketPos.X, CEIL - 0.1, bucketPos.Z), Vector3.new(0.3, 0.1, 0.3))

	-- south-west, beside the stair: barrels and a crate
	barrel(store, Vector3.new(wx + 1.3, FLOOR, -5.6), 2.8, 1.8)
	barrel(store, Vector3.new(wx + 3.3, FLOOR, -6.1), 2.6, 1.7, Color3.fromRGB(88, 58, 36))
	crate(store, CFrame.new(wx + 1.2, FLOOR, -3.9) * CFrame.Angles(0, 0.3, 0), Vector3.new(1.6, 1.4, 1.6))
	ropeCoil(store, Vector3.new(wx + 3.2, FLOOR + 2.6, -6.1), 0.6)

	-- east wall: stone patch under a caged work light, barrels, leaning planks, shelves
	Kit.cagedLight(
		store,
		CFrame.lookAt(
			Vector3.new(ex - 0.15, FLOOR + 9.2, 2.2),
			Vector3.new(ex - 0.15, FLOOR + 9.2, 2.2) - Vector3.new(-1, -0.6, 0)
		),
		16,
		0.6
	)
	barrel(store, Vector3.new(ex - 1.1, FLOOR, -5.4), 2.8, 1.8, Color3.fromRGB(70, 74, 66))
	barrel(store, Vector3.new(ex - 1.0, FLOOR, -3.3), 2.8, 1.8, Color3.fromRGB(96, 40, 30))
	barrel(store, Vector3.new(ex - 1.0, FLOOR, 4.6), 2.6, 1.7)
	ropeCoil(store, Vector3.new(ex - 2.4, FLOOR, 0.6), 0.75)
	crate(store, CFrame.new(ex - 1.2, FLOOR, 1.6) * CFrame.Angles(0, -0.12, 0), Vector3.new(1.6, 1.3, 1.6))
	for i = 0, 3 do
		local z = 6.3 + i * 0.55
		local foot = Vector3.new(ex - 1.3 - i * 0.05, FLOOR, z)
		local topP = Vector3.new(ex - 0.12, FLOOR + 6.4 + i * 0.3, z + 0.1)
		beam(
			store,
			"LeaningPlank",
			foot + Vector3.new(0, 0.05, 0),
			topP,
			0.5,
			0.12,
			pick(TONES),
			WOOD,
			{ CanCollide = false }
		)
	end
	-- shelf unit in the north-east corner: oil, jars, candle boxes
	local shelf = Kit.folder(store, "Shelf")
	local s0, s1 = 11.2, Z1 - IN - 0.2
	local sd = 1.5
	for _, z in { s0, s1 } do
		for _, x in { ex - 0.15, ex - sd + 0.15 } do
			timber(shelf, "ShelfPost", Vector3.new(0.3, 7, 0.3), Vector3.new(x, FLOOR + 3.5, z))
		end
	end
	for k = 0, 3 do
		local y = FLOOR + 0.4 + k * 2.1
		box(
			shelf,
			"ShelfBoard",
			Vector3.new(sd, 0.18, s1 - s0 + 0.3),
			Vector3.new(ex - sd / 2, y, (s0 + s1) / 2),
			pick(TONES),
			WOOD
		)
		if k > 0 then
			local z = s0 + 0.5
			while z < s1 - 0.5 do
				local roll = rng:NextNumber()
				if roll < 0.4 then
					cyl(
						shelf,
						"OilCan",
						0.9,
						0.6,
						Vector3.new(ex - 0.75, y + 0.54, z),
						"y",
						pick({ Color3.fromRGB(70, 96, 70), Color3.fromRGB(150, 40, 30), Color3.fromRGB(150, 120, 50) }),
						METAL,
						DETAIL
					)
					z += 0.8
				elseif roll < 0.7 then
					cyl(
						shelf,
						"Jar",
						0.7,
						0.5,
						Vector3.new(ex - 0.75, y + 0.44, z),
						"y",
						Color3.fromRGB(190, 170, 120),
						Enum.Material.Glass,
						{
							Transparency = 0.35,
							CanCollide = false,
							CanQuery = false,
							CastShadow = false,
						}
					)
					z += 0.65
				else
					box(
						shelf,
						"Box",
						Vector3.new(1.0, 0.7, 1.1),
						CFrame.new(ex - 0.75, y + 0.44, z + 0.3) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0),
						C.cardboard,
						Enum.Material.Cardboard,
						DETAIL
					)
					z += 1.3
				end
			end
		end
	end
	-- north wall east of the bench: stacked crates
	crate(store, CFrame.new(56.6, FLOOR, nz - 1.3) * CFrame.Angles(0, 0.05, 0), Vector3.new(2.4, 2.2, 2.4))
	crate(store, CFrame.new(56.7, FLOOR + 2.2, nz - 1.3) * CFrame.Angles(0, -0.15, 0), Vector3.new(2.0, 1.8, 2.0))
	ropeCoil(store, Vector3.new(56.7, FLOOR + 4.0, nz - 1.3), 0.6)

	-- hanging lanterns: one over the stair (shadows), one over the floor by the furnace
	-- (the stair lantern hangs off the line of sight from the doorway to the WORKSHOP sign)
	hangLantern(store, "copper", BEAM_XS[1], SZC - 3, CEIL - BEAM_H - 1.4, 1.0, 22, true)
	hangLantern(store, "iron", BEAM_XS[2], -4.5, CEIL - BEAM_H - 3.2, 0.9, 16, false)

	-- a sign hanging from the far beam, facing the doorway (a carved 3D plank that swings a little
	-- on its chains when SignageRooms is there; a flat painted board otherwise)
	local signY = CEIL - BEAM_H - 1.8
	local signX = BEAM_XS[2] - 0.6
	local roomSigns = script.Parent.Parent:FindFirstChild("SignageRooms")
	if roomSigns then
		local hanging =
			require(roomSigns).workshopHanging(store, Vector3.new(signX, signY + 0.65, SZC), -Vector3.xAxis, 5.2, 1.3)
		for _, dz in { -2, 2 } do
			chain(hanging, Vector3.new(signX, CEIL - BEAM_H, SZC + dz), Vector3.new(signX, signY + 0.85, SZC + dz))
		end
		hanging:SetAttribute("SwayPivot", CFrame.new(signX, CEIL - BEAM_H, SZC))
	else
		local sign = box(
			store,
			"WorkshopSign",
			Vector3.new(0.2, 1.3, 5.2),
			Vector3.new(signX, signY, SZC),
			Color3.fromRGB(200, 184, 150),
			WOOD,
			DETAIL
		)
		Kit.surfaceText(sign, Enum.NormalId.Left, "WORKSHOP", Enum.Font.SpecialElite, Color3.fromRGB(90, 30, 24))
		for _, dz in { -2, 2 } do
			chain(store, Vector3.new(signX, CEIL - BEAM_H, SZC + dz), Vector3.new(signX, signY + 0.65, SZC + dz))
		end
	end

	-- drip by the boiler, puddle beneath
	local dripPos = Vector3.new(56.4, CEIL - 0.1, -6.4)
	Kit.anchor(store, "Drip", CFrame.new(dripPos), Vector3.new(0.3, 0.1, 0.3))
	cyl(
		store,
		"Puddle",
		0.02,
		2.2,
		Vector3.new(dripPos.X, FLOOR + 0.01, dripPos.Z),
		"y",
		Color3.fromRGB(30, 34, 36),
		Enum.Material.Glass,
		{
			Transparency = 0.3,
			Reflectance = 0.2,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)

	-- a few notes pinned to the boards
	for _, spec in
		{
			{ "W", -10.5, FLOOR + 5.2, "PILOT LIGHT\nDO NOT\nTOUCH" },
			{ "N", 41.0, FLOOR + 7.4, "oil -\nmonday" },
			{ "E", -7.0, FLOOR + 5.5, "valve 3\nsticks" },
		}
	do
		local cf = wallCF(spec[1], spec[2], spec[3], IN + 0.02)
		local face = spec[1] == "W" and Enum.NormalId.Right
			or spec[1] == "E" and Enum.NormalId.Left
			or Enum.NormalId.Front
		local size = (spec[1] == "W" or spec[1] == "E") and Vector3.new(0.03, 1.2, 1.0) or Vector3.new(1.0, 1.2, 0.03)
		local note = box(store, "Note", size, cf * CFrame.Angles(0, 0, 0), Color3.fromRGB(224, 214, 188), nil, DETAIL)
		Kit.surfaceText(note, face, spec[4], Enum.Font.SpecialElite, Color3.fromRGB(60, 40, 30))
	end
end

------------------------------------------------------------------------------------------
local Workshop = {}

function Workshop.build(root: Instance): Model
	rng = Random.new(2718)
	local model = Kit.folder(root, "Workshop")
	buildLining(model)
	buildFraming(model)
	buildStair(model)
	buildFurnace(model)
	buildBoiler(model)
	buildBench(model)
	buildStorage(model)
	return model
end

return Workshop
