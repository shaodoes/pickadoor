--[[
	The reading hall's reward stations, server side (all rules and tables are in Shared.Rewards):
		ClaimDaily      7-day streak calendar, one claim per UTC day
		SpinWheel       Wheel of Fate: 1 free spin per UTC day, banked extra spins, or buy one for Keys
		ClaimChallenge  pay out a completed challenge (progress is counted by Common.ChallengeService)
		Talked          a finished conversation counts towards the "talk to ..." challenges
		RewardsDebug    Studio only: shift the reward clock (workspace RewardDayOffset) / reset your rewards

	Every claim and roll happens here with os.time(); the client only animates. The chest and the wheel
	in the hall are animated on every client from attributes set here (see StationFX.client):
		Lobby.Stations.DailyStation  OpenSeq, OpenBy
		Lobby.Stations.WheelStation  SpinSeq, SpinIndex, SpinOffset, SpinStart, SpinBy
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Lanterns = require(Shared.Lanterns)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local DataService = require(ServerStorage.Common.DataService)
local ChallengeService = require(ServerStorage.Common.ChallengeService)

local RewardsService = {}

local CURRENCY = Config.CurrencyName
local rng = Random.new()
local lastSpin: { [Player]: number } = {}
local lastClaim: { [Player]: number } = {}
local stations: Instance? = nil

local function station(name: string): Instance?
	return stations and stations:FindFirstChild(name)
end

local function plural(n: number, word: string): string
	return string.format("%d %s%s", n, word, n == 1 and "" or "s")
end

-- Add `count` of a consumable, spilling anything over its cap into Keys at the shop price.
-- Returns a description of what was given. Mutates `data` directly (call inside an update or before one).
local function giveItem(data: any, id: string, count: number): string
	local def = Items.get(id)
	if not def or def.kind ~= "consumable" then
		return ""
	end
	local have = data.Inventory[id] or 0
	local fits = math.clamp(def.cap - have, 0, count)
	data.Inventory[id] = have + fits
	local spill = count - fits
	if spill > 0 then
		local keys = spill * def.price
		data.Keys += keys
		if fits == 0 then
			return string.format("%s (pockets full: +%d %s instead)", def.name, keys, CURRENCY)
		end
		return string.format("%d %s (+%d %s for the rest)", fits, def.name, keys, CURRENCY)
	end
	return if count == 1 then def.name else string.format("%d %s", count, def.name)
end

------------------------------------------------------------------------------------------
-- Daily reward
------------------------------------------------------------------------------------------
function RewardsService.claimDaily(player: Player)
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Your save isn't loaded yet." }
	end
	if os.clock() - (lastClaim[player] or 0) < 1 then
		return { ok = false, message = "One moment..." }
	end
	lastClaim[player] = os.clock()
	local today = Rewards.today()
	local state = Rewards.dailyState(data.Daily, today)
	if not state.claimable then
		return {
			ok = false,
			message = "Already opened today. Come back in "
				.. Rewards.formatDuration(Rewards.secondsToNextDay())
				.. ".",
		}
	end
	local reward = Rewards.Daily[state.day]
	local parts = { string.format("+%d %s", reward.keys, CURRENCY) }
	DataService.update(player, function(d)
		d.Keys += reward.keys
		if reward.spins then
			d.Spins.extra += reward.spins
			table.insert(parts, "+" .. plural(reward.spins, "spin"))
		end
		for id, count in reward.items or {} do
			table.insert(parts, "+" .. giveItem(d, id, count))
		end
		d.Daily.streak = state.day
		d.Daily.lastClaimDay = today
	end)
	local chest = station("DailyStation")
	if chest then
		chest:SetAttribute("OpenBy", player.UserId)
		chest:SetAttribute("OpenSeq", (chest:GetAttribute("OpenSeq") or 0) + 1)
	end
	ChallengeService.record(player, "dailyChest")
	return {
		ok = true,
		day = state.day,
		keys = reward.keys,
		spins = reward.spins,
		items = reward.items,
		message = string.format("Day %d: %s", state.day, table.concat(parts, ", ")),
	}
end

------------------------------------------------------------------------------------------
-- Wheel of Fate
------------------------------------------------------------------------------------------
-- A random lantern this player doesn't own (cheaper ones are likelier), or nil if they own them all.
local function pickLantern(data: any): string?
	local pool, total = {}, 0
	for _, def in Lanterns.List do
		if def.id ~= Lanterns.DefaultId and not data.OwnedLanterns[def.id] then
			local weight = 1 / math.max(def.price, 50)
			total += weight
			table.insert(pool, { id = def.id, weight = weight })
		end
	end
	local pick = rng:NextNumber() * total
	for _, entry in pool do
		pick -= entry.weight
		if pick <= 0 then
			return entry.id
		end
	end
	return pool[#pool] and pool[#pool].id
end

-- Apply a segment's prize to `data` (no replication). Returns the reward description for the client.
local function grantSegment(data: any, seg: Rewards.Segment)
	if seg.kind == "keys" then
		data.Keys += seg.amount
		return { kind = "keys", amount = seg.amount, text = string.format("+%d %s", seg.amount, CURRENCY) }
	elseif seg.kind == "item" then
		local text = giveItem(data, seg.item :: string, seg.amount)
		return { kind = "item", amount = seg.amount, item = seg.item, text = "+" .. text }
	elseif seg.kind == "spin" then
		data.Spins.extra += seg.amount
		return { kind = "spin", amount = seg.amount, text = "+" .. plural(seg.amount, "free spin") }
	end
	local lanternId = pickLantern(data)
	if lanternId then
		data.OwnedLanterns[lanternId] = true
		local def = Lanterns.get(lanternId)
		return {
			kind = "lantern",
			amount = 1,
			lantern = lanternId,
			text = string.format("A lantern: the %s! Equip it at the workbench.", def and def.name or lanternId),
		}
	end
	data.Keys += Rewards.LanternFallbackKeys
	return {
		kind = "keys",
		amount = Rewards.LanternFallbackKeys,
		text = string.format("+%d %s (you own every lantern)", Rewards.LanternFallbackKeys, CURRENCY),
	}
end

function RewardsService.spin(player: Player, buy: any)
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Your save isn't loaded yet." }
	end
	if os.clock() - (lastSpin[player] or 0) < Rewards.SpinDuration + 0.4 then
		return { ok = false, message = "The wheel is still turning." }
	end
	local today = Rewards.today()
	local source
	if buy == true then
		if data.Keys < Rewards.SpinCost then
			return { ok = false, message = string.format("A spin costs %d %s.", Rewards.SpinCost, CURRENCY) }
		end
		source = "buy"
	elseif Rewards.freeSpinReady(data.Spins, today) then
		source = "free"
	elseif data.Spins.extra > 0 then
		source = "extra"
	else
		return {
			ok = false,
			message = string.format(
				"No spins left. Buy one for %d %s, or come back in %s.",
				Rewards.SpinCost,
				CURRENCY,
				Rewards.formatDuration(Rewards.secondsToNextDay())
			),
		}
	end
	lastSpin[player] = os.clock()

	local index = Rewards.rollSegment(rng)
	local offset = rng:NextNumber(-0.34, 0.34) * Rewards.SegmentAngle
	local start = workspace:GetServerTimeNow() + 0.2 -- a little lead so every client starts on time

	-- pay for the spin (pushed to the client now) ...
	DataService.update(player, function(d)
		if source == "buy" then
			d.Keys -= Rewards.SpinCost
		elseif source == "free" then
			d.Spins.lastFreeDay = today
		else
			d.Spins.extra -= 1
		end
		d.Spins.total += 1
	end)
	ChallengeService.record(player, "spin")
	-- ... but the prize goes into the save silently and only reaches the client once the wheel has landed,
	-- so the Keys counter doesn't give the result away (it's already in the profile if they leave mid-spin).
	local reward = grantSegment(data, Rewards.Wheel[index])
	task.delay(start - workspace:GetServerTimeNow() + Rewards.SpinDuration, function()
		if player.Parent then
			DataService.update(player, function() end)
		end
	end)

	local wheel = station("WheelStation")
	if wheel then
		wheel:SetAttribute("SpinIndex", index)
		wheel:SetAttribute("SpinOffset", offset)
		wheel:SetAttribute("SpinStart", start)
		wheel:SetAttribute("SpinBy", player.UserId)
		wheel:SetAttribute("SpinSeq", (wheel:GetAttribute("SpinSeq") or 0) + 1)
	end
	return {
		ok = true,
		source = source,
		index = index,
		offset = offset,
		start = start,
		duration = Rewards.SpinDuration,
		reward = reward,
		message = reward.text,
	}
end

------------------------------------------------------------------------------------------
-- Talking to the lobby's characters (counts for the "talk to" challenges)
------------------------------------------------------------------------------------------
local TALK_STATS = { Teeth = "talkTeeth", Librarian = "talkLibrarian", Archivist = "talkArchivist" }
local lastTalk: { [Player]: number } = {}

local function talked(player: Player, who: any)
	local stat = type(who) == "string" and TALK_STATS[who]
	if not stat or os.clock() - (lastTalk[player] or 0) < 2 then
		return
	end
	lastTalk[player] = os.clock()
	ChallengeService.record(player, stat)
end

------------------------------------------------------------------------------------------
-- Studio debug: move the reward clock / reset your own rewards
------------------------------------------------------------------------------------------
local function refreshAll()
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			DataService.update(player, function() end) -- replicate() re-draws challenges for the new day
		end
	end
end

local function debugAction(player: Player, action: any)
	if not RunService:IsStudio() then
		return
	end
	local offset = tonumber(workspace:GetAttribute("RewardDayOffset")) or 0
	if action == "nextDay" then
		workspace:SetAttribute("RewardDayOffset", offset + 1)
	elseif action == "skipDay" then
		workspace:SetAttribute("RewardDayOffset", offset + 2) -- misses a day: the streak breaks
	elseif action == "resetDay" then
		workspace:SetAttribute("RewardDayOffset", 0)
	elseif action == "resetAll" then
		DataService.update(player, function(d)
			d.Daily = { streak = 0, lastClaimDay = -1 }
			d.Spins = { lastFreeDay = -1, extra = 0, total = 0 }
			d.Challenges = { day = -1, week = -1, daily = {}, weekly = {} }
		end)
	else
		return
	end
	Remotes.get("Notify"):FireClient(
		player,
		string.format("(Studio) Reward clock: day offset %d.", tonumber(workspace:GetAttribute("RewardDayOffset")) or 0)
	)
	refreshAll()
end

------------------------------------------------------------------------------------------
function RewardsService.start(lobby: Instance)
	stations = lobby:FindFirstChild("Stations")
	if not stations then
		task.spawn(function()
			stations = lobby:WaitForChild("Stations", 30)
		end)
	end
	if RunService:IsStudio() and workspace:GetAttribute("RewardDayOffset") == nil then
		workspace:SetAttribute("RewardDayOffset", 0)
	end

	Remotes.get("ClaimDaily").OnServerInvoke = RewardsService.claimDaily
	Remotes.get("SpinWheel").OnServerInvoke = RewardsService.spin
	Remotes.get("ClaimChallenge").OnServerInvoke = ChallengeService.claim
	Remotes.get("Talked").OnServerEvent:Connect(talked)
	Remotes.get("RewardsDebug").OnServerEvent:Connect(debugAction)

	Players.PlayerRemoving:Connect(function(player)
		lastSpin[player] = nil
		lastClaim[player] = nil
		lastTalk[player] = nil
	end)

	-- when the UTC day (or week) turns over, push fresh challenges + badges to everyone
	task.spawn(function()
		local day, week = Rewards.today(), Rewards.thisWeek()
		while true do
			task.wait(5)
			local nowDay, nowWeek = Rewards.today(), Rewards.thisWeek()
			if nowDay ~= day or nowWeek ~= week then
				day, week = nowDay, nowWeek
				refreshAll()
			end
		end
	end)
end

return RewardsService
