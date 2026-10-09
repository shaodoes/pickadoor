--[[
	Per-room mood (client-only). Owns the Lighting post-effects at runtime: the lobby builder lays down a
	neutral base (Atmosphere, ColorCorrection, Bloom, ambients) and this script eases all of it toward
	the RoomMoods profile of the room the player is in, so each room has its own air and grade and the
	change is a ~1.5 s blend, never a cut. Nothing here replicates: other players see their own room.

	  grade      Atmosphere, ColorCorrection, Bloom, Lighting.Ambient/OutdoorAmbient/ExposureCompensation
	  tension    in the door hall the grade tightens (redder, flatter, heavier edges, thicker air) with the
	             queue tension DoorFX writes on the PICK A DOOR sign
	  vignette   four gradient frames at the screen edges (ScreenGui behind every other UI)
	  lantern    the held lantern's light follows the room's `lantern` scale (LanternFX.heldLightScale;
	             other players' lanterns are scaled the same way, every 2 s)
	  haze       each room's RoomMoods.haze volumes: big, very faint smoke puffs lit only by the lamps
	             around them (LightInfluence 1), so light seems to hang in the air. Only the current
	             room's (and its neighbours') volumes emit; the rest fade out as their puffs die.
	             Rates follow the player's graphics quality.

	Room resolution reuses the Shell's FX = "Room" anchors (as AmbientSound does), from the character's
	position (the camera when there's no character), at 5 Hz.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoomMoods = require(Shared:WaitForChild("RoomMoods"))
local LanternFX = require(Shared:WaitForChild("LanternFX"))

local player = Players.LocalPlayer
local lobby = workspace:WaitForChild("Lobby", 60)
if not lobby then
	return
end

local SMOOTH = 3 / RoomMoods.BLEND_TIME -- exponential rate: ~95% of the way there after BLEND_TIME
local ROOM_EVERY = 0.2
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
-- neighbours whose haze keeps drifting while you're next door (half rate)
local NEIGHBOURS: { [string]: { string } } = {
	Foyer = { "Shop" },
	Shop = { "Foyer" },
	Stair = { "Foyer", "Hall" },
	Hall = { "Workshop", "DoorHall" },
	Workshop = { "Hall" },
	DoorHall = { "Hall" },
}

------------------------------------------------------------------------------------------
-- The Lighting instances (the builder's, or our own if a place has none)
------------------------------------------------------------------------------------------
local function ensure(className: string, name: string): Instance
	local inst = Lighting:FindFirstChildOfClass(className)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end
local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
local grade = ensure("ColorCorrectionEffect", "ColorCorrection") :: ColorCorrectionEffect
local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect

------------------------------------------------------------------------------------------
-- Blend state: a flat list of numeric channels (colours split into r, g, b)
------------------------------------------------------------------------------------------
type Channel = { group: string, key: string, comp: string? }
local CHANNELS: { Channel } = {}
local function add(group: string, key: string, isColor: boolean?)
	if isColor then
		for _, comp in { "R", "G", "B" } do
			table.insert(CHANNELS, { group = group, key = key, comp = comp })
		end
	else
		table.insert(CHANNELS, { group = group, key = key })
	end
end
add("atmosphere", "Density")
add("atmosphere", "Offset")
add("atmosphere", "Haze")
add("atmosphere", "Glare")
add("atmosphere", "Color", true)
add("atmosphere", "Decay", true)
add("grade", "Tint", true)
add("grade", "Contrast")
add("grade", "Saturation")
add("grade", "Brightness")
add("bloom", "Intensity")
add("bloom", "Size")
add("bloom", "Threshold")
add("light", "Ambient", true)
add("light", "OutdoorAmbient", true)
add("light", "Exposure")
add("vignette", "Amount")
add("lantern", "Scale")

local function flatten(profile): { number }
	local out = table.create(#CHANNELS)
	for i, ch in CHANNELS do
		local value = if ch.group == "vignette" or ch.group == "lantern"
			then profile[ch.group]
			else profile[ch.group][ch.key]
		out[i] = if ch.comp then (value :: any)[ch.comp] else value
	end
	return out
end

-- tension offsets (added, scaled by tension); colours lerp toward the tension tint instead
local function tensionTarget(base: { number }, room: string, tension: number): { number }
	local spec = RoomMoods.Profiles[room] and RoomMoods.Profiles[room].tension
	if not spec or tension <= 0.001 then
		return base
	end
	local out = table.clone(base)
	for i, ch in CHANNELS do
		local value
		if ch.group == "vignette" or ch.group == "lantern" then
			value = spec[ch.group]
		else
			value = spec[ch.group] and spec[ch.group][ch.key]
		end
		if value ~= nil then
			if ch.comp then
				out[i] = base[i] + ((value :: any)[ch.comp] - base[i]) * tension
			else
				out[i] = base[i] + value * tension
			end
		end
	end
	return out
end

local cache: { [string]: { number } } = {}
local function targetFor(room: string): { number }
	local t = cache[room]
	if not t then
		t = flatten(RoomMoods.resolve(room))
		cache[room] = t
	end
	return t
end

------------------------------------------------------------------------------------------
-- Vignette
------------------------------------------------------------------------------------------
local vignetteFrames: { Frame } = {}
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "MoodVignette"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10 -- under every other lobby UI
	gui.Parent = player:WaitForChild("PlayerGui")
	-- {size, position, gradient rotation (0 = dark at the left edge)}
	for _, spec in
		{
			{ UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0), 90 },
			{ UDim2.fromScale(1, 0.24), UDim2.fromScale(0, 0.76), 270 },
			{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0, 0), 0 },
			{ UDim2.fromScale(0.2, 1), UDim2.fromScale(0.8, 0), 180 },
		}
	do
		local f = Instance.new("Frame")
		f.Size = spec[1]
		f.Position = spec[2]
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		table.insert(vignetteFrames, f)
	end
end

------------------------------------------------------------------------------------------
-- Haze volumes
------------------------------------------------------------------------------------------
local gameSettings = UserSettings():GetService("UserGameSettings")
local function quality(): number
	local level = gameSettings.SavedQualityLevel
	if level == Enum.SavedQualitySetting.Automatic then
		return 0.75
	end
	return math.clamp(level.Value / 10, 0.1, 1)
end

local hazeFolder = Instance.new("Folder")
hazeFolder.Name = "MoodFX"
hazeFolder.Parent = workspace

type Haze = { emitter: ParticleEmitter, rate: number, room: string, weight: number }
local hazes: { Haze } = {}
for room, profile in RoomMoods.Profiles do
	for i, spec in profile.haze or {} do
		local p = Instance.new("Part")
		p.Name = room .. "Haze" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = spec.size
		p.CFrame = spec.cf
		p.Parent = hazeFolder
		local puff = spec.puff or 7
		local e = Instance.new("ParticleEmitter")
		e.Texture = SMOKE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 0
		e.Lifetime = NumberRange.new(10, 16)
		e.Speed = NumberRange.new(0.05, 0.25)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 0.4
		e.Acceleration = Vector3.new(0, 0.015, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-5, 5)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, puff * 0.6),
			NumberSequenceKeypoint.new(1, puff * 1.25),
		})
		-- each puff is barely there; many overlapping ones build a soft, uneven volume
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.935),
			NumberSequenceKeypoint.new(0.7, 0.935),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Color = ColorSequence.new(spec.color)
		e.LightEmission = 0
		e.LightInfluence = spec.lit or 1 -- only visible where a lamp actually lights the air
		e.Brightness = 1.6
		e.Parent = p
		table.insert(hazes, { emitter = e, rate = spec.rate or 1.5, room = room, weight = 0 })
	end
