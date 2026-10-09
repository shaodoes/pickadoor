--[[
	DoorRoomFlow: the trial's round state machine, as a module so it can run against any built Trial
	model: the real place's (Main.server.luau) or a preview inside the lobby place (see below).

	Phases (workspace attribute Phase; TimeLeft counts down once a second):
	  Waiting  until the party has arrived (deps.expectedPartySize(), 15 s grace), then 2 s
	  Pick     pickTime s. Each player's door is the Zone they stand in when it hits zero; nobody's
	           zone -> random. One door is the right one, chosen here, kept in a local and NEVER
	           replicated until the doors open.
	  Resolve  the leaves swing open; players are placed: right door -> SafeRoom.Arrive (Side "Safe"),
	           wrong door -> ThreatCorridor.Arrive (Side "Threat"); workspace.Revealed = the right door
	  Reveal   revealTime s on screen
	  Round    roundLength s: the Stalker hunts the threat side; a safe-side player may FOLLOW THEM IN
	           (the FollowIn remote or the safe room's prompt), once. Dying on the threat side ->
	           Alive = false and a respawn in the safe room as a spectator (a revive pass gives one
	           return to the corridor instead).
	  Reward   rewardTime s: safe -> Rewards.Blessing, threat survivors -> Rewards.Hunt, dead -> nothing
	  Return   returnTime s, then deps.returnToLobby() (teleport; mocked in Studio -> next round here)

	Per-player attributes: Side ("Door" | "Safe" | "Threat"), Picked ("Left" | "Right" | nil),
	Alive (bool), RevivesLeft (number).

	Running it inside the LOBBY place for a test (Studio Play, temporary Script):
	  -- ServerStorage.Prev_Trial = a mirror of src/trial/server (prun.sh), workspace.TrialPreview = the
	  -- map built with TrialBuilder.build({ parent = workspace, offset = Vector3.new(0, 0, 1200) })
	  local flow = require(game.ServerStorage.Prev_Trial.DoorRoomFlow)
	  local ctl = flow.start(workspace.TrialPreview, { expectedPartySize = function() return 1 end })
	  -- ctl.skip() ends the current phase early, ctl.phase() reads it, ctl.stop() tears it down.
	  Deps are optional: without DataService the rewards are only announced, without the FollowIn
	  remote only the safe room's prompt works. The overlay LocalScript reads the same attributes.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Sfx = require(Shared.Sfx)

local DoorRoomFlow = {}

export type Deps = {
	DataService: any?, -- rewards + stats (update(player, mutator))
	ChallengeService: any?, -- record(player, stat): rightDoor / trials / huntSurvived challenge progress
	Monetization: any?, -- ownsRevive(player)
	Stalker: any?, -- the Stalker module; defaults to script.Parent.Stalker when present
	returnToLobby: (() -> ())?, -- end of Return; return normally to run the next round here
	expectedPartySize: (() -> number)?, -- how many players to wait for (default 1)
	arrivalGrace: number?, -- seconds to wait for the rest of the party (default 15)
}

export type Controller = {
	stop: () -> (),
	skip: () -> (),
	phase: () -> string,
}

local SWING = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local RESPAWN_DELAY = 2.5

local function inZone(zone: BasePart, position: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function remote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function notify(player: Player, text: string)
	local r = remote("Notify")
	if r then
		r:FireClient(player, text)
	end
end

-- Swing a door's Leaf (and every part with Swing = true) about the leaf's hinge. The closed pose is
-- remembered in ClosedCFrame attributes the first time, so the doors can be shut again next round.
local function swingDoor(door: Instance, open: boolean)
	local leaf = door:FindFirstChild("Leaf") :: BasePart?
	if not leaf then
		return
	end
	local closed = leaf:GetAttribute("ClosedCFrame")
	if typeof(closed) ~= "CFrame" then
		closed = leaf.CFrame
		leaf:SetAttribute("ClosedCFrame", closed)
	end
	local hinge = closed * CFrame.new(leaf:GetAttribute("HingeX") or 0, 0, 0)
	local angle = open and (leaf:GetAttribute("SwingAngle") or 0) or 0
	local about = hinge * CFrame.Angles(0, angle, 0) * hinge:Inverse() -- rotates world space about the hinge
	for _, part in door:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Swing") then
			local rest = part:GetAttribute("ClosedCFrame")
			if typeof(rest) ~= "CFrame" then
				rest = part.CFrame
				part:SetAttribute("ClosedCFrame", rest)
			end
			TweenService:Create(part, open and SWING or SHUT, { CFrame = about * rest }):Play()
		end
	end
	if open then
		Sfx.at(leaf, "DoorSwing")
	end
end

-- Lights the builder tagged with a Flicker attribute: true blinks (the glowing core and its halo go
-- dark with it), "furnace" breathes. FlickerRate = chance per 0.12 s tick to blink.
local function runFlicker(trial: Model, isRunning: () -> boolean)
	local lights = {}
	for _, inst in trial:GetDescendants() do
		if inst:IsA("Light") and inst:GetAttribute("Flicker") then
			table.insert(lights, {
				light = inst,
				base = inst.Brightness,
				kind = inst:GetAttribute("Flicker"),
				rate = inst:GetAttribute("FlickerRate") or 0.03,
			})
		end
	end
	while isRunning() do
		for _, entry in lights do
			if entry.kind == "furnace" then
				entry.light.Brightness = entry.base * (0.8 + math.random() * 0.35)
			elseif math.random() < entry.rate then
				local core = entry.light.Parent
				local glow = core and core:FindFirstChild("Halo")
				entry.light.Brightness = 0
				if core and core:IsA("BasePart") then
					core.Transparency = 0.85
				end
				if glow then
					glow.Enabled = false
				end
				task.delay(0.05 + math.random() * 0.3, function()
					entry.light.Brightness = entry.base
					if core and core:IsA("BasePart") then
						core.Transparency = 0.35
					end
					if glow then
						glow.Enabled = true
					end
				end)
			end
		end
		task.wait(0.12)
	end
end

function DoorRoomFlow.start(trial: Model, deps: Deps?): Controller
	local d: Deps = deps or {}
	local flow = Config.DoorRoomFlow
	local doorRoom = trial:WaitForChild("DoorRoom")
	local doors = doorRoom:WaitForChild("Doors")
	local leftDoor, rightDoor = doors:WaitForChild("Left"), doors:WaitForChild("Right")
	local zones =
		{ Left = leftDoor:WaitForChild("Zone") :: BasePart, Right = rightDoor:WaitForChild("Zone") :: BasePart }
	local spawnPoint = doorRoom:WaitForChild("Spawn") :: BasePart
	local safeRoom = trial:WaitForChild("SafeRoom")
	local corridor = trial:WaitForChild("ThreatCorridor")
	local safeArrive = (safeRoom:WaitForChild("Arrive") :: BasePart).CFrame
	local threatArrive = (corridor:WaitForChild("Arrive") :: BasePart).CFrame
	local doorSpawn = spawnPoint.CFrame * CFrame.new(0, 3, 0) -- a character's pivot sits ~3 studs up
	local stalkerModel = corridor:FindFirstChild("Stalker")

	local running = true
	local phase = "Waiting"
	local skipRequested = false
	local connections: { RBXScriptConnection } = {}
	local respawnToken: { [Player]: number } = {}

	local function setPhase(name: string, seconds: number?)
		phase = name
		workspace:SetAttribute("Phase", name)
		workspace:SetAttribute("TimeLeft", seconds or 0)
	end

	local function countdown(seconds: number)
		for t = seconds, 1, -1 do
			if not running or skipRequested then
				break
			end
			workspace:SetAttribute("TimeLeft", t)
			task.wait(1)
		end
		skipRequested = false
		workspace:SetAttribute("TimeLeft", 0)
	end

	-- The stalker only ever hunts living players on the threat side, and only during the round.
	local StalkerModule = d.Stalker
	if not StalkerModule and script.Parent:FindFirstChild("Stalker") then
		StalkerModule = require(script.Parent.Stalker)
	end
	local stalker = nil
	if stalkerModel and StalkerModule then
		stalker = StalkerModule.start(stalkerModel, {
			home = (corridor:WaitForChild("End") :: BasePart).CFrame,
			isTarget = function(player: Player)
				return phase == "Round"
					and player:GetAttribute("Side") == "Threat"
					and player:GetAttribute("Alive") == true
			end,
		})
	end

	-- Characters: this module owns spawning so a dead player comes back where the round says.
	local previousAutoLoads = Players.CharacterAutoLoads
	Players.CharacterAutoLoads = false

	-- Pivot a character to an Arrive CFrame, clustered so a party doesn't spawn inside each other.
	local function placeAt(player: Player, at: CFrame, index: number)
		local character = player.Character
		if not character then
			return
		end
		-- 1st on the spot, then alternating left / right of it, a row back every four
		local k = (index - 1) % 4
		local dx = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * 2.4
		character:PivotTo(at * CFrame.new(dx, 0, ((index - 1) // 4) * 2.6))
	end

	local function spawnAt(player: Player, at: CFrame, index: number)
		if not player.Parent then
			return
		end
		player:LoadCharacter()
		local character = player.Character
		if not character then
			local started = os.clock()
			repeat
				task.wait()
				character = player.Character
			until character or os.clock() - started > 5 or not player.Parent
		end
		if character then
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait() -- let the spawn settle before overriding it
			placeAt(player, at, index)
		end
	end

	local onDied -- forward declaration (hookCharacter <-> onDied)

	local function hookCharacter(player: Player, character: Model)
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
			if humanoid then
				humanoid.Died:Once(function()
					onDied(player)
				end)
			end
		end)
	end

	onDied = function(player: Player)
		if not running then
			return
		end
		local token = (respawnToken[player] or 0) + 1
		respawnToken[player] = token
		local onThreat = phase == "Round" and player:GetAttribute("Side") == "Threat"
		if onThreat and (player:GetAttribute("RevivesLeft") or 0) > 0 then
			-- the revive pass: one trip back into the corridor
			player:SetAttribute("RevivesLeft", player:GetAttribute("RevivesLeft") - 1)
			task.delay(RESPAWN_DELAY, function()
				if running and respawnToken[player] == token and phase == "Round" and player.Parent then
					spawnAt(player, threatArrive, 1)
					player:SetAttribute("Alive", true)
					notify(player, "Revived. Keep moving.")
				end
			end)
			return
		end
		if onThreat then
			player:SetAttribute("Alive", false)
		end
		task.delay(RESPAWN_DELAY, function()
			if not running or respawnToken[player] ~= token or not player.Parent then
				return
			end
			if onThreat and (phase == "Round" or phase == "Reward") then
				player:SetAttribute("Side", "Safe")
				spawnAt(player, safeArrive, 1)
				notify(player, "You didn't make it. Watch from the warm side.")
				return
			end
			-- died anywhere else (fell, the safe side): come back where you were
			local side = player:GetAttribute("Side")
			local at = if side == "Safe" then safeArrive elseif side == "Threat" then threatArrive else doorSpawn
			spawnAt(player, at, 1)
		end)
	end

	local function onPlayer(player: Player)
		player:SetAttribute("Side", "Door")
		player:SetAttribute("Alive", true)
		player:SetAttribute("Picked", nil)
		table.insert(
			connections,
			player.CharacterAdded:Connect(function(character)
				hookCharacter(player, character)
			end)
		)
		if player.Character then
			hookCharacter(player, player.Character)
		else
			task.spawn(spawnAt, player, doorSpawn, 1)
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(onPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			respawnToken[player] = nil
		end)
	)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- FOLLOW THEM IN: a living safe-side player, during the round, once (there's no way back)
	local function followIn(player: Player)
		if not running or phase ~= "Round" then
			return
		end
		if player:GetAttribute("Side") ~= "Safe" or player:GetAttribute("Alive") ~= true then
			return
		end
		player:SetAttribute("Side", "Threat")
		placeAt(player, threatArrive, 1)
		notify(player, "You followed them in.")
	end
	local followDoor = safeRoom:FindFirstChild("FollowDoor")
	local slab = followDoor and followDoor:FindFirstChild("Slab")
	local prompt = slab and slab:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		table.insert(connections, prompt.Triggered:Connect(followIn))
	end
	local followRemote = remote("FollowIn")
	if followRemote then
		table.insert(connections, followRemote.OnServerEvent:Connect(followIn))
	end

	local function pickFor(player: Player): string
		local root = rootOf(player)
		if root then
			for name, zone in zones do
				if inZone(zone, root.Position) then
					return name
				end
			end
		end
		return math.random() < 0.5 and "Left" or "Right" -- nobody's zone: the doors decide
	end

	local function runRound()
		setPhase("Waiting")
		workspace:SetAttribute("Revealed", nil)
		swingDoor(leftDoor, false)
		swingDoor(rightDoor, false)
		if stalker then
			stalker.setActive(false)
			stalker.reset()
		end
		for _, player in Players:GetPlayers() do
			player:SetAttribute("Side", "Door")
			player:SetAttribute("Picked", nil)
			player:SetAttribute("Alive", true)
		end
		while running and #Players:GetPlayers() == 0 do
			task.wait(0.5)
		end
		if not running then
			return
		end
		-- give the rest of the party a moment to arrive
		local expected = d.expectedPartySize and d.expectedPartySize() or 1
		local deadline = os.clock() + (d.arrivalGrace or 15)
		while running and #Players:GetPlayers() < expected and os.clock() < deadline and not skipRequested do
			task.wait(0.5)
		end
		skipRequested = false
		task.wait(2)
		for _, player in Players:GetPlayers() do
			local revives = (d.Monetization and d.Monetization.ownsRevive(player)) and 1 or 0
			player:SetAttribute("RevivesLeft", revives)
		end

		-- PICK. The right door is a local until Resolve: nothing about it reaches a client.
		local rightDoorName = math.random() < 0.5 and "Left" or "Right"
		setPhase("Pick", flow.pickTime)
		countdown(flow.pickTime)
		if not running then
			return
		end

		-- RESOLVE
		if not running then
			return
		end
		setPhase("Resolve", 0)
		local placements = {}
		for _, player in Players:GetPlayers() do
			local picked = pickFor(player)
			player:SetAttribute("Picked", picked)
			table.insert(placements, { player = player, safe = picked == rightDoorName })
		end
		swingDoor(leftDoor, true)
		swingDoor(rightDoor, true)
		workspace:SetAttribute("Revealed", rightDoorName)
		task.wait(1.4) -- let the leaves swing before anyone moves
		local safeCount, threatCount = 0, 0
		for _, p in placements do
			if p.player.Parent then
				if p.safe then
					if d.ChallengeService then
						d.ChallengeService.record(p.player, "rightDoor")
					end
					safeCount += 1
					p.player:SetAttribute("Side", "Safe")
					placeAt(p.player, safeArrive, safeCount)
				else
					threatCount += 1
					p.player:SetAttribute("Side", "Threat")
					placeAt(p.player, threatArrive, threatCount)
				end
			end
		end
		setPhase("Reveal", flow.revealTime)
		countdown(flow.revealTime)
		if not running then
			return
		end

		-- ROUND
		setPhase("Round", flow.roundLength)
		if stalker then
			stalker.setActive(true)
		end
		countdown(flow.roundLength)
		if stalker then
			stalker.setActive(false)
		end
		if not running then
			return
		end

		-- REWARD
		setPhase("Reward", flow.rewardTime)
		for _, player in Players:GetPlayers() do
			local side = player:GetAttribute("Side")
			local alive = player:GetAttribute("Alive") == true
			local reward, line = 0, nil
			if side == "Door" then
				line = "You missed this round. Next time, pick a door."
			elseif not alive then
				line = "You didn't make it. No keys this time."
			elseif side == "Threat" then
				reward = Config.Rewards.Hunt
				line = string.format("You survived it: +%d %s", reward, Config.CurrencyName)
			else
				reward = Config.Rewards.Blessing
				line = string.format("The right door: +%d %s", reward, Config.CurrencyName)
			end
			if d.DataService and side ~= "Door" then
				d.DataService.update(player, function(data)
					data.Keys += reward
					data.TrialsPlayed += 1
					if alive then
						data.TrialsSurvived += 1
					end
				end)
			end
			if d.ChallengeService and side ~= "Door" then
				d.ChallengeService.record(player, "trials")
				if side == "Threat" and alive then
					d.ChallengeService.record(player, "huntSurvived")
				end
			end
			notify(player, line)
		end
		countdown(flow.rewardTime)
		if not running then
			return
		end

		-- RETURN
		setPhase("Return", flow.returnTime)
		countdown(flow.returnTime)
		if not running then
			return
		end
		if d.returnToLobby then
			d.returnToLobby()
		end
		-- anyone still here (mocked or failed teleport) goes back to the door room for the next round
		for i, player in Players:GetPlayers() do
			player:SetAttribute("Side", "Door")
			spawnAt(player, doorSpawn, i)
		end
	end

	task.spawn(runFlicker, trial, function()
		return running
	end)
	task.spawn(function()
		while running do
			local ok, err = pcall(runRound)
			if not ok then
				warn("[DoorRoomFlow] Round error: " .. tostring(err))
				task.wait(2)
			end
		end
	end)

	return {
		stop = function()
			running = false
			skipRequested = true
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			if stalker then
				stalker.stop()
			end
			Players.CharacterAutoLoads = previousAutoLoads
			setPhase("Stopped")
		end,
		skip = function()
			skipRequested = true
		end,
		phase = function()
			return phase
		end,
	}
end

return DoorRoomFlow
