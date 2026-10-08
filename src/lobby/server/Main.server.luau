-- Lobby place entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
Remotes.setup()

local Common = ServerStorage:WaitForChild("Common")
local DataService = require(Common.DataService)
local Monetization = require(Common.Monetization)
local LanternService = require(Common.LanternService)

-- The map is normally baked into the place; build it on the fly if it isn't.
local lobby = workspace:FindFirstChild("Lobby")
if not lobby then
	lobby = require(ServerStorage.Builders.LobbyBuilder).build()
end

DataService.start()
Monetization.start()
LanternService.start()
require(script.Parent.ShopService).start()
require(script.Parent.QueueService).start(lobby)
require(script.Parent.LeaderboardService).start(lobby)
