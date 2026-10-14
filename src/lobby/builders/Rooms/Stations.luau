--[[
	Reward stations in the reading hall (floor y = 0): three glowing floor rings, each with its object
	just behind it (positions in Layout.Stations, titles/colours in Shared.Rewards.Stations).

	World contract (read by RewardsService, Rewards.client, StationFX.client, ArchivistService):
		Lobby.Stations (Folder)
		  DailyStation     (Model) attrs Station = "Daily",      RingRadius
		  WheelStation     (Model) attrs Station = "Wheel",      RingRadius
		  ChallengeStation (Model) attrs Station = "Challenges", RingRadius
		    each: Ring (Part; Position = ring centre at floor level) + RingBand / RingHaze glow layers,
		          LabelAnchor (invisible Part) with BillboardGui "Label" (TextLabels Title, Subtitle)
		DailyStation.Chest (Model): Body, LockPlate, Glow (Neon, Transparency 1 until opened, PointLight
		    "GlowLight" disabled), Lid (Model; PrimaryPart LidHinge, an invisible part whose X axis is
		    the hinge line along the back-top edge: a positive rotation about it lifts the front).
		WheelStation.Rotor (Model; PrimaryPart Hub, centred on the axle, LookVector = the wheel's front
		    normal). Rotating Hub's frame by CFrame.Angles(0, 0, +a) turns the wheel a degrees CLOCKWISE
		    as seen from the front. Segment i (wedges carry attribute Segment = i) is centred
		    (i - 1) * SegmentAngle clockwise from 12 o'clock at rest angle 0.
		WheelStation.Pointer (Model; PrimaryPart PointerHinge, same orientation as the wheel; part
		    PointerTip at its tip). A negative rotation about the hinge's Z kicks the tip to the
		    viewer's right, the way the pegs push it when the wheel turns clockwise.
		ChallengeStation.Desk (Model): the archivist's counter, top at y 3.1; he stands behind it at
		    Layout.Stations.Challenges.npc (built by Npcs/Archivist), so the floor there stays clear.

	Everything except the chest body, the wheel's frame and the desk carcass is Kit.DETAIL.
	Roughly 360 parts in all (the chest and the wheel are built 1.7x their design size; same count).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Builders = script.Parent.Parent
local Kit = require(Builders.Kit)
local Layout = require(Builders.Layout)
local Rewards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rewards"))
local roomSignsModule = Builders:FindFirstChild("SignageRooms")
local SignageRooms = roomSignsModule and require(roomSignsModule)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local PLANKS = Enum.Material.WoodPlanks
local NEON = Enum.Material.Neon
local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball

local FLOOR = Layout.Rooms.Hall.y
local CREAM = Color3.fromRGB(236, 224, 198)
local INK = Color3.fromRGB(22, 14, 10)
local AGED_WOOD = Color3.fromRGB(62, 40, 26)
local LID_WOOD = Color3.fromRGB(74, 48, 30)
local IRON = Color3.fromRGB(34, 32, 30)
local BRASS = C.brass
local GOLD = Color3.fromRGB(212, 162, 64)
local WALNUT = Color3.fromRGB(66, 42, 28)
local PAPER = Color3.fromRGB(226, 214, 186)

local TITLE_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local TO_Z = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis (its X) turned to run along Z
local TO_Y = CFrame.Angles(0, 0, math.rad(90)) -- ... or upright

local Stations = {}

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
-- Cylinder whose axis is cf's X axis.
local function cyl(
	parent: Instance,
	name: string,
	length: number,
	dia: number,
	cf: CFrame,
	color: Color3,
	material,
	extra
)
	local part = box(parent, name, Vector3.new(length, dia, dia), cf, color, material, extra or DETAIL)
	part.Shape = CYLINDER
	return part
end

local function ball(parent: Instance, name: string, dia: number, cf, color: Color3, material, extra)
	local part = box(parent, name, Vector3.new(dia, dia, dia), cf, color, material, extra or DETAIL)
	part.Shape = BALL
	return part
end

-- Right triangle with its right angle at `corner`: one leg (length a) runs along unit `along`, the
-- other (length b) along unit `up`; extruded `thick` across the plane. (A WedgePart's right angle
-- is its (-Y, +Z) edge, with legs toward -Z (Size.Z) and +Y (Size.Y).)
local function tri(
	parent: Instance,
	name: string,
	corner: Vector3,
	along: Vector3,
	up: Vector3,
	a: number,
	b: number,
	thick: number,
	color: Color3,
	material
)
	local zAxis = -along
	local xAxis = up:Cross(zAxis)
	local centre = corner + up * (b / 2) + along * (a / 2)
	return Kit.wedge(
		parent,
		name,
		Vector3.new(thick, b, a),
		CFrame.fromMatrix(centre, xAxis, up, zAxis),
		color,
		material,
		DETAIL
	)
end

-- The glowing floor medallion: a bright neon rim with a soft haze just outside it, a dark inlay, a
-- second fainter band, tick marks between the bands and a keyhole in the middle. Every layer is
-- 0.012 thick and stacked 0.01 apart, all lifted RUG_CLEAR off the floor so they sit over the hall's
-- rugs (top 0.08) instead of under them.
-- The rim's outer edge is exactly `radius`, the same circle the client uses as the trigger (only the
-- faint haze reaches 0.25 past it). Ticks, band and keyhole grow with the radius (k = 1 at radius 3).
local TICK_WHITE = Color3.fromRGB(246, 242, 234)
local RUG_CLEAR = 0.08

local function ring(model: Model, centre: Vector3, radius: number, color: Color3, yaw: number): BasePart
	local dark = color:Lerp(Color3.fromRGB(12, 10, 10), 0.84)
	local k = radius / 3
	local function disc(name: string, dia: number, h: number, transparency: number, col: Color3, material)
		local part =
			cyl(model, name, 0.012, dia, CFrame.new(centre.X, FLOOR + RUG_CLEAR + h, centre.Z) * TO_Y, col, material)
		part.Transparency = transparency
		return part
	end
	disc("RingHaze", radius * 2 + 0.5, 0.02, 0.95, color, NEON)
	local rim = disc("Ring", radius * 2, 0.03, 0.35, color, NEON)
	-- the inside is a tinted wash over the neon rim disc below it; it has to hide most of that disc
	-- (at 0.82 the whole medallion read as one blown-out neon puddle), so only the ~0.4 rim band
	-- left showing round it burns bright
	local rimWidth = 0.3 * math.min(k, 1.35)
	disc("RingInlay", (radius - rimWidth) * 2, 0.04, 0, dark:Lerp(color, 0.18), Enum.Material.SmoothPlastic) -- opaque: only the rim glows
	local inner = radius * 0.64
	disc("RingBand", inner * 2, 0.05, 0.7, color, NEON)
	-- the band is a full neon disc too: a second inlay leaves only its ~0.13 edge showing
	disc("RingInlay", inner * 2 - 0.26 * k, 0.055, 0, dark:Lerp(color, 0.18), Enum.Material.SmoothPlastic)
	disc("RingCore", inner * 2 - 0.26 * k, 0.06, 0.97, color, NEON)

	-- twelve ticks between the bands, every third one longer (a clock face on the floor); white over
	-- the dimmed coloured glow so the face reads at a glance
	local outer = radius - rimWidth - 0.1
	local thin = math.min(k, 1.4)
	for i = 0, 11 do
		local long = i % 3 == 0
		local len = (outer - inner) * (if long then 0.7 else 0.4)
		local mid = (inner + outer) / 2
		local cf = CFrame.new(centre.X, FLOOR + RUG_CLEAR + 0.05, centre.Z)
			* CFrame.Angles(0, yaw + i * math.pi / 6, 0)
			* CFrame.new(0, 0, -mid)
		local mark = box(
			model,
			"RingTick",
			Vector3.new((if long then 0.15 else 0.1) * thin, 0.012, len),
			cf,
			TICK_WHITE,
			NEON,
			DETAIL
		)
		mark.Transparency = 0.05
	end
	-- keyhole, its slot pointing at whoever steps on from the front
	local key = CFrame.new(centre.X, FLOOR + RUG_CLEAR + 0.07, centre.Z) * CFrame.Angles(0, yaw, 0)
	cyl(model, "RingKeyhole", 0.012, 0.5 * k, key * CFrame.new(0, 0, -0.12 * k) * TO_Y, color, NEON).Transparency = 0.15
	box(
		model,
		"RingKeyhole",
		Vector3.new(0.2 * k, 0.012, 0.55 * k),
		key * CFrame.new(0, 0, 0.22 * k),
		color,
		NEON,
		DETAIL
	).Transparency =
		0.15

	-- a soft light so the ring tints the floor and anyone standing on it (no shadows); its reach
	-- follows the ring's size, the brightness stays low (StationFX breathes it 0.12..0.25)
	local point = Instance.new("Attachment")
	point.Name = "Glow"
	point.Parent = rim
	point.WorldPosition = Vector3.new(centre.X, FLOOR + 0.8, centre.Z)
	local light = Kit.pointLight(point, math.clamp(radius * 2.2, 8, 11), 0.15, false, color)
	light.Name = "RingLight"

	model:SetAttribute("RingRadius", radius)
	model.WorldPivot = CFrame.new(centre.X, FLOOR, centre.Z)
	return rim
end

-- Floating title + subtitle in the lobby's name-tag style (cream, stroked, unlit, short range).
-- With SignageRooms the title becomes floating holographic 3D letters ("Title3D", facing `facing`)
-- and the billboard keeps only its rule and subtitle, nudged down under them (the Title label stays,
-- invisible, for the scripts that look it up).
local function label(model: Model, pos: Vector3, title: string, subtitle: string, color: Color3, facing: Vector3)
	local anchor = box(model, "LabelAnchor", Vector3.new(0.4, 0.4, 0.4), pos, Color3.new(1, 1, 1), nil, INVISIBLE)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(250, 60)
	gui.LightInfluence = 0
	gui.MaxDistance = 45
	gui.Parent = anchor

	local head = Instance.new("TextLabel")
	head.Name = "Title"
	head.BackgroundTransparency = 1
	head.Size = UDim2.fromScale(1, 0.6)
	head.FontFace = TITLE_FONT
	head.TextScaled = true
	head.Text = title
	head.TextColor3 = CREAM
	head.TextStrokeColor3 = INK
	head.TextStrokeTransparency = 0.35
	head.Parent = gui

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.fromScale(0.5, 0.63)
	rule.Size = UDim2.new(0.42, 0, 0, 2)
	rule.BackgroundColor3 = color
	rule.BackgroundTransparency = 0.2
	rule.BorderSizePixel = 0
	rule.Parent = gui

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.7)
	sub.Size = UDim2.fromScale(1, 0.3)
	sub.Font = Enum.Font.SpecialElite
	sub.TextScaled = true
	sub.Text = subtitle
	sub.TextColor3 = color:Lerp(CREAM, 0.45)
	sub.TextStrokeColor3 = INK
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui

	if SignageRooms then
		local flat = Vector3.new(facing.X, 0, facing.Z)
		SignageRooms.holoTitle(model, pos + Vector3.new(0, 0.25, 0), flat.Unit, title, color)
		head.TextTransparency = 1
		head.TextStrokeTransparency = 1
		gui.StudsOffset = Vector3.new(0, -0.9, 0)
	end
	return anchor
