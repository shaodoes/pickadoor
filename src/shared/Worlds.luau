--[[
	Worlds: the catalogue of what waits behind the doors (replaces the old Config.Fates stub).

	All 36 worlds from "Pick a Door: Liminal Spaces - The Full Remastered Collection", in the video's door
	pairings (the one-off Secret Door is left out), plus Studio-only test worlds. Each round draws one
	safe and one dangerous world; the door colours are fixed (red = Left, blue = Right) and which of the
	two is safe is a coin flip, so a world's `videoDoor` is trivia, never a rule.

	Entry fields:
	  id          stable key (save data: WorldsSeen / Collectibles, Stats.world_<id>, Stats.worldEscaped_<id>)
	  name        display name;  kind "safe" | "danger" (inferred where the video gives no number)
	  pair        the video's pairing number;  videoDoor "Red" | "Blue";  clip  start time in the video
	  setting, food, water, rest, rules   the video's description (strings, "" when not given)
	  survival    the stated survival chance in percent, or nil;  risk  the catalogue's risk label
	  blurb       one line for the reveal card
	  playable    true once the world is built (all three Worlds/<module>.luau files exist)
	  debug       Studio test worlds: only drawn when nothing real of that kind is playable (or forced)
	  slot        world slot index: the world is built at Config.Worlds.slotOrigin + (slot-1) * slotSpacing on X
	  play        how it plays (only worlds that have, or will soon have, modules):
	    module       name of the three Worlds/<module>.luau files (builder, server, client)
	    mood         client Lighting while you are inside (WorldMood.apply keys)
	    hints        up to three rule lines for the reveal card
	    reward       Keys for escaping (danger) / leaving (safe); default Config.Rewards.Hunt / .Blessing
	    collectible  { id, name } (lounges): found once per player ever, kept in Collectibles
	    pickups      number of key pickups a lounge builder places (Lounge.luau pays them)

	API:
	  Worlds.get(id) -> entry?
	  Worlds.list() -> { entry }  (catalogue order)
	  Worlds.playable(kind, includeDebug?) -> { entry }
	  Worlds.drawPair(rng, last?, seen?) -> safeId, dangerId
	      no immediate repeats of `last` ({ [id]: true }); worlds missing from `seen` weigh x2;
	      falls back to the debug worlds of a kind when nothing real of that kind is playable yet
]]
local Worlds = {}

export type Play = {
	module: string,
	mood: { [string]: any }?,
	hints: { string }?,
	reward: number?,
	collectible: { id: string, name: string }?,
	pickups: number?,
}

export type World = {
	id: string,
	name: string,
	kind: string,
	pair: number,
	videoDoor: string,
	clip: string,
	setting: string,
	food: string,
	water: string,
	rest: string,
	rules: string,
	survival: number?,
	risk: string,
	blurb: string,
	playable: boolean,
	debug: boolean?,
	slot: number,
	play: Play?,
}

