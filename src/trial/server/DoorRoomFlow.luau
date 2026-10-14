--[[
	DoorRoomFlow: the trial's round state machine, as a module so it can run against any built Trial
	model: the real place's (Main.server.luau) or a preview inside the lobby place (see below).

	Each round draws a pair of worlds (Shared.Worlds.drawPair: one safe, one dangerous). The doors are
	fixed, red = Left and blue = Right; which of them is the safe one is a coin flip. The pair and the
	safe door live in locals here and NEVER replicate before a player commits; the worlds are built (and
	kept) in ServerStorage until their first player enters (WorldHost).

	Phases (workspace attribute Phase; TimeLeft counts down once a second where there is a countdown):
	  Waiting  until the party has arrived (deps.expectedPartySize(), arrivalGrace s), then 2 s. The
	           clients hold a black screen.
	  Pick     pickTime s (15). Everyone is placed at the Spawn facing the doors (first person, client).
	           Walking into a door's Zone commits you (server-checked, 10x a second): DoorEvent "commit"
	           goes to you alone with your world, and the door sequence plays on the shared DoorPick
	           timeline (the first player at a door opens it, later ones breathe at the open door); at its
	           end WorldHost.enter puts you at your world's Arrive. The first player into a world starts
	           that world's round (its escalation timer counts from then). Nobody in a Zone when the time
	           runs out: DoorEvent "glitch", the room tears apart around them, then they die (no world).
	  Round    no countdown. Ends when nobody is picking, committing or inside a world. Escaping pays at
	           once (WorldHost); the dead and the finished wait in DoorRoom.Hold and spectate. A lounge
	           player may FOLLOW THEM IN (the FollowIn remote or the lounge's FollowDoor) while someone is
	           in the dangerous world. Lounges close loungeCloseAfter s after the dangerous side is done
	           (but not before they've been open a minute); the hidden cap (Config.Worlds.hardCap) closes
	           everything.
	  Return   returnTime s, then deps.returnToLobby() (teleport; mocked in Studio -> next round here)

	Per-player attributes: Status ("Door" | "Committing" | "Glitch" | "In" | "Escaped" | "Dead" |
	"Spectating"), Picked ("Left" | "Right", after the commit), World (WorldHost), RevivesLeft.
	Death inside a dangerous world: a revive pass sends you back to its Arrive once; otherwise you're out
	(Status Dead) and respawn at the Hold. Death in a lounge respawns you in the lounge.

	Studio-only debug (workspace attributes, read while running):
	  DebugPair       "safeId,dangerId" forces the pair (e.g. "_test_lounge,_test_hunt")
	  DebugSide       "Left" | "Right": which door is the safe one
	  DebugEscalateAt seconds into a dangerous world's round before it escalates (WorldHost)
	  DebugSkip       true: end the current phase now (cleared after use)
	  DebugOpenDoor   "Left" | "Right" during Pick: that door opens as if another player had opened it
	                  (the next player to walk up gets the "already open" breath; cleared after use)

	Running it inside the LOBBY place for a test (Studio Play, temporary Script):
	  -- ServerStorage.Prev_Trial = a mirror of src/trial/server, workspace.TrialPreview = the map built
	  -- with TrialBuilder.build({ parent = workspace, offset = Vector3.new(0, 0, 1200) }), and
	  -- ServerStorage.Builders = src/trial/builders (WorldHost builds the worlds from it)
	  local flow = require(game.ServerStorage.Prev_Trial.DoorRoomFlow)
	  local ctl = flow.start(workspace.TrialPreview, { expectedPartySize = function() return 1 end })
	  -- ctl.skip() ends the current phase early, ctl.phase() reads it, ctl.stop() tears it down.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DoorPick = require(Shared.DoorPick)
local Sfx = require(Shared.Sfx)
local Worlds = require(Shared.Worlds)
local WorldHost = require(script.Parent.WorldHost)

local DoorRoomFlow = {}

export type Deps = {
	DataService: any?, -- rewards + stats (update(player, mutator))
	ChallengeService: any?, -- record(player, stat): rightDoor / trials / huntSurvived / world_<id> progress
	Monetization: any?, -- ownsRevive(player)
	Stalker: any?, -- the Stalker module; defaults to script.Parent.Stalker when present
	returnToLobby: (() -> ())?, -- end of Return; return normally to run the next round here
	expectedPartySize: (() -> number)?, -- how many players to wait for (default 1)
	arrivalGrace: number?, -- seconds to wait for the rest of the party (default Config)
}

export type Controller = {
	stop: () -> (),
	skip: () -> (),
	phase: () -> string,
}

local SHUT = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OPEN = TweenInfo.new(DoorPick.SWING_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local DOORS = { "Left", "Right" }

local function inZone(zone: BasePart, position: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function remote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function notify(player: Player, text: string, kind: string?)
	local r = remote("Notify")
	if r then
		r:FireClient(player, text, kind)
	end
end

-- Studio-only debug attribute (nil outside Studio).
local function debugAttr(name: string): any
	return if RunService:IsStudio() then workspace:GetAttribute(name) else nil
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
			TweenService:Create(part, open and OPEN or SHUT, { CFrame = about * rest }):Play()
		end
	end
	door:SetAttribute("Open", open)
	local void = door:FindFirstChild("Void")
	local blocker = void and void:FindFirstChild("Blocker") :: BasePart?
	if blocker then
		blocker.CanCollide = not open -- open: you can walk through into the black
	end
	if open then
		Sfx.at(leaf, "DoorSwing")
	end
end

-- Lights tagged "Flicker" (TrialKit.flicker): true blinks (the glowing core and its halo go dark with
-- it), "furnace" breathes. FlickerRate = chance per 0.12 s tick to blink. Worlds built later join in.
local function runFlicker(isRunning: () -> boolean)
	while isRunning() do
		for _, light in CollectionService:GetTagged("Flicker") do
			if not light:IsA("Light") or not light:IsDescendantOf(workspace) then
				continue
			end
			local base = light:GetAttribute("FlickerBase")
			if typeof(base) ~= "number" then
				base = light.Brightness
				light:SetAttribute("FlickerBase", base)
			end
			local kind = light:GetAttribute("Flicker")
			if kind == "furnace" then
				light.Brightness = base * (0.8 + math.random() * 0.35)
			elseif kind and math.random() < (light:GetAttribute("FlickerRate") or 0.03) then
				local core = light.Parent
				local glow = core and core:FindFirstChild("Halo")
				light.Brightness = 0
				if core and core:IsA("BasePart") then
					core.Transparency = 0.85
				end
				if glow and glow:IsA("BillboardGui") then
					glow.Enabled = false
				end
				task.delay(0.05 + math.random() * 0.3, function()
					light.Brightness = base
					if core and core:IsA("BasePart") then
						core.Transparency = 0.35
					end
					if glow and glow:IsA("BillboardGui") then
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
	local doorFolder = doorRoom:WaitForChild("Doors")
	local doors = {}
	for _, name in DOORS do
		local model = doorFolder:WaitForChild(name)
		doors[name] = {
			name = name,
			model = model,
			color = model:GetAttribute("Color") or name,
			zone = model:WaitForChild("Zone") :: BasePart,
			t0 = nil :: number?, -- server time the door started opening this round
		}
	end
	local spawnPoint = doorRoom:WaitForChild("Spawn") :: BasePart
	local doorSpawn = spawnPoint.CFrame * CFrame.new(0, 3, 0) -- a character's pivot sits ~3 studs up
	local holdCf = (doorRoom:WaitForChild("Hold") :: BasePart).CFrame
	local doorEvent = remote("DoorEvent")

	local running = true
	local phase = "Waiting"
	local skipRequested = false
	local connections: { RBXScriptConnection } = {}
	local respawnToken: { [Player]: number } = {}
	local rng = Random.new()
	local lastPair: { [string]: boolean } = {}

	-- this round's secret (locals only) and bookkeeping
	local round = {
		safeId = nil :: string?,
		dangerId = nil :: string?,
		safeDoor = "Left",
		pickEnded = false,
		pickEndAt = 0,
		dangerDoneAt = nil :: number?,
	}

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

	local StalkerModule = d.Stalker
	if not StalkerModule and script.Parent:FindFirstChild("Stalker") then
		StalkerModule = require(script.Parent.Stalker)
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

	local host -- WorldHost (forward declaration: followIn needs it, it needs followIn)

	-- FOLLOW THEM IN: a living lounge player follows the others into this round's dangerous world,
	-- once (there's no way back), while someone is still in there.
	local function followIn(player: Player)
		if not running or phase ~= "Round" and phase ~= "Pick" then
			return
		end
		if player:GetAttribute("Status") ~= "In" or player:GetAttribute("World") ~= round.safeId then
			return
		end
		if not rootOf(player) or not round.dangerId then
			return
		end
		if #host.playersIn(round.dangerId, true) == 0 then
			notify(player, "Nobody is left in there to follow.")
			return
		end
		host.enter(player, round.dangerId)
		notify(player, "You followed them in.")
	end

	host = WorldHost.new(trial, {
		DataService = d.DataService,
		ChallengeService = d.ChallengeService,
		Stalker = StalkerModule,
		placeAt = placeAt,
		hold = function()
			return holdCf
		end,
		followIn = followIn,
	})

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
		local function later(fn: () -> ())
			task.delay(flow.respawnDelay, function()
				if running and respawnToken[player] == token and player.Parent then
					fn()
				end
			end)
		end
		local status = player:GetAttribute("Status")
		local world = host.world(player:GetAttribute("World"))
		if status == "In" and world and world.kind == "danger" then
			if (player:GetAttribute("RevivesLeft") or 0) > 0 then
				-- the revive pass: one trip back to the world's Arrive
				player:SetAttribute("RevivesLeft", player:GetAttribute("RevivesLeft") - 1)
				later(function()
					if player:GetAttribute("Status") == "In" then
						spawnAt(player, doorSpawn, 1)
						host.respawnInside(player)
						notify(player, "Revived. Keep moving.")
					end
				end)
				return
			end
			host.out(player, "Dead")
			later(function()
				spawnAt(player, holdCf, 1)
				notify(player, "You didn't make it. Wait for the others.")
			end)
			return
		end
		if status == "In" and world then
			-- a lounge can't hurt you, but you can still fall: back to its Arrive
			later(function()
				spawnAt(player, doorSpawn, 1)
				host.respawnInside(player)
			end)
			return
		end
		if status == "Door" and phase == "Pick" then
			later(function()
				spawnAt(player, doorSpawn, 1) -- still time to pick
			end)
			return
		end
		if status == "Door" or status == "Committing" or status == "Glitch" then
			player:SetAttribute("Status", "Dead")
		end
		later(function()
			local at = if player:GetAttribute("Status") == "Door" then doorSpawn else holdCf
			spawnAt(player, at, 1)
		end)
	end

	local function onPlayer(player: Player)
		local late = phase ~= "Waiting" and phase ~= "Pick"
		player:SetAttribute("Status", if late then "Spectating" else "Door")
		player:SetAttribute("World", nil)
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
			task.spawn(spawnAt, player, if late then holdCf else doorSpawn, 1)
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

	local followRemote = remote("FollowIn")
	if followRemote then
		table.insert(connections, followRemote.OnServerEvent:Connect(followIn))
	end

	------------------------------------------------------------------------------------------
	-- The door sequence
	------------------------------------------------------------------------------------------
	local function openDoor(door, t0: number)
		door.t0 = t0
		local delay = math.max(0, t0 + DoorPick.LEAF_AT - workspace:GetServerTimeNow())
		task.delay(delay, function()
			if running and door.t0 == t0 then
				swingDoor(door.model, true)
			end
		end)
	end

	-- A player walked into a door's Zone during Pick: they're committed. Only they learn their world.
	local function commit(player: Player, doorName: string)
		local door = doors[doorName]
		local worldId = if doorName == round.safeDoor then round.safeId else round.dangerId
		local now = workspace:GetServerTimeNow()
		local mode, stepAt
		if door.t0 then
			mode = "breathe"
			stepAt = math.max(now + DoorPick.BREATHE_LEN, DoorPick.openDoneAt(door.t0))
		else
			mode = "open"
			openDoor(door, now)
			stepAt = now + DoorPick.OPEN_LEN
		end
		player:SetAttribute("Status", "Committing")
		player:SetAttribute("Picked", doorName)
		if doorEvent then
			doorEvent:FireClient(player, "commit", {
				door = doorName,
				color = door.color,
				mode = mode,
				world = worldId,
				t0 = now,
				stepAt = stepAt,
			})
		end
		local safe = doorName == round.safeDoor
		task.delay(DoorPick.enterAt(stepAt) - now, function()
			if running and player.Parent and player:GetAttribute("Status") == "Committing" then
				host.enter(player, worldId :: string)
				if safe and d.ChallengeService then
					d.ChallengeService.record(player, "rightDoor") -- (after the reveal, not before)
				end
			end
		end)
	end

	-- Pick ran out with this player at no door: the room glitches out around them, then they die.
	local function glitch(player: Player)
		player:SetAttribute("Status", "Glitch")
		if doorEvent then
			doorEvent:FireClient(player, "glitch", { t0 = workspace:GetServerTimeNow() })
		end
		task.delay(DoorPick.GLITCH_LEN, function()
			if not running or not player.Parent or player:GetAttribute("Status") ~= "Glitch" then
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0 -- onDied: Status Dead, respawn at the Hold
			else
				player:SetAttribute("Status", "Dead")
			end
		end)
	end

	local function drawPair()
		local safeId, dangerId = Worlds.drawPair(rng, lastPair)
		local forced = debugAttr("DebugPair")
		if typeof(forced) == "string" then
			local a, b = string.match(forced, "^%s*([%w_]+)%s*,%s*([%w_]+)")
			local sa, sb = Worlds.get(a), Worlds.get(b)
			if sa and sb and sa.play and sb.play then
				safeId, dangerId = a :: string, b :: string
			else
				warn("[DoorRoomFlow] DebugPair not understood: " .. forced)
			end
		end
		local side = debugAttr("DebugSide")
		round.safeId, round.dangerId = safeId, dangerId
		round.safeDoor = if side == "Left" or side == "Right"
			then side
			else (rng:NextNumber() < 0.5 and "Left" or "Right")
		lastPair = { [safeId] = true, [dangerId] = true }
	end

	local function busy(player: Player): boolean
		local status = player:GetAttribute("Status")
		return status == "Door" or status == "Committing" or status == "Glitch" or status == "In"
	end

	------------------------------------------------------------------------------------------
	-- One round
	------------------------------------------------------------------------------------------
	local function runRound()
		setPhase("Waiting")
		host.reset()
		for _, door in doors do
			door.t0 = nil
			swingDoor(door.model, false)
		end
		round.pickEnded = false
		round.dangerDoneAt = nil
		for _, player in Players:GetPlayers() do
			player:SetAttribute("Status", "Door")
			player:SetAttribute("Picked", nil)
			player:SetAttribute("World", nil)
			player:SetAttribute("Objective", nil)
			player:SetAttribute("LastWorld", nil)
			player:SetAttribute("Reward", nil)
		end
		while running and #Players:GetPlayers() == 0 do
			task.wait(0.5)
		end
		if not running then
			return
		end
		-- give the rest of the party a moment to arrive
		local expected = d.expectedPartySize and d.expectedPartySize() or 1
		local deadline = os.clock() + (d.arrivalGrace or flow.arrivalGrace)
		while running and #Players:GetPlayers() < expected and os.clock() < deadline and not skipRequested do
			task.wait(0.5)
		end
		skipRequested = false
		task.wait(2)
		if not running then
			return
		end
		for _, player in Players:GetPlayers() do
			local revives = (d.Monetization and d.Monetization.ownsRevive(player)) and 1 or 0
			player:SetAttribute("RevivesLeft", revives)
		end

		-- PICK. The pair and the safe door are locals: nothing about them reaches a client until its
		-- own player commits. Both worlds are built (stashed in ServerStorage) now so entering doesn't hitch.
		drawPair()
		for _, id in { round.safeId, round.dangerId } do
			local ok, err = pcall(host.prepare, id)
			if not ok then
				warn("[DoorRoomFlow] Couldn't build " .. tostring(id) .. ": " .. tostring(err))
			end
		end
		for i, player in Players:GetPlayers() do
			if player:GetAttribute("Status") == "Door" then
				placeAt(player, doorSpawn, i) -- facing the doors
			end
		end
		setPhase("Pick", flow.pickTime)
		local pickEnd = os.clock() + flow.pickTime
		while running and not skipRequested do
			local left = pickEnd - os.clock()
			if left <= 0 then
				break
			end
			workspace:SetAttribute("TimeLeft", math.ceil(left))
			local waiting = 0
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Status") ~= "Door" then
					continue
				end
				waiting += 1
				local root = rootOf(player)
				if root then
					for _, name in DOORS do
						if inZone(doors[name].zone, root.Position) then
							commit(player, name)
							break
						end
					end
				end
			end
			if waiting == 0 then
				break -- everyone has chosen
			end
			local forceOpen = debugAttr("DebugOpenDoor")
			if (forceOpen == "Left" or forceOpen == "Right") and not doors[forceOpen].t0 then
				workspace:SetAttribute("DebugOpenDoor", nil)
				openDoor(doors[forceOpen], workspace:GetServerTimeNow())
			end
			task.wait(0.1)
		end
		skipRequested = false
		workspace:SetAttribute("TimeLeft", 0)
		if not running then
			return
		end
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Status") == "Door" then
				glitch(player)
			end
		end
		round.pickEnded = true
		round.pickEndAt = os.clock()

		-- ROUND: no countdown; it's over when nobody is still picking, committing or inside
		setPhase("Round", 0)
		while running and not skipRequested do
			host.step()
			local now = os.clock()
			local anyBusy, dangerBusy = false, false
			for _, player in Players:GetPlayers() do
				if busy(player) then
					anyBusy = true
					local status = player:GetAttribute("Status")
					local world = player:GetAttribute("World")
					if status == "Committing" or status == "Glitch" or world == round.dangerId then
						dangerBusy = true -- (a commit might be to either world: wait it out)
					end
				end
			end
			if not anyBusy then
				break
			end
			-- lounges close a while after the dangerous side is done (and never before a minute)
			if not dangerBusy then
				round.dangerDoneAt = round.dangerDoneAt or now
				if
					now - round.dangerDoneAt >= Config.Worlds.loungeCloseAfter
					and host.roundTime(round.safeId) >= 60
				then
					host.close(round.safeId :: string)
				end
			end
			if now - round.pickEndAt >= Config.Worlds.hardCap then
				host.close(round.safeId :: string)
				host.close(round.dangerId :: string)
				for _, player in Players:GetPlayers() do
					if busy(player) then
						player:SetAttribute("Status", "Dead") -- stuck mid-sequence: let the round end
					end
				end
			end
			task.wait(0.25)
		end
		skipRequested = false
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
			player:SetAttribute("Status", "Door")
			player:SetAttribute("World", nil)
			task.spawn(spawnAt, player, doorSpawn, i)
		end
		task.wait(0.5)
	end

	task.spawn(runFlicker, function()
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
	-- DebugSkip (Studio): the same as ctl.skip()
	table.insert(
		connections,
		workspace:GetAttributeChangedSignal("DebugSkip"):Connect(function()
			if debugAttr("DebugSkip") == true then
				workspace:SetAttribute("DebugSkip", false)
				skipRequested = true
			end
		end)
	)

	return {
		stop = function()
			running = false
			skipRequested = true
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
			host.stop()
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
