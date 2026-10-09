--[[
	SignageRooms: the lobby's room and station signs, built from the Signage 3D kit (text3D, panel,
	ledRow, bulbs, halos) and tagged for client/SignFX. Each builder takes the sign's centre ON the
	mounting surface and the surface's outward normal `n` (the direction the sign faces).

	  readingRoom(parent, centre, n)     foyer, over the grand stair: a theatre-marquee lightbox in
	                                     dark bronze, warm bulbs all round, brass-capped letters in
	                                     silhouette, chevrons chasing down to the stair
	  theDoors(parent, centre, n)        reading hall, over the arch: blackened steel, red neon letters
	                                     that won't behave, a red LED run, down-chevrons either side
	  workshopBoard(parent, centre, n)   reading hall, over the workshop doorway: carved walnut with
	                                     brass-capped letters, brass bosses and arrow, a picture lamp
	  workshopHanging(parent, top, n, w, h, drop)  inside the workshop: a painted plank on chains
	                                     that swings a little (the chains go in the model too)
	  benchLanterns(parent, cf)          workshop bench: painted green board, cream letters, embers
	  shopLanterns(parent, centre, n)    gift shop lantern wall: black lacquer, gold letters, violet rim
	  holoTitle(parent, centre, n, str, color)  reward stations: floating holographic letters
	  recordsHeader(parent, centre, n)   foyer leaderboard: carved header, brass letters

	The view frame of every sign: X to the viewer's right, Y up, +Z toward the viewer; its origin is
	the sign's front plane. All parts are Kit.DETAIL; lights never cast shadows.
]]
local Kit = require(script.Parent.Kit)
local Signage = require(script.Parent.Signage)

local SignageRooms = {}

local DETAIL = Kit.DETAIL
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic

local WARM = Color3.fromRGB(255, 184, 122)

-- The view frame for a sign facing `n`, its front plane `out` studs proud of `centre`.
local function viewAt(centre: Vector3, n: Vector3, out: number): CFrame
	local p = centre + n * out
	return CFrame.lookAt(p, p - n)
end

-- A down-pointing chevron (tip at u, v) of two bars; Step attribute for the SignFX chase.
local function chevron(
	parent: Instance,
	view: CFrame,
	u: number,
	v: number,
	z: number,
	arm: number,
	thick: number,
	depth: number,
	color: Color3,
	material: Enum.Material,
	step: number?,
	name: string?
)
	for _, side in { -1, 1 } do
		local dir = Vector2.new(side * math.cos(math.rad(45)), math.sin(math.rad(45)))
		local mid = Vector2.new(u, v) + dir * (arm / 2)
		local bar = Kit.box(
			parent,
			name or "Chevron",
			Vector3.new(arm + thick / 2, thick, depth),
			view * CFrame.new(mid.X, mid.Y, z + depth / 2) * CFrame.Angles(0, 0, math.atan2(dir.Y, dir.X)),
			color,
			material,
			DETAIL
		)
		if step then
			bar:SetAttribute("Step", step)
		end
	end
end

-- A down arrow: shaft and a chevron head (tip at u, v).
local function arrowDown(
	parent: Instance,
	view: CFrame,
	u: number,
	v: number,
	z: number,
	size: number,
	thick: number,
	depth: number,
	color: Color3,
	material: Enum.Material
)
	local shaft = Kit.box(
		parent,
		"Arrow",
		Vector3.new(thick, size, depth),
		view * CFrame.new(u, v + size / 2 + thick * 0.2, z + depth / 2),
		color,
		material,
		DETAIL
	)
	shaft.Reflectance = 0.2
	chevron(parent, view, u, v, z, size * 0.55, thick, depth, color, material, nil, "Arrow")
end

local function sign(parent: Instance, name: string): Model
	return Kit.folder(parent, name)
end

