--[[
	Furniture and set dressing shared by every lobby room.

	All functions take world-space CFrames whose position is ON THE FLOOR (or on the surface the
	piece stands on). The piece's front faces cf's -Z (LookVector); for seats, the sitter faces -Z.

	Mesh props come from ServerStorage.Props (see Kit.prop): every prop there has its pivot at the
	bottom centre, a FrontYaw attribute that turns its front to -Z, and a Height attribute (studs at
	scale 1). Each piece falls back to a primitive build when its prop is missing.
]]
local Kit = require(script.Parent.Kit)
local Books = require(script.Parent.Books)

local C = Kit.C
local box = Kit.box
local wedge = Kit.wedge
local prop = Kit.prop
local DETAIL = Kit.DETAIL

local Furniture = {}

-- Local palette for the reference look: smooth grey-blue concrete, dark stained wood, black leather.
local CONCRETE = Color3.fromRGB(106, 113, 124)
local CONCRETE_DARK = Color3.fromRGB(78, 83, 92)
local SOIL = Color3.fromRGB(46, 34, 26)
local STAIN = Color3.fromRGB(58, 40, 28)
local FRAME_METAL = Color3.fromRGB(40, 42, 46)
local PAPER = Color3.fromRGB(198, 190, 170)
local SHADE_FABRIC = Color3.fromRGB(232, 206, 160)

local function upCylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra
)
	return Kit.cylinder(parent, name, height, diameter, pos, "y", color, material, extra)
end

-- Height of a prop at `scale` (from its Height attribute), or nil when the prop is missing.
local function propHeight(name: string, scale: number?): number?
	if not Kit.hasProp(name) then
		return nil
	end
	local source = game:GetService("ServerStorage").Props[name]
	return (source:GetAttribute("Height") or 0) * (scale or 1)
end

--[[
	A vertical prism with chamfered corners (a square with its four corners cut at 45 degrees):
	two crossed boxes plus four wedges laid on their side to fill the corner triangles.
	`cf` is the centre of the bottom face; w/d = footprint along local X/Z, c = chamfer leg.
]]
local function chamferPrism(
	parent: Instance,
	name: string,
	cf: CFrame,
	w: number,
	d: number,
	h: number,
	c: number,
	color: Color3,
	material: Enum.Material,
	extra
)
	local mid = cf * CFrame.new(0, h / 2, 0)
	box(parent, name, Vector3.new(w, h, d - 2 * c), mid, color, material, extra)
	box(parent, name, Vector3.new(w - 2 * c, h, d), mid, color, material, extra)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- A wedge's right angle sits at local (-Y, +Z); map local Y -> outward X and local Z -> inward Z
			-- (sign-flipped extrusion axis keeps the frame right-handed) so the triangle fills the corner.
			local corner = Vector3.new(sx * (w / 2 - c / 2), h / 2, sz * (d / 2 - c / 2))
			local frame =
				CFrame.fromMatrix(corner, Vector3.new(0, sx * sz, 0), Vector3.new(sx, 0, 0), Vector3.new(0, 0, -sz))
			wedge(parent, name .. "Chamfer", Vector3.new(h, c, c), cf * frame, color, material, extra)
		end
	end
end

