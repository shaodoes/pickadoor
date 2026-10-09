--[[
	The Shopkeeper, "Teeth", behind the gift-shop counter. The figure itself is built by
	Builders/Npcs/Shopkeeper and baked into the lobby by LobbyBuilder; this adopts that copy
	(Lobby.Shopkeeper) or builds one if the lobby doesn't have it. He is anchored parts with his rest
	pose in attributes: Shopkeeper.client animates him, the shop panel opens from his prompt.
]]
local ServerStorage = game:GetService("ServerStorage")

local Npcs = require(ServerStorage:WaitForChild("Builders"):WaitForChild("Npcs"))

local ShopkeeperService = {}

function ShopkeeperService.start(lobby: Instance): Model
	local model = lobby:FindFirstChild("Shopkeeper")
	if model and model:IsA("Model") then
		return model
	end
	return Npcs.buildShopkeeper(lobby)
end

return ShopkeeperService
