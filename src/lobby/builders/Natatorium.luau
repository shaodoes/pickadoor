--[[
	Outside: an endless flooded natatorium of tiled groin vaults, seen only through the windows.
	Terrain water fills everything outside the building's footprint; piers stand on a grid; every
	bay is vaulted (well above the roofs) and a cold light hangs in some of them.
]]
local Kit = require(script.Parent.Kit)
local Shell = require(script.Parent.Shell)
local Layout = require(script.Parent.Layout)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local Natatorium = {}

local POOL = {
	floorY = -8, -- tiled pool floor
	waterY = 4, -- still water, a stud below the reading hall's window sills
	spacing = 28, -- pier grid
	pier = 4,
	springY = 23, -- vaults spring above every roof so they never cut into a room
	extent = 5, -- bays in each direction from the centre
}
Natatorium.POOL = POOL

-- Half of a groin vault: a barrel shell spanning one bay. Two crossed barrels per bay read as a
-- groin vault from below. `alongX` decides which way the barrel runs.
local function barrel(parent: Instance, cx: number, cz: number, alongX: boolean)
	local radius, segments = POOL.spacing / 2, 10
	local chord = 2 * radius * math.sin(math.pi / (2 * segments)) + 0.5
	for i = 0, segments - 1 do
		local a = math.pi * (i + 0.5) / segments
		local y = POOL.springY + math.sin(a) * radius
		local offset = math.cos(a) * radius
		if alongX then
			box(
				parent,
				"Vault",
				Vector3.new(POOL.spacing, 1, chord),
				CFrame.new(cx, y, cz + offset) * CFrame.Angles(-(math.pi / 2 + a), 0, 0),
				C.tile,
				Enum.Material.CeramicTiles,
				DETAIL
			)
		else
			box(
				parent,
				"Vault",
				Vector3.new(chord, 1, POOL.spacing),
				CFrame.new(cx + offset, y, cz) * CFrame.Angles(0, 0, a + math.pi / 2),
				C.tile,
				Enum.Material.CeramicTiles,
				DETAIL
			)
		end
	end
end

-- does the rectangle [x0,x1]x[z0,z1] overlap any footprint?
local function overlaps(footprints, x0: number, x1: number, z0: number, z1: number): boolean
	for _, f in footprints do
		if x1 > f[1] and x0 < f[2] and z1 > f[3] and z0 < f[4] then
			return true
		end
	end
	return false
end