------------------------------------------------------------------------------------------
-- READING ROOM: theatre marquee
------------------------------------------------------------------------------------------
function SignageRooms.readingRoom(parent: Instance, centre: Vector3, n: Vector3): Model
	local model = sign(parent, "ReadingRoomSign")
	local W, H, D = 12, 2.1, 0.45
	local view = viewAt(centre, n, D)
	Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(52, 38, 26),
		faceColor = Color3.fromRGB(70, 52, 34),
		faceMaterial = METAL,
		faceReflectance = 0.08,
		bevelColor = Color3.fromRGB(150, 110, 62),
		bevelReflectance = 0.25,
		bevel = 0.15,
		name = "Case",
	})
	-- the frosted lightbox, lit from inside
	local LW, LH = W - 1.0, 1.3
	local box = Kit.box(
		model,
		"Lightbox",
		Vector3.new(LW, LH, 0.04),
		view * CFrame.new(0, 0, 0.02),
		Color3.fromRGB(214, 150, 88),
		NEON,
		DETAIL
	)
	box.Transparency = 0.3
	-- bronze sight-line round the lightbox
	Signage.edgeFrame(model, view, LW + 0.12, LH + 0.12, 0.06, 0, 0.07, Color3.fromRGB(120, 88, 50), METAL, "Trim")

	-- letters in silhouette: dark bronze returns, brass caps, the light spilling round them
	local textU = -0.6
	local tv = view * CFrame.new(textU, 0, 0.04)
	Signage.text3D(model, tv, "READING ROOM", {
		height = 0.95,
		width = 0.74,
		gap = 0.2,
		stroke = 0.19,
		layers = {
			{
				name = "Glow",
				color = Color3.fromRGB(255, 168, 90),
				material = NEON,
				transparency = 0.5,
				grow = 0.14,
				z = 0.005,
				d = 0.02,
			},
			{ name = "Body", color = Color3.fromRGB(48, 34, 22), material = METAL, z = 0.03, d = 0.2 },
			{
				name = "Face",
				color = Color3.fromRGB(178, 136, 74),
				material = METAL,
				reflectance = 0.2,
				grow = -0.04,
				z = 0.23,
				d = 0.03,
			},
		},
	})

	-- chevrons chasing down toward the stair (Step 3 on top)
	for i, v in { 0.42, 0.06, -0.3 } do
		chevron(model, view, 4.85, v - 0.12, 0.04, 0.34, 0.08, 0.06, Color3.fromRGB(255, 150, 70), NEON, 4 - i)
	end

	-- marquee bulbs round the border
	Signage.bulbs(model, view, Signage.rectPoints(W - 0.5, H - 0.46, 0.7), 0, 0.15, Color3.fromRGB(255, 196, 120))

	Kit.pointLight(box, 12, 0.6, false, WARM)
	Signage.hazeVolume(model, view, 0, -H / 2 - 1, 1.1, Vector3.new(W - 2, 1, 1.4))
	Signage.tagFX(model, view, "marquee", {
		Width = W,
		Height = H,
		Accent = WARM,
		Pulse = 5,
		PulseAmt = 0.35,
		Sweep = 11,
		SweepColor = Color3.fromRGB(255, 220, 170),
		Chase = 1,
		Haze = "dust",
		Flicker = 40,
	})
	return model
end

