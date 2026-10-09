--[[
	Daily rewards, the Wheel of Fate and challenges: every table and rule both sides need.
	The server is the only authority (it grants, rolls and validates); clients use this module to
	draw the calendar / wheel / ledger and to work out what's claimable for the "!" badges.

	Time: days and weeks are UTC. Day index = floor(t / 86400); weeks start on Monday
	(1970-01-01 was a Thursday, so week index = floor((day + 3) / 7)). The server uses os.time(),
	clients workspace:GetServerTimeNow(). In Studio only, workspace attribute RewardDayOffset (whole
	days, set by the server's debug hook or the command bar) shifts "now" so streaks and rotation
	can be tested.

	Profile schema (DataService defaults; all optional on old saves):
		Daily      = { streak = 0..7 (the calendar day last claimed), lastClaimDay = -1 }
		Spins      = { lastFreeDay = -1, extra = 0, total = 0 }
		Challenges = { day = -1, week = -1, daily = { Slot }, weekly = { Slot } }
		  Slot     = { id = string, progress = number, claimed = boolean }
]]
local RunService = game:GetService("RunService")

local Rewards = {}

------------------------------------------------------------------------------------------
-- Time
------------------------------------------------------------------------------------------
local DAY = 86400

function Rewards.dayOffset(): number
	if not RunService:IsStudio() then
		return 0
	end
	return math.floor(tonumber(workspace:GetAttribute("RewardDayOffset")) or 0)
end

-- "Now" in seconds since the epoch (UTC), including the Studio day offset.
function Rewards.now(): number
	local t = if RunService:IsServer() then os.time() else workspace:GetServerTimeNow()
	return t + Rewards.dayOffset() * DAY
end

function Rewards.dayIndex(t: number): number
	return t // DAY
end

function Rewards.weekIndex(t: number): number
	return (t // DAY + 3) // 7
end

function Rewards.today(): number
	return Rewards.dayIndex(Rewards.now())
end

function Rewards.thisWeek(): number
	return Rewards.weekIndex(Rewards.now())
end

function Rewards.secondsToNextDay(): number
	local t = Rewards.now()
	return DAY - (t % DAY)
end

function Rewards.secondsToNextWeek(): number
	local t = Rewards.now()
	local day = t // DAY
	local daysLeft = 6 - ((day + 3) % 7) -- 0 on Sunday
	return daysLeft * DAY + (DAY - t % DAY)
end

-- "5h 12m" / "2d 4h" / "48s"
function Rewards.formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = seconds // DAY, (seconds % DAY) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, seconds % 60)
	end
	return string.format("%ds", seconds)
end

------------------------------------------------------------------------------------------
-- Daily reward: a 7-day streak calendar. One claim per UTC day; miss a day and it starts over.
------------------------------------------------------------------------------------------
export type DailyDay = { day: number, keys: number, spins: number?, items: { [string]: number }? }

Rewards.Daily = {
	{ day = 1, keys = 25 },
	{ day = 2, keys = 40 },
	{ day = 3, keys = 60 },
	{ day = 4, keys = 80 },
	{ day = 5, keys = 100 },
	{ day = 6, keys = 150 },
	{ day = 7, keys = 250, spins = 1, items = { bandage = 1 } },
} :: { DailyDay }

-- What the calendar should show for a profile's Daily table on `today`:
--   claimable  - a claim is available today
--   day        - the calendar day (1..7) you'd claim now, or the one claimed today
--   claimedToday
--   streak     - days already banked in the current run (0 if it broke)
function Rewards.dailyState(daily: any, today: number?)
	today = today or Rewards.today()
	local streak = if type(daily) == "table" then tonumber(daily.streak) or 0 else 0
	local last = if type(daily) == "table" then tonumber(daily.lastClaimDay) or -1 else -1
	if last == today then
		return { claimable = false, claimedToday = true, day = math.clamp(streak, 1, 7), streak = streak }
	end
	local alive = last == (today :: number) - 1 and streak > 0 and streak < 7
	local banked = if alive then streak else 0
	return { claimable = true, claimedToday = false, day = banked + 1, streak = banked }
end

------------------------------------------------------------------------------------------
-- Wheel of Fate
------------------------------------------------------------------------------------------
Rewards.SpinCost = 150 -- Keys for an extra spin
Rewards.SpinDuration = 5.5 -- seconds from start to rest (UI wheel and 3D wheel use the same curve)
Rewards.SpinTurns = 5 -- whole turns before it settles
Rewards.LanternFallbackKeys = 300 -- the lantern segment when you already own every lantern

export type Segment = {
	kind: "keys" | "item" | "spin" | "lantern",
	label: string, -- short text on the segment
	amount: number, -- keys / item count / spins (lantern: 1)
	item: string?, -- Items id for kind "item"
	weight: number, -- relative odds (the table sums to 100, so weight = percent)
	color: Color3, -- segment fill
	icon: string?, -- UIKit icon name
}

-- Order = clockwise from 12 o'clock as seen from the front. Segment i is centred on (i - 1) * 36 degrees.
-- Colours alternate the lobby's door palette: oxblood, walnut, brass, slate.
Rewards.Wheel = {
	{ kind = "keys", label = "25", amount = 25, weight = 22, color = Color3.fromRGB(116, 40, 34), icon = "key" },
	{
		kind = "item",
		label = "PILLS",
		amount = 1,
		item = "speed_pills",
		weight = 12,
		color = Color3.fromRGB(62, 84, 110),
		icon = "pills",
	},
	{ kind = "keys", label = "50", amount = 50, weight = 18, color = Color3.fromRGB(88, 60, 38), icon = "key" },
	{
		kind = "item",
		label = "BANDAGE",
		amount = 1,
		item = "bandage",
		weight = 12,
		color = Color3.fromRGB(116, 40, 34),
		icon = "bandage",
	},
	{ kind = "keys", label = "100", amount = 100, weight = 10, color = Color3.fromRGB(62, 84, 110), icon = "key" },
	{
		kind = "item",
		label = "PICKS",
		amount = 1,
		item = "lockpicks",
		weight = 10,
		color = Color3.fromRGB(88, 60, 38),
		icon = "lockpick",
	},
	{ kind = "keys", label = "200", amount = 200, weight = 5, color = Color3.fromRGB(116, 40, 34), icon = "key" },
	{ kind = "spin", label = "SPIN", amount = 1, weight = 6, color = Color3.fromRGB(62, 84, 110), icon = "play" },
	{ kind = "keys", label = "500", amount = 500, weight = 2, color = Color3.fromRGB(150, 112, 56), icon = "key" },
	{
		kind = "lantern",
		label = "LANTERN",
		amount = 1,
		weight = 3,
		color = Color3.fromRGB(42, 30, 26),
		icon = "lantern",
	},
} :: { Segment }

Rewards.SegmentAngle = 360 / #Rewards.Wheel

function Rewards.totalWeight(): number
	local total = 0
	for _, seg in Rewards.Wheel do
		total += seg.weight
	end
	return total
end

-- Odds as percentages, in wheel order.
function Rewards.odds(): { number }
	local total = Rewards.totalWeight()
	local list = {}
	for i, seg in Rewards.Wheel do
		list[i] = seg.weight / total * 100
	end
	return list
end

-- Server: pick a segment index with the weighted table.
function Rewards.rollSegment(rng: Random): number
	local pick = rng:NextNumber() * Rewards.totalWeight()
	for i, seg in Rewards.Wheel do
		pick -= seg.weight
		if pick < 0 then
			return i
		end
	end
	return 1
end

-- Clockwise rotation (degrees) that puts the centre of segment `index` under the top pointer,
-- plus `offset` degrees of in-segment jitter (|offset| < SegmentAngle / 2).
function Rewards.restAngle(index: number, offset: number?): number
	return (-(index - 1) * Rewards.SegmentAngle - (offset or 0)) % 360
end

-- Ease-out used by both wheels: fast start, long slow settle.
function Rewards.spinEase(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return 1 - (1 - alpha) ^ 4
end

-- Total clockwise travel (degrees) for a spin from rotation `from` that rests on `index` (+offset).
function Rewards.spinTravel(from: number, index: number, offset: number?): number
	local delta = (Rewards.restAngle(index, offset) - from) % 360
	return Rewards.SpinTurns * 360 + delta
end

------------------------------------------------------------------------------------------
-- Challenges: 3 daily + 3 weekly per player, drawn deterministically from these pools.
-- `stat` is what ChallengeService.record(player, stat, amount) counts.
------------------------------------------------------------------------------------------
--	Stats recorded by the game:
--		trials        finished a trial (not counting rounds spent at the door)   DoorRoomFlow
--		rightDoor     picked the right door                                       DoorRoomFlow
--		huntSurvived  survived the threat side                                    DoorRoomFlow
--		speedPills    used Speed Pills                                            ItemService
--		bandage       used a Bandage Pack                                         ItemService
--		itemsUsed     used any consumable                                         ItemService
--		lockpick      picked a lock                                               ItemService
--		laserStun     stunned an entity with the laser                            ItemService
--		dailyChest    claimed the daily reward                                    RewardsService
--		spin          spun the Wheel of Fate                                      RewardsService
--		talkTeeth / talkLibrarian / talkArchivist   finished a conversation       Talked remote
export type ChallengeDef = {
	id: string,
	text: string,
	stat: string,
	target: number,
	keys: number,
	spins: number?,
}

Rewards.DailyChallenges = {
	{ id = "d_trials", text = "Go through 2 doors", stat = "trials", target = 2, keys = 60 },
	{ id = "d_right", text = "Pick the right door 2 times", stat = "rightDoor", target = 2, keys = 80 },
	{ id = "d_hunt", text = "Survive a Hunt", stat = "huntSurvived", target = 1, keys = 100 },
	{ id = "d_pills", text = "Swallow 2 Speed Pills", stat = "speedPills", target = 2, keys = 50 },
	{ id = "d_bandage", text = "Patch yourself up with a Bandage Pack", stat = "bandage", target = 1, keys = 50 },
	{ id = "d_lock", text = "Pick a lock", stat = "lockpick", target = 1, keys = 60 },
	{ id = "d_stun", text = "Blind an entity with the laser", stat = "laserStun", target = 1, keys = 80 },
	{ id = "d_chest", text = "Open the daily chest", stat = "dailyChest", target = 1, keys = 30 },
	{ id = "d_spin", text = "Spin the Wheel of Fate", stat = "spin", target = 1, keys = 30 },
	{ id = "d_teeth", text = "Have a word with Teeth", stat = "talkTeeth", target = 1, keys = 25 },
	{ id = "d_librarian", text = "Listen to the Librarian", stat = "talkLibrarian", target = 1, keys = 25 },
	{ id = "d_ashby", text = "Ask Mr. Ashby about his ledger", stat = "talkArchivist", target = 1, keys = 25 },
} :: { ChallengeDef }

Rewards.WeeklyChallenges = {
	{ id = "w_trials", text = "Go through 10 doors", stat = "trials", target = 10, keys = 300, spins = 1 },
	{ id = "w_hunt", text = "Survive 3 Hunts", stat = "huntSurvived", target = 3, keys = 400, spins = 1 },
	{ id = "w_right", text = "Pick the right door 8 times", stat = "rightDoor", target = 8, keys = 350 },
	{ id = "w_items", text = "Use 6 items", stat = "itemsUsed", target = 6, keys = 250 },
	{ id = "w_stun", text = "Blind 5 entities with the laser", stat = "laserStun", target = 5, keys = 400 },
	{ id = "w_chest", text = "Open the daily chest on 5 days", stat = "dailyChest", target = 5, keys = 300, spins = 1 },
	{ id = "w_spin", text = "Spin the Wheel of Fate 5 times", stat = "spin", target = 5, keys = 250 },
	{ id = "w_locks", text = "Pick 3 locks", stat = "lockpick", target = 3, keys = 250 },
} :: { ChallengeDef }

Rewards.ChallengesPerSet = 3

local defsById: { [string]: ChallengeDef } = {}
for _, def in Rewards.DailyChallenges do
	defsById[def.id] = def
end
for _, def in Rewards.WeeklyChallenges do
	defsById[def.id] = def
end

function Rewards.challenge(id: string?): ChallengeDef?
	return id and defsById[id] or nil
end

-- Deterministic draw of `count` distinct challenges from `pool` for (userId, period).
local function draw(pool: { ChallengeDef }, userId: number, period: number, salt: number, count: number)
	local rng = Random.new((userId % 1000003) * 7919 + period * 104729 + salt)
	local indices = {}
	for i = 1, #pool do
		indices[i] = i
	end
	for i = #indices, 2, -1 do
		local j = rng:NextInteger(1, i)
		indices[i], indices[j] = indices[j], indices[i]
	end
	local slots = {}
	for i = 1, math.min(count, #indices) do
		table.insert(slots, { id = pool[indices[i]].id, progress = 0, claimed = false })
	end
	return slots
end

function Rewards.drawDaily(userId: number, day: number)
	return draw(Rewards.DailyChallenges, userId, day, 11, Rewards.ChallengesPerSet)
end

function Rewards.drawWeekly(userId: number, week: number)
	return draw(Rewards.WeeklyChallenges, userId, week, 29, Rewards.ChallengesPerSet)
end

-- Server: make sure a profile's Challenges are for the current day/week (re-draws on rollover and
-- repairs bad data). Returns true if anything changed.
function Rewards.rollover(data: any, userId: number): boolean
	local today, week = Rewards.today(), Rewards.thisWeek()
	local ch = data.Challenges
	if type(ch) ~= "table" then
		ch = { day = -1, week = -1, daily = {}, weekly = {} }
		data.Challenges = ch
	end
	local changed = false
	if ch.day ~= today or type(ch.daily) ~= "table" then
		ch.day = today
		ch.daily = Rewards.drawDaily(userId, today)
		changed = true
	end
	if ch.week ~= week or type(ch.weekly) ~= "table" then
		ch.week = week
		ch.weekly = Rewards.drawWeekly(userId, week)
		changed = true
	end
	return changed
end

-- Client/server: is this slot complete and unclaimed?
function Rewards.slotClaimable(slot: any): boolean
	local def = type(slot) == "table" and Rewards.challenge(slot.id)
	return def ~= nil and not slot.claimed and (tonumber(slot.progress) or 0) >= def.target
end

------------------------------------------------------------------------------------------
-- Badges: what each station has waiting for a profile snapshot (client "!" markers)
------------------------------------------------------------------------------------------
function Rewards.freeSpinReady(spins: any, today: number?): boolean
	today = today or Rewards.today()
	return type(spins) ~= "table" or spins.lastFreeDay ~= today
end

function Rewards.spinsAvailable(spins: any, today: number?): number
	local extra = type(spins) == "table" and tonumber(spins.extra) or 0
	return extra + (if Rewards.freeSpinReady(spins, today) then 1 else 0)
end

function Rewards.badges(snapshot: any): { Daily: boolean, Wheel: boolean, Challenges: boolean }
	if type(snapshot) ~= "table" then
		return { Daily = false, Wheel = false, Challenges = false }
	end
	local today = Rewards.today()
	local challenges = false
	local ch = snapshot.Challenges
	if type(ch) == "table" then
		for _, set in { ch.daily, ch.weekly } do
			for _, slot in (type(set) == "table" and set or {}) do
				if Rewards.slotClaimable(slot) then
					challenges = true
				end
			end
		end
	end
	return {
		Daily = Rewards.dailyState(snapshot.Daily, today).claimable,
		Wheel = Rewards.spinsAvailable(snapshot.Spins, today) > 0,
		Challenges = challenges,
	}
end

------------------------------------------------------------------------------------------
-- Stations (the three glowing rings in the reading hall; positions live in Builders.Layout)
------------------------------------------------------------------------------------------
Rewards.Stations = {
	Daily = { title = "DAILY REWARD", color = Color3.fromRGB(255, 186, 92) }, -- warm candle gold
	Wheel = { title = "WHEEL OF FATE", color = Color3.fromRGB(196, 120, 255) }, -- uncanny violet
	Challenges = { title = "CHALLENGES", color = Color3.fromRGB(120, 214, 220) }, -- the archivist's cold teal
}

-- The Archivist (challenges NPC)
Rewards.ArchivistName = "Mr. Ashby"

return Rewards
