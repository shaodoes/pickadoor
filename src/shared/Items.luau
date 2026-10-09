-- Purchasable item catalog (sold for Keys at the shop, used from the hotbar).
-- Consumables stack up to `cap` and have a per-item use cooldown; `unlock` items are bought once.
-- Effect numbers live here so the server (ItemService) and the client (ItemsClient VFX timers) agree.
local Items = {}

export type ItemDef = {
	id: string,
	name: string,
	description: string,
	price: number,
	kind: "consumable" | "unlock",
	cap: number,
	cooldown: number, -- seconds between uses (0 = none)
	icon: string, -- UIKit icon name
	color: Color3, -- icon / accent colour
	effect: { [string]: number }?, -- per-item tuning read by ItemService
}

Items.List = {
	{
		id = "speed_pills",
		name = "Speed Pills",
		description = "Twenty seconds of legs that don't argue. Don't read the label.",
		price = 40,
		kind = "consumable",
		cap = 5,
		cooldown = 25,
		icon = "pills",
		color = Color3.fromRGB(96, 198, 222),
		effect = { speed = 8, duration = 20 },
	},
	{
		id = "bandage",
		name = "Bandage Pack",
		description = "Wraps you back together, slowly. Smells like the shop.",
		price = 60,
		kind = "consumable",
		cap = 5,
		cooldown = 10,
		icon = "bandage",
		color = Color3.fromRGB(236, 226, 204),
		effect = { heal = 60, duration = 4 },
	},
	{
		id = "lockpicks",
		name = "Lockpicks",
		description = "For boxes that were never yours. Hold the prompt on a lock. One use each.",
		price = 80,
		kind = "consumable",
		cap = 5,
		cooldown = 0,
		icon = "lockpick",
		color = Color3.fromRGB(206, 174, 110),
	},
	{
		id = "laser_pointer",
		name = "Laser Pointer",
		description = "Shine it in their eyes. They hate that. Recharges in the library, not out there.",
		price = 400,
		kind = "unlock",
		cap = 1,
		cooldown = 0,
		icon = "laser",
		color = Color3.fromRGB(232, 66, 58),
	},
} :: { ItemDef }

local byId: { [string]: ItemDef } = {}
for _, def in Items.List do
	byId[def.id] = def
end

function Items.get(id: string?): ItemDef?
	return id and byId[id] or nil
end

function Items.isConsumable(id: string?): boolean
	local def = Items.get(id)
	return def ~= nil and def.kind == "consumable"
end

return Items