local LIST: { World } = {
	-- 1
	{
		id = "mimic_lab",
		name = "Mimic Lab",
		kind = "danger",
		pair = 1,
		videoDoor = "Red",
		clip = "00:07",
		setting = "Night guard in the containment wing of a white underground lab.",
		food = "",
		water = "",
		rest = "",
		rules = "Scientists bang on the glass begging to be let out. Scan before unlocking: a red light means a mimic. Wet-plastic skin or an odd jaw and hands: hide behind the emergency door.",
		risk = "Danger",
		blurb = "They all say they're the real one.",
	},
	{
		id = "azure_water_park",
		name = "Azure Water Park",
		kind = "safe",
		pair = 1,
		videoDoor = "Blue",
		clip = "00:51",
		setting = "A bright indoor water park with 100 m slides, and you are the only guest.",
		food = "Pizza and lemonade.",
		water = "Warm water everywhere.",
		rest = "",
		rules = "None.",
		risk = "Safe",
		blurb = "The whole park, all to yourself.",
	},
	-- 2
	{
		id = "retro_room",
		name = "Retro Room",
		kind = "safe",
		pair = 2,
		videoDoor = "Blue",
		clip = "01:21",
		setting = "A cozy '90s room with bean bags and every console.",
		food = "An infinite pizza and soda fridge.",
		water = "Soda from the fridge.",
		rest = "A bed.",
		rules = "Entities can't enter. Don't look under the bed.",
		risk = "Safe",
		blurb = "Nothing can get in here. Probably.",
		play = {
			module = "RetroRoom",
			hints = { "Entities can't come in here.", "Raid the fridge.", "Don't look under the bed." },
			collectible = { id = "mixtape", name = "Mixtape" },
			pickups = 8,
		},
	},
	{
		id = "the_bedroom",
		name = "The Bedroom",
		kind = "danger",
		pair = 2,
		videoDoor = "Red",
		clip = "01:52",
		setting = "A nightmare bedroom with a door on the left, a door on the right, and a closet.",
		food = "",
		water = "",
		rest = "",
		rules = "Listen. Footsteps: use the flashlight. Breathing: shut that door, no light. The closet creaks: shut it, fast.",
		risk = "Danger",
		blurb = "Listen carefully. Your ears are all you have.",
		play = {
			module = "TheBedroom",
			hints = {
				"Footsteps: flashlight on.",
				"Breathing: shut that door, lights off.",
				"Closet creak: shut it fast.",
			},
		},
	},
	-- 3
	{
		id = "entity_hive",
		name = "Entity Hive",
		kind = "danger",
		pair = 3,
		videoDoor = "Red",
		clip = "02:33",
		setting = "A lobby where the entities wait.",
		food = "",
		water = "",
		rest = "",
		rules = "Don't look at anything for more than 2 seconds or the exit vanishes. Reach the flesh valve exit before the light flickers out.",
		risk = "Danger",
		blurb = "Everything here is waiting for its turn.",
	},
	{
		id = "candy_kingdom",
		name = "Candy Kingdom",
		kind = "danger",
		pair = 3,
		videoDoor = "Blue",
		clip = "02:59",
		setting = "A candy wasteland of sugar-pile hills.",
		food = "Sour seeds (they keep you sharp).",
		water = "",
		rest = "",
		rules = "Keep moving or the ground pulls you in. Avoid the Gummy Guardian's hug.",
		risk = "Danger",
		blurb = "Sweet, until you stop moving.",
	},
	-- 4
	{
		id = "plastic_playground",
		name = "Plastic Playground",
		kind = "danger",
		pair = 4,
		videoDoor = "Red",
		clip = "03:29",
		setting = "Infinite indoor play tubes, humid, the lights always on.",
		food = "Juice boxes in the ball pits.",
		water = "Juice boxes.",
		rest = "",
		rules = "Avoid the crawl spaces (the mascot). Squeaking plastic: you have 10 seconds to hide.",
		risk = "Danger",
		blurb = "Something squeaks through the tubes behind you.",
	},
	{
		id = "abandoned_carnival",
		name = "Abandoned Carnival",
		kind = "safe",
		pair = 4,
		videoDoor = "Blue",
		clip = "04:01",
		setting = "A decaying theme park whose machines run without power.",
		food = "Popcorn at the ticket booths.",
		water = "",
		rest = "Sleep in the Ferris-wheel cabins.",
		rules = "Don't enter the funhouse.",
		risk = "Mostly safe",
		blurb = "The rides still run. Nobody knows on what.",
	},
	-- 5
	{
		id = "cloud_lounge",
		name = "Cloud Lounge",
		kind = "safe",
		pair = 5,
		videoDoor = "Red",
		clip = "04:32",
		setting = "A lounge on a bouncy floor of solid cloud.",
		food = "Self-refilling pancakes.",
		water = "",
		rest = "A floating mattress.",
		rules = "None.",
		survival = 99,
		risk = "99%",
		blurb = "Soft, bright and endless. Try the pancakes.",
		play = {
			module = "CloudLounge",
			hints = { "The floor bounces.", "The pancakes refill themselves.", "Find the syrup bottle." },
			collectible = { id = "syrup_bottle", name = "Syrup Bottle" },
			pickups = 8,
		},
	},
	{
		id = "infinite_living_room",
		name = "Infinite Living Room",
		kind = "danger",
		pair = 5,
		videoDoor = "Blue",
		clip = "04:56",
		setting = "A wood-panel maze with a ceiling so low you crouch.",
		food = "",
		water = "Ceiling condensation only.",
		rest = "",
		rules = "A rising loud hum: move to another room.",
		survival = 24,
		risk = "24%",
		blurb = "When the hum gets louder, move.",
	},
	-- 6
	{
		id = "backyard_labyrinth",
		name = "Backyard Labyrinth",
		kind = "danger",
		pair = 6,
		videoDoor = "Red",
		clip = "05:32",
		setting = "A fence maze under a frozen moon, the crickets deafening.",
		food = "",
		water = "Garden hoses (copper water).",
		rest = "",
		rules = "The Neighbor plays hide and seek. A fence rattles: run. The crickets go silent: freeze.",
		risk = "Danger",
		blurb = "The Neighbor wants to play.",
	},
	{
		id = "play_pit",
		name = "Play Pit",
		kind = "safe",
		pair = 6,
		videoDoor = "Blue",
		clip = "06:00",
		setting = "A primary-colour ball pit.",
		food = "",
		water = "",
		rest = "",
		rules = "None. Find the gold ball.",
		risk = "Safe",
		blurb = "Somewhere in all those balls, one is gold.",
		play = {
			module = "PlayPit",
			hints = { "Wade through the pit.", "One of the balls is gold." },
			collectible = { id = "gold_ball", name = "Gold Ball" },
			pickups = 8,
		},
	},
	-- 7
	{
		id = "orbit_lounge",
		name = "Orbit Lounge",
		kind = "safe",
		pair = 7,
		videoDoor = "Red",
		clip = "06:49",
		setting = "A neon oasis in a violet nebula, in low gravity.",
		food = "Cosmic coasters and chips.",
		water = "Floating drink spheres.",
		rest = "",
		rules = "None.",
		risk = "Safe",
		blurb = "Float. Drink. Watch the nebula turn.",
	},
	{
		id = "terror_hotel",
		name = "Terror Hotel",
		kind = "danger",
		pair = 7,
		videoDoor = "Blue",
		clip = "07:18",
		setting = "A 1920s hotel lobby, gold trim and red velvet.",
		food = "Raw steak and wine (eat fast).",
		water = "Wine.",
		rest = "Sleep in the even-numbered rooms.",
		rules = "Don't look at the guests. Hand your luggage to the faceless bellhop. Music plays backwards: take the elevator up a floor.",
		risk = "Danger",
		blurb = "Check-in is forever.",
	},
	-- 8
	{
		id = "infinite_caves",
		name = "Infinite Caves",
		kind = "danger",
		pair = 8,
		videoDoor = "Blue",
		clip = "08:11",
		setting = "Damp caverns and cliffs.",
		food = "",
		water = "Stalactite drip water.",
		rest = "Rest by the blue-white glowing walls.",
		rules = "Footstep echoes draw attention. Venomous spiders wait in the shadows: move quietly.",
		risk = "Danger",
		blurb = "Every step echoes. Something is listening.",
	},
	{
		id = "golden_baths",
		name = "Golden Baths",
		kind = "safe",
		pair = 8,
		videoDoor = "Red",
		clip = "08:45",
		setting = "A marble sanctuary of glowing healing pools.",
		food = "Grapes.",
		water = "Spring water.",
		rest = "Heated silk beds.",
		rules = "The steam turns red: change pools.",
		risk = "Safe",
		blurb = "Warm water, gold light. Watch the steam.",
	},
	-- 9
	{
		id = "fleshy_nest",
		name = "Fleshy Nest",
		kind = "danger",
		pair = 9,
		videoDoor = "Blue",
		clip = "09:22",
		setting = "Pulsing tentacle caves.",
		food = "",
		water = "The liquid in unhatched eggs (before they harden).",
		rest = "",
		rules = "Blue mist thins your breath. Hide in the giant rib cages from insect swarms and the mind-control embryo. Howling: run, it's a pack.",
		risk = "Danger",
		blurb = "It's breathing. So is everything inside it.",
	},
	{
		id = "paradise_lounge",
		name = "Paradise Lounge",
		kind = "safe",
		pair = 9,
		videoDoor = "Red",
		clip = "10:10",
		setting = "(No narration in the video: design it from the visuals.)",
		food = "",
		water = "",
		rest = "",
		rules = "",
		risk = "Safe?",
		blurb = "Paradise, apparently.",
	},
	-- 10
	{
		id = "playroom_abyss",
		name = "Playroom Abyss",
		kind = "danger",
		pair = 10,
		videoDoor = "Blue",
		clip = "10:48",
		setting = "An infinite playroom of fake grass under humming lights.",
		food = "Plastic food (it tastes of wax).",
		water = "",
		rest = "Oversized toy beds.",
		rules = "Always hold a toy or the toddler entity claims you. Never enter the dark tunnels.",
		survival = 80,
		risk = "80%",
		blurb = "Hold on to your toy.",
	},
	{
		id = "static_desert",
		name = "Static Desert",
		kind = "danger",
		pair = 10,
		videoDoor = "Red",
		clip = "11:24",
		setting = "A desert of soft grey TV-static sand.",
		food = "The Signalman serves TV dinners.",
		water = "Milkshakes.",
		rest = "",
		rules = "A face appears on his screen: never look, or you turn to stone.",
		survival = 45,
		risk = "45%",
		blurb = "Don't look at the screen.",
	},
	-- 11
	{
		id = "infinite_indoor_street",
		name = "Infinite Indoor Street",
		kind = "danger",
		pair = 11,
		videoDoor = "Red",
		clip = "12:04",
		setting = "A windowless street of drywall shacks.",
		food = "Drywall crackers.",
		water = "",
		rest = "",
		rules = "Keep walking. The streetlights go out: hide in a house and stay silent. Stay too long and the door vanishes.",
		survival = 17,
		risk = "17%",
		blurb = "Keep walking. Always keep walking.",
	},
	{
		id = "arcade_hall",
		name = "Arcade Hall",
		kind = "danger",
		pair = 11,
		videoDoor = "Blue",
		clip = "12:34",
		setting = "An infinite hall of glowing yellow arches.",
		food = "Floating pizza machines.",
		water = "Floating soda machines.",
		rest = "A warm floating carpet.",
		rules = "Hold the high score. Drop to second and the Game Over entity comes.",
		survival = 68,
		risk = "68%",
		blurb = "Stay number one.",
	},
	-- 12
	{
		id = "infinite_party",
		name = "Infinite Party",
		kind = "danger",
		pair = 12,
		videoDoor = "Red",
		clip = "13:12",
		setting = "A bright basement full of balloons that won't pop.",
		food = "Foam birthday cake.",
		water = "",
		rest = "Bean bags.",
		rules = "Don't blow out the candles. The Birthday Boy hides. Never open the gift boxes.",
		survival = 75,
		risk = "75%",
		blurb = "It's always somebody's birthday.",
	},
	{
		id = "laundromat_basement",
		name = "Laundromat Basement",
		kind = "danger",
		pair = 12,
		videoDoor = "Blue",
		clip = "13:42",
		setting = "Thousands of washing machines in two inches of soapy water.",
		food = "Soggy cereal on the dryers.",
		water = "",
		rest = "A bed of wet clothes.",
		rules = "The spin cycle hunts: a machine starts by itself, run to the next room.",
		survival = 45,
		risk = "45%",
		blurb = "When a machine starts on its own, run.",
	},
	-- 13
	{
		id = "balloon_sky_bridge",
		name = "Balloon Sky Bridge",
		kind = "danger",
		pair = 13,
		videoDoor = "Red",
		clip = "14:16",
		setting = "A bridge of party balloons above the clouds.",
		food = "Floating cloud cakes.",
		water = "",
		rest = "",
		rules = "The Watcher clown follows to carry your bags: keep walking.",
		survival = 60,
		risk = "60%",
		blurb = "Don't let the clown carry your bags.",
	},
	{
		id = "sunset_party_yard",
		name = "Sunset Party Yard",
		kind = "danger",
		pair = 13,
		videoDoor = "Blue",
		clip = "14:40",
		setting = 'A yard under a permanent purple sunset ("bourbon yard" in the transcript).',
		food = "Neon blue cake.",
		water = "",
		rest = "",
		rules = "The Party Goer is a balloon with a human face. A balloon pops: you have 5 seconds to dive under the party table and freeze.",
		survival = 45,
		risk = "45%",
		blurb = "When a balloon pops, get under the table.",
	},
	-- 14
	{
		id = "endless_pink_closet",
		name = "Endless Pink Closet",
		kind = "safe",
		pair = 14,
		videoDoor = "Red",
		clip = "15:23",
		setting = "Racks of clothes in soft light.",
		food = "Candy in the pockets.",
		water = "Water on the shelves.",
		rest = "Rest in the clothes piles.",
		rules = "A tall black figure hangs like a coat: don't touch it. Warm clothing: don't touch.",
		survival = 93,
		risk = "93%",
		blurb = "Don't touch the coat that's warm.",
	},
	{
		id = "concrete_rooms",
		name = "Concrete Rooms",
		kind = "danger",
		pair = 14,
		videoDoor = "Blue",
		clip = "15:49",
		setting = "Infinite cold grey rooms, one flickering bulb each.",
		food = "None.",
		water = "None.",
		rest = "",
		rules = "Corner entities multiply with every flicker. Lights out: reach a lit room within 20 seconds.",
		survival = 18,
		risk = "18%",
		blurb = "Every flicker, there are more of them.",
		play = {
			module = "ConcreteRooms",
			hints = { "Each flicker adds one in the corner.", "Lights out: reach a lit room in 20 s." },
		},
	},
	-- 15
	{
		id = "looping_suburban_house",
		name = "Looping Suburban House",
		kind = "safe",
		pair = 15,
		videoDoor = "Blue",
		clip = "16:22",
		setting = "A house whose rooms bend back on themselves; pastel bedrooms.",
		food = "Childhood comfort food.",
		water = "",
		rest = "Deep sleep.",
		rules = "Translucent parents. Refuse the neighbour's cookies. Never answer your name from upstairs. Keep a light on: darkness shrinks the house.",
		survival = 85,
		risk = "85%",
		blurb = "Home. Mostly.",
	},
	{
		id = "midnight_playground",
		name = "Midnight Playground",
		kind = "danger",
		pair = 15,
		videoDoor = "Red",
		clip = "17:04",
		setting = "An overgrown playground under a starless night.",
		food = "Cake slices.",
		water = "Juice boxes.",
		rest = "Naps in the tunnels.",
		rules = "Keep moving: stillness summons the playmates. Don't look at faces. Don't climb the highest slide. Ignore the lost child.",
		survival = 33,
		risk = "33%",
		blurb = "Stand still and they come to play.",
	},
	-- 16
	{
		id = "goth_bedroom_wing",
		name = "Goth Bedroom Wing",
		kind = "safe",
		pair = 16,
		videoDoor = "Blue",
		clip = "17:54",
		setting = "Purple and black velvet bedrooms.",
		food = "Black tea, dark chocolate and pomegranate.",
		water = "Black tea.",
		rest = "Canopy beds.",
		rules = "The goth figures stay calm if you accept their black roses.",
		risk = "Safe",
		blurb = "Accept the rose.",
	},
	{
		id = "red_wallpaper_hallway",
		name = "Red Wallpaper Hallway",
		kind = "danger",
		pair = 16,
		videoDoor = "Red",
		clip = "18:24",
		setting = "An endless hall of peeling red wallpaper and rust stains.",
		food = "",
		water = "A rusty faucet (brown water).",
		rest = "Rest on the cold tile.",
		rules = "Don't answer your name from the side rooms. Look away from the mirrors.",
		risk = "Unsafe",
		blurb = "Someone in the side rooms knows your name.",
	},
	-- 17
	{
		id = "pastel_nursery_loop",
		name = "Pastel Nursery Loop",
		kind = "danger",
		pair = 17,
		videoDoor = "Blue",
		clip = "19:08",
		setting = "A looping pink bedroom of cribs and stuffed animals.",
		food = "Toy tea sets and animal cookies.",
		water = "",
		rest = "Plush beds.",
		rules = "The tall black creature moves one room closer every time you blink. Keep the nightlight on.",
		survival = 45,
		risk = "45%",
		blurb = "Don't blink. Keep the nightlight on.",
	},
	{
		id = "cloud_gas_station",
		name = "Cloud Gas Station",
		kind = "safe",
		pair = 17,
		videoDoor = "Red",
		clip = "19:49",
		setting = "A '90s gas station floating in the clouds.",
		food = "A restocking fridge.",
		water = "Any-flavour slurpee.",
		rest = "",
		rules = "Black figures watch from the pumps. Ignore the phantom customer bell.",
		survival = 95,
		risk = "95%",
		blurb = "Ignore the bell.",
	},
	-- 18
	{
		id = "infinite_food_court",
		name = "Infinite Food Court",
		kind = "safe",
		pair = 18,
		videoDoor = "Blue",
		clip = "20:25",
		setting = "A bright cafeteria with soft '80s music.",
		food = "Unlimited vending machines and fridges.",
		water = "The fridges.",
		rest = "Booths and nap rooms.",
		rules = "The employees are silent and friendly. Don't waste food.",
		survival = 95,
		risk = "95%",
		blurb = "All you can eat. Don't waste any.",
	},
	{
		id = "endless_art_gallery",
		name = "Endless Art Gallery",
		kind = "danger",
		pair = 18,
		videoDoor = "Red",
		clip = "21:00",
		setting = "White walls, spotlights and paintings that move.",
		food = "Refilling grapes.",
		water = "",
		rest = "Benches that grow cold.",
		rules = "Never stop watching a painting. They whisper after hours.",
		survival = 30,
		risk = "30%",
		blurb = "They only move when nobody is looking.",
		play = {
			module = "ArtGallery",
			hints = { "Paintings move when nobody watches.", "Keep your eyes on them." },
		},
	},

	-- Studio test worlds (Phase 0): the old safe room and threat corridor, wrapped as worlds. Only
	-- drawn while no real world of their kind is playable, or when forced with DebugPair.
	{
		id = "_test_lounge",
		name = "Test Lounge",
		kind = "safe",
		pair = 0,
		videoDoor = "Blue",
		clip = "",
		setting = "The old warm sitting room.",
		food = "",
		water = "",
		rest = "Armchairs by the fire.",
		rules = "None.",
		risk = "Safe",
		blurb = "A warm room to wait in.",
		playable = true,
		debug = true,
		play = {
			module = "TestLounge",
			mood = {
				Ambient = Color3.fromRGB(40, 30, 22),
				OutdoorAmbient = Color3.fromRGB(20, 16, 12),
				FogColor = Color3.fromRGB(20, 14, 10),
				FogStart = 60,
				FogEnd = 220,
				TintColor = Color3.fromRGB(255, 240, 225),
			},
			hints = { "Pick up the keys.", "Find the brass bell.", "Leave by the exit when you like." },
			collectible = { id = "_test_bell", name = "Brass Bell" },
			pickups = 4,
		},
	},
	{
		id = "_test_hunt",
		name = "Test Corridor",
		kind = "danger",
		pair = 0,
		videoDoor = "Red",
		clip = "",
		setting = "The old threat corridor.",
		food = "",
		water = "",
		rest = "",
		rules = "The Follower walks the corridor.",
		risk = "Danger",
		blurb = "It follows. It always follows.",
		playable = true,
		debug = true,
		play = {
			module = "TestHunt",
			mood = {
				Ambient = Color3.fromRGB(10, 11, 14),
				OutdoorAmbient = Color3.fromRGB(6, 6, 8),
				FogColor = Color3.fromRGB(4, 4, 6),
				FogStart = 20,
				FogEnd = 120,
				TintColor = Color3.fromRGB(225, 232, 255),
				Saturation = -0.25,
			},
			hints = { "Search the crate for the key.", "Reach the far end.", "Don't let it touch you." },
		},
	},
	{
		id = "_template",
		name = "Template",
		kind = "danger",
		pair = 0,
		videoDoor = "Red",
		clip = "",
		setting = "The copy-me world (Worlds/_Template.luau).",
		food = "",
		water = "",
		rest = "",
		rules = "",
		risk = "Danger",
		blurb = "Copy me.",
		playable = true,
		debug = true,
		play = {
			module = "_Template",
			hints = { "Press the button.", "Reach the exit." },
		},
	},
}

