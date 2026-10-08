-- Game-wide tuning. Shared by the Lobby and Trial places.
local Config = {}

-- Fill these in after publishing (Creator Dashboard). While 0, teleports and purchases are mocked.
Config.LobbyPlaceId = 0
Config.TrialPlaceId = 0
Config.ReviveGamePassId = 0

-- Currency & data
Config.CurrencyName = "Keys"
Config.StartingKeys = 50
Config.StudioTestKeys = 1000 -- granted in Studio when DataStores are unavailable, so the shop can be tested
Config.DataStoreName = "PlayerData_v1"
Config.KeysLeaderboardStore = "TopKeys_v1"
Config.TrialsLeaderboardStore = "TopTrials_v1"
Config.AutosaveInterval = 120

-- Lobby queue pads
Config.Modes = {
	Solo = { capacity = 1, color = Color3.fromRGB(176, 132, 62) },
	Duo = { capacity = 2, color = Color3.fromRGB(128, 44, 40) },
	Squad = { capacity = 4, color = Color3.fromRGB(62, 84, 110) },
}
Config.ModeOrder = { "Solo", "Duo", "Squad" }
Config.QueueCountdown = 15 -- seconds once the first player steps on a pad
Config.FullQueueCountdown = 5 -- countdown is cut to this once the pad is full
Config.LeaveCooldown = 2

-- Trials
Config.DoorPickTime = 10
Config.TrialDuration = 12 * 60 -- real trials: 10-15 min
Config.StubTrialDuration = 30 -- placeholder length until trial maps exist
Config.Rewards = {
	Blessing = 40, -- good door
	Hunt = 100, -- survived a bad door
}

-- The pool of fates behind the doors. Each trial map will register itself here later.
Config.Fates = {
	{
		id = "reading_room",
		name = "The Endless Reading Room",
		kind = "Blessing",
		blurb = "Quiet. Warm. Something left you gifts.",
	},
	{ id = "sunlit_atrium", name = "Sunlit Atrium", kind = "Blessing", blurb = "Too bright for anything to hide." },
	{
		id = "poolrooms",
		name = "The Poolrooms",
		kind = "Blessing",
		blurb = "Tiled halls of still water. Collect what floats.",
	},
	{ id = "level_zero", name = "Yellow Rooms", kind = "Hunt", blurb = "The hum is louder here. Keep moving." },
	{ id = "night_motel", name = "Vacancy", kind = "Hunt", blurb = "Every room is checked in. Not by you." },
	{
		id = "long_hall",
		name = "The Long Hallway",
		kind = "Hunt",
		blurb = "It is behind you. It is always behind you.",
	},
}

