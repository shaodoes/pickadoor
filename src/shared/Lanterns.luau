-- Lantern catalog. Every player owns the default; the rest are bought with Keys.
local Lanterns = {}

Lanterns.DefaultId = "brass"

Lanterns.List = {
	{
		id = "brass",
		name = "Brass Classic",
		description = "Standard issue. It has seen a lot of doors.",
		price = 0,
		bodyColor = Color3.fromRGB(163, 120, 55),
		bodyMaterial = Enum.Material.Metal,
		glassColor = Color3.fromRGB(255, 214, 160),
		lightColor = Color3.fromRGB(255, 170, 90),
		brightness = 1.4,
		range = 16,
	},
	{
		id = "iron",
		name = "Blackened Iron",
		description = "Heavy, cold, dependable.",
		price = 150,
		bodyColor = Color3.fromRGB(38, 38, 42),
		bodyMaterial = Enum.Material.DiamondPlate,
		glassColor = Color3.fromRGB(255, 225, 190),
		lightColor = Color3.fromRGB(255, 196, 130),
		brightness = 1.5,
		range = 17,
	},
	{
		id = "verdigris",
		name = "Verdigris Copper",
		description = "Pulled from a flooded room. The flame burns green.",
		price = 300,
		bodyColor = Color3.fromRGB(72, 140, 118),
		bodyMaterial = Enum.Material.CorrodedMetal,
		glassColor = Color3.fromRGB(200, 255, 220),
		lightColor = Color3.fromRGB(160, 255, 200),
		brightness = 1.3,
		range = 17,
	},
	{
		id = "bone",
		name = "Bone Lantern",
		description = "Carved from something that used to walk.",
		price = 600,
		bodyColor = Color3.fromRGB(226, 216, 190),
		bodyMaterial = Enum.Material.Marble,
		glassColor = Color3.fromRGB(255, 245, 225),
		lightColor = Color3.fromRGB(255, 238, 210),
		brightness = 1.6,
		range = 18,
	},
	{
		id = "bloodglass",
		name = "Bloodglass",
		description = "The light makes the shadows nervous.",
		price = 1200,
		bodyColor = Color3.fromRGB(70, 18, 18),
		bodyMaterial = Enum.Material.Metal,
		glassColor = Color3.fromRGB(255, 70, 60),
		lightColor = Color3.fromRGB(255, 70, 55),
		brightness = 1.8,
		range = 18,
	},
}

local byId = {}
for _, def in Lanterns.List do
	byId[def.id] = def
end

function Lanterns.get(id: string?)
	return id and byId[id] or nil
end

function Lanterns.getOrDefault(id: string?)
	return (id and byId[id]) or byId[Lanterns.DefaultId]
end

return Lanterns
