--[[
	Trial place entry point. Builds the map if it isn't baked into the place, starts the shared
	services and hands the round loop to DoorRoomFlow (that module documents the phases and the
	attributes the client overlay reads).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
Remotes.setup()

local Common = ServerStorage:WaitForChild("Common")
local DataService = require(Common.DataService)
local Monetization = require(Common.Monetization)
local LanternService = require(Common.LanternService)
local DoorRoomFlow = require(script.Parent.DoorRoomFlow)
local Stalker = require(script.Parent.Stalker)

local trial = workspace:FindFirstChild("Trial") or require(ServerStorage.Builders.TrialBuilder).build()

DataService.start()
Monetization.start()
LanternService.start()

-- ItemService (items, laser, lockpicks) is written by the items specialist; the trial runs
-- without it until it lands, so look for it instead of requiring it outright.
local itemService = Common:FindFirstChild("ItemService")
if itemService then
	local ok, err = pcall(function()
		require(itemService).start({ recharge = false })
	end)
	if not ok then
		warn("[Trial] ItemService failed to start: " .. tostring(err))
	end
else
	warn("[Trial] ItemService not found; items are disabled this session.")
end

-- The lobby's QueueService teleports a party with TeleportData { mode, partySize, party }.
local expectedPartySize = 1
Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if typeof(teleportData) == "table" and typeof(teleportData.partySize) == "number" then
		expectedPartySize = math.clamp(teleportData.partySize, 1, 4)
	end
end)

-- Back to the lobby. Returning normally means the teleport didn't happen (mocked in Studio, or it
-- failed) and DoorRoomFlow runs the next round here instead.
local function returnToLobby()
	local players = Players:GetPlayers()
	if Config.LobbyPlaceId ~= 0 and not RunService:IsStudio() and #players > 0 then
		for _, player in players do
			DataService.saveForTeleport(player)
		end
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, Config.LobbyPlaceId, players)
		if ok then
			return
		end
		warn("[Trial] Return teleport failed: " .. tostring(err))
	end
	print("[Trial] (mock) Returning players to the lobby; restarting the round instead.")
end

DoorRoomFlow.start(trial, {
	DataService = DataService,
	Monetization = Monetization,
	Stalker = Stalker,
	returnToLobby = returnToLobby,
	expectedPartySize = function()
		return expectedPartySize
	end,
})
