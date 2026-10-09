--[[
	Daily Reward station panel ("DailyPanel"): the 7-day streak calendar.

	  * Hero row of 7 day cards (day 7 is a bigger treasure card with a drawn chest and its bonus).
	    States (as the old calendar): claimed (earlier days of the run), today (claimable: animated
	    rotating-gradient border, pulsing glow, shine sweep, bobbing TODAY pill), todayClaimed
	    (stamped check + green OPENED pill), future (dimmed with a lock). No data yet: all future.
	  * Streak bar under the cards (fills to the banked streak / 7 with a glowing head, day diamonds
	    light up as it passes them) with a count-up "DAY N OF 7" and the miss-a-day rule.
	  * Big CLAIM button (pulse + shine while claimable; a muted "NEXT IN 5h 12m" countdown otherwise,
	    refreshed by tick()). A "TOMORROW" chip previews the next reward.
	  * Claim: Remotes ClaimDaily in a pcall with a busy guard; on success the card stamps, sparkles
	    burst, keys fly to the header balance chip (which then counts up), the panel flashes gold and
	    the bar fills to the new streak. Errors become toasts.
	  * Studio only: DEBUG +1 DAY / SKIP 2 DAYS buttons in the bottom-left corner.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local Sfx = require(Shared.Sfx)
local UIFx = require(Shared:WaitForChild("UIFx"))
local UIKit = require(Shared.UIKit)

local Common = require(script.Parent.Common)
local Shell = require(script.Parent.Shell)

local Colors, Face = UIKit.Colors, UIKit.Face
local CURRENCY = string.upper(Config.CurrencyName)
local DAYS = #Rewards.Daily
local ACCENT = Rewards.Stations.Daily.color

-- palette for the dark cards
local FACE_BASE = Color3.fromRGB(62, 44, 34)
local FACE_TODAY = Color3.fromRGB(104, 74, 46)
local FACE_CLAIMED = Color3.fromRGB(40, 50, 36)
local CLAIMED_GREEN = Color3.fromRGB(112, 190, 104)
local TRACK = Color3.fromRGB(20, 13, 10)

-- layout (design px inside shell.content, ~812 wide)
local ROW_Y = 12 -- leaves room for the TODAY pill hanging over the cards' top edge
local ROW_H = 206
local BIG_W = 170
local BIG_GAP = 14
local GAP = 10
local SMALL_H = 186
local SMALL_COUNT = DAYS - 1
local STREAK_Y = ROW_Y + ROW_H + 16

type Ctx = {
	gui: ScreenGui,
	getSnapshot: () -> any?,
	toast: (message: string, kind: string?) -> (),
	talkArchivist: () -> (),
}

type DayCard = {
	day: number,
	big: boolean,
	slot: Frame,
	face: Frame,
	stroke: UIStroke,
	dayLabel: TextLabel,
	amount: TextLabel,
	unit: TextLabel,
	keyIcon: Frame?,
	dim: Frame,
	lock: Frame,
	shade: Frame,
	check: Frame,
	state: string,
}

type DailyView = { claimable: boolean, claimedToday: boolean, day: number, streak: number }

local function plusFormat(n: number): string
	return "+" .. tostring(math.round(n))
end

local function dayCountFormat(n: number): string
	return string.format("DAY %d OF %d", math.round(n), DAYS)
end

-- A TextLabel that scales its text to its box, capped at `maxSize`.
local function scaledText(props: { [string]: any }, maxSize: number, minSize: number?): TextLabel
	props.TextScaled = true
	local label = Common.text(props)
	UIKit.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = minSize or 8, Parent = label })
	return label
end

local function darkGradient(): UIGradient
	return UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 138, 128)),
	})
end