------------------------------------------------------------------------------------------
-- THE DOORS: blackened steel, red neon
------------------------------------------------------------------------------------------
function SignageRooms.theDoors(parent: Instance, centre: Vector3, n: Vector3): Model
	local model = sign(parent, "TheDoorsSign")
	local W, H, D = 9, 1.5, 0.4
	local RED = Color3.fromRGB(230, 50, 36)
	local view = viewAt(centre, n, D)
	local _, face = Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(26, 24, 24),
		faceColor = Color3.fromRGB(14, 13, 13),
		faceReflectance = 0.12,
		bevelColor = Color3.fromRGB(70, 60, 58),
		bevelReflectance = 0.2,
		bevel = 0.14,
	})
	Signage.text3D(model, view * CFrame.new(0, 0.12, 0), "THE DOORS", {
		height = 0.8,
		width = 0.76,
		gap = 0.22,
		stroke = 0.2,
		layers = {
			{
				name = "Glow",
				color = Color3.fromRGB(150, 14, 10),
				material = NEON,
				transparency = 0.45,
				grow = 0.2,
				z = 0.005,
				d = 0.02,
			},
			{ name = "Body", color = Color3.fromRGB(88, 30, 24), material = METAL, z = 0.02, d = 0.2 },
			{
				name = "Face",
				color = Color3.fromRGB(200, 34, 22),
				material = NEON,
				grow = -0.05,
				z = 0.22,
				d = 0.03,
			},
		},
	})
	Signage.ledRow(model, view, W - 1.2, -H / 2 + 0.2, 0, 14, Color3.fromRGB(200, 40, 30), 1)
	-- down-chevrons either side, pointing through the arch (Step 3 on top)
	for _, side in { -1, 1 } do
		for i, v in { 0.35, 0, -0.35 } do
			chevron(
				model,
				view * CFrame.new(0, 0, -D),
				side * (W / 2 + 0.75),
				v - 0.15,
				0,
				0.42,
				0.09,
				0.08,
				RED,
				NEON,
				4 - i
			)
		end
	end
	Kit.pointLight(face, 9, 0.45, false, Color3.fromRGB(255, 70, 50))
	Signage.hazeVolume(model, view, 0, -H / 2 - 0.7, 0.6, Vector3.new(W - 2, 0.5, 1))
	Signage.tagFX(model, view, "neon", {
		Width = W,
		Height = H,
		Accent = Color3.fromRGB(255, 60, 44),
		Pulse = 3.5,
		PulseAmt = 0.5,
		Sweep = 9,
		SweepColor = Color3.fromRGB(255, 170, 150),
		Flicker = 14,
		Haze = "haze",
		HazeRate = 1.5,
		Chase = 1,
	})
	return model
end

------------------------------------------------------------------------------------------
-- WORKSHOP (hall): carved walnut, brass inlay, picture lamp
------------------------------------------------------------------------------------------
local BRASS = Color3.fromRGB(190, 146, 74)

function SignageRooms.workshopBoard(parent: Instance, centre: Vector3, n: Vector3): Model
	local model = sign(parent, "WorkshopBoard")
	local W, H, D = 8.4, 1.7, 0.3
	local view = viewAt(centre, n, D)
	Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(46, 30, 20),
		bodyMaterial = WOOD,
		faceColor = Color3.fromRGB(58, 38, 24),
		faceMaterial = WOOD,
		bevelColor = Color3.fromRGB(122, 86, 54),
		bevelMaterial = WOOD,
		bevelReflectance = 0,
		bevel = 0.16,
	})
	-- a routed groove inside the edge
	Signage.edgeFrame(model, view, W - 0.6, H - 0.6, 0.05, 0, 0.015, Color3.fromRGB(30, 20, 13), WOOD, "Groove")
	Signage.text3D(model, view * CFrame.new(-0.55, 0, 0), "WORKSHOP", {
		height = 0.85,
		width = 0.76,
		gap = 0.2,
		stroke = 0.2,
		layers = {
			{ name = "Body", color = Color3.fromRGB(92, 62, 38), material = WOOD, z = 0, d = 0.14 },
			{
				name = "Face",
				color = BRASS,
				material = METAL,
				reflectance = 0.2,
				grow = -0.04,
				z = 0.14,
				d = 0.03,
			},
		},
	})
	arrowDown(model, view, W / 2 - 0.75, -0.42, 0, 0.75, 0.12, 0.12, BRASS, METAL)
	for _, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
		local boss = Kit.box(
			model,
			"Boss",
			Vector3.new(0.07, 0.2, 0.2),
			view * CFrame.new(c[1] * (W / 2 - 0.3), c[2] * (H / 2 - 0.3), 0.035) * CFrame.Angles(0, math.rad(90), 0),
			BRASS,
			METAL,
			DETAIL
		)
		boss.Shape = Enum.PartType.Cylinder
		boss.Reflectance = 0.2
	end
	-- picture lamp: arm off the wall above the board, a brass hood leaning out over it
	local wallZ = -D
	local armZ0, armZ1 = wallZ, 0.85
	Kit.box(
		model,
		"LampArm",
		Vector3.new(0.08, 0.08, armZ1 - armZ0),
		view * CFrame.new(0, H / 2 + 0.55, (armZ0 + armZ1) / 2),
		BRASS,
		METAL,
		DETAIL
	)
	Kit.box(
		model,
		"LampMount",
		Vector3.new(0.5, 0.3, 0.05),
		view * CFrame.new(0, H / 2 + 0.55, wallZ + 0.025),
		BRASS,
		METAL,
		DETAIL
	)
	local hood = Kit.box(
		model,
		"LampHood",
		Vector3.new(3.2, 0.22, 0.32),
		view * CFrame.new(0, H / 2 + 0.45, armZ1) * CFrame.Angles(math.rad(-25), 0, 0),
		BRASS,
		METAL,
		DETAIL
	)
	hood.Reflectance = 0.2
	local tube = Kit.box(
		model,
		"LampTube",
		Vector3.new(3, 0.05, 0.08),
		view * CFrame.new(0, H / 2 + 0.32, armZ1 - 0.02),
		Color3.fromRGB(255, 190, 120),
		NEON,
		DETAIL
	)
	tube.Transparency = 0.2
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 100
	spot.Range = 6
	spot.Brightness = 1.2
	spot.Color = WARM
	spot.Shadows = false
	spot.Parent = tube
	Signage.hazeVolume(model, view, 0, 0, 0.6, Vector3.new(W - 1.5, H, 0.8))
	Signage.tagFX(model, view, "carved", {
		Width = W,
		Height = H,
		Accent = Color3.fromRGB(255, 196, 120),
		Pulse = 6,
		PulseAmt = 0.15,
		Sweep = 10,
		SweepColor = Color3.fromRGB(255, 226, 170),
		Haze = "dust",
		HazeRate = 2,
	})
	return model
