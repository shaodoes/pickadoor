--[[
	Challenges station: Mr. Ashby's ledger.

	A dark, ledger-styled panel with a DAILY / WEEKLY segmented switch (sliding accent indicator, a
	claimable-count badge on each tab), a live reset countdown for the selected set, and one card per
	challenge slot: icon tile, title + the archivist's flavour line, an animated progress bar with a
	count-up, reward chips and a CLAIM button that pulses, shines and glows when the line is complete.
	Claimed lines get a stamped LOGGED mark and dim. Claiming bursts sparkles, flies keys to the
	balance chip and stamps the card.

	Logic ported from the old Rewards.client Challenges section: same remote
	(ClaimChallenge(scope, slot) -> { ok, message }), busy guard, toasts and Studio debug button.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local UIFx = require(Shared:WaitForChild("UIFx"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Common = require(script.Parent.Common)
local Shell = require(script.Parent.Shell)

local Colors, Face = UIKit.Colors, UIKit.Face

local ACCENT = Rewards.Stations.Challenges.color
local SPIN_COLOR = Rewards.Stations.Wheel and Rewards.Stations.Wheel.color or Colors.accent
local SERIF_ITALIC =
	Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)

local CREAM = Colors.paper
local CREAM_MUTED = Colors.muted
local INK_DEEP = Color3.fromRGB(20, 14, 12)
local CARD_TOP = Color3.fromRGB(50, 37, 31)
local CARD_BOTTOM = Color3.fromRGB(29, 21, 18)
local TILE_BG = Color3.fromRGB(24, 17, 14)
local TILE_READY = Color3.fromRGB(28, 72, 74)
local CLAIM_FACE = Color3.fromRGB(38, 138, 140)
local WAIT_FACE = Color3.fromRGB(62, 46, 39)
local FILL_DONE = Colors.goldBright
local WHITE = Color3.new(1, 1, 1)

local SCOPES = { "daily", "weekly" }
local SCOPE_LABEL = { daily = "DAILY", weekly = "WEEKLY" }

local TOP_H = 44
local LIST_Y = 56
local FOOTER_H = 32
local CARD_GAP = 10
local TILE = 60
local MID_X = 108
local BTN_W = 132
local BTN_H = 44
local CHIP_W = 112
local RIGHT_W = 16 + BTN_W + 12 + CHIP_W
local STAGGER = 0.07

-- Which icon sits in a card's tile, by the stat the challenge counts.
local STAT_ICON = {
	trials = "lantern",
	rightDoor = "check",
	huntSurvived = "heart",
	speedPills = "pills",
	bandage = "bandage",
	itemsUsed = "cart",
	lockpick = "lockpick",
	laserStun = "laser",
	dailyChest = "key",
	spin = "play",
	talkTeeth = "help",
	talkLibrarian = "help",
	talkArchivist = "help",
}

-- Mr. Ashby's margin notes, by stat.
local STAT_NOTE = {
	trials = "Each door you pass is another line in his book.",
	rightDoor = "He only writes down the right ones.",
	huntSurvived = "Live through it. The ledger needs a witness.",
	speedPills = "Outrun whatever is behind you.",
	bandage = "Patch up. Blood smudges the ink.",
	itemsUsed = "Supplies are for spending, he says.",
	lockpick = "Every lock keeps a story. Pick one.",
	laserStun = "Light is the one thing they fear.",
	dailyChest = "Collect your keep from the daily chest.",
	spin = "The Wheel of Fate keeps its own records.",
	talkTeeth = "Teeth knows things. Ask him.",
	talkLibrarian = "The Librarian rarely speaks. Listen.",
	talkArchivist = "He does love to talk about the ledger.",
}
local DEFAULT_NOTE = string.format("%s is watching this line closely.", Rewards.ArchivistName)

local SPIN_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, ACCENT),
	ColorSequenceKeypoint.new(0.25, WHITE),
	ColorSequenceKeypoint.new(0.5, Colors.goldBright),
	ColorSequenceKeypoint.new(0.75, WHITE),
	ColorSequenceKeypoint.new(1, ACCENT),
})

type Card = {
	scope: string,
	slot: number,
	frame: Frame,
	stroke: UIStroke,
	gradient: UIGradient?,
	tile: Frame,
	tileStroke: UIStroke,
	iconKey: string?,
	entry: TextLabel,
	title: TextLabel,
	note: TextLabel,
	fill: Frame,
	fillGradient: UIGradient,
	count: TextLabel,
	chips: Frame,
	holder: Frame,
	holderGlow: UIStroke,
	button: GuiButton,
	stamp: Frame,
	dim: Frame,
	defId: string?,
	target: number,
	shown: number,
	state: string?,
	busy: boolean,
	localClaimed: string?,
	hovered: boolean,
	stopPulse: (() -> ())?,
	stopShine: (() -> ())?,
	fmt: (n: number) -> string,
	token: number,
}

