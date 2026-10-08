-- Puts the player's equipped lantern in their hand every time they spawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LanternBuilder = require(Shared.LanternBuilder)
local DataService = require(script.Parent.DataService)

local LanternService = {}

local function removeExisting(player: Player)
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item.Name == "Lantern" then
					item:Destroy()
				end
			end
		end
	end
end

function LanternService.give(player: Player)
	local data = DataService.waitFor(player)
	local character = player.Character
	if not data or not character then
		return
	end
	removeExisting(player)
	local tool = LanternBuilder.buildTool(data.EquippedLantern)
	tool.Parent = player:WaitForChild("Backpack")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

function LanternService.start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid")
			LanternService.give(player)
		end)
		if player.Character then
			task.spawn(LanternService.give, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return LanternService
