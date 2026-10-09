-- Lobby soundscape (client-only):
--   room tone   2D beds (library air, basement rumble, workshop machinery, natatorium water) crossfaded
--               by the room the camera is in (FX="Room" volumes, attribute Room = Foyer|Shop|...)
--   anchors     positional loops / random one-shots at FX anchors (Furnace, Boiler, Hum, Steam, Water,
--               WindowShaft, Pipes, Drip, Clock), culled by distance from the camera
--   doors       each pad's Leaf rattles while its queue counts down, shakes in the last five seconds and
--               creaks open with a whoosh on launch; a low drone swells with the highest pad tension
--   clock       ticks in step with DoorFX's second hand (tick, tick, tick, back); chatters while time runs backwards
--   extras      occasional paper rustles, tile footsteps for the local character
-- Everything is optional: missing anchors just mean silence there. Work runs at 10 Hz, not per frame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local lobby = workspace:WaitForChild("Lobby", 60)
if not lobby then
	return
end

local rng = Random.new()
local TICK = 0.1 -- seconds between updates
local CULL_MARGIN = 12 -- studs past a sound's max distance before it is paused

------------------------------------------------------------------------------------------
-- Room tone
------------------------------------------------------------------------------------------
local BEDS = { "AmbLibrary", "AmbBasement", "AmbWorkshop", "AmbWater" }
-- relative level of each bed per room (missing = silent)
local ROOM_MIX: { [string]: { [string]: number } } = {
	Foyer = { AmbLibrary = 1, AmbBasement = 0.3 },
	Shop = { AmbLibrary = 0.35, AmbBasement = 0.55 }, -- the shop went dark: less library air, more low rumble under the drone
	Stair = { AmbLibrary = 0.8, AmbBasement = 0.6, AmbWater = 0.3 },
	Hall = { AmbLibrary = 1, AmbBasement = 0.4, AmbWater = 0.8 },
	DoorHall = { AmbLibrary = 0.35, AmbBasement = 1, AmbWater = 0.2 },
	Workshop = { AmbBasement = 0.5, AmbWorkshop = 1 },
	Outside = { AmbBasement = 0.6 },
}
-- how much of the door drone reaches each room
local DRONE_REACH: { [string]: number } = { DoorHall = 1, Hall = 0.45, Stair = 0.2, Workshop = 0.15 }

-- Fallback room bounds (mirrors Layout.Rooms) for when no Room anchors exist yet.
local FALLBACK_ROOMS = {
	{ name = "Foyer", min = Vector3.new(-2, 4, 42), max = Vector3.new(30, 22, 66) },
	{ name = "Shop", min = Vector3.new(-30, 4, 42), max = Vector3.new(-6, 21, 66) },
	{ name = "Stair", min = Vector3.new(4, -2, 30), max = Vector3.new(20, 21, 42) },
	{ name = "Hall", min = Vector3.new(-32, -2, -20), max = Vector3.new(32, 18, 30) },
	{ name = "DoorHall", min = Vector3.new(-36, -2, -60), max = Vector3.new(36, 20, -24) },
	{ name = "Workshop", min = Vector3.new(36, -7, -14), max = Vector3.new(62, 11, 18) },
}

local beds: { [string]: Sound } = {}
for _, name in BEDS do
	local sound = Sfx.loop(SoundService, name, { volume = 0 })
	if sound then
		beds[name] = sound
	end
end
local drone = Sfx.loop(SoundService, "DoorDrone", { volume = 0 })

-- Lobby music: one slow loop from the start of the track, ducked per room. It all but disappears in the
-- shop, where the shopkeeper's drone takes over, and thins out among the doors.
local MUSIC_MIX: { [string]: number } =
	{ Foyer = 1, Shop = 0.22, Stair = 0.9, Hall = 0.85, DoorHall = 0.5, Workshop = 0.7, Outside = 0.5 }
local music = Sfx.make(SoundService, "LobbyMusic", { volume = 0 })
if music then
	music.Looped = true
	music:Play()
end

-- The shop's drone hangs on the shopkeeper himself (built at runtime), or over his spot behind the counter.
task.spawn(function()
	local keeper = lobby:WaitForChild("Shopkeeper", 60)
	local host: Instance? = keeper and (keeper:FindFirstChild("Head") or keeper.PrimaryPart)
	if not host then
		local point = Instance.new("Attachment")
		point.Name = "ShopDroneAnchor"
		point.WorldPosition = Vector3.new(-23.4, 10, 53.2)
		point.Parent = workspace.Terrain
		host = point
	end
	Sfx.loop(host :: Instance, "ShopDrone")
end)