-- A little treasure chest drawn with frames (walnut box, brass bands, gold lock plate).
local function chestIcon(parent: Instance, width: number, position: UDim2): Frame
	local h = math.floor(width * 0.78)
	local f = UIKit.new("Frame", {
		Name = "Chest",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = position,
		Size = UDim2.fromOffset(width, h),
		ZIndex = 4,
		Parent = parent,
	})
	local walnut, walnutDark = Color3.fromRGB(128, 82, 48), Color3.fromRGB(88, 54, 32)
	local function piece(color: Color3, x: number, y: number, w: number, hh: number, radius: number?, z: number?)
		local p = UIKit.new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, hh),
			ZIndex = z or 4,
			Parent = f,
		})
		if radius then
			UIKit.corner(radius).Parent = p
		end
		return p
	end
	local lid = piece(walnut, 0, 0, 1, 0.46, math.floor(width * 0.16)) -- domed lid
	UIKit.sheen(0.5).Parent = lid
	piece(walnut, 0, 0.28, 1, 0.18) -- squares off the lid's lower corners
	piece(walnutDark, 0, 0.44, 1, 0.56, 4) -- box
	piece(Common.BRASS, 0, 0.4, 1, 0.07, nil, 5) -- lip band
	piece(Common.BRASS, 0.14, 0, 0.08, 1, 2, 5) -- straps
	piece(Common.BRASS, 0.78, 0, 0.08, 1, 2, 5)
	local plate = piece(Colors.goldBright, 0.39, 0.32, 0.22, 0.3, 3, 6) -- lock plate
	UIKit.stroke(Common.BRASS_DARK, 1.5, 0).Parent = plate
	piece(Colors.ink, 0.475, 0.4, 0.05, 0.12, 2, 7) -- keyhole
	return f
end

local Daily = {}

