-- Client-side sound effects, all defined in Config.Sounds.
--   Sfx.play(name)            UI sounds: non-positional, played through SoundService
--   Sfx.make / at / loop      world sounds: positional, emitted from a part, attachment or point
--   Sfx.speak(voice)          one syllable of a character's dialogue voice (see Voice below)
-- World sounds are routed through two SoundGroups (Ambience, World) so they can be balanced or muted as a whole.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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

-- A character's dialogue voice: short vocal clips played one syllable at a time while their line types.
export type Voice = {
	sounds: { string }, -- Config.Sounds names, picked at random (never the same one twice running)
	every: number?, -- a syllable every N letters (plus one at the start of each word); default 3
	gap: number?, -- minimum seconds between syllables; default 0.08
	speed: number?, -- base PlaybackSpeed (pitch); default 1
	jitter: number?, -- random +/- PlaybackSpeed variation; default 0.06
	length: number?, -- seconds of clip per syllable; longer clips play a random slice, then fade
	eq: { low: number, mid: number, high: number }?, -- EqualizerSoundEffect gains in dB (negative high = muffled)
	reverb: number?, -- ReverbSoundEffect WetLevel in dB (nil = dry)
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

-- One voice channel per Voice table: its own Sound per clip (with the voice's effects), at most
-- one syllable sounding at a time - the next one fades the previous out instead of stacking on it.
type Channel = {
	sounds: { Sound },
	base: { number },
	fades: { [Sound]: Tween },
	last: number,
	current: Sound?,
	token: number,
}
local channels: { [Voice]: Channel } = {}
local VOICE_FADE = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function channelFor(voice: Voice): Channel
	local channel = channels[voice]
	if channel then
		return channel
	end
	channel = { sounds = {}, base = {}, fades = {}, last = 0, current = nil, token = 0 }
	for _, name in voice.sounds do
		local def = Config.Sounds[name]
		if def and def.id ~= 0 then
			local sound = Instance.new("Sound")
			sound.Name = "Voice_" .. name
			sound.SoundId = "rbxassetid://" .. def.id
			sound.Volume = def.volume
			if voice.eq then
				local eq = Instance.new("EqualizerSoundEffect")
				eq.LowGain = voice.eq.low
				eq.MidGain = voice.eq.mid
				eq.HighGain = voice.eq.high
				eq.Priority = 1
				eq.Parent = sound
			end
			if voice.reverb then
				local reverb = Instance.new("ReverbSoundEffect")
				reverb.DecayTime = 0.6
				reverb.Density = 1
				reverb.Diffusion = 1
				reverb.DryLevel = 0
				reverb.WetLevel = voice.reverb
				reverb.Priority = 0
				reverb.Parent = sound
			end
			sound.Parent = SoundService
			table.insert(channel.sounds, sound)
			table.insert(channel.base, def.volume)
		end
	end
	channels[voice] = channel
	return channel
end

local function fadeOut(channel: Channel, sound: Sound)
	local fade = TweenService:Create(sound, VOICE_FADE, { Volume = 0 })
	channel.fades[sound] = fade
	fade.Completed:Once(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and channel.fades[sound] == fade then
			channel.fades[sound] = nil
			sound:Stop()
		end
	end)
	fade:Play()
end

-- Play one syllable of `voice`. Pitched by voice.speed +/- jitter; clips longer than voice.length
-- play a random slice of themselves, so a few mumbled phrases make many different syllables.
function Sfx.speak(voice: Voice)
	local channel = channelFor(voice)
	local count = #channel.sounds
	if count == 0 then
		return
	end
	local i = math.random(count)
	if count > 1 and i == channel.last then
		i = i % count + 1
	end
	channel.last = i
	local sound = channel.sounds[i]
	local previous = channel.current
	if previous and previous ~= sound and previous.IsPlaying then
		fadeOut(channel, previous)
	end
	local pending = channel.fades[sound]
	if pending then
		channel.fades[sound] = nil
		pending:Cancel()
	end

	local jitter = voice.jitter or 0.06
	local speed = (voice.speed or 1) * (1 + (math.random() * 2 - 1) * jitter)
	sound.PlaybackSpeed = speed
	sound.Volume = channel.base[i]
	local length = voice.length
	local start = 0
	if length and sound.TimeLength > 0 then
		local span = length * speed -- seconds of clip heard in `length` seconds of real time
		if sound.TimeLength > span then
			start = math.random() * (sound.TimeLength - span)
		end
	end
	sound.TimePosition = start
	sound:Play()
	channel.current = sound
	channel.token += 1
	if length then
		local token = channel.token
		task.delay(length, function()
			if channel.token == token and sound.IsPlaying then
				fadeOut(channel, sound)
			end
		end)
	end
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
