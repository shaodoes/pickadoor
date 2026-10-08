-- Player save data (Keys, lanterns, stats). Used by both places.
-- If DataStores are unavailable (e.g. Studio without API access) the player gets an in-memory
-- profile that is never written back, so test sessions can't clobber real saves.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lanterns = require(Shared.Lanterns)
local Remotes = require(Shared.Remotes)

local DataService = {}

type Profile = { data: { [string]: any }, canSave: boolean, released: boolean }
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
	}
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
	}
end

local function replicate(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
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

	profiles[player] = { data = reconcile(data), canSave = canSave, released = false }
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