end

------------------------------------------------------------------------------------------
-- WORKSHOP (inside): painted plank on chains
------------------------------------------------------------------------------------------
-- `top` is the centre of the plank's top edge; `n` the side the lettering faces. Returns the model
-- (chains are added to it by the caller so they swing with it) and the plank's chain points.
function SignageRooms.workshopHanging(parent: Instance, top: Vector3, n: Vector3, w: number, h: number): Model
	local model = sign(parent, "WorkshopSign")
	local T = 0.24
	local centre = top - Vector3.new(0, h / 2, 0)
	local view = viewAt(centre, n, T / 2)
	Kit.box(
		model,
		"Plank",
		Vector3.new(w, h, T),
		view * CFrame.new(0, 0, -T / 2),
		Color3.fromRGB(176, 148, 108),
		WOOD,
		DETAIL
	)
	for _, side in { 1, -1 } do
		-- a routed border on both faces
		local sv = if side == 1 then view else view * CFrame.new(0, 0, -T) * CFrame.Angles(0, math.pi, 0)
		Signage.edgeFrame(model, sv, w - 0.24, h - 0.24, 0.06, 0, 0.015, Color3.fromRGB(110, 84, 56), WOOD, "Trim")
	end
	Signage.text3D(model, view, "WORKSHOP", {
		height = 0.62,
		width = 0.74,
		gap = 0.2,
		stroke = 0.2,
		jitter = { rot = 1.5, v = 0.03, seed = 7 },
		layers = {
			{ name = "Body", color = Color3.fromRGB(110, 34, 26), material = WOOD, z = 0, d = 0.1 },
			{
				name = "Face",
				color = Color3.fromRGB(226, 210, 172),
				material = WOOD,
				grow = -0.04,
				z = 0.1,
				d = 0.025,
			},
		},
	})
	for _, du in { -w / 2 + 0.6, w / 2 - 0.6 } do
		local ring = Kit.box(
			model,
			"Ring",
			Vector3.new(0.06, 0.26, 0.26),
			view * CFrame.new(du, h / 2 + 0.08, -T / 2) * CFrame.Angles(0, math.rad(90), 0),
			BRASS,
			METAL,
			DETAIL
		)
		ring.Shape = Enum.PartType.Cylinder
	end
	Signage.tagFX(model, view, "hanging", {
		Width = w,
		Height = h,
		Accent = WARM,
		Sway = 2,
	})
	return model
end

