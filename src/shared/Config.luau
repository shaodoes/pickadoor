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
-- [trial config] door-room flow tuning (safe side / threat side durations etc.)
Config.DoorRoomFlow = {
	pickTime = Config.DoorPickTime, -- PICK A DOOR countdown; each player's door is the Zone they stand in at zero
	revealTime = 4, -- doors swing open, "THE RIGHT DOOR WAS ..." before the round starts
	roundLength = 60, -- stub; real trials run 10-15 min (Config.TrialDuration) once the maps exist
	rewardTime = 4, -- the tally on screen before the return countdown
	returnTime = 5,
}
-- The Follower (threat corridor stalker): see src/trial/server/Stalker.luau
Config.Stalker = {
	walkSpeed = 11,
	aggroRange = 60, -- studs; it idles at the far end until someone comes this close
	damage = 34, -- per touch: three touches and you're done
	hitCooldown = 1.5, -- seconds per player between touches
	hitRange = 3, -- a pass this close counts as a touch (Touched misses at walking speed)
	retarget = 0.5, -- seconds between target updates
}

-- [items config] item tuning that isn't per-item (battery recharge rates etc.)
Config.Items = {
	LaserBatteryMax = 100,
	LaserDrainSeconds = 12, -- a full battery lasts this long of continuous firing
	LaserRechargeSeconds = 90, -- empty -> full while idle in the lobby (the trial passes recharge = false)
	LaserRange = 80, -- studs
	LaserAimCone = 60, -- degrees off the lens forward / the character's facing that the aim may deviate
	LaserStunHold = 0.5, -- seconds of continuous beam on an Entity before it is stunned
	LaserStunDuration = 4,
	LockHoldSeconds = 2.5, -- ProximityPrompt hold to pick a lock
	LockRelockSeconds = 20, -- a picked chest closes and locks again after this long
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

	-- [music] lobby music loop + the shop's darker drone (ids are meant to be swapped freely)
	-- "Remembering You (c)" by Laura Rossi (APM Music / KPM, Creator Store): sparse, melancholic solo piano, 131 s.
	-- Replace `id` with any other track; AmbientSound ducks it per room (quietest inside the shop).
	LobbyMusic = { id = 9043586747, volume = 0.2, looped = true, group = "Music", world = true },
	-- Pro Sound Effects "Eerie Tone, Metallic Swirling Tone, Tubular" 83.7 s: hangs around the shopkeeper
	ShopDrone = {
		id = 9114228148,
		volume = 0.4,
		speed = 0.9,
		looped = true,
		near = 7,
		far = 34,
		group = "Ambience",
		world = true,
	},
	-- [items] item use / laser / lockpick sounds
	PillSwallow = {
		id = 102367379211988,
		alt = { 133988388434763 },
		volume = 0.6,
		near = 4,
		far = 30,
		group = "World",
		world = true,
	}, -- gulp 0.9 s / 1.2 s
	BandageWrap = {
		id = 131079594340516,
		alt = { 9120205039 },
		volume = 0.5,
		near = 4,
		far = 30,
		group = "World",
		world = true,
	}, -- bandage wrapping 2.5 s, towel/cloth rustle 3.9 s
	LockpickClick = {
		id = 9116784575,
		volume = 0.45,
		speed = 0.9,
		looped = true,
		near = 3,
		far = 25,
		group = "World",
		world = true,
	}, -- small ratchet clicks, 5.4 s
	LockOpen = {
		id = 9117185722,
		alt = { 9117185720 },
		volume = 0.6,
		near = 5,
		far = 40,
		group = "World",
		world = true,
	}, -- padlock opens 1.7 s / 3.2 s
	LaserHum = {
		id = 9119806465,
		volume = 0.28,
		speed = 1.6,
		looped = true,
		near = 4,
		far = 35,
		group = "World",
		world = true,
	}, -- buzzy phasey synth drone pitched up, 36 s
	LaserHiss = {
		id = 9114277757,
		alt = { 9114277402, 9114277338 },
		volume = 0.5,
		near = 5,
		far = 45,
		group = "World",
		world = true,
	}, -- electric zaps 1.0 s / 2.1 s / 2.0 s
	Stun = {
		id = 18939003571,
		alt = { 139239108826837 },
		volume = 0.5,
		near = 6,
		far = 60,
		group = "World",
		world = true,
	}, -- short ear ringing 2.8 s / 3.4 s
	-- [shopkeeper] the shopkeeper's hiss and tics
	ShopkeeperHiss = {
		id = 9113991846, -- creature snarl / hiss exhale, 2.5 s
		alt = { 9113989919, 9125475724 }, -- hiss exhale 1.1 s, growl-hiss-snarl 2.3 s
		volume = 0.55,
		near = 6,
		far = 40,
		group = "World",
		world = true,
	},
	ShopkeeperTic = { -- the grin tic: a quiet wet click of the tongue / teeth
		id = 9126135650, -- tongue click with saliva, 0.5 s
		alt = { 9126163553, 9126135424 }, -- throat suction with lip plop 0.4 s, tongue click 0.6 s
		volume = 0.25,
		near = 4,
		far = 24,
		group = "World",
		world = true,
	},
	-- [lantern] lantern equip / flame sounds
	LanternEquip = {
		id = 103911273184692, -- fire ignite, 1.9 s
		alt = { 7278182233 }, -- fire ignite (second take), 2.0 s
		volume = 0.4,
		near = 3,
		far = 30,
		group = "World",
		world = true,
	},
	LanternFlame = {
		id = 9112780438,
		volume = 0.07,
		speed = 1.15,
		looped = true,
		near = 3,
		far = 14,
		group = "World",
		world = true,
	}, -- fireplace crackle loop pitched up to a small flame, 36 s
	-- [trial] door room: chime, countdown ticks, voice line hook
	PickChime = { id = 9114352428, volume = 0.6 }, -- evil church bell, twisted and slowed, 8.2 s: the doors are ready
	PickTick = { id = 9120917861, volume = 0.5 }, -- soft temple-block clunk, 0.5 s: one per second of the countdown
	PickTickHot = { id = 9119976314, volume = 0.65 }, -- dull clunky block strike, 0.75 s: the last three seconds (played lower)
	-- voice line "PICK A DOOR" (asset id supplied by the user; 0 = not set, the chime + text stand in)
	PickADoorVoice = { id = 0, volume = 1 },
	StalkerHit = {
		id = 9113525391, -- body slam against a car door, 1.55 s
		alt = { 9113525643 },
		volume = 0.8,
		speed = 0.8,
		near = 6,
		far = 70,
		group = "World",
		world = true,
	},
	DoorSwing = {
		id = 9120839552, -- long wooden door creak + squeak, 4.2 s: the leaves swinging open
		alt = { 9114135682 }, -- door creak open and close, 2.3 s
		volume = 0.7,
		speed = 0.85,
		near = 8,
		far = 90,
		group = "World",
		world = true,
	},
}

return Config
