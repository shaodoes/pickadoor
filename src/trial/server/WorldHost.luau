--[[
	WorldHost: builds, shows, runs and resets the worlds behind the doors (catalogue: Shared.Worlds).

	All worlds live in the one trial place. Each is built lazily, once, by its builder
	(ServerStorage.Builders.Worlds.<Module>) at its own slot (Config.Worlds.slotOrigin + (slot - 1) *
	slotSpacing on X), kept in ServerStorage while it isn't being played (so nothing about a pair
	replicates early) and moved into Trial.Worlds when its first player enters. Its server module
	(script.Parent.Worlds.<Module>) is started once with a ctx and returns a controller:

	  start(ctx) -> {
	      reset: () -> (),               -- back to the start (between rounds; the model is stashed after)
	      roundStart: () -> (),          -- the world's first player just entered: go
	      escalate: (level: number) -> (), -- Config.Worlds.escalateAt s in (danger): more / faster entities
	      steps: { Objectives.Step }?,   -- danger: the objective chain before the exit opens
	      onEnter: ((Player) -> ())?,    -- someone entered (also late arrivals, followers, revives)
	      onClientEvent: ((Player, kind: string, ...any) -> ())?, -- WorldEvent from this world's client module
	      stop: () -> (),
	  }

	ctx (what a server world module gets):
	  id, def (catalogue entry), kind ("safe" | "danger"), model, origin, rng (Random)
	  inside(player) -> boolean            -- Status "In" and World == id
	  players() -> { Player }              -- living players inside
	  escape(player)                       -- pays (Hunt / Blessing or def.play.reward) and sends them out
	  damage(player, amount), kill(player)
	  notify(player?, text, kind?)         -- toast (nil player = everyone inside)
	  caption(player?, text, seconds?)     -- subtitle line (every sound cue should have one)
	  fire(player?, kind, ...)             -- WorldEvent to this world's client module (nil = everyone inside)
	  advanceStep(by?), step() -> number   -- the objective chain (custom steps finish themselves this way)
	  collect(player) -> boolean           -- the world's collectible (def.play.collectible); false if found before
	  pay(player, keys, line?)             -- immediate Keys (pickups)
	  escalated() -> boolean, roundTime() -> number
	  part(name) -> Instance?              -- model:FindFirstChild(name, true)
	  Stalker, Objectives, Config          -- modules, for convenience

	Players: attributes World (id while inside), Status ("Door" | "Committing" | "In" | "Escaped" |
	"Dead" | "Spectating"; DoorRoomFlow owns the rest), Objective (the current step's text), and an
	ObjectValue child GuideTarget (set once the world has escalated: the blue path's goal).
	World model attributes: Escalated, ObjIndex / ObjCount / ObjText / ObjDone (Objectives).
	Rewards: escaping pays at once; Stats.world_<id> on entering, Stats.worldEscaped_<id> on escaping
	(ChallengeService), WorldsSeen / Collectibles in the save.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Worlds = require(Shared.Worlds)
local Objectives = require(script.Parent.Objectives)

local WorldHost = {}

export type Deps = {
	DataService: any?,
	ChallengeService: any?,
	Stalker: any?,
	placeAt: (Player, CFrame, number) -> (), -- DoorRoomFlow's clustered placement
	hold: () -> CFrame, -- where finished / dead players wait (DoorRoom.Hold)
	followIn: ((Player) -> ())?, -- a lounge's FOLLOW THEM IN door was used
	changed: (() -> ())?, -- someone's Status changed (the round may be over)
}

local function remote(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- Studio-only override of the escalation time (workspace attribute DebugEscalateAt, seconds).
local function escalateAt(): number
	local debugAt = RunService:IsStudio() and workspace:GetAttribute("DebugEscalateAt")
	return if typeof(debugAt) == "number" then debugAt else Config.Worlds.escalateAt
end

function WorldHost.new(trial: Model, deps: Deps)
	local folder = trial:FindFirstChild("Worlds")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Worlds"
		folder.Parent = trial
	end
	local stash = ServerStorage:FindFirstChild("WorldStash") or Instance.new("Folder")
	stash.Name = "WorldStash"
	stash.Parent = ServerStorage
	local builders = ServerStorage:WaitForChild("Builders")
	local TrialKit = require(builders:WaitForChild("TrialKit"))
	local serverModules = script.Parent:WaitForChild("Worlds")
	local notifyRemote = remote("Notify")
	local worldRemote = remote("WorldEvent")

	local host = {}
	local built: { [string]: any } = {}
	local entered: { [string]: number } = {} -- per world: arrivals this round (placement slots)
	local connections: { RBXScriptConnection } = {}

	local function notify(player: Player, text: string, kind: string?)
		if notifyRemote and player.Parent then
			notifyRemote:FireClient(player, text, kind)
		end
	end

	local function guideValue(player: Player): ObjectValue
		local value = player:FindFirstChild("GuideTarget") :: ObjectValue?
		if not value then
			value = Instance.new("ObjectValue")
			value.Name = "GuideTarget"
			value.Parent = player
		end
		return value :: ObjectValue
	end

	local function inside(player: Player, id: string): boolean
		return player:GetAttribute("World") == id and player:GetAttribute("Status") == "In"
	end

	local function playersIn(id: string, aliveOnly: boolean?): { Player }
		local out = {}
		for _, player in Players:GetPlayers() do
			if inside(player, id) and (not aliveOnly or humanoidOf(player)) then
				table.insert(out, player)
			end
		end
		return out
	end
	host.playersIn = playersIn

	local function setStatus(player: Player, status: string)
		player:SetAttribute("Status", status)
		if deps.changed then
			task.defer(deps.changed)
		end
	end

	local function exitPart(w): BasePart?
		local exit = w.model:FindFirstChild("Exit")
		local slab = exit and exit:FindFirstChild("Slab")
		return if slab and slab:IsA("BasePart") then slab else nil
	end

	local function objectiveText(w): string?
		if w.kind ~= "danger" or not w.chain then
			return nil
		end
		return if w.chain.complete() then "GET TO THE EXIT" else w.chain.text()
	end

	local function publishObjective(w)
		local text = objectiveText(w)
		for _, player in playersIn(w.id) do
			player:SetAttribute("Objective", text)
		end
	end

	------------------------------------------------------------------------------------------
	-- Building
	------------------------------------------------------------------------------------------
	local function build(id: string)
		local def = Worlds.get(id)
		assert(def and def.play, "WorldHost: no playable world " .. tostring(id))
		local module = def.play.module
		local builder = builders:WaitForChild("Worlds"):FindFirstChild(module)
		local server = serverModules:FindFirstChild(module)
		assert(builder and server, "WorldHost: missing Worlds/" .. module .. " (builder or server module)")
		local origin = Config.Worlds.slotOrigin + Vector3.new((def.slot - 1) * Config.Worlds.slotSpacing, 0, 0)
		local model = require(builder).build(stash, origin, TrialKit.at(origin))
		model.Name = id
		model:SetAttribute("WorldId", id)
		model:SetAttribute("Kind", def.kind)
		model.Parent = stash

		local w = {
			id = id,
			def = def,
			kind = def.kind,
			model = model,
			origin = origin,
			ctl = nil :: any,
			chain = nil :: any,
			active = false,
			roundStart = 0,
			escalated = false,
			nudged = false,
		}
		local ctx = {
			id = id,
			def = def,
			kind = def.kind,
			model = model,
			origin = origin,
			rng = Random.new(),
			Stalker = deps.Stalker,
			Objectives = Objectives,
			Config = Config,
		}
		function ctx.inside(player: Player): boolean
			return inside(player, id)
		end
		function ctx.players(): { Player }
			return playersIn(id, true)
		end
		function ctx.escape(player: Player)
			host.escape(player)
		end
		function ctx.damage(player: Player, amount: number)
			local humanoid = humanoidOf(player)
			if humanoid then
				humanoid:TakeDamage(amount)
			end
		end
		function ctx.kill(player: Player)
			local humanoid = humanoidOf(player)
			if humanoid then
				humanoid.Health = 0
			end
		end
		function ctx.notify(player: Player?, text: string, kind: string?)
			for _, p in if player then { player } else playersIn(id) do
				notify(p, text, kind)
			end
		end
		function ctx.fire(player: Player?, kind: string, ...)
			if not worldRemote then
				return
			end
			for _, p in if player then { player } else playersIn(id) do
				worldRemote:FireClient(p, id, kind, ...)
			end
		end
		function ctx.caption(player: Player?, text: string, seconds: number?)
			ctx.fire(player, "caption", text, seconds or 3)
		end
		function ctx.advanceStep(by: Player?)
			if w.chain then
				w.chain.advance(by)
			end
		end
		function ctx.step(): number
			return if w.chain then w.chain.index() else 1
		end
		function ctx.pay(player: Player, keys: number, line: string?)
			if deps.DataService then
				deps.DataService.update(player, function(data)
					data.Keys += keys
				end)
			end
			if line then
				notify(player, line)
			end
		end
		function ctx.collect(player: Player): boolean
			local item = def.play and def.play.collectible
			if not item then
				return false
			end
			local data = deps.DataService and deps.DataService.get(player)
			if data and data.Collectibles[item.id] then
				notify(player, string.format("You already have the %s.", item.name))
				return false
			end
			if deps.DataService then
				deps.DataService.update(player, function(d)
					d.Collectibles[item.id] = true
					d.Keys += Config.Rewards.Collectible
				end)
			end
			notify(
				player,
				string.format("Found: %s. +%d %s", item.name, Config.Rewards.Collectible, Config.CurrencyName),
				"success"
			)
			return true
		end
		function ctx.escalated(): boolean
			return w.escalated
		end
		function ctx.roundTime(): number
			return if w.active then os.clock() - w.roundStart else 0
		end
		function ctx.part(name: string): Instance?
			return model:FindFirstChild(name, true)
		end
		w.ctx = ctx

		w.ctl = require(server).start(ctx)
		if w.kind == "danger" then
			w.chain = Objectives.new(model, w.ctl.steps or {}, {
				inside = ctx.inside,
				notify = notify,
				onAdvance = function(_, step, by)
					local text = if w.chain.complete() then "The way out is open." else "Done: " .. step.text:lower()
					for _, p in playersIn(id) do
						notify(p, if by and by ~= p then by.DisplayName .. ": " .. text else text, "success")
					end
					ctx.fire(nil, "objective", w.chain.index())
					local slab = exitPart(w)
					local prompt = slab and slab:FindFirstChildOfClass("ProximityPrompt")
					if prompt then
						prompt.Enabled = w.chain.complete()
					end
					publishObjective(w)
				end,
			})
		end

		-- the exit: any time in a lounge; after the last objective in a dangerous world
		local slab = exitPart(w)
		local exitPrompt = slab and slab:FindFirstChildOfClass("ProximityPrompt")
		if exitPrompt then
			exitPrompt.Enabled = w.kind ~= "danger"
			table.insert(
				connections,
				exitPrompt.Triggered:Connect(function(player)
					if not inside(player, id) or not humanoidOf(player) then
						return
					end
					if w.chain and not w.chain.complete() then
						notify(player, "It won't open. Not yet.")
						return
					end
					host.escape(player)
				end)
			)
		end
		-- FOLLOW THEM IN (lounges)
		local follow = model:FindFirstChild("FollowDoor")
		local followSlab = follow and follow:FindFirstChild("Slab")
		local followPrompt = followSlab and followSlab:FindFirstChildOfClass("ProximityPrompt")
		if followPrompt then
			table.insert(
				connections,
				followPrompt.Triggered:Connect(function(player)
					if inside(player, id) and deps.followIn then
						deps.followIn(player)
					end
				end)
			)
		end
		built[id] = w
		return w
	end

	-- Build (if needed) and keep it stashed: called for the drawn pair as Pick starts, so entering
	-- doesn't hitch. Nothing replicates while the model sits in ServerStorage.
	function host.prepare(id: string)
		return built[id] or build(id)
	end

	function host.world(id: string?)
		return if id then built[id] else nil
	end

	------------------------------------------------------------------------------------------
	-- Rounds
	------------------------------------------------------------------------------------------
	local function begin(w)
		w.model.Parent = folder
		w.active = true
		w.roundStart = os.clock()
		w.escalated = false
		w.nudged = false
		w.model:SetAttribute("Escalated", false)
		if w.chain then
			w.chain.reset()
			local slab = exitPart(w)
			local prompt = slab and slab:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = false
			end
		end
		w.ctl.roundStart()
	end

	-- Put a player into a world (their door sequence finished, or they followed / were revived).
	function host.enter(player: Player, id: string)
		local w = host.prepare(id)
		if not w.active then
			begin(w)
		end
		entered[id] = (entered[id] or 0) + 1
		local arrive = w.model:FindFirstChild("Arrive") :: BasePart
		deps.placeAt(player, arrive.CFrame, entered[id])
		player:SetAttribute("World", id)
		setStatus(player, "In")
		player:SetAttribute("Objective", objectiveText(w))
		guideValue(player).Value = nil
		if deps.DataService then
			deps.DataService.update(player, function(data)
				data.WorldsSeen[id] = true
			end)
		end
		if deps.ChallengeService then
			deps.ChallengeService.record(player, "world_" .. id)
		end
		if w.ctl.onEnter then
			task.spawn(w.ctl.onEnter, player)
		end
	end

	-- Back into the world they're in after a revive (no new arrival bookkeeping).
	function host.respawnInside(player: Player)
		local w = built[player:GetAttribute("World")]
		if not w then
			return
		end
		local arrive = w.model:FindFirstChild("Arrive") :: BasePart
		deps.placeAt(player, arrive.CFrame, 1)
		if w.ctl.onEnter then
			task.spawn(w.ctl.onEnter, player)
		end
	end

	-- Out through the exit (or a lounge closing): pay at once, then wait in the door room.
	function host.escape(player: Player)
		local id = player:GetAttribute("World")
		local w = built[id]
		if not w or player:GetAttribute("Status") ~= "In" then
			return
		end
		local danger = w.kind == "danger"
		local reward = (w.def.play and w.def.play.reward)
			or (if danger then Config.Rewards.Hunt else Config.Rewards.Blessing)
		if deps.DataService then
			deps.DataService.update(player, function(data)
				data.Keys += reward
				data.TrialsPlayed += 1
				data.TrialsSurvived += 1
			end)
		end
		if deps.ChallengeService then
			deps.ChallengeService.record(player, "trials")
			if danger then
				deps.ChallengeService.record(player, "huntSurvived")
				deps.ChallengeService.record(player, "worldEscaped_" .. id)
			end
		end
		player:SetAttribute("LastWorld", id)
		player:SetAttribute("Reward", reward)
		player:SetAttribute("World", nil)
		player:SetAttribute("Objective", nil)
		guideValue(player).Value = nil
		setStatus(player, "Escaped")
		deps.placeAt(player, deps.hold(), 1)
		notify(
			player,
			string.format(
				"%s: +%d %s",
				if danger then "You got out" else "You left " .. w.def.name,
				reward,
				Config.CurrencyName
			),
			"success"
		)
	end

	-- Out without a reward: died (no revive left) or still inside when the round was cut off.
	function host.out(player: Player, status: string)
		local id = player:GetAttribute("World")
		if id and deps.DataService then
			deps.DataService.update(player, function(data)
				data.TrialsPlayed += 1
			end)
		end
		if id and deps.ChallengeService then
			deps.ChallengeService.record(player, "trials")
		end
		player:SetAttribute("LastWorld", id)
		player:SetAttribute("Reward", 0)
		player:SetAttribute("World", nil)
		player:SetAttribute("Objective", nil)
		guideValue(player).Value = nil
		setStatus(player, status)
	end

	-- Everyone still inside `id` leaves: a lounge closing pays them out, a dangerous world cut off
	-- (the hidden safety cap) doesn't.
	function host.close(id: string)
		local w = built[id]
		if not w then
			return
		end
		for _, player in playersIn(id) do
			if w.kind == "safe" and humanoidOf(player) then
				notify(player, "The lounge closes behind you.")
				host.escape(player)
			else
				host.out(player, "Dead")
				deps.placeAt(player, deps.hold(), 1)
				notify(player, "The door closed with you inside. No keys this time.")
			end
		end
	end

	function host.isActive(id: string?): boolean
		local w = id and built[id]
		return w ~= nil and w.active
	end

	function host.roundTime(id: string?): number
		local w = id and built[id]
		return if w and w.active then os.clock() - w.roundStart else 0
	end

	-- Called a few times a second by DoorRoomFlow during the round: escalation, guide targets, nudges.
	function host.step()
		for id, w in built do
			if not w.active then
				continue
			end
			local t = os.clock() - w.roundStart
			if w.kind == "danger" then
				if not w.escalated and t >= escalateAt() then
					w.escalated = true
					w.model:SetAttribute("Escalated", true)
					task.spawn(w.ctl.escalate, 1)
					w.ctx.fire(nil, "escalate", 1)
					for _, player in playersIn(id) do
						notify(player, Config.Worlds.guide.toast)
					end
				end
				if w.escalated then
					local exit = exitPart(w)
					for _, player in playersIn(id) do
						local target = if w.chain.complete() then exit else w.chain.targetFor(player)
						local value = guideValue(player)
						if value.Value ~= target then
							value.Value = target
						end
					end
				end
			elseif not w.nudged and t >= Config.Worlds.loungeNudgeAt then
				w.nudged = true
				for _, player in playersIn(id) do
					notify(player, "The lounge is closing soon. Leave by the exit when you're ready.")
				end
			end
		end
	end

	-- Between rounds: every world back to the start and out of workspace.
	function host.reset()
		table.clear(entered)
		for _, w in built do
			if w.active then
				w.active = false
				local ok, err = pcall(w.ctl.reset)
				if not ok then
					warn("[WorldHost] " .. w.id .. " reset failed: " .. tostring(err))
				end
				if w.chain then
					w.chain.reset()
				end
			end
			w.escalated = false
			w.model:SetAttribute("Escalated", false)
			w.model.Parent = stash
		end
		for _, player in Players:GetPlayers() do
			guideValue(player).Value = nil
		end
	end

	-- WorldEvent from a world's client module: only from players inside that world
	if worldRemote then
		table.insert(
			connections,
			worldRemote.OnServerEvent:Connect(function(player, id, kind, ...)
				local w = typeof(id) == "string" and built[id]
				if w and typeof(kind) == "string" and inside(player, id) and w.ctl.onClientEvent then
					w.ctl.onClientEvent(player, kind, ...)
				end
			end)
		)
	end

	function host.stop()
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
		for _, w in built do
			pcall(w.ctl.stop)
			if w.chain then
				w.chain.stop()
			end
		end
	end

	return host
end

return WorldHost