------------------------------------------------------------------------------------------
-- LANTERNS (workshop bench): painted board
------------------------------------------------------------------------------------------
-- `cf` is the centre of the board's back on the lining, LookVector into the room.
function SignageRooms.benchLanterns(parent: Instance, cf: CFrame): Model
	local model = sign(parent, "Sign")
	local W, H, D = 6.2, 1.25, 0.18
	local view = cf * CFrame.new(0, 0, -D) * CFrame.Angles(0, math.pi, 0)
	Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(38, 56, 46),
		bodyMaterial = WOOD,
		faceColor = Color3.fromRGB(44, 64, 52),
		faceMaterial = WOOD,
		bevelColor = Color3.fromRGB(70, 92, 76),
		bevelMaterial = WOOD,
		bevelReflectance = 0,
		bevel = 0.08,
	})
	Signage.text3D(model, view, "LANTERNS", {
		height = 0.72,
		width = 0.76,
		gap = 0.2,
		stroke = 0.2,
		jitter = { rot = 1, v = 0.02, seed = 3 },
		layers = {
			{ name = "Body", color = Color3.fromRGB(168, 152, 120), material = WOOD, z = 0, d = 0.09 },
			{
				name = "Face",
				color = Color3.fromRGB(230, 216, 180),
				material = SMOOTH,
				grow = -0.03,
				z = 0.09,
				d = 0.02,
			},
		},
	})
	for _, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
		local screw = Kit.box(
			model,
			"Screw",
			Vector3.new(0.04, 0.1, 0.1),
			view * CFrame.new(c[1] * (W / 2 - 0.18), c[2] * (H / 2 - 0.16), 0.02) * CFrame.Angles(0, math.rad(90), 0),
			BRASS,
			METAL,
			DETAIL
		)
		screw.Shape = Enum.PartType.Cylinder
	end
	Signage.haloAt(model, view, 0, 0, 0.3, 5, Color3.fromRGB(255, 170, 96), 0.7)
	Signage.hazeVolume(model, view, 0, -H / 2 - 0.7, 0.6, Vector3.new(W - 1.5, 0.4, 0.6))
	Signage.tagFX(model, view, "painted", {
		Width = W,
		Height = H,
		Accent = Color3.fromRGB(255, 170, 96),
		Pulse = 4,
		PulseAmt = 0.25,
		Haze = "embers",
		HazeRate = 1.2,
	})
	return model
end

------------------------------------------------------------------------------------------
-- LANTERNS (gift shop): black lacquer, gold letters
------------------------------------------------------------------------------------------
function SignageRooms.shopLanterns(parent: Instance, centre: Vector3, n: Vector3): Model
	local model = sign(parent, "LanternsBoard")
	local W, H, D = 6.4, 1.1, 0.15
	local view = viewAt(centre, n, D)
	Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(12, 10, 14),
		bodyMaterial = WOOD,
		faceColor = Color3.fromRGB(9, 7, 12),
		faceReflectance = 0.15,
		bevelColor = Color3.fromRGB(110, 88, 52),
		bevelReflectance = 0.25,
		bevel = 0.06,
	})
	Signage.text3D(model, view, "LANTERNS", {
		height = 0.62,
		width = 0.78,
		gap = 0.2,
		stroke = 0.18,
		layers = {
			{
				name = "Glow",
				color = Color3.fromRGB(120, 60, 220),
				material = NEON,
				transparency = 0.65,
				grow = 0.12,
				z = 0.005,
				d = 0.02,
			},
			{ name = "Body", color = Color3.fromRGB(120, 92, 48), material = METAL, z = 0.02, d = 0.1 },
			{
				name = "Face",
				color = Color3.fromRGB(200, 160, 84),
				material = METAL,
				reflectance = 0.3,
				grow = -0.03,
				z = 0.12,
				d = 0.02,
			},
		},
	})
	Signage.tagFX(model, view, "gilt", {
		Width = W,
		Height = H,
		Accent = Color3.fromRGB(150, 90, 255),
		Sweep = 8,
		SweepColor = Color3.fromRGB(255, 228, 170),
	})
	return model
end

