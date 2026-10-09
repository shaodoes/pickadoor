-- Player save data (Keys, lanterns, stats). Used by both places.
-- If DataStores are unavailable (e.g. Studio without API access) the player gets an in-memory
-- profile that is never written back, so test sessions can't clobber real saves.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Lanterns = require(Shared.Lanterns)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local Titles = require(Shared.Titles)

local DataService = {}

-- lastKeys: the Keys balance at the previous push, so increases can be added to Stats.keysEarned
type Profile = { data: { [string]: any }, canSave: boolean, released: boolean, lastKeys: number }
local profiles: { [Player]: Profile } = {}

local changedEvent = Instance.new("BindableEvent")
DataService.Changed = changedEvent.Event -- (player, data)

local store, keysBoard, trialsBoard
local storesOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
	keysBoard = DataStoreService:GetOrderedDataStore(Config.KeysLeaderboardStore)
	trialsBoard = DataStoreService:GetOrderedDataStore(Config.TrialsLeaderboardStore)
end)

local function defaults()
	return {
		Keys = Config.StartingKeys,
		OwnedLanterns = { [Lanterns.DefaultId] = true },
		EquippedLantern = Lanterns.DefaultId,
		TrialsPlayed = 0,
		TrialsSurvived = 0,
		SeenGuide = false,
		-- items (see Shared.Items): consumable counts, the laser unlock + its battery, chests already looted
		Inventory = {},
		LaserUnlocked = false,
		LaserBattery = Config.Items.LaserBatteryMax,
		OpenedLocks = {},
		-- rewards (see Shared.Rewards): daily streak, wheel spins, the challenge ledger
		Daily = { streak = 0, lastClaimDay = -1 },
		Spins = { lastFreeDay = -1, extra = 0, total = 0 },
		Challenges = { day = -1, week = -1, daily = {}, weekly = {} },
		-- titles + nameplate (see Shared.Titles): lifetime stat counters (challenge stat names plus
		-- huntStreak / bestHuntStreak / keysEarned), character deaths, earned titles, the one shown
		Stats = {},
		Deaths = 0,
		Titles = { [Titles.DefaultId] = true },
		EquippedTitle = Titles.DefaultId,
	}
end

-- Clean up a rewards sub-table from an old or damaged save: keep known numeric fields, default the rest.
local function numbers(value: any, template: { [string]: number })
	local out = {}
	for key, default in template do
		local n = type(value) == "table" and tonumber(value[key]) or nil
		out[key] = if n and n == n then math.floor(n) else default
	end
	return out
end

local function slots(list: any)
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, slot in list do
		if type(slot) == "table" and Rewards.challenge(slot.id) then
			table.insert(out, {
				id = slot.id,
				progress = math.max(0, math.floor(tonumber(slot.progress) or 0)),
				claimed = slot.claimed == true,
			})
		end
	end
	return out
end