--[[
	The lobby seen from the pool: one tiled block, from the pool floor up to the vaults' springing
	line, with a flat tiled roof (the "lid") at the springing line that the vaults land on. Inside it,
	above the rooms' own roofs, is a closed attic nobody can see into, so no roof slab, wall top, joist
	or stair poking through a roof is ever visible from outside.

	The plan is a grid built from every footprint edge. Narrow slots between rooms (and small notches
	in concave corners) are filled in so the block has a clean outline. The skin runs just outside the
	outline (0.4 thick), cut round every window on an outer wall (Shell.ROOMS windows), with a darker
	cornice where it meets the lid. Each `keepOut` rectangle (the house stairwell shaft rising above the
	foyer) is cut out of the lid and wrapped in a tiled tower instead.

	Everything here sits outside the room footprints (skin, cornice) or above every room's ceiling
	slab (lid, tower), so none of it can show inside a room. Returns the filled slots as {x0,x1,z0,z1}.
]]
local LID = POOL.springY -- top of the block = vault springing line = pier tops
local LID_T = 1 -- lid thickness (stays above the tallest roof: the foyer's slab tops out at y=21)
local SKIN = 0.4
local CORNICE = { out = 0.8, h = 1.4 }

local function buildBlock(pool: Instance, footprints: { { number } }, keepOut: { { number } }): { { number } }
	local WALL = Layout.WALL
	local function tiled(name, size, pos, color)
		return box(pool, name, size, pos, color or C.tile, Enum.Material.CeramicTiles, DETAIL)
	end

	-- compressed grid over every footprint edge
	local xs, zs, seenX, seenZ = {}, {}, {}, {}
	for _, f in footprints do
		for _, x in { f[1], f[2] } do
			if not seenX[x] then
				seenX[x] = true
				table.insert(xs, x)
			end
		end
		for _, z in { f[3], f[4] } do
			if not seenZ[z] then
				seenZ[z] = true
				table.insert(zs, z)
			end
		end
	end
	table.sort(xs)
	table.sort(zs)
	local nx, nz = #xs - 1, #zs - 1
	local solid = {}
	for i = 1, nx do
		solid[i] = {}
		for j = 1, nz do
			local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
			solid[i][j] = false
			for _, f in footprints do
				if cx > f[1] and cx < f[2] and cz > f[3] and cz < f[4] then
					solid[i][j] = true
				end
			end
		end
	end
	local function at(i, j): boolean
		return i >= 1 and i <= nx and j >= 1 and j <= nz and solid[i][j]
	end

	-- fill slots no wider than a wall between two solid cells, then the small notches those fills
	-- leave where a slot meets the outline
	local fills, filled = {}, {}
	local function wasFilled(i, j): boolean
		return filled[i * 1000 + j] == true
	end
	for _ = 1, 3 do
		local changed = false
		for i = 1, nx do
			for j = 1, nz do
				if not solid[i][j] then
					local w, d = xs[i + 1] - xs[i], zs[j + 1] - zs[j]
					local slotX = w <= WALL and at(i - 1, j) and at(i + 1, j)
					local slotZ = d <= WALL and at(i, j - 1) and at(i, j + 1)
					local sides = (at(i - 1, j) and 1 or 0)
						+ (at(i + 1, j) and 1 or 0)
						+ (at(i, j - 1) and 1 or 0)
						+ (at(i, j + 1) and 1 or 0)
					local nextToFill = wasFilled(i - 1, j)
						or wasFilled(i + 1, j)
						or wasFilled(i, j - 1)
						or wasFilled(i, j + 1)
					local notch = w <= WALL and d <= WALL and sides >= 2 and nextToFill
					if slotX or slotZ or notch then
						solid[i][j] = true
						filled[i * 1000 + j] = true
						changed = true
						table.insert(fills, { xs[i], xs[i + 1], zs[j], zs[j + 1] })
					end
				end
			end
		end
		if not changed then
			break
		end
	end

	-- the lid: greedy rectangles over the solid cells, each cut round the keepOut rectangles
	local function cut(r, holes, out)
		for n, h in holes do
			if r[2] > h[1] and r[1] < h[2] and r[4] > h[3] and r[3] < h[4] then
				local rest = table.move(holes, n + 1, #holes, 1, {})
				cut({ r[1], r[2], r[3], h[3] }, rest, out)
				cut({ r[1], r[2], h[4], r[4] }, rest, out)
				cut({ r[1], h[1], math.max(r[3], h[3]), math.min(r[4], h[4]) }, rest, out)
				cut({ h[2], r[2], math.max(r[3], h[3]), math.min(r[4], h[4]) }, rest, out)
				return
			end
		end
		if r[2] - r[1] > 0.01 and r[4] - r[3] > 0.01 then
			table.insert(out, r)
		end
	end
	local used = {}
	for i = 1, nx do
		used[i] = {}
	end
	for i = 1, nx do
		for j = 1, nz do
			if solid[i][j] and not used[i][j] then
				local j1 = j
				while at(i, j1 + 1) and not used[i][j1 + 1] do
					j1 += 1
				end
				local i1 = i
				while true do
					local ok = i1 + 1 <= nx
					for jj = j, j1 do
						ok = ok and at(i1 + 1, jj) and not used[i1 + 1][jj]
					end
					if not ok then
						break
					end
					i1 += 1
				end
				for ii = i, i1 do
					for jj = j, j1 do
						used[ii][jj] = true
					end
				end
				local pieces = {}
				cut({ xs[i], xs[i1 + 1], zs[j], zs[j1 + 1] }, keepOut, pieces)
				for _, r in pieces do
					tiled(
						"BlockLid",
						Vector3.new(r[2] - r[1], LID_T, r[4] - r[3]),
						Vector3.new((r[1] + r[2]) / 2, LID - LID_T / 2, (r[3] + r[4]) / 2)
					)
				end
			end
		end
	end

	-- outline edges: { axis = the axis it runs along, at = its coordinate, out = outward sign, a0, a1 }
	local runs = {}
	local function edge(axis: string, coord: number, out: number, a0: number, a1: number)
		local key = axis .. coord .. ":" .. out
		runs[key] = runs[key] or { axis = axis, at = coord, out = out, segs = {} }
		table.insert(runs[key].segs, { a0, a1 })
	end
	for i = 1, nx do
		for j = 1, nz do
			if solid[i][j] then
				if not at(i - 1, j) then
					edge("z", xs[i], -1, zs[j], zs[j + 1])
				end
				if not at(i + 1, j) then
					edge("z", xs[i + 1], 1, zs[j], zs[j + 1])
				end
				if not at(i, j - 1) then
					edge("x", zs[j], -1, xs[i], xs[i + 1])
				end
				if not at(i, j + 1) then
					edge("x", zs[j + 1], 1, xs[i], xs[i + 1])
				end
			end
		end
	end

	-- windows in outer walls stay open: { axis, at, out, a0, a1, y0, y1 }
	local windows = {}
	for name, spec in Shell.ROOMS do
		local room = Layout.Rooms[name]
		for side, win in spec.windows or {} do
			local axis = (side == "W" or side == "E") and "z" or "x"
			local out = (side == "W" or side == "S") and -1 or 1
			local coord = side == "W" and room.x0 - WALL
				or side == "E" and room.x1 + WALL
				or side == "S" and room.z0 - WALL
				or room.z1 + WALL
			for _, w in win.list do
				table.insert(windows, {
					axis = axis,
					at = coord,
					out = out,
					a0 = w.z - w.w / 2,
					a1 = w.z + w.w / 2,
					y0 = room.y + win.y0,
					y1 = room.y + win.y1,
				})
			end
		end
	end

	-- a slab lying in an edge's plane: [a0,a1] along it, [y0,y1] up, `d0..d1` outward from the line
	local function slab(name, run, a0, a1, y0, y1, d0, d1, color)
		if a1 - a0 < 0.01 or y1 - y0 < 0.01 then
			return
		end
		local p = run.at + run.out * (d0 + d1) / 2
		local size = run.axis == "z" and Vector3.new(d1 - d0, y1 - y0, a1 - a0)
			or Vector3.new(a1 - a0, y1 - y0, d1 - d0)
		local pos = run.axis == "z" and Vector3.new(p, (y0 + y1) / 2, (a0 + a1) / 2)
			or Vector3.new((a0 + a1) / 2, (y0 + y1) / 2, p)
		tiled(name, size, pos, color)
	end

	local y0, y1 = POOL.floorY, LID
	for _, run in runs do
		table.sort(run.segs, function(p, q)
			return p[1] < q[1]
		end)
		local merged = {}
		for _, s in run.segs do
			local last = merged[#merged]
			if last and math.abs(last[2] - s[1]) < 0.01 then
				last[2] = s[2]
			else
				table.insert(merged, { s[1], s[2] })
			end
		end
		for _, m in merged do
			local holes = {}
			for _, w in windows do
				if w.axis == run.axis and w.at == run.at and w.out == run.out and w.a0 >= m[1] and w.a1 <= m[2] then
					table.insert(holes, w)
				end
			end
			table.sort(holes, function(p, q)
				return p.a0 < q.a0
			end)
			-- runs along X wrap the convex corners (ends pushed out past the corner); runs along Z
			-- butt into them, so no two pieces overlap there. At concave corners the ends just tuck
			-- into the wall behind the other run's skin.
			local wraps = run.axis == "x"
			local ext = wraps and SKIN or 0
			local cursor = m[1] - ext
			for _, h in holes do
				slab("OuterSkin", run, cursor, h.a0, y0, y1, 0, SKIN)
				slab("OuterSkin", run, h.a0, h.a1, y0, h.y0, 0, SKIN)
				slab("OuterSkin", run, h.a0, h.a1, h.y1, y1, 0, SKIN)
				cursor = h.a1
			end
			slab("OuterSkin", run, cursor, m[2] + ext, y0, y1, 0, SKIN)
			local e = SKIN + CORNICE.out
			local cext = wraps and e or SKIN
			slab("Cornice", run, m[1] - cext, m[2] + cext, LID - CORNICE.h, LID + 0.2, SKIN, e, C.tileDeep)
		end
	end

	-- the house stairwell shaft rises through the lid (Foyer.luau: its ceiling tops out 12 studs
	-- above the foyer ceiling): wrap it in a tiled tower with a flat top
	local towerTop = Layout.Rooms.Foyer.y + Layout.Rooms.Foyer.h + 12.5
	for _, k in keepOut do
		local x0, x1, z0, z1 = k[1], k[2], k[3], k[4]
		local yb = LID - LID_T
		for _, run in
			{
				{ axis = "z", at = x0, out = -1, a0 = z0, a1 = z1 },
				{ axis = "z", at = x1, out = 1, a0 = z0, a1 = z1 },
				{ axis = "x", at = z0, out = -1, a0 = x0, a1 = x1 },
				{ axis = "x", at = z1, out = 1, a0 = x0, a1 = x1 },
			}
		do
			local ext = run.axis == "x" and SKIN or 0
			slab("TowerSkin", run, run.a0 - ext, run.a1 + ext, yb, towerTop, 0, SKIN)
		end
		tiled(
			"TowerTop",
			Vector3.new(x1 - x0 + 2 * SKIN, SKIN, z1 - z0 + 2 * SKIN),
			Vector3.new((x0 + x1) / 2, towerTop + SKIN / 2, (z0 + z1) / 2)
		)
	end

	return fills
end

-- `keepOut`: extra rectangles {x0,x1,z0,z1} where no vault may pass (e.g. the house stair shaft).
function Natatorium.build(root: Instance, keepOut: { { number } }?)
	local pool = Kit.folder(root, "Natatorium")
	local S, n = POOL.spacing, POOL.extent
	local size = S * (n * 2 + 1)
	local footprints = Shell.footprints()

	box(
		pool,
		"PoolFloor",
		Vector3.new(size, 2, size),
		Vector3.new(0, POOL.floorY - 1, 0),
		C.tileDeep,
		Enum.Material.CeramicTiles
	)

	-- the building reads from outside as one tiled block sunk into the pool, rising to the vaults
	local fills = buildBlock(pool, footprints, keepOut or {})
	for _, r in fills do
		table.insert(footprints, r)
	end

	-- piers on the grid corners, skipping any that would stand in the building
	local pierTop = POOL.springY
	local pierH = pierTop - POOL.floorY
	for i = -n, n + 1 do
		for k = -n, n + 1 do
			local px, pz = (i - 0.5) * S, (k - 0.5) * S
			local h = POOL.pier / 2 + 1
			if not overlaps(footprints, px - h, px + h, pz - h, pz + h) then
				box(
					pool,
					"Pier",
					Vector3.new(POOL.pier, pierH, POOL.pier),
					Vector3.new(px, POOL.floorY + pierH / 2, pz),
					C.tile,
					Enum.Material.CeramicTiles
				)
			end
		end
	end

	-- vaults over every bay (except where they'd show inside the stair shaft), cold lights in some bays
	for i = -n, n do
		for k = -n, n do
			local cx, cz = i * S, k * S
			if not overlaps(keepOut or {}, cx - S / 2, cx + S / 2, cz - S / 2, cz + S / 2) then
				barrel(pool, cx, cz, true)
				barrel(pool, cx, cz, false)
			else
				-- no vault here: a flat tiled cap at crown height, so the neighbouring vaults' open
				-- arches look onto tile instead of a black void
				box(
					pool,
					"VaultCap",
					Vector3.new(S, 1, S),
					Vector3.new(cx, POOL.springY + S / 2 + 0.5, cz),
					C.tile,
					Enum.Material.CeramicTiles,
					DETAIL
				)
			end
			if
				(i + k) % 2 == 0
				and math.abs(i) <= 3
				and math.abs(k) <= 3
				and not overlaps(footprints, cx - 2, cx + 2, cz - 2, cz + 2)
			then
				local glow = box(
					pool,
					"VaultGlow",
					Vector3.new(1, 1, 1),
					Vector3.new(cx, POOL.springY + 6, cz),
					C.coldLight,
					nil,
					INVISIBLE
				)
				Kit.pointLight(glow, 50, 0.85, false, C.coldLight)
			end
		end
	end

	-- one bay has an open oculus and a ladder climbing up to it out of the water
	local lx, lz = -3 * S, 0
	local apex = POOL.springY + S / 2
	local oculus = box(
		pool,
		"Oculus",
		Vector3.new(0.4, 7, 7),
		CFrame.new(lx, apex - 1.5, lz) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(225, 240, 240),
		Enum.Material.Neon,
		{
			Shape = Enum.PartType.Cylinder,
			CanCollide = false,
			CastShadow = false,
		}
	)
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Left -- after the roll, the cylinder's -X face points down
	beam.Angle = 50
	beam.Range = 40
	beam.Brightness = 2
	beam.Color = Color3.fromRGB(200, 230, 235)
	beam.Parent = oculus
	local ladderBottom, ladderTop = POOL.floorY, apex - 1.5
	for _, dz in { -0.9, 0.9 } do
		box(
			pool,
			"LadderRail",
			Vector3.new(0.2, ladderTop - ladderBottom, 0.2),
			Vector3.new(lx + 2.6, (ladderBottom + ladderTop) / 2, lz + dz),
			Color3.fromRGB(190, 195, 195),
			Enum.Material.Metal,
			DETAIL
		)
	end
	for y = ladderBottom + 1, ladderTop - 0.5, 1.2 do
		box(
			pool,
			"LadderRung",
			Vector3.new(0.15, 0.15, 1.8),
			Vector3.new(lx + 2.6, y, lz),
			Color3.fromRGB(190, 195, 195),
			Enum.Material.Metal,
			DETAIL
		)
	end

	-- thin mist lying on the water outside the reading hall windows
	for _, z in { -8, 8, 22 } do
		Kit.anchor(pool, "PoolMist", CFrame.new(-52, POOL.waterY + 1.2, z), Vector3.new(24, 2.4, 16))
	end

	-- still water everywhere outside the building (terrain water reflects the vaults)
	local terrain = workspace.Terrain
	terrain:Clear()
	local waterH = POOL.waterY - POOL.floorY
	local waterCf = CFrame.new(0, (POOL.floorY + POOL.waterY) / 2, 0)
	terrain:FillBlock(waterCf, Vector3.new(size, waterH, size), Enum.Material.Water)
	for _, f in footprints do
		terrain:FillBlock(
			CFrame.new((f[1] + f[2]) / 2, (POOL.floorY + POOL.waterY) / 2, (f[3] + f[4]) / 2),
			Vector3.new(f[2] - f[1], waterH + 2, f[4] - f[3]),
			Enum.Material.Air
		)
	end
	terrain.WaterColor = Color3.fromRGB(38, 78, 82)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.7
	terrain.WaterWaveSize = 0.02
	terrain.WaterWaveSpeed = 2
	return pool
end

return Natatorium