------------------------------------------------------------------------------------------
-- Reward stations: holographic floating titles
------------------------------------------------------------------------------------------
function SignageRooms.holoTitle(parent: Instance, centre: Vector3, n: Vector3, str: string, color: Color3): Model
	local model = sign(parent, "Title3D")
	local view = viewAt(centre, n, 0)
	local spec = {
		height = 0.62,
		width = 0.78,
		gap = 0.2,
		stroke = 0.17,
		layers = {
			{
				name = "Glow",
				color = color:Lerp(Color3.new(0, 0, 0), 0.35),
				material = NEON,
				transparency = 0.6,
				grow = 0.12,
				z = -0.04,
				d = 0.02,
			},
			{ name = "Face", color = color, material = NEON, transparency = 0.15, z = 0, d = 0.06 },
		},
	}
	local _, width = Signage.text3D(model, view, str, spec)
	-- the projector: a dark housing with a lit slit under the text, a faint fan of light rising
	local barV = -spec.height / 2 - 0.3
	Kit.box(
		model,
		"Projector",
		Vector3.new(width * 0.5, 0.08, 0.14),
		view * CFrame.new(0, barV - 0.05, 0),
		Color3.fromRGB(20, 20, 22),
		METAL,
		DETAIL
	)
	local slit = Kit.box(
		model,
		"Edge",
		Vector3.new(width * 0.46, 0.025, 0.02),
		view * CFrame.new(0, barV, 0.07),
		color,
		NEON,
		DETAIL
	)
	slit.Transparency = 0.2
	for _, side in { -1, 1 } do
		-- the fan: two faint sheets leaning out from the slit to the ends of the text
		local a = Vector2.new(side * width * 0.2, barV)
		local b = Vector2.new(side * width * 0.5, spec.height / 2)
		local d = b - a
		local sheet = Kit.box(
			model,
			"Fan",
			Vector3.new(0.03, d.Magnitude, 0.01),
			view * CFrame.new((a.X + b.X) / 2, (a.Y + b.Y) / 2, -0.02) * CFrame.Angles(0, 0, -math.atan2(d.X, d.Y)),
			color,
			NEON,
			DETAIL
		)
		sheet.Transparency = 0.85
	end
	local fill = Kit.box(
		model,
		"Fan",
		Vector3.new(width * 0.8, spec.height + 0.3, 0.01),
		view * CFrame.new(0, (barV + spec.height / 2) / 2, -0.06),
		color,
		NEON,
		DETAIL
	)
	fill.Transparency = 0.96
	Signage.hazeVolume(model, view, 0, barV + 0.1, 0, Vector3.new(width * 0.6, 0.2, 0.3))
	Signage.tagFX(model, view, "holo", {
		Width = width,
		Height = spec.height,
		Accent = color,
		Bob = 0.12,
		Pulse = 3,
		PulseAmt = 0.4,
		Sweep = 4.5,
		SweepColor = color:Lerp(Color3.new(1, 1, 1), 0.5),
		Flicker = 25,
		Haze = "motes",
		HazeRate = 2,
		Cull = 70,
	})
	return model
end

------------------------------------------------------------------------------------------
-- HALL OF RECORDS: carved header over the leaderboard
------------------------------------------------------------------------------------------
function SignageRooms.recordsHeader(parent: Instance, centre: Vector3, n: Vector3): Model
	local model = sign(parent, "RecordsHeader")
	local W, H, D = 4.6, 0.85, 0.22
	local view = viewAt(centre, n, D)
	Signage.panel(model, view, W, H, D, {
		bodyColor = Color3.fromRGB(46, 30, 20),
		bodyMaterial = WOOD,
		faceColor = Color3.fromRGB(60, 40, 26),
		faceMaterial = WOOD,
		bevelColor = Color3.fromRGB(112, 78, 48),
		bevelMaterial = WOOD,
		bevelReflectance = 0,
		bevel = 0.08,
	})
	Signage.text3D(model, view, "HALL OF RECORDS", {
		height = 0.32,
		width = 0.74,
		gap = 0.18,
		stroke = 0.2,
		space = 0.45,
		layers = {
			{ name = "Body", color = Color3.fromRGB(92, 62, 38), material = WOOD, z = 0, d = 0.06 },
			{
				name = "Face",
				color = BRASS,
				material = METAL,
				reflectance = 0.22,
				grow = -0.015,
				z = 0.06,
				d = 0.015,
			},
		},
	})
	Signage.tagFX(model, view, "carved", {
		Width = W,
		Height = H,
		Accent = Color3.fromRGB(255, 200, 130),
		Sweep = 12,
		SweepColor = Color3.fromRGB(255, 230, 180),
	})
	return model
end

return SignageRooms
