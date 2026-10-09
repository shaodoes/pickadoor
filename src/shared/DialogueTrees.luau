-- Everything the lobby's characters say, as Dialogue trees (see Dialogue.luau for the node format).
--   DialogueTrees.Librarian   the introduction: nine lines, straight through
--   DialogueTrees.Shopkeeper  Teeth, behind the gift-shop counter: a small menu of questions
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
				{ text = "What are you?", next = "what" },
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

		-- "What are you?"
		what = { text = "The shopkeeper.", next = "before" },
		before = { text = "Before that? The shop was empty. Then it wasn't.", next = "rude" },
		rude = { text = "Don't look at the teeth. Everyone looks at the teeth. It's rude.", next = "menu" },

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

return DialogueTrees
