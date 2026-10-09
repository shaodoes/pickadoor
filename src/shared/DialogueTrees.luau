-- Everything the lobby's characters say, as Dialogue trees (see Dialogue.luau for the node format).
--   DialogueTrees.Librarian   the introduction: nine lines, straight through
--   DialogueTrees.Shopkeeper  Teeth, behind the gift-shop counter: a small menu of questions
--   DialogueTrees.Archivist   Mr. Ashby, at the challenges desk: a small menu; action "openChallenges"
--   DialogueTrees.ArchivistGreetings  one-liners he whispers when you step onto his ring
-- Shopkeeper context (opts.context): trialsPlayed: number, keys: number, currency: string, lasered: boolean.
local Config = require(script.Parent.Config)
local Dialogue = require(script.Parent.Dialogue)
local UIKit = require(script.Parent.UIKit)

type Tree = Dialogue.Tree

local DialogueTrees = {}

------------------------------------------------------------------------------------------
-- The Librarian
------------------------------------------------------------------------------------------
DialogueTrees.Librarian = {
	speaker = "THE LIBRARIAN",
	accent = UIKit.Colors.accent,
	start = "stairs",
	nodes = {
		stairs = { text = "Oh. Another one found the stairs.", next = "library" },
		library = {
			text = "This is the library. Nobody remembers building it down here. You can stay as long as you like... but the doors will want you eventually.",
			next = "mats",
		},
		mats = {
			text = "See the mats along the back wall? Stand on one. Solo, Duo, or Squad. Bring friends if you have them.",
			next = "count",
		},
		count = {
			text = "When the count runs out, the door opens. Behind it are two more doors, and ten seconds to choose.",
			next = "kind",
		},
		kind = {
			text = "Some lead somewhere kind. Warm rooms. Gifts. " .. Config.CurrencyName .. ".",
			next = "occupied",
		},
		occupied = {
			text = "Some lead somewhere that is... occupied. Keep moving, keep quiet, and stay alive until it lets you go.",
			next = "spend",
		},
		spend = {
			text = "Whatever you bring back, spend at my desk. Or take it to the workbench for a better lantern.",
			next = "lantern",
		},
		lantern = {
			text = "Your lantern is the one thing that goes through the door with you. Look after it.",
			next = "listening",
		},
		listening = { text = "That's all I can tell you. Pick a door. They're all listening." },
	},
} :: Tree

------------------------------------------------------------------------------------------
-- Teeth, the shopkeeper. Polite. Too polite.
------------------------------------------------------------------------------------------
local function played(ctx): boolean
	return (ctx.trialsPlayed or 0) > 0
end

DialogueTrees.Shopkeeper = {
	speaker = "TEETH",
	accent = Color3.fromRGB(96, 40, 150),
	start = function(ctx)
		if ctx.lasered then
			return "lasered"
		elseif played(ctx) then
			return "returning"
		end
		return "welcome"
	end,
	nodes = {
		-- openers
		welcome = { text = "Welcome. Mind the glass. It's mine.", next = "menu" },
		returning = { text = "You came back. They usually don't. Go on. Browse.", next = "menu" },
		lasered = { text = "Put that away. I like my eyes.", next = "menu" },

		menu = {
			text = "Ask. I don't mind questions. I mind fingerprints.",
			choices = {
				{ text = "What do you sell?", next = "wares" },
				{ text = "Tell me about yourself", next = "about" },
				{ text = "What's behind the doors?", next = "doors" },
				{ text = "Nothing, sorry", next = "nothing" },
			},
		},

		-- "What do you sell?"
		wares = {
			text = "Pills for your legs. Bandages for your mistakes. Lockpicks for things that would rather stay shut.",
			next = "laser",
		},
		laser = { text = "And a laser pointer. It bothers the others. Not me. Nothing bothers me.", next = "count" },
		count = {
			text = function(ctx)
				return string.format(
					"You have %d %s. I counted. I always count.",
					ctx.keys or 0,
					ctx.currency or Config.CurrencyName
				)
			end,
			choices = {
				{ text = "Show me.", action = "openShop" },
				{ text = "Back", next = "menu" },
			},
		},

		-- "Tell me about yourself": a submenu, so the main menu keeps its four slots
		about = {
			text = "Me? Nobody asks about me. They ask about prices. Go on, then. Quickly, before I get shy.",
			choices = {
				{ text = "What are you?", next = "what" },
				{ text = "Why are you helping us?", next = "why" },
				{ text = "Are the others like you?", next = "others" },
				{ text = "Back", next = "menu" },
			},
		},

		-- "What are you?"
		what = { text = "The shopkeeper.", next = "before" },
		before = { text = "Before that? The shop was empty. Then it wasn't.", next = "rude" },
		rude = { text = "Don't look at the teeth. Everyone looks at the teeth. It's rude.", next = "about" },

		-- "Why are you helping us?": why a thing like him is on your side
		why = {
			text = "I used to be behind one of the doors. The wrong one. I was very good at it.",
			next = "why2",
		},
		why2 = {
			text = "But hunting is lonely. You chase someone for hours and then... they're gone. Every time. No conversation.",
			next = "why3",
		},
		why3 = {
			text = "Customers come back. Prey doesn't. I did the arithmetic. I'm very good at arithmetic.",
			next = "why4",
		},
		why4 = {
			text = "So I made a deal with the library. I keep the shop. It keeps my old door shut behind me.",
			next = "why5",
		},
		why5 = {
			text = function(ctx)
				if played(ctx) then
					return "And you came back. You see? It works. I'm so glad. I would hate to have to go back to the old job."
				end
				return "Buy a laser. Buy bandages. Come back alive. I'd hate for you to become a story I tell."
			end,
			next = "about",
		},

		-- "Are the others like you?"
		others = {
			text = "The others? No. They don't count, they don't trade, and they don't stop.",
			next = "others2",
		},
		others2 = {
			text = "The laser makes them blink. Blinking is all you need. Trust a thing that never does.",
			next = "about",
		},

		-- "What's behind the doors?"
		doors = {
			text = function(ctx)
				if played(ctx) then
					return "You already know. You've got the look."
				end
				return "Two doors. Behind one, somewhere kind. Behind the other, something awake."
			end,
			next = "doors2",
		},
		doors2 = {
			text = function(ctx)
				if played(ctx) then
					return "Whatever came back with you... spend it here. It doesn't keep."
				end
				return "The doors pick too, you know. Not just you."
			end,
			next = "menu",
		},

		-- "Nothing, sorry"
		nothing = { text = "Nothing is my favourite. Come again. You will." },
	},
} :: Tree