local function reconcile(data)
	for key, value in defaults() do
		if data[key] == nil then
			data[key] = value
		end
	end
	data.OwnedLanterns[Lanterns.DefaultId] = true
	if not data.OwnedLanterns[data.EquippedLantern] then
		data.EquippedLantern = Lanterns.DefaultId
	end
	-- every consumable has a count (0 when missing), clamped to its cap; unknown ids are dropped
	local inventory = {}
	for _, def in Items.List do
		if def.kind == "consumable" then
			local count = tonumber(data.Inventory[def.id]) or 0
			inventory[def.id] = math.clamp(math.floor(count), 0, def.cap)
		end
	end
	data.Inventory = inventory
	data.LaserUnlocked = data.LaserUnlocked == true
	data.LaserBattery = math.clamp(tonumber(data.LaserBattery) or 0, 0, Config.Items.LaserBatteryMax)
	if typeof(data.OpenedLocks) ~= "table" then
		data.OpenedLocks = {}
	end
	data.Daily = numbers(data.Daily, { streak = 0, lastClaimDay = -1 })
	data.Daily.streak = math.clamp(data.Daily.streak, 0, #Rewards.Daily)
	data.Spins = numbers(data.Spins, { lastFreeDay = -1, extra = 0, total = 0 })
	data.Spins.extra = math.clamp(data.Spins.extra, 0, 99)
	local ch = type(data.Challenges) == "table" and data.Challenges or {}
	data.Challenges = {
		day = math.floor(tonumber(ch.day) or -1),
		week = math.floor(tonumber(ch.week) or -1),
		daily = slots(ch.daily),
		weekly = slots(ch.weekly),
	}
	-- lifetime stats: any string key with a whole, non-negative count
	local stats = {}
	if type(data.Stats) == "table" then
		for key, value in data.Stats do
			local n = tonumber(value)
			if type(key) == "string" and n and n == n then
				stats[key] = math.max(0, math.floor(n))
			end
		end
	end
	-- saves from before lifetime stats existed: seed the trial count from TrialsPlayed
	if stats.trials == nil then
		stats.trials = math.max(0, math.floor(tonumber(data.TrialsPlayed) or 0))
	end
	data.Stats = stats
	local deaths = tonumber(data.Deaths)
	data.Deaths = if deaths and deaths == deaths then math.max(0, math.floor(deaths)) else 0
	local titles = { [Titles.DefaultId] = true }
	if type(data.Titles) == "table" then
		for id, owned in data.Titles do
			if owned == true and Titles.get(id) then
				titles[id] = true
			end
		end
	end
	data.Titles = titles
	if not titles[data.EquippedTitle] then
		data.EquippedTitle = Titles.DefaultId
	end
	return data
end

local function retry(label: string, fn: () -> any): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		task.wait(attempt)
	end
	return false, nil
end

local function storageKey(player: Player)
	return "u_" .. player.UserId
end

local function cloneSlots(list)
	local out = {}
	for i, slot in list do
		out[i] = table.clone(slot)
	end
	return out
end

function DataService.snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local d = profile.data
	return {
		Keys = d.Keys,
		OwnedLanterns = table.clone(d.OwnedLanterns),
		EquippedLantern = d.EquippedLantern,
		TrialsPlayed = d.TrialsPlayed,
		TrialsSurvived = d.TrialsSurvived,
		SeenGuide = d.SeenGuide,
		Inventory = table.clone(d.Inventory),
		LaserUnlocked = d.LaserUnlocked,
		LaserBattery = d.LaserBattery,
		OpenedLocks = table.clone(d.OpenedLocks),
		Daily = table.clone(d.Daily),
		Spins = table.clone(d.Spins),
		Challenges = {
			day = d.Challenges.day,
			week = d.Challenges.week,
			daily = cloneSlots(d.Challenges.daily),
			weekly = cloneSlots(d.Challenges.weekly),
		},
		Stats = table.clone(d.Stats),
		Deaths = d.Deaths,
		Titles = table.clone(d.Titles),
		EquippedTitle = d.EquippedTitle,
	}
end

local function replicate(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	-- challenges re-draw when the UTC day / week turns over (every push keeps them current)
	Rewards.rollover(profile.data, player.UserId)
	-- lifetime Keys earned (the "Hoarder" title): count every rise in the balance since the last push
	local gained = profile.data.Keys - profile.lastKeys
	if gained > 0 then
		profile.data.Stats.keysEarned = (profile.data.Stats.keysEarned or 0) + gained
	end
	profile.lastKeys = profile.data.Keys
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		stats[Config.CurrencyName].Value = profile.data.Keys
		stats.Trials.Value = profile.data.TrialsSurvived
	end
	Remotes.get("DataUpdated"):FireClient(player, DataService.snapshot(player))
	changedEvent:Fire(player, profile.data)
end

local function load(player: Player)
	local data, canSave = nil, false
	if storesOk then
		local ok, result = retry("Load " .. player.Name, function()
			return store:GetAsync(storageKey(player))
		end)
		if ok then
			data, canSave = result or defaults(), true
		end
	end
	if not data then
		data = defaults()
		if RunService:IsStudio() then
			data.Keys = Config.StudioTestKeys
			warn("[DataService] DataStores unavailable; using a temporary Studio profile (not saved).")
		else
			Remotes.get("Notify")
				:FireClient(player, "Your save couldn't be loaded. Progress this session won't be saved.")
		end
	end
	if not player.Parent then
		return
	end

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local keys = Instance.new("IntValue")
	keys.Name = Config.CurrencyName
	keys.Parent = stats
	local trials = Instance.new("IntValue")
	trials.Name = "Trials"
	trials.Parent = stats
	stats.Parent = player

	data = reconcile(data)
	profiles[player] = { data = data, canSave = canSave, released = false, lastKeys = data.Keys }
	replicate(player)
end

function DataService.save(player: Player)
	local profile = profiles[player]
	if not profile or not profile.canSave or profile.released then
		return
	end
	local data = profile.data
	retry("Save " .. player.Name, function()
		store:UpdateAsync(storageKey(player), function()
			return data
		end)
	end)
	pcall(function()
		keysBoard:SetAsync(tostring(player.UserId), data.Keys)
		trialsBoard:SetAsync(tostring(player.UserId), data.TrialsSurvived)
	end)
end

-- Save now and stop writing for this player (they are teleporting to another place that will own the data).
function DataService.saveForTeleport(player: Player)
	DataService.save(player)
	local profile = profiles[player]
	if profile then
		profile.released = true
	end
end

function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.data
end

function DataService.waitFor(player: Player)
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return DataService.get(player)
end

-- Mutate a player's data and push the change to their client.
function DataService.update(player: Player, mutator: (data: any) -> ())
	local profile = profiles[player]
	if not profile then
		return false
	end
	mutator(profile.data)
	replicate(player)
	return true
end

function DataService.addKeys(player: Player, amount: number)
	return DataService.update(player, function(data)
		data.Keys += amount
	end)
end

function DataService.isReady(): boolean
	return storesOk
end

function DataService.start()
	Remotes.get("GetData").OnServerInvoke = function(player)
		DataService.waitFor(player)
		return DataService.snapshot(player)
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

return DataService