type List = {
	frame: Frame,
	cards: { Card },
}

type Tab = {
	button: TextButton,
	label: TextLabel,
	badge: Frame,
	badgeText: TextLabel,
	count: number,
}

local function scaled(label: TextLabel, maxSize: number, minSize: number?): TextLabel
	label.TextScaled = true
	UIKit.new("UITextSizeConstraint", {
		MaxTextSize = maxSize,
		MinTextSize = minSize or 8,
		Parent = label,
	})
	return label
end

-- "5h 12m 03s" / "2d 04h 12m" / "4m 09s"
local function formatReset(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %02dh %02dm", d, h, m)
	elseif h > 0 then
		return string.format("%dh %02dm %02ds", h, m, s)
	end
	return string.format("%dm %02ds", m, s)
end

local function secondsLeft(scope: string): number
	return if scope == "weekly" then Rewards.secondsToNextWeek() else Rewards.secondsToNextDay()
end

-- Centre of `obj` in `parent`'s scale space (independent of any UIScale on the way).
local function originIn(parent: GuiObject, obj: GuiObject): UDim2
	local pSize = parent.AbsoluteSize
	if pSize.X <= 0 or pSize.Y <= 0 then
		return UDim2.fromScale(0.5, 0.5)
	end
	local centre = obj.AbsolutePosition + obj.AbsoluteSize / 2 - parent.AbsolutePosition
	return UDim2.fromScale(centre.X / pSize.X, centre.Y / pSize.Y)
end

local function slotOf(snapshot: any, scope: string, index: number): any
	local ch = snapshot and snapshot.Challenges
	local set = type(ch) == "table" and ch[scope]
	local slot = type(set) == "table" and set[index]
	return if type(slot) == "table" then slot else nil
end

local function build(ctx: any)
	local latest: any = nil
	local balanceSeen = false
	local balanceHold = 0
	local current = "daily"
	local tabToken = 0

	local shell: any = Shell.new(ctx.gui, {
		name = "ChallengesPanel",
		title = "Challenges",
		subtitle = Rewards.ArchivistName .. "'s ledger",
		accent = ACCENT,
		size = Vector2.new(820, 550),
		icon = "check",
		balance = true,
	})
	local content: Frame = shell.content
	local group = shell.group

	--------------------------------------------------------------------------------------
	-- Top bar: tab switch, reset timer, TALK
	--------------------------------------------------------------------------------------
	local tabsFrame = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = INK_DEEP,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(300, TOP_H),
		Parent = content,
	}, {
		UIKit.corner(TOP_H // 2),
		UIKit.stroke(ACCENT, 1.5, 0.7),
	})
	local indicator = UIKit.new("Frame", {
		Name = "Indicator",
		BackgroundColor3 = ACCENT,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(0.5, -6, 1, -8),
		ZIndex = 2,
		Parent = tabsFrame,
	}, {
		UIKit.corner((TOP_H - 8) // 2),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 190)),
		}),
	})
	UIFx.glow(indicator, ACCENT, 2, 0.45)

	local INDICATOR_POS = {
		daily = UDim2.fromOffset(4, 4),
		weekly = UDim2.new(0.5, 2, 0, 4),
	}

	local tabs: { [string]: Tab } = {}
	local setTab: (scope: string, animate: boolean) -> ()

	for i, scope in SCOPES do
		local button = UIKit.new("TextButton", {
			Name = "Tab_" .. scope,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale((i - 1) * 0.5, 0),
			Size = UDim2.fromScale(0.5, 1),
			ZIndex = 3,
			Parent = tabsFrame,
		})
		local label = scaled(
			Common.text({
				Name = "Label",
				Text = SCOPE_LABEL[scope],
				FontFace = Face.bold,
				TextColor3 = CREAM_MUTED,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -56, 0, 22),
				ZIndex = 4,
				Parent = button,
			}),
			18,
			10
		)
		local badge = UIKit.new("Frame", {
			Name = "Badge",
			BackgroundColor3 = Colors.goldBright,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			Visible = false,
			ZIndex = 5,
			Parent = button,
		}, {
			Common.circle(),
			UIKit.stroke(Colors.shadow, 1.5, 0.4),
		})
		local badgeText = scaled(
			Common.text({
				Name = "Count",
				Text = "0",
				FontFace = Face.bold,
				TextColor3 = Colors.ink,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
				Parent = badge,
			}),
			13,
			8
		)
		tabs[scope] = { button = button, label = label, badge = badge, badgeText = badgeText, count = 0 }
		button.MouseEnter:Connect(function()
			if current ~= scope then
				Sfx.play("Hover", 0.08)
				UIFx.tween(label, UIFx.Info.fast, { TextColor3 = CREAM })
			end
		end)
		button.MouseLeave:Connect(function()
			if current ~= scope then
				UIFx.tween(label, UIFx.Info.fast, { TextColor3 = CREAM_MUTED })
			end
		end)
		button.Activated:Connect(function()
			if current ~= scope then
				Sfx.play("Click")
				setTab(scope, true)
			end
		end)
	end

	-- Reset timer (live countdown for the selected set) with a little ticking clock.
	local timerFrame = UIKit.new("Frame", {
		Name = "Timer",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(318, 0),
		Size = UDim2.new(1, -(318 + 140), 0, TOP_H),
		Parent = content,
	})
	local clock = UIKit.new("Frame", {
		Name = "Clock",
		BackgroundColor3 = INK_DEEP,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(30, 30),
		Parent = timerFrame,
	}, {
		Common.circle(),
		UIKit.stroke(ACCENT, 2, 0.2),
	})
	UIKit.new("Frame", {
		Name = "Pin",
		BackgroundColor3 = ACCENT,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		ZIndex = 3,
		Parent = clock,
	}, { Common.circle() })
	local hand = UIKit.new("Frame", {
		Name = "Hand",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 20),
		ZIndex = 2,
		Parent = clock,
	})
	UIKit.new("Frame", {
		Name = "Needle",
		BackgroundColor3 = CREAM,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0.5),
		ZIndex = 2,
		Parent = hand,
	})
	local timerCaption = scaled(
		Common.text({
			Name = "Caption",
			Text = "DAILY RESETS IN",
			FontFace = Face.semi,
			TextColor3 = ACCENT,
			Position = UDim2.fromOffset(40, 3),
			Size = UDim2.new(1, -40, 0, 15),
			Parent = timerFrame,
		}),
		13,
		8
	)
	local timerLabel = scaled(
		Common.text({
			Name = "Time",
			Text = "",
			FontFace = Face.bold,
			TextColor3 = CREAM,
			Position = UDim2.fromOffset(40, 18),
			Size = UDim2.new(1, -40, 0, 24),
			Parent = timerFrame,
		}),
		22,
		10
	)

	-- TALK (to the Archivist): closes the ledger and opens his dialogue.
	local talkHolder = UIKit.new("Frame", {
		Name = "TalkHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(124, TOP_H - 4),
		Parent = content,
	})
	local talkButton = UIKit.button("TALK", {
		Name = "Talk",
		Size = UDim2.fromScale(1, 1),
		TextSize = 17,
		Parent = talkHolder,
	}, {
		style = "ink",
		icon = "help",
		iconSize = 16,
		radius = 10,
		depth = 2,
		tooltip = "Talk to " .. Rewards.ArchivistName,
	})
	talkButton:SetAttribute("BaseColor", WAIT_FACE)
	local talkFace = talkButton:FindFirstChild("Face")
	local talkStroke = talkFace and talkFace:FindFirstChildOfClass("UIStroke")
	if talkStroke then
		talkStroke.Color = ACCENT
	end
	talkButton.Activated:Connect(function()
		UIKit.hide(shell.frame)
		ctx.talkArchivist()
	end)

	--------------------------------------------------------------------------------------
	-- Ledger viewport + footer
	--------------------------------------------------------------------------------------
	local viewport = UIKit.new("Frame", {
		Name = "Ledger",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.new(1, 0, 1, -(LIST_Y + FOOTER_H)),
		Parent = content,
	})
	local emptyNote = scaled(
		Common.text({
			Name = "Empty",
			Text = string.format("%s is still sharpening his pencil...", Rewards.ArchivistName),
			FontFace = SERIF_ITALIC,
			TextColor3 = CREAM_MUTED,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -40, 0, 30),
			Visible = false,
			ZIndex = 8,
			Parent = viewport,
		}),
		18,
		10
	)

	local keeper = scaled(
		Common.text({
			Name = "Keeper",
			Text = string.format(
				"Kept by %s, the Archivist. Finish a line, then claim it here.",
				Rewards.ArchivistName
			),
			FontFace = SERIF_ITALIC,
			TextColor3 = CREAM_MUTED,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 4, 1, -2),
			Size = UDim2.new(1, if Common.IS_STUDIO then -140 else -8, 0, 22),
			Parent = content,
		}),
		14,
		9
	)
	Common.debugButton(content, "DEBUG +1 DAY", "nextDay", UDim2.fromScale(1, 1), Vector2.new(1, 1))

	--------------------------------------------------------------------------------------
	-- Cards
	--------------------------------------------------------------------------------------
	local lists: { [string]: List } = {}
	local perSet = Rewards.ChallengesPerSet
	local claim: (card: Card) -> ()

	local function setTileIcon(card: Card, name: string, color: Color3)
		local key = name .. tostring(color)
		if card.iconKey == key then
			return
		end
		card.iconKey = key
		local old = card.tile:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		local glyph = UIKit.icon(name, color, 32)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.ZIndex = 2
		glyph.Parent = card.tile
	end

	local function rewardChip(
		parent: Instance,
		order: number,
		icon: string,
		caption: string,
		iconColor: Color3,
		bg: Color3
	)
		local chip = UIKit.new("Frame", {
			Name = "Reward",
			BackgroundColor3 = bg,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			LayoutOrder = order,
			Parent = parent,
		}, {
			UIKit.corner(12),
			UIKit.stroke(iconColor, 1, 0.65),
			UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10) }),
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local glyph = UIKit.icon(icon, iconColor, 14)
		glyph.LayoutOrder = 1
		glyph.Parent = chip
		Common.text({
			Name = "Amount",
			Text = caption,
			FontFace = Face.bold,
			TextSize = 15,
			TextColor3 = Colors.paperLight,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 24),
			LayoutOrder = 2,
			Parent = chip,
		})
		return chip
	end

	local function rebuildChips(card: Card, def: any)
		for _, child in card.chips:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		rewardChip(card.chips, 1, "key", tostring(def.keys), Colors.goldBright, INK_DEEP)
		if def.spins then
			rewardChip(
				card.chips,
				2,
				"play",
				string.format("+%d SPIN%s", def.spins, if def.spins == 1 then "" else "S"),
				SPIN_COLOR,
				SPIN_COLOR:Lerp(INK_DEEP, 0.72)
			)
		end
		local items = def.items
		if type(items) == "table" then
			local order = 3
			for id, amount in items do
				local item = Items.get(id)
				rewardChip(
					card.chips,
					order,
					item and item.icon or "cart",
					string.format("x%d", tonumber(amount) or 1),
					item and item.color or CREAM,
					INK_DEEP
				)
				order += 1
			end
		end
	end

	local function strokeAlpha(card: Card): number
		local base = if card.state == "ready" then 0.05 elseif card.state == "claimed" then 0.86 else 0.6
		return if card.hovered then math.max(base - 0.3, 0) else base
	end

	local function applyStroke(card: Card, animate: boolean)
		local ready = card.state == "ready"
		local goal = {
			Transparency = strokeAlpha(card),
			Thickness = if ready then 2.5 else 1.5,
		}
		card.stroke.Color = if ready then WHITE else ACCENT
		if animate then
			UIFx.tween(card.stroke, UIFx.Info.fast, goal)
		else
			card.stroke.Transparency = goal.Transparency
			card.stroke.Thickness = goal.Thickness
		end
	end

	local function setReadyFx(card: Card, on: boolean)
		if on then
			if not card.gradient then
				card.gradient = UIFx.spinGradient(card.stroke, SPIN_COLORS, group, 120)
			end
			local gradient = card.gradient
			if gradient then
				gradient.Enabled = true
			end
			card.holderGlow.Transparency = 0.15
			if not card.stopPulse then
				card.stopPulse = UIFx.pulse(card.holder, group, 0.05, 1.1)
			end
			if not card.stopShine then
				local face = card.button:FindFirstChild("Face")
				if face and face:IsA("GuiObject") then
					card.stopShine = UIFx.shine(face, group, { period = 2.4, color = WHITE, alpha = 0.55 })
				end
			end
		else
			local gradient = card.gradient
			if gradient then
				gradient.Enabled = false
			end
			card.holderGlow.Transparency = 1
			local stopPulse, stopShine = card.stopPulse, card.stopShine
			card.stopPulse, card.stopShine = nil, nil
			if stopPulse then
				stopPulse()
			end
			if stopShine then
				stopShine()
			end
		end
	end

	-- Paint a card for its state ("progress" | "ready" | "claimed"); stamps on the way into claimed.
	local function applyState(card: Card, state: string, statIcon: string, animate: boolean)
		local previous = card.state
		card.state = state
		local entryCaption: string
		if state == "claimed" then
			entryCaption = "LOGGED"
			card.tile.BackgroundColor3 = TILE_BG
			card.tileStroke.Transparency = 0.85
			setTileIcon(card, "check", CREAM_MUTED)
			card.title.TextColor3 = CREAM_MUTED
			card.entry.TextColor3 = CREAM_MUTED
			card.holder.Visible = false
			card.stamp.Visible = true
			card.dim.BackgroundTransparency = 0.55
			setReadyFx(card, false)
			if animate and previous ~= nil and previous ~= "claimed" then
				UIFx.stamp(card.stamp)
			end
		elseif state == "ready" then
			entryCaption = "COMPLETE  ·  CLAIM IT"
			card.tile.BackgroundColor3 = TILE_READY
			card.tileStroke.Transparency = 0.1
			setTileIcon(card, statIcon, Colors.goldBright)
			card.title.TextColor3 = Colors.paperLight
			card.entry.TextColor3 = Colors.goldBright
			card.holder.Visible = true
			card.stamp.Visible = false
			card.dim.BackgroundTransparency = 1
			Common.restyle(card.button, "CLAIM", "green", "key", 18)
			card.button:SetAttribute("BaseColor", CLAIM_FACE)
			setReadyFx(card, true)
		else
			entryCaption = "IN PROGRESS"
			card.tile.BackgroundColor3 = TILE_BG
			card.tileStroke.Transparency = 0.55
			setTileIcon(card, statIcon, ACCENT)
			card.title.TextColor3 = CREAM
			card.entry.TextColor3 = ACCENT
			card.holder.Visible = true
			card.stamp.Visible = false
			card.dim.BackgroundTransparency = 1
			Common.restyle(card.button, "NOT YET", "ink", "lock", 16)
			card.button:SetAttribute("BaseColor", WAIT_FACE)
			setReadyFx(card, false)
		end
		card.entry.Text = string.format("ENTRY %02d  ·  %s", card.slot, entryCaption)
		card.fillGradient.Color = if state == "progress"
			then ColorSequence.new(ACCENT:Lerp(WHITE, 0.25), ACCENT)
			else ColorSequence.new(FILL_DONE, Colors.gold)
		applyStroke(card, animate)
	end

	local function setProgress(card: Card, progress: number, animate: boolean)
		local from = card.shown
		card.shown = progress
		local alpha = if card.target > 0 then progress / card.target else 0
		if animate and from ~= progress then
			card.token += 1
			UIFx.fill(card.fill, alpha, 0.6)
			UIFx.countUp(card.count, from, progress, 0.6, card.fmt)
		else
			card.fill.Size = UDim2.fromScale(alpha, 1)
			card.count.Text = card.fmt(progress)
		end
	end

	local function render(card: Card, slot: any, animate: boolean)
		local def = slot and Rewards.challenge(slot.id)
		card.frame.Visible = def ~= nil
		if not def then
			card.defId = nil
			card.state = nil
			setReadyFx(card, false)
			return
		end
		local fresh = card.defId ~= def.id
		if fresh then
			card.defId = def.id
			card.target = def.target
			card.shown = 0
			card.title.Text = def.text
			card.note.Text = STAT_NOTE[def.stat] or DEFAULT_NOTE
			rebuildChips(card, def)
		end
		if slot.claimed == true then
			card.localClaimed = nil -- the server has caught up with our optimistic stamp
		end
		local progress = math.min(tonumber(slot.progress) or 0, def.target)
		local claimed = slot.claimed == true or card.localClaimed == def.id
		local state = if claimed then "claimed" elseif progress >= def.target then "ready" else "progress"
		setProgress(card, progress, animate and not fresh)
		if state ~= card.state or fresh then
			applyState(card, state, STAT_ICON[def.stat] or "key", animate and not fresh)
		end
	end

	local function buildCard(list: List, scope: string, index: number): Card
		local frame = UIKit.new("Frame", {
			Name = string.format("%s%d", scope, index),
			BackgroundColor3 = WHITE,
			Position = UDim2.new(0, 0, (index - 1) / perSet, (index - 1) * CARD_GAP / perSet),
			Size = UDim2.new(1, 0, 1 / perSet, -CARD_GAP * (perSet - 1) / perSet),
			Parent = list.frame,
		}, {
			UIKit.corner(14),
			UIKit.new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(CARD_TOP, CARD_BOTTOM),
			}),
		})
		local stroke = UIFx.glow(frame, ACCENT, 1.5, 0.6)

		-- the ledger margin: a faint double rule between the tile and the entry
		for r = 0, 1 do
			UIKit.new("Frame", {
				Name = "Rule",
				BackgroundColor3 = ACCENT,
				BackgroundTransparency = 0.78,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 91 + r * 4, 0.5, 0),
				Size = UDim2.new(0, 1, 1, -22),
				Parent = frame,
			})
		end

		local tile = UIKit.new("Frame", {
			Name = "Tile",
			BackgroundColor3 = TILE_BG,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			Size = UDim2.fromOffset(TILE, TILE),
			Parent = frame,
		}, { UIKit.corner(14) })
		local tileStroke = UIKit.stroke(ACCENT, 1.5, 0.55)
		tileStroke.Parent = tile

		local mid = UIKit.new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(MID_X, 0),
			Size = UDim2.new(1, -(MID_X + RIGHT_W + 8), 1, 0),
			Parent = frame,
		})
		local entry = scaled(
			Common.text({
				Name = "Entry",
				Text = "",
				FontFace = Face.semi,
				TextColor3 = ACCENT,
				Position = UDim2.fromScale(0, 0.1),
				Size = UDim2.fromScale(1, 0.15),
				Parent = mid,
			}),
			13,
			8
		)
		local title = scaled(
			Common.text({
				Name = "Title",
				Text = "",
				FontFace = Face.bold,
				TextColor3 = CREAM,
				Position = UDim2.fromScale(0, 0.25),
				Size = UDim2.fromScale(1, 0.27),
				Parent = mid,
			}),
			22,
			12
		)
		local note = scaled(
			Common.text({
				Name = "Note",
				Text = "",
				FontFace = SERIF_ITALIC,
				TextColor3 = CREAM_MUTED,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromScale(0, 0.53),
				Size = UDim2.fromScale(1, 0.2),
				Parent = mid,
			}),
			13,
			8
		)
		local track = UIKit.new("Frame", {
			Name = "Progress",
			BackgroundColor3 = INK_DEEP,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.84),
			Size = UDim2.new(1, -76, 0, 10),
			Parent = mid,
		}, { UIKit.corner(5), UIKit.stroke(ACCENT, 1, 0.75) })
		local fill = UIKit.new("Frame", {
			Name = "Fill",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			Parent = track,
		}, { UIKit.corner(5) })
		local fillGradient = UIKit.new("UIGradient", {
			Color = ColorSequence.new(ACCENT:Lerp(WHITE, 0.25), ACCENT),
			Parent = fill,
		})
		local count = scaled(
			Common.text({
				Name = "Count",
				Text = "",
				FontFace = Face.bold,
				TextColor3 = CREAM,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.84),
				Size = UDim2.fromOffset(68, 20),
				Parent = mid,
			}),
			17,
			9
		)

		local chips = UIKit.new("Frame", {
			Name = "Rewards",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(16 + BTN_W + 12), 0.5, 0),
			Size = UDim2.new(0, CHIP_W, 1, -14),
			Parent = frame,
		}, {
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})

		local holder = UIKit.new("Frame", {
			Name = "ClaimHolder",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(BTN_W, BTN_H),
			Parent = frame,
		}, { UIKit.corner(12) })
		local holderGlow = UIKit.stroke(ACCENT, 3, 1)
		holderGlow.Parent = holder
		local button = UIKit.button("NOT YET", {
			Name = "Claim",
			Size = UDim2.fromScale(1, 1),
			TextSize = 18,
			Parent = holder,
		}, { style = "ink", icon = "lock", iconSize = 16, radius = 10 })

		local stamp = UIKit.new("Frame", {
			Name = "Stamp",
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.88,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -(16 + BTN_W / 2), 0.5, 0),
			Size = UDim2.fromOffset(BTN_W - 8, BTN_H),
			Rotation = -8,
			Visible = false,
			ZIndex = 7,
			Parent = frame,
		}, {
			UIKit.corner(8),
			UIKit.stroke(ACCENT, 2.5, 0.05),
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local stampIcon = UIKit.icon("check", ACCENT, 20)
		stampIcon.LayoutOrder = 1
		stampIcon.ZIndex = 7
		stampIcon.Parent = stamp
		Common.text({
			Name = "Label",
			Text = "LOGGED",
			FontFace = Face.bold,
			TextSize = 21,
			TextColor3 = ACCENT,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 26),
			LayoutOrder = 2,
			ZIndex = 7,
			Parent = stamp,
		})

		local dim = UIKit.new("Frame", {
			Name = "Dim",
			BackgroundColor3 = Colors.shadow,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = frame,
		}, { UIKit.corner(14) })

		local card: Card
		card = {
			scope = scope,
			slot = index,
			frame = frame,
			stroke = stroke,
			gradient = nil,
			tile = tile,
			tileStroke = tileStroke,
			iconKey = nil,
			entry = entry,
			title = title,
			note = note,
			fill = fill,
			fillGradient = fillGradient,
			count = count,
			chips = chips,
			holder = holder,
			holderGlow = holderGlow,
			button = button,
			stamp = stamp,
			dim = dim,
			defId = nil,
			target = 1,
			shown = 0,
			state = nil,
			busy = false,
			localClaimed = nil,
			hovered = false,
			stopPulse = nil,
			stopShine = nil,
			fmt = function(n: number): string
				return string.format("%d / %d", math.floor(n + 0.5), card.target)
			end,
			token = 0,
		}

		UIFx.hover(frame, {
			scale = 1.015,
			onEnter = function()
				card.hovered = true
				applyStroke(card, true)
			end,
			onLeave = function()
				card.hovered = false
				applyStroke(card, true)
			end,
		})
		button.Activated:Connect(function()
			claim(card)
		end)
		return card
	end

	for _, scope in SCOPES do
		local frame = UIKit.new("Frame", {
			Name = "List_" .. scope,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = scope == current,
			Parent = viewport,
		}, {
			-- room for the hover lift and the glow strokes inside the clipped viewport
			UIKit.new("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 5),
			}),
		})
		local list: List = { frame = frame, cards = {} }
		for i = 1, perSet do
			table.insert(list.cards, buildCard(list, scope, i))
		end
		lists[scope] = list
	end

	--------------------------------------------------------------------------------------
	-- Tabs, timer, reveals
	--------------------------------------------------------------------------------------
	local function claimableCount(scope: string): number
		local n = 0
		for i = 1, perSet do
			local slot = slotOf(latest, scope, i)
			local card = lists[scope] and lists[scope].cards[i]
			if slot and Rewards.slotClaimable(slot) and not (card and card.localClaimed == slot.id) then
				n += 1
			end
		end
		return n
	end

	local function updateTabs(animate: boolean)
		for _, scope in SCOPES do
			local tab = tabs[scope]
			local n = claimableCount(scope)
			local grew = n > tab.count
			tab.count = n
			tab.badge.Visible = n > 0
			tab.badgeText.Text = tostring(n)
			if animate and grew and n > 0 then
				UIFx.reveal(tab.badge, { offset = Vector2.zero, scale = 0.3, duration = 0.45 })
			end
		end
	end

	local function updateEmpty()
		local any = false
		for _, card in lists[current].cards do
			if card.frame.Visible then
				any = true
				break
			end
		end
		emptyNote.Visible = not any
	end

	local function updateTimer()
		local left = secondsLeft(current)
		timerLabel.Text = formatReset(left)
		hand.Rotation = (60 - math.floor(left) % 60) * 6
	end

	-- Refill a card's bar from empty (on reveal), after `delay` seconds.
	local function refill(card: Card, delay: number)
		card.token += 1
		local token = card.token
		local target = card.shown
		card.fill.Size = UDim2.fromScale(0, 1)
		card.count.Text = card.fmt(0)
		task.delay(delay, function()
			if card.token ~= token then
				return
			end
			UIFx.fill(card.fill, if card.target > 0 then target / card.target else 0, 0.7)
			if target > 0 then
				UIFx.countUp(card.count, 0, target, 0.7, card.fmt)
			end
		end)
	end

	local function revealCards(scope: string, dir: number, delay: number)
		local shown: { GuiObject } = {}
		local cards: { Card } = {}
		for _, card in lists[scope].cards do
			if card.frame.Visible then
				table.insert(shown, card.frame)
				table.insert(cards, card)
			end
		end
		UIFx.stagger(shown, STAGGER, {
			delay = delay,
			offset = if dir == 0 then Vector2.new(0, 22) else Vector2.new(dir * 70, 0),
			scale = 0.92,
		})
		for i, card in cards do
			refill(card, delay + (i - 1) * STAGGER + 0.15)
		end
	end

	setTab = function(scope: string, animate: boolean)
		local previous = current
		current = scope
		tabToken += 1
		local token = tabToken
		local dir = if scope == "weekly" then 1 else -1

		if animate then
			UIFx.tween(indicator, UIFx.Info.spring, { Position = INDICATOR_POS[scope] })
		else
			indicator.Position = INDICATOR_POS[scope]
		end
		for s, tab in tabs do
			local goal = { TextColor3 = if s == scope then Colors.shadow else CREAM_MUTED }
			if animate then
				UIFx.tween(tab.label, UIFx.Info.fast, goal)
			else
				tab.label.TextColor3 = goal.TextColor3
			end
		end
		timerCaption.Text = SCOPE_LABEL[scope] .. " RESETS IN"

		for s, list in lists do
			if s == scope then
				list.frame.Visible = true
				list.frame.Position = UDim2.new()
			elseif animate and s == previous and previous ~= scope then
				local frame = list.frame
				UIFx.tween(frame, UIFx.Info.smooth, { Position = UDim2.fromScale(-dir * 0.6, 0) })
				task.delay(0.3, function()
					if tabToken == token then
						frame.Visible = false
						frame.Position = UDim2.new()
					end
				end)
			else
				list.frame.Visible = false
				list.frame.Position = UDim2.new()
			end
		end
		if animate then
			revealCards(scope, dir, 0.04)
		end
		updateTimer()
		updateEmpty()
	end

	local function defaultScope(): string
		if claimableCount("daily") > 0 then
			return "daily"
		elseif claimableCount("weekly") > 0 then
			return "weekly"
		end
		return "daily"
	end

	shell:onOpened(function()
		setTab(defaultScope(), false)
		UIFx.stagger({ tabsFrame, timerFrame, talkHolder }, 0.06, { offset = Vector2.new(0, -14), scale = 0.9 })
		revealCards(current, 0, 0.12)
		UIFx.reveal(keeper, { delay = 0.3, offset = Vector2.new(0, 10), scale = 1 })
	end)

	--------------------------------------------------------------------------------------
	-- Data
	--------------------------------------------------------------------------------------
	local function setBalanceFromLatest(animate: boolean)
		local keys = latest and tonumber(latest.Keys)
		if keys then
			shell:setBalance(keys, animate and balanceSeen)
			balanceSeen = true
		end
	end

	local function update(snapshot: any?)
		latest = snapshot
		local open = UIKit.isOpen(shell.frame)
		for scope, list in lists do
			for _, card in list.cards do
				if not card.busy then
					render(card, slotOf(snapshot, scope, card.slot), open)
				end
			end
		end
		updateTabs(open)
		updateEmpty()
		if balanceHold == 0 then
			setBalanceFromLatest(open)
		end
	end

	-- Keys arrive at the chip: let it count up to the (by now) updated balance.
	local function releaseBalance()
		balanceHold = math.max(balanceHold - 1, 0)
		if balanceHold == 0 then
			setBalanceFromLatest(true)
		end
	end

	local function celebrate(card: Card, def: any)
		local panel: GuiObject = shell.frame
		local origin = originIn(panel, card.holder)
		Sfx.play("Purchase", 0.04)
		UIFx.burst(panel, origin, {
			count = 26,
			colors = { ACCENT, Colors.goldBright, CREAM },
			spread = 150,
		})
		shell:flash(ACCENT, 0.12)
		UIFx.flyUp(panel, origin, "+" .. tostring(def.keys), { color = Colors.goldBright, icon = "key" })
		if def.spins then
			task.delay(0.25, function()
				UIFx.flyUp(panel, origin, string.format("+%d SPIN", def.spins), { color = SPIN_COLOR, icon = "play" })
			end)
		end
		local target = shell:balanceTarget()
		if target then
			balanceHold += 1
			local released = false
			local function release()
				if not released then
					released = true
					releaseBalance()
				end
			end
			UIFx.flyTo(panel, card.holder, target, {
				count = 6,
				icon = "key",
				color = Colors.goldBright,
				onArrive = release,
			})
			task.delay(1.6, release) -- never leave the chip frozen if the flight is cut short
		end
	end

	claim = function(card: Card)
		local scope, index = card.scope, card.slot
		local slot = slotOf(latest, scope, index)
		local def = slot and Rewards.challenge(slot.id)
		if card.busy or not slot or not def then
			return
		end
		if slot.claimed or card.localClaimed == def.id then
			ctx.toast("Already paid out.")
			return
		elseif not Rewards.slotClaimable(slot) then
			Sfx.play("Error")
			UIFx.shake(card.frame, 4, 0.25)
			ctx.toast(string.format("Not yet: %d / %d.", tonumber(slot.progress) or 0, def.target))
			return
		end
		card.busy = true
		card.button.Text = "..."
		local ok, res = pcall(function()
			return Remotes.get("ClaimChallenge"):InvokeServer(scope, index)
		end)
		card.busy = false
		if not ok or type(res) ~= "table" or not res.ok then
			Sfx.play("Error")
			ctx.toast(
				if type(res) == "table" then tostring(res.message) else "The ledger won't open. Try again.",
				"error"
			)
			render(card, slotOf(latest, scope, index), UIKit.isOpen(shell.frame))
			if card.state == "ready" then
				card.button.Text = "CLAIM"
			end
			return
		end
		card.localClaimed = def.id
		celebrate(card, def)
		render(card, slotOf(latest, scope, index) or slot, UIKit.isOpen(shell.frame))
		updateTabs(false)
		task.delay(0.2, function()
			ctx.toast(tostring(res.message), "success")
		end)
	end

	local function tick()
		if UIKit.isOpen(shell.frame) then
			updateTimer()
		end
	end

	setTab(current, false)
	update(ctx.getSnapshot())

	return {
		panel = shell.frame,
		update = update,
		tick = tick,
	}
end

return { build = build }