end

-- Yaw for the ring's keyhole so its round end points at the station's object.
local function yawToward(from: Vector3, to: Vector3): number
	local d = to - from
	return math.atan2(-d.X, -d.Z)
end

local function stationModel(parent: Instance, name: string, station: string): Model
	local model = Kit.folder(parent, name)
	model:SetAttribute("Station", station)
	return model
end

------------------------------------------------------------------------------------------
-- Daily: an old iron-banded treasure chest with a barrel lid
------------------------------------------------------------------------------------------
-- Designed at unit scale (body 2.2 x 1.4 x 1.0) and built CHEST_SCALE times bigger: every offset
-- goes through at() and every size through sz() / the scaled ball and cylinder helpers below.
local CHEST_SCALE = 1.7
local CW, CD, CH = 2.2, 1.4, 1.0 -- body width (X), depth (Z), height (unit scale)
local FEET = 0.16
local LR = CD / 2 -- the barrel lid's radius
-- built size: 3.74 wide (CW) x 2.38 deep (CD), 3.16 to the top of the closed lid

local function buildChest(parent: Instance, base: CFrame): Model
	local S = CHEST_SCALE
	local model = Kit.folder(parent, "Chest")
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S, z * S)
	end
	local function sz(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * S
	end
	local function sball(p: Instance, name: string, dia: number, cf: CFrame, color: Color3, material)
		return ball(p, name, dia * S, cf, color, material)
	end
	local function scyl(p: Instance, name: string, length: number, dia: number, cf: CFrame, color: Color3, material)
		return cyl(p, name, length * S, dia * S, cf, color, material)
	end
	local top = FEET + CH

	-- carcass on four iron ball feet
	local body = box(model, "Body", sz(CW, CH, CD), at(0, FEET + CH / 2, 0), AGED_WOOD, PLANKS)
	model.PrimaryPart = body
	for _, sx in { -1, 1 } do
		for _, sz2 in { -1, 1 } do
			sball(model, "Foot", 0.24, at(sx * (CW / 2 - 0.14), 0.12, sz2 * (CD / 2 - 0.14)), IRON, METAL)
			-- brass corner caps, top and bottom
			for _, y in { FEET + 0.15, top - 0.15 } do
				box(
					model,
					"Corner",
					sz(0.18, 0.3, 0.18),
					at(sx * (CW / 2 - 0.07), y, sz2 * (CD / 2 - 0.07)),
					BRASS,
					METAL,
					DETAIL
				)
			end
		end
	end
	-- plank seams on the front, iron bands round the bottom and the rim, straps front and back
	for _, y in { FEET + CH * 0.36, FEET + CH * 0.68 } do
		box(model, "Seam", sz(CW - 0.4, 0.025, 0.02), at(0, y, -CD / 2 - 0.005), INK, WOOD, DETAIL)
	end
	box(model, "Band", sz(CW + 0.04, 0.12, CD + 0.04), at(0, FEET + 0.09, 0), IRON, METAL, DETAIL)
	box(model, "Band", sz(CW + 0.04, 0.1, CD + 0.04), at(0, top - 0.06, 0), IRON, METAL, DETAIL)
	for _, sx in { -1, 1 } do
		local x = sx * CW * 0.31
		for _, sz2 in { -1, 1 } do
			box(model, "Strap", sz(0.17, CH, 0.04), at(x, FEET + CH / 2, sz2 * (CD / 2 + 0.02)), IRON, METAL, DETAIL)
		end
		for _, y in { FEET + 0.3, FEET + 0.62 } do
			sball(model, "Rivet", 0.07, at(x, y, -CD / 2 - 0.045), BRASS, METAL)
		end
		-- carrying handle on each end: two brackets and an iron bar
		local hx = sx * (CW / 2 + 0.03)
		for _, sz2 in { -1, 1 } do
			box(model, "HandleBracket", sz(0.06, 0.14, 0.06), at(hx, FEET + CH * 0.62, sz2 * 0.24), IRON, METAL, DETAIL)
		end
		scyl(model, "Handle", 0.54, 0.07, at(sx * (CW / 2 + 0.08), FEET + CH * 0.58, 0) * TO_Z, IRON, METAL)
	end

	-- brass lock plate with a keyhole
	local plateY = top - 0.32
	local plate = box(model, "LockPlate", sz(0.46, 0.5, 0.04), at(0, plateY, -CD / 2 - 0.04), BRASS, METAL, DETAIL)
	plate.Reflectance = 0.05
	sball(model, "Keyhole", 0.1, at(0, plateY + 0.02, -CD / 2 - 0.055), INK, Enum.Material.SmoothPlastic)
	box(
		model,
		"Keyhole",
		sz(0.05, 0.13, 0.02),
		at(0, plateY - 0.06, -CD / 2 - 0.065),
		INK,
		Enum.Material.SmoothPlastic,
		DETAIL
	)

	-- the hoard inside (only seen with the lid up): velvet, a mound of gold, loose coins, a key
	box(
		model,
		"Lining",
		sz(CW - 0.2, 0.03, CD - 0.2),
		at(0, top + 0.015, 0),
		Color3.fromRGB(70, 18, 22),
		Enum.Material.Fabric,
		DETAIL
	)
	for _, spec in { { -0.35, 0.05, 0.62 }, { 0.2, -0.1, 0.56 }, { 0.55, 0.15, 0.44 } } do
		sball(model, "Hoard", spec[3], at(spec[1], top - spec[3] * 0.22, spec[2]), GOLD, METAL)
	end
	for i, spec in { { -0.8, -0.3 }, { -0.05, 0.38 }, { 0.75, -0.3 }, { 0.4, 0.4 }, { -0.6, 0.35 } } do
		scyl(
			model,
			"Coin",
			0.03,
			0.18,
			at(spec[1], top + 0.05, spec[2]) * CFrame.Angles(0, i, math.rad(80 + i * 3)),
			GOLD,
			METAL
		)
	end
	local glow = box(
		model,
		"Glow",
		sz(CW - 0.5, 0.3, CD - 0.5),
		at(0, top + 0.22, 0),
		Color3.fromRGB(255, 196, 92),
		NEON,
		DETAIL
	)
	glow.Transparency = 1
	local light = Kit.pointLight(glow, 8 * S, 2.2, false, Color3.fromRGB(255, 190, 100))
	light.Name = "GlowLight"
	light.Enabled = false

	-- barrel lid: five staves around an axis along the middle of the body's top edge, iron
	-- bands over it and a hasp hanging down the front; all of it in Model "Lid"
	local lid = Kit.folder(model, "Lid")
	local axis = at(0, top, 0)
	local chord = 2 * LR * math.sin(math.rad(18)) * 1.06
	for k = -2, 2 do
		local a = math.rad(k * 36)
		local stave = axis * CFrame.Angles(a, 0, 0)
		local function on(x: number, y: number): CFrame
			return stave * CFrame.new(x * S, y * S, 0)
		end
		box(
			lid,
			"Stave",
			sz(CW + 0.04, 0.12, chord),
			on(0, LR - 0.06),
			if k % 2 == 0 then LID_WOOD else AGED_WOOD,
			PLANKS,
			DETAIL
		)
		-- end caps: one radial slab per stave closes the half-round ends
		for _, sx in { -1, 1 } do
			box(
				lid,
				"LidEnd",
				sz(0.1, LR - 0.04, chord),
				on(sx * (CW / 2 - 0.06), (LR - 0.04) / 2),
				AGED_WOOD,
				PLANKS,
				DETAIL
			)
		end
		for _, sx in { -1, 1 } do
			local band =
				box(lid, "LidBand", sz(0.18, 0.05, chord * 1.02), on(sx * CW * 0.31, LR + 0.015), IRON, METAL, DETAIL)
			if math.abs(k) <= 1 then
				sball(lid, "Rivet", 0.07, band.CFrame * CFrame.new(0, 0.03 * S, 0), BRASS, METAL)
			end
		end
	end
	-- brass edging along the lid's front and back bottom edges, and the hasp
	for _, sz2 in { -1, 1 } do
		box(lid, "LidEdge", sz(CW + 0.08, 0.08, 0.06), at(0, top + 0.04, sz2 * (LR - 0.02)), BRASS, METAL, DETAIL)
	end
	box(lid, "Hasp", sz(0.2, 0.36, 0.04), at(0, top - 0.1, -CD / 2 - 0.075), IRON, METAL, DETAIL)
	sball(lid, "HaspRing", 0.1, at(0, top - 0.24, -CD / 2 - 0.1), IRON, METAL)
	-- hinge line along the back-top edge of the body (X axis)
	local hinge = box(lid, "LidHinge", sz(0.2, 0.2, 0.2), at(0, top, CD / 2), Color3.new(1, 1, 1), nil, INVISIBLE)
	lid.PrimaryPart = hinge
	lid.WorldPivot = hinge.CFrame

	-- keep people from walking through the lid (the staves are non-colliding details)
	box(model, "LidCollider", sz(CW, LR, CD), at(0, top + LR / 2, 0), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	return model
end

local function buildDaily(parent: Instance)
	local spec = Layout.Stations.Daily
	local info = Rewards.Stations.Daily
	local model = stationModel(parent, "DailyStation", "Daily")
	local base = spec.object
	local yaw = yawToward(spec.ring, base.Position)
	ring(model, spec.ring, spec.radius, info.color, yaw)
	buildChest(model, base)
	-- over the chest (lid top ~3.2): high enough to clear the lid swinging open and the coins rising
	-- the 3D title turns toward the left of the stair foot (0, 24): it reads from the stair and the
	-- walkway, and its far end stays ~0.8 clear of the right pillar at (20, 17.5) beside the chest
	local labelPos = (base * CFrame.new(0, 5.6, 0)).Position
	label(model, labelPos, info.title, "free every day", info.color, Vector3.new(0, labelPos.Y, 24) - labelPos)
	return model
end

------------------------------------------------------------------------------------------
-- Wheel of Fate
------------------------------------------------------------------------------------------
-- Designed at unit scale and built WHEEL_SCALE times bigger. Everything above the plinth is then
-- lowered by WHEEL_DROP so the crest stays under the ceiling (16): the wheel (10.2 across) clears
-- the plinth by ~0.5, the top beam tops out at ~12.9, the finials ~13.7 and the crest ~14.3.
local WHEEL_SCALE = 1.7
local WHEEL_DROP = 1.0
local CREST_SCALE = 1.25 -- the little brass door on top stays smaller, under the title
local AXLE_Y = 4.2 -- (unit scale; world ~6.14)
local SEG_R = 2.55 -- segment wedges reach this radius at their corners
local PEG_R = 2.72

local function buildWheel(parent: Instance)
	local spec = Layout.Stations.Wheel
	local info = Rewards.Stations.Wheel
	local model = stationModel(parent, "WheelStation", "Wheel")
	local base = spec.object
	local yaw = yawToward(spec.ring, base.Position)
	ring(model, spec.ring, spec.radius, info.color, yaw)
	local S = WHEEL_SCALE
	-- at(): above the plinth (dropped); floor(): standing on the floor (plinth, shoes, braces)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S - WHEEL_DROP, z * S)
	end
	local function floor(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S, z * S)
	end
	local function sz(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * S
	end
	local function sball(p: Instance, name: string, dia: number, cf: CFrame, color: Color3, material)
		return ball(p, name, dia * S, cf, color, material)
	end
	local function scyl(
		p: Instance,
		name: string,
		length: number,
		dia: number,
		cf: CFrame,
		color: Color3,
		material,
		extra
	)
		return cyl(p, name, length * S, dia * S, cf, color, material, extra)
	end

	-- frame: plinth, two legs, an axle beam behind the wheel and a top beam that holds the pointer
	local frame = Kit.folder(model, "Frame")
	box(frame, "Plinth", sz(6.9, 0.3, 1.9), floor(0, 0.15, 0.3), C.darkWood, WOOD)
	box(frame, "PlinthTrim", sz(6.9, 0.06, 0.06), floor(0, 0.3, -0.66), BRASS, METAL, DETAIL)
	local legBottom = 0.3 * S
	local legTop = 8.2 * S - WHEEL_DROP -- the top beam's upper face
	for _, sx in { -1, 1 } do
		box(
			frame,
			"Leg",
			Vector3.new(0.38 * S, legTop - legBottom, 0.38 * S),
			base * CFrame.new(sx * 3.15 * S, (legTop + legBottom) / 2, 0.55 * S),
			C.darkWood,
			WOOD
		)
		box(frame, "LegShoe", sz(0.56, 0.22, 0.56), floor(sx * 3.15, 0.41, 0.55), BRASS, METAL, DETAIL)
		box(frame, "LegCollar", sz(0.48, 0.14, 0.48), at(sx * 3.15, AXLE_Y, 0.55), BRASS, METAL, DETAIL)
		sball(frame, "Finial", 0.42, at(sx * 3.15, 8.42, 0.55), BRASS, METAL)
		-- a raked brace from the plinth's back to each leg
		box(
			frame,
			"Brace",
			sz(0.18, 2.6, 0.18),
			floor(sx * 2.4, 1.3, 0.55) * CFrame.Angles(0, 0, sx * math.rad(-28)),
			C.darkWood,
			WOOD,
			DETAIL
		)
	end
	box(frame, "AxleBeam", sz(6.3, 0.36, 0.3), at(0, AXLE_Y, 0.55), C.darkWood, WOOD)
	box(frame, "TopBeam", sz(6.8, 0.34, 0.44), at(0, 8.0, 0.55), C.darkWood, WOOD)
	box(frame, "TopTrim", sz(6.8, 0.06, 0.04), at(0, 8.0, 0.32), BRASS, METAL, DETAIL)
	scyl(frame, "Axle", 0.6, 0.3, at(0, AXLE_Y, 0.3) * TO_Z, BRASS, METAL)
	-- a little brass door on top of the frame (standing on the top beam, scaled a bit less)
	local crestBase = at(0, 8.17, 0.55) -- top face of the top beam
	local CS = CREST_SCALE
	local function crest(x: number, y: number, z: number): CFrame
		return crestBase * CFrame.new(x * CS, (y - 8.17) * CS, (z - 0.55) * CS)
	end
	box(frame, "Crest", Vector3.new(0.7, 0.8, 0.08) * CS, crest(0, 8.57, 0.55), BRASS, METAL, DETAIL)
	cyl(frame, "CrestArch", 0.08 * CS, 0.7 * CS, crest(0, 8.97, 0.55) * TO_Z, BRASS, METAL)
	box(
		frame,
		"CrestDoor",
		Vector3.new(0.42, 0.62, 0.02) * CS,
		crest(0, 8.6, 0.5),
		Color3.fromRGB(40, 26, 20),
		WOOD,
		DETAIL
	)
	ball(frame, "CrestKnob", 0.07 * CS, crest(0.12, 8.55, 0.48), BRASS, METAL)
	-- bracket reaching forward from the top beam to the pointer
	box(frame, "PointerArm", sz(0.3, 0.22, 1.3), at(0, 7.9, -0.05), C.darkWood, WOOD, DETAIL)

	-- rotor: everything that turns
	local rotor = Kit.folder(model, "Rotor")
	local hubCF = at(0, AXLE_Y, -0.2)
	local hub = box(rotor, "Hub", Vector3.new(0.4, 0.4, 0.4), hubCF, Color3.new(1, 1, 1), nil, INVISIBLE)
	rotor.PrimaryPart = hub
	rotor.WorldPivot = hubCF
	local function h(x: number, y: number, z: number): CFrame
		return hubCF * CFrame.new(x * S, y * S, z * S)
	end
	-- direction from the centre at `deg` clockwise from 12 o'clock (as seen from the front, +X is
	-- the viewer's LEFT, so clockwise heads toward -X), and the clockwise tangent there
	local function dir(deg: number): Vector3
		local r = math.rad(deg)
		return Vector3.new(-math.sin(r), math.cos(r), 0)
	end
	local function tangent(deg: number): Vector3
		local r = math.rad(deg)
		return Vector3.new(-math.cos(r), -math.sin(r), 0)
	end
	local function world(v: Vector3): Vector3
		return hubCF:VectorToWorldSpace(v)
	end
	local function onFace(r: number, deg: number, z: number): CFrame
		-- frame on the wheel face at radius r (unit scale): up = outward, front (-Z) = toward the viewer
		local up = world(dir(deg))
		local back = world(Vector3.new(0, 0, 1))
		local pos = (hubCF * CFrame.new((dir(deg) * r + Vector3.new(0, 0, z)) * S)).Position
		return CFrame.fromMatrix(pos, up:Cross(back), up)
	end

	scyl(rotor, "Backing", 0.2, 6.0, h(0, 0, 0.15) * TO_Z, C.darkWood, WOOD, {}) -- solid: you can't walk through it
	scyl(rotor, "Rim", 0.1, 5.72, h(0, 0, 0) * TO_Z, BRASS, METAL)

	local seg = Rewards.SegmentAngle
	local half = seg / 2
	local a, b = SEG_R * math.cos(math.rad(half)), SEG_R * math.sin(math.rad(half))
	for i, s in Rewards.Wheel do
		local centreDeg = (i - 1) * seg
		local corner = (hubCF * CFrame.new((dir(centreDeg) * a + Vector3.new(0, 0, -0.08)) * S)).Position
		for _, side in { 1, -1 } do
			local w = tri(
				rotor,
				"Segment",
				corner,
				world(-dir(centreDeg)),
				world(tangent(centreDeg) * side),
				a * S,
				b * S,
				0.06 * S,
				s.color,
				WOOD
			)
			w:SetAttribute("Segment", i)
		end
		-- a little arched door on each segment, in a darker shade of its colour
		local doorCF = onFace(1.2, centreDeg, -0.12)
		local doorColor = s.color:Lerp(Color3.new(0, 0, 0), 0.45)
		box(rotor, "SegDoor", sz(0.34, 0.5, 0.03), doorCF, doorColor, WOOD, DETAIL)
		scyl(rotor, "SegDoorArch", 0.03, 0.34, doorCF * CFrame.new(0, 0.25 * S, 0) * TO_Z, doorColor, WOOD)
		sball(rotor, "SegKnob", 0.07, doorCF * CFrame.new(-0.09 * S, -0.04 * S, -0.03 * S), BRASS, METAL)
		-- the prize, upright when the segment is at the top
		local tag = box(rotor, "SegLabel", sz(1.1, 0.42, 0.02), onFace(2.0, centreDeg, -0.12), C.paint, nil, INVISIBLE)
		local gui, text = Kit.surfaceText(tag, Enum.NormalId.Front, s.label, nil, CREAM)
		gui.PixelsPerStud = 72 -- ~135 x 51 px per label: as crisp as before at the bigger size
		gui.LightInfluence = 0.25
		gui.Brightness = 1.4
		text.FontFace = TITLE_FONT
		text.TextStrokeColor3 = INK
		text.TextStrokeTransparency = 0.4
		tag:SetAttribute("Segment", i)

		-- brass divider on the boundary after this segment, a peg at its rim end, a stud mid-segment
		local edgeDeg = centreDeg + half
		box(
			rotor,
			"Divider",
			sz(0.06, SEG_R - 0.6, 0.05),
			onFace((SEG_R + 0.6) / 2, edgeDeg, -0.13),
			BRASS,
			METAL,
			DETAIL
		)
		scyl(rotor, "Peg", 0.3, 0.12, onFace(PEG_R, edgeDeg, -0.15) * TO_Z, BRASS, METAL)
		sball(rotor, "Stud", 0.1, onFace(PEG_R, centreDeg, -0.06), BRASS, METAL)
	end
	-- hub: brass boss, dark cap, keyhole
	scyl(rotor, "Boss", 0.12, 1.1, h(0, 0, -0.15) * TO_Z, BRASS, METAL)
	scyl(rotor, "BossCap", 0.06, 0.75, h(0, 0, -0.22) * TO_Z, C.darkWood, WOOD)
	sball(rotor, "BossKey", 0.16, h(0, 0.06, -0.25), INK, Enum.Material.SmoothPlastic)
	box(rotor, "BossKey", sz(0.07, 0.18, 0.02), h(0, -0.06, -0.26), INK, Enum.Material.SmoothPlastic, DETAIL)

	-- pointer: a door-knocker ring on the hinge with a brass arrow hanging down to the pegs
	local pointer = Kit.folder(model, "Pointer")
	local pivot = at(0, 7.72, -0.62)
	local pivotPart =
		box(pointer, "PointerHinge", Vector3.new(0.2, 0.2, 0.2), pivot, Color3.new(1, 1, 1), nil, INVISIBLE)
	pointer.PrimaryPart = pivotPart
	pointer.WorldPivot = pivot
	scyl(pointer, "Knocker", 0.08, 0.42, pivot * TO_Z, BRASS, METAL)
	scyl(pointer, "KnockerEye", 0.09, 0.22, pivot * TO_Z, INK, Enum.Material.SmoothPlastic)
	box(pointer, "Shaft", sz(0.1, 0.45, 0.06), pivot * CFrame.new(0, -0.38 * S, 0), BRASS, METAL, DETAIL)
	local tipTop = (pivot * CFrame.new(0, -0.58 * S, 0)).Position
	local down, right = -pivot.UpVector, pivot.RightVector
	for _, side in { 1, -1 } do
		tri(pointer, "Arrow", tipTop, down, right * side, 0.3 * S, 0.17 * S, 0.06 * S, BRASS, METAL)
	end
	local tipCF = pivot * CFrame.new(0, -0.86 * S, 0)
	box(pointer, "PointerTip", Vector3.new(0.05, 0.05, 0.05), tipCF, BRASS, nil, INVISIBLE)

	-- title just above the top beam, in front of the crest (y 13.6: a 60 px billboard stays under the
	-- 16-stud ceiling out to its 45-stud MaxDistance and clears the pointer from the ring),
	-- and 2.4 in front of the frame so the top beam and crest never cut into it
	label(model, (base * CFrame.new(0, 13.6, -2.4)).Position, info.title, "spin your luck", info.color, base.LookVector)
	return model
end

------------------------------------------------------------------------------------------
-- Challenges: the archivist's counter, ledger, ink, cards, bell, candle and a card catalogue
------------------------------------------------------------------------------------------
local DESK_TOP = 3.1

local function buildChallenges(parent: Instance)
	local spec = Layout.Stations.Challenges
	local info = Rewards.Stations.Challenges
	local model = stationModel(parent, "ChallengeStation", "Challenges")
	local base = spec.object
	local yaw = yawToward(spec.ring, base.Position)
	ring(model, spec.ring, spec.radius, info.color, yaw)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	local desk = Kit.folder(model, "Desk")
	-- carcass: top, front panel facing the ring, two sides, a shelf inside; the back stays open
	box(desk, "DeskTop", Vector3.new(3.3, 0.12, 1.3), at(0, DESK_TOP - 0.06, 0), WALNUT, WOOD)
	box(
		desk,
		"FrontPanel",
		Vector3.new(3.1, DESK_TOP - 0.12, 0.1),
		at(0, (DESK_TOP - 0.12) / 2, -0.5),
		C.darkWood,
		WOOD
	)
	for _, sx in { -1, 1 } do
		box(
			desk,
			"Side",
			Vector3.new(0.1, DESK_TOP - 0.12, 1.1),
			at(sx * 1.5, (DESK_TOP - 0.12) / 2, 0.05),
			C.darkWood,
			WOOD
		)
		box(desk, "Panel", Vector3.new(1.2, 1.9, 0.04), at(sx * 0.72, 1.5, -0.57), WALNUT, WOOD, DETAIL)
	end
	box(desk, "Shelf", Vector3.new(2.9, 0.06, 1.0), at(0, 1.2, 0.05), C.darkWood, WOOD, DETAIL)
	box(desk, "KickPlate", Vector3.new(3.1, 0.24, 0.03), at(0, 0.12, -0.565), BRASS, METAL, DETAIL)
	box(desk, "Moulding", Vector3.new(3.36, 0.1, 0.1), at(0, DESK_TOP - 0.17, -0.6), WALNUT, WOOD, DETAIL)
	box(
		desk,
		"Blotter",
		Vector3.new(2.5, 0.01, 0.9),
		at(0, DESK_TOP + 0.005, 0),
		Color3.fromRGB(34, 52, 40),
		Enum.Material.Fabric,
		DETAIL
	)
	local plate = box(desk, "Nameplate", Vector3.new(1.4, 0.3, 0.02), at(0, 2.62, -0.56), BRASS, METAL, DETAIL)
	Kit.surfaceText(
		plate,
		Enum.NormalId.Front,
		string.upper(Rewards.ArchivistName) .. " - ARCHIVIST",
		Enum.Font.SpecialElite,
		INK
	)

	local topY = DESK_TOP + 0.01
	-- the ledger: open, a little turned toward the customer, a ribbon trailing off the front
	local ledger = at(-0.2, topY, -0.05) * CFrame.Angles(0, math.rad(6), 0)
	box(
		desk,
		"LedgerCover",
		Vector3.new(1.5, 0.04, 1.0),
		ledger * CFrame.new(0, 0.02, 0),
		Color3.fromRGB(92, 30, 26),
		Enum.Material.Leather,
		DETAIL
	)
	box(
		desk,
		"LedgerSpine",
		Vector3.new(0.1, 0.07, 1.0),
		ledger * CFrame.new(0, 0.05, 0),
		Color3.fromRGB(70, 22, 20),
		Enum.Material.Leather,
		DETAIL
	)
	for _, sx in { -1, 1 } do
		local page = ledger * CFrame.new(sx * 0.37, 0.07, 0) * CFrame.Angles(0, 0, sx * math.rad(-3))
		box(desk, "Page", Vector3.new(0.68, 0.06, 0.92), page, PAPER, Enum.Material.SmoothPlastic, DETAIL)
		for line = 1, 4 do
			box(
				desk,
				"Ink",
				Vector3.new(0.5 - (line % 2) * 0.12, 0.004, 0.025),
				page * CFrame.new(-0.02, 0.032, -0.3 + line * 0.14),
				Color3.fromRGB(40, 34, 40),
				Enum.Material.SmoothPlastic,
				DETAIL
			)
		end
	end
	box(
		desk,
		"Ribbon",
		Vector3.new(0.05, 0.006, 0.5),
		ledger * CFrame.new(0.32, 0.104, -0.2),
		Color3.fromRGB(150, 28, 30),
		Enum.Material.Fabric,
		DETAIL
	)
	box(
		desk,
		"Ribbon",
		Vector3.new(0.05, 0.006, 0.26),
		ledger * CFrame.new(0.34, 0.006, -0.62) * CFrame.Angles(0, math.rad(-10), 0),
		Color3.fromRGB(150, 28, 30),
		Enum.Material.Fabric,
		DETAIL
	)

	-- inkwell and quill
	local well = at(1.0, topY, 0.2)
	cyl(
		desk,
		"Inkwell",
		0.18,
		0.24,
		well * CFrame.new(0, 0.09, 0) * TO_Y,
		Color3.fromRGB(24, 28, 40),
		Enum.Material.Glass
	)
	cyl(desk, "InkwellCap", 0.05, 0.13, well * CFrame.new(0, 0.2, 0) * TO_Y, BRASS, METAL)
	local quill = well * CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-22), 0, math.rad(-18))
	box(desk, "Quill", Vector3.new(0.025, 0.75, 0.025), quill * CFrame.new(0, 0.3, 0), PAPER, nil, DETAIL)
	box(
		desk,
		"QuillVane",
		Vector3.new(0.012, 0.45, 0.13),
		quill * CFrame.new(0, 0.48, 0.04),
		Color3.fromRGB(214, 208, 196),
		Enum.Material.Fabric,
		DETAIL
	)

	-- a stack of index cards, and a brass service bell
	for i = 1, 4 do
		box(
			desk,
			"Card",
			Vector3.new(0.5, 0.02, 0.32),
			at(0.95, topY + 0.01 + (i - 1) * 0.02, -0.35) * CFrame.Angles(0, math.rad((i * 37) % 17 - 8), 0),
			if i == 4 then Color3.fromRGB(240, 232, 210) else PAPER,
			Enum.Material.SmoothPlastic,
			DETAIL
		)
	end
	local bell = at(-1.25, topY, -0.38)
	cyl(desk, "BellBase", 0.04, 0.38, bell * CFrame.new(0, 0.02, 0) * TO_Y, C.darkWood, WOOD)
	ball(desk, "Bell", 0.32, bell * CFrame.new(0, 0.04, 0), BRASS, METAL).Reflectance = 0.1
	ball(desk, "BellPlunger", 0.06, bell * CFrame.new(0, 0.22, 0), BRASS, METAL)

	-- candle on a brass dish; AtmosFX dresses the "Candle" anchor with a flame and a soft light
	local candle = at(-1.25, topY, 0.35)
	cyl(desk, "CandleDish", 0.04, 0.36, candle * CFrame.new(0, 0.02, 0) * TO_Y, BRASS, METAL)
	cyl(
		desk,
		"Candle",
		0.5,
		0.13,
		candle * CFrame.new(0, 0.29, 0) * TO_Y,
		Color3.fromRGB(236, 226, 200),
		Enum.Material.SmoothPlastic
	)
	Kit.anchor(desk, "Candle", candle * CFrame.new(0, 0.58, 0), nil, { Range = 7 })

	-- the card catalogue beside the desk: 3 x 4 little drawers with brass pulls
	local cab = at(2.35, 0, 0.1)
	box(desk, "Catalogue", Vector3.new(1.2, 2.5, 1.1), cab * CFrame.new(0, 1.25, 0), WALNUT, WOOD)
	box(desk, "CatalogueTop", Vector3.new(1.3, 0.08, 1.2), cab * CFrame.new(0, 2.54, 0), C.darkWood, WOOD, DETAIL)
	for col = -1, 1 do
		for row = 0, 3 do
			local dcf = cab * CFrame.new(col * 0.37, 0.65 + row * 0.5, -0.47)
			box(desk, "Drawer", Vector3.new(0.33, 0.44, 0.04), dcf, C.midWood, WOOD, DETAIL)
			box(desk, "Pull", Vector3.new(0.12, 0.05, 0.04), dcf * CFrame.new(0, -0.08, -0.03), BRASS, METAL, DETAIL)
			box(desk, "Tag", Vector3.new(0.14, 0.07, 0.01), dcf * CFrame.new(0, 0.08, -0.025), PAPER, nil, DETAIL)
		end
	end
	-- a couple of box files on top of it
	for i, spec2 in { { -0.2, 0.42, Color3.fromRGB(70, 60, 44) }, { 0.22, 0.36, Color3.fromRGB(52, 44, 34) } } do
		box(
			desk,
			"BoxFile",
			Vector3.new(0.34, spec2[2], 0.8),
			cab * CFrame.new(spec2[1], 2.58 + spec2[2] / 2, 0) * CFrame.Angles(0, math.rad(i * 4), 0),
			spec2[3],
			Enum.Material.Cardboard,
			DETAIL
		)
	end

	-- over the desk, well above his name tag (head ~4.6 + 2.0, hidden past 30 studs) and the whisper
	-- bubble (head + 2.6), so the three never stack on screen
	label(
		model,
		(base * CFrame.new(0, 10, 0)).Position,
		info.title,
		Rewards.ArchivistName .. " keeps the ledger",
		info.color,
		base.LookVector
	)
	return model
end

------------------------------------------------------------------------------------------
function Stations.build(root: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Stations"
	folder.Parent = root
	buildDaily(folder)
	buildWheel(folder)
	buildChallenges(folder)
	return folder
end

return Stations