-- the six starter worlds are reserved here (modules named) but not playable until Phase 1 builds them
local byId: { [string]: World } = {}
for i, world in LIST do
	world.slot = i
	world.playable = world.playable == true
	byId[world.id] = world
end

-- debug worlds the drawer may fall back to (the template is only ever forced)
local FALLBACK = { _test_lounge = true, _test_hunt = true }

function Worlds.get(id: string?): World?
	return if id then byId[id] else nil
end

function Worlds.list(): { World }
	return LIST
end

function Worlds.playable(kind: string, includeDebug: boolean?): { World }
	local out = {}
	for _, world in LIST do
		if world.kind == kind and world.playable and world.play and (includeDebug or not world.debug) then
			table.insert(out, world)
		end
	end
	return out
end

local function pick(rng: Random, kind: string, last: { [string]: boolean }?, seen: { [string]: boolean }?): string
	local pool = Worlds.playable(kind)
	if #pool == 0 then
		for _, world in Worlds.playable(kind, true) do
			if FALLBACK[world.id] then
				table.insert(pool, world)
			end
		end
	end
	assert(#pool > 0, "Worlds.drawPair: nothing playable of kind " .. kind)
	-- no immediate repeat (unless it's the only one); unseen worlds weigh double
	local candidates = {}
	local total = 0
	for _, world in pool do
		if #pool == 1 or not (last and last[world.id]) then
			local weight = if seen and not seen[world.id] then 2 else 1
			total += weight
			table.insert(candidates, { id = world.id, weight = weight })
		end
	end
	local roll = rng:NextNumber() * total
	for _, c in candidates do
		roll -= c.weight
		if roll <= 0 then
			return c.id
		end
	end
	return candidates[#candidates].id
end

function Worlds.drawPair(rng: Random, last: { [string]: boolean }?, seen: { [string]: boolean }?): (string, string)
	return pick(rng, "safe", last, seen), pick(rng, "danger", last, seen)
end

return Worlds
