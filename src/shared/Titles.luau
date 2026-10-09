--[[
	Title catalogue: the line under a player's name on their overhead nameplate.

	Titles are earned from achievements (the server is the only authority: Common.TitleService
	checks them every time a profile changes) and the player picks which earned one is shown
	(EquipTitle remote, lobby TITLES panel). Both sides use this module: the server to unlock, the
	client to draw the TITLES panel with progress and hints.

	Each entry:
		id      stable save key (never rename)
		text    what the nameplate says
		rarity  one of Lanterns.Rarities; colours the round badge (Titles.color)
		icon    UIKit.icon glyph drawn inside the badge
		hint    how to earn it (shown on locked rows)
		stat    what is counted (see Titles.progress); target = how many

	Stats counted (profile.Stats, lifetime; filled by ChallengeService.record and DataService):
		every challenge stat in Shared.Rewards (trials, rightDoor, huntSurvived, lockpick, laserStun,
		spin, talkTeeth, ...), plus
		bestHuntStreak  most Hunts survived in a row without dying (huntStreak is the current run)
		keysEarned      lifetime Keys gained (spending doesn't take it back)
	Special stats handled here: "dailyStreak" (Daily.streak), "lanterns" (owned lanterns, target =
	the whole catalogue), "deaths" (profile.Deaths), "default" (everyone has it).
]]
local Shared = script.Parent
local Lanterns = require(Shared.Lanterns)

local Titles = {}

Titles.DefaultId = "welcome"

export type Title = {
	id: string,
	text: string,
	rarity: string,
	icon: string,
	hint: string,
	stat: string,
	target: number,
}

Titles.List = {
	{
		id = "welcome",
		text = "Welcome",
		rarity = "Common",
		icon = "door",
		hint = "Everyone starts here.",
		stat = "default",
		target = 0,
	},
	{
		id = "first_door",
		text = "First Door",
		rarity = "Common",
		icon = "door",
		hint = "Finish your first trial.",
		stat = "trials",
		target = 1,
	},
	{
		id = "survivor",
		text = "Survivor",
		rarity = "Uncommon",
		icon = "heart",
		hint = "Survive a Hunt.",
		stat = "huntSurvived",
		target = 1,
	},
	{
		id = "lucky",
		text = "Lucky",
		rarity = "Uncommon",
		icon = "check",
		hint = "Pick the right door 5 times.",
		stat = "rightDoor",
		target = 5,
	},
	{
		id = "locksmith",
		text = "Locksmith",
		rarity = "Uncommon",
		icon = "lockpick",
		hint = "Pick 5 locks.",
		stat = "lockpick",
		target = 5,
	},
	{
		id = "doomed",
		text = "Doomed",
		rarity = "Uncommon",
		icon = "skull",
		hint = "Die 25 times. It happens.",
		stat = "deaths",
		target = 25,
	},
	{
		id = "night_owl",
		text = "Night Owl",
		rarity = "Rare",
		icon = "moon",
		hint = "Claim the daily chest 7 days in a row.",
		stat = "dailyStreak",
		target = 7,
	},
	{
		id = "blinder",
		text = "Blinder",
		rarity = "Rare",
		icon = "laser",
		hint = "Stun 10 entities with the laser.",
		stat = "laserStun",
		target = 10,
	},
	{
		id = "teeths_favourite",
		text = "Teeth's Favourite",
		rarity = "Rare",
		icon = "eye",
		hint = "Talk to Teeth 10 times.",
		stat = "talkTeeth",
		target = 10,
	},
	{
		id = "wheel_spinner",
		text = "Wheel Spinner",
		rarity = "Rare",
		icon = "wheel",
		hint = "Spin the Wheel of Fate 50 times.",
		stat = "spin",
		target = 50,
	},
	{
		id = "regular",
		text = "Regular",
		rarity = "Epic",
		icon = "door",
		hint = "Finish 25 trials.",
		stat = "trials",
		target = 25,
	},
	{
		id = "collector",
		text = "Collector",
		rarity = "Epic",
		icon = "lantern",
		hint = "Own every lantern.",
		stat = "lanterns",
		target = 0, -- the whole catalogue (see Titles.progress)
	},
	{
		id = "hoarder",
		text = "Hoarder",
		rarity = "Epic",
		icon = "key",
		hint = "Earn 10,000 Keys in total.",
		stat = "keysEarned",
		target = 10000,
	},
	{
		id = "unkillable",
		text = "Unkillable",
		rarity = "Legendary",
		icon = "skull",
		hint = "Survive 5 Hunts in a row without dying.",
		stat = "bestHuntStreak",
		target = 5,
	},
	{
		id = "door_warden",
		text = "Door Warden",
		rarity = "Legendary",
		icon = "medal",
		hint = "Finish 100 trials.",
		stat = "trials",
		target = 100,
	},
} :: { Title }

local byId: { [string]: Title } = {}
for _, def in Titles.List do
	assert(not byId[def.id], "duplicate title id " .. def.id)
	byId[def.id] = def
end

function Titles.get(id: any): Title?
	return if type(id) == "string" then byId[id] else nil
end

function Titles.getOrDefault(id: any): Title
	return Titles.get(id) or byId[Titles.DefaultId]
end

function Titles.color(def: Title): Color3
	return Lanterns.rarityColor(def.rarity)
end

-- (current, target) for a profile (server data or a client snapshot); current is clamped to target.
function Titles.progress(def: Title, data: any): (number, number)
	if type(data) ~= "table" then
		return 0, math.max(def.target, 1)
	end
	local current, target = 0, def.target
	if def.stat == "default" then
		return 1, 1
	elseif def.stat == "dailyStreak" then
		current = type(data.Daily) == "table" and tonumber(data.Daily.streak) or 0
	elseif def.stat == "lanterns" then
		target = #Lanterns.List
		local owned = type(data.OwnedLanterns) == "table" and data.OwnedLanterns or {}
		for _, lantern in Lanterns.List do
			if owned[lantern.id] then
				current += 1
			end
		end
	elseif def.stat == "deaths" then
		current = tonumber(data.Deaths) or 0
	else
		current = type(data.Stats) == "table" and tonumber(data.Stats[def.stat]) or 0
	end
	target = math.max(target, 1)
	return math.min(current, target), target
end

function Titles.isMet(def: Title, data: any): boolean
	local current, target = Titles.progress(def, data)
	return current >= target
end

return Titles
