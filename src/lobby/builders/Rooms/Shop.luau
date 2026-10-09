--[[
	The Gift Shop: Teeth's room. The one room in the lobby that goes dark: black and deep purple where
	everything else is warm. The shopkeeper himself (a tall black-purple grinning thing) is built at runtime
	by ShopkeeperService at Layout.Shopkeeper, behind the counter; the floor there (x -25..-22, z 50..56)
	is kept clear of props.

	Two halves:
	  * Storefront, on the foyer side of the shared wall (the x = Openings.ShopDoor.x1 face, facing +X):
	    the steel portal round the opening, planters and the chalk A-board stay; the marquee box sign has
	    gone black enamel with violet trim, cold violet-white lettering, a violet neon tube and a ring of
	    pale bulbs with a few of them dead.
	  * Interior (Layout.Rooms.Shop): purple damask wallpaper (a tinted Texture on thin panels over the
	    shell walls), ebony wainscot, black marble floor and ceiling, a dark-wood checkout counter with a
	    magenta underglow (the "Shop" ProximityPrompt), and behind it the lantern wall: every lantern in
	    Lanterns.List in its own velvet cubby, warm-flamed (the lanterns are the only warm light in here).
	    Around the walls: card catalogue, stock rack, books for sale, a picks table, a postcard spinner,
	    a curio vitrine, a featured lantern under a glass dome, his posters, plants and a shelf of
	    unlit black candles. Lighting is cold: black pendants with violet bulbs, violet track spots.

	Everything is built in world coordinates; the room shell (floor, walls, ceiling) comes from Shell.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.Kit)
local Layout = require(script.Parent.Parent.Layout)
local Furniture = require(script.Parent.Parent.Furniture)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local R = Layout.Rooms.Shop
local DOOR = Layout.Openings.ShopDoor
local FY = R.y -- foyer / shell floor
local FLOOR_RAISE = 0.1 -- the black tiles laid over the shell floor
local SF = R.y + FLOOR_RAISE -- shop floor: everything inside stands on the tiles
local CEIL = R.y + R.h -- shop ceiling
local FOYER_CEIL = Layout.Rooms.Foyer.y + Layout.Rooms.Foyer.h
local FRONT_X = DOOR.x1 -- foyer face of the shared wall
local DOOR_ZC = (DOOR.z0 + DOOR.z1) / 2
local WALL_OUT = 0.17 -- front face of the wallpaper panels; wall-hung things sit on this

-- Teeth's palette: ebony and black walnut, deep-purple velvet, dulled gilt, cold violet light.
local STEEL = Color3.fromRGB(56, 64, 76) -- blue-grey painted steel (portal, track)
local BLACK = Color3.fromRGB(12, 10, 14) -- enamel, sign case, skirting
local SOOT = Color3.fromRGB(16, 12, 18) -- ceiling, cornice, beam
local EBONY = Color3.fromRGB(26, 18, 22) -- carcasses, plinths, legs
local WALNUT = Color3.fromRGB(40, 26, 34) -- tops, doors, trims
local WALNUT_LIGHT = Color3.fromRGB(56, 38, 48) -- raised panels, drawer fronts
local VELVET = Color3.fromRGB(50, 16, 70) -- cubby velvet
local VELVET_DARK = Color3.fromRGB(34, 10, 50)
local GOLD = Color3.fromRGB(146, 118, 70) -- dulled gilt lettering
local BRASS = Color3.fromRGB(84, 68, 40) -- tarnished hardware
local CARD = Color3.fromRGB(38, 20, 56) -- price tags, cards, labels
local CARD_TEXT = Color3.fromRGB(222, 208, 240) -- pale lilac print
local CARD_ACCENT = Color3.fromRGB(190, 140, 255) -- brighter lilac print
local PAPER = Color3.fromRGB(16, 10, 22) -- poster paper
local POSTER_FRAME = Color3.fromRGB(62, 34, 100) -- violet frames, like the reference
local VIOLET = Color3.fromRGB(150, 90, 255) -- glow behind lettering, neon tubes
local COLD = Color3.fromRGB(200, 170, 255) -- cold violet-white light
local COLD_NEON = Color3.fromRGB(150, 110, 255) -- neon parts (Neon renders much paler than its colour)
local MAGENTA = Color3.fromRGB(200, 70, 255) -- counter underglow
local SIGN_TEXT = Color3.fromRGB(230, 220, 255)
local BONE = Color3.fromRGB(196, 186, 206) -- keys, pages, quills: grey-lilac instead of cream
local TILE_A = Color3.fromRGB(22, 16, 26)
local TILE_B = Color3.fromRGB(30, 22, 34)
local GLASS = { Transparency = 0.82, Reflectance = 0.08, CanCollide = false, CastShadow = false }

-- Wallpaper: "Black & Tan Damask (S)" from the Creator Store (decal 4818172644 wraps this image), a seamless
-- black damask on cream. Tinted dark violet the cream becomes the purple ground and the damask stays black.
local WALLPAPER = "rbxassetid://4818172612"
local WALLPAPER_TINT = Color3.fromRGB(48, 22, 74)
local WALLPAPER_BASE = Color3.fromRGB(20, 10, 30)
local WALLPAPER_TILE = 6 -- studs per repeat

local Shop = {}

-- CFrame at `pos` whose front (-Z, LookVector) points along `dir`: surfaces facing that way are Front.
local function facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.lookAt(pos, pos + dir)
end

local function cyl(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material,
	extra
)
	-- cylinder along cf's Y axis (upright when cf is upright)
	local part = box(
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		extra
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Glowing SurfaceGui text: an unlit label with a soft stroke "bloom" behind it.
local function glowText(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	font: Enum.Font,
	color: Color3,
	glow: Color3,
	ppm: number?
)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppm or 60
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = part
	for i, spec in { { 7, 0.82 }, { 3, 0.6 }, { 0, 1 } } do
		local label = Instance.new("TextLabel")
		label.Name = "Glow" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = font
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = color
		label.ZIndex = i
		label.TextTransparency = if i == 1 then 0.75 elseif i == 2 then 0.45 else 0
		if i < 3 then
			label.TextColor3 = glow
		end
		label.Parent = gui
		if spec[1] > 0 then
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = spec[1]
			stroke.Color = glow
			stroke.Transparency = spec[2]
			stroke.Parent = label
		end
	end
	return gui
end

-- Printed card/poster text (lit by the room).
local function printText(part: BasePart, face: Enum.NormalId, lines, bg: Color3?, ppm: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppm or 50
	gui.LightInfluence = 1
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = bg and 0 or 1
	frame.BackgroundColor3 = bg or Color3.new()
	frame.BorderSizePixel = 0
	frame.Parent = gui
	-- each line: { text, font, color, y0, y1 } in scale units of the card height
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.07, line[4])
		label.Size = UDim2.fromScale(0.86, line[5] - line[4])
		label.Font = line[2]
		label.Text = line[1]
		label.TextColor3 = line[3]
		label.TextScaled = true
		label.Parent = frame
	end
	return gui
end

-- Cold version of Kit.halo: concentric discs fading outward, lilac at the rim to near-white at the core.
local function coldHalo(part: BasePart, studs: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Halo"
	gui.Size = UDim2.fromScale(studs, studs)
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.MaxDistance = 120
	gui.Parent = part
	for i, spec in { { 1, 0.95 }, { 0.78, 0.92 }, { 0.58, 0.88 }, { 0.4, 0.8 }, { 0.24, 0.62 }, { 0.12, 0.35 } } do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(spec[1], spec[1])
		ring.BackgroundColor3 = Color3.fromRGB(170, 120, 255):Lerp(Color3.fromRGB(236, 228, 255), (i - 1) / 6)
		ring.BackgroundTransparency = spec[2]
		ring.BorderSizePixel = 0
		ring.ZIndex = i
		ring.Parent = gui
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = ring
	end
	return gui
end

-- Props and furniture come stained for the warm lobby: plain wood parts go black walnut and cardboard
-- goes dark and dusty. Textured meshes ignore Color, so they drop their map for a flat dark colour
-- (`tint`, or dark book-cloth tones in turn) in `material`. Returns the model for chaining.
local DARK_CLOTH = {
	Color3.fromRGB(72, 40, 104),
	Color3.fromRGB(40, 28, 62),
	Color3.fromRGB(58, 34, 80),
	Color3.fromRGB(30, 22, 44),
}
local function restain(model: Model?, tint: Color3?, material: Enum.Material?): Model?
	if not model then
		return nil
	end
	local k = 0
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and d.TextureID ~= "" then
			k += 1
			d.TextureID = ""
			d.Color = tint or DARK_CLOTH[(k - 1) % #DARK_CLOTH + 1]
			d.Material = material or Enum.Material.Fabric
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Wood then
			d.Color = WALNUT
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Cardboard then
			d.Color = Color3.fromRGB(58, 46, 44)
		end
	end
	return model
end

------------------------------------------------------------------------------------------
-- Storefront (foyer side)
------------------------------------------------------------------------------------------
local function buildStorefront(shop: Instance)
	local front = Kit.folder(shop, "Storefront")
	local rng = Kit.rng
	local x = FRONT_X
	local width = DOOR.z1 - DOOR.z0
	local top = DOOR.y1

	-- chunky steel portal round the opening, with chamfered inner edges (Shell lines the opening itself)
	for _, side in { -1, 1 } do
		local z = if side < 0 then DOOR.z0 - 0.55 else DOOR.z1 + 0.55
		box(
			front,
			"Jamb",
			Vector3.new(0.7, top + 1.1 - FY, 1.1),
			Vector3.new(x + 0.35, (FY + top + 1.1) / 2, z),
			STEEL,
			Enum.Material.Metal
		)
		-- chamfer strip on the jamb's inner edge
		box(
			front,
			"Chamfer",
			Vector3.new(0.5, top - FY, 0.5),
			CFrame.new(x + 0.2, (FY + top) / 2, if side < 0 then DOOR.z0 else DOOR.z1)
				* CFrame.Angles(0, math.rad(45), 0),
			STEEL:Lerp(Color3.new(1, 1, 1), 0.08),
			Enum.Material.Metal,
			DETAIL
		)
		-- kick plate
		box(
			front,
			"Kick",
			Vector3.new(0.78, 0.9, 1.18),
			Vector3.new(x + 0.37, FY + 0.45, z),
			C.rail,
			Enum.Material.DiamondPlate,
			DETAIL
		)
	end
	box(
		front,
		"Header",
		Vector3.new(0.7, 1.1, width + 2.2),
		Vector3.new(x + 0.35, top + 0.55, DOOR_ZC),
		STEEL,
		Enum.Material.Metal
	)
	box(
		front,
		"HeaderChamfer",
		Vector3.new(0.5, 0.5, width),
		CFrame.new(x + 0.2, top, DOOR_ZC) * CFrame.Angles(0, 0, math.rad(45)),
		STEEL:Lerp(Color3.new(1, 1, 1), 0.08),
		Enum.Material.Metal,
		DETAIL
	)
	box(
		front,
		"Threshold",
		Vector3.new(DOOR.x1 - DOOR.x0 + 0.6, 0.06, width),
		Vector3.new((DOOR.x0 + DOOR.x1) / 2, FY + 0.03, DOOR_ZC),
		C.rail,
		Enum.Material.DiamondPlate,
		DETAIL
	)

	-- the marquee: a black enamel box sign hung on chains in front of the header, violet trim, cold
	-- back-lit lettering, a violet neon tube that flickers now and then, and a ring of pale bulbs
	local signW, signH, signD = width + 1.6, 2.5, 0.7
	local sy = top + 0.6 + signH / 2
	local sx = x + 1.15
	local signCf = facing(Vector3.new(sx, sy, DOOR_ZC), Vector3.xAxis) -- Front face looks into the foyer
	local case = box(front, "SignCase", Vector3.new(signW, signH, signD), signCf, BLACK, Enum.Material.Metal)
	box(
		front,
		"SignRim",
		Vector3.new(signW + 0.24, signH + 0.24, signD - 0.2),
		signCf * CFrame.new(0, 0, 0.05),
		Color3.fromRGB(70, 36, 112),
		Enum.Material.Metal,
		DETAIL
	)
	local face = box(
		front,
		"SignFace",
		Vector3.new(signW - 1.1, 1.55, 0.05),
		signCf * CFrame.new(0, 0.22, -signD / 2 - 0.02),
		Color3.fromRGB(8, 6, 10),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	glowText(face, Enum.NormalId.Front, "GIFT SHOP", Enum.Font.Bodoni, SIGN_TEXT, VIOLET)
	local sub = box(
		front,
		"SignSub",
		Vector3.new(signW - 4, 0.42, 0.05),
		signCf * CFrame.new(0, -0.82, -signD / 2 - 0.02),
		Color3.fromRGB(8, 6, 10),
		nil,
		DETAIL
	)
	glowText(
		sub,
		Enum.NormalId.Front,
		"LANTERNS  ·  PILLS  ·  LOCKPICKS",
		Enum.Font.Antique,
		Color3.fromRGB(206, 190, 240),
		Color3.fromRGB(130, 80, 230),
		80
	)
	-- neon tube framing the lettering
	local neonViolet = Color3.fromRGB(160, 100, 255)
	local tw, th = signW - 0.7, signH - 0.5
	for _, spec in
		{
			{ Vector3.new(tw, 0.09, 0.09), CFrame.new(0, th / 2, 0) },
			{ Vector3.new(tw, 0.09, 0.09), CFrame.new(0, -th / 2, 0) },
			{ Vector3.new(0.09, th, 0.09), CFrame.new(-tw / 2, 0, 0) },
			{ Vector3.new(0.09, th, 0.09), CFrame.new(tw / 2, 0, 0) },
		}
	do
		local tube = box(
			front,
			"NeonTube",
			spec[1],
			signCf * CFrame.new(0, 0, -signD / 2 - 0.1) * spec[2],
			neonViolet,
			Enum.Material.Neon,
			DETAIL
		)
		tube.Transparency = 0.15
		tube:SetAttribute("NeonFlicker", true)
	end
	-- marquee bulbs along the top and bottom edges: pale violet-white, about one in five burnt out
	local bulbs = 14
	for i = 0, bulbs - 1 do
		local u = (i + 0.5) / bulbs - 0.5
		for _, v in { 1, -1 } do
			local dead = rng:NextNumber() < 0.2
			local bulb = box(
				front,
				dead and "DeadBulb" or "MarqueeBulb",
				Vector3.new(0.26, 0.26, 0.26),
				signCf * CFrame.new(u * (signW - 0.4), v * (signH / 2 - 0.02), -signD / 2 - 0.02),
				dead and Color3.fromRGB(64, 60, 72) or Color3.fromRGB(150, 130, 215),
				dead and Enum.Material.Glass or Enum.Material.Neon,
				DETAIL
			)
			bulb.Shape = Enum.PartType.Ball
			bulb.Transparency = dead and 0.1 or 0.35
		end
	end
	-- light: a dim violet wash down the front of the wall and onto the foyer floor
	local lamp = box(
		front,
		"SignLight",
		Vector3.new(0.2, 0.2, 0.2),
		signCf * CFrame.new(0, -signH / 2 - 0.2, -0.6),
		COLD,
		nil,
		INVISIBLE
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 120
	spot.Range = 16
	spot.Brightness = 1.4
	spot.Color = Color3.fromRGB(170, 130, 255)
	spot.Shadows = false
	spot.Parent = lamp
	Kit.pointLight(case, 9, 0.5, false, Color3.fromRGB(140, 80, 255))
	-- chains up to the foyer ceiling
	for _, dz in { -signW / 2 + 1, signW / 2 - 1 } do
		local cz = DOOR_ZC + dz
		box(
			front,
			"Chain",
			Vector3.new(0.08, FOYER_CEIL - (sy + signH / 2), 0.08),
			Vector3.new(sx, (FOYER_CEIL + sy + signH / 2) / 2, cz),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
		cyl(front, "ChainPlate", 0.12, 0.6, CFrame.new(sx, FOYER_CEIL - 0.06, cz), C.steel, Enum.Material.Metal, DETAIL)
	end

	-- concrete planters with ferns either side of the doorway
	for _, z in { DOOR.z0 - 2.4, DOOR.z1 + 2.4 } do
		local p = Vector3.new(x + 1.4, FY, z)
		box(
			front,
			"Planter",
			Vector3.new(2.4, 2, 2.4),
			p + Vector3.new(0, 1, 0),
			Color3.fromRGB(150, 150, 146),
			Enum.Material.Concrete
		)
		box(
			front,
			"Soil",
			Vector3.new(2.1, 0.1, 2.1),
			p + Vector3.new(0, 1.92, 0),
			Color3.fromRGB(46, 34, 26),
			Enum.Material.Ground,
			DETAIL
		)
		if not Kit.prop(front, "Fern", CFrame.new(p + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, z, 0), 1.1) then
			box(
				front,
				"Shrub",
				Vector3.new(1.8, 2.6, 1.8),
				p + Vector3.new(0, 3.2, 0),
				Color3.fromRGB(52, 86, 48),
				Enum.Material.Grass,
				DETAIL
			)
		end
	end

	-- chalk A-board on the foyer floor: the lobby's board, his chalk
	local boardBase = CFrame.new(x + 4, FY, DOOR.z0 - 3.2) * CFrame.Angles(0, math.rad(-62), 0)
	for _, side in { 1, -1 } do
		local lean = boardBase * CFrame.new(0, 0, side * 0.78) * CFrame.Angles(side * math.rad(-14), 0, 0)
		local panel = lean * CFrame.new(0, 1.55, 0)
		box(front, "BoardFrame", Vector3.new(2.2, 3.2, 0.14), panel, C.midWood, Enum.Material.Wood)
		local slate = box(
			front,
			"Slate",
			Vector3.new(1.85, 2.7, 0.04),
			panel * CFrame.new(0, 0.05, side * 0.08),
			C.chalkboard,
			Enum.Material.Slate,
			DETAIL
		)
		printText(slate, if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front, {
			{ "NEW MANAGEMENT", Enum.Font.PermanentMarker, Color3.fromRGB(226, 220, 236), 0.05, 0.21 },
			{ "he doesn't blink", Enum.Font.Kalam, Color3.fromRGB(196, 150, 255), 0.24, 0.38 },
			{ "LANTERNS · PILLS", Enum.Font.Kalam, Color3.fromRGB(200, 212, 230), 0.47, 0.59 },
			{ "LOCKPICKS", Enum.Font.Kalam, Color3.fromRGB(200, 212, 230), 0.59, 0.71 },
			{ "-> ask Teeth", Enum.Font.Kalam, Color3.fromRGB(226, 220, 236), 0.8, 0.93 },
		})
	end
	box(
		front,
		"BoardHinge",
		Vector3.new(2.2, 0.16, 0.5),
		boardBase * CFrame.new(0, 3.12, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
end

------------------------------------------------------------------------------------------
-- Wallpaper, wainscot, floor and ceiling: the dark skin over the grey shell
------------------------------------------------------------------------------------------
-- Inner faces of the shop's four walls, with the direction into the room and the room-facing NormalId.
local SIDES = {
	W = { axis = "x", at = R.x0, n = 1, face = Enum.NormalId.Right },
	E = { axis = "x", at = R.x1, n = -1, face = Enum.NormalId.Left },
	S = { axis = "z", at = R.z0, n = 1, face = Enum.NormalId.Back },
	N = { axis = "z", at = R.z1, n = -1, face = Enum.NormalId.Front },
}

-- A board `thick` deep whose back sits `off` studs off the wall face, spanning [a0, a1] along the wall
-- and [y0, y1] up it. Returns the part and the NormalId of its room-facing side.
local function wallBoard(
	parent: Instance,
	name: string,
	side: string,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	off: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
)
	local s = SIDES[side]
	local mid, len = (a0 + a1) / 2, a1 - a0
	local c = s.at + s.n * (off + thick / 2)
	local size, pos
	if s.axis == "x" then
		size, pos = Vector3.new(thick, y1 - y0, len), Vector3.new(c, (y0 + y1) / 2, mid)
	else
		size, pos = Vector3.new(len, y1 - y0, thick), Vector3.new(mid, (y0 + y1) / 2, c)
	end
	return box(parent, name, size, pos, color, material, DETAIL), s.face
end

local function buildSkin(shop: Instance)
	local skin = Kit.folder(shop, "Skin")
	local topY = CEIL - 1.3 -- the cornice cover takes over above this
	local railY = FY + 3.86 -- underside of Shell's dado rail

	-- damask panel 0.07..0.17 off the wall (over Shell's panel seams, under its wainscot lip)
	local function paper(side: string, a0: number, a1: number, y0: number, y1: number)
		local p, face = wallBoard(skin, "Damask", side, a0, a1, y0, y1, 0.07, 0.1, WALLPAPER_BASE, Enum.Material.Fabric)
		local tex = Instance.new("Texture")
		tex.Face = face
		tex.Texture = WALLPAPER
		tex.StudsPerTileU = WALLPAPER_TILE
		tex.StudsPerTileV = WALLPAPER_TILE
		tex.Color3 = WALLPAPER_TINT
		tex.Parent = p
		return p
	end
	-- ebony wainscot proud of Shell's concrete one, under its rail; black skirting board on the tiles.
	-- The foyer-side wall has no Shell finishes on this side, so it gets its own rail.
	local function dado(side: string, a0: number, a1: number, ownRail: boolean)
		wallBoard(skin, "Dado", side, a0, a1, FY + 0.62, railY, 0.18, 0.1, EBONY, Enum.Material.Wood)
		wallBoard(skin, "Skirting", side, a0, a1, FY, FY + 0.62, 0.3, 0.1, BLACK, Enum.Material.SmoothPlastic)
		if ownRail then
			wallBoard(skin, "Rail", side, a0, a1, railY, railY + 0.26, 0, 0.3, C.rail, Enum.Material.Metal)
		end
	end
	paper("W", R.z0, R.z1, FY + 4.2, topY)
	dado("W", R.z0, R.z1, false)
	for _, side in { "N", "S" } do
		paper(side, R.x0 + WALL_OUT, R.x1 - WALL_OUT, FY + 4.2, topY)
		dado(side, R.x0 + 0.28, R.x1 - 0.28, false)
	end
	-- the shared wall, either side of the doorway reveal and over it
	for _, seg in { { R.z0, DOOR.z0 - 0.15 }, { DOOR.z1 + 0.15, R.z1 } } do
		paper("E", seg[1], seg[2], FY + 4.2, topY)
		dado("E", seg[1], seg[2], true)
	end
	paper("E", DOOR.z0 - 0.15, DOOR.z1 + 0.15, DOOR.y1, topY)

	-- black ceiling under the grey slab, inset for the cornice; the cornice and Shell's downstand beam
	-- (with its angled haunches) are boxed in black the same way
	local cx, cz = (R.x0 + R.x1) / 2, (R.z0 + R.z1) / 2
	box(
		skin,
		"Ceiling",
		Vector3.new(R.x1 - R.x0 - 2.6, 0.1, R.z1 - R.z0 - 2.6),
		Vector3.new(cx, CEIL - 0.06, cz),
		SOOT,
		Enum.Material.Plaster,
		DETAIL
	)
	local k = 2.0 -- Shell's cornice is a 1.8 square rolled 45 degrees; this one wraps it
	for _, s in { -1, 1 } do
		local z = s < 0 and R.z0 or R.z1
		local x = s < 0 and R.x0 or R.x1
		box(
			skin,
			"Cornice",
			Vector3.new(R.x1 - R.x0, k, k),
			CFrame.new(cx, CEIL, z) * CFrame.Angles(math.rad(45), 0, 0),
			SOOT,
			Enum.Material.Plaster,
			DETAIL
		)
		box(
			skin,
			"Cornice",
			Vector3.new(k, k, R.z1 - R.z0),
			CFrame.new(x, CEIL, cz) * CFrame.Angles(0, 0, math.rad(45)),
			SOOT,
			Enum.Material.Plaster,
			DETAIL
		)
	end
	-- Shell spaces its beams (spanning Z here) evenly across X, one per 14 studs
	local beams = math.max(1, math.floor((R.x1 - R.x0) / 14))
	for i = 1, beams do
		local p = R.x0 + (R.x1 - R.x0) * i / (beams + 1)
		local depth, width = 1.5, 2.4
		local cf = CFrame.new(p, CEIL - depth / 2, cz) * CFrame.Angles(0, math.rad(90), 0)
		box(skin, "Beam", Vector3.new(R.z1 - R.z0, depth, width), cf, SOOT, Enum.Material.Plaster, DETAIL)
		for _, s in { -1, 1 } do
			box(
				skin,
				"BeamHaunch",
				Vector3.new(R.z1 - R.z0, 1.1, 1.1),
				cf * CFrame.new(0, depth / 2, s * width / 2) * CFrame.Angles(math.rad(45), 0, 0),
				SOOT,
				Enum.Material.Plaster,
				DETAIL
			)
		end
	end

	-- black marble floor: a near-black bed with big tiles on it, walkable
	box(
		skin,
		"Grout",
		Vector3.new(R.x1 - R.x0, 0.012, R.z1 - R.z0),
		Vector3.new(cx, FY + 0.05, cz),
		Color3.fromRGB(10, 8, 12),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	local n = 6
	local tx, tz = (R.x1 - R.x0) / n, (R.z1 - R.z0) / n
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			box(
				skin,
				"Tile",
				Vector3.new(tx - 0.08, 0.05, tz - 0.08),
				Vector3.new(R.x0 + (ix + 0.5) * tx, FY + FLOOR_RAISE - 0.025, R.z0 + (iz + 0.5) * tz),
				(ix + iz) % 2 == 0 and TILE_A or TILE_B,
				Enum.Material.Marble,
				{ CastShadow = false, CanTouch = false }
			)
		end
	end
	return skin
end

------------------------------------------------------------------------------------------
-- Checkout counter
------------------------------------------------------------------------------------------
local COUNTER = { x = -20.8, z0 = 47.5, z1 = 58.5, depth = 2.6, h = 3.5 }

local function buildTill(parent: Instance, base: CFrame)
	-- antique cash register in black enamel with tarnished trim; `base` sits on the counter top, keys
	-- toward base's -Z
	local till = Kit.folder(parent, "Till")
	local enamel = Color3.fromRGB(20, 16, 20)
	box(till, "Drawer", Vector3.new(1.7, 0.5, 1.5), base * CFrame.new(0, 0.25, 0), EBONY, Enum.Material.Wood, DETAIL)
	box(till, "Body", Vector3.new(1.5, 0.8, 1.1), base * CFrame.new(0, 0.9, 0.15), enamel, Enum.Material.Metal, DETAIL)
	box(
		till,
		"KeyBed",
		Vector3.new(1.5, 0.3, 0.7),
		base * CFrame.new(0, 0.65, -0.55) * CFrame.Angles(math.rad(-20), 0, 0),
		enamel,
		Enum.Material.Metal,
		DETAIL
	)
	for row = 0, 1 do
		for col = 0, 3 do
			cyl(
				till,
				"Key",
				0.14,
				0.17,
				base
					* CFrame.new(-0.5 + col * 0.33, 0.85 - row * 0.12, -0.42 - row * 0.28)
					* CFrame.Angles(math.rad(-20), 0, 0),
				BONE,
				Enum.Material.SmoothPlastic,
				DETAIL
			)
		end
	end
	local flag = box(till, "Flag", Vector3.new(1.1, 0.45, 0.12), base * CFrame.new(0, 1.55, 0.2), CARD, nil, DETAIL)
	printText(flag, Enum.NormalId.Back, { { "NO REFUNDS", Enum.Font.Bodoni, CARD_TEXT, 0.1, 0.9 } }, nil, 120)
	box(
		till,
		"FlagHousing",
		Vector3.new(1.25, 0.12, 0.3),
		base * CFrame.new(0, 1.32, 0.2),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	cyl(
		till,
		"Crank",
		0.5,
		0.12,
		base * CFrame.new(0.85, 0.95, 0.2) * CFrame.Angles(0, 0, math.rad(90)),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		till,
		"CrankHandle",
		Vector3.new(0.12, 0.12, 0.45),
		base * CFrame.new(1.1, 0.95, 0.4),
		EBONY,
		Enum.Material.Wood,
		DETAIL
	)
	return till
end

-- Banker's lamp on the counter, cold: the mesh prop re-stained (tarnished brass, violet glass) with a
-- lilac glow strip under the shade; boxes if the prop is missing.
local function coldDeskLamp(parent: Instance, pos: Vector3)
	local yaw = CFrame.Angles(0, Kit.rng:NextNumber(-0.6, 0.6), 0)
	local lamp = Kit.prop(parent, "BankerLamp", CFrame.new(pos) * yaw, 1)
	local glowCf
	if lamp then
		for _, d in lamp:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Material == Enum.Material.Metal then
					d.Color = BRASS
				elseif d.Material == Enum.Material.Glass then
					d.Color = Color3.fromRGB(40, 20, 70)
				elseif d.Material == Enum.Material.Neon then
					d.Color = COLD_NEON
				end
			end
		end
		glowCf = CFrame.new(pos) * yaw * CFrame.new(0, 1.0, 0)
	else
		lamp = Kit.folder(parent, "BankerLamp")
		box(
			lamp,
			"LampBase",
			Vector3.new(0.7, 0.12, 0.45),
			pos + Vector3.new(0, 0.06, 0),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			lamp,
			"LampStem",
			Vector3.new(0.1, 0.95, 0.1),
			pos + Vector3.new(0, 0.55, 0),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
		box(
			lamp,
			"LampShade",
			Vector3.new(1.1, 0.3, 0.45),
			CFrame.new(pos + Vector3.new(0, 1.1, 0)) * yaw,
			Color3.fromRGB(40, 20, 70),
			Enum.Material.Glass,
			DETAIL
		)
		glowCf = CFrame.new(pos) * yaw * CFrame.new(0, 0.93, 0)
	end
	local glow = box(lamp, "Glow", Vector3.new(0.75, 0.05, 0.22), glowCf, COLD_NEON, Enum.Material.Neon, DETAIL)
	glow.Transparency = 0.25
	coldHalo(glow, 1.4)
	Kit.pointLight(glow, 8, 0.7, false, COLD)
	return lamp
end

local function buildCounter(shop: Instance)
	local counter = Kit.folder(shop, "Counter")
	local cx, d = COUNTER.x, COUNTER.depth
	local len = COUNTER.z1 - COUNTER.z0
	local cz = (COUNTER.z0 + COUNTER.z1) / 2
	local topY = SF + COUNTER.h
	local frontX = cx + d / 2 -- customer side faces +X

	box(
		counter,
		"Plinth",
		Vector3.new(d - 0.3, 0.35, len - 0.3),
		Vector3.new(cx - 0.1, SF + 0.175, cz),
		BLACK,
		Enum.Material.Wood
	)
	box(
		counter,
		"Body",
		Vector3.new(d - 0.2, COUNTER.h - 0.6, len - 0.2),
		Vector3.new(cx - 0.05, SF + 0.35 + (COUNTER.h - 0.6) / 2, cz),
		EBONY,
		Enum.Material.Wood
	)
	box(
		counter,
		"Top",
		Vector3.new(d + 0.3, 0.26, len + 0.4),
		Vector3.new(cx, topY - 0.13, cz),
		WALNUT,
		Enum.Material.Wood
	)
	box(
		counter,
		"TopEdge",
		Vector3.new(0.12, 0.12, len + 0.4),
		Vector3.new(cx + d / 2 + 0.19, topY - 0.3, cz),
		GOLD,
		Enum.Material.Metal,
		DETAIL
	)
	-- raised panels on the customer face, separated by fluted pilasters
	local panels = 4
	local pw = (len - 0.2) / panels
	for i = 0, panels - 1 do
		local z = COUNTER.z0 + 0.1 + (i + 0.5) * pw
		box(
			counter,
			"Panel",
			Vector3.new(0.1, COUNTER.h - 1.4, pw - 0.7),
			Vector3.new(frontX, SF + 0.35 + (COUNTER.h - 0.6) / 2, z),
			WALNUT_LIGHT,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			counter,
			"PanelInset",
			Vector3.new(0.06, COUNTER.h - 2.0, pw - 1.3),
			Vector3.new(frontX + 0.06, SF + 0.35 + (COUNTER.h - 0.6) / 2, z),
			WALNUT,
			Enum.Material.Wood,
			DETAIL
		)
	end
	for i = 0, panels do
		local z = COUNTER.z0 + 0.1 + i * pw
		box(
			counter,
			"Pilaster",
			Vector3.new(0.18, COUNTER.h - 0.6, 0.3),
			Vector3.new(frontX + 0.02, SF + 0.35 + (COUNTER.h - 0.6) / 2, z),
			BLACK,
			Enum.Material.Wood,
			DETAIL
		)
	end
	-- foot rail on little brackets
	box(
		counter,
		"FootRail",
		Vector3.new(0.14, 0.14, len - 0.6),
		Vector3.new(frontX + 0.55, SF + 0.55, cz),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	for _, z in { COUNTER.z0 + 0.6, cz, COUNTER.z1 - 0.6 } do
		box(
			counter,
			"RailBracket",
			Vector3.new(0.6, 0.1, 0.1),
			Vector3.new(frontX + 0.27, SF + 0.55, z),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
	end
	-- name plate
	local plate = box(
		counter,
		"Plate",
		Vector3.new(0.06, 0.5, 2.6),
		Vector3.new(frontX + 0.13, topY - 0.75, cz),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	printText(
		plate,
		Enum.NormalId.Right,
		{ { "CHECKOUT", Enum.Font.Bodoni, Color3.fromRGB(24, 16, 12), 0.1, 0.9 } },
		nil,
		80
	)
	-- magenta underglow tucked under the body's lip, spilling across the tiles at the customers' feet
	local glow = box(
		counter,
		"BaseGlow",
		Vector3.new(0.08, 0.06, len - 0.5),
		Vector3.new(cx + 1.2, SF + 0.3, cz),
		MAGENTA,
		Enum.Material.Neon,
		DETAIL
	)
	glow.Transparency = 0.2
	local under = Instance.new("SurfaceLight")
	under.Face = Enum.NormalId.Right
	under.Angle = 140
	under.Range = 7
	under.Brightness = 0.8
	under.Color = MAGENTA
	under.Shadows = false
	under.Parent = glow

	-- on top: till (keys toward him), bell, open ledger, lamp, parcels, a tent card
	buildTill(counter, facing(Vector3.new(cx - 0.2, topY, COUNTER.z0 + 1.6), -Vector3.xAxis))
	local bellPos = Vector3.new(cx + 0.75, topY, cz + 0.4)
	cyl(
		counter,
		"BellBase",
		0.1,
		0.62,
		CFrame.new(bellPos + Vector3.new(0, 0.05, 0)),
		EBONY,
		Enum.Material.Wood,
		DETAIL
	)
	local dome = box(
		counter,
		"Bell",
		Vector3.new(0.48, 0.48, 0.48),
		bellPos + Vector3.new(0, 0.12, 0),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	dome.Shape = Enum.PartType.Ball
	cyl(
		counter,
		"BellPlunger",
		0.14,
		0.07,
		CFrame.new(bellPos + Vector3.new(0, 0.42, 0)),
		C.steel,
		Enum.Material.Metal,
		DETAIL
	)
	local card = box(
		counter,
		"TentCard",
		Vector3.new(0.05, 0.5, 0.9),
		CFrame.new(bellPos + Vector3.new(0.1, 0.24, 0.9)) * CFrame.Angles(0, 0, math.rad(-12)),
		CARD,
		nil,
		DETAIL
	)
	printText(card, Enum.NormalId.Right, {
		{ "RING ONCE", Enum.Font.Bodoni, CARD_TEXT, 0.1, 0.5 },
		{ "he will hear you", Enum.Font.Garamond, CARD_ACCENT, 0.52, 0.86 },
	}, nil, 120)
	box(counter, "CardFoot", Vector3.new(0.2, 0.04, 0.9), bellPos + Vector3.new(0.05, 0.02, 0.9), CARD, nil, DETAIL)
	-- open ledger, pages tipped up a little either side of the spine
	local ledger = Vector3.new(cx - 0.1, topY, cz + 2.4)
	box(
		counter,
		"LedgerCover",
		Vector3.new(1.3, 0.06, 1.9),
		ledger + Vector3.new(0, 0.03, 0),
		Color3.fromRGB(40, 14, 50),
		Enum.Material.Fabric,
		DETAIL
	)
	for _, s in { -1, 1 } do
		box(
			counter,
			"LedgerPages",
			Vector3.new(1.18, 0.1, 0.9),
			CFrame.new(ledger + Vector3.new(0, 0.12, s * 0.46)) * CFrame.Angles(s * math.rad(4), 0, 0),
			Color3.fromRGB(150, 140, 160),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
	box(
		counter,
		"Pen",
		Vector3.new(0.05, 0.05, 0.8),
		CFrame.new(ledger + Vector3.new(0.3, 0.2, 0.4)) * CFrame.Angles(0, math.rad(30), 0),
		Color3.fromRGB(20, 20, 24),
		nil,
		DETAIL
	)
	coldDeskLamp(counter, Vector3.new(cx - 0.6, topY, COUNTER.z1 - 0.9))
	-- black-paper parcels tied with violet string, ready for collection
	for i, spec in { { 1.2, 0.6, 1.0 }, { 0.9, 0.45, 0.8 } } do
		local y = topY + (i == 1 and 0.3 or 0.6 + 0.225)
		local cf = CFrame.new(cx + 0.3, y, COUNTER.z1 - 2.3) * CFrame.Angles(0, math.rad(i * 9), 0)
		box(
			counter,
			"Parcel",
			Vector3.new(spec[1], spec[2], spec[3]),
			cf,
			Color3.fromRGB(46, 38, 46),
			Enum.Material.Cardboard,
			DETAIL
		)
		box(
			counter,
			"Twine",
			Vector3.new(spec[1] + 0.02, spec[2] + 0.02, 0.05),
			cf,
			Color3.fromRGB(120, 90, 160),
			Enum.Material.Fabric,
			DETAIL
		)
		box(
			counter,
			"Twine",
			Vector3.new(0.05, spec[2] + 0.02, spec[3] + 0.02),
			cf,
			Color3.fromRGB(120, 90, 160),
			Enum.Material.Fabric,
			DETAIL
		)
	end

	-- no prompt on the counter: you talk to Teeth, and his "Show me." opens the shop

	-- nothing stands behind the counter: that's where he is (Layout.Shopkeeper)
	-- dust hanging in the cold light over the counter
	Kit.anchor(counter, "LampDust", CFrame.new(cx, SF + 7, cz), Vector3.new(5, 5, 9), { Color = COLD })
	return counter
end

------------------------------------------------------------------------------------------
-- Lantern wall: velvet cubbies behind the counter, one lantern each, lit cold from above
------------------------------------------------------------------------------------------
local function buildLanternWall(shop: Instance)
	local wall = Kit.folder(shop, "LanternWall")
	local x0 = R.x0
	local depth = 1.8
	local fx = x0 + depth -- front plane
	local zc = DOOR_ZC
	local count = #Lanterns.List
	local divider, cubbyW = 0.25, 2.3
	local width = count * cubbyW + (count + 1) * divider
	local baseH, cubbyH = 3.2, 3.8
	local cubbyY = SF + baseH + 0.2

	-- base cabinet with doors
	box(
		wall,
		"Base",
		Vector3.new(depth, baseH, width),
		Vector3.new(x0 + depth / 2, SF + baseH / 2, zc),
		EBONY,
		Enum.Material.Wood
	)
	for i = 0, 3 do
		local z = zc - width / 2 + (i + 0.5) * width / 4
		box(
			wall,
			"Door",
			Vector3.new(0.1, baseH - 0.7, width / 4 - 0.25),
			Vector3.new(fx + 0.05, SF + baseH / 2 + 0.1, z),
			WALNUT,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			wall,
			"Knob",
			Vector3.new(0.14, 0.14, 0.14),
			Vector3.new(fx + 0.15, SF + baseH / 2 + 0.3, z + (i % 2 == 0 and 1 or -1) * (width / 8 - 0.4)),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
	end
	box(
		wall,
		"Ledge",
		Vector3.new(depth + 0.35, 0.2, width + 0.3),
		Vector3.new(x0 + (depth + 0.35) / 2, SF + baseH + 0.1, zc),
		WALNUT,
		Enum.Material.Wood
	)

	-- cubbies (the velvet back sits on the wallpaper panel, not the shell wall)
	box(
		wall,
		"Velvet",
		Vector3.new(0.15, cubbyH, width),
		Vector3.new(x0 + WALL_OUT + 0.075, cubbyY + cubbyH / 2, zc),
		VELVET,
		Enum.Material.Fabric
	)
	for i = 0, count do
		local z = zc - width / 2 + divider / 2 + i * (cubbyW + divider)
		box(
			wall,
			"Divider",
			Vector3.new(depth, cubbyH, divider),
			Vector3.new(x0 + depth / 2, cubbyY + cubbyH / 2, z),
			EBONY,
			Enum.Material.Wood
		)
	end
	box(
		wall,
		"CubbyTop",
		Vector3.new(depth + 0.2, 0.3, width + 0.2),
		Vector3.new(x0 + (depth + 0.2) / 2, cubbyY + cubbyH + 0.15, zc),
		EBONY,
		Enum.Material.Wood
	)
	box(
		wall,
		"Crown",
		Vector3.new(depth + 0.6, 0.35, width + 0.8),
		Vector3.new(x0 + (depth + 0.6) / 2, cubbyY + cubbyH + 0.475, zc),
		WALNUT,
		Enum.Material.Wood
	)
	box(
		wall,
		"Glass",
		Vector3.new(0.06, cubbyH, width - 0.1),
		Vector3.new(fx - 0.02, cubbyY + cubbyH / 2, zc),
		Color3.fromRGB(200, 220, 225),
		Enum.Material.Glass,
		GLASS
	)

	for i, def in Lanterns.List do
		local z = zc - width / 2 + divider + (i - 0.5) * cubbyW + (i - 1) * divider
		-- cold strip light hidden under the cubby top; the lantern's own flame stays warm
		local strip = box(
			wall,
			"Strip",
			Vector3.new(0.12, 0.05, cubbyW - 0.4),
			Vector3.new(fx - 0.35, cubbyY + cubbyH - 0.05, z),
			COLD_NEON,
			Enum.Material.Neon,
			DETAIL
		)
		strip.Transparency = 0.25
		-- velvet riser, lantern on it
		box(
			wall,
			"Riser",
			Vector3.new(1.3, 0.35, 1.3),
			Vector3.new(x0 + 0.95, cubbyY + 0.175, z),
			VELVET_DARK,
			Enum.Material.Fabric,
			DETAIL
		)
		local lantern = LanternBuilder.buildModel(def.id, true)
		lantern:PivotTo(CFrame.new(x0 + 0.95, cubbyY + 0.35, z) * CFrame.Angles(0, math.rad(90), 0))
		local light = lantern:FindFirstChild("Light", true)
		if light then
			light.Brightness *= 0.4
			light.Range = 6
			light.Shadows = false
		end
		lantern.Parent = wall
		-- price tag on the ledge lip
		local tag = box(
			wall,
			"PriceTag",
			Vector3.new(0.04, 0.5, 1.7),
			Vector3.new(x0 + depth + 0.37, SF + baseH + 0.02, z),
			CARD,
			nil,
			DETAIL
		)
		printText(tag, Enum.NormalId.Right, {
			{ string.upper(def.name), Enum.Font.Bodoni, CARD_TEXT, 0.06, 0.5 },
			{
				if def.price > 0 then def.price .. " KEYS" else "ON THE HOUSE",
				Enum.Font.Garamond,
				CARD_ACCENT,
				0.52,
				0.94,
			},
		}, nil, 160)
	end

	-- gilt "LANTERNS" board above, with a picture light, all hung on the wallpaper
	local wx = x0 + WALL_OUT
	local boardY = cubbyY + cubbyH + 1.2
	local board =
		box(wall, "Board", Vector3.new(0.15, 1.1, 6.4), Vector3.new(wx + 0.075, boardY, zc), BLACK, Enum.Material.Wood)
	printText(board, Enum.NormalId.Right, { { "LANTERNS", Enum.Font.Bodoni, GOLD, 0.08, 0.92 } }, nil, 60)
	box(
		wall,
		"PictureLightArm",
		Vector3.new(0.7, 0.08, 0.08),
		Vector3.new(wx + 0.35, boardY + 0.9, zc),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	local hood = box(
		wall,
		"PictureLight",
		Vector3.new(0.3, 0.2, 3.4),
		Vector3.new(wx + 0.75, boardY + 0.9, zc),
		BRASS,
		Enum.Material.Metal,
		DETAIL
	)
	local tube = box(
		wall,
		"PictureTube",
		Vector3.new(0.08, 0.05, 3.2),
		Vector3.new(wx + 0.75, boardY + 0.78, zc),
		COLD_NEON,
		Enum.Material.Neon,
		DETAIL
	)
	tube.Transparency = 0.3
	local wash = Instance.new("SpotLight")
	wash.Face = Enum.NormalId.Bottom
	wash.Angle = 120
	wash.Range = 5
	wash.Brightness = 1.0
	wash.Color = COLD
	wash.Parent = hood

	-- wall clock above it all (ticking via the Clock sound marker)
	local clockPos = Vector3.new(wx + 0.1, boardY + 2.0, zc)
	local clockCf = facing(clockPos, Vector3.xAxis)
	cyl(wall, "ClockRim", 0.2, 2.1, clockCf * CFrame.Angles(math.rad(90), 0, 0), EBONY, Enum.Material.Wood)
	local dial = cyl(
		wall,
		"ClockFace",
		0.22,
		1.8,
		clockCf * CFrame.new(0, 0, -0.02) * CFrame.Angles(math.rad(90), 0, 0),
		Color3.fromRGB(46, 36, 58),
		nil,
		DETAIL
	)
	dial.CastShadow = false
	box(
		wall,
		"HourHand",
		Vector3.new(0.08, 0.5, 0.03),
		clockCf * CFrame.new(0, 0, -0.15) * CFrame.Angles(0, 0, math.rad(-60)) * CFrame.new(0, 0.22, 0),
		BONE,
		nil,
		DETAIL
	)
	box(
		wall,
		"MinuteHand",
		Vector3.new(0.06, 0.75, 0.03),
		clockCf * CFrame.new(0, 0, -0.16) * CFrame.Angles(0, 0, math.rad(20)) * CFrame.new(0, 0.34, 0),
		BONE,
		nil,
		DETAIL
	)
	Kit.anchor(wall, "Clock", clockPos)
	return wall
end

------------------------------------------------------------------------------------------
-- Around the walls
------------------------------------------------------------------------------------------
local function buildCatalogue(shop: Instance, cf: CFrame)
	-- card catalogue cabinet; `cf` on the floor, drawers face cf's -Z
	local cab = Kit.folder(shop, "CardCatalogue")
	local w, h, d = 3.6, 4.6, 2.2
	box(cab, "Body", Vector3.new(w, h - 0.6, d), cf * CFrame.new(0, 0.6 + (h - 0.6) / 2, 0), WALNUT, Enum.Material.Wood)
	box(cab, "TopBoard", Vector3.new(w + 0.3, 0.2, d + 0.2), cf * CFrame.new(0, h + 0.1, 0), EBONY, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				cab,
				"Leg",
				Vector3.new(0.3, 0.6, 0.3),
				cf * CFrame.new(sx * (w / 2 - 0.25), 0.3, sz * (d / 2 - 0.25)),
				EBONY,
				Enum.Material.Wood
			)
		end
	end
	local rows, cols = 6, 3
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local px = (col - (cols - 1) / 2) * (w - 0.3) / cols
			local py = 0.95 + row * 0.62
			box(
				cab,
				"Drawer",
				Vector3.new((w - 0.3) / cols - 0.1, 0.52, 0.1),
				cf * CFrame.new(px, py, -d / 2 - 0.05),
				WALNUT_LIGHT,
				Enum.Material.Wood,
				DETAIL
			)
			box(
				cab,
				"Label",
				Vector3.new(0.4, 0.14, 0.04),
				cf * CFrame.new(px, py + 0.1, -d / 2 - 0.11),
				CARD_TEXT,
				nil,
				DETAIL
			)
		end
	end
	return cab
end

local function buildBooksForSale(shop: Instance)
	local books = Kit.folder(shop, "BooksForSale")
	-- tall shelves along the north wall (books face -Z, into the room)
	local z = R.z1 - 0.9
	for _, x in { -22.6, -16.3 } do
		if not restain(Kit.prop(books, "Bookshelf", CFrame.new(x, SF, z))) then
			restain(Furniture.bookcase(books, CFrame.new(x, SF, z) * CFrame.Angles(0, math.pi, 0), 5.6, 11, 1.6, false))
		end
	end
	-- picks table in front
	local t = CFrame.new(-18.6, SF, 61.9)
	local topY = 2.7
	box(books, "TableTop", Vector3.new(5, 0.25, 2.4), t * CFrame.new(0, topY - 0.125, 0), WALNUT, Enum.Material.Wood)
	box(
		books,
		"TableApron",
		Vector3.new(4.6, 0.4, 2.0),
		t * CFrame.new(0, topY - 0.45, 0),
		EBONY,
		Enum.Material.Wood,
		DETAIL
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				books,
				"Leg",
				Vector3.new(0.3, topY - 0.25, 0.3),
				t * CFrame.new(sx * 2.2, (topY - 0.25) / 2, sz * 0.95),
				EBONY,
				Enum.Material.Wood
			)
		end
	end
	local rng = Kit.rng
	-- books standing up on little easels, faced toward the walkway (-Z)
	for i = 0, 3 do
		local bx = -1.8 + i * 1.2
		local cf = t * CFrame.new(bx, topY, 0.3) * CFrame.Angles(math.rad(-12), 0, 0)
		box(
			books,
			"Easel",
			Vector3.new(0.3, 0.6, 0.4),
			t * CFrame.new(bx, topY + 0.3, 0.55),
			EBONY,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			books,
			"PickBook",
			Vector3.new(0.9, 1.25, 0.18),
			cf * CFrame.new(0, 0.625, 0),
			Kit.BOOK_COLORS[rng:NextInteger(1, #Kit.BOOK_COLORS)],
			Enum.Material.Fabric,
			DETAIL
		)
	end
	for _, bx in { -1.2, 1.4 } do
		Furniture.bookPile(books, (t * CFrame.new(bx, topY, -0.6)).Position, 3)
	end
	local tent = box(
		books,
		"TentCard",
		Vector3.new(1.6, 0.6, 0.05),
		t * CFrame.new(0, topY + 0.3, -0.95) * CFrame.Angles(math.rad(12), 0, 0),
		CARD,
		nil,
		DETAIL
	)
	printText(tent, Enum.NormalId.Front, {
		{ "HIS PICKS", Enum.Font.Bodoni, CARD_ACCENT, 0.08, 0.58 },
		{ "he has read you", Enum.Font.Garamond, CARD_TEXT, 0.6, 0.92 },
	}, nil, 100)
	return books
end

local function buildPostcards(shop: Instance, pos: Vector3)
	-- spinning wire postcard rack, black
	local rack = Kit.folder(shop, "PostcardRack")
	local rng = Kit.rng
	local iron = Color3.fromRGB(24, 22, 28)
	cyl(rack, "Base", 0.15, 1.8, CFrame.new(pos + Vector3.new(0, 0.075, 0)), iron, Enum.Material.Metal)
	box(rack, "Pole", Vector3.new(0.14, 5.6, 0.14), pos + Vector3.new(0, 2.95, 0), iron, Enum.Material.Metal)
	local cardColors = {
		Color3.fromRGB(60, 40, 90),
		Color3.fromRGB(40, 50, 72),
		Color3.fromRGB(92, 60, 124),
		Color3.fromRGB(30, 24, 40),
		Color3.fromRGB(124, 104, 150),
		Color3.fromRGB(52, 30, 62),
	}
	for tier = 0, 2 do
		local y = 1.5 + tier * 1.45
		local spin = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(20 + tier * 15), 0)
		for side = 0, 3 do
			local face = spin * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -0.42)
			box(
				rack,
				"Wire",
				Vector3.new(1.3, 1.25, 0.06),
				face,
				iron,
				Enum.Material.Metal,
				{ Transparency = 0.55, CanCollide = false, CastShadow = false }
			)
			for k = -1, 1, 2 do
				local cardCf = face * CFrame.new(k * 0.33, 0.06, -0.07) * CFrame.Angles(math.rad(-6), 0, 0)
				box(
					rack,
					"Postcard",
					Vector3.new(0.58, 0.82, 0.03),
					cardCf,
					cardColors[rng:NextInteger(1, #cardColors)],
					nil,
					DETAIL
				)
				box(
					rack,
					"Picture",
					Vector3.new(0.46, 0.4, 0.02),
					cardCf * CFrame.new(0, 0.12, -0.02),
					cardColors[rng:NextInteger(1, #cardColors)],
					nil,
					DETAIL
				)
			end
		end
	end
	local topper = box(rack, "Topper", Vector3.new(1.4, 0.45, 0.05), pos + Vector3.new(0, 5.95, 0), CARD, nil, DETAIL)
	topper.CFrame = facing(topper.Position, Vector3.new(1, 0, -0.6).Unit)
	printText(topper, Enum.NormalId.Front, { { "POSTCARDS", Enum.Font.Bodoni, CARD_TEXT, 0.1, 0.9 } }, nil, 80)
	printText(topper, Enum.NormalId.Back, { { "POSTCARDS", Enum.Font.Bodoni, CARD_TEXT, 0.1, 0.9 } }, nil, 80)
	return rack
end

local function buildVitrine(shop: Instance, cf: CFrame, length: number)
	-- curio cabinet: ebony base, brass-framed glass case on top, lit cold from inside. Front faces cf's -Z.
	local case = Kit.folder(shop, "CurioCase")
	local d, baseH, glassH = 2.0, 2.9, 1.5
	box(case, "Base", Vector3.new(length, baseH, d), cf * CFrame.new(0, baseH / 2, 0), EBONY, Enum.Material.Wood)
	box(
		case,
		"Plinth",
		Vector3.new(length + 0.2, 0.3, d + 0.2),
		cf * CFrame.new(0, 0.15, 0),
		BLACK,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		case,
		"Bed",
		Vector3.new(length - 0.2, 0.08, d - 0.2),
		cf * CFrame.new(0, baseH + 0.04, 0),
		VELVET_DARK,
		Enum.Material.Fabric,
		DETAIL
	)
	box(
		case,
		"GlassBox",
		Vector3.new(length - 0.1, glassH, d - 0.1),
		cf * CFrame.new(0, baseH + glassH / 2, 0),
		Color3.fromRGB(200, 220, 225),
		Enum.Material.Glass,
		GLASS
	)
	-- brass edges
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				case,
				"Post",
				Vector3.new(0.1, glassH, 0.1),
				cf * CFrame.new(sx * (length / 2 - 0.05), baseH + glassH / 2, sz * (d / 2 - 0.05)),
				BRASS,
				Enum.Material.Metal,
				DETAIL
			)
		end
		box(
			case,
			"TopEdge",
			Vector3.new(length, 0.08, 0.1),
			cf * CFrame.new(0, baseH + glassH, sx * (d / 2 - 0.05)),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
	end
	local strip = box(
		case,
		"Strip",
		Vector3.new(length - 0.6, 0.05, 0.12),
		cf * CFrame.new(0, baseH + glassH - 0.08, 0.6),
		COLD_NEON,
		Enum.Material.Neon,
		DETAIL
	)
	strip.Transparency = 0.3
	Kit.pointLight(strip, 6, 0.7, false, COLD)
	-- front drawers
	for i = -1, 1 do
		box(
			case,
			"Drawer",
			Vector3.new(length / 3 - 0.3, 0.9, 0.08),
			cf * CFrame.new(i * length / 3, baseH - 0.7, -d / 2 - 0.04),
			WALNUT,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			case,
			"Pull",
			Vector3.new(0.5, 0.1, 0.1),
			cf * CFrame.new(i * length / 3, baseH - 0.7, -d / 2 - 0.12),
			BRASS,
			Enum.Material.Metal,
			DETAIL
		)
	end
	-- the curios
	local y = baseH + 0.08
	local function at(x, h, z)
		return cf * CFrame.new(x, y + h, z)
	end
	local n = math.floor(length / 1.3)
	for i = 0, n - 1 do
		local x = -length / 2 + 0.75 + i * (length - 1.5) / math.max(n - 1, 1)
		local kind = i % 4
		if kind == 0 then -- snow globe
			cyl(case, "GlobeBase", 0.22, 0.5, at(x, 0.11, 0), EBONY, Enum.Material.Wood, DETAIL)
			local g = box(
				case,
				"Globe",
				Vector3.new(0.55, 0.55, 0.55),
				at(x, 0.48, 0),
				Color3.fromRGB(210, 230, 240),
				Enum.Material.Glass,
				DETAIL
			)
			g.Shape = Enum.PartType.Ball
			g.Transparency = 0.5
			box(case, "Tiny", Vector3.new(0.12, 0.25, 0.12), at(x, 0.38, 0), Color3.fromRGB(60, 40, 80), nil, DETAIL)
		elseif kind == 1 then -- pocket watch on its chain
			cyl(case, "Watch", 0.08, 0.55, at(x, 0.04, 0.1), GOLD, Enum.Material.Metal, DETAIL)
			cyl(case, "WatchFace", 0.09, 0.42, at(x, 0.05, 0.1), BONE, nil, DETAIL)
			box(
				case,
				"WatchChain",
				Vector3.new(0.04, 0.03, 0.6),
				at(x + 0.15, 0.02, -0.35) * CFrame.Angles(0, math.rad(30), 0),
				GOLD,
				Enum.Material.Metal,
				DETAIL
			)
		elseif kind == 2 then -- old keys
			for k = -1, 1 do
				local kc = at(x + k * 0.22, 0.03, 0) * CFrame.Angles(0, math.rad(k * 15), 0)
				box(case, "KeyShaft", Vector3.new(0.06, 0.05, 0.55), kc, BRASS, Enum.Material.Metal, DETAIL)
				box(
					case,
					"KeyBow",
					Vector3.new(0.2, 0.05, 0.2),
					kc * CFrame.new(0, 0, 0.3),
					BRASS,
					Enum.Material.Metal,
					DETAIL
				)
			end
		else -- little ink bottle and a quill
			box(
				case,
				"Ink",
				Vector3.new(0.3, 0.35, 0.3),
				at(x, 0.175, 0),
				Color3.fromRGB(30, 20, 50),
				Enum.Material.Glass,
				DETAIL
			)
			box(
				case,
				"Quill",
				Vector3.new(0.05, 0.8, 0.12),
				at(x + 0.05, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-18)),
				BONE,
				Enum.Material.Fabric,
				DETAIL
			)
		end
	end
	return case
end

local function buildFeatured(shop: Instance, pos: Vector3)
	-- the newest lantern on a column under a glass dome, spot-lit from the track
	local feat = Kit.folder(shop, "Featured")
	local def = Lanterns.List[#Lanterns.List]
	local h = 3.3
	cyl(feat, "Foot", 0.3, 2.3, CFrame.new(pos + Vector3.new(0, 0.15, 0)), EBONY, Enum.Material.Wood)
	cyl(
		feat,
		"Column",
		h - 0.6,
		1.7,
		CFrame.new(pos + Vector3.new(0, 0.3 + (h - 0.6) / 2, 0)),
		WALNUT,
		Enum.Material.Wood
	)
	cyl(feat, "Cap", 0.3, 2.2, CFrame.new(pos + Vector3.new(0, h - 0.15, 0)), EBONY, Enum.Material.Wood)
	cyl(feat, "Cushion", 0.2, 1.5, CFrame.new(pos + Vector3.new(0, h + 0.1, 0)), VELVET, Enum.Material.Fabric, DETAIL)
	local lantern = LanternBuilder.buildModel(def.id, true)
	lantern:PivotTo(CFrame.new(pos + Vector3.new(0, h + 0.2, 0)) * CFrame.Angles(0, math.rad(60), 0))
	local light = lantern:FindFirstChild("Light", true)
	if light then
		light.Brightness *= 0.5
		light.Range = 8
		light.Shadows = false
	end
	lantern.Parent = feat
	-- glass dome (cylinder bell + ball top) resting on the cap rim
	cyl(
		feat,
		"Dome",
		3.0,
		1.95,
		CFrame.new(pos + Vector3.new(0, h + 1.5, 0)),
		Color3.fromRGB(210, 228, 232),
		Enum.Material.Glass,
		GLASS
	)
	local cap = box(
		feat,
		"DomeTop",
		Vector3.new(1.95, 1.95, 1.95),
		pos + Vector3.new(0, h + 3.0, 0),
		Color3.fromRGB(210, 228, 232),
		Enum.Material.Glass,
		GLASS
	)
	cap.Shape = Enum.PartType.Ball
	local plate = box(
		feat,
		"Plate",
		Vector3.new(1.2, 0.4, 0.05),
		CFrame.lookAt(pos + Vector3.new(0, h - 1.0, 0), pos + Vector3.new(1, h - 1.0, 1)) * CFrame.new(0, 0, -0.86),
		CARD,
		nil,
		DETAIL
	)
	printText(plate, Enum.NormalId.Front, {
		{ "NEW: " .. string.upper(def.name), Enum.Font.Bodoni, CARD_TEXT, 0.05, 0.55 },
		{ def.price .. " keys", Enum.Font.Garamond, CARD_ACCENT, 0.55, 0.95 },
	}, nil, 160)
	return feat
end

local function poster(parent: Instance, cf: CFrame, w: number, h: number, lines)
	-- framed poster flat on the wallpaper; cf is the poster centre on the panel face, -Z pointing into the room
	local frame = box(
		parent,
		"PosterFrame",
		Vector3.new(w + 0.24, h + 0.24, 0.1),
		cf * CFrame.new(0, 0, -0.05),
		POSTER_FRAME,
		Enum.Material.Wood,
		DETAIL
	)
	local paper = box(
		parent,
		"Poster",
		Vector3.new(w, h, 0.04),
		cf * CFrame.new(0, 0, -0.12),
		PAPER,
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	printText(paper, Enum.NormalId.Front, lines, PAPER, 40)
	return frame
end

local function buildWalls(shop: Instance)
	local deco = Kit.folder(shop, "WallDecor")
	local south = function(x, y)
		return facing(Vector3.new(x, y, R.z0 + WALL_OUT), Vector3.zAxis)
	end
	local north = function(x, y)
		return facing(Vector3.new(x, y, R.z1 - WALL_OUT), -Vector3.zAxis)
	end
	local lilac = Color3.fromRGB(176, 120, 255)
	local pale = Color3.fromRGB(214, 200, 236)
	local dim = Color3.fromRGB(120, 90, 160)
	poster(deco, south(-19.2, SF + 7.4), 2.6, 3.6, {
		{ "SMILE", Enum.Font.Bodoni, lilac, 0.16, 0.5 },
		{ "he can see", Enum.Font.Garamond, pale, 0.62, 0.76 },
		{ "your teeth", Enum.Font.Garamond, pale, 0.76, 0.9 },
	})
	poster(deco, south(-15.4, SF + 7.8), 2.4, 3.2, {
		{ "HE'S", Enum.Font.Antique, pale, 0.08, 0.26 },
		{ "ALWAYS", Enum.Font.Antique, lilac, 0.26, 0.5 },
		{ "OPEN", Enum.Font.Antique, pale, 0.5, 0.7 },
		{ "24 hours · no days off", Enum.Font.Garamond, dim, 0.78, 0.9 },
	})
	poster(deco, north(-10.2, SF + 8.6), 2.2, 3.0, {
		{ "DO NOT", Enum.Font.Bodoni, pale, 0.1, 0.32 },
		{ "LOOK", Enum.Font.Bodoni, lilac, 0.32, 0.56 },
		{ "AWAY", Enum.Font.Bodoni, pale, 0.56, 0.78 },
		{ "he doesn't", Enum.Font.Garamond, dim, 0.82, 0.94 },
	})
	poster(deco, north(-7.6, SF + 9.2), 1.6, 2.2, {
		{ "PICK", Enum.Font.Antique, lilac, 0.1, 0.34 },
		{ "A", Enum.Font.Antique, lilac, 0.34, 0.52 },
		{ "DOOR", Enum.Font.Antique, lilac, 0.52, 0.76 },
	})
	-- plaque over the doorway, seen on the way out
	local plaque = box(
		deco,
		"Plaque",
		Vector3.new(6, 0.8, 0.08),
		facing(Vector3.new(R.x1 - WALL_OUT - 0.04, DOOR.y1 + 0.9, DOOR_ZC), -Vector3.xAxis),
		BLACK,
		Enum.Material.Wood,
		DETAIL
	)
	printText(
		plaque,
		Enum.NormalId.Front,
		{ { "THANK YOU  ·  HE'LL REMEMBER YOU", Enum.Font.Bodoni, GOLD, 0.12, 0.88 } },
		nil,
		50
	)

	-- shelf of black candles on brackets (south wall, behind the counter), none of them lit
	local sx, sy = -24.6, SF + 5.2
	box(deco, "CandleShelf", Vector3.new(4.2, 0.2, 1.0), Vector3.new(sx, sy, R.z0 + 0.5), WALNUT, Enum.Material.Wood)
	for _, dx in { -1.6, 1.6 } do
		box(
			deco,
			"Bracket",
			Vector3.new(0.15, 0.8, 0.7),
			Vector3.new(sx + dx, sy - 0.5, R.z0 + 0.38),
			Color3.fromRGB(30, 30, 34),
			Enum.Material.Metal,
			DETAIL
		)
	end
	for _, spec in { { -1.6, 0.9 }, { -0.9, 0.6 }, { -0.25, 1.2 }, { 0.5, 0.7 }, { 1.2, 1.0 }, { 1.75, 0.5 } } do
		local p = Vector3.new(sx + spec[1], sy + 0.1, R.z0 + 0.5)
		cyl(
			deco,
			"Candle",
			spec[2],
			0.34,
			CFrame.new(p + Vector3.new(0, spec[2] / 2, 0)),
			Color3.fromRGB(18, 14, 20),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
		box(
			deco,
			"Wick",
			Vector3.new(0.04, 0.12, 0.04),
			p + Vector3.new(0, spec[2] + 0.05, 0),
			Color3.fromRGB(40, 36, 40),
			nil,
			DETAIL
		)
	end
	local label =
		box(deco, "ShelfLabel", Vector3.new(1.4, 0.3, 0.04), Vector3.new(sx, sy - 0.05, R.z0 + 1.02), CARD, nil, DETAIL)
	printText(
		label,
		Enum.NormalId.Back,
		{ { "CANDLES  ·  3 KEYS", Enum.Font.Garamond, CARD_TEXT, 0.1, 0.9 } },
		nil,
		120
	)
	return deco
end

local function buildStock(shop: Instance)
	local stock = Kit.folder(shop, "Stock")
	restain(
		Furniture.metalRack(stock, CFrame.new(R.x0 + 1.1, SF, 62.6) * CFrame.Angles(0, math.rad(90), 0), 5.4, 6.4, 1.8)
	)
	restain(
		Kit.prop(stock, "BoxTaped", CFrame.new(-25.4, SF, 44.2) * CFrame.Angles(0, math.rad(80), 0)),
		Color3.fromRGB(58, 46, 44),
		Enum.Material.Cardboard
	)
	restain(Kit.prop(stock, "BoxOpen", CFrame.new(-26.4, SF, 61.6) * CFrame.Angles(0, math.rad(75), 0), 0.9))
	-- plants: a palm in the corner by the door, a fern by the postcards
	Kit.prop(stock, "PalmVase", CFrame.new(R.x1 - 1.5, SF, R.z0 + 1.6), 0.9)
	Kit.prop(stock, "Fern", CFrame.new(R.x1 - 1.3, SF, R.z1 - 1.3), 1.1)
	return stock
end

------------------------------------------------------------------------------------------
-- Lighting
------------------------------------------------------------------------------------------
-- Pendant over the counter: black enamel cone on a cord, a cold violet bulb that throws a pool of lilac
-- light down. Named like Kit.bareBulb's (Lamp / Core / Shade) so AtmosFX hangs its light cone under it.
local function coldPendant(parent: Instance, pos: Vector3, range: number, brightness: number, shadows: boolean)
	local model = Kit.folder(parent, "Lamp")
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; roll them upright
	local fittingY = pos.Y + 1.0
	local noCollide = { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CastShadow = false }
	box(
		model,
		"Rose",
		Vector3.new(0.2, 0.8, 0.8),
		CFrame.new(pos.X, CEIL - 0.1, pos.Z) * upright,
		BLACK,
		Enum.Material.Metal,
		noCollide
	)
	box(
		model,
		"Cord",
		Vector3.new(0.07, CEIL - fittingY, 0.07),
		Vector3.new(pos.X, (CEIL + fittingY) / 2, pos.Z),
		Color3.fromRGB(20, 16, 22),
		Enum.Material.Fabric,
		DETAIL
	)
	box(
		model,
		"Fitting",
		Vector3.new(0.4, 0.34, 0.34),
		CFrame.new(pos.X, fittingY, pos.Z) * upright,
		BLACK,
		Enum.Material.Metal,
		noCollide
	)
	local core = box(model, "Core", Vector3.new(0.5, 0.5, 0.5), pos, COLD_NEON, Enum.Material.Neon, DETAIL)
	core.Shape = Enum.PartType.Ball
	core.Transparency = 0.35
	coldHalo(core, 2.6)
	-- stepped black cone, lit lilac inside
	for i, spec in { { 0.75, 0.7 }, { 0.52, 1.2 }, { 0.3, 1.7 }, { 0.1, 2.1 } } do
		box(
			model,
			"Shade",
			Vector3.new(i == 4 and 0.14 or 0.24, spec[2], spec[2]),
			CFrame.new(pos + Vector3.new(0, spec[1], 0)) * upright,
			Color3.fromRGB(18, 14, 20),
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
		)
	end
	box(
		model,
		"ShadeInner",
		Vector3.new(0.05, 1.5, 1.5),
		CFrame.new(pos + Vector3.new(0, 0.18, 0)) * upright,
		COLD_NEON,
		Enum.Material.Neon,
		{
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 115
	spot.Range = range
	spot.Brightness = brightness * 1.3
	spot.Color = COLD
	spot.Shadows = shadows
	spot.Parent = core
	Kit.pointLight(core, range * 0.55, brightness * 0.35, false, COLD)
	return model, core
end

local function trackSpot(parent: Instance, mount: Vector3, target: Vector3, brightness: number, range: number)
	-- a spot can on a short stem below the track, aimed at `target`
	local stemBottom = mount - Vector3.new(0, 0.5, 0)
	box(
		parent,
		"Stem",
		Vector3.new(0.1, 0.5, 0.1),
		mount - Vector3.new(0, 0.25, 0),
		C.steel,
		Enum.Material.Metal,
		DETAIL
	)
	local aim = CFrame.lookAt(stemBottom, target)
	cyl(
		parent,
		"Can",
		0.8,
		0.5,
		aim * CFrame.new(0, 0, -0.2) * CFrame.Angles(math.rad(90), 0, 0),
		Color3.fromRGB(30, 30, 32),
		Enum.Material.Metal,
		DETAIL
	)
	local lens = cyl(
		parent,
		"Lens",
		0.04,
		0.4,
		aim * CFrame.new(0, 0, -0.61) * CFrame.Angles(math.rad(90), 0, 0),
		COLD_NEON,
		Enum.Material.Neon,
		DETAIL
	)
	lens.Transparency = 0.2
	local emitter =
		box(parent, "SpotEmitter", Vector3.new(0.1, 0.1, 0.1), aim * CFrame.new(0, 0, -0.7), COLD, nil, INVISIBLE)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = range
	spot.Brightness = brightness
	spot.Color = COLD
	spot.Shadows = false
	spot.Parent = emitter
end

local function buildLighting(shop: Instance)
	local lights = Kit.folder(shop, "Lighting")
	-- two black pendants over the counter (only the first throws shadows)
	coldPendant(lights, Vector3.new(COUNTER.x, CEIL - 4.2, 50.5), 16, 1.2, true)
	coldPendant(lights, Vector3.new(COUNTER.x, CEIL - 4.2, 55.5), 16, 1.1, false)
	-- ceiling track down the middle of the shop floor with spots on the displays
	local tx = -13
	local z0, z1 = 44.5, 61.5
	box(
		lights,
		"Track",
		Vector3.new(0.3, 0.2, z1 - z0),
		Vector3.new(tx, CEIL - 0.1, (z0 + z1) / 2),
		STEEL,
		Enum.Material.Metal,
		DETAIL
	)
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 45.5), Vector3.new(-11, SF + 4, 45.6), 3, 16) -- featured lantern
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 47), Vector3.new(-17, SF + 3, 43.6), 1.6, 18) -- curio case
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 60), Vector3.new(-18.6, SF + 3, 62), 1.6, 18) -- picks table
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 61), Vector3.new(-10.5, SF + 3, 62.6), 1.4, 16) -- postcards
	-- dim violet fill so the corners read, not black
	local fill =
		box(lights, "Fill", Vector3.new(0.2, 0.2, 0.2), Vector3.new(-17, CEIL - 2, DOOR_ZC), COLD, nil, INVISIBLE)
	Kit.pointLight(fill, 22, 0.4, false, Color3.fromRGB(150, 110, 220))
	return lights
end

------------------------------------------------------------------------------------------
function Shop.build(root: Instance)
	Kit.reseed(4242)
	local shop = Kit.folder(root, "Shop")

	buildStorefront(shop)
	buildSkin(shop)
	buildCounter(shop)
	buildLanternWall(shop)
	buildCatalogue(shop, facing(Vector3.new(R.x0 + 1.15, SF, 44.5), Vector3.xAxis))
	buildBooksForSale(shop)
	buildPostcards(shop, Vector3.new(-10.4, SF, 62.4))
	buildVitrine(shop, facing(Vector3.new(-17.2, SF, R.z0 + 1.2), Vector3.zAxis), 7)
	buildFeatured(shop, Vector3.new(-10.8, SF, 45.4))
	buildWalls(shop)
	buildStock(shop)
	buildLighting(shop)

	-- the walkway rug, doorway to counter: violet-black with a lilac border
	local rugX0, rugX1 = COUNTER.x + COUNTER.depth / 2 + 1.0, DOOR.x0 - 0.8
	local rugCx, rugW = (rugX0 + rugX1) / 2, rugX1 - rugX0
	box(
		shop,
		"Rug",
		Vector3.new(rugW, 0.08, 7.6),
		Vector3.new(rugCx, SF + 0.04, DOOR_ZC),
		Color3.fromRGB(30, 12, 40),
		Enum.Material.Carpet,
		{ CanCollide = false, CastShadow = false }
	)
	box(
		shop,
		"RugBorder",
		Vector3.new(rugW - 0.8, 0.02, 6.8),
		Vector3.new(rugCx, SF + 0.09, DOOR_ZC),
		Color3.fromRGB(96, 60, 140),
		Enum.Material.Carpet,
		DETAIL
	)
	box(
		shop,
		"RugField",
		Vector3.new(rugW - 1.2, 0.02, 6.4),
		Vector3.new(rugCx, SF + 0.1, DOOR_ZC),
		Color3.fromRGB(44, 18, 60),
		Enum.Material.Carpet,
		DETAIL
	)
	return shop
end

return Shop
