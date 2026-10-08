-- Queue pads in front of the lobby doors. Standing on a pad joins it; when its countdown hits 0
-- the group is teleported to a private Trial server together.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DataService = require(ServerStorage.Common.DataService)

local QueueService = {}

type PadState = {
	model: Model,
	mode: string,
	capacity: number,
	zone: BasePart,
	exit: BasePart,
	members: { Player },
	countdown: number?,
	launching: boolean,
}

local pads: { PadState } = {}
local cooldownUntil: { [Player]: number } = {}

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function inZone(zone: BasePart, position: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function padOf(player: Player): PadState?
	for _, pad in pads do
		if table.find(pad.members, player) then
			return pad
		end
	end
	return nil
end

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function removeMember(pad: PadState, player: Player)
	local index = table.find(pad.members, player)
	if index then
		table.remove(pad.members, index)
		player:SetAttribute("QueuedPad", nil)
	end
end

-- Step the player off the pad so they don't instantly rejoin.
local function eject(pad: PadState, player: Player)
	removeMember(pad, player)
	cooldownUntil[player] = os.clock() + Config.LeaveCooldown
	local root = rootPart(player)
	if root then
		root.CFrame = CFrame.new(pad.exit.Position, pad.exit.Position + Vector3.new(0, 0, 1))
	end
end

local function updateDisplay(pad: PadState)
	local count = #pad.members
	local timeLeft = pad.countdown and math.max(0, math.ceil(pad.countdown)) or 0
	pad.model:SetAttribute("Count", count)
	pad.model:SetAttribute("TimeLeft", timeLeft)
	pad.model:SetAttribute("Launching", pad.launching)
	local sign = pad.model:FindFirstChild("Sign")
	local status = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Status")
	if status then
		if pad.launching then
			status.Text = "ENTERING..."
		elseif count == 0 then
			status.Text = string.format("0 / %d", pad.capacity)
		else
			status.Text = string.format("%d / %d  -  %ds", count, pad.capacity, timeLeft)
		end
	end
end

local function launch(pad: PadState)
	pad.launching = true
	local party = table.clone(pad.members)
	updateDisplay(pad)
	for _, player in party do
		notify(player, "The door creaks open...")
	end

	local mocked = Config.TrialPlaceId == 0 or RunService:IsStudio()
	if mocked then
		local names = {}
		for _, player in party do
			table.insert(names, player.Name)
		end
		print(
			string.format(
				"[QueueService] (mock) Would teleport %s party [%s] to Trial place %d",
				pad.mode,
				table.concat(names, ", "),
				Config.TrialPlaceId
			)
		)
		task.wait(1.5)
		for _, player in party do
			notify(player, "(Studio) Teleport mocked. Publish + set Config.TrialPlaceId to enter a real trial.")
			eject(pad, player)
		end
	else
		for _, player in party do
			DataService.saveForTeleport(player)
		end
		local ok, err = pcall(function()
			local accessCode = TeleportService:ReserveServer(Config.TrialPlaceId)
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = accessCode
			local userIds = {}
			for _, player in party do
				table.insert(userIds, player.UserId)
			end
			options:SetTeleportData({ mode = pad.mode, partySize = #party, party = userIds })
			TeleportService:TeleportAsync(Config.TrialPlaceId, party, options)
		end)
		if not ok then
			warn("[QueueService] Teleport failed: " .. tostring(err))
			for _, player in party do
				notify(player, "The door wouldn't open. Try again.")
				eject(pad, player)
			end
		else
			task.wait(10) -- give the teleport time; anyone still here gets released back to the lobby
			for _, player in party do
				if player.Parent then
					eject(pad, player)
				end
			end
		end
	end

	table.clear(pad.members)
	pad.countdown = nil
	pad.launching = false
	updateDisplay(pad)
end

local function step(dt: number)
	local now = os.clock()
	for _, pad in pads do
		if pad.launching then
			continue
		end

		-- drop anyone who left the zone, died or left the game
		for i = #pad.members, 1, -1 do
			local player = pad.members[i]
			local root = player.Parent and rootPart(player)
			if not root or not inZone(pad.zone, root.Position) then
				removeMember(pad, player)
			end
		end

		-- add players standing in the zone while there's room
		for _, player in Players:GetPlayers() do
			if #pad.members >= pad.capacity then
				break
			end
			local root = rootPart(player)
			if
				root
				and not padOf(player)
				and (cooldownUntil[player] or 0) < now
				and inZone(pad.zone, root.Position)
			then
				table.insert(pad.members, player)
				player:SetAttribute("QueuedPad", pad.model.Name)
			end
		end

		local count = #pad.members
		if count == 0 then
			pad.countdown = nil
		else
			pad.countdown = (pad.countdown or Config.QueueCountdown) - dt
			if count >= pad.capacity then
				pad.countdown = math.min(pad.countdown :: number, Config.FullQueueCountdown)
			end
			if (pad.countdown :: number) <= 0 then
				task.spawn(launch, pad)
			end
		end
		updateDisplay(pad)
	end
end

function QueueService.start(lobby: Instance)
	for _, model in lobby:WaitForChild("Pads"):GetChildren() do
		local mode = model:GetAttribute("Mode")
		table.insert(pads, {
			model = model,
			mode = mode,
			capacity = model:GetAttribute("Capacity") or Config.Modes[mode].capacity,
			zone = model:WaitForChild("Zone"),
			exit = model:WaitForChild("Exit"),
			members = {},
			countdown = nil,
			launching = false,
		})
	end

	Remotes.get("LeaveQueue").OnServerEvent:Connect(function(player)
		local pad = padOf(player)
		if pad and not pad.launching then
			eject(pad, player)
		end
	end)

	-- "PICK A DOOR" button: join people already waiting if anyone is, otherwise the nearest Solo door
	Remotes.get("QuickJoin").OnServerEvent:Connect(function(player)
		local root = rootPart(player)
		if not root or padOf(player) then
			return
		end
		local best, bestScore = nil, -math.huge
		for _, pad in pads do
			if not pad.launching and #pad.members < pad.capacity then
				local score = if #pad.members > 0
					then 10 + #pad.members / pad.capacity
					elseif pad.mode == "Solo" then 5
					else 1
				score -= (root.Position - pad.zone.Position).Magnitude / 1000 -- nearer wins a tie
				if score > bestScore then
					best, bestScore = pad, score
				end
			end
		end
		if not best then
			notify(player, "Every door is busy. Try again in a moment.")
			return
		end
		cooldownUntil[player] = nil
		local spot = best.zone.Position - Vector3.new(0, best.zone.Size.Y / 2 - 3, 0)
		root.CFrame = CFrame.lookAt(spot, spot + Vector3.new(0, 0, -1)) -- facing the door
	end)

	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
		local pad = padOf(player)
		if pad then
			removeMember(pad, player)
		end
	end)

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(string.format("[QueueService] TeleportInitFailed for %s: %s %s", player.Name, tostring(result), message))
		notify(player, "Teleport failed. Step on a pad to try again.")
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.2 then
			step(accumulated)
			accumulated = 0
		end
	end)
end

return QueueService
