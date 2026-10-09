--[[
	Challenge progress, shared by both places (the lobby and the trial use the same DataService).

	ChallengeService.record(player, stat, amount?)
		Count `amount` (default 1) towards every unclaimed daily/weekly challenge on `stat` (stat names
		are listed in Shared.Rewards). Toasts when one completes. Safe to call from anywhere on the
		server; does nothing for players without a loaded profile.

	ChallengeService.claim(player, scope, slot) -> { ok, message }
		Pays out a completed challenge (Keys, and extra Wheel of Fate spins for some weeklies).

	ChallengeService.Completed: (player, def) fires when a challenge reaches its target.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local DataService = require(script.Parent.DataService)

local ChallengeService = {}

local completedEvent = Instance.new("BindableEvent")
ChallengeService.Completed = completedEvent.Event

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text, "success")
end

function ChallengeService.record(player: Player, stat: string, amount: number?)
	local add = math.max(0, math.floor(amount or 1))
	if add == 0 or not DataService.get(player) then
		return
	end
	local finished = {}
	local touched = false
	DataService.update(player, function(data)
		Rewards.rollover(data, player.UserId)
		for _, set in { data.Challenges.daily, data.Challenges.weekly } do
			for _, slot in set do
				local def = Rewards.challenge(slot.id)
				if def and def.stat == stat and not slot.claimed and slot.progress < def.target then
					slot.progress = math.min(def.target, slot.progress + add)
					touched = true
					if slot.progress >= def.target then
						table.insert(finished, def)
					end
				end
			end
		end
	end)
	if not touched then
		return
	end
	for _, def in finished do
		completedEvent:Fire(player, def)
		notify(player, string.format("Challenge complete: %s. Claim it from %s.", def.text, Rewards.ArchivistName))
	end
end

function ChallengeService.claim(player: Player, scope: any, slotIndex: any)
	if (scope ~= "daily" and scope ~= "weekly") or type(slotIndex) ~= "number" then
		return { ok = false, message = "That isn't in the ledger." }
	end
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Your ledger isn't loaded yet." }
	end
	Rewards.rollover(data, player.UserId)
	local slot = data.Challenges[scope][math.floor(slotIndex)]
	local def = slot and Rewards.challenge(slot.id)
	if not slot or not def then
		return { ok = false, message = "That page has turned. Have another look." }
	end
	if slot.claimed then
		return { ok = false, message = "Already paid out." }
	end
	if slot.progress < def.target then
		return { ok = false, message = string.format("Not yet: %d / %d.", slot.progress, def.target) }
	end
	DataService.update(player, function(d)
		slot.claimed = true
		d.Keys += def.keys
		if def.spins then
			d.Spins.extra += def.spins
		end
	end)
	local parts = { string.format("+%d %s", def.keys, Config.CurrencyName) }
	if def.spins then
		table.insert(parts, string.format("+%d spin%s", def.spins, def.spins == 1 and "" or "s"))
	end
	return { ok = true, message = string.format("%s: %s", def.text, table.concat(parts, ", ")) }
end

return ChallengeService