end

------------------------------------------------------------------------------------------
-- Room tracking
------------------------------------------------------------------------------------------
local roomAnchors: { BasePart } = {}
local function considerAnchor(d: Instance)
	if d:IsA("BasePart") and d:GetAttribute("FX") == "Room" then
		table.insert(roomAnchors, d)
	end
end
for _, d in lobby:GetDescendants() do
	considerAnchor(d)
end
lobby.DescendantAdded:Connect(considerAnchor)

local heroSign: Instance? = nil
task.spawn(function()
	local queue = lobby:WaitForChild("Queue", 30)
	heroSign = queue and queue:WaitForChild("StencilSign", 30)
end)

local function probePosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local room = "Foyer"
local nextRoomCheck = 0
local tension = 0
local state = table.clone(targetFor(room))
local q = quality()
local nextQuality = 0

local function apply(v: { number })
	local i = 0
	local function n(): number
		i += 1
		return v[i]
	end
	local function c(): Color3
		return Color3.new(math.clamp(n(), 0, 1), math.clamp(n(), 0, 1), math.clamp(n(), 0, 1))
	end
	atmosphere.Density = n()
	atmosphere.Offset = n()
	atmosphere.Haze = n()
	atmosphere.Glare = n()
	atmosphere.Color = c()
	atmosphere.Decay = c()
	grade.TintColor = c()
	grade.Contrast = n()
	grade.Saturation = n()
	grade.Brightness = n()
	bloom.Intensity = n()
	bloom.Size = n()
	bloom.Threshold = n()
	Lighting.Ambient = c()
	Lighting.OutdoorAmbient = c()
	Lighting.ExposureCompensation = n()
	local amount = math.clamp(n(), 0, 1)
	for _, f in vignetteFrames do
		f.BackgroundTransparency = 1 - amount
	end
	LanternFX.heldLightScale = n()
