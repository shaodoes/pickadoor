-- Lantern catalog. Every player owns the default; the rest are bought with Keys.
-- Each entry describes the lantern's body (LanternBuilder), its light (PointLight) and its flame
-- (the layered Neon flame + particle look in the model). `lightRadius` is derived from `range`
-- for the UI's LIGHT meter.
local Lanterns = {}

Lanterns.DefaultId = "copper"

-- Rarities in price order; the colours are the UI pills, row strokes and pegboard tags.
Lanterns.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
Lanterns.RarityColors = {
	Common = Color3.fromRGB(142, 142, 148),
	Uncommon = Color3.fromRGB(92, 160, 96),
	Rare = Color3.fromRGB(74, 128, 206),
	Epic = Color3.fromRGB(150, 86, 196),
	Legendary = Color3.fromRGB(222, 170, 60),
}

export type Flame = {
	color: Color3, -- outer flame / particle tongue
	tip: Color3, -- bright core and the top of the tongue
	emberColor: Color3,
	rate: number, -- particle tongue rate (kept <= 12: these sit on ~12 lobby lanterns plus the one in hand)
	smoke: boolean?, -- dark lanterns put up a faint wisp
	smokeColor: Color3?,
}

export type Lantern = {
	id: string,
	name: string,
	rarity: string,
	description: string,
	price: number,
	bodyColor: Color3,
	trimColor: Color3?,
	bodyMaterial: Enum.Material,
	trimMaterial: Enum.Material?, -- mullions, ring, bands (defaults to bodyMaterial)
	glassColor: Color3,
	lightColor: Color3,
	brightness: number,
	range: number,
	lightRadius: number,
	flame: Flame,
}

Lanterns.List = {
	{
		id = "copper",
		name = "Copper Classic",
		rarity = "Common",
		description = "Standard issue. Dented, patched and relit more times than anyone has counted. It has seen a lot of doors.",
		price = 0,
		bodyColor = Color3.fromRGB(128, 64, 40),
		trimColor = Color3.fromRGB(190, 112, 74),
		bodyMaterial = Enum.Material.Metal,
		glassColor = Color3.fromRGB(255, 214, 160),
		lightColor = Color3.fromRGB(255, 170, 90),
		brightness = 1.4,
		range = 16,
		flame = {
			color = Color3.fromRGB(255, 132, 36),
			tip = Color3.fromRGB(255, 228, 170),
			emberColor = Color3.fromRGB(255, 160, 60),
			rate = 8,
		},
	},
	{
		id = "iron",
		name = "Blackened Iron",
		rarity = "Uncommon",
		description = "Heavy, cold, dependable. Forge-black plate and a wick that never guttered. Its glass is sooted from older fires.",
		price = 150,
		bodyColor = Color3.fromRGB(38, 38, 42),
		trimColor = Color3.fromRGB(96, 96, 104),
		bodyMaterial = Enum.Material.DiamondPlate,
		trimMaterial = Enum.Material.Metal,
		glassColor = Color3.fromRGB(255, 225, 190),
		lightColor = Color3.fromRGB(255, 196, 130),
		brightness = 1.5,
		range = 17,
		flame = {
			color = Color3.fromRGB(255, 196, 96),
			tip = Color3.fromRGB(255, 244, 214),
			emberColor = Color3.fromRGB(255, 210, 120),
			rate = 8,
			smoke = true,
			smokeColor = Color3.fromRGB(120, 116, 112),
		},
	},
	{
		id = "verdigris",
		name = "Verdigris Copper",
		rarity = "Rare",
		description = "Pulled from a flooded room and never quite dry. The copper has gone sea-green and the flame followed it.",
		price = 300,
		bodyColor = Color3.fromRGB(72, 140, 118),
		trimColor = Color3.fromRGB(150, 92, 62), -- the copper showing through
		bodyMaterial = Enum.Material.Metal,
		trimMaterial = Enum.Material.CorrodedMetal,
		glassColor = Color3.fromRGB(200, 255, 220),
		lightColor = Color3.fromRGB(160, 255, 200),
		brightness = 1.3,
		range = 17,
		flame = {
			color = Color3.fromRGB(80, 230, 150),
			tip = Color3.fromRGB(210, 255, 225),
			emberColor = Color3.fromRGB(120, 255, 180),
			rate = 9,
		},
	},
	{
		id = "bone",
		name = "Bone Lantern",
		rarity = "Epic",
		description = "Carved from something that used to walk. The grooves were cut from the inside. It burns white, and cold.",
		price = 600,
		bodyColor = Color3.fromRGB(172, 160, 132), -- old ivory; anything paler blows out under its own light
		trimColor = Color3.fromRGB(140, 122, 92),
		bodyMaterial = Enum.Material.Marble,
		glassColor = Color3.fromRGB(236, 242, 255),
		lightColor = Color3.fromRGB(222, 234, 255), -- cold
		brightness = 1.6,
		range = 18,
		flame = {
			color = Color3.fromRGB(214, 232, 255),
			tip = Color3.fromRGB(255, 255, 255),
			emberColor = Color3.fromRGB(200, 226, 255),
			rate = 7,
		},
	},
	{
		id = "bloodglass",
		name = "Bloodglass",
		rarity = "Legendary",
		description = "Blown from glass that was already red. The light makes the shadows nervous, and the smoke is darker than it should be.",
		price = 1200,
		bodyColor = Color3.fromRGB(70, 18, 18),
		trimColor = Color3.fromRGB(138, 104, 58), -- old gold
		bodyMaterial = Enum.Material.Metal,
		glassColor = Color3.fromRGB(255, 70, 60),
		lightColor = Color3.fromRGB(255, 70, 55),
		brightness = 1.8,
		range = 18,
		flame = {
			color = Color3.fromRGB(220, 30, 30),
			tip = Color3.fromRGB(255, 150, 120),
			emberColor = Color3.fromRGB(255, 70, 50),
			rate = 10,
			smoke = true,
			smokeColor = Color3.fromRGB(48, 20, 22),
		},
	},
}

-- derived stats + lookup
local byId = {}
for _, def in Lanterns.List do
	def.lightRadius = def.range
	byId[def.id] = def
end

-- The largest light radius / brightness in the catalog, for the UI meters.
Lanterns.MaxLightRadius = 0
Lanterns.MaxBrightness = 0
for _, def in Lanterns.List do
	Lanterns.MaxLightRadius = math.max(Lanterns.MaxLightRadius, def.lightRadius)
	Lanterns.MaxBrightness = math.max(Lanterns.MaxBrightness, def.brightness)
end

function Lanterns.get(id: string?): Lantern?
	return id and byId[id] or nil
end

function Lanterns.getOrDefault(id: string?): Lantern
	return (id and byId[id]) or byId[Lanterns.DefaultId]
end

function Lanterns.rarityColor(rarity: string?): Color3
	return Lanterns.RarityColors[rarity or "Common"] or Lanterns.RarityColors.Common
end

return Lanterns