-- UI / ambience sound effects (Creator Store audio, verified to load: PreloadAsync + TimeLength > 0).
-- Every entry has `id` and `volume`. World sounds (`world = true`) also carry optional fields read by
-- Sfx.make / Sfx.at / Sfx.loop:
--   alt      extra ids picked at random for one-shots (variation)
--   looped   loop it
--   speed    base PlaybackSpeed (pitch)
--   near/far RollOffMinDistance / RollOffMaxDistance in studs (InverseTapered)
--   group    SoundGroup name ("Ambience" or "World")
-- Most world sounds are Pro Sound Effects library clips (licensed for Roblox use).
Config.Sounds = {
	Hover = { id = 119354387183704, volume = 0.25 },
	Click = { id = 87437544236708, volume = 0.45 },
	PanelOpen = { id = 95995953662374, volume = 0.5 }, -- book page turn
	PanelClose = { id = 9118835414, volume = 0.3 },
	Error = { id = 87519554692663, volume = 0.4 },
	Purchase = { id = 100813529228543, volume = 0.5 },
	Type = { id = 9120300134, volume = 0.18 }, -- typewriter key, used for the guide's dialogue
	Knock = { id = 9120918417, volume = 0.5 },

	-- Room tone beds (2D, crossfaded by AmbientSound by the room the camera is in)
	AmbLibrary = { id = 9125446564, volume = 0.16, speed = 0.9, looped = true, group = "Ambience", world = true }, -- deep AC room tone, 34.6 s
	AmbBasement = { id = 9112775414, volume = 0.22, looped = true, group = "Ambience", world = true }, -- slow rumbly pipe-interior presence, 63.7 s
	AmbWorkshop = { id = 9112825337, volume = 0.2, speed = 0.85, looped = true, group = "Ambience", world = true }, -- machine room presence, 56 s
	AmbWater = { id = 9120570661, volume = 0.12, looped = true, group = "Ambience", world = true }, -- water lap inside a cave (reverberant), 34.5 s
	DoorDrone = { id = 9112795463, volume = 0.5, looped = true, group = "Ambience", world = true }, -- hollow rumble drone, 106 s; swells with queue tension

	-- Positional loops at FX anchors
	FurnaceFire = { id = 9112780462, volume = 0.55, looped = true, near = 6, far = 55, group = "World", world = true }, -- crackly fireplace, 42.8 s
	FurnaceRoar = {
		id = 9112780561,
		volume = 0.25,
		speed = 0.7,
		looped = true,
		near = 5,
		far = 45,
		group = "World",
		world = true,
	}, -- kerosene fire whoosh, 49 s
	Boiler = {
		id = 9125674114,
		volume = 0.35,
		speed = 0.8,
		looped = true,
		near = 6,
		far = 50,
		group = "World",
		world = true,
	}, -- deep ticking bassy hum, 18.5 s
	LampHum = { id = 9112823813, volume = 0.06, looped = true, near = 2, far = 14, group = "World", world = true }, -- light bulb buzz, 49.4 s
	SteamHiss = { id = 137065982, volume = 0.18, looped = true, near = 3, far = 28, group = "World", world = true }, -- gas/steam leak loop, 12.1 s
	WaterLap = { id = 9126195224, volume = 0.14, looped = true, near = 6, far = 40, group = "World", world = true }, -- small pool lapping, 49.3 s
	DoorRattle = { id = 9118062766, volume = 0.4, looped = true, near = 5, far = 60, group = "World", world = true }, -- constant metal rattle, 5.1 s

	-- Positional one-shots
	PipeGroan = {
		id = 9116878293, -- distant metal stress booms, 2.5 s
		alt = { 9126282474, 9126282061, 9113135175 }, -- strained creaking 6.3 s / 5.1 s, building knocks 10.6 s
		volume = 0.4,
		near = 8,
		far = 90,
		group = "World",
		world = true,
	},
	Drip = {
		id = 9126181980, -- distant reverberant drop, 0.65 s
		alt = { 9120510269, 9120507347 }, -- single drip 1.1 s, drop onto metal 2.0 s
		volume = 0.35,
		near = 3,
		far = 35,
		group = "World",
		world = true,
	},
	SteamBurst = {
		id = 9116496074,
		alt = { 9116496050 },
		volume = 0.22,
		near = 4,
		far = 40,
		group = "World",
		world = true,
	}, -- air release, 5 s
	ClockTick = { id = 134410911353980, volume = 0.3, near = 4, far = 40, group = "World", world = true }, -- single tick, 0.18 s
	DoorShake = { id = 9114152831, volume = 0.5, near = 6, far = 70, group = "World", world = true }, -- hard door shakes + rattle, 4.9 s
	DoorCreak = {
		id = 9120839010,
		alt = { 9116604303 },
		volume = 0.35,
		near = 5,
		far = 50,
		group = "World",
		world = true,
	}, -- wood creak 2.0 s, metal creak 1.1 s
	DoorOpen = { id = 9114144822, volume = 0.7, speed = 0.8, near = 8, far = 90, group = "World", world = true }, -- long door squeak, 5.9 s
	DoorWhoosh = { id = 133215732722481, volume = 0.6, speed = 0.55, near = 8, far = 90, group = "World", world = true }, -- low long whoosh, 0.7 s
	PaperRustle = {
		id = 9118184352, -- paper handling 2.3 s
		alt = { 9125724963, 9117233449 }, -- slow rustle 2.1 s, rustle 2.0 s
		volume = 0.14,
		near = 3,
		far = 30,
		group = "World",
		world = true,
	},

	-- Local character footsteps on the lobby's tile floor (replaces the default Running sound; set to nil to keep it)
	FootstepTile = { id = 89709498928615, volume = 0.45, world = true }, -- marble/tile footsteps loop, 3.3 s
}

return Config
