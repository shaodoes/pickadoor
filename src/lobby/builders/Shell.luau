--[[
	Room shells from Layout: floor slab + worn tiles, walls cut around openings, reference-style wall
	finishes (dark wainscot, metal rail, panel seams), a 45-degree cornice where walls meet the ceiling,
	a smooth concrete ceiling with chamfered downstand beams and recessed strip lights.

	Shell.buildRoom(parent, name) builds one room. Shared walls are built once, by the room listed as
	owning them in ROOMS below (the other room skips that side).
]]
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL

local WALL = Layout.WALL
local WALL_BOTTOM = -9 -- walls run down into the natatorium water so nothing hangs over a void
local TILE = 6
local BAND = 4 -- wainscot height

local Shell = {}

-- Per room: which sides to build (N = +Z, S = -Z, E = +X, W = -X), which openings cut each side,
-- windows, and finishes.
local ROOMS = {
	Foyer = {
		sides = { N = {}, S = { "StairTop" }, E = {}, W = { "ShopDoor" } },
		beams = "x",
		strips = true,
	},
	Shop = {
		sides = { N = {}, S = {}, W = {} },
		beams = "z",
		strips = false,
	},
	Stair = {
		sides = { E = {}, W = {} },
		noFloor = true,
		noFinish = true, -- the stair builder adds its own raking rail
		strips = true,
	},
	Hall = {
		sides = { N = { "StairFoot" }, E = { "WorkshopDoor" }, W = {} },
		windows = { W = Layout.HallWindows },
		beams = "x",
		strips = false, -- the reading hall is lit by its pendant lamps and the windows
	},
	DoorHall = {
		sides = { N = { "Arch" }, S = Layout.DoorOpenings, E = {}, W = {} },
		windows = {
			W = {
				y0 = 9,
				y1 = 14,
				list = { { z = -50, w = 8 }, { z = -34, w = 8 } },
				shaftLength = 11, -- high clerestory windows: a softer shaft that fades before the mats
				shaftStrength = 0.45,
			},
		},
		beams = "z",
		strips = true,
	},
	Workshop = {
		sides = { N = {}, S = {}, E = {} },
		noTiles = true,
		noFinish = true,
		strips = false,
	},
}
Shell.ROOMS = ROOMS

------------------------------------------------------------------------------------------
-- Geometry helpers
------------------------------------------------------------------------------------------

-- A wall side as a line: `along` is the axis it runs on ("x" or "z"), `at` the coordinate of its
-- centre plane, `inner` the coordinate of the face toward the room, `normal` the room-facing normal.
local function sideLine(room, side: string)
	if side == "N" then
		return {
			along = "x",
			a0 = room.x0 - WALL,
			a1 = room.x1 + WALL,
			at = room.z1 + WALL / 2,
			inner = room.z1,
			normal = Vector3.new(0, 0, -1),
		}
	elseif side == "S" then
		return {
			along = "x",
			a0 = room.x0 - WALL,
			a1 = room.x1 + WALL,
			at = room.z0 - WALL / 2,
			inner = room.z0,
			normal = Vector3.new(0, 0, 1),
		}
	elseif side == "E" then
		return {
			along = "z",
			a0 = room.z0,
			a1 = room.z1,
			at = room.x1 + WALL / 2,
			inner = room.x1,
			normal = Vector3.new(-1, 0, 0),
		}
	else
		return {
			along = "z",
			a0 = room.z0,
			a1 = room.z1,
			at = room.x0 - WALL / 2,
			inner = room.x0,
			normal = Vector3.new(1, 0, 0),
		}
	end
end

-- World CFrame/size for a slab of wall spanning [a0,a1] along the line, [y0,y1] vertically, `depth` thick
-- centred `offset` studs from the wall's centre plane toward the room.
local function wallBox(line, a0: number, a1: number, y0: number, y1: number, depth: number, offset: number)
	local mid, len = (a0 + a1) / 2, a1 - a0
	local yc, h = (y0 + y1) / 2, y1 - y0
	local n = line.normal
	if line.along == "x" then
		return Vector3.new(len, h, depth), CFrame.new(mid, yc, line.at + n.Z * offset)
	end
	return Vector3.new(depth, h, len), CFrame.new(line.at + n.X * offset, yc, mid)
end