end

-- Other players' lanterns aren't animated here (LanternFX only drives your own), so their lights are
-- scaled directly, by the same factor, from the brightness they were built with.
local otherBase: { [Light]: number } = setmetatable({}, { __mode = "k" }) :: any
local function scaleOtherLanterns(scale: number)
	for _, other in Players:GetPlayers() do
		local tool = other ~= player and other.Character and other.Character:FindFirstChild("Lantern")
		local parts = tool and tool:IsA("Tool") and LanternFX.flameParts(tool)
		local light = parts and parts.light
		if light then
			local base = otherBase[light]
			if not base then
				base = light.Brightness
				otherBase[light] = base
			end
			light.Brightness = base * scale
		end
	end
end
apply(state)

local settled = false
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	if now >= nextRoomCheck then
		nextRoomCheck = now + ROOM_EVERY
		local pos = probePosition()
		if pos then
			local newRoom = RoomMoods.roomAt(pos, roomAnchors, room)
			if newRoom ~= room then
				room = newRoom
				settled = false
			end
		end
		local raw = heroSign and heroSign:GetAttribute("Tension")
		local newTension = if typeof(raw) == "number" then math.clamp(raw, 0, 1) else 0
		if room ~= "DoorHall" then
			newTension = 0
		end
		if math.abs(newTension - tension) > 0.01 then
			tension = newTension
			settled = false
		end
		if now >= nextQuality then
			nextQuality = now + 2
			q = quality()
			scaleOtherLanterns(LanternFX.heldLightScale)
		end
		-- haze: this room full, its neighbours at half, the rest off (their puffs fade as they die)
		local near = NEIGHBOURS[room] or {}
		for _, h in hazes do
			local w = if h.room == room then 1 elseif table.find(near, h.room) then 0.5 else 0
			if w ~= h.weight then
				h.weight = w
			end
			h.emitter.Rate = h.rate * w * (0.3 + 0.7 * q)
		end
	end

	if settled then
		return
	end
	local target = tensionTarget(targetFor(room), room, tension)
	local k = 1 - math.exp(-SMOOTH * math.min(dt, 0.1))
	local maxDelta = 0
	for i, goal in target do
		local d = goal - state[i]
		state[i] += d * k
		maxDelta = math.max(maxDelta, math.abs(d))
	end
	if maxDelta < 0.001 then
		state = table.clone(target)
		settled = true
	end
	apply(state)
end)
