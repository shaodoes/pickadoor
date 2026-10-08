-- Server-validated lantern purchases and equipping.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lanterns = require(Shared.Lanterns)
local Remotes = require(Shared.Remotes)
local DataService = require(ServerStorage.Common.DataService)
local LanternService = require(ServerStorage.Common.LanternService)

local ShopService = {}

local function result(ok: boolean, message: string)
	return { ok = ok, message = message }
end

function ShopService.buyLantern(player: Player, id: any)
	if typeof(id) ~= "string" then
		return result(false, "Invalid item.")
	end
	local def = Lanterns.get(id)
	local data = DataService.get(player)
	if not def or not data then
		return result(false, "Invalid item.")
	end
	if data.OwnedLanterns[id] then
		return result(false, "You already own " .. def.name .. ".")
	end
	if data.Keys < def.price then
		return result(
			false,
			string.format("Not enough %s (%d more needed).", Config.CurrencyName, def.price - data.Keys)
		)
	end
	DataService.update(player, function(d)
		d.Keys -= def.price
		d.OwnedLanterns[id] = true
	end)
	return result(true, "Purchased " .. def.name .. ".")
end

function ShopService.equipLantern(player: Player, id: any)
	if typeof(id) ~= "string" then
		return result(false, "Invalid lantern.")
	end
	local def = Lanterns.get(id)
	local data = DataService.get(player)
	if not def or not data then
		return result(false, "Invalid lantern.")
	end
	if not data.OwnedLanterns[id] then
		return result(false, "You don't own " .. def.name .. " yet.")
	end
	DataService.update(player, function(d)
		d.EquippedLantern = id
	end)
	task.spawn(LanternService.give, player)
	return result(true, def.name .. " equipped.")
end

function ShopService.start()
	Remotes.get("BuyLantern").OnServerInvoke = ShopService.buyLantern
	Remotes.get("EquipLantern").OnServerInvoke = ShopService.equipLantern
end

return ShopService
