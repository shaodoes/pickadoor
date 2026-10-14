--[[
	WorldClient: the client half of the worlds. While the local player is inside a world (their World
	attribute), it runs that world's client module, applies its Lighting mood and routes WorldEvent.

	Client module contract (src/trial/client/Worlds/<Module>.luau, see _Template.luau):
	  enter(ctx) -> cleanup: () -> ()
	ctx:
	  id, def (Shared.Worlds entry), model (Trial.Worlds.<id>), player
	  onEvent(fn(kind, ...)) -> disconnect     WorldEvent from this world's server module
	  fire(kind, ...)                          WorldEvent to it (its onClientEvent)
	  caption(text, seconds?)                  a subtitle line (Screen.caption)
	  Screen, Sfx, Config                      modules, for convenience

	Handled here for every world: "caption" (subtitle), "pickup" / "taken" / "collectible" (hide what
	you've collected; key pickups spin), the mood. Spectating someone (the camera on their humanoid)
	shows their world's mood. The blue guide path is GuidePath (started here).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local Worlds = require(Shared:WaitForChild("Worlds"))
local GuidePath = require(script.Parent:WaitForChild("GuidePath"))
local Screen = require(script.Parent:WaitForChild("Screen"))
local WorldMood = require(script.Parent:WaitForChild("WorldMood"))

local player = Players.LocalPlayer
local worldsFolder = workspace:WaitForChild("Trial"):WaitForChild("Worlds")
local modules = script.Parent:WaitForChild("Worlds")
local worldEvent = Remotes.get("WorldEvent")

task.spawn(GuidePath.start)

-- hide (or show again) a part and everything under it, for this client only
local function setHidden(part: Instance, hidden: boolean)
	for _, d in { part, table.unpack(part:GetDescendants()) } do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		elseif d:IsA("Light") or d:IsA("ProximityPrompt") then
			d.Enabled = not hidden
		end
	end
end

------------------------------------------------------------------------------------------
-- The world we're in
------------------------------------------------------------------------------------------
type Session = {
	id: string,
	model: Instance,
	handlers: { (string, ...any) -> () },
	cleanup: (() -> ())?,
	hidden: { Instance },
}
local session: Session? = nil

local function leave()
	local s = session
	if not s then
		return
	end
	session = nil
	if s.cleanup then
		local ok, err = pcall(s.cleanup)
		if not ok then
			warn("[WorldClient] " .. s.id .. " cleanup failed: " .. tostring(err))
		end
	end
	for _, inst in s.hidden do
		if inst.Parent then
			setHidden(inst, false)
		end
	end
end

local function enter(id: string)
	leave()
	local def = Worlds.get(id)
	if not def or not def.play then
		return
	end
	local model = worldsFolder:WaitForChild(id, 10)
	if not model or player:GetAttribute("World") ~= id then
		return
	end
	local s: Session = { id = id, model = model, handlers = {}, cleanup = nil, hidden = {} }
	session = s
	local module = modules:FindFirstChild(def.play.module)
	if module then
		local ctx = {
			id = id,
			def = def,
			model = model,
			player = player,
			Screen = Screen,
			Sfx = Sfx,
			Config = Config,
		}
		function ctx.onEvent(fn: (string, ...any) -> ()): () -> ()
			table.insert(s.handlers, fn)
			return function()
				local i = table.find(s.handlers, fn)
				if i then
					table.remove(s.handlers, i)
				end
			end
		end
		function ctx.fire(kind: string, ...)
			worldEvent:FireServer(id, kind, ...)
		end
		function ctx.caption(text: string, seconds: number?)
			Screen.caption(text, seconds)
		end
		local ok, result = pcall(require(module).enter, ctx)
		if ok then
			s.cleanup = result
		else
			warn("[WorldClient] " .. id .. " enter failed: " .. tostring(result))
		end
	end
end

local function hideNamed(name: string)
	local s = session
	local part = s and s.model:FindFirstChild(name, true)
	if s and part then
		setHidden(part, true)
		table.insert(s.hidden, part)
	end
end

worldEvent.OnClientEvent:Connect(function(id, kind, ...)
	local s = session
	if not s or s.id ~= id then
		return
	end
	if kind == "caption" then
		local text, seconds = ...
		Screen.caption(text, seconds)
	elseif kind == "pickup" then
		hideNamed((...))
		Sfx.play("KeyPickup", 0.05)
	elseif kind == "taken" then
		for _, name in (...) or {} do
			hideNamed(name)
		end
	elseif kind == "collectible" then
		hideNamed((...))
		Sfx.play("RewardChime", 0.02)
	end
	for _, fn in table.clone(s.handlers) do
		task.spawn(fn, kind, ...)
	end
end)

player:GetAttributeChangedSignal("World"):Connect(function()
	local id = player:GetAttribute("World")
	if typeof(id) == "string" then
		task.spawn(enter, id)
	else
		leave()
	end
end)
if typeof(player:GetAttribute("World")) == "string" then
	task.spawn(enter, player:GetAttribute("World"))
end

------------------------------------------------------------------------------------------
-- Mood (ours, or whoever we're watching) and spinning key pickups
------------------------------------------------------------------------------------------
local function viewedWorld(): string?
	local subject = workspace.CurrentCamera.CameraSubject
	local character = subject and subject:IsA("Humanoid") and subject.Parent
	local watched = character and Players:GetPlayerFromCharacter(character)
	local id = (watched or player):GetAttribute("World")
	return if typeof(id) == "string" then id else nil
end

local moodWorld: string? = "-"
local nextMoodCheck = 0
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now >= nextMoodCheck then
		nextMoodCheck = now + 0.3
		local id = viewedWorld()
		if id ~= moodWorld then
			moodWorld = id
			local def = Worlds.get(id)
			WorldMood.apply(def and def.play and def.play.mood or nil, if id then 0.6 else 1.2)
		end
	end
	local s = session
	if s then
		local spin = CFrame.Angles(0, now * 2 % (math.pi * 2), 0)
		for _, key in CollectionService:GetTagged("KeyPickup") do
			if key:IsDescendantOf(s.model) and key:IsA("BasePart") then
				local home = key:GetAttribute("Home")
				if typeof(home) ~= "CFrame" then
					home = key.CFrame
					key:SetAttribute("Home", home)
				end
				key.CFrame = (home :: CFrame) * CFrame.new(0, math.sin(now * 2) * 0.15, 0) * spin
			end
		end
	end
end)
