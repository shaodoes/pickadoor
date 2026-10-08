-- Game pass ownership. Sets the "HasRevivePass" attribute on each player.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Monetization = {}

local reviveOwners: { [Player]: boolean } = {}

function Monetization.ownsRevive(player: Player): boolean
	if Config.ReviveGamePassId == 0 then
		return false
	end
	if reviveOwners[player] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.ReviveGamePassId)
		end)
		reviveOwners[player] = ok and owns or false
	end
	return reviveOwners[player]
end

function Monetization.start()
	local function onPlayer(player: Player)
		player:SetAttribute("HasRevivePass", Monetization.ownsRevive(player))
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		reviveOwners[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.ReviveGamePassId then
			reviveOwners[player] = true
			player:SetAttribute("HasRevivePass", true)
			Remotes.get("Notify"):FireClient(player, "Revive unlocked: once per trial, you can come back.")
		end
	end)
end

return Monetization