-- Openings on a side, converted to {a0, a1, y0, y1, window?} along the line.
local function openingsFor(line, names, windows)
	local list = {}
	for _, name in names do
		local o = Layout.Openings[name]
		if line.along == "x" then
			table.insert(list, { a0 = o.x0, a1 = o.x1, y0 = o.y0, y1 = o.y1, name = name, noReveal = o.noReveal })
		else
			table.insert(list, { a0 = o.z0, a1 = o.z1, y0 = o.y0, y1 = o.y1, name = name, noReveal = o.noReveal })
		end
	end
	if windows then
		for _, w in windows.list do
			table.insert(list, {
				a0 = w.z - w.w / 2,
				a1 = w.z + w.w / 2,
				y0 = windows.yBase + windows.y0,
				y1 = windows.yBase + windows.y1,
				window = true,
			})
		end
	end
	table.sort(list, function(p, q)
		return p.a0 < q.a0
	end)
	return list
end

------------------------------------------------------------------------------------------
-- Walls
------------------------------------------------------------------------------------------
local function buildWall(parent: Instance, room, line, openings, finish: boolean)
	local top = room.y + room.h + 1
	local function piece(a0, a1, y0, y1)
		if a1 - a0 > 0.01 and y1 - y0 > 0.01 then
			local size, cf = wallBox(line, a0, a1, y0, y1, WALL, 0)
			box(parent, "Wall", size, cf, C.block, Enum.Material.Plaster)
		end
	end
	local cursor = line.a0
	for _, o in openings do
		piece(cursor, o.a0, WALL_BOTTOM, top)
		piece(o.a0, o.a1, WALL_BOTTOM, o.y0)
		piece(o.a0, o.a1, o.y1, top)
		cursor = o.a1
	end
	piece(cursor, line.a1, WALL_BOTTOM, top)

	-- reveals: dark steel frames round doorways, chamfered top corners on wide openings
	for _, o in openings do
		if o.window or o.noReveal then
			continue
		end
		local width = o.a1 - o.a0
		local frame = Color3.fromRGB(46, 48, 52)
		for _, a in { o.a0, o.a1 } do
			local size, cf = wallBox(line, a - 0.15, a + 0.15, o.y0, o.y1, WALL + 0.3, 0)
			box(parent, "Reveal", size, cf, frame, Enum.Material.Metal, DETAIL)
		end
		local size, cf = wallBox(line, o.a0 - 0.15, o.a1 + 0.15, o.y1 - 0.3, o.y1, WALL + 0.3, 0)
		box(parent, "Reveal", size, cf, frame, Enum.Material.Metal, DETAIL)
		if width >= 10 then
			-- 45-degree haunches in the top corners, like the reference's angled transitions
			local k = 2.2
			for _, a in { o.a0, o.a1 } do
				-- a square rolled 45 degrees and centred on the corner leaves a clean triangular fillet
				local hSize, hCf
				if line.along == "x" then
					hSize = Vector3.new(k * 1.4142, k * 1.4142, WALL - 0.02)
					hCf = CFrame.new(a, o.y1, line.at) * CFrame.Angles(0, 0, math.rad(45))
				else
					hSize = Vector3.new(WALL - 0.02, k * 1.4142, k * 1.4142)
					hCf = CFrame.new(line.at, o.y1, a) * CFrame.Angles(math.rad(45), 0, 0)
				end
				box(parent, "Haunch", hSize, hCf, C.block, Enum.Material.Plaster, DETAIL)
			end
		end
	end

	if not finish then
		return
	end
	-- finishes on the room side, clipped to the interior span
	local inA0 = line.along == "x" and room.x0 or room.z0
	local inA1 = line.along == "x" and room.x1 or room.z1
	local bandTop = room.y + BAND
	-- wainscot + rail wherever no opening comes below the rail
	local cursorA = inA0
	local function band(a0, a1)
		a0, a1 = math.max(a0, inA0), math.min(a1, inA1)
		if a1 - a0 < 0.2 then
			return
		end
		local size, cf = wallBox(line, a0, a1, room.y, bandTop, 0.16, WALL / 2 + 0.08)
		box(parent, "Wainscot", size, cf, C.wainscot, Enum.Material.Concrete, DETAIL)
		size, cf = wallBox(line, a0, a1, bandTop - 0.125, bandTop + 0.125, 0.3, WALL / 2 + 0.15)
		box(parent, "Rail", size, cf, C.rail, Enum.Material.Metal, DETAIL)
		size, cf = wallBox(line, a0, a1, room.y, room.y + 0.6, 0.24, WALL / 2 + 0.12)
		box(parent, "Skirting", size, cf, C.blockLow, Enum.Material.Concrete, DETAIL)
	end
	for _, o in openings do
		if o.y0 < bandTop then
			band(cursorA, o.a0)
			cursorA = o.a1
		end
	end
	band(cursorA, inA1)
	-- vertical panel seams every 8 studs on the upper wall
	local first = math.ceil((inA0 + 4) / 8) * 8
	for a = first, inA1 - 4, 8 do
		local blocked = false
		for _, o in openings do
			if a > o.a0 - 0.8 and a < o.a1 + 0.8 then
				blocked = true
			end
		end
		if not blocked then
			local size, cf =
				wallBox(line, a - 0.04, a + 0.04, bandTop + 0.2, room.y + room.h - 1.2, 0.06, WALL / 2 + 0.03)
			box(parent, "Seam", size, cf, C.seam, Enum.Material.SmoothPlastic, DETAIL)
		end
	end
	-- horizontal seam halfway up, like precast panels
	local seamY = room.y + BAND + (room.h - BAND) * 0.55
	local cursorB = inA0
	for _, o in openings do
		if o.y0 < seamY and o.y1 > seamY then
			local a0, a1 = cursorB, math.max(inA0, o.a0 - 0.2)
			if a1 - a0 > 0.3 then
				local size, cf = wallBox(line, a0, a1, seamY - 0.04, seamY + 0.04, 0.06, WALL / 2 + 0.03)
				box(parent, "Seam", size, cf, C.seam, Enum.Material.SmoothPlastic, DETAIL)
			end
			cursorB = math.min(inA1, o.a1 + 0.2)
		end
	end
	if inA1 - cursorB > 0.3 then
		local size, cf = wallBox(line, cursorB, inA1, seamY - 0.04, seamY + 0.04, 0.06, WALL / 2 + 0.03)
		box(parent, "Seam", size, cf, C.seam, Enum.Material.SmoothPlastic, DETAIL)
	end
