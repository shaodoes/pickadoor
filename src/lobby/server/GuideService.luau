-- The Librarian: a tall, quiet guide standing in the foyer with a lantern. Built by
-- Builders/Npcs/Librarian and baked into the lobby by LobbyBuilder; this adopts that copy
-- (Lobby.Guide, plus his Lectern) or builds them if missing, then starts his idle. Players talk to
-- him (ProximityPrompt, Panel = "Guide"); the dialogue itself runs in Guide.client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local DataService = require(ServerStorage.Common.DataService)
local Npcs = require(ServerStorage:WaitForChild("Builders"):WaitForChild("Npcs"))

local GuideService = {}

function GuideService.start(lobby: Instance)
	local guide = lobby:FindFirstChild("Guide")
	if not (guide and guide:IsA("Model")) then
		guide = Npcs.buildGuide(lobby)
	end
	if guide then
		Npcs.playIdle(guide :: Model)
	end
	Remotes.get("GuideSeen").OnServerEvent:Connect(function(player)
		DataService.update(player, function(data)
			data.SeenGuide = true
		end)
	end)
end

return GuideService
