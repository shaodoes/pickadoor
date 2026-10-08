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

return Config