------------------------------------------------------------------------------------------
-- Mr. Ashby, the archivist. Dry, precise, kind, and not entirely here.
------------------------------------------------------------------------------------------
DialogueTrees.Archivist = {
	speaker = "MR. ASHBY",
	-- the station's cold teal, darkened so the cream tab text stays readable
	accent = Color3.fromRGB(56, 118, 124),
	start = "greeting",
	nodes = {
		greeting = {
			text = "Good evening. Or morning. Down here it is always a quarter past something. Ashby, archivist. Mind the ink.",
			next = "menu",
		},

		menu = {
			text = "Is there something you'd like explained, or something you'd like entered?",
			-- (five choices: the number keys reach 1-4, "Goodbye." is a click)
			choices = {
				{ text = "Show me the ledger.", action = "openChallenges" },
				{ text = "What is this ledger?", next = "ledger" },
				{ text = "Who are you?", next = "who" },
				{ text = "The chest and the wheel?", next = "chest" }, -- short: a half-width cell truncates
				{ text = "Goodbye.", next = "goodbye" },
			},
		},

		-- "What is this ledger?"
		ledger = {
			text = "Everyone who goes through a door is written in here. Name, date, door. What came back, and what didn't.",
			next = "ledger2",
		},
		ledger2 = {
			text = "Each day I set you three small tasks, and three larger ones each week. Finish one, and I pay you for the trouble.",
			next = "ledger3",
		},
		ledger3 = {
			text = "The daily page turns at midnight, the weekly page on Monday. Universal time. The library doesn't keep yours.",
			next = "menu",
		},

		-- "Who are you?"
		who = {
			text = "I was a patron, once. I borrowed a book, and I returned it... rather late.",
			next = "who2",
		},
		who2 = {
			text = "Forty-one years, by the stamp. The library was very understanding. It gave me a desk, and all the time I need to work it off.",
			next = "who3",
		},
		who3 = {
			text = "So I keep the accounts now. Everyone's. It's quiet work. I've stopped feeling the cold. I've stopped feeling most things.",
			next = "menu",
		},

		-- "What's the chest and the wheel?"
		chest = {
			text = "The chest between the study desks opens once a day. Come every day and it grows generous. Miss one and it forgets you.",
			next = "wheel",
		},
		wheel = {
			text = "And at the back, the Wheel of Fate. One free turn a day. It keeps no records at all, which I find very upsetting.",
			next = "menu",
		},

		-- "Goodbye."
		goodbye = { text = "Go carefully. I would so hate to write you in red." },
	},
} :: Tree

-- Whispered in a bubble over his head when you step onto the challenges ring (Archivist.client).
DialogueTrees.ArchivistGreetings = {
	"Name, date, door. Everything gets written down.",
	"Mind the cold. It's only me.",
	"Ah. You're on today's page.",
	"Do sign in. Everyone does, eventually.",
	"Your account is in order. Mostly.",
	"Don't mind me. I'm only keeping count.",
	"Back again. I'll make a note of it.",
}

return DialogueTrees
