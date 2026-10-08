-- Client-side sound effects. Sounds live in SoundService so they play non-positionally.
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local Sfx = {}

local sounds: { [string]: Sound } = {}

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

function Sfx.preload()
	for name in Config.Sounds do
		get(name)
	end
end

return Sfx
