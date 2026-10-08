--[[
	The Gift Shop: the librarian's little shop off the arrival foyer, where she sells lanterns and curios.

	Two halves:
	  * Storefront, on the foyer side of the shared wall (the x = Openings.ShopDoor.x1 face, facing +X):
	    a steel portal frame round the opening, a hanging back-lit "GIFT SHOP" marquee box sign with
	    bulbs and a neon tube, planters either side and a chalk A-board.
	  * Interior (Layout.Rooms.Shop): a clear rug-lined walkway from the doorway to the checkout counter
	    (till, bell, ledger, banker lamp; the "Shop" ProximityPrompt), and behind it the lit lantern wall
	    with every lantern in Lanterns.List in its own velvet cubby with a price tag. Around the walls:
	    card catalogue, stock rack, books for sale, a staff-picks table, a postcard spinner, a curio
	    vitrine, a featured lantern under a glass dome, posters, plants and a candle shelf.

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
local FY = R.y -- shop floor
local CEIL = R.y + R.h -- shop ceiling
local FOYER_CEIL = Layout.Rooms.Foyer.y + Layout.Rooms.Foyer.h
local FRONT_X = DOOR.x1 -- foyer face of the shared wall
local DOOR_ZC = (DOOR.z0 + DOOR.z1) / 2

local STEEL = Color3.fromRGB(56, 64, 76) -- blue-grey painted steel (portal, track)
local CREAM = Color3.fromRGB(232, 220, 192)
local VELVET = Color3.fromRGB(34, 58, 46)
local GOLD = Color3.fromRGB(212, 168, 92)
local SIGN_GLOW = Color3.fromRGB(255, 214, 150)
local GLASS = { Transparency = 0.82, Reflectance = 0.08, CanCollide = false, CastShadow = false }

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
	gui.Brightness = 2.2
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

------------------------------------------------------------------------------------------
-- Storefront (foyer side)
------------------------------------------------------------------------------------------
local function buildStorefront(shop: Instance)
	local front = Kit.folder(shop, "Storefront")
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

	-- the marquee: an enamelled box sign hung on chains in front of the header, back-lit lettering,
	-- a ring of amber bulbs and a red neon tube that flickers now and then
	local signW, signH, signD = width + 1.6, 2.5, 0.7
	local sy = top + 0.6 + signH / 2
	local sx = x + 1.15
	local signCf = facing(Vector3.new(sx, sy, DOOR_ZC), Vector3.xAxis) -- Front face looks into the foyer
	local case = box(
		front,
		"SignCase",
		Vector3.new(signW, signH, signD),
		signCf,
		Color3.fromRGB(30, 46, 40),
		Enum.Material.Metal
	)
	box(
		front,
		"SignRim",
		Vector3.new(signW + 0.24, signH + 0.24, signD - 0.2),
		signCf * CFrame.new(0, 0, 0.05),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local face = box(
		front,
		"SignFace",
		Vector3.new(signW - 1.1, 1.55, 0.05),
		signCf * CFrame.new(0, 0.22, -signD / 2 - 0.02),
		Color3.fromRGB(22, 34, 30),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	glowText(face, Enum.NormalId.Front, "GIFT SHOP", Enum.Font.Bodoni, SIGN_GLOW, Color3.fromRGB(255, 150, 60))
	local sub = box(
		front,
		"SignSub",
		Vector3.new(signW - 4, 0.42, 0.05),
		signCf * CFrame.new(0, -0.82, -signD / 2 - 0.02),
		Color3.fromRGB(22, 34, 30),
		nil,
		DETAIL
	)
	glowText(
		sub,
		Enum.NormalId.Front,
		"LANTERNS  ·  BOOKS  ·  CURIOS",
		Enum.Font.Antique,
		Color3.fromRGB(255, 196, 140),
		Color3.fromRGB(255, 120, 50),
		80
	)
	-- neon tube framing the lettering
	local neonRed = Color3.fromRGB(255, 92, 70)
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
			neonRed,
			Enum.Material.Neon,
			DETAIL
		)
		tube.Transparency = 0.15
		tube:SetAttribute("NeonFlicker", true)
	end
	-- marquee bulbs along the top and bottom edges
	local bulbs = 14
	for i = 0, bulbs - 1 do
		local u = (i + 0.5) / bulbs - 0.5
		for _, v in { 1, -1 } do
			local bulb = box(
				front,
				"MarqueeBulb",
				Vector3.new(0.26, 0.26, 0.26),
				signCf * CFrame.new(u * (signW - 0.4), v * (signH / 2 - 0.02), -signD / 2 - 0.02),
				Color3.fromRGB(255, 190, 110),
				Enum.Material.Neon,
				DETAIL
			)
			bulb.Shape = Enum.PartType.Ball
		end
	end
	-- light: wash down the front of the wall and onto the foyer floor
	local lamp = box(
		front,
		"SignLight",
		Vector3.new(0.2, 0.2, 0.2),
		signCf * CFrame.new(0, -signH / 2 - 0.2, -0.6),
		C.warm,
		nil,
		INVISIBLE
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 120
	spot.Range = 16
	spot.Brightness = 2.2
	spot.Color = Color3.fromRGB(255, 196, 130)
	spot.Shadows = false
	spot.Parent = lamp
	Kit.pointLight(case, 9, 0.8, false, Color3.fromRGB(255, 150, 90))
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

	-- chalk A-board on the foyer floor
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
			{ "LANTERNS", Enum.Font.PermanentMarker, Color3.fromRGB(236, 232, 220), 0.06, 0.24 },
			{ "now in stock!", Enum.Font.Kalam, Color3.fromRGB(240, 200, 120), 0.26, 0.4 },
			{ "books · postcards", Enum.Font.Kalam, Color3.fromRGB(200, 220, 230), 0.48, 0.6 },
			{ "curios & candles", Enum.Font.Kalam, Color3.fromRGB(200, 220, 230), 0.6, 0.72 },
			{ "-> ask the librarian", Enum.Font.Kalam, Color3.fromRGB(236, 232, 220), 0.8, 0.93 },
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
-- Checkout counter
------------------------------------------------------------------------------------------
local COUNTER = { x = -20.8, z0 = 47.5, z1 = 58.5, depth = 2.6, h = 3.5 }

local function buildTill(parent: Instance, base: CFrame)
	-- antique brass cash register; `base` sits on the counter top, keys toward base's -Z
	local till = Kit.folder(parent, "Till")
	local brass = Color3.fromRGB(170, 128, 62)
	box(
		till,
		"Drawer",
		Vector3.new(1.7, 0.5, 1.5),
		base * CFrame.new(0, 0.25, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(till, "Body", Vector3.new(1.5, 0.8, 1.1), base * CFrame.new(0, 0.9, 0.15), brass, Enum.Material.Metal, DETAIL)
	box(
		till,
		"KeyBed",
		Vector3.new(1.5, 0.3, 0.7),
		base * CFrame.new(0, 0.65, -0.55) * CFrame.Angles(math.rad(-20), 0, 0),
		brass,
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
				CREAM,
				Enum.Material.SmoothPlastic,
				DETAIL
			)
		end
	end
	local flag = box(
		till,
		"Flag",
		Vector3.new(1.1, 0.45, 0.12),
		base * CFrame.new(0, 1.55, 0.2),
		Color3.fromRGB(240, 228, 196),
		nil,
		DETAIL
	)
	printText(
		flag,
		Enum.NormalId.Back,
		{ { "THANK YOU", Enum.Font.Bodoni, Color3.fromRGB(60, 30, 20), 0.1, 0.9 } },
		nil,
		120
	)
	box(
		till,
		"FlagHousing",
		Vector3.new(1.25, 0.12, 0.3),
		base * CFrame.new(0, 1.32, 0.2),
		brass,
		Enum.Material.Metal,
		DETAIL
	)
	cyl(
		till,
		"Crank",
		0.5,
		0.12,
		base * CFrame.new(0.85, 0.95, 0.2) * CFrame.Angles(0, 0, math.rad(90)),
		brass,
		Enum.Material.Metal,
		DETAIL
	)
	box(
		till,
		"CrankHandle",
		Vector3.new(0.12, 0.12, 0.45),
		base * CFrame.new(1.1, 0.95, 0.4),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	return till
end

local function buildCounter(shop: Instance)
	local counter = Kit.folder(shop, "Counter")
	local cx, d = COUNTER.x, COUNTER.depth
	local len = COUNTER.z1 - COUNTER.z0
	local cz = (COUNTER.z0 + COUNTER.z1) / 2
	local topY = FY + COUNTER.h
	local frontX = cx + d / 2 -- customer side faces +X

	box(
		counter,
		"Plinth",
		Vector3.new(d - 0.3, 0.35, len - 0.3),
		Vector3.new(cx - 0.1, FY + 0.175, cz),
		C.darkWood,
		Enum.Material.Wood
	)
	box(
		counter,
		"Body",
		Vector3.new(d - 0.2, COUNTER.h - 0.6, len - 0.2),
		Vector3.new(cx - 0.05, FY + 0.35 + (COUNTER.h - 0.6) / 2, cz),
		C.wood,
		Enum.Material.Wood
	)
	local top = box(
		counter,
		"Top",
		Vector3.new(d + 0.3, 0.26, len + 0.4),
		Vector3.new(cx, topY - 0.13, cz),
		C.midWood,
		Enum.Material.Wood
	)
	box(
		counter,
		"TopEdge",
		Vector3.new(0.12, 0.12, len + 0.4),
		Vector3.new(cx + d / 2 + 0.19, topY - 0.3, cz),
		C.brass,
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
			Vector3.new(frontX, FY + 0.35 + (COUNTER.h - 0.6) / 2, z),
			C.midWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			counter,
			"PanelInset",
			Vector3.new(0.06, COUNTER.h - 2.0, pw - 1.3),
			Vector3.new(frontX + 0.06, FY + 0.35 + (COUNTER.h - 0.6) / 2, z),
			C.wood,
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
			Vector3.new(frontX + 0.02, FY + 0.35 + (COUNTER.h - 0.6) / 2, z),
			C.darkWood,
			Enum.Material.Wood,
			DETAIL
		)
	end
	-- brass foot rail on little brackets
	box(
		counter,
		"FootRail",
		Vector3.new(0.14, 0.14, len - 0.6),
		Vector3.new(frontX + 0.55, FY + 0.55, cz),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	for _, z in { COUNTER.z0 + 0.6, cz, COUNTER.z1 - 0.6 } do
		box(
			counter,
			"RailBracket",
			Vector3.new(0.6, 0.1, 0.1),
			Vector3.new(frontX + 0.27, FY + 0.55, z),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	-- brass name plate
	local plate = box(
		counter,
		"Plate",
		Vector3.new(0.06, 0.5, 2.6),
		Vector3.new(frontX + 0.13, topY - 0.75, cz),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	printText(
		plate,
		Enum.NormalId.Right,
		{ { "CHECKOUT", Enum.Font.Bodoni, Color3.fromRGB(50, 34, 18), 0.1, 0.9 } },
		nil,
		80
	)

	-- on top: till (keys toward the librarian), bell, open ledger, lamp, parcels, a tent card
	buildTill(counter, facing(Vector3.new(cx - 0.2, topY, COUNTER.z0 + 1.6), -Vector3.xAxis))
	local bellPos = Vector3.new(cx + 0.75, topY, cz + 0.4)
	cyl(
		counter,
		"BellBase",
		0.1,
		0.62,
		CFrame.new(bellPos + Vector3.new(0, 0.05, 0)),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	local dome = box(
		counter,
		"Bell",
		Vector3.new(0.48, 0.48, 0.48),
		bellPos + Vector3.new(0, 0.12, 0),
		C.brass,
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
		CREAM,
		nil,
		DETAIL
	)
	printText(card, Enum.NormalId.Right, {
		{ "PLEASE RING", Enum.Font.Bodoni, Color3.fromRGB(60, 34, 24), 0.1, 0.5 },
		{ "for service", Enum.Font.Garamond, Color3.fromRGB(60, 34, 24), 0.52, 0.86 },
	}, nil, 120)
	box(counter, "CardFoot", Vector3.new(0.2, 0.04, 0.9), bellPos + Vector3.new(0.05, 0.02, 0.9), CREAM, nil, DETAIL)
	-- open ledger, pages tipped up a little either side of the spine
	local ledger = Vector3.new(cx - 0.1, topY, cz + 2.4)
	box(
		counter,
		"LedgerCover",
		Vector3.new(1.3, 0.06, 1.9),
		ledger + Vector3.new(0, 0.03, 0),
		Color3.fromRGB(86, 28, 24),
		Enum.Material.Fabric,
		DETAIL
	)
	for _, s in { -1, 1 } do
		box(
			counter,
			"LedgerPages",
			Vector3.new(1.18, 0.1, 0.9),
			CFrame.new(ledger + Vector3.new(0, 0.12, s * 0.46)) * CFrame.Angles(s * math.rad(4), 0, 0),
			Color3.fromRGB(236, 226, 200),
			Enum.Material.Fabric,
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
	Furniture.deskLamp(counter, Vector3.new(cx - 0.6, topY, COUNTER.z1 - 0.9), 10)
	-- brown-paper parcels tied with string, ready for collection
	for i, spec in { { 1.2, 0.6, 1.0 }, { 0.9, 0.45, 0.8 } } do
		local y = topY + (i == 1 and 0.3 or 0.6 + 0.225)
		local cf = CFrame.new(cx + 0.3, y, COUNTER.z1 - 2.3) * CFrame.Angles(0, math.rad(i * 9), 0)
		box(
			counter,
			"Parcel",
			Vector3.new(spec[1], spec[2], spec[3]),
			cf,
			Color3.fromRGB(176, 140, 98),
			Enum.Material.Cardboard,
			DETAIL
		)
		box(
			counter,
			"Twine",
			Vector3.new(spec[1] + 0.02, spec[2] + 0.02, 0.05),
			cf,
			Color3.fromRGB(226, 214, 186),
			Enum.Material.Fabric,
			DETAIL
		)
		box(
			counter,
			"Twine",
			Vector3.new(0.05, spec[2] + 0.02, spec[3] + 0.02),
			cf,
			Color3.fromRGB(226, 214, 186),
			Enum.Material.Fabric,
			DETAIL
		)
	end

	Kit.prompt(top, "Gift Shop", "Browse Shop", "Shop")

	-- the librarian's chair behind the counter, and a step stool
	Kit.prop(counter, "ChairVictorian", facing(Vector3.new(cx - 3, FY, cz - 1.5), Vector3.xAxis))
	-- dust hanging in the lamp light over the counter
	Kit.anchor(counter, "LampDust", CFrame.new(cx, FY + 7, cz), Vector3.new(5, 5, 9))
	return counter
end

------------------------------------------------------------------------------------------
-- Lantern wall: back-lit velvet cubbies behind the counter, one lantern each
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
	local cubbyY = FY + baseH + 0.2

	-- base cabinet with doors
	box(
		wall,
		"Base",
		Vector3.new(depth, baseH, width),
		Vector3.new(x0 + depth / 2, FY + baseH / 2, zc),
		C.wood,
		Enum.Material.Wood
	)
	for i = 0, 3 do
		local z = zc - width / 2 + (i + 0.5) * width / 4
		box(
			wall,
			"Door",
			Vector3.new(0.1, baseH - 0.7, width / 4 - 0.25),
			Vector3.new(fx + 0.05, FY + baseH / 2 + 0.1, z),
			C.midWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			wall,
			"Knob",
			Vector3.new(0.14, 0.14, 0.14),
			Vector3.new(fx + 0.15, FY + baseH / 2 + 0.3, z + (i % 2 == 0 and 1 or -1) * (width / 8 - 0.4)),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	box(
		wall,
		"Ledge",
		Vector3.new(depth + 0.35, 0.2, width + 0.3),
		Vector3.new(x0 + (depth + 0.35) / 2, FY + baseH + 0.1, zc),
		C.midWood,
		Enum.Material.Wood
	)

	-- cubbies
	box(
		wall,
		"Velvet",
		Vector3.new(0.15, cubbyH, width),
		Vector3.new(x0 + 0.075, cubbyY + cubbyH / 2, zc),
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
			C.darkWood,
			Enum.Material.Wood
		)
	end
	box(
		wall,
		"CubbyTop",
		Vector3.new(depth + 0.2, 0.3, width + 0.2),
		Vector3.new(x0 + (depth + 0.2) / 2, cubbyY + cubbyH + 0.15, zc),
		C.darkWood,
		Enum.Material.Wood
	)
	box(
		wall,
		"Crown",
		Vector3.new(depth + 0.6, 0.35, width + 0.8),
		Vector3.new(x0 + (depth + 0.6) / 2, cubbyY + cubbyH + 0.475, zc),
		C.midWood,
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
		-- warm strip light hidden under the cubby top
		local strip = box(
			wall,
			"Strip",
			Vector3.new(0.12, 0.05, cubbyW - 0.4),
			Vector3.new(fx - 0.35, cubbyY + cubbyH - 0.05, z),
			SIGN_GLOW,
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
			VELVET:Lerp(Color3.new(0, 0, 0), 0.25),
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
			Vector3.new(x0 + depth + 0.37, FY + baseH + 0.02, z),
			CREAM,
			nil,
			DETAIL
		)
		printText(tag, Enum.NormalId.Right, {
			{ string.upper(def.name), Enum.Font.Bodoni, Color3.fromRGB(40, 28, 20), 0.06, 0.5 },
			{
				if def.price > 0 then def.price .. " KEYS" else "ON THE HOUSE",
				Enum.Font.Garamond,
				Color3.fromRGB(130, 30, 24),
				0.52,
				0.94,
			},
		}, nil, 160)
	end

	-- gilt "LANTERNS" board above, with a brass picture light
	local boardY = cubbyY + cubbyH + 1.2
	local board = box(
		wall,
		"Board",
		Vector3.new(0.15, 1.1, 6.4),
		Vector3.new(x0 + 0.075, boardY, zc),
		Color3.fromRGB(24, 30, 26),
		Enum.Material.Wood
	)
	printText(board, Enum.NormalId.Right, { { "LANTERNS", Enum.Font.Bodoni, GOLD, 0.08, 0.92 } }, nil, 60)
	box(
		wall,
		"PictureLightArm",
		Vector3.new(0.7, 0.08, 0.08),
		Vector3.new(x0 + 0.35, boardY + 0.9, zc),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local hood = box(
		wall,
		"PictureLight",
		Vector3.new(0.3, 0.2, 3.4),
		Vector3.new(x0 + 0.75, boardY + 0.9, zc),
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	local tube = box(
		wall,
		"PictureTube",
		Vector3.new(0.08, 0.05, 3.2),
		Vector3.new(x0 + 0.75, boardY + 0.78, zc),
		SIGN_GLOW,
		Enum.Material.Neon,
		DETAIL
	)
	tube.Transparency = 0.3
	local wash = Instance.new("SpotLight")
	wash.Face = Enum.NormalId.Bottom
	wash.Angle = 120
	wash.Range = 5
	wash.Brightness = 1.2
	wash.Color = C.warm
	wash.Parent = hood

	-- wall clock above it all (ticking via the Clock sound marker)
	local clockPos = Vector3.new(x0 + 0.1, boardY + 2.0, zc)
	local clockCf = facing(clockPos, Vector3.xAxis)
	cyl(wall, "ClockRim", 0.2, 2.1, clockCf * CFrame.Angles(math.rad(90), 0, 0), C.darkWood, Enum.Material.Wood)
	local dial = cyl(
		wall,
		"ClockFace",
		0.22,
		1.8,
		clockCf * CFrame.new(0, 0, -0.02) * CFrame.Angles(math.rad(90), 0, 0),
		CREAM,
		nil,
		DETAIL
	)
	dial.CastShadow = false
	box(
		wall,
		"HourHand",
		Vector3.new(0.08, 0.5, 0.03),
		clockCf * CFrame.new(0, 0, -0.15) * CFrame.Angles(0, 0, math.rad(-60)) * CFrame.new(0, 0.22, 0),
		Color3.fromRGB(20, 20, 20),
		nil,
		DETAIL
	)
	box(
		wall,
		"MinuteHand",
		Vector3.new(0.06, 0.75, 0.03),
		clockCf * CFrame.new(0, 0, -0.16) * CFrame.Angles(0, 0, math.rad(20)) * CFrame.new(0, 0.34, 0),
		Color3.fromRGB(20, 20, 20),
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
	box(
		cab,
		"Body",
		Vector3.new(w, h - 0.6, d),
		cf * CFrame.new(0, 0.6 + (h - 0.6) / 2, 0),
		C.midWood,
		Enum.Material.Wood
	)
	box(
		cab,
		"TopBoard",
		Vector3.new(w + 0.3, 0.2, d + 0.2),
		cf * CFrame.new(0, h + 0.1, 0),
		C.darkWood,
		Enum.Material.Wood
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(
				cab,
				"Leg",
				Vector3.new(0.3, 0.6, 0.3),
				cf * CFrame.new(sx * (w / 2 - 0.25), 0.3, sz * (d / 2 - 0.25)),
				C.darkWood,
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
				C.wood,
				Enum.Material.Wood,
				DETAIL
			)
			box(
				cab,
				"Label",
				Vector3.new(0.4, 0.14, 0.04),
				cf * CFrame.new(px, py + 0.1, -d / 2 - 0.11),
				CREAM,
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
		if not Kit.prop(books, "Bookshelf", CFrame.new(x, FY, z)) then
			Furniture.bookcase(books, CFrame.new(x, FY, z) * CFrame.Angles(0, math.pi, 0), 5.6, 11, 1.6, false)
		end
	end
	-- staff-picks table in front
	local t = CFrame.new(-18.6, FY, 61.9)
	local topY = 2.7
	box(books, "TableTop", Vector3.new(5, 0.25, 2.4), t * CFrame.new(0, topY - 0.125, 0), C.midWood, Enum.Material.Wood)
	box(
		books,
		"TableApron",
		Vector3.new(4.6, 0.4, 2.0),
		t * CFrame.new(0, topY - 0.45, 0),
		C.wood,
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
				C.darkWood,
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
			C.darkWood,
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
		CREAM,
		nil,
		DETAIL
	)
	printText(tent, Enum.NormalId.Front, {
		{ "STAFF PICKS", Enum.Font.Bodoni, Color3.fromRGB(110, 26, 22), 0.08, 0.58 },
		{ "she has read them all", Enum.Font.Garamond, Color3.fromRGB(50, 36, 26), 0.6, 0.92 },
	}, nil, 100)
	return books
end

local function buildPostcards(shop: Instance, pos: Vector3)
	-- spinning wire postcard rack
	local rack = Kit.folder(shop, "PostcardRack")
	local rng = Kit.rng
	cyl(rack, "Base", 0.15, 1.8, CFrame.new(pos + Vector3.new(0, 0.075, 0)), C.steel, Enum.Material.Metal)
	box(rack, "Pole", Vector3.new(0.14, 5.6, 0.14), pos + Vector3.new(0, 2.95, 0), C.steel, Enum.Material.Metal)
	local cardColors = {
		Color3.fromRGB(96, 150, 170), -- natatorium blue
		Color3.fromRGB(196, 150, 90),
		Color3.fromRGB(120, 140, 92),
		Color3.fromRGB(170, 90, 70),
		Color3.fromRGB(220, 206, 170),
		Color3.fromRGB(70, 96, 120),
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
				Color3.fromRGB(40, 40, 42),
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
	local topper = box(
		rack,
		"Topper",
		Vector3.new(1.4, 0.45, 0.05),
		pos + Vector3.new(0, 5.95, 0),
		Color3.fromRGB(150, 36, 30),
		nil,
		DETAIL
	)
	topper.CFrame = facing(topper.Position, Vector3.new(1, 0, -0.6).Unit)
	printText(topper, Enum.NormalId.Front, { { "POSTCARDS", Enum.Font.Bodoni, CREAM, 0.1, 0.9 } }, nil, 80)
	printText(topper, Enum.NormalId.Back, { { "POSTCARDS", Enum.Font.Bodoni, CREAM, 0.1, 0.9 } }, nil, 80)
	return rack
end

local function buildVitrine(shop: Instance, cf: CFrame, length: number)
	-- curio cabinet: wooden base, brass-framed glass case on top, lit from inside. Front faces cf's -Z.
	local case = Kit.folder(shop, "CurioCase")
	local d, baseH, glassH = 2.0, 2.9, 1.5
	box(case, "Base", Vector3.new(length, baseH, d), cf * CFrame.new(0, baseH / 2, 0), C.wood, Enum.Material.Wood)
	box(
		case,
		"Plinth",
		Vector3.new(length + 0.2, 0.3, d + 0.2),
		cf * CFrame.new(0, 0.15, 0),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	box(
		case,
		"Bed",
		Vector3.new(length - 0.2, 0.08, d - 0.2),
		cf * CFrame.new(0, baseH + 0.04, 0),
		VELVET:Lerp(Color3.fromRGB(90, 30, 30), 0.7),
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
				C.brass,
				Enum.Material.Metal,
				DETAIL
			)
		end
		box(
			case,
			"TopEdge",
			Vector3.new(length, 0.08, 0.1),
			cf * CFrame.new(0, baseH + glassH, sx * (d / 2 - 0.05)),
			C.brass,
			Enum.Material.Metal,
			DETAIL
		)
	end
	local strip = box(
		case,
		"Strip",
		Vector3.new(length - 0.6, 0.05, 0.12),
		cf * CFrame.new(0, baseH + glassH - 0.08, 0.6),
		SIGN_GLOW,
		Enum.Material.Neon,
		DETAIL
	)
	strip.Transparency = 0.3
	Kit.pointLight(strip, 6, 0.8, false)
	-- front drawers
	for i = -1, 1 do
		box(
			case,
			"Drawer",
			Vector3.new(length / 3 - 0.3, 0.9, 0.08),
			cf * CFrame.new(i * length / 3, baseH - 0.7, -d / 2 - 0.04),
			C.midWood,
			Enum.Material.Wood,
			DETAIL
		)
		box(
			case,
			"Pull",
			Vector3.new(0.5, 0.1, 0.1),
			cf * CFrame.new(i * length / 3, baseH - 0.7, -d / 2 - 0.12),
			C.brass,
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
			cyl(case, "GlobeBase", 0.22, 0.5, at(x, 0.11, 0), C.darkWood, Enum.Material.Wood, DETAIL)
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
			box(case, "Tiny", Vector3.new(0.12, 0.25, 0.12), at(x, 0.38, 0), Color3.fromRGB(60, 90, 70), nil, DETAIL)
		elseif kind == 1 then -- pocket watch on its chain
			cyl(case, "Watch", 0.08, 0.55, at(x, 0.04, 0.1) * CFrame.Angles(0, 0, 0), GOLD, Enum.Material.Metal, DETAIL)
			cyl(case, "WatchFace", 0.09, 0.42, at(x, 0.05, 0.1), CREAM, nil, DETAIL)
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
				box(case, "KeyShaft", Vector3.new(0.06, 0.05, 0.55), kc, C.brass, Enum.Material.Metal, DETAIL)
				box(
					case,
					"KeyBow",
					Vector3.new(0.2, 0.05, 0.2),
					kc * CFrame.new(0, 0, 0.3),
					C.brass,
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
				Color3.fromRGB(30, 34, 60),
				Enum.Material.Glass,
				DETAIL
			)
			box(
				case,
				"Quill",
				Vector3.new(0.05, 0.8, 0.12),
				at(x + 0.05, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-18)),
				CREAM,
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
	cyl(feat, "Foot", 0.3, 2.3, CFrame.new(pos + Vector3.new(0, 0.15, 0)), C.darkWood, Enum.Material.Wood)
	cyl(
		feat,
		"Column",
		h - 0.6,
		1.7,
		CFrame.new(pos + Vector3.new(0, 0.3 + (h - 0.6) / 2, 0)),
		C.wood,
		Enum.Material.Wood
	)
	cyl(feat, "Cap", 0.3, 2.2, CFrame.new(pos + Vector3.new(0, h - 0.15, 0)), C.darkWood, Enum.Material.Wood)
	cyl(
		feat,
		"Cushion",
		0.2,
		1.5,
		CFrame.new(pos + Vector3.new(0, h + 0.1, 0)),
		Color3.fromRGB(110, 30, 30),
		Enum.Material.Fabric,
		DETAIL
	)
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
		C.brass,
		Enum.Material.Metal,
		DETAIL
	)
	printText(plate, Enum.NormalId.Front, {
		{ "NEW: " .. string.upper(def.name), Enum.Font.Bodoni, Color3.fromRGB(50, 30, 16), 0.05, 0.55 },
		{ def.price .. " keys", Enum.Font.Garamond, Color3.fromRGB(110, 24, 20), 0.55, 0.95 },
	}, nil, 160)
	return feat
end

local function poster(parent: Instance, cf: CFrame, w: number, h: number, bg: Color3, lines)
	-- framed poster flat on a wall; cf is the poster centre on the wall face, -Z pointing into the room
	local frame = box(
		parent,
		"PosterFrame",
		Vector3.new(w + 0.24, h + 0.24, 0.1),
		cf * CFrame.new(0, 0, -0.05),
		C.darkWood,
		Enum.Material.Wood,
		DETAIL
	)
	local paper = box(
		parent,
		"Poster",
		Vector3.new(w, h, 0.04),
		cf * CFrame.new(0, 0, -0.12),
		bg,
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	printText(paper, Enum.NormalId.Front, lines, bg, 40)
	return frame
end

local function buildWalls(shop: Instance)
	local deco = Kit.folder(shop, "WallDecor")
	local south = function(x, y)
		return facing(Vector3.new(x, y, R.z0), Vector3.zAxis)
	end
	local north = function(x, y)
		return facing(Vector3.new(x, y, R.z1), -Vector3.zAxis)
	end
	local ink = Color3.fromRGB(40, 28, 22)
	poster(deco, south(-19.2, FY + 7.4), 2.6, 3.6, Color3.fromRGB(120, 28, 24), {
		{ "LIGHT", Enum.Font.Bodoni, CREAM, 0.08, 0.28 },
		{ "YOUR", Enum.Font.Bodoni, CREAM, 0.28, 0.46 },
		{ "WAY", Enum.Font.Bodoni, CREAM, 0.46, 0.66 },
		{ "lanterns sold at the desk", Enum.Font.Garamond, Color3.fromRGB(240, 200, 150), 0.74, 0.9 },
	})
	poster(deco, south(-15.4, FY + 7.8), 2.4, 3.2, Color3.fromRGB(60, 112, 120), {
		{ "VISIT", Enum.Font.Antique, CREAM, 0.08, 0.24 },
		{ "THE", Enum.Font.Antique, CREAM, 0.24, 0.36 },
		{ "NATATORIUM", Enum.Font.Antique, CREAM, 0.36, 0.52 },
		{ "(do not swim)", Enum.Font.Garamond, Color3.fromRGB(210, 236, 236), 0.7, 0.86 },
	})
	poster(deco, north(-10.2, FY + 8.6), 2.2, 3.0, Color3.fromRGB(226, 214, 184), {
		{ "QUIET", Enum.Font.Bodoni, ink, 0.12, 0.36 },
		{ "PLEASE", Enum.Font.Bodoni, ink, 0.36, 0.56 },
		{ "the doors are listening", Enum.Font.Garamond, Color3.fromRGB(120, 30, 26), 0.7, 0.86 },
	})
	poster(deco, north(-7.6, FY + 9.2), 1.6, 2.2, Color3.fromRGB(40, 50, 64), {
		{ "PICK", Enum.Font.Antique, Color3.fromRGB(240, 200, 120), 0.1, 0.34 },
		{ "A", Enum.Font.Antique, Color3.fromRGB(240, 200, 120), 0.34, 0.52 },
		{ "DOOR", Enum.Font.Antique, Color3.fromRGB(240, 200, 120), 0.52, 0.76 },
	})
	-- thank-you plaque over the doorway, seen on the way out
	local plaque = box(
		deco,
		"Plaque",
		Vector3.new(6, 0.8, 0.08),
		facing(Vector3.new(DOOR.x0 - 0.04, DOOR.y1 + 0.9, DOOR_ZC), -Vector3.xAxis),
		Color3.fromRGB(24, 30, 26),
		Enum.Material.Wood,
		DETAIL
	)
	printText(
		plaque,
		Enum.NormalId.Front,
		{ { "THANK YOU  ·  MIND THE DOORS", Enum.Font.Bodoni, GOLD, 0.12, 0.88 } },
		nil,
		50
	)

	-- candle shelf on brackets (south wall, behind the counter)
	local sx, sy = -24.6, FY + 5.2
	box(deco, "CandleShelf", Vector3.new(4.2, 0.2, 1.0), Vector3.new(sx, sy, R.z0 + 0.5), C.midWood, Enum.Material.Wood)
	for _, dx in { -1.6, 1.6 } do
		box(
			deco,
			"Bracket",
			Vector3.new(0.15, 0.8, 0.7),
			Vector3.new(sx + dx, sy - 0.5, R.z0 + 0.38),
			C.steel,
			Enum.Material.Metal,
			DETAIL
		)
	end
	for i, spec in { { -1.6, 0.9 }, { -0.9, 0.6 }, { -0.25, 1.2 }, { 0.5, 0.7 }, { 1.2, 1.0 }, { 1.75, 0.5 } } do
		local p = Vector3.new(sx + spec[1], sy + 0.1, R.z0 + 0.5)
		cyl(
			deco,
			"Candle",
			spec[2],
			0.34,
			CFrame.new(p + Vector3.new(0, spec[2] / 2, 0)),
			Color3.fromRGB(236, 226, 204),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
		if i % 2 == 1 then
			Kit.anchor(deco, "Candle", p + Vector3.new(0, spec[2] + 0.12, 0))
		end
	end
	local label = box(
		deco,
		"ShelfLabel",
		Vector3.new(1.4, 0.3, 0.04),
		Vector3.new(sx, sy - 0.05, R.z0 + 1.02),
		CREAM,
		nil,
		DETAIL
	)
	printText(
		label,
		Enum.NormalId.Back,
		{ { "CANDLES  ·  3 KEYS", Enum.Font.Garamond, Color3.fromRGB(60, 30, 20), 0.1, 0.9 } },
		nil,
		120
	)
	return deco
end

local function buildStock(shop: Instance)
	local stock = Kit.folder(shop, "Stock")
	Furniture.metalRack(stock, CFrame.new(R.x0 + 1.1, FY, 62.6) * CFrame.Angles(0, math.rad(90), 0), 5.4, 6.4, 1.8)
	Kit.prop(stock, "BoxTaped", CFrame.new(-25.4, FY, 44.2) * CFrame.Angles(0, math.rad(80), 0))
	Kit.prop(stock, "BoxOpen", CFrame.new(-26.4, FY, 61.6) * CFrame.Angles(0, math.rad(75), 0), 0.9)
	-- plants: a palm in the corner by the door, a fern by the postcards
	Kit.prop(stock, "PalmVase", CFrame.new(R.x1 - 1.5, FY, R.z0 + 1.6), 0.9)
	Kit.prop(stock, "Fern", CFrame.new(R.x1 - 1.3, FY, R.z1 - 1.3), 1.1)
	return stock
end

------------------------------------------------------------------------------------------
-- Lighting
------------------------------------------------------------------------------------------
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
		SIGN_GLOW,
		Enum.Material.Neon,
		DETAIL
	)
	lens.Transparency = 0.2
	local emitter =
		box(parent, "SpotEmitter", Vector3.new(0.1, 0.1, 0.1), aim * CFrame.new(0, 0, -0.7), C.warm, nil, INVISIBLE)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 50
	spot.Range = range
	spot.Brightness = brightness
	spot.Color = C.warm
	spot.Shadows = false
	spot.Parent = emitter
end

local function buildLighting(shop: Instance)
	local lights = Kit.folder(shop, "Lighting")
	-- two green-enamel pendants over the counter
	Kit.bareBulb(lights, Vector3.new(COUNTER.x, CEIL - 4.2, 50.5), 16, 1.1, true, "shade", CEIL)
	Kit.bareBulb(lights, Vector3.new(COUNTER.x, CEIL - 4.2, 55.5), 16, 1.0, false, "shade", CEIL)
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
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 45.5), Vector3.new(-11, FY + 4, 45.6), 3, 16) -- featured lantern
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 47), Vector3.new(-17, FY + 3, 43.6), 1.6, 18) -- curio case
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 60), Vector3.new(-18.6, FY + 3, 62), 1.6, 18) -- staff picks
	trackSpot(lights, Vector3.new(tx, CEIL - 0.2, 61), Vector3.new(-10.5, FY + 3, 62.6), 1.4, 16) -- postcards
	-- soft fill so the corners aren't black
	local fill =
		box(lights, "Fill", Vector3.new(0.2, 0.2, 0.2), Vector3.new(-17, CEIL - 2, DOOR_ZC), C.warm, nil, INVISIBLE)
	Kit.pointLight(fill, 22, 0.35, false)
	return lights
end

------------------------------------------------------------------------------------------
function Shop.build(root: Instance)
	Kit.reseed(4242)
	local shop = Kit.folder(root, "Shop")

	buildStorefront(shop)
	buildCounter(shop)
	buildLanternWall(shop)
	buildCatalogue(shop, facing(Vector3.new(R.x0 + 1.15, FY, 44.5), Vector3.xAxis))
	buildBooksForSale(shop)
	buildPostcards(shop, Vector3.new(-10.4, FY, 62.4))
	buildVitrine(shop, facing(Vector3.new(-17.2, FY, R.z0 + 1.2), Vector3.zAxis), 7)
	buildFeatured(shop, Vector3.new(-10.8, FY, 45.4))
	buildWalls(shop)
	buildStock(shop)
	buildLighting(shop)

	-- the walkway rug, doorway to counter
	local rugX0, rugX1 = COUNTER.x + COUNTER.depth / 2 + 1.0, DOOR.x0 - 0.8
	local rugCx, rugW = (rugX0 + rugX1) / 2, rugX1 - rugX0
	box(
		shop,
		"Rug",
		Vector3.new(rugW, 0.08, 7.6),
		Vector3.new(rugCx, FY + 0.04, DOOR_ZC),
		Color3.fromRGB(104, 34, 30),
		Enum.Material.Carpet,
		{ CanCollide = false, CastShadow = false }
	)
	box(
		shop,
		"RugBorder",
		Vector3.new(rugW - 0.8, 0.02, 6.8),
		Vector3.new(rugCx, FY + 0.09, DOOR_ZC),
		Color3.fromRGB(176, 128, 70),
		Enum.Material.Carpet,
		DETAIL
	)
	box(
		shop,
		"RugField",
		Vector3.new(rugW - 1.2, 0.02, 6.4),
		Vector3.new(rugCx, FY + 0.1, DOOR_ZC),
		Color3.fromRGB(70, 28, 30),
		Enum.Material.Carpet,
		DETAIL
	)
	return shop
end

return Shop
