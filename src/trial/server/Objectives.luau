--[[
	Objectives: a dangerous world's chain of steps before its exit opens (2-3 steps per world). Progress
	is party-shared: anyone inside finishing a step finishes it for everyone. WorldHost creates one
	chain per world from the server module's `steps` and wires the exit to chain.complete().

	  local chain = Objectives.new(worldModel, steps, {
	      inside = function(player) -> boolean end,   -- only players inside this world count
	      onAdvance = function(index, step, by) end,  -- optional: a step was finished (by: Player?)
	  })

	A step:
	  {
	    id = "breakers",
	    text = "RESTORE THE BREAKERS",       -- shown as the objective; "(2/3)" is appended for counts
	    kind = "interact" | "collect" | "reach" | "custom",
	    targets = { BasePart } | BasePart,    -- interact / collect / reach: each one must be done once
	    action = "Restore",                   -- interact / collect: the prompt's ActionText
	    hold = 3,                             -- interact / collect: the prompt's HoldDuration
	    radius = 6,                           -- reach: studs from a target's position (default 6)
	    canUse = function(player, part) -> (boolean, string?) end, -- optional gate (+ a refusal line)
	    target = function(player) -> BasePart? end, -- optional: what the blue guide path points at
	    done = function() -> boolean end,     -- custom: polled 5x a second (or call chain.advance)
	  }
	interact: a ProximityPrompt on each target (made here unless the part already has one), enabled only
	  while its step is current; collect: the same, and the part vanishes once taken (back on reset);
	reach: any inside player's root within `radius` of a target.

	Replicated on the world model: ObjIndex (1-based; #steps + 1 = complete), ObjCount, ObjText, ObjDone.
	API: chain.index(), chain.complete(), chain.current(), chain.advance(by?), chain.text(),
	     chain.targetFor(player) (default: the nearest unfinished target), chain.reset(), chain.stop()
]]
local Players = game:GetService("Players")

local Objectives = {}

export type Step = {
	id: string,
	text: string,
	kind: string,
	targets: any?,
	action: string?,
	hold: number?,
	radius: number?,
	canUse: ((Player, BasePart) -> (boolean, string?))?,
	target: ((Player) -> BasePart?)?,
	done: (() -> boolean)?,
}

export type Hooks = {
	inside: (Player) -> boolean,
	onAdvance: ((number, Step, Player?) -> ())?,
	notify: ((Player, string) -> ())?,
}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function targetsOf(step: Step): { BasePart }
	local t = step.targets
	if typeof(t) == "Instance" then
		return { t :: BasePart }
	end
	return (t or {}) :: { BasePart }
end

-- Hide / show a collected part (and everything under it), remembering how it looked.
local function setTaken(part: BasePart, taken: boolean)
	local list: { Instance } = { part }
	for _, d in part:GetDescendants() do
		table.insert(list, d)
	end
	for _, inst in list do
		if inst:IsA("BasePart") or inst:IsA("Decal") then
			local key = "ObjTransparency"
			if taken then
				if inst:GetAttribute(key) == nil then
					inst:SetAttribute(key, inst.Transparency)
				end
				inst.Transparency = 1
			elseif inst:GetAttribute(key) ~= nil then
				inst.Transparency = inst:GetAttribute(key)
				inst:SetAttribute(key, nil)
			end
		elseif inst:IsA("Light") then
			inst.Enabled = not taken
		end
	end
end

function Objectives.new(world: Model, steps: { Step }, hooks: Hooks)
	local index = 1
	local doneTargets: { [BasePart]: boolean } = {}
	local prompts: { [BasePart]: ProximityPrompt } = {}
	local connections: { RBXScriptConnection } = {}
	local running = true

	local chain = {}

	local function current(): Step?
		return steps[index]
	end

	local function remaining(step: Step): ({ BasePart }, number)
		local list = {}
		local all = targetsOf(step)
		for _, part in all do
			if not doneTargets[part] then
				table.insert(list, part)
			end
		end
		return list, #all
	end

	local function text(): string
		local step = current()
		if not step then
			return ""
		end
		local left, total = remaining(step)
		if total > 1 then
			return string.format("%s  %d/%d", step.text, total - #left, total)
		end
		return step.text
	end
	chain.text = text

	local function publish()
		world:SetAttribute("ObjIndex", index)
		world:SetAttribute("ObjCount", #steps)
		world:SetAttribute("ObjText", text())
		world:SetAttribute("ObjDone", index > #steps)
	end

	local function refreshPrompts()
		local step = current()
		for part, prompt in prompts do
			local live = false
			if step and (step.kind == "interact" or step.kind == "collect") and not doneTargets[part] then
				live = table.find(targetsOf(step), part) ~= nil
			end
			prompt.Enabled = live
		end
	end

	function chain.advance(by: Player?)
		local step = current()
		if not step or not running then
			return
		end
		index += 1
		publish()
		refreshPrompts()
		if hooks.onAdvance then
			task.spawn(hooks.onAdvance, index - 1, step, by)
		end
	end

	-- one target of the current step is done; the step finishes when they all are
	local function finishTarget(part: BasePart, by: Player?)
		local step = current()
		if not step or doneTargets[part] or not table.find(targetsOf(step), part) then
			return
		end
		doneTargets[part] = true
		if step.kind == "collect" then
			setTaken(part, true)
		end
		local left = remaining(step)
		if #left == 0 then
			chain.advance(by)
		else
			publish()
			refreshPrompts()
		end
	end

	-- prompts for every interact / collect target, all steps up front (enabled only when current)
	for _, step in steps do
		if step.kind ~= "interact" and step.kind ~= "collect" then
			continue
		end
		for _, part in targetsOf(step) do
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = step.action or (if step.kind == "collect" then "Take" else "Use")
				prompt.ObjectText = ""
				prompt.HoldDuration = step.hold or 0
				prompt.MaxActivationDistance = 9
				prompt.RequiresLineOfSight = false
				prompt.Parent = part
			end
			prompts[part] = prompt
			table.insert(
				connections,
				prompt.Triggered:Connect(function(player)
					if not hooks.inside(player) or current() ~= step then
						return
					end
					if step.canUse then
						local ok, why = step.canUse(player, part)
						if not ok then
							if why and hooks.notify then
								hooks.notify(player, why)
							end
							return
						end
					end
					finishTarget(part, player)
				end)
			)
		end
	end

	-- reach / custom steps are polled
	task.spawn(function()
		while running do
			local step = current()
			if step and step.kind == "reach" then
				local radius = step.radius or 6
				for _, player in Players:GetPlayers() do
					local root = hooks.inside(player) and rootOf(player)
					if root then
						for _, part in remaining(step) do
							if (part.Position - root.Position).Magnitude <= radius then
								finishTarget(part, player)
							end
						end
					end
				end
			elseif step and step.kind == "custom" and step.done and step.done() then
				chain.advance(nil)
			end
			task.wait(0.2)
		end
	end)

	function chain.index(): number
		return index
	end

	function chain.complete(): boolean
		return index > #steps
	end

	function chain.current(): Step?
		return current()
	end

	-- What the blue guide path should lead `player` to: the step's own choice, else the nearest
	-- unfinished target of the current step (nil once complete: WorldHost points at the exit then).
	function chain.targetFor(player: Player): BasePart?
		local step = current()
		if not step then
			return nil
		end
		if step.target then
			return step.target(player)
		end
		local root = rootOf(player)
		local best, bestDist = nil, math.huge
		for _, part in remaining(step) do
			local d = if root then (part.Position - root.Position).Magnitude else 0
			if d < bestDist then
				best, bestDist = part, d
			end
		end
		return best
	end

	function chain.reset()
		index = 1
		for part in doneTargets do
			setTaken(part, false)
		end
		table.clear(doneTargets)
		publish()
		refreshPrompts()
	end

	function chain.stop()
		running = false
		for _, c in connections do
			c:Disconnect()
		end
		table.clear(connections)
	end

	publish()
	refreshPrompts()
	return chain
end

return Objectives