function Daily.build(ctx: Ctx)
	local shell = Shell.new(ctx.gui, {
		name = "DailyPanel",
		title = "Daily Reward",
		subtitle = "Come back every day to grow your streak",
		accent = ACCENT,
		size = Vector2.new(860, 520),
		icon = "key",
		balance = true,
	})
	local content: Frame = shell.content
	local group = shell.group

	--------------------------------------------------------------------------------------
	-- Day cards
	--------------------------------------------------------------------------------------
	local row = UIKit.new("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, ROW_Y),
		Size = UDim2.new(1, 0, 0, ROW_H),
		Parent = content,
	})
	local smallRow = UIKit.new("Frame", {
		Name = "Week",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(BIG_W + BIG_GAP), 1, 0),
		Parent = row,
	})

	local cards: { DayCard } = {}
	local slots: { GuiObject } = {}

	local function buildDayCard(index: number): DayCard
		local def = Rewards.Daily[index]
		local big = index == DAYS
		local slot: Frame
		if big then
			slot = UIKit.new("Frame", {
				Name = "Day" .. index,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, BIG_W, 1, 0),
				ZIndex = 1,
				Parent = row,
			})
		else
			local i = index - 1
			slot = UIKit.new("Frame", {
				Name = "Day" .. index,
				BackgroundTransparency = 1,
				Position = UDim2.new(i / SMALL_COUNT, i * GAP / SMALL_COUNT, 0, (ROW_H - SMALL_H) / 2),
				Size = UDim2.new(1 / SMALL_COUNT, -(SMALL_COUNT - 1) * GAP / SMALL_COUNT, 0, SMALL_H),
				ZIndex = 1,
				Parent = smallRow,
			})
		end

		local hoverGlow = UIKit.new("Frame", {
			Name = "HoverGlow",
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 14, 1, 14),
			ZIndex = 0,
			Parent = slot,
		}, { UIKit.corner(20) })
		UIKit.shadow(slot, 14, 4, 0.8)
		local face = UIKit.new("Frame", {
			Name = "Face",
			BackgroundColor3 = FACE_BASE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = slot,
		}, { UIKit.corner(14), darkGradient() })
		local stroke = UIKit.stroke(Common.BRASS_DARK, 1.5, 0.5)
		stroke.Parent = face

		local dayLabel = scaledText({
			Name = "DayLabel",
			Text = if big then "DAY " .. index .. "  TREASURE" else "DAY " .. index,
			FontFace = Face.semi,
			TextColor3 = Colors.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(6, if big then 14 else 16),
			Size = UDim2.new(1, -12, 0, 18),
			ZIndex = 3,
			Parent = face,
		}, 16)

		local amount, unit, keyIcon
		if big then
			UIKit.new("Frame", {
				Name = "Halo",
				BackgroundColor3 = ACCENT,
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 68),
				Size = UDim2.fromOffset(88, 88),
				ZIndex = 2,
				Parent = face,
			}, { Common.circle() })
			chestIcon(face, 78, UDim2.new(0.5, 0, 0, 38))
			amount = scaledText({
				Name = "Amount",
				Text = "+" .. def.keys,
				FontFace = Face.bold,
				TextColor3 = Colors.text,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(6, 104),
				Size = UDim2.new(1, -12, 0, 30),
				ZIndex = 3,
				Parent = face,
			}, 28)
			unit = scaledText({
				Name = "Unit",
				Text = CURRENCY,
				FontFace = Face.semi,
				TextColor3 = Colors.muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(6, 133),
				Size = UDim2.new(1, -12, 0, 14),
				ZIndex = 3,
				Parent = face,
			}, 12)
			local extras = {}
			if def.spins then
				table.insert(extras, string.format("+%d FREE SPIN%s", def.spins, if def.spins == 1 then "" else "S"))
			end
			for id, count in def.items or {} do
				table.insert(extras, string.format("+%d %s", count, string.upper(Common.itemName(id))))
			end
			for i, line in extras do
				local chip = UIKit.new("Frame", {
					Name = "Extra" .. i,
					BackgroundColor3 = Colors.shadow,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(12, 152 + (i - 1) * 22),
					Size = UDim2.new(1, -24, 0, 19),
					ZIndex = 3,
					Parent = face,
				}, { UIKit.corner(9) })
				scaledText({
					Name = "Text",
					Text = line,
					FontFace = Face.semi,
					TextColor3 = Colors.goldBright,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromOffset(6, 2),
					Size = UDim2.new(1, -12, 1, -4),
					ZIndex = 3,
					Parent = chip,
				}, 13)
			end
		else
			UIKit.new("Frame", {
				Name = "Halo",
				BackgroundColor3 = ACCENT,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 70),
				Size = UDim2.fromOffset(56, 56),
				ZIndex = 2,
				Parent = face,
			}, { Common.circle() })
			keyIcon = UIKit.icon("key", Colors.gold, 32)
			keyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			keyIcon.Position = UDim2.new(0.5, 0, 0, 70)
			keyIcon.ZIndex = 4
			keyIcon.Parent = face
			amount = scaledText({
				Name = "Amount",
				Text = "+" .. def.keys,
				FontFace = Face.bold,
				TextColor3 = Colors.text,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(4, 106),
				Size = UDim2.new(1, -8, 0, 32),
				ZIndex = 3,
				Parent = face,
			}, 30)
			unit = scaledText({
				Name = "Unit",
				Text = CURRENCY,
				FontFace = Face.semi,
				TextColor3 = Colors.muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(4, 140),
				Size = UDim2.new(1, -8, 0, 14),
				ZIndex = 3,
				Parent = face,
			}, 12)
		end

		-- future: dimmed, with a lock badge
		local dim = UIKit.new("Frame", {
			Name = "Dim",
			BackgroundColor3 = Colors.shadow,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 8,
			Parent = face,
		}, { UIKit.corner(14) })
		local lock = UIKit.new("Frame", {
			Name = "Lock",
			BackgroundColor3 = Colors.ink,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(24, 24),
			Visible = false,
			ZIndex = 9,
			Parent = face,
		}, { Common.circle(), UIKit.stroke(Common.BRASS_DARK, 1.5, 0.3) })
		local lockIcon = UIKit.icon("lock", Colors.muted, 14)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromScale(0.5, 0.5)
		lockIcon.ZIndex = 10
		lockIcon.Parent = lock

		-- claimed: a dark shade and a stamped check medallion
		local shade = UIKit.new("Frame", {
			Name = "Shade",
			BackgroundColor3 = Colors.shadow,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 8,
			Parent = face,
		}, { UIKit.corner(14) })
		local checkSize = if big then 64 else 48
		local check = UIKit.new("Frame", {
			Name = "Check",
			BackgroundColor3 = Colors.green,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, if big then 68 else 70),
			Size = UDim2.fromOffset(checkSize, checkSize),
			Rotation = -10,
			Visible = false,
			ZIndex = 6,
			Parent = slot,
		}, { Common.circle(), UIKit.stroke(Colors.paperLight, 3, 0), UIKit.sheen(0.5) })
		local tick = UIKit.icon("check", Colors.paperLight, math.floor(checkSize * 0.55))
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(0.5, 0.5)
		tick.ZIndex = 7
		tick.Parent = check

		UIFx.hover(slot, { scale = 1.05, glow = hoverGlow })

		return {
			day = index,
			big = big,
			slot = slot,
			face = face,
			stroke = stroke,
			dayLabel = dayLabel,
			amount = amount,
			unit = unit,
			keyIcon = keyIcon,
			dim = dim,
			lock = lock,
			shade = shade,
			check = check,
			state = "",
		}
	end

	for i = 1, DAYS do
		cards[i] = buildDayCard(i)
		slots[i] = cards[i].slot
	end

	-- Today's decorations: one set, moved into whichever card is today.
	local todayGlow = UIKit.new("Frame", {
		Name = "TodayGlow",
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 22, 1, 22),
		ZIndex = 0,
	}, { UIKit.corner(24) })
	local todayRing = UIKit.new("Frame", {
		Name = "TodayRing",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, { UIKit.corner(14) })
	local ringStroke = UIKit.stroke(Color3.new(1, 1, 1), 3, 0)
	ringStroke.Parent = todayRing
	UIFx.spinGradient(
		ringStroke,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Colors.goldBright),
			ColorSequenceKeypoint.new(0.25, ACCENT),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 248, 228)),
			ColorSequenceKeypoint.new(0.75, ACCENT),
			ColorSequenceKeypoint.new(1, Colors.goldBright),
		}),
		group,
		140
	)
	local todayShine = UIKit.new("Frame", {
		Name = "TodayShine",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = cards[1].slot, -- shine() needs a parented object; placeToday() moves it
	}, { UIKit.corner(14) })
	UIFx.shine(todayShine, group, { period = 2.8, color = Colors.goldBright, alpha = 0.55 })
	local pill = scaledText({
		Name = "TodayPill",
		Text = "TODAY",
		FontFace = Face.bold,
		TextColor3 = Colors.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = ACCENT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(70, 22),
		ZIndex = 9,
	}, 14)
	UIKit.corner(11).Parent = pill
	UIKit.stroke(Colors.shadow, 1.5, 0.4).Parent = pill
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 3),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = pill,
	})

	--------------------------------------------------------------------------------------
	-- Streak bar
	--------------------------------------------------------------------------------------
	local streakRow = UIKit.new("Frame", {
		Name = "Streak",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, STREAK_Y),
		Size = UDim2.new(1, 0, 0, 70),
		Parent = content,
	})
	scaledText({
		Name = "Title",
		Text = "YOUR STREAK",
		FontFace = Face.bold,
		TextColor3 = Colors.text,
		Size = UDim2.new(0.5, 0, 0, 20),
		Parent = streakRow,
	}, 18)
	local dayCount = scaledText({
		Name = "DayCount",
		Text = "...",
		FontFace = Face.bold,
		TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.new(0.5, 0, 0, 24),
		Parent = streakRow,
	}, 22)
	local track = UIKit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = TRACK,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, -8, 0, 14),
		Parent = streakRow,
	}, { UIKit.corner(7), UIKit.stroke(Common.BRASS_DARK, 1.5, 0.45) })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
		Parent = track,
	}, {
		UIKit.corner(7),
		UIKit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Common.BRASS_DARK),
				ColorSequenceKeypoint.new(0.6, ACCENT),
				ColorSequenceKeypoint.new(1, Colors.goldBright),
			}),
		}),
	})
	local ticks: { Frame } = {}
	local tickLit: { boolean } = {}
	for i = 1, DAYS do
		ticks[i] = UIKit.new("Frame", {
			Name = "Tick" .. i,
			BackgroundColor3 = Colors.inkSoft,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(i / DAYS, 0.5),
			Size = UDim2.fromOffset(if i == DAYS then 14 else 10, if i == DAYS then 14 else 10),
			Rotation = 45,
			ZIndex = 3,
			Parent = track,
		}, { UIKit.corner(2), UIKit.stroke(Colors.shadow, 1.5, 0.3) })
		tickLit[i] = false
	end
	local head = UIKit.new("Frame", {
		Name = "Head",
		BackgroundColor3 = Colors.goldBright,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		Visible = false,
		ZIndex = 4,
		Parent = track,
	}, { Common.circle() })
	local headGlow = UIKit.stroke(ACCENT, 5, 0.4)
	headGlow.Parent = head
	local rule = scaledText({
		Name = "Rule",
		Text = "Claim every day. Miss one and the streak resets to Day 1.",
		FontFace = Face.serif,
		TextColor3 = Colors.muted,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = streakRow,
	}, 15)

	--------------------------------------------------------------------------------------
	-- Claim button + tomorrow chip + debug
	--------------------------------------------------------------------------------------
	local claimHolder = UIKit.new("Frame", {
		Name = "ClaimHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(360, 62),
		Parent = content,
	})
	local pulseFrame = UIKit.new("Frame", {
		Name = "Pulse",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = claimHolder,
	})
	local claimGlow = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 22, 1, 22),
		ZIndex = 0,
		Parent = pulseFrame,
	}, { UIKit.corner(24) })
	local claimButton = UIKit.button("...", {
		Name = "Claim",
		Size = UDim2.fromScale(1, 1),
		TextSize = 26,
		ZIndex = 1,
		Parent = pulseFrame,
	}, { style = "ink", radius = 16, depth = 4 })
	local claimFace = claimButton:FindFirstChild("Face") :: Frame?

	local tomorrow = UIKit.new("Frame", {
		Name = "Tomorrow",
		BackgroundColor3 = Colors.ink,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -12),
		Size = UDim2.fromOffset(168, 50),
		Visible = false,
		Parent = content,
	}, { UIKit.corner(12), UIKit.stroke(Common.BRASS_DARK, 1.5, 0.4), darkGradient() })
	scaledText({
		Name = "Caption",
		Text = "TOMORROW",
		FontFace = Face.semi,
		TextColor3 = Colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.new(1, -16, 0, 13),
		Parent = tomorrow,
	}, 12)
	local tomorrowKey = UIKit.icon("key", Colors.gold, 18)
	tomorrowKey.AnchorPoint = Vector2.new(0, 0.5)
	tomorrowKey.Position = UDim2.fromOffset(14, 32)
	tomorrowKey.Parent = tomorrow
	local tomorrowAmount = scaledText({
		Name = "Amount",
		Text = "",
		FontFace = Face.bold,
		TextColor3 = Colors.goldBright,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(36, 21),
		Size = UDim2.new(1, -46, 0, 22),
		Parent = tomorrow,
	}, 20)

	Common.debugButton(content, "DEBUG +1 DAY", "nextDay", UDim2.new(0, 0, 1, -38), Vector2.new(0, 1))
	Common.debugButton(content, "SKIP 2 DAYS", "skipDay", UDim2.new(0, 0, 1, -4), Vector2.new(0, 1))

	--------------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------------
	local hasData = false
	local view: DailyView = { claimable = false, claimedToday = false, day = 1, streak = 0 }
	local todayCard: DayCard? = nil
	local renderedClaimable: boolean? = nil
	local barAlpha = 0
	local busy = false
	local stopShine: (() -> ())? = nil
	local stopPulse: (() -> ())? = nil

	-- balance chip: held back while keys are flying so it counts up when they land
	local latestKeys: number? = nil
	local shownKeys: number? = nil
	local holdBalance = false
	local function applyBalance()
		if latestKeys == nil then
			return
		end
		local keys = latestKeys :: number
		shell:setBalance(keys, shownKeys ~= nil and keys > (shownKeys :: number))
		shownKeys = keys
	end

	local function setCardState(card: DayCard, state: string)
		if card.state == state then
			return
		end
		card.state = state
		local today = state == "today"
		local claimed = state == "claimed" or state == "todayClaimed"
		card.face.BackgroundColor3 = if today then FACE_TODAY elseif claimed then FACE_CLAIMED else FACE_BASE
		if today then
			card.stroke.Color = Colors.goldBright
			card.stroke.Thickness = 2
			card.stroke.Transparency = 0
		elseif state == "todayClaimed" then
			card.stroke.Color = CLAIMED_GREEN
			card.stroke.Thickness = 2.5
			card.stroke.Transparency = 0.05
		else
			card.stroke.Color = Common.BRASS_DARK
			card.stroke.Thickness = 1.5
			card.stroke.Transparency = if claimed then 0.35 else 0.55
		end
		card.dayLabel.TextColor3 = if today then Colors.paperLight else Colors.muted
		card.amount.TextColor3 = if today then Colors.goldBright elseif claimed then Colors.muted else Colors.text
		card.unit.TextColor3 = if today then Colors.cream else Colors.muted
		if card.keyIcon then
			Common.tint(card.keyIcon, if today then Colors.goldBright else Colors.gold)
		end
		card.dim.Visible = state == "future"
		card.lock.Visible = state == "future"
		card.shade.Visible = claimed
		card.check.Visible = claimed
		card.slot.ZIndex = if today or state == "todayClaimed" then 2 else 1
	end

	local function placeToday(card: DayCard?, claimedToday: boolean)
		local slot = card and card.slot
		todayGlow.Parent = if slot and not claimedToday then slot else nil
		todayRing.Parent = if slot and not claimedToday then slot else nil
		todayShine.Parent = if slot and not claimedToday then slot else nil
		pill.Parent = slot
		pill.Text = if claimedToday then "OPENED" else "TODAY"
		pill.BackgroundColor3 = if claimedToday then CLAIMED_GREEN else ACCENT
	end

	local function setBar(alpha: number, animate: boolean)
		if math.abs(alpha - barAlpha) < 0.0001 and animate then
			return
		end
		barAlpha = alpha
		if animate then
			UIFx.fill(fill, alpha, 0.8)
		else
			fill.Size = UDim2.fromScale(alpha, 1)
		end
	end

	local function setClaimable(claimable: boolean)
		if renderedClaimable == claimable then
			return
		end
		renderedClaimable = claimable
		if claimable then
			if claimFace and not stopShine then
				stopShine = UIFx.shine(claimFace, group, { period = 2.2, color = Colors.paperLight, alpha = 0.5 })
			end
			if not stopPulse then
				stopPulse = UIFx.pulse(pulseFrame, group, 0.035, 1.4)
			end
		else
			if stopShine then
				stopShine()
				stopShine = nil
			end
			if stopPulse then
				stopPulse()
				stopPulse = nil
			end
			claimGlow.BackgroundTransparency = 1
		end
	end

	local function countdownCaption(): string
		return "NEXT IN " .. Rewards.formatDuration(Rewards.secondsToNextDay())
	end

	local function render(st: DailyView, data: boolean, animateBar: boolean)
		hasData = data
		view = st
		todayCard = nil
		local todayClaimed = false
		for _, card in cards do
			local state
			if data and card.day < st.day then
				state = "claimed"
			elseif data and card.day == st.day then
				state = if st.claimedToday then "todayClaimed" else "today"
			else
				state = "future"
			end
			setCardState(card, state)
			if state == "today" or state == "todayClaimed" then
				todayCard = card
				todayClaimed = state == "todayClaimed"
			end
		end
		placeToday(todayCard, todayClaimed)

		local streak = if not data then 0 elseif st.claimedToday then st.day else st.streak
		setBar(streak / DAYS, animateBar)
		if data then
			UIFx.countUp(dayCount, st.day, st.day, 0, dayCountFormat) -- also cancels a running count
		else
			dayCount.Text = "..."
		end

		local claimable = data and st.claimable
		if claimable then
			Common.restyle(claimButton, string.format("CLAIM DAY %d", st.day), "green", "key", 24)
		else
			Common.restyle(claimButton, if data then countdownCaption() else "...", "ink", nil)
		end
		setClaimable(claimable)

		if data then
			local nextDay = (st.day % DAYS) + 1
			local reward = Rewards.Daily[nextDay]
			tomorrowAmount.Text = if reward.spins or reward.items
				then string.format("+%d + CHEST", reward.keys)
				else "+" .. reward.keys
			tomorrow.Visible = true
		else
			tomorrow.Visible = false
		end
	end

	local function update(snapshot: any?)
		local daily = snapshot and snapshot.Daily
		local st = Rewards.dailyState(daily)
		render(st, snapshot ~= nil, true)

		-- the streak broke (missed a day): say so instead of the plain rule
		local raw = if type(daily) == "table" then tonumber(daily.streak) or 0 else 0
		local last = if type(daily) == "table" then tonumber(daily.lastClaimDay) or -1 else -1
		local broke = snapshot ~= nil
			and st.claimable
			and st.streak == 0
			and raw > 0
			and raw < DAYS
			and last < Rewards.today() - 1
		if broke then
			rule.Text = "You missed a day, so the streak started over. Don't miss tomorrow!"
			rule.TextColor3 = Colors.creamHot
		else
			rule.Text = "Claim every day. Miss one and the streak resets to Day 1."
			rule.TextColor3 = Colors.muted
		end

		local keys = snapshot and tonumber(snapshot.Keys)
		if keys then
			latestKeys = keys
			if not holdBalance then
				applyBalance()
			end
		end
	end

	--------------------------------------------------------------------------------------
	-- Looping motion (only while open)
	--------------------------------------------------------------------------------------
	local lastHeadAlpha = -1
	group:add(function(t: number)
		local card = todayCard
		if card then
			pill.Position = UDim2.new(0.5, 0, 0, -2 + math.sin(t * 3) * 3)
			if card.state == "today" then
				local wave = (math.sin(t * 3.4) + 1) / 2
				todayGlow.BackgroundTransparency = 0.5 + 0.38 * (1 - wave)
			end
		end
		if renderedClaimable then
			local wave = (math.sin(t * 2.8) + 1) / 2
			claimGlow.BackgroundTransparency = 0.55 + 0.35 * (1 - wave)
		end
		-- bar head follows the fill; diamonds light as it passes them
		local alpha = fill.Size.X.Scale
		if alpha ~= lastHeadAlpha then
			lastHeadAlpha = alpha
			head.Visible = alpha > 0.002
			head.Position = UDim2.fromScale(alpha, 0.5)
			for i = 1, DAYS do
				local lit = alpha >= i / DAYS - 0.002
				if lit ~= tickLit[i] then
					tickLit[i] = lit
					ticks[i].BackgroundColor3 = if lit then Colors.goldBright else Colors.inkSoft
				end
			end
		end
		headGlow.Transparency = 0.25 + 0.35 * (math.sin(t * 5) + 1) / 2
	end)

	--------------------------------------------------------------------------------------
	-- Open: staggered reveal, count-ups, bar fills from 0
	--------------------------------------------------------------------------------------
	shell:onOpened(function()
		UIFx.stagger(slots, 0.05, { delay = 0.08, offset = Vector2.new(0, 30), scale = 0.6 })
		UIFx.reveal(streakRow, { delay = 0.42, offset = Vector2.new(0, 16) })
		UIFx.reveal(claimHolder, { delay = 0.5, offset = Vector2.new(0, 20), scale = 0.8 })
		UIFx.reveal(tomorrow, { delay = 0.56, offset = Vector2.new(0, 20) })
		for i, card in cards do
			local keys = Rewards.Daily[i].keys
			card.amount.Text = "+0"
			task.delay(0.08 + i * 0.05, function()
				UIFx.countUp(card.amount, 0, keys, 0.6, plusFormat)
			end)
		end
		-- the bar replays from empty every time
		fill.Size = UDim2.fromScale(0, 1)
		if hasData then
			dayCount.Text = dayCountFormat(0)
			task.delay(0.45, function()
				UIFx.fill(fill, barAlpha, 0.9)
				UIFx.countUp(dayCount, 0, view.day, 0.8, dayCountFormat)
			end)
		end
	end)

	--------------------------------------------------------------------------------------
	-- Claim
	--------------------------------------------------------------------------------------
	local function celebrate(day: number, keys: number)
		local card = cards[day]
		if not card then
			holdBalance = false
			applyBalance()
			return
		end
		-- show it as claimed right away (the DataUpdated snapshot follows)
		render({ claimable = false, claimedToday = true, day = day, streak = day }, true, true)
		UIFx.stamp(card.check)
		UIFx.burst(card.slot, UDim2.fromScale(0.5, 0.4), {
			count = 28,
			colors = { Colors.goldBright, ACCENT, Colors.paperLight },
			spread = 1.2,
		})
		UIFx.flyUp(card.slot, UDim2.fromScale(0.5, 0.1), "+" .. keys, { color = Colors.goldBright, icon = "key" })
		shell:flash(ACCENT, 0.3)
		Sfx.play("Purchase")

		local released = false
		local function release()
			if released then
				return
			end
			released = true
			holdBalance = false
			applyBalance()
		end
		local target = shell:balanceTarget()
		if not target then
			release()
		else
			UIFx.flyTo(shell.frame, card.slot, target, {
				count = 8,
				icon = "key",
				color = Colors.goldBright,
				onArrive = release,
			})
			task.delay(1.6, release) -- in case the flight never lands (panel closed mid-air)
		end
	end

	claimButton.Activated:Connect(function()
		local snapshot = ctx.getSnapshot()
		if busy or not snapshot then
			return
		end
		local st = Rewards.dailyState(snapshot.Daily)
		if not st.claimable or renderedClaimable == false then
			ctx.toast(
				"Already opened today. Come back in " .. Rewards.formatDuration(Rewards.secondsToNextDay()) .. "."
			)
			return
		end
		busy = true
		holdBalance = true -- a DataUpdated during the call waits for the keys to land on the chip
		claimButton.Text = "OPENING..."
		local ok, res = pcall(function()
			return Remotes.get("ClaimDaily"):InvokeServer()
		end)
		busy = false
		if not ok or type(res) ~= "table" or not res.ok then
			holdBalance = false
			update(ctx.getSnapshot())
			ctx.toast(
				if type(res) == "table" and res.message
					then tostring(res.message)
					else "The chest won't budge. Try again.",
				"error"
			)
			return
		end
		local day = tonumber(res.day) or st.day
		local def = Rewards.Daily[day]
		celebrate(day, tonumber(res.keys) or (def and def.keys) or 0)
		task.delay(0.25, function()
			ctx.toast(tostring(res.message), "success")
		end)
	end)

	--------------------------------------------------------------------------------------
	-- StationUI
	--------------------------------------------------------------------------------------
	local function tick()
		if hasData and renderedClaimable == false and not busy then
			claimButton.Text = countdownCaption()
		end
	end

	render(view, false, false)
	update(ctx.getSnapshot())

	return {
		panel = shell.frame,
		update = update,
		tick = tick,
	}
end

return Daily
