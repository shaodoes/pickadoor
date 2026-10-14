--[[
	Stalker: server AI for the threat corridor's entity ("The Follower"), built by TrialBuilder.

	  local ai = Stalker.start(model, {
	      home = endPart.CFrame,                 -- where it idles between hunts
	      isTarget = function(player) ... end,   -- who it hunts (threat side, alive)
	      onHit = function(player, damage) end,  -- optional, after the damage is applied
	      pathfind = true,                       -- optional: route round walls (PathfindingService)
	  })
	  ai.setActive(true)   -- hunts only while active (the Round phase); otherwise it walks home
	  ai.reset()           -- back home, cooldowns forgotten (between rounds)
	  ai.stop()            -- disconnects everything

	Behaviour (a stub, but a working one): idles at `home`; when a target is within aggroRange it
	walks toward the nearest one (Humanoid:MoveTo, re-targeted every `retarget` seconds); stops
	entirely while the model's attribute Stunned == true (ItemService sets it: the laser pointer);
	touching a target (UpperTorso.Touched, or closer than hitRange) deals `damage` with a per-player
	cooldown and a positional hit sound. Tuning defaults come from Config.Stalker.
	With opts.pathfind it walks straight at a target it can see, and otherwise follows a
	PathfindingService route (recomputed at most once a second, or when the target moves 6 studs), so it
	can hunt through room grids and round corners; walking home uses the same routing.
]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Sfx = require(Shared.Sfx)

local Stalker = {}

export type Opts = {
	home: CFrame,
	isTarget: (Player) -> boolean,
	onHit: ((Player, number) -> ())?,
	walkSpeed: number?,
	aggroRange: number?,
	damage: number?,
	hitCooldown: number?,
	hitRange: number?,
	retarget: number?,
	pathfind: boolean?,
}

export type Controller = {
	setActive: (boolean) -> (),
	reset: () -> (),
	setSpeed: (number) -> (),
	stop: () -> (),
	isHunting: () -> boolean,
}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Stalker.start(model: Model, opts: Opts): Controller
	local tuning = Config.Stalker or {}
	local walkSpeed = opts.walkSpeed or tuning.walkSpeed or 11
	local aggroRange = opts.aggroRange or tuning.aggroRange or 60
	local damage = opts.damage or tuning.damage or 34
	local hitCooldown = opts.hitCooldown or tuning.hitCooldown or 1.5
	local hitRange = opts.hitRange or tuning.hitRange or 3
	local retarget = opts.retarget or tuning.retarget or 0.5

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart
	local torso = (model:FindFirstChild("UpperTorso") or root) :: BasePart
	assert(humanoid and root, "Stalker.start: model needs a Humanoid and a HumanoidRootPart")
	humanoid.WalkSpeed = walkSpeed
	pcall(root.SetNetworkOwner, root, nil) -- the server drives it (errors outside a running server)

	local eyes = {}
	for _, name in { "EyeL", "EyeR" } do
		local eye = model:FindFirstChild(name)
		local light = eye and eye:FindFirstChildOfClass("PointLight")
		if light then
			table.insert(eyes, light)
		end
	end

	local running = true
	local active = false
	local hunting = false
	local lastHit: { [Player]: number } = {}
	local connections: { RBXScriptConnection } = {}

	local function stunned(): boolean
		return model:GetAttribute("Stunned") == true
	end

	local function setHunting(on: boolean)
		if hunting == on then
			return
		end
		hunting = on
		for _, light in eyes do
			light.Brightness = on and 1.4 or 0.5
			light.Range = on and 10 or 7
		end
	end

	local function hold()
		humanoid:MoveTo(root.Position)
	end

	-- Line of sight from the head to a point (the model and the target's character are ignored).
	local sightParams = RaycastParams.new()
	sightParams.FilterType = Enum.RaycastFilterType.Exclude
	local function canSee(position: Vector3, ignore: Instance?): boolean
		sightParams.FilterDescendantsInstances = if ignore then { model, ignore } else { model }
		local from = root.Position + Vector3.new(0, 2, 0)
		return workspace:Raycast(from, position - from, sightParams) == nil
	end

	-- PathfindingService routing (opts.pathfind): a cached route to `goal`, re-planned when stale.
	local route: { PathWaypoint }? = nil
	local routeIndex = 1
	local routeGoal: Vector3? = nil
	local routeAt = 0
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 9, AgentCanJump = false })
	local function walkTo(goal: Vector3, ignore: Instance?)
		if not opts.pathfind or canSee(goal, ignore) then
			route = nil
			humanoid:MoveTo(goal)
			return
		end
		local now = os.clock()
		if not route or now - routeAt > 1 or not routeGoal or (routeGoal - goal).Magnitude > 6 then
			routeAt, routeGoal = now, goal
			local ok = pcall(path.ComputeAsync, path, root.Position, goal)
			if ok and path.Status == Enum.PathStatus.Success then
				route = path:GetWaypoints()
				routeIndex = math.min(2, #route)
			else
				route = nil
			end
		end
		if not route then
			humanoid:MoveTo(goal) -- no route: try the straight line
			return
		end
		while
			routeIndex < #route
			and ((route[routeIndex].Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 3
		do
			routeIndex += 1
		end
		humanoid:MoveTo(route[routeIndex].Position)
	end

	-- Hurt a player if their cooldown has passed. Server-authoritative: nothing the client sends matters.
	local function hit(player: Player)
		if not active or stunned() or not opts.isTarget(player) then
			return
		end
		local now = os.clock()
		if (lastHit[player] or 0) + hitCooldown > now then
			return
		end
		local character = player.Character
		local target = character and character:FindFirstChildOfClass("Humanoid")
		if not target or target.Health <= 0 then
			return
		end
		lastHit[player] = now
		target:TakeDamage(damage)
		Sfx.at(torso, "StalkerHit")
		if opts.onHit then
			task.spawn(opts.onHit, player, damage)
		end
	end

	table.insert(
		connections,
		torso.Touched:Connect(function(part)
			local character = part:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				hit(player)
			end
		end)
	)
	table.insert(
		connections,
		model:GetAttributeChangedSignal("Stunned"):Connect(function()
			if stunned() then
				humanoid.WalkSpeed = 0
				hold()
			else
				humanoid.WalkSpeed = walkSpeed
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			lastHit[player] = nil
		end)
	)

	local function nearestTarget(): (BasePart?, number)
		local best, bestDist = nil, math.huge
		for _, player in Players:GetPlayers() do
			if opts.isTarget(player) then
				local targetRoot = rootOf(player)
				if targetRoot then
					local d = (targetRoot.Position - root.Position).Magnitude
					if d < bestDist then
						best, bestDist = targetRoot, d
					end
				end
			end
		end
		return best, bestDist
	end

	-- Brain: re-target every `retarget` seconds. MoveTo times out after 8 s on its own, so it is
	-- re-issued each tick rather than waited on.
	task.spawn(function()
		while running do
			if active and not stunned() then
				local target, dist = nearestTarget()
				if target and dist <= aggroRange then
					setHunting(true)
					walkTo(target.Position, target.Parent)
				else
					setHunting(false)
					if (root.Position - opts.home.Position).Magnitude > 4 then
						walkTo(opts.home.Position)
					else
						hold()
					end
				end
			else
				setHunting(false)
			end
			task.wait(retarget)
		end
	end)

	-- Reach: a close pass counts as a touch too (Touched misses a lot at walking speeds).
	task.spawn(function()
		while running do
			if active and hunting and not stunned() then
				for _, player in Players:GetPlayers() do
					local targetRoot = rootOf(player)
					if targetRoot and (targetRoot.Position - root.Position).Magnitude <= hitRange then
						hit(player)
					end
				end
			end
			task.wait(0.1)
		end
	end)

	local controller: Controller = {
		setActive = function(on: boolean)
			active = on
			if on then
				pcall(root.SetNetworkOwner, root, nil) -- (fails while the world is stashed out of workspace)
			end
			if not on then
				setHunting(false)
				hold()
			end
		end,
		reset = function()
			table.clear(lastHit)
			setHunting(false)
			humanoid.Health = humanoid.MaxHealth
			model:PivotTo(opts.home)
			route = nil
			hold()
		end,
		setSpeed = function(speed: number)
			walkSpeed = speed
			if not stunned() then
				humanoid.WalkSpeed = speed
			end
		end,
		stop = function()
			running = false
			active = false
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
		end,
		isHunting = function()
			return hunting
		end,
	}
	return controller
end

return Stalker