end

-- Glass, frame and sill for each window opening, plus a light-shaft anchor and caustics on the ceiling.
local function buildWindows(parent: Instance, room, line, windows)
	local y0, y1 = windows.yBase + windows.y0, windows.yBase + windows.y1
	local h, yc = y1 - y0, (y0 + y1) / 2
	local n = line.normal
	for _, w in windows.list do
		local function at(offset: number, y: number)
			return Vector3.new(line.at + n.X * offset, y, w.z)
		end
		box(parent, "WindowGlass", Vector3.new(0.2, h, w.w), at(-0.8, yc), C.glass, Enum.Material.Glass, {
			Transparency = 0.86,
			CastShadow = false,
			CanQuery = false,
		})
		local frame = Color3.fromRGB(46, 48, 52)
		box(parent, "Mullion", Vector3.new(0.3, h, 0.3), at(-0.6, yc), frame, Enum.Material.Metal, DETAIL)
		box(parent, "Transom", Vector3.new(0.3, 0.3, w.w), at(-0.6, yc + h * 0.18), frame, Enum.Material.Metal, DETAIL)
		for _, dz in { -w.w / 2, w.w / 2 } do
			box(
				parent,
				"WindowFrame",
				Vector3.new(WALL + 0.2, h, 0.3),
				Vector3.new(line.at, yc, w.z + dz),
				C.block,
				Enum.Material.Plaster,
				DETAIL
			)
		end
		box(
			parent,
			"WindowHead",
			Vector3.new(WALL + 0.2, 0.3, w.w + 0.6),
			Vector3.new(line.at, y1, w.z),
			C.block,
			Enum.Material.Plaster,
			DETAIL
		)
		box(
			parent,
			"Sill",
			Vector3.new(WALL + 1.2, 0.35, w.w + 1),
			at(0.6, y0 - 0.17),
			Color3.fromRGB(150, 152, 156),
			Enum.Material.Concrete
		)
		-- cold light from outside
		local glass = box(
			parent,
			"WindowLight",
			Vector3.new(0.1, h, w.w),
			at(WALL / 2 + 0.1, yc),
			C.coldLight,
			nil,
			Kit.INVISIBLE
		)
		local light = Instance.new("SurfaceLight")
		light.Face = n.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left
		light.Color = C.coldLight
		light.Brightness = 1.1
		light.Range = 22
		light.Angle = 70
		light.Shadows = true
		light.Parent = glass
		-- markers for client FX: a shaft of light into the room, water light playing on the ceiling
		local face = CFrame.lookAt(at(WALL / 2 + 0.15, yc), at(WALL / 2 + 5, yc - 2.5))
		Kit.anchor(
			parent,
			"WindowShaft",
			face,
			Vector3.new(w.w - 0.6, h - 0.4, 0.2),
			{ Color = C.coldLight, Length = windows.shaftLength or 18, Strength = windows.shaftStrength or 1 }
		)
		local ceilingY = room.y + room.h - 0.08
		Kit.anchor(
			parent,
			"Caustics",
			CFrame.lookAt(at(WALL / 2 + 6, ceilingY), at(WALL / 2 + 6, ceilingY - 5), Vector3.xAxis),
			Vector3.new(w.w + 4, 10, 0.1),
			{ Color = C.coldLight }
		)
	end
