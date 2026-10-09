-- Queue pads in front of the lobby doors. Standing on a pad joins it; when its countdown hits 0
-- the party plays the door-entry cutscene (Shared/DoorEntry: the door creaks open, they walk into the
-- black one by one, it slams) and is then teleported to a private Trial server together.
-- The server owns the timing: it stamps the pad's CutsceneStart, walks everyone in, waits out the
-- sequence and only then teleports (or, in Studio, mocks it and puts them back at the pad's Exit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DoorEntry = require(Shared.DoorEntry)
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

-- The cutscene is over for this player (their client fades back in when the attribute clears).
local function endCutscene(player: Player)
	player:SetAttribute("CutscenePad", nil)
	player:SetAttribute("CutsceneSlot", nil)
end

-- The leaf is swung client-side only, so while the party walks through, its server copy must not block them.
local function setLeafSolid(pad: PadState, solid: boolean)
	local leaf = pad.model:FindFirstChild("Leaf")
	if not leaf then
		return
	end
	for _, part in leaf:GetDescendants() do
		if part:IsA("BasePart") then
			if solid then
				local was = part:GetAttribute("CutsceneCollide")
				if was ~= nil then
					part.CanCollide = was
					part:SetAttribute("CutsceneCollide", nil)
				end
			elseif part:GetAttribute("CutsceneCollide") == nil then
				part:SetAttribute("CutsceneCollide", part.CanCollide)
				part.CanCollide = false
			end
		end
	end
end

-- An invisible floor and stops in the black passage behind the door, so whoever walks in stands on
-- something and can't wander out of the back of the wall.
local function buildWalkIn(pad: PadState)
	if pad.model:FindFirstChild("WalkIn") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "WalkIn"
	local f = DoorEntry.frame(pad.model)
	local function block(name: string, size: Vector3, offset: Vector3)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		-- pitch black (Neon black never catches light), so the light pouring out of the cutscene
		-- doorway can't reveal the plaster behind it: the passage reads as a void, not a cupboard
		part.Color = Color3.new(0, 0, 0)
		part.Material = Enum.Material.Neon
		part.Size = size
		part.CFrame = f * CFrame.new(offset)
		part.Parent = folder
	end
	block("Floor", Vector3.new(5.4, 0.4, 4.4), Vector3.new(0, -0.18, -2.1)) -- just proud of the plaster below
	block("Back", Vector3.new(5.6, 10, 0.4), Vector3.new(0, 5, -4.15))
	block("SideL", Vector3.new(0.4, 10, 4.4), Vector3.new(-2.9, 5, -2.1))
	block("SideR", Vector3.new(0.4, 10, 4.4), Vector3.new(2.9, 5, -2.1))
	folder.Parent = pad.model
end

-- Server half of the walk (the player's own client walks the same path locally; both aim at the same points).
local function walkIn(pad: PadState, player: Player, slot: number, count: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 or not pad.launching then
		return
	end
	for _, point in DoorEntry.walkPoints(pad.model, slot, count) do
		humanoid:MoveTo(point)
		local t0 = os.clock()
		while os.clock() - t0 < 1.4 do
			task.wait(0.05)
			if not player.Parent or humanoid.Health <= 0 or not root.Parent or not pad.launching then
				return
			end
			if ((root.Position - point) * Vector3.new(1, 0, 1)).Magnitude < 1 then
				break
			end
		end
	end
end

-- Anyone who isn't in the party but followed them into the passage is put back out in the hall.
local function clearPassage(pad: PadState, party: { Player })
	for _, player in Players:GetPlayers() do
		local root = rootPart(player)
		if root and not table.find(party, player) and DoorEntry.inside(pad.model, root.Position, 0.3) then
			root.CFrame = CFrame.new(pad.exit.Position, pad.exit.Position + Vector3.new(0, 0, 1))
		end
	end
end

local function launch(pad: PadState)
	pad.launching = true
	local party = table.clone(pad.members)

	-- start the door-entry cutscene a beat ahead so every client begins it in step
	local start = workspace:GetServerTimeNow() + DoorEntry.LEAD
	pad.model:SetAttribute("CutsceneStart", start)
	pad.model:SetAttribute("CutsceneCount", #party)
	for i, player in party do
		player:SetAttribute("CutsceneSlot", i)
		player:SetAttribute("CutscenePad", pad.model.Name)
	end
	updateDisplay(pad)
	setLeafSolid(pad, false)
	for i, player in party do
		task.delay(DoorEntry.LEAD + DoorEntry.walkStart(i), walkIn, pad, player, i, #party)
	end
	-- the server is the clock: nothing teleports until the whole sequence (and its title card) has played
	task.wait(math.max(0, start + DoorEntry.LENGTH - workspace:GetServerTimeNow()))
	setLeafSolid(pad, true)
	clearPassage(pad, party)

	-- whoever left the game mid-cutscene is simply dropped from the party
	for i = #party, 1, -1 do
		if not party[i].Parent then
			table.remove(party, i)
		end
	end

	local mocked = Config.TrialPlaceId == 0 or RunService:IsStudio() or #party == 0
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
		-- back out at the pad's Exit while the screen is still black, then the clients fade in
		for _, player in party do
			eject(pad, player)
			endCutscene(player)
		end
		task.wait(0.6)
		for _, player in party do
			if player.Parent then
				notify(player, "(Studio) Teleport mocked. Publish + set Config.TrialPlaceId to enter a real trial.")
			end
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
				eject(pad, player)
				endCutscene(player)
				notify(player, "The door wouldn't open. Try again.")
			end
		else
			-- the screen stays black on the title card while the teleport goes through; anyone still
			-- here after 10 s is released back to the lobby
			task.wait(10)
			for _, player in party do
				if player.Parent then
					eject(pad, player)
					endCutscene(player)
				end
			end
		end
	end

	for _, player in party do
		if player.Parent and player:GetAttribute("CutscenePad") == pad.model.Name then
			endCutscene(player)
		end
	end
	table.clear(pad.members)
	pad.countdown = nil
	pad.launching = false
	pad.model:SetAttribute("CutsceneStart", nil)
	pad.model:SetAttribute("CutsceneCount", nil)
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
		local pad: PadState = {
			model = model,
			mode = mode,
			capacity = model:GetAttribute("Capacity") or Config.Modes[mode].capacity,
			zone = model:WaitForChild("Zone"),
			exit = model:WaitForChild("Exit"),
			members = {},
			countdown = nil,
			launching = false,
		}
		table.insert(pads, pad)
		buildWalkIn(pad)
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
		-- don't leave them sitting on the black title card until the launch times out
		local pad = padOf(player)
		if pad and pad.launching and player:GetAttribute("CutscenePad") then
			eject(pad, player)
			endCutscene(player)
		end
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