--[[
	A sloped skirt around a w x d rectangle: four wedges whose slope runs from the rectangle's edge
	(at y0, full depth `drop` below y0+drop) out by `out` studs at the top. With `down` the skirt
	flares toward the floor instead (a plinth taper). Long sides (local X) run past the corners so
	the short sides tuck between them, giving a clean folded look at the corners.
]]
local function flare(
	parent: Instance,
	name: string,
	cf: CFrame,
	w: number,
	d: number,
	y0: number,
	rise: number,
	out: number,
	down: boolean,
	color: Color3,
	material: Enum.Material,
	extra
)
	local yc = y0 + rise / 2
	local sides = {
		{ dir = Vector3.new(0, 0, -1), len = w + 2 * out, half = d / 2 },
		{ dir = Vector3.new(0, 0, 1), len = w + 2 * out, half = d / 2 },
		{ dir = Vector3.new(-1, 0, 0), len = d, half = w / 2 },
		{ dir = Vector3.new(1, 0, 0), len = d, half = w / 2 },
	}
	for _, s in sides do
		local outward = s.dir
		local pos = outward * (s.half + out / 2) + Vector3.new(0, yc, 0)
		-- local +Z (the wedge's full vertical face) goes against the shaft; local -Y (its full flat face)
		-- goes on top for a capital flare, or on the bottom for a plinth taper
		local zAxis = -outward
		local yAxis = if down then Vector3.new(0, 1, 0) else Vector3.new(0, -1, 0)
		local xAxis = yAxis:Cross(zAxis)
		wedge(
			parent,
			name,
			Vector3.new(s.len, rise, out),
			cf * CFrame.fromMatrix(pos, xAxis, yAxis, zAxis),
			color,
			material,
			extra
		)
	end
end

-- Plants for planters: sink a potted plant prop so only the foliage shows above the soil.
local PLANTS = { "Plant1", "Plant2", "Fern" }
local POT_FRACTION = { Plant1 = 0.36, Plant2 = 0.38, Fern = 0.22 } -- pot height / prop height
local function plantIn(parent: Instance, soil: CFrame, which: number, scale: number)
	local rng = Kit.rng
	for k = 0, #PLANTS - 1 do
		local name = PLANTS[(which + k - 1) % #PLANTS + 1]
		local h = propHeight(name, scale)
		if h then
			-- drop the pot below the soil line so only the foliage shows
			local sink = h * POT_FRACTION[name]
			return prop(
				parent,
				name,
				soil * CFrame.new(0, -sink, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				scale
			)
		end
	end
	-- fallback: a tuft of leaves
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		wedge(
			parent,
			"Leaf",
			Vector3.new(0.1, 1.6 * scale, 0.7 * scale),
			soil * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.7 * scale, -0.3 * scale) * CFrame.Angles(-0.4, 0, 0),
			Color3.fromRGB(52, 92, 46),
			Enum.Material.Grass,
			DETAIL
		)
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Shelving
----------------------------------------------------------------------------------------------------

-- Bookcase centered at `cf` (base on floor), long along local X, books facing local +Z (and -Z if doubleSided).
function Furniture.bookcase(
	parent: Instance,
	cf: CFrame,
	length: number,
	height: number,
	depth: number,
	doubleSided: boolean
)
	local rng = Kit.rng
	local unit = Kit.folder(parent, "Bookcase")
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	box(
		unit,
		"Back",
		Vector3.new(length, height, 0.3),
		at(0, height / 2, doubleSided and 0 or -depth / 2 + 0.15),
		C.darkWood,
		Enum.Material.Wood
	)
	for _, s in { -1, 1 } do
		box(
			unit,
			"Side",
			Vector3.new(0.5, height, depth),
			at(s * (length / 2 + 0.25), height / 2, 0),
			C.wood,
			Enum.Material.Wood
		)
	end
	box(unit, "Top", Vector3.new(length + 1, 0.4, depth + 0.2), at(0, height + 0.2, 0), C.wood, Enum.Material.Wood)
	box(unit, "Plinth", Vector3.new(length, 0.5, depth), at(0, 0.25, 0), C.darkWood, Enum.Material.Wood)
	local levels = math.floor((height - 0.5) / 2.4)
	for level = 0, levels - 1 do
		local y = 0.5 + level * 2.4
		if level > 0 then
			box(
				unit,
				"Shelf",
				Vector3.new(length, 0.2, depth),
				at(0, y, 0),
				C.wood,
				Enum.Material.Wood,
				{ CastShadow = false }
			)
		end
		local y0 = if level == 0 then y else y + 0.1 -- books sit flush on the plinth, or on the board
		if doubleSided then
			local bookDepth = depth / 2 - 0.45
			for _, side in { 1, -1 } do
				Books.fillShelf(unit, at, length, y0, side * (0.15 + bookDepth / 2 + 0.1), bookDepth, rng)
			end
		else
			Books.fillShelf(unit, at, length, y0, 0.25, depth - 0.7, rng)
		end
	end
	return unit
end

-- Steel utility rack with cardboard boxes of books and loose piles.
function Furniture.metalRack(parent: Instance, cf: CFrame, length: number, height: number, depth: number)
	local rng = Kit.rng
	local unit = Kit.folder(parent, "Rack")
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				unit,
				"Upright",
				Vector3.new(0.25, height, 0.25),
				at(sx * length / 2, height / 2, sz * depth / 2),
				C.steel,
				Enum.Material.Metal
			)
		end
	end
	for i = 0, 3 do
		local y = 0.4 + i * (height - 0.6) / 3
		box(
			unit,
			"Shelf",
			Vector3.new(length, 0.15, depth),
			at(0, y, 0),
			Color3.fromRGB(88, 88, 88),
			Enum.Material.DiamondPlate
		)
		local x = -length / 2 + 0.3
		while x < length / 2 - 1 do
			local w = math.min(rng:NextNumber(1.6, 2.6), length / 2 - 0.3 - x)
			local roll = rng:NextNumber()
			if roll < 0.55 then
				local h = rng:NextNumber(1.1, 1.6)
				box(
					unit,
					"Box",
					Vector3.new(w - 0.1, h, depth - 0.3),
					at(x + w / 2, y + 0.075 + h / 2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0),
					C.cardboard:Lerp(Color3.new(0.3, 0.25, 0.2), rng:NextNumber(0, 0.4)),
					Enum.Material.Cardboard,
					DETAIL
				)
			elseif roll < 0.85 then
				for k = 1, rng:NextInteger(2, 5) do
					box(
						unit,
						"Book",
						Vector3.new(w * 0.7, 0.28, depth * 0.6),
						at(x + w / 2, y + 0.075 + (k - 0.5) * 0.28, 0)
							* CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0),
						Kit.BOOK_COLORS[rng:NextInteger(1, #Kit.BOOK_COLORS)],
						Enum.Material.Fabric,
						DETAIL
					)
				end
			end
			x += w
		end
	end
	return unit
end

-- A pile of books lying on a surface at `pos`: cloth covers with cream page blocks, each turned a little.
function Furniture.bookPile(parent: Instance, pos: Vector3, count: number)
	local rng = Kit.rng
	local pile = Kit.folder(parent, "BookPile")
	local y = pos.Y
	local yaw = rng:NextNumber(0, math.pi * 2)
	for _ = 1, count do
		local w, d = rng:NextNumber(1.1, 1.6), rng:NextNumber(0.8, 1.1)
		local t = rng:NextNumber(0.22, 0.36)
		yaw += math.rad(rng:NextNumber(-18, 18))
		local cf = CFrame.new(pos.X, y + t / 2, pos.Z)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.new(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
		box(
			pile,
			"Cover",
			Vector3.new(w, t, d),
			cf,
			Kit.BOOK_COLORS[rng:NextInteger(1, #Kit.BOOK_COLORS)],
			Enum.Material.Fabric,
			DETAIL
		)
		-- page block shows on three edges (spine side stays cloth)
		box(
			pile,
			"Pages",
			Vector3.new(w - 0.06, t - 0.06, d - 0.02),
			cf * CFrame.new(0.05, 0, 0),
			PAPER,
			Enum.Material.SmoothPlastic,
			DETAIL
		)
		y += t
	end
	return pile
end

-- Row of tall wall bookshelves along cf's X axis, backs against the wall behind (+Z of cf), facing -Z.
-- `cf` is the centre of the row's footprint (shelf depth ~1.6, so put it ~0.9 off the wall).
function Furniture.wallShelves(parent: Instance, cf: CFrame, length: number)
	if not Kit.hasProp("Bookshelf") then
		-- bookcase() puts books toward its +Z; turn it so they face cf's -Z
		Furniture.bookcase(parent, cf * CFrame.Angles(0, math.pi, 0), length, 11, 2.4, false)
		return
	end
	local width = 6.2
	local count = math.max(1, math.floor(length / width + 0.5))
	for i = 1, count do
		local x = (i - (count + 1) / 2) * width
		prop(parent, "Bookshelf", cf * CFrame.new(x, 0, 0))
	end
end

----------------------------------------------------------------------------------------------------
-- Seating
----------------------------------------------------------------------------------------------------

-- Dark-stained library chair with a leather seat; the sitter faces cf's -Z. 10 parts.
function Furniture.chair(parent: Instance, cf: CFrame)
	local model = Kit.folder(parent, "Chair")
	local seatY, w, d = 1.95, 1.8, 1.7
	local legH = seatY - 0.12
	local rake = CFrame.Angles(math.rad(8), 0, 0) -- back leans away from the sitter (+Z)
	for _, x in { -w / 2 + 0.12, w / 2 - 0.12 } do
		box(
			model,
			"Leg",
			Vector3.new(0.2, legH, 0.2),
			cf * CFrame.new(x, legH / 2, -d / 2 + 0.12),
			STAIN,
			Enum.Material.Wood,
			DETAIL
		)
		-- back leg continues up as the back post
		box(
			model,
			"Post",
			Vector3.new(0.2, 4.2, 0.22),
			cf * CFrame.new(x, 0, d / 2 - 0.13) * rake * CFrame.new(0, 2.1, 0),
			STAIN,
			Enum.Material.Wood,
			DETAIL
		)
	end
	box(model, "Seat", Vector3.new(w, 0.24, d), cf * CFrame.new(0, seatY - 0.12, 0), STAIN, Enum.Material.Wood)
	box(
		model,
		"Cushion",
		Vector3.new(w - 0.25, 0.16, d - 0.3),
		cf * CFrame.new(0, seatY + 0.07, -0.05),
		Color3.fromRGB(70, 30, 26),
		Enum.Material.Leather,
		DETAIL
	)
	local back = cf * CFrame.new(0, 0, d / 2 - 0.13) * rake
	box(
		model,
		"TopRail",
		Vector3.new(w - 0.1, 0.42, 0.18),
		back * CFrame.new(0, 3.95, 0),
		STAIN,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		model,
		"MidRail",
		Vector3.new(w - 0.3, 0.16, 0.14),
		back * CFrame.new(0, 2.85, 0),
		STAIN,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		model,
		"Splat",
		Vector3.new(0.5, 1.0, 0.1),
		back * CFrame.new(0, 3.3, 0),
		Color3.fromRGB(74, 50, 34),
		Enum.Material.Wood,
		DETAIL
	)
	box(
		model,
		"Apron",
		Vector3.new(w - 0.3, 0.22, 0.12),
		cf * CFrame.new(0, seatY - 0.35, -d / 2 + 0.14),
		STAIN,
		Enum.Material.Wood,
		DETAIL
	)
	return model
end

-- Black mesh office chair (reference study rows).
function Furniture.officeChair(parent: Instance, cf: CFrame)
	local m = prop(parent, "OfficeChair", cf)
	if m then
		return m
	end
	return Furniture.chair(parent, cf)
end

-- Upholstered armchair. Without a colour: the black leather wingback; with one: the fabric armchair
-- tinted to that colour (falls back to a primitive build).
function Furniture.armchair(parent: Instance, cf: CFrame, color: Color3?)
	if color then
		local m = prop(parent, "Armchair", cf)
		if m then
			-- tint the upholstery (untextured fabric meshes), keep wood feet as they are
			for _, p in m:GetDescendants() do
				if p:IsA("MeshPart") and p.TextureID == "" and not p:FindFirstChildWhichIsA("SurfaceAppearance") then
					p.Color = color
				end
			end
			return m
		end
	else
		local m = prop(parent, "ArmchairLeather", cf) or prop(parent, "Armchair", cf)
		if m then
			return m
		end
	end
	color = color or Color3.fromRGB(70, 40, 36)
	local model = Kit.folder(parent, "Armchair")
	box(model, "Base", Vector3.new(3.2, 1.0, 3), cf * CFrame.new(0, 0.7, 0), color, Enum.Material.Fabric)
	box(
		model,
		"Cushion",
		Vector3.new(2.2, 0.5, 2.5),
		cf * CFrame.new(0, 1.45, -0.2),
		color,
		Enum.Material.Fabric,
		DETAIL
	)
	box(model, "Back", Vector3.new(3.2, 2.8, 0.7), cf * CFrame.new(0, 2.2, 1.15), color, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		box(
			model,
			"Arm",
			Vector3.new(0.5, 1.2, 3),
			cf * CFrame.new(s * 1.35, 1.75, 0),
			color,
			Enum.Material.Fabric,
			DETAIL
		)
		for _, z in { -1.3, 1.3 } do
			box(
				model,
				"Foot",
				Vector3.new(0.25, 0.2, 0.25),
				cf * CFrame.new(s * 1.4, 0.1, z),
				STAIN,
				Enum.Material.Wood,
				DETAIL
			)
		end
	end
	return model
end

-- Worn leather sofa (seats ~1.9 studs high). `color` tints the primitive fallback only.
function Furniture.sofa(parent: Instance, cf: CFrame, color: Color3?)
	local m = prop(parent, "Sofa", cf)
	if m then
		return m
	end
	color = color or Color3.fromRGB(96, 48, 34)
	local model = Kit.folder(parent, "Sofa")
	local L = 7.5
	box(model, "Base", Vector3.new(L, 1.1, 3.2), cf * CFrame.new(0, 0.75, 0), color, Enum.Material.Leather)
	for _, x in { -L / 4 + 0.05, L / 4 - 0.05 } do
		box(
			model,
			"Cushion",
			Vector3.new(L / 2 - 0.9, 0.55, 2.5),
			cf * CFrame.new(x, 1.6, -0.3),
			color,
			Enum.Material.Leather,
			DETAIL
		)
		box(
			model,
			"BackCushion",
			Vector3.new(L / 2 - 0.9, 1.5, 0.6),
			cf * CFrame.new(x, 2.5, 1.0) * CFrame.Angles(math.rad(-10), 0, 0),
			color,
			Enum.Material.Leather,
			DETAIL
		)
	end
	box(model, "Back", Vector3.new(L, 2.6, 0.6), cf * CFrame.new(0, 1.9, 1.35), color, Enum.Material.Leather)
	for _, s in { -1, 1 } do
		box(
			model,
			"Arm",
			Vector3.new(0.7, 1.5, 3.2),
			cf * CFrame.new(s * (L / 2 - 0.35), 1.6, 0),
			color,
			Enum.Material.Leather,
			DETAIL
		)
	end
	return model
end

-- Waiting bench: dark wooden slats on black steel frames, back toward cf's +Z. Depth ~2.2.
function Furniture.bench(parent: Instance, cf: CFrame, length: number)
	local model = Kit.folder(parent, "Bench")
	local seatY = 1.9
	-- seat: three slats with gaps
	for i, z in { -0.62, 0, 0.62 } do
		box(
			model,
			"Slat",
			Vector3.new(length, 0.16, 0.52),
			cf * CFrame.new(0, seatY - 0.08, z),
			STAIN,
			Enum.Material.Wood,
			if i == 2 then nil else DETAIL
		)
	end
	-- back: two slats on a reclined plane
	local back = cf * CFrame.new(0, seatY, 0.95) * CFrame.Angles(math.rad(12), 0, 0)
	for _, y in { 0.75, 1.45 } do
		box(
			model,
			"BackSlat",
			Vector3.new(length, 0.5, 0.14),
			back * CFrame.new(0, y, 0),
			STAIN,
			Enum.Material.Wood,
			DETAIL
		)
	end
	-- frames: front leg, back leg/post, seat bearer, at each end and every ~4 studs
	local frames = math.max(2, math.floor(length / 4) + 1)
	for i = 0, frames - 1 do
		local x = -length / 2 + 0.5 + i * (length - 1) / (frames - 1)
		box(
			model,
			"LegFront",
			Vector3.new(0.18, seatY - 0.16, 0.18),
			cf * CFrame.new(x, (seatY - 0.16) / 2, -0.75),
			FRAME_METAL,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			model,
			"Bearer",
			Vector3.new(0.16, 0.16, 1.9),
			cf * CFrame.new(x, seatY - 0.24, 0),
			FRAME_METAL,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			model,
			"LegBack",
			Vector3.new(0.18, seatY - 0.16, 0.18),
			cf * CFrame.new(x, (seatY - 0.16) / 2, 0.75),
			FRAME_METAL,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			model,
			"Post",
			Vector3.new(0.14, 1.9, 0.14),
			back * CFrame.new(x, 0.95, 0.12),
			FRAME_METAL,
			Enum.Material.Metal,
			DETAIL
		)
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Tables and lamps
----------------------------------------------------------------------------------------------------

-- Green banker's lamp standing on a surface at `pos`; the shade glows warm (no bulb visible).
function Furniture.deskLamp(parent: Instance, pos: Vector3, range: number?)
	local rng = Kit.rng
	local yaw = CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0)
	local lamp = prop(parent, "BankerLamp", CFrame.new(pos) * yaw, 1)
	local glowCf
	if lamp then
		glowCf = CFrame.new(pos) * yaw * CFrame.new(0, 1.0, 0)
	else
		lamp = Kit.folder(parent, "BankerLamp")
		box(
			lamp,
			"LampBase",
			Vector3.new(0.7, 0.12, 0.45),
			pos + Vector3.new(0, 0.06, 0),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			lamp,
			"LampStem",
			Vector3.new(0.1, 0.95, 0.1),
			pos + Vector3.new(0, 0.55, 0),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			lamp,
			"LampShade",
			Vector3.new(1.1, 0.3, 0.45),
			CFrame.new(pos + Vector3.new(0, 1.1, 0)) * yaw,
			Color3.fromRGB(30, 96, 60),
			Enum.Material.Glass,
			DETAIL
		)
		glowCf = CFrame.new(pos) * yaw * CFrame.new(0, 0.93, 0)
	end
	-- glowing strip under the shade, a soft halo, and the light itself
	local glow = box(lamp, "Glow", Vector3.new(0.75, 0.05, 0.22), glowCf, Kit.GLOW, Enum.Material.Neon, DETAIL)
	glow.Transparency = 0.25
	Kit.halo(glow, 1.4)
	Kit.pointLight(glow, range or 9, 0.9, false)
	return lamp
end

-- Tall floor lamp: weighted base, brass pole, glowing fabric drum shade with a warm halo.
function Furniture.floorLamp(parent: Instance, pos: Vector3)
	local model = Kit.folder(parent, "FloorLamp")
	upCylinder(model, "Base", 0.14, 1.3, pos + Vector3.new(0, 0.07, 0), FRAME_METAL, Enum.Material.Metal)
	upCylinder(
		model,
		"Pole",
		4.9,
		0.14,
		pos + Vector3.new(0, 2.5, 0),
		Color3.fromRGB(96, 74, 46),
		Enum.Material.Metal,
		DETAIL
	)
	local shadeY = pos.Y + 5.25
	-- drum shade: slightly tapered (two stacked drums), lit from inside
	upCylinder(
		model,
		"Shade",
		0.65,
		1.75,
		Vector3.new(pos.X, shadeY - 0.3, pos.Z),
		SHADE_FABRIC,
		Enum.Material.SmoothPlastic,
		{ CanCollide = false, CastShadow = false, Transparency = 0.12 }
	)
	upCylinder(
		model,
		"ShadeTop",
		0.6,
		1.5,
		Vector3.new(pos.X, shadeY + 0.32, pos.Z),
		SHADE_FABRIC,
		Enum.Material.SmoothPlastic,
		{ CanCollide = false, CastShadow = false, Transparency = 0.12 }
	)
	local core =
		upCylinder(model, "Glow", 1.0, 1.25, Vector3.new(pos.X, shadeY, pos.Z), Kit.GLOW, Enum.Material.Neon, DETAIL)
	core.Transparency = 0.45
	Kit.halo(core, 4.2)
	Kit.pointLight(core, 16, 1.1, false)
	return model
end

-- Small round side table; returns the world Y of its top surface.
function Furniture.sideTable(parent: Instance, cf: CFrame): number
	local model = Kit.folder(parent, "SideTable")
	local topY = 2.45
	upCylinder(model, "Top", 0.14, 2.1, (cf * CFrame.new(0, topY - 0.07, 0)).Position, STAIN, Enum.Material.Wood)
	upCylinder(
		model,
		"Pedestal",
		topY - 0.4,
		0.28,
		(cf * CFrame.new(0, (topY - 0.14 + 0.26) / 2, 0)).Position,
		STAIN,
		Enum.Material.Wood,
		DETAIL
	)
	upCylinder(model, "Shelf", 0.1, 1.4, (cf * CFrame.new(0, 0.9, 0)).Position, STAIN, Enum.Material.Wood, DETAIL)
	upCylinder(
		model,
		"Foot",
		0.26,
		1.2,
		(cf * CFrame.new(0, 0.13, 0)).Position,
		Color3.fromRGB(44, 30, 22),
		Enum.Material.Wood
	)
	return (cf * CFrame.new(0, topY, 0)).Position.Y
end

-- Loose sheets of paper lying on a surface at local (x, y, z) of `cf`.
local function papers(parent: Instance, cf: CFrame, x: number, y: number, z: number, n: number)
	local rng = Kit.rng
	for k = 1, n do
		box(
			parent,
			"Paper",
			Vector3.new(0.85, 0.02, 1.1),
			cf
				* CFrame.new(x + rng:NextNumber(-0.3, 0.3), y + 0.01 + (k - 1) * 0.02, z + rng:NextNumber(-0.2, 0.2))
				* CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0),
			PAPER:Lerp(Color3.fromRGB(200, 186, 150), rng:NextNumber(0, 0.5)),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
end

-- Long reading table with a lamp, books and chairs pulled up to both long sides, each facing the table.
function Furniture.readingTable(parent: Instance, cf: CFrame)
	local model = Kit.folder(parent, "ReadingTable")
	local topY = 3
	box(
		model,
		"Top",
		Vector3.new(7, 0.3, 3.6),
		cf * CFrame.new(0, topY - 0.15, 0),
		Color3.fromRGB(86, 58, 38),
		Enum.Material.Wood
	)
	for _, x in { -3.1, 3.1 } do
		for _, z in { -1.4, 1.4 } do
			box(
				model,
				"Leg",
				Vector3.new(0.32, topY - 0.3, 0.32),
				cf * CFrame.new(x, (topY - 0.3) / 2, z),
				STAIN,
				Enum.Material.Wood
			)
		end
	end
	for _, z in { -1.45, 1.45 } do
		box(
			model,
			"Apron",
			Vector3.new(6.0, 0.4, 0.14),
			cf * CFrame.new(0, topY - 0.5, z),
			STAIN,
			Enum.Material.Wood,
			DETAIL
		)
	end
	Furniture.deskLamp(model, (cf * CFrame.new(1.9, topY, 0.3)).Position)
	Furniture.bookPile(model, (cf * CFrame.new(-1.8, topY, 0.4)).Position, 3)
	papers(model, cf, 0.2, topY, -0.6, 2)
	local rng = Kit.rng
	for _, side in { -1, 1 } do
		for _, x in { -1.6, 1.6 } do
			-- chair on this side, sitter facing the table (cf's -Z points at the table), pulled out a bit
			local seat = cf * CFrame.new(x + rng:NextNumber(-0.15, 0.15), 0, side * rng:NextNumber(2.25, 2.6))
			local facing = CFrame.lookAt(seat.Position, (cf * CFrame.new(x, 0, 0)).Position)
			Furniture.chair(model, facing * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0))
		end
	end
	return model
end

--[[
	Long library study desk along cf's X axis (front = cf's -Z). Office chairs face the desk from the
	front side; when `seats` don't fit on one side the rest go on the back side (facing the other way).
	Banker lamps glow between seats; books and papers are scattered on the top.
]]
function Furniture.studyDesk(parent: Instance, cf: CFrame, length: number, seats: number)
	local rng = Kit.rng
	local model = Kit.folder(parent, "StudyDesk")
	local topY, depth = 3, 3.4
	box(
		model,
		"Top",
		Vector3.new(length, 0.22, depth),
		cf * CFrame.new(0, topY - 0.11, 0),
		Color3.fromRGB(64, 46, 34),
		Enum.Material.Wood
	)
	-- thin dark edge band so the top reads as a slab
	box(
		model,
		"Edge",
		Vector3.new(length + 0.04, 0.12, depth + 0.04),
		cf * CFrame.new(0, topY - 0.28, 0),
		Color3.fromRGB(34, 26, 22),
		Enum.Material.Wood,
		DETAIL
	)
	-- end panels and mid supports (panel legs), plus a modesty panel down the middle
	local supports = math.max(2, math.floor(length / 6) + 1)
	for i = 0, supports - 1 do
		local x = -length / 2 + 0.25 + i * (length - 0.5) / (supports - 1)
		box(
			model,
			"Panel",
			Vector3.new(0.25, topY - 0.34, depth - 0.4),
			cf * CFrame.new(x, (topY - 0.34) / 2, 0),
			Color3.fromRGB(44, 34, 28),
			Enum.Material.Wood
		)
	end
	box(
		model,
		"Modesty",
		Vector3.new(length - 0.6, 1.4, 0.12),
		cf * CFrame.new(0, topY - 1.04, 0),
		Color3.fromRGB(44, 34, 28),
		Enum.Material.Wood,
		DETAIL
	)

	-- seats: front side first, then the back side
	local perSide = math.max(1, math.floor(length / 3.2))
	local front = math.min(seats, perSide)
	local back = math.min(seats - front, perSide)
	local spots = {}
	for _, spec in { { n = front, side = -1 }, { n = back, side = 1 } } do
		for i = 1, spec.n do
			local x = (i - (spec.n + 1) / 2) * (length / spec.n)
			table.insert(spots, { x = x, side = spec.side })
		end
	end
	for _, s in spots do
		local pos = cf * CFrame.new(s.x + rng:NextNumber(-0.25, 0.25), 0, s.side * rng:NextNumber(2.2, 2.7))
		local facing = CFrame.lookAt(pos.Position, (cf * CFrame.new(s.x, 0, 0)).Position)
		Furniture.officeChair(model, facing * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0))
	end

	-- desk clutter: a lamp every ~6 studs on the centre line, books and papers in front of seats
	local lamps = math.max(1, math.floor(length / 6 + 0.5))
	for i = 1, lamps do
		local x = (i - (lamps + 1) / 2) * (length / lamps)
		Furniture.deskLamp(model, (cf * CFrame.new(x, topY, 0)).Position, 10)
	end
	for _, s in spots do
		local roll = rng:NextNumber()
		if roll < 0.45 then
			Furniture.bookPile(
				model,
				(cf * CFrame.new(s.x + rng:NextNumber(-0.8, 0.8), topY, s.side * 0.9)).Position,
				rng:NextInteger(1, 3)
			)
		end
		papers(model, cf, s.x + rng:NextNumber(-0.4, 0.4), topY, s.side * 1.0, rng:NextInteger(1, 2))
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Concrete: pillars and planters
----------------------------------------------------------------------------------------------------

--[[
	Floor-to-ceiling column in the reference style: a dark plinth, a chamfered square shaft, then an
	angled capital that flares out to meet the ceiling at `pos.Y + height`.
]]
function Furniture.pillar(parent: Instance, pos: Vector3, height: number)
	local model = Kit.folder(parent, "Pillar")
	local cf = CFrame.new(pos)
	local W, chamfer = 3, 0.45
	local capH, flareH, flareOut = 1.1, 1.6, 0.9
	local plinthH = 0.8
	local shaftH = height - capH - flareH - plinthH
	-- plinth: slightly wider, darker band at the bottom with a sloped top lip
	chamferPrism(
		model,
		"Plinth",
		cf,
		W + 0.5,
		W + 0.5,
		plinthH - 0.25,
		chamfer + 0.2,
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	flare(
		model,
		"PlinthSlope",
		cf,
		W,
		W,
		plinthH - 0.25,
		0.25,
		0.25,
		true,
		CONCRETE_DARK,
		Enum.Material.Concrete,
		DETAIL
	)
	chamferPrism(
		model,
		"Shaft",
		cf * CFrame.new(0, plinthH, 0),
		W,
		W,
		shaftH + flareH,
		chamfer,
		CONCRETE,
		Enum.Material.Plaster
	)
	-- angled capital: sloped skirt from the shaft out to the cap block, cap block meets the ceiling
	local capW = W + 2 * flareOut
	flare(
		model,
		"Flare",
		cf,
		W,
		W,
		height - capH - flareH,
		flareH,
		flareOut,
		false,
		CONCRETE,
		Enum.Material.Plaster,
		{ CastShadow = false }
	)
	box(
		model,
		"Cap",
		Vector3.new(capW, capH, capW),
		cf * CFrame.new(0, height - capH / 2, 0),
		CONCRETE,
		Enum.Material.Plaster
	)
	-- shadow-line groove where the shaft meets the flare
	box(
		model,
		"Groove",
		Vector3.new(W + 0.06, 0.12, W - 2 * chamfer),
		cf * CFrame.new(0, height - capH - flareH - 0.35, 0),
		CONCRETE_DARK,
		Enum.Material.Plaster,
		DETAIL
	)
	box(
		model,
		"Groove",
		Vector3.new(W - 2 * chamfer, 0.12, W + 0.06),
		cf * CFrame.new(0, height - capH - flareH - 0.35, 0),
		CONCRETE_DARK,
		Enum.Material.Plaster,
		DETAIL
	)
	return model
end

--[[
	Freestanding angled concrete pedestal (~7-9 studs) with a planter and a lush plant on top
	(reference: half-pillar whose top flares out into a planter box).
]]
function Furniture.planterPillar(parent: Instance, pos: Vector3, height: number?)
	local model = Kit.folder(parent, "PlanterPillar")
	local H = height or 7.5
	local cf = CFrame.new(pos) * CFrame.Angles(0, Kit.rng:NextInteger(0, 3) * math.pi / 2, 0)
	local W, chamfer = 2.4, 0.35
	local boxH, flareH, flareOut = 1.5, 1.3, 0.75
	local baseH = 0.9
	-- base block, tapering in to the shaft
	chamferPrism(model, "Base", cf, W + 0.8, W + 0.8, baseH - 0.4, chamfer + 0.2, CONCRETE_DARK, Enum.Material.Concrete)
	flare(model, "BaseTaper", cf, W, W, baseH - 0.4, 0.4, 0.4, true, CONCRETE_DARK, Enum.Material.Concrete, DETAIL)
	chamferPrism(
		model,
		"Shaft",
		cf * CFrame.new(0, baseH, 0),
		W,
		W,
		H - baseH - boxH,
		chamfer,
		CONCRETE,
		Enum.Material.Plaster
	)
	-- flare out to the planter box
	flare(
		model,
		"Flare",
		cf,
		W,
		W,
		H - boxH - flareH,
		flareH,
		flareOut,
		false,
		CONCRETE,
		Enum.Material.Plaster,
		{ CastShadow = false }
	)
	local bw = W + 2 * flareOut
	local rim = 0.3
	local topCf = cf * CFrame.new(0, H - boxH, 0)
	box(
		model,
		"PlanterFloor",
		Vector3.new(bw, boxH - 0.4, bw),
		topCf * CFrame.new(0, (boxH - 0.4) / 2, 0),
		CONCRETE,
		Enum.Material.Plaster
	)
	for _, s in { -1, 1 } do
		box(
			model,
			"Rim",
			Vector3.new(bw, 0.4, rim),
			topCf * CFrame.new(0, boxH - 0.2, s * (bw / 2 - rim / 2)),
			CONCRETE,
			Enum.Material.Plaster,
			{ CastShadow = false }
		)
		box(
			model,
			"Rim",
			Vector3.new(rim, 0.4, bw - 2 * rim),
			topCf * CFrame.new(s * (bw / 2 - rim / 2), boxH - 0.2, 0),
			CONCRETE,
			Enum.Material.Plaster,
			{ CastShadow = false }
		)
	end
	local soilY = boxH - 0.15
	box(
		model,
		"Soil",
		Vector3.new(bw - 2 * rim, 0.1, bw - 2 * rim),
		topCf * CFrame.new(0, soilY - 0.05, 0),
		SOIL,
		Enum.Material.Ground,
		DETAIL
	)
	plantIn(model, topCf * CFrame.new(0, soilY, 0), 1, 1.55)
	return model
end

-- Low concrete planter box along cf's X axis with plants every ~2.6 studs.
function Furniture.planter(parent: Instance, cf: CFrame, length: number)
	local model = Kit.folder(parent, "Planter")
	local h, d, rim = 1.7, 2.2, 0.3
	box(
		model,
		"Body",
		Vector3.new(length, h - 0.2, d),
		cf * CFrame.new(0, (h - 0.2) / 2, 0),
		CONCRETE,
		Enum.Material.Plaster
	)
	-- overhanging chamfered lip
	for _, s in { -1, 1 } do
		box(
			model,
			"Lip",
			Vector3.new(length + 0.3, 0.2, rim + 0.15),
			cf * CFrame.new(0, h - 0.1, s * (d / 2 - rim / 2 + 0.075)),
			CONCRETE,
			Enum.Material.Plaster,
			{ CastShadow = false }
		)
		box(
			model,
			"Lip",
			Vector3.new(rim + 0.15, 0.2, d - 2 * rim),
			cf * CFrame.new(s * (length / 2 - rim / 2 + 0.075), h - 0.1, 0),
			CONCRETE,
			Enum.Material.Plaster,
			{ CastShadow = false }
		)
	end
	box(
		model,
		"Kick",
		Vector3.new(length - 0.3, 0.3, d + 0.06),
		cf * CFrame.new(0, 0.15, 0),
		CONCRETE_DARK,
		Enum.Material.Concrete,
		DETAIL
	)
	box(
		model,
		"Soil",
		Vector3.new(length - 2 * rim, 0.1, d - 2 * rim),
		cf * CFrame.new(0, h - 0.25, 0),
		SOIL,
		Enum.Material.Ground,
		DETAIL
	)
	local n = math.max(1, math.floor(length / 2.6))
	for i = 1, n do
		local x = (i - (n + 1) / 2) * (length / n)
		plantIn(model, cf * CFrame.new(x, h - 0.2, 0), i, 0.95)
	end
	return model
end

-- A potted plant on the floor (or any surface). `size` scales it (1 = ~4.6 studs tall).
function Furniture.pottedPlant(parent: Instance, cf: CFrame, size: number?)
	local scale = size or 1
	local rng = Kit.rng
	local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local m = prop(parent, if rng:NextNumber() < 0.6 then "Plant1" else "Plant2", cf * spin, scale)
		or prop(parent, "Fern", cf * spin, scale)
	if m then
		return m
	end
	local model = Kit.folder(parent, "PottedPlant")
	chamferPrism(model, "Pot", cf, 1.4 * scale, 1.4 * scale, 1.3 * scale, 0.2 * scale, CONCRETE, Enum.Material.Plaster)
	plantIn(model, cf * CFrame.new(0, 1.3 * scale, 0), 1, scale)
	return model
end

-- Cluster of cardboard boxes; a few are stacked and rest exactly on the box below.
function Furniture.boxes(parent: Instance, cf: CFrame, count: number)
	local rng = Kit.rng
	local model = Kit.folder(parent, "Boxes")
	-- ground ring of spots around cf, then stack on the earlier ones
	local spots = {
		Vector3.new(0, 0, 0),
		Vector3.new(3.0, 0, 0.4),
		Vector3.new(0.3, 0, 3.4),
		Vector3.new(-2.9, 0, 1.1),
		Vector3.new(3.4, 0, 3.8),
	}
	local placed = {}
	for i = 1, count do
		local scale = rng:NextNumber(0.85, 1.1)
		local name = if rng:NextNumber() < 0.3 then "BoxOpen" else "BoxTaped"
		local h = propHeight(name, scale)
		local yaw = CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0)
		local base
		-- every third box goes on top of an earlier closed box
		if i % 3 == 0 and #placed > 0 then
			local under = placed[#placed]
			if under.closed then
				name = "BoxTaped"
				scale = math.min(scale, under.scale * 0.85)
				h = propHeight(name, scale)
				base = CFrame.new(under.top) * yaw
				table.remove(placed, #placed)
			end
		end
		if not base then
			local spot = spots[((#model:GetChildren()) % #spots) + 1]
			base = cf * CFrame.new(spot) * yaw
		end
		if h then
			local m = prop(model, name, base, scale)
			if m and name == "BoxTaped" then
				table.insert(placed, { top = base.Position + Vector3.new(0, h, 0), scale = scale, closed = true })
			end
		else
			-- primitive fallback
			local s = Vector3.new(2.2, 1.8, 2.8) * scale
			box(model, "Box", s, base * CFrame.new(0, s.Y / 2, 0), C.cardboard, Enum.Material.Cardboard)
			box(
				model,
				"Tape",
				Vector3.new(0.5, 0.02, s.Z + 0.02),
				base * CFrame.new(0, s.Y + 0.01, 0),
				Color3.fromRGB(170, 140, 96),
				Enum.Material.SmoothPlastic,
				DETAIL
			)
			table.insert(placed, { top = base.Position + Vector3.new(0, s.Y, 0), scale = scale, closed = true })
		end
	end
	return model
end

return Furniture