end

------------------------------------------------------------------------------------------
-- Floor, ceiling
------------------------------------------------------------------------------------------
local function buildFloor(parent: Instance, room, spec)
	-- interior only: the walls run down past the floor and close the edges, and doorway sills
	-- are the wall pieces left under each opening
	box(
		parent,
		"Floor",
		Vector3.new(room.x1 - room.x0, 2, room.z1 - room.z0),
		Vector3.new((room.x0 + room.x1) / 2, room.y - 1, (room.z0 + room.z1) / 2),
		C.grout,
		Enum.Material.Concrete
	)
	if spec.noTiles then
		return
	end
	local rng = Kit.rng
	local nx, nz = math.floor((room.x1 - room.x0) / TILE), math.floor((room.z1 - room.z0) / TILE)
	local tx, tz = (room.x1 - room.x0) / nx, (room.z1 - room.z0) / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = room.x0 + (ix + 0.5) * tx
			local z = room.z0 + (iz + 0.5) * tz
			local shade = rng:NextNumber(-0.07, 0.05)
			local color = shade < 0 and C.tileFloor:Lerp(Color3.fromRGB(70, 66, 60), -shade * 3)
				or C.tileFloor:Lerp(Color3.fromRGB(170, 164, 154), shade * 3)
			box(
				parent,
				"Tile",
				Vector3.new(tx - 0.1, 0.04, tz - 0.1),
				Vector3.new(x, room.y + 0.02, z),
				color,
				Enum.Material.Concrete,
				{
					CastShadow = false,
					CanQuery = false,
					CanTouch = false,
				}
			)
		end
	end
end

