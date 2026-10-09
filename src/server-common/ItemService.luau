--[[
	Server-authoritative items, used by BOTH places: ItemService.start({ recharge = true | false }).

	  buy / use        BuyItem / UseItem RemoteFunctions -> { ok, message, cooldown? }
	  speed pills      +WalkSpeed on the humanoid for a while (attribute SpeedPillsUntil)
	  bandage          heals over a few seconds (attribute Bandaging)
	  lockpicks        a hold-to-pick ProximityPrompt on every model tagged `Lockable` (attributes LockId,
	                   Reward; optional parts Lid / Lock with a `Hinge` CFrame attribute in the part's own
	                   space, swung open by `OpenAngle` degrees; optional PointLight "GlintLight" lit while open)
	  laser pointer    UseItem toggles the Tool (the lantern goes away while it is out). LaserFire turns the
	                   replicated Beam on; LaserAim streams the aim point, which the server clamps to a cone
	                   around the lens and the character's facing before raycasting. Entities under the beam for
	                   LaserStunHold seconds are Stunned (unless Unstunnable). The battery drains while firing
	                   and recharges while idle when `recharge` is on (the lobby only).

	Attributes written: Entity models `Lasered`, `Stunned`, `StunnedUntil` (server time); Lockable models
	`Locked`; players `LaserBattery` (replicated for the hotbar); the laser Tool `Firing`.
	ItemEvent (server -> client) kinds: "speed"/"heal" (character, duration), "unlock" (model, player),
	"stun" (entity, player), "laserHit" (position, entity) - clients turn these into VFX/SFX.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local LaserBuilder = require(Shared.LaserBuilder)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local LanternService = require(script.Parent.LanternService)

local ItemService = {}

local T = Config.Items
local BATTERY_MAX = T.LaserBatteryMax
local COS_CONE = math.cos(math.rad(T.LaserAimCone))

local stunnedEvent = Instance.new("BindableEvent")
ItemService.Stunned = stunnedEvent.Event -- (entity: Model, byPlayer: Player)

type LaserState = {
	tool: Tool,
	character: Model,
	lens: Attachment,
	beam: Beam,
	light: PointLight,
	endAtt: Attachment,
	params: RaycastParams,
	firing: boolean,
	equipping: boolean,
	aim: Vector3?,
	hitEntity: Model?,
	hitSince: number,
	deadNotified: number,
}
type Swing = { part: BasePart, hinge: CFrame, closed: CFrame, angle: number }
type Lock = { model: Model, prompt: ProximityPrompt, swings: { Swing }, light: PointLight? }

local cooldowns: { [Player]: { [string]: number } } = {} -- os.clock() when the item is ready again
local lasers: { [Player]: LaserState } = {}
local laseredBy: { [Model]: { [Player]: boolean } } = {} -- which beams are on an entity right now
local locks: { [Model]: Lock } = {}
local recharge = true

-- unlock-kind items and the profile flag that records them
local UNLOCK_FIELD = { laser_pointer = "LaserUnlocked" }

local function result(ok: boolean, message: string, extra: { [string]: any }?)
	local r: { [string]: any } = extra or {}
	r.ok = ok
	r.message = message
	return r
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

-- `player` nil broadcasts to everyone (effects other people should see / hear).
local function itemEvent(player: Player?, kind: string, ...)
	local remote = Remotes.get("ItemEvent")
	if player then
		remote:FireClient(player, kind, ...)
	else
		remote:FireAllClients(kind, ...)
	end
end

local function aliveHumanoid(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		return character, humanoid
	end
	return nil, nil
end

local function cooldownLeft(player: Player, id: string): number
	local mine = cooldowns[player]
	local ready = mine and mine[id]
	return ready and math.max(ready - os.clock(), 0) or 0
end

local function setCooldown(player: Player, id: string, seconds: number)
	if seconds <= 0 then
		return
	end
	local mine = cooldowns[player]
	if not mine then
		mine = {}
		cooldowns[player] = mine
	end
	mine[id] = os.clock() + seconds
end

------------------------------------------------------------------------------------------
-- Battery
------------------------------------------------------------------------------------------
-- The live profile table is written directly (it is saved with the rest of the profile); the
-- replicated player attribute drives the hotbar without a full snapshot per tick.
local function setBattery(player: Player, value: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	value = math.clamp(value, 0, BATTERY_MAX)
	data.LaserBattery = value
	local shown = math.floor(value + 0.5)
	if player:GetAttribute("LaserBattery") ~= shown then
		player:SetAttribute("LaserBattery", shown)
	end
end

------------------------------------------------------------------------------------------
-- Shop
------------------------------------------------------------------------------------------
function ItemService.buy(player: Player, id: any)
	if typeof(id) ~= "string" then
		return result(false, "Invalid item.")
	end
	local def = Items.get(id)
	local data = DataService.get(player)
	if not def or not data then
		return result(false, "Invalid item.")
	end
	local field = UNLOCK_FIELD[id]
	if def.kind == "unlock" then
		if not field then
			return result(false, "Invalid item.")
		end
		if data[field] then
			return result(false, "You already own the " .. def.name .. ".")
		end
	end
	local count = data.Inventory[id] or 0
	if def.kind == "consumable" and count >= def.cap then
		return result(false, string.format("You can only carry %d %s.", def.cap, def.name))
	end
	if data.Keys < def.price then
		return result(
			false,
			string.format("Not enough %s (%d more needed).", Config.CurrencyName, def.price - data.Keys)
		)
	end
	DataService.update(player, function(d)
		d.Keys -= def.price
		if def.kind == "unlock" then
			d[field] = true
		else
			d.Inventory[id] = count + 1
		end
	end)
	if def.kind == "unlock" then
		return result(true, string.format("Bought the %s. Press 4 to take it out.", def.name))
	end
	return result(true, string.format("Bought %s (%d/%d).", def.name, count + 1, def.cap))
end

------------------------------------------------------------------------------------------
-- Consumable effects
------------------------------------------------------------------------------------------
local function applySpeed(character: Model, humanoid: Humanoid, def)
	local eff = def.effect
	local now = os.clock()
	local activeUntil = humanoid:GetAttribute("SpeedPillsUntil")
	if typeof(activeUntil) == "number" and activeUntil > now then
		return false, "The pills are still working."
	end
	local expiry = now + eff.duration
	humanoid.WalkSpeed += eff.speed
	humanoid:SetAttribute("SpeedPillsUntil", expiry)
	task.delay(eff.duration, function()
		-- only undo our own boost (a second dose can't start while this one runs, so expiry identifies it)
		if humanoid.Parent and humanoid:GetAttribute("SpeedPillsUntil") == expiry then
			humanoid:SetAttribute("SpeedPillsUntil", nil)
			humanoid.WalkSpeed = math.max(humanoid.WalkSpeed - eff.speed, 0)
		end
	end)
	itemEvent(nil, "speed", character, eff.duration)
	return true, string.format("Speed pills: +%d speed for %ds.", eff.speed, eff.duration)
end

local function applyHeal(character: Model, humanoid: Humanoid, def)
	local eff = def.effect
	if humanoid.Health >= humanoid.MaxHealth then
		return false, "You're not hurt."
	end
	if humanoid:GetAttribute("Bandaging") then
		return false, "You're already bandaging."
	end
	humanoid:SetAttribute("Bandaging", true)
	task.spawn(function()
		local step = 0.25
		local ticks = math.max(math.floor(eff.duration / step), 1)
		local per = eff.heal / ticks
		for _ = 1, ticks do
			task.wait(step)
			if not humanoid.Parent or humanoid.Health <= 0 then
				break
			end
			humanoid.Health = math.min(humanoid.Health + per, humanoid.MaxHealth)
		end
		if humanoid.Parent then
			humanoid:SetAttribute("Bandaging", nil)
		end
	end)
	itemEvent(nil, "heal", character, eff.duration)
	return true, string.format("Bandaged: +%d health over %ds.", eff.heal, eff.duration)
end

------------------------------------------------------------------------------------------
-- Laser pointer: tool handling
------------------------------------------------------------------------------------------
local function entityOf(instance: Instance?): Model?
	local node = instance
	while node and node ~= workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "Entity") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function markLasered(entity: Model, player: Player, on: boolean)
	local set = laseredBy[entity]
	if not set then
		if not on then
			return
		end
		set = {}
		laseredBy[entity] = set
	end
	set[player] = if on then true else nil
	local any = next(set) ~= nil
	if not any then
		laseredBy[entity] = nil
	end
	if entity.Parent then
		entity:SetAttribute("Lasered", any)
	end
end

local function clearHit(state: LaserState, player: Player)
	if state.hitEntity then
		markLasered(state.hitEntity, player, false)
		state.hitEntity = nil
	end
end

local function stun(entity: Model, player: Player)
	local untilTime = workspace:GetServerTimeNow() + T.LaserStunDuration
	entity:SetAttribute("Stunned", true)
	entity:SetAttribute("StunnedUntil", untilTime)
	stunnedEvent:Fire(entity, player)
	itemEvent(nil, "stun", entity, player)
	task.delay(T.LaserStunDuration, function()
		if entity.Parent and entity:GetAttribute("StunnedUntil") == untilTime then
			entity:SetAttribute("Stunned", false)
		end
	end)
end

local function setFiring(player: Player, firing: boolean)
	local state = lasers[player]
	if not state or state.firing == firing then
		return
	end
	if firing then
		local data = DataService.get(player)
		if not data or data.LaserBattery < 1 then
			if os.clock() - state.deadNotified > 2 then
				state.deadNotified = os.clock()
				notify(player, "The laser's battery is dead. It recharges in the library.")
			end
			return
		end
		state.hitEntity = nil
		state.hitSince = os.clock()
	else
		clearHit(state, player)
	end
	state.firing = firing
	state.tool:SetAttribute("Firing", firing)
	state.beam.Enabled = firing
	state.light.Enabled = firing
	if not firing then
		-- push the drained battery into the client's snapshot
		DataService.update(player, function() end)
	end
end

local function removeLanterns(player: Player)
	for _, container in { player:FindFirstChild("Backpack"), player.Character } do
		if container then
			for _, item in container:GetChildren() do
				if item:IsA("Tool") and item.Name == "Lantern" then
					item:Destroy()
				end
			end
		end
	end
end

local function putAwayLaser(player: Player, giveLantern: boolean)
	local state = lasers[player]
	if not state then
		return
	end
	setFiring(player, false)
	lasers[player] = nil
	state.tool:Destroy()
	state.endAtt:Destroy()
	if giveLantern and aliveHumanoid(player) then
		task.spawn(LanternService.give, player)
	end
end

local function equipLaser(player: Player): (boolean, string)
	local character, humanoid = aliveHumanoid(player)
	if not character or not humanoid then
		return false, "You can't take that out right now."
	end
	removeLanterns(player)

	local tool = LaserBuilder.buildTool()
	tool:SetAttribute("OwnerUserId", player.UserId)
	local handle = tool:FindFirstChild("Handle") :: BasePart
	local lens = handle:FindFirstChild("Lens") :: Attachment
	local beam = handle:FindFirstChild("Beam") :: Beam
	local light = lens:FindFirstChild("LensLight") :: PointLight
	-- the beam's far end lives under Terrain so every client sees it move
	local endAtt = Instance.new("Attachment")
	endAtt.Name = "LaserEnd_" .. player.UserId
	endAtt.WorldPosition = lens.WorldPosition
	endAtt.Parent = workspace.Terrain
	beam.Attachment1 = endAtt

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local state: LaserState = {
		tool = tool,
		character = character,
		lens = lens,
		beam = beam,
		light = light,
		endAtt = endAtt,
		params = params,
		firing = false,
		equipping = true,
		aim = nil,
		hitEntity = nil,
		hitSince = 0,
		deadNotified = 0,
	}
	lasers[player] = state

	-- any unequip (hotbar, death, something destroying it) puts the laser away; the lantern comes back
	tool.AncestryChanged:Connect(function()
		task.defer(function()
			if lasers[player] ~= state or state.equipping then
				return
			end
			if tool.Parent == nil or not tool:IsDescendantOf(character) then
				putAwayLaser(player, true)
			end
		end)
	end)

	tool.Parent = player:WaitForChild("Backpack")
	humanoid:EquipTool(tool)
	task.delay(0.3, function()
		if lasers[player] ~= state then
			return
		end
		state.equipping = false
		if not tool:IsDescendantOf(character) then
			putAwayLaser(player, true)
		end
	end)
	return true, "Laser pointer out. Hold click to fire; press 4 to put it away."
end

local function toggleLaser(player: Player, data)
	if not data.LaserUnlocked then
		return result(false, "You don't own the laser pointer. The shop sells it.")
	end
	if lasers[player] then
		putAwayLaser(player, true)
		return result(true, "Laser pointer put away.")
	end
	local ok, message = equipLaser(player)
	return result(ok, message)
end

-- One Heartbeat of firing: drain, aim, raycast, move the beam end, track the entity under it.
local function tickLaser(player: Player, state: LaserState, dt: number, now: number)
	local character = state.character
	local _, humanoid = aliveHumanoid(player)
	if not humanoid or not state.tool:IsDescendantOf(character) then
		setFiring(player, false)
		return
	end
	local data = DataService.get(player)
	if not data then
		setFiring(player, false)
		return
	end
	local battery = data.LaserBattery - dt * BATTERY_MAX / T.LaserDrainSeconds
	setBattery(player, battery)
	if battery <= 0 then
		setFiring(player, false)
		notify(player, "The laser's battery is dead.")
		return
	end

	local origin = state.lens.WorldPosition
	local forward = state.lens.WorldCFrame.LookVector
	local dir = forward
	local aim = state.aim
	if aim then
		local toAim = aim - origin
		if toAim.Magnitude > 0.5 then
			toAim = toAim.Unit
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local facing = root and root.CFrame.LookVector or forward
			if toAim:Dot(forward) >= COS_CONE and toAim:Dot(facing) >= COS_CONE then
				dir = toAim
			end
		end
	end
	local hit = workspace:Raycast(origin, dir * T.LaserRange, state.params)
	local hitPos = hit and hit.Position or origin + dir * T.LaserRange
	state.endAtt.WorldPosition = hitPos

	local entity = hit and entityOf(hit.Instance) or nil
	if entity ~= state.hitEntity then
		clearHit(state, player)
		if entity then
			state.hitEntity = entity
			state.hitSince = now
			markLasered(entity, player, true)
			itemEvent(player, "laserHit", hitPos, entity)
		end
	elseif entity and now - state.hitSince >= T.LaserStunHold then
		if entity:GetAttribute("Unstunnable") ~= true then
			if entity:GetAttribute("Stunned") ~= true then
				stun(entity, player)
			end
			-- the next stun needs another LaserStunHold of beam after this one ends
			state.hitSince = now + T.LaserStunDuration
		end
	end
end

------------------------------------------------------------------------------------------
-- Use
------------------------------------------------------------------------------------------
function ItemService.use(player: Player, id: any)
	if typeof(id) ~= "string" then
		return result(false, "Invalid item.")
	end
	local def = Items.get(id)
	local data = DataService.get(player)
	if not def or not data then
		return result(false, "Invalid item.")
	end
	if id == "laser_pointer" then
		return toggleLaser(player, data)
	end
	if id == "lockpicks" then
		local count = data.Inventory[id] or 0
		if count <= 0 then
			return result(false, "No lockpicks. The shop sells them.")
		end
		return result(false, "Hold the prompt on a locked chest to use a lockpick.", { kind = "info" })
	end
	local count = data.Inventory[id] or 0
	if count <= 0 then
		return result(false, string.format("No %s left. The shop sells them.", def.name))
	end
	local remaining = cooldownLeft(player, id)
	if remaining > 0 then
		return result(
			false,
			string.format("%s ready in %ds.", def.name, math.ceil(remaining)),
			{ cooldown = remaining }
		)
	end
	local character, humanoid = aliveHumanoid(player)
	if not character or not humanoid then
		return result(false, "You can't use that right now.")
	end
	local ok, message
	if id == "speed_pills" then
		ok, message = applySpeed(character, humanoid, def)
	elseif id == "bandage" then
		ok, message = applyHeal(character, humanoid, def)
	else
		ok, message = false, "That item can't be used here."
	end
	if not ok then
		return result(false, message)
	end
	DataService.update(player, function(d)
		d.Inventory[id] = math.max((d.Inventory[id] or 0) - 1, 0)
	end)
	setCooldown(player, id, def.cooldown)
	return result(true, message, { cooldown = def.cooldown })
end

------------------------------------------------------------------------------------------
-- Lockables
------------------------------------------------------------------------------------------
-- Parts with a `Hinge` attribute (a CFrame in the part's own space whose X axis is the hinge line) swing
-- about it; t = 0 closed .. 1 open.
local function setSwing(lock: Lock, t: number)
	for _, s in lock.swings do
		local hingeWorld = s.closed * s.hinge
		s.part.CFrame = hingeWorld * CFrame.Angles(s.angle * t, 0, 0) * s.hinge:Inverse()
	end
end

local function animateSwing(lock: Lock, open: boolean, duration: number)
	if #lock.swings == 0 then
		return
	end
	local driver = Instance.new("NumberValue")
	driver.Value = if open then 0 else 1
	driver.Changed:Connect(function(t)
		setSwing(lock, t)
	end)
	local info = if open
		then TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		else TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(driver, info, { Value = if open then 1 else 0 })
	tween.Completed:Once(function()
		driver:Destroy()
	end)
	tween:Play()
end

local function pickLock(player: Player, lock: Lock)
	local model = lock.model
	if model:GetAttribute("Locked") ~= true then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	local lockId = tostring(model:GetAttribute("LockId") or model:GetFullName())
	if (data.Inventory.lockpicks or 0) <= 0 then
		notify(player, "You need lockpicks. The shop sells them.")
		return
	end
	if data.OpenedLocks[lockId] then
		notify(player, "Already emptied by you.")
		return
	end
	local reward = tonumber(model:GetAttribute("Reward")) or 0
	model:SetAttribute("Locked", false)
	lock.prompt.Enabled = false
	DataService.update(player, function(d)
		d.Inventory.lockpicks = math.max((d.Inventory.lockpicks or 0) - 1, 0)
		d.Keys += reward
		d.OpenedLocks[lockId] = true
	end)
	animateSwing(lock, true, 0.9)
	if lock.light then
		lock.light.Enabled = true
	end
	itemEvent(nil, "unlock", model, player)
	notify(player, string.format("Lock picked. Inside: %d %s.", reward, Config.CurrencyName))

	-- it locks itself again so other players can have a go
	task.delay(T.LockRelockSeconds, function()
		if not model.Parent or locks[model] ~= lock then
			return
		end
		animateSwing(lock, false, 0.6)
		if lock.light then
			lock.light.Enabled = false
		end
		model:SetAttribute("Locked", true)
		lock.prompt.Enabled = true
	end)
end

local function setupLock(model: Instance)
	if not model:IsA("Model") or locks[model] then
		return
	end
	local host = model:FindFirstChild("Lock") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not host or not host:IsA("BasePart") then
		return
	end
	if model:GetAttribute("Locked") == nil then
		model:SetAttribute("Locked", true)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = tostring(model:GetAttribute("PromptName") or "Locked chest")
	prompt.ActionText = "Pick lock"
	prompt.HoldDuration = T.LockHoldSeconds
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = model:GetAttribute("Locked") == true
	prompt:SetAttribute("Panel", "Lock") -- the lobby HUD ignores prompts with a Panel it doesn't know
	prompt.Parent = host

	local swings: { Swing } = {}
	for _, spec in { { "Lid", 105 }, { "Lock", 35 } } do
		local part = model:FindFirstChild(spec[1])
		local hinge = part and part:GetAttribute("Hinge")
		if part and part:IsA("BasePart") and typeof(hinge) == "CFrame" then
			table.insert(swings, {
				part = part,
				hinge = hinge,
				closed = part.CFrame,
				angle = math.rad(tonumber(part:GetAttribute("OpenAngle")) or spec[2]),
			})
		end
	end
	local light = nil
	for _, d in model:GetDescendants() do
		if d:IsA("PointLight") and d.Name == "GlintLight" then
			light = d
			break
		end
	end
	local lock: Lock = { model = model, prompt = prompt, swings = swings, light = light }
	locks[model] = lock
	prompt.Triggered:Connect(function(player)
		pickLock(player, lock)
	end)
end

------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------
function ItemService.start(opts: { recharge: boolean? }?)
	recharge = not (opts and opts.recharge == false)

	Remotes.get("BuyItem").OnServerInvoke = ItemService.buy
	Remotes.get("UseItem").OnServerInvoke = ItemService.use
	Remotes.get("LaserFire").OnServerEvent:Connect(function(player, firing)
		if typeof(firing) == "boolean" then
			setFiring(player, firing)
		end
	end)
	Remotes.get("LaserAim").OnServerEvent:Connect(function(player, aim)
		local state = lasers[player]
		if state and typeof(aim) == "Vector3" and aim.X == aim.X and aim.Magnitude < 1e5 then
			state.aim = aim
		end
	end)

	local function onPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			putAwayLaser(player, false)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		putAwayLaser(player, false)
		cooldowns[player] = nil
		for entity, set in laseredBy do
			if set[player] then
				markLasered(entity, player, false)
			end
		end
	end)
	-- the battery attribute follows the profile as soon as it loads
	DataService.Changed:Connect(function(player, data)
		if player:GetAttribute("LaserBattery") == nil then
			player:SetAttribute("LaserBattery", math.floor((data.LaserBattery or 0) + 0.5))
		end
	end)

	for _, model in CollectionService:GetTagged("Lockable") do
		setupLock(model)
	end
	CollectionService:GetInstanceAddedSignal("Lockable"):Connect(setupLock)
	CollectionService:GetInstanceRemovedSignal("Lockable"):Connect(function(model)
		locks[model] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, state in lasers do
			if state.firing then
				tickLaser(player, state, dt, now)
			end
		end
	end)

	-- idle recharge (lobby only)
	task.spawn(function()
		while true do
			task.wait(1)
			if recharge then
				for _, player in Players:GetPlayers() do
					local data = DataService.get(player)
					local state = lasers[player]
					if
						data
						and data.LaserUnlocked
						and data.LaserBattery < BATTERY_MAX
						and not (state and state.firing)
					then
						setBattery(player, data.LaserBattery + BATTERY_MAX / T.LaserRechargeSeconds)
					end
				end
			end
		end
	end)
end

return ItemService
