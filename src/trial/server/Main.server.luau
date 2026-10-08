--[[
	Trial place entry point (stub). Flow per round:
		Waiting -> Pick (stand at a door, Config.DoorPickTime) -> Reveal -> Trial (placeholder) -> Return
	Phase state is published as Workspace attributes for the client overlay:
		Phase, TimeLeft, FateName, FateKind, FateBlurb, VotesLeft, VotesRight
	Real liminal maps will replace the "Trial" phase.
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

local room = workspace:FindFirstChild("DoorRoom") or require(ServerStorage.Builders.TrialBuilder).build()

DataService.start()
Monetization.start()
LanternService.start()

local expectedPartySize = 1
local revivesLeft: { [Player]: number } = {}

Players.PlayerAdded:Connect(function(player)
	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData
	if typeof(teleportData) == "table" and typeof(teleportData.partySize) == "number" then
		expectedPartySize = math.clamp(teleportData.partySize, 1, 4)
	end
end)

local function setPhase(phase: string, seconds: number?)
	workspace:SetAttribute("Phase", phase)
	workspace:SetAttribute("TimeLeft", seconds or 0)
end

local function countdown(seconds: number, onTick: (() -> ())?)
	for t = seconds, 1, -1 do
		workspace:SetAttribute("TimeLeft", t)
		if onTick then
			onTick()
		end
		task.wait(1)
	end
	workspace:SetAttribute("TimeLeft", 0)
end

local function playersInZone(zone: BasePart): number
	local count = 0
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local rel = zone.CFrame:PointToObjectSpace(root.Position)
			local half = zone.Size / 2
			if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
				count += 1
			end
		end
	end
	return count
end

local function pickTwoFates()
	local pool = table.clone(Config.Fates)
	local a = table.remove(pool, math.random(#pool))
	local b = table.remove(pool, math.random(#pool))
	return a, b
end

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
	print("[Trial] (mock) Returning players to the lobby; restarting round instead.")
	for _, player in players do
		player:LoadCharacter()
	end
end

local function runRound()
	setPhase("Waiting")
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
	-- give the rest of the party a moment to arrive
	local deadline = os.clock() + 15
	while #Players:GetPlayers() < expectedPartySize and os.clock() < deadline do
		task.wait(0.5)
	end
	task.wait(2)

	for _, player in Players:GetPlayers() do
		revivesLeft[player] = Monetization.ownsRevive(player) and 1 or 0
		player:SetAttribute("RevivesLeft", revivesLeft[player])
	end

	local leftFate, rightFate = pickTwoFates()
	local leftZone = room.Doors.Left.Zone
	local rightZone = room.Doors.Right.Zone

	setPhase("Pick", Config.DoorPickTime)
	countdown(Config.DoorPickTime, function()
		workspace:SetAttribute("VotesLeft", playersInZone(leftZone))
		workspace:SetAttribute("VotesRight", playersInZone(rightZone))
	end)
	local votesLeft, votesRight = playersInZone(leftZone), playersInZone(rightZone)
	local fate
	if votesLeft == votesRight then
		fate = math.random() < 0.5 and leftFate or rightFate -- tie or nobody chose: the doors decide
	else
		fate = votesLeft > votesRight and leftFate or rightFate
	end

	workspace:SetAttribute("FateName", fate.name)
	workspace:SetAttribute("FateKind", fate.kind)
	workspace:SetAttribute("FateBlurb", fate.blurb)
	setPhase("Reveal", 5)
	countdown(5)

	-- TODO(trials): load the liminal map for `fate.id` here and run it for Config.TrialDuration.
	setPhase("Trial", Config.StubTrialDuration)
	countdown(Config.StubTrialDuration)

	local reward = Config.Rewards[fate.kind] or 0
	for _, player in Players:GetPlayers() do
		DataService.update(player, function(d)
			d.Keys += reward
			d.TrialsPlayed += 1
			d.TrialsSurvived += 1
		end)
		Remotes.get("Notify"):FireClient(player, string.format("Trial survived: +%d %s", reward, Config.CurrencyName))
	end

	setPhase("Return", 5)
	countdown(5)
	returnToLobby()
end

Players.PlayerRemoving:Connect(function(player)
	revivesLeft[player] = nil
end)

while true do
	local ok, err = pcall(runRound)
	if not ok then
		warn("[Trial] Round error: " .. tostring(err))
		task.wait(2)
	end
end
