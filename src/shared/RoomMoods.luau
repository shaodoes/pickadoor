--[[
	Per-room mood for the lobby (data only; Mood.client blends it on the player's machine).

	The lobby builder (setupLighting) lays down a neutral base: Atmosphere, ColorCorrection, Bloom,
	DepthOfField and the Lighting ambients. Mood.client then owns those same instances at runtime and
	eases every value below toward the profile of the room the player is in (~1.5 s), so walking from
	the warm foyer into the black/violet store or the cold door hall shifts the whole grade smoothly.

	Each profile is absolute (not an offset), keyed by the Room names the Shell builder writes on its
	FX = "Room" anchors (Foyer, Shop, Stair, Hall, DoorHall, Workshop). Missing fields fall back to
	RoomMoods.Base. Fields:
	  atmosphere  Density, Offset, Haze, Glare, Color, Decay
	  grade       ColorCorrection: Tint, Contrast, Saturation, Brightness
	  bloom       Intensity, Size, Threshold
	  light       Lighting: Ambient, OutdoorAmbient, Exposure (ExposureCompensation)
	  vignette    0..1 darkening at the screen edges (a ScreenGui; there's no vignette post effect)
	  lantern     multiplier on held lanterns' light here (1 = as built for the dark trials; the lobby is
	              lit already, and a full-strength lantern a stud from a white avatar blows it out)
	  haze        world-space haze volumes that belong to this room: slow, very faint smoke that only
	              shows where a lamp lights it (LightInfluence 1), so it reads as light hanging in the
	              air around the lamps and windows. { cf, size, color, rate?, puff? (particle studs), lit? }
	DoorHall also has `tension`: extra offsets applied on top, scaled by the queue tension (0..1) that
	DoorFX writes on the PICK A DOOR sign.

	Mood.client resolves the room from the character (camera as a fallback): RoomMoods.roomAt().
]]
local RoomMoods = {}

local rgb = Color3.fromRGB
local v3 = Vector3.new

RoomMoods.BLEND_TIME = 1.5 -- seconds to (nearly) settle into a new room's mood

-- The neutral base. Keep in step with LobbyBuilder.setupLighting (which writes these into Lighting).
RoomMoods.Base = {
	atmosphere = {
		Density = 0.3,
		Offset = 0,
		Haze = 1.2,
		Glare = 0,
		Color = rgb(60, 60, 56),
		Decay = rgb(28, 32, 34),
	},
	grade = { Tint = rgb(255, 246, 236), Contrast = 0.16, Saturation = -0.06, Brightness = 0 },
	bloom = { Intensity = 0.45, Size = 24, Threshold = 1.7 },
	light = { Ambient = rgb(13, 13, 14), OutdoorAmbient = rgb(14, 17, 19), Exposure = 0 },
	vignette = 0.25,
	lantern = 0.5,
}

RoomMoods.Profiles = {
	-- warm, cosy arrival: amber air, gentle contrast, soft lamp bloom
	Foyer = {
		atmosphere = { Density = 0.3, Haze = 1.5, Color = rgb(76, 64, 50), Decay = rgb(40, 30, 22) },
		grade = { Tint = rgb(255, 240, 222), Contrast = 0.13, Saturation = -0.02, Brightness = 0.005 },
		bloom = { Intensity = 0.5, Size = 26, Threshold = 1.6 },
		light = { Ambient = rgb(16, 14, 12), Exposure = 0.05 },
		vignette = 0.2,
		haze = {
			-- the lamp pool at the foot of the house stairs / spawn
			{ cf = CFrame.new(12, 10, 52), size = v3(16, 6, 14), color = rgb(255, 214, 170), rate = 1.6 },
		},
	},
	-- the store (Teeth): very dark, cold violet, deep shadows, eerie low haze; the eyes and the violet
	-- neon are what's left to see, so bloom stays a touch hotter here than anywhere else
	Shop = {
		atmosphere = { Density = 0.4, Haze = 2, Color = rgb(34, 24, 48), Decay = rgb(14, 8, 24) },
		grade = { Tint = rgb(222, 210, 255), Contrast = 0.3, Saturation = -0.12, Brightness = -0.035 },
		bloom = { Intensity = 0.7, Size = 28, Threshold = 1.45 },
		light = { Ambient = rgb(7, 6, 11), OutdoorAmbient = rgb(8, 7, 12), Exposure = -0.2 },
		vignette = 0.45,
		lantern = 0.6,
		haze = {
			-- low violet ground haze across the shop floor, thickest round the counter
			{ cf = CFrame.new(-18, 8, 54), size = v3(22, 3, 22), color = rgb(150, 120, 220), rate = 2, lit = 1 },
			{ cf = CFrame.new(-20, 12, 53), size = v3(8, 6, 12), color = rgb(170, 140, 255), rate = 1 },
		},
	},
	-- the grand stair: halfway between the foyer and the hall
	Stair = {
		atmosphere = { Density = 0.32, Haze = 1.5, Color = rgb(68, 64, 56), Decay = rgb(32, 32, 30) },
		grade = { Tint = rgb(255, 244, 230), Contrast = 0.15, Saturation = -0.04, Brightness = 0 },
		bloom = { Intensity = 0.48, Size = 26, Threshold = 1.62 },
		light = { Ambient = rgb(14, 13, 13), Exposure = 0.02 },
		vignette = 0.22,
	},
	-- reading hall: calm warm lamplight, cool teal spill from the natatorium windows, dusty air
	Hall = {
		atmosphere = { Density = 0.33, Haze = 1.7, Color = rgb(62, 64, 60), Decay = rgb(22, 38, 42) },
		grade = { Tint = rgb(255, 246, 236), Contrast = 0.15, Saturation = -0.05, Brightness = 0 },
		bloom = { Intensity = 0.45, Size = 26, Threshold = 1.65 },
		light = { Ambient = rgb(12, 13, 15), Exposure = 0 },
		vignette = 0.25,
		haze = {
			-- dust hanging under the three globe pendants down the middle of the hall
			{ cf = CFrame.new(5, 8, 8), size = v3(12, 5, 34), color = rgb(255, 214, 170), rate = 2 },
			-- cold haze along the natatorium windows, lit by the window SurfaceLights
			{ cf = CFrame.new(-26, 7, 7), size = v3(9, 7, 36), color = rgb(150, 205, 215), rate = 2 },
			-- the reading-table lamps on the right
			{ cf = CFrame.new(24, 7, 0), size = v3(8, 5, 26), color = rgb(255, 210, 160), rate = 1 },
		},
	},
	-- workshop: furnace orange, smoky thick air, embers (AtmosFX)
	Workshop = {
		atmosphere = { Density = 0.44, Haze = 2.4, Color = rgb(84, 58, 38), Decay = rgb(48, 24, 12) },
		grade = { Tint = rgb(255, 230, 204), Contrast = 0.2, Saturation = 0.03, Brightness = 0 },
		bloom = { Intensity = 0.55, Size = 30, Threshold = 1.5 },
		light = { Ambient = rgb(17, 12, 9), Exposure = 0 },
		vignette = 0.3,
		haze = {
			-- smoke rolling off the furnace mouth, lit orange by its glow
			{ cf = CFrame.new(49, 1, -6), size = v3(10, 6, 8), color = rgb(255, 170, 110), rate = 2.4, puff = 9 },
			-- general smoky ceiling layer
			{ cf = CFrame.new(49, 5, 2), size = v3(24, 4, 28), color = rgb(200, 160, 120), rate = 1.6 },
			-- the lantern bench task light
			{ cf = CFrame.new(49, 2, 14), size = v3(8, 4, 5), color = rgb(255, 210, 160), rate = 0.8 },
		},
	},
	-- door hall: tense. Darker, desaturated, cold with a red undertone, heavy edges; tightens further
	-- as the queues count down (tension)
	DoorHall = {
		atmosphere = { Density = 0.38, Haze = 1.6, Color = rgb(50, 46, 50), Decay = rgb(32, 16, 16) },
		grade = { Tint = rgb(236, 236, 248), Contrast = 0.24, Saturation = -0.22, Brightness = -0.02 },
		bloom = { Intensity = 0.45, Size = 24, Threshold = 1.65 },
		light = { Ambient = rgb(10, 10, 12), Exposure = -0.12 },
		vignette = 0.45,
		haze = {
			-- low cold mist along the door wall
			{ cf = CFrame.new(0, 2, -55), size = v3(66, 3, 8), color = rgb(190, 180, 190), rate = 2.4 },
			-- under the queue lamp in the middle of the hall
			{ cf = CFrame.new(5, 9, -46), size = v3(12, 5, 12), color = rgb(255, 200, 160), rate = 1 },
		},
		tension = {
			grade = { Tint = rgb(255, 206, 200), Contrast = 0.1, Saturation = -0.12, Brightness = -0.03 },
			atmosphere = { Density = 0.08, Haze = 0.6 },
			vignette = 0.2,
		},
	},
}

-- Fallback room bounds (mirror builders/Layout.Rooms) for when the Room anchors haven't streamed in.
RoomMoods.Bounds = {
	{ name = "Foyer", min = v3(-2, 4, 42), max = v3(30, 22, 66) },
	{ name = "Shop", min = v3(-30, 4, 42), max = v3(-6, 21, 66) },
	{ name = "Stair", min = v3(4, -2, 30), max = v3(20, 21, 42) },
	{ name = "Hall", min = v3(-32, -2, -20), max = v3(32, 18, 30) },
	{ name = "DoorHall", min = v3(-36, -2, -60), max = v3(36, 20, -24) },
	{ name = "Workshop", min = v3(36, -7, -14), max = v3(62, 11, 18) },
}

local function insideBox(part: BasePart, pos: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size * 0.5
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

-- The room containing `pos`: the Room anchor parts first (FX = "Room", attribute Room), else the
-- fallback bounds. In doorways (between volumes) `current` is kept, so moods don't flicker there.
function RoomMoods.roomAt(pos: Vector3, anchors: { BasePart }, current: string): string
	for _, part in anchors do
		if part.Parent and insideBox(part, pos) then
			return part:GetAttribute("Room") or current
		end
	end
	if #anchors == 0 then
		for _, r in RoomMoods.Bounds do
			if
				pos.X >= r.min.X
				and pos.X <= r.max.X
				and pos.Y >= r.min.Y
				and pos.Y <= r.max.Y
				and pos.Z >= r.min.Z
				and pos.Z <= r.max.Z
			then
				return r.name
			end
		end
	end
	return current
end

-- Profile for a room with every field filled in from Base.
function RoomMoods.resolve(room: string)
	local p = RoomMoods.Profiles[room] or RoomMoods.Profiles.Hall
	local out = {}
	for _, group in { "atmosphere", "grade", "bloom", "light" } do
		local merged = table.clone(RoomMoods.Base[group])
		for key, value in p[group] or {} do
			merged[key] = value
		end
		out[group] = merged
	end
	out.vignette = p.vignette or RoomMoods.Base.vignette
	out.lantern = p.lantern or RoomMoods.Base.lantern
	return out
end

return RoomMoods