local roomParts: { BasePart } = {}
local currentRoom = "Hall"

local function inside(part: BasePart, pos: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size * 0.5
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

-- Which room the camera is in. Between volumes (doorways) the last room is kept so beds don't dip.
local function roomAt(pos: Vector3): string
	if #roomParts > 0 then
		for i = #roomParts, 1, -1 do
			local part = roomParts[i]
			if not part.Parent then
				table.remove(roomParts, i)
			elseif inside(part, pos) then
				return part:GetAttribute("Room") or currentRoom
			end
		end
	else
		for _, r in FALLBACK_ROOMS do
			if
				pos.X >= r.min.X
				and pos.X <= r.max.X
				and pos.Y >= r.min.Y
				and pos.Y <= r.max.Y
				and pos.Z >= r.min.Z
				and pos.Z <= r.max.Z
			then
				return r.name
			end
		end
	end
	return currentRoom
end

local function updateBeds(room: string, maxTension: number)
	local mix = ROOM_MIX[room] or ROOM_MIX.Outside
	for name, sound in beds do
		local target = (mix[name] or 0) * Config.Sounds[name].volume
		-- slow crossfade: ~1.5 s to settle
		sound.Volume += (target - sound.Volume) * 0.12
	end
	if drone then
		local def = Config.Sounds.DoorDrone
		local target = def.volume * maxTension * (DRONE_REACH[room] or 0.08)
		drone.Volume += (target - drone.Volume) * 0.1
		drone.PlaybackSpeed = 0.8 + maxTension * 0.3
	end
	if music then
		-- the music also sinks a little while a door is counting down, so the drone can rise over it
		local target = Config.Sounds.LobbyMusic.volume
			* (MUSIC_MIX[room] or MUSIC_MIX.Outside)
			* (1 - maxTension * 0.35)
		music.Volume += (target - music.Volume) * 0.06
	end
end

------------------------------------------------------------------------------------------
-- FX anchors
------------------------------------------------------------------------------------------
type Emitter = { name: string, min: number, max: number, volume: number? }
type Spec = { loops: { { name: string, volume: number? } }?, emitter: Emitter? }

local SPECS: { [string]: Spec } = {
	Furnace = { loops = { { name = "FurnaceFire" }, { name = "FurnaceRoar" } } },
	Boiler = { loops = { { name = "Boiler" } } },
	Hum = { loops = { { name = "LampHum" } } },
	Steam = { loops = { { name = "SteamHiss" } }, emitter = { name = "SteamBurst", min = 12, max = 35 } },
	Water = { loops = { { name = "WaterLap" } } },
	WindowShaft = { loops = { { name = "WaterLap", volume = Config.Sounds.WaterLap.volume * 0.6 } } },
	Pipes = { emitter = { name = "PipeGroan", min = 9, max = 28 } },
	Drip = { emitter = { name = "Drip", min = 2.5, max = 7 } },
}

type Anchor = {
	part: BasePart,
	spec: Spec,
	range: number, -- cull distance
	sounds: { Sound }?, -- created lazily the first time the camera comes near
	active: boolean,
	nextAt: number,
}

local anchors: { Anchor } = {}
local clocks: { Instance } = {} -- tick emitters (Clock anchors + the queue clock face)

local function rangeOf(spec: Spec): number
	local far = 0
	for _, l in spec.loops or {} do
		far = math.max(far, Config.Sounds[l.name].far or 60)
	end
	if spec.emitter then
		far = math.max(far, Config.Sounds[spec.emitter.name].far or 60)
	end
	return far + CULL_MARGIN
end

local function addClock(target: Instance)
	if not table.find(clocks, target) then
		table.insert(clocks, target)
	end
end

local function onDescendant(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local kind = d:GetAttribute("FX")
	if not kind then
		return
	end
	if kind == "Room" then
		table.insert(roomParts, d)
	elseif kind == "Clock" then
		addClock(d)
	else
		local spec = SPECS[kind]
		if spec then
			table.insert(anchors, {
				part = d,
				spec = spec,
				range = rangeOf(spec),
				active = false,
				nextAt = os.clock() + rng:NextNumber(0, spec.emitter and spec.emitter.max or 0),
			})
		end
	end
end

for _, d in lobby:GetDescendants() do
	onDescendant(d)
end
lobby.DescendantAdded:Connect(onDescendant)

local function setActive(a: Anchor, on: boolean)
	if a.active == on then
		return
	end
	a.active = on
	local loops = a.spec.loops
	if not loops then
		return
	end
	if on and not a.sounds then
		local list = {}
		for _, l in loops do
			local sound = Sfx.loop(a.part, l.name, l.volume and { volume = l.volume } or nil)
			if sound then
				table.insert(list, sound)
			end
		end
		a.sounds = list
	elseif a.sounds then
		for _, sound in a.sounds do
			if on then
				sound:Resume()
			else
				sound:Pause()
			end
		end
	end
end

local function updateAnchors(camPos: Vector3, now: number)
	for i = #anchors, 1, -1 do
		local a = anchors[i]
		if not a.part.Parent then
			-- streamed out or rebuilt: its sounds went with it
			table.remove(anchors, i)
		else
			local near = (a.part.Position - camPos).Magnitude <= a.range
			setActive(a, near)
			local e = a.spec.emitter
			if e and now >= a.nextAt then
				a.nextAt = now + rng:NextNumber(e.min, e.max)
				if near then
					Sfx.at(a.part, e.name, { jitter = 0.12, volume = e.volume })
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Door hall: pads
------------------------------------------------------------------------------------------
type Door = {
	pad: Instance,
	point: Attachment,
	rattle: Sound?,
	launching: boolean,
	nextShake: number,
	nextCreak: number,
}
local doors: { Door } = {}

local function addPad(pad: Instance)
	task.spawn(function()
		local leaf = pad:WaitForChild("Leaf", 15)
		if not leaf then
			return
		end
		local center: Vector3
		if leaf:IsA("Model") then
			center = leaf:GetBoundingBox().Position
		elseif leaf:IsA("BasePart") then
			center = leaf.Position
		else
			return
		end
		-- the sound sits where the closed leaf is, so the leaf swinging doesn't drag it around
		local point = Instance.new("Attachment")
		point.Name = "DoorSound_" .. pad.Name
		point.WorldPosition = center
		point.Parent = workspace.Terrain
		pad.Destroying:Once(function()
			point:Destroy()
		end)
		local rattle = Sfx.loop(point, "DoorRattle", { volume = 0 })
		local now = os.clock()
		table.insert(doors, {
			pad = pad,
			point = point,
			rattle = rattle,
			launching = pad:GetAttribute("Launching") == true,
			nextShake = now,
			nextCreak = now + rng:NextNumber(2, 6),
		})
	end)
end

-- Same curve as DoorFX: 0 when nobody is queued; 0.25 -> 1 as the countdown runs out.
local function tensionOf(pad: Instance): number
	if (pad:GetAttribute("Count") or 0) == 0 then
		return 0
	end
	local timeLeft = pad:GetAttribute("TimeLeft") or Config.QueueCountdown
	return 0.25 + 0.75 * math.clamp(1 - timeLeft / Config.QueueCountdown, 0, 1)
end

-- Returns the drone tension (launching counts as full) and DoorFX's clock tension (queues only).
local function updateDoors(camPos: Vector3, now: number): (number, number)
	local maxTension, queueTension = 0, 0
	for i = #doors, 1, -1 do
		local d = doors[i]
		local pad = d.pad
		if not pad.Parent then
			d.point:Destroy()
			table.remove(doors, i)
			continue
		end
		local tension = tensionOf(pad)
		local launching = pad:GetAttribute("Launching") == true
		local timeLeft = pad:GetAttribute("TimeLeft") or 0
		local near = (d.point.WorldPosition - camPos).Magnitude < 90
		maxTension = math.max(maxTension, launching and 1 or tension)
		queueTension = math.max(queueTension, tension)

		if launching and not d.launching and near then
			Sfx.at(d.point, "DoorOpen", { jitter = 0.05 })
			Sfx.at(d.point, "DoorWhoosh", { jitter = 0.05 })
		end
		d.launching = launching

		local rattle = d.rattle
		if rattle then
			local target = 0
			if tension > 0 and not launching and near then
				target = Config.Sounds.DoorRattle.volume * tension * (timeLeft <= 5 and 1 or 0.35)
			end
			rattle.Volume += (target - rattle.Volume) * 0.35
			rattle.PlaybackSpeed = 0.85 + tension * 0.35
		end

		if tension > 0 and not launching and near then
			if timeLeft <= 5 and now >= d.nextShake then
				d.nextShake = now + rng:NextNumber(1.2, 2.6)
				Sfx.at(d.point, "DoorShake", { jitter = 0.1, volume = Config.Sounds.DoorShake.volume * tension })
			end
			if now >= d.nextCreak then
				d.nextCreak = now + rng:NextNumber(3, 7) / (1 + tension)
				Sfx.at(d.point, "DoorCreak", { jitter = 0.15 })
			end
		end
	end
	return maxTension, queueTension
end

task.spawn(function()
	local pads = lobby:WaitForChild("Pads", 30)
	if not pads then
		return
	end
	for _, pad in pads:GetChildren() do
		addPad(pad)
	end
	pads.ChildAdded:Connect(addPad)
end)

------------------------------------------------------------------------------------------
-- Clock ticks (in step with DoorFX: tick, tick, tick, back; frantic while time runs backwards)
------------------------------------------------------------------------------------------
task.spawn(function()
	local queue = lobby:WaitForChild("Queue", 30)
	local clock = queue and queue:WaitForChild("Clock", 15)
	local face = clock and clock:WaitForChild("Face", 15)
	if face then
		addClock(face)
	end
end)

local lastSecond = math.floor(os.clock())
local nextFastTick = 0

local function tickClocks(camPos: Vector3, volume: number, speed: number)
	local range = (Config.Sounds.ClockTick.far or 40) + 5
	for i = #clocks, 1, -1 do
		local c = clocks[i]
		if not c.Parent then
			table.remove(clocks, i)
		elseif c:IsA("BasePart") and (c.Position - camPos).Magnitude <= range then
			Sfx.at(c, "ClockTick", { volume = volume, speed = speed, jitter = 0.02 })
		end
	end
end

local function updateClocks(camPos: Vector3, now: number, tension: number)
	if #clocks == 0 then
		return
	end
	local def = Config.Sounds.ClockTick
	if tension > 0 then
		-- the hands spin backwards: a quiet ratchet chatter
		if now >= nextFastTick then
			nextFastTick = now + 1 / (3 + tension * 6)
			tickClocks(camPos, def.volume * 0.6, 1.25)
		end
		lastSecond = math.floor(now)
		return
	end
	local sec = math.floor(now)
	if sec ~= lastSecond then
		lastSecond = sec
		-- every fourth second the hand slips back: a lower, duller tock
		local back = sec % 4 == 3
		tickClocks(camPos, back and def.volume * 0.8 or def.volume, back and 0.8 or 1)
	end
end

------------------------------------------------------------------------------------------
-- Paper rustles: now and then near a drifting sheet, or just somewhere close by
------------------------------------------------------------------------------------------
local nextRustle = os.clock() + rng:NextNumber(8, 20)

local function updateRustle(camPos: Vector3, now: number, room: string)
	if now < nextRustle then
		return
	end
	nextRustle = now + rng:NextNumber(14, 35)
	if room == "Workshop" then
		return
	end
	local papers = lobby:FindFirstChild("DriftingPapers")
	if papers then
		local sheets = papers:GetChildren()
		if #sheets > 0 then
			local sheet = sheets[rng:NextInteger(1, #sheets)]
			if sheet:IsA("BasePart") and (sheet.Position - camPos).Magnitude < 30 then
				Sfx.at(sheet, "PaperRustle", { jitter = 0.15 })
				return
			end
		end
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(6, 14)
	Sfx.at(camPos + Vector3.new(math.cos(angle) * dist, -3, math.sin(angle) * dist), "PaperRustle", { jitter = 0.15 })
end

------------------------------------------------------------------------------------------
-- Footsteps: swap the default Running sound for a tile footstep
------------------------------------------------------------------------------------------
local function onCharacter(character: Model)
	local def = Config.Sounds.FootstepTile
	if not def then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 15)
	local running = root and root:WaitForChild("Running", 15)
	if running and running:IsA("Sound") then
		running.SoundId = "rbxassetid://" .. def.id
		running.Volume = def.volume
	end
end

local player = Players.LocalPlayer
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

------------------------------------------------------------------------------------------
local acc = 0
local camPos = Vector3.zero
local queueTension = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	-- the clock is checked every frame so ticks land on the second hand's snap
	updateClocks(camPos, now, queueTension)
	acc += dt
	if acc < TICK then
		return
	end
	acc = 0
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camPos = camera.CFrame.Position
	currentRoom = roomAt(camPos)
	local maxTension
	maxTension, queueTension = updateDoors(camPos, now)
	updateBeds(currentRoom, maxTension)
	updateAnchors(camPos, now)
	updateRustle(camPos, now, currentRoom)
end)
