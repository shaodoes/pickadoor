-- Fills the Hall of Records board on the mezzanine from the OrderedDataStores DataService writes.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local LeaderboardService = {}

local REFRESH_SECONDS = 60
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	if not nameCache[userId] then
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		nameCache[userId] = ok and name or ("#" .. userId)
	end
	return nameCache[userId]
end

local function fill(column: Instance, entries: { { key: string, value: number } }?, fallback: string?)
	for row = 1, 10 do
		local label = column:FindFirstChild("Row" .. row)
		if label then
			local entry = entries and entries[row]
			if entry then
				label.Text = string.format("%d.  %s  -  %d", row, nameFor(tonumber(entry.key) or 0), entry.value)
			elseif row == 1 and fallback then
				label.Text = fallback
			else
				label.Text = string.format("%d.  ---", row)
			end
		end
	end
end

local function fetchTop(storeName: string)
	local ok, entries = pcall(function()
		local store = DataStoreService:GetOrderedDataStore(storeName)
		return store:GetSortedAsync(false, 10):GetCurrentPage()
	end)
	return ok and entries or nil
end

function LeaderboardService.start(lobby: Instance)
	local gui = lobby:WaitForChild("Leaderboard"):WaitForChild("Board"):WaitForChild("SurfaceGui")
	task.spawn(function()
		while true do
			local keys = fetchTop(Config.KeysLeaderboardStore)
			local trials = fetchTop(Config.TrialsLeaderboardStore)
			local fallback = (keys == nil) and "Records unavailable (enable Studio API access)" or nil
			fill(gui.Keys, keys, fallback)
			fill(gui.Trials, trials, fallback)
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
