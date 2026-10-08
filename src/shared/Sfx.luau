-- Client-side sound effects, all defined in Config.Sounds.
--   Sfx.play(name)            UI sounds: non-positional, played through SoundService
--   Sfx.make / at / loop      world sounds: positional, emitted from a part, attachment or point
-- World sounds are routed through two SoundGroups (Ambience, World) so they can be balanced or muted as a whole.
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local Sfx = {}

export type SoundOpts = {
	volume: number?, -- overrides the Config volume
	speed: number?, -- overrides the Config PlaybackSpeed
	jitter: number?, -- random +/- PlaybackSpeed variation (one-shots default to 0.06)
	near: number?, -- RollOffMinDistance
	far: number?, -- RollOffMaxDistance
	looped: boolean?,
	id: number?, -- play this specific id instead of the entry's (or a random alt)
}

local sounds: { [string]: Sound } = {}
local groups: { [string]: SoundGroup } = {}

local function get(name: string): Sound?
	local def = Config.Sounds[name]
	if not def then
		return nil
	end
	local sound = sounds[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Sfx_" .. name
		sound.SoundId = "rbxassetid://" .. def.id
		sound.Volume = def.volume
		sound.Parent = SoundService
		sounds[name] = sound
	end
	return sound
end

-- Play a named effect. A little pitch variation keeps repeated clicks from sounding robotic.
function Sfx.play(name: string, pitchJitter: number?)
	local sound = get(name)
	if not sound then
		return
	end
	local jitter = pitchJitter or 0.06
	sound.PlaybackSpeed = 1 + (math.random() * 2 - 1) * jitter
	SoundService:PlayLocalSound(sound)
end

-- Preload the UI sounds (world sounds load when the lobby creates them).
function Sfx.preload()
	for name, def in Config.Sounds do
		if not def.world then
			get(name)
		end
	end
end

-- A SoundGroup under SoundService, created on first use.
function Sfx.group(name: string): SoundGroup
	local group = groups[name]
	if not group then
		group = SoundService:FindFirstChild(name) :: SoundGroup?
		if not group or not group:IsA("SoundGroup") then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Volume = 1
			group.Parent = SoundService
		end
		groups[name] = group
	end
	return group :: SoundGroup
end

-- Pick an id for a one-shot: the main id or one of its alternates.
local function pickId(def): number
	local alt = def.alt
	if alt and #alt > 0 then
		local i = math.random(#alt + 1)
		return i == 1 and def.id or alt[i - 1]
	end
	return def.id
end

-- Build (but don't play) a Sound from a Config entry under `parent`. Positional when parent is a
-- BasePart or Attachment; 2D when parented to SoundService etc. Returns nil for unknown names.
function Sfx.make(parent: Instance, name: string, opts: SoundOpts?): Sound?
	local def = Config.Sounds[name]
	if not def then
		return nil
	end
	local o: SoundOpts = opts or {}
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. (o.id or def.id)
	sound.Volume = o.volume or def.volume
	sound.PlaybackSpeed = o.speed or def.speed or 1
	sound.Looped = if o.looped ~= nil then o.looped else (def.looped == true)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = o.near or def.near or 6
	sound.RollOffMaxDistance = o.far or def.far or 60
	if def.group then
		sound.SoundGroup = Sfx.group(def.group)
	end
	sound.Parent = parent
	return sound
end

-- A tiny pool of Terrain attachments so one-shots can be played at an arbitrary point.
local pointPool: { Attachment } = {}
local function borrowPoint(position: Vector3): Attachment
	local a = table.remove(pointPool)
	if not a then
		a = Instance.new("Attachment")
		a.Name = "SfxPoint"
	end
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	return a
end

-- Fire-and-forget positional one-shot at a part, attachment or world point. Random alternate id and
-- pitch jitter for variety; the Sound cleans itself up when it ends.
function Sfx.at(target: Instance | Vector3, name: string, opts: SoundOpts?): Sound?
	local def = Config.Sounds[name]
	if not def then
		return nil
	end
	local o: SoundOpts = opts or {}
	local point: Attachment? = nil
	local parent: Instance
	if typeof(target) == "Vector3" then
		point = borrowPoint(target)
		parent = point :: Attachment
	else
		parent = target :: Instance
	end
	local sound = Sfx.make(parent, name, {
		volume = o.volume,
		speed = o.speed,
		near = o.near,
		far = o.far,
		looped = false,
		id = o.id or pickId(def),
	}) :: Sound
	local jitter = o.jitter or 0.06
	sound.PlaybackSpeed *= 1 + (math.random() * 2 - 1) * jitter
	local done = false
	local function cleanup()
		if done then
			return
		end
		done = true
		sound:Destroy()
		if point then
			point.Parent = nil
			table.insert(pointPool, point)
		end
	end
	sound.Ended:Once(cleanup)
	task.delay(20, cleanup) -- in case it never loads or never ends (one-shots are all short)
	sound:Play()
	return sound
end

-- Start a looping positional sound on `parent` (e.g. an FX anchor). Starts at a random offset so
-- identical loops in the same room don't phase together. Destroy it (or its parent) to stop.
function Sfx.loop(parent: Instance, name: string, opts: SoundOpts?): Sound?
	local sound = Sfx.make(parent, name, opts)
	if not sound then
		return nil
	end
	sound.Looped = true
	sound:Play()
	task.spawn(function()
		-- TimeLength is 0 until the asset has loaded
		if not sound.IsLoaded then
			sound.Loaded:Wait()
		end
		if sound.Parent and sound.TimeLength > 0 then
			sound.TimePosition = math.random() * sound.TimeLength
		end
	end)
	return sound
end

return Sfx