local function buildCeiling(parent: Instance, room, spec, holes)
	local yc = room.y + room.h
	local x0, x1, z0, z1 = room.x0 - WALL, room.x1 + WALL, room.z0 - WALL, room.z1 + WALL
	-- slab, cut around any holes (rectangles {x0,x1,z0,z1}) with a simple strip decomposition along X
	local function slab(ax0, ax1, az0, az1)
		if ax1 - ax0 > 0.01 and az1 - az0 > 0.01 then
			box(
				parent,
				"Ceiling",
				Vector3.new(ax1 - ax0, 1, az1 - az0),
				Vector3.new((ax0 + ax1) / 2, yc + 0.5, (az0 + az1) / 2),
				C.ceiling,
				Enum.Material.Plaster
			)
		end
	end
	if not holes or #holes == 0 then
		slab(x0, x1, z0, z1)
	else
		local hole = holes[1] -- one hole per room is all we need
		slab(x0, x1, z0, hole.z0)
		slab(x0, x1, hole.z1, z1)
		slab(x0, hole.x0, hole.z0, hole.z1)
		slab(hole.x1, x1, hole.z0, hole.z1)
	end
	-- 45-degree cornice along every wall: a square beam rolled 45 degrees, half buried in the corner
	local k = 1.8
	for _, s in (if spec.noFinish then {} else { -1, 1 }) do
		local z = s < 0 and room.z0 or room.z1
		local x = s < 0 and room.x0 or room.x1
		box(
			parent,
			"Cornice",
			Vector3.new(room.x1 - room.x0, k, k),
			CFrame.new((room.x0 + room.x1) / 2, yc, z) * CFrame.Angles(math.rad(45), 0, 0),
			C.ceiling,
			Enum.Material.Plaster,
			DETAIL
		)
		box(
			parent,
			"Cornice",
			Vector3.new(k, k, room.z1 - room.z0),
			CFrame.new(x, yc, (room.z0 + room.z1) / 2) * CFrame.Angles(0, 0, math.rad(45)),
			C.ceiling,
			Enum.Material.Plaster,
			DETAIL
		)
	end
	-- downstand beams with chamfered soffits, spanning the short way
	if spec.beams and not spec.noFinish then
		local alongX = spec.beams == "x"
		local span0, span1 = alongX and room.z0 or room.x0, alongX and room.z1 or room.x1
		local count = math.max(1, math.floor((span1 - span0) / 14))
		for i = 1, count do
			local p = span0 + (span1 - span0) * i / (count + 1)
			local inHole = false
			for _, hole in holes or {} do
				if
					(alongX and p > hole.z0 - 2 and p < hole.z1 + 2)
					or (not alongX and p > hole.x0 - 2 and p < hole.x1 + 2)
				then
					inHole = true
				end
			end
			if not inHole then
				local len = alongX and (room.x1 - room.x0) or (room.z1 - room.z0)
				local mid = alongX and (room.x0 + room.x1) / 2 or (room.z0 + room.z1) / 2
				local depth, width = 1.4, 2.2
				local cf = alongX and CFrame.new(mid, yc - depth / 2, p)
					or CFrame.new(p, yc - depth / 2, mid) * CFrame.Angles(0, math.rad(90), 0)
				box(parent, "Beam", Vector3.new(len, depth, width), cf, C.ceiling, Enum.Material.Plaster)
				for _, s in { -1, 1 } do
					-- angled haunch where the beam meets the slab
					box(
						parent,
						"BeamHaunch",
						Vector3.new(len, 0.9, 0.9),
						cf * CFrame.new(0, depth / 2, s * width / 2) * CFrame.Angles(math.rad(45), 0, 0),
						C.ceiling,
						Enum.Material.Plaster,
						DETAIL
					)
				end
			end
		end
	end
	-- recessed warm strip lights in dark housings, in rows across the room
	if spec.strips then
		local w, d = room.x1 - room.x0, room.z1 - room.z0
		local alongX = w < d -- strips run across the short dimension? no: along the long one, in rows
		local rows = math.max(1, math.floor((alongX and w or d) / 14))
		local perRow = math.max(1, math.floor((alongX and d or w) / 12))
		for r = 1, rows do
			for i = 1, perRow do
				local a = (alongX and room.x0 or room.z0) + (alongX and w or d) * r / (rows + 1)
				local b = (alongX and room.z0 or room.x0) + (alongX and d or w) * (i - 0.5) / perRow
				local pos = alongX and Vector3.new(a, yc - 0.02, b) or Vector3.new(b, yc - 0.02, a)
				local len = 6
				local size = alongX and Vector3.new(1.1, 0.1, len + 0.5) or Vector3.new(len + 0.5, 0.1, 1.1)
				local inHole = false
				for _, hole in holes or {} do
					if pos.X > hole.x0 - 1 and pos.X < hole.x1 + 1 and pos.Z > hole.z0 - 1 and pos.Z < hole.z1 + 1 then
						inHole = true
					end
				end
				if not inHole then
					box(parent, "StripHousing", size, pos, Color3.fromRGB(40, 42, 46), Enum.Material.Metal, DETAIL)
					local tube = box(
						parent,
						"StripLight",
						alongX and Vector3.new(0.6, 0.08, len) or Vector3.new(len, 0.08, 0.6),
						pos - Vector3.new(0, 0.04, 0),
						Color3.fromRGB(255, 214, 170),
						Enum.Material.Neon,
						DETAIL
					)
					tube.Transparency = 0.15
					local light = Instance.new("SurfaceLight")
					light.Face = Enum.NormalId.Bottom
					light.Color = Color3.fromRGB(255, 214, 172)
					light.Brightness = 0.38
					light.Range = 16
					light.Angle = 110
					light.Shadows = false
					light.Parent = tube
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
function Shell.buildRoom(parent: Instance, name: string, holes: { any }?)
	local room = Layout.Rooms[name]
	local spec = ROOMS[name]
	local model = Kit.folder(parent, name .. "Shell")
	if not spec.noFloor then
		buildFloor(model, room, spec)
	end
	for side, names in spec.sides do
		local line = sideLine(room, side)
		local windows = spec.windows and spec.windows[side]
		if windows then
			windows = table.clone(windows)
			windows.yBase = room.y
		end
		local openings = openingsFor(line, names, windows)
		buildWall(model, room, line, openings, not spec.noFinish)
		if windows then
			buildWindows(model, room, line, windows)
		end
	end
	buildCeiling(model, room, spec, holes)
	Kit.anchor(
		model,
		"Room",
		CFrame.new((room.x0 + room.x1) / 2, room.y + room.h / 2, (room.z0 + room.z1) / 2),
		Vector3.new(room.x1 - room.x0, room.h, room.z1 - room.z0),
		{ Room = name }
	)
	return model
end

-- Union of every room's footprint including walls, as {x0, x1, z0, z1} (for the natatorium).
function Shell.footprints(): { { number } }
	local list = {}
	for _, room in Layout.Rooms do
		table.insert(list, { room.x0 - WALL, room.x1 + WALL, room.z0 - WALL, room.z1 + WALL, room.y + room.h + 1 })
	end
	return list
end

return Shell
