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

	-- the outside of the building is tiled too, as if it had been sunk into the pool: a skin just
	-- outside every wall, below the water and up from the window heads
	for _, f in footprints do
		local x0, x1, z0, z1, top = f[1], f[2], f[3], f[4], f[5]
		local function skin(sx, sz, px, pz, y0, y1)
			-- never inside another room (shared walls have rooms on both sides)
			for _, r in Layout.Rooms do
				if px + sx / 2 > r.x0 and px - sx / 2 < r.x1 and pz + sz / 2 > r.z0 and pz - sz / 2 < r.z1 then
					return
				end
			end
			if y1 > y0 then
				box(
					pool,
					"OuterSkin",
					Vector3.new(sx, y1 - y0, sz),
					Vector3.new(px, (y0 + y1) / 2, pz),
					C.tile,
					Enum.Material.CeramicTiles,
					DETAIL
				)
			end
		end
		for _, s in { -1, 1 } do
			local px = s < 0 and x0 - 0.2 or x1 + 0.2
			local pz = s < 0 and z0 - 0.2 or z1 + 0.2
			skin(0.4, z1 - z0 + 0.8, px, (z0 + z1) / 2, POOL.floorY, POOL.waterY + 0.5)
			skin(0.4, z1 - z0 + 0.8, px, (z0 + z1) / 2, math.max(top - 3, 14.5), top)
			skin(x1 - x0 + 0.8, 0.4, (x0 + x1) / 2, pz, POOL.floorY, top)
		end
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
