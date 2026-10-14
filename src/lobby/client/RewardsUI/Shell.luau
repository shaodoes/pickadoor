--[[
	Shell: the dark "station panel" every reward station (Daily / Wheel / Challenges) is built in.

	  local shell = Shell.new(ctx.gui, {
	  	name = "DailyPanel", title = "Daily Reward", subtitle = "Come back every day",
	  	accent = Rewards.Stations.Daily.color, size = Vector2.new(820, 500), icon = "key", balance = true,
	  })
	  shell.frame    the panel Frame (works with UIKit.show / hide / isOpen / toggle and the "Open" attribute)
	  shell.content  transparent Frame under the header: size.X - 48 wide, size.Y - 108 tall (24 px side
	                 insets, 16 px top/bottom), e.g. 820x500 -> 772x392
	  shell.header   the header Frame (76 px tall)
	  shell.group    UIFx.Group, active only while the panel is open (or still closing); put loops here
	  shell.accent   the accent Color3
	  shell:onOpened(fn)   fn runs (task.spawn) every time the panel opens, right after the entrance starts
	  shell:onClosed(fn)   fn runs every time the panel starts closing (Open turns false)
	  shell:setBalance(keys, animate?)   the header Keys chip (count-up + pulse when it rises); no-op without balance
	  shell:balanceTarget()              the chip (a UIFx.flyTo target), nil without balance
	  shell:shake(intensity?, duration?) / shell:flash(color?, strength?)

	Look: a sheet with a charcoal-to-ink glass gradient (UIKit's dark theme), a brass stroke whose gradient slowly turns (with an
	accent-tinted highlight), a soft accent glow around it, a slowly drifting accent haze inside, and a
	header with a medallion, title, subtitle, Keys chip (with a spinning 3D key), a round close button and an accent rule with a
	travelling highlight.

	Motion: UIKit.show pops the "Fit" UIScale (registered with UIKit.registerPanel) and plays PanelOpen; on
	top of that the "Stage" (everything inside the frame) slides up 30 px, the glow fades in and the header
	pieces + rule stagger in. Closing: UIKit.hide shrinks the scale; the stage dips and the glow fades. The
	stage is deliberately NOT named "Body" (UIKit.show would slide that too) and is not a CanvasGroup.

	Hierarchy (ZIndex is per-sibling: the gui uses ZIndexBehavior.Sibling):
	  frame (ZIndex 5) > Fit (UIScale), Stage > Glow1..3 (0), Shadow (1), Sheet (2) >
	    Aura (1), TopLight (1), Trim (2), Header (3), Content (3)
	  Effects UIFx adds on top: FxShine 20, FxFlash 45, FxConfetti 48, FxBurst 50, FxFlyUp 55, FxFlyTo 60.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI3D = require(Shared.UI3D)
local UIKit = require(Shared.UIKit)
local UIFx = require(Shared.UIFx)

local Colors, Face = UIKit.Colors, UIKit.Face

local HEADER = 76
local RADIUS = 18
local INSET = 24
local TEXT_X = 98 -- title/subtitle left edge (right of the medallion)

local WOOD = Color3.fromRGB(32, 36, 48) -- (top of the sheet's gradient: cool charcoal now, the name stuck)
local INK = Color3.fromRGB(10, 12, 17)
local BRASS = Colors.gold
local BRASS_DARK = Color3.fromRGB(150, 112, 56)
local BRASS_LIGHT = Color3.fromRGB(240, 206, 140)
local CREAM = Colors.paper
local WHITE = Color3.new(1, 1, 1)
local CHIP = Colors.ink
local CHIP_HOT = Color3.fromRGB(104, 78, 36)
local CHIP_COOL = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local SERIF_ITALIC =
	Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)

local SLIDE_IN = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local GLOW_IN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.08)
local GLOW_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RULE_IN = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.2)

-- soft halo layers around the sheet: grow (px), transparency at rest, corner radius
local GLOWS = {
	{ grow = 56, alpha = 0.94, radius = RADIUS + 28 },
	{ grow = 26, alpha = 0.88, radius = RADIUS + 13 },
	{ grow = 8, alpha = 0.8, radius = RADIUS + 4 },
}

local Shell = {}
Shell.__index = Shell
Shell.HEADER = HEADER

export type Options = {
	name: string?,
	title: string,
	subtitle: string?,
	accent: Color3?,
	size: Vector2?,
	icon: string?,
	balance: boolean?,
}

export type Shell = typeof(setmetatable(
	{} :: {
		frame: Frame,
		content: Frame,
		header: Frame,
		group: UIFx.Group,
		accent: Color3,
		_stage: Frame,
		_sheet: Frame,
		_chip: Frame?,
		_amount: TextLabel?,
		_key: UI3D.Spinner?,
		_balance: number?,
		_opened: { () -> () },
		_closed: { () -> () },
	},
	Shell
))

local function circle(): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local function fadeEnds(edge: number, alpha: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge, alpha),
		NumberSequenceKeypoint.new(1 - edge, alpha),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- The round medallion: accent halo (breathing while open), dark disc with an accent ring, the icon.
local function buildMedallion(header: Frame, accent: Color3, iconName: string?, group: UIFx.Group): Frame
	local holder = UIKit.new("Frame", {
		Name = "Medallion",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(INSET + 30, HEADER / 2),
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 4,
		Parent = header,
	})
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 1,
		Parent = holder,
	}, { circle() })
	UIFx.pulse(halo, group, 0.08, 2.4)

	local disc = UIKit.new("Frame", {
		Name = "Disc",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 2,
		Parent = holder,
	}, {
		circle(),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(44, 50, 66), INK) }),
		UIKit.new("UIStroke", { Color = accent, Thickness = 2, Transparency = 0.05 }),
	})
	UIKit.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(42, 42),
		Parent = disc,
	}, {
		circle(),
		UIKit.new("UIStroke", { Color = BRASS, Thickness = 1, Transparency = 0.55 }),
	})
	if iconName then
		local icon = UIKit.icon(iconName, accent:Lerp(WHITE, 0.4), 26)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 2
		icon.Parent = disc
	else
		UIKit.new("Frame", {
			Name = "Gem",
			BackgroundColor3 = accent:Lerp(WHITE, 0.3),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 14),
			Rotation = 45,
			ZIndex = 2,
			Parent = disc,
		}, { UIKit.corner(3) })
	end
	return holder
end

-- Modern round close button: dark disc, brass ring, the cross turns a quarter on hover.
local function buildClose(header: Frame, frame: Frame): TextButton
	local button = UIKit.new("TextButton", {
		Name = "Close",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Colors.inkSoft,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -(INSET + 20), 0, HEADER / 2),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 4,
		Parent = header,
	}, { circle() })
	local stroke = UIKit.new("UIStroke", {
		Color = BRASS,
		Thickness = 1.5,
		Transparency = 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	local icon = UIKit.icon("close", CREAM, 14)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = button

	UIFx.hover(button, {
		scale = 1.1,
		stroke = stroke,
		onEnter = function()
			UIFx.tween(icon, UIFx.Info.spring, { Rotation = 90 })
			UIFx.tween(button, UIFx.Info.fast, { BackgroundColor3 = Color3.fromRGB(50, 56, 72) })
		end,
		onLeave = function()
			UIFx.tween(icon, UIFx.Info.smooth, { Rotation = 0 })
			UIFx.tween(button, UIFx.Info.fast, { BackgroundColor3 = Colors.inkSoft })
		end,
	})
	button.Activated:Connect(function()
		UIKit.hide(frame)
	end)
	return button
end

-- The Keys balance pill: a spinning 3D key + amount.
local function buildChip(header: Frame): (Frame, TextLabel, UI3D.Spinner)
	local chip = UIKit.new("Frame", {
		Name = "Balance",
		BackgroundColor3 = CHIP,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(INSET + 56), 0, HEADER / 2),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		ZIndex = 4,
		Parent = header,
	}, {
		circle(),
		UIKit.new("UIStroke", {
			Color = BRASS,
			Thickness = 1.5,
			Transparency = 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 16) }),
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local key = UI3D.key(chip, 30, { speed = 1.2, zIndex = 5 })
	key.viewport.LayoutOrder = 1
	local amount = UIKit.new("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		Text = "0",
		FontFace = Face.bold,
		TextSize = 22,
		TextColor3 = Colors.goldBright,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = 2,
		Parent = chip,
	})
	return chip, amount, key
end

function Shell.new(gui: ScreenGui, opts: Options): Shell
	local accent = opts.accent or BRASS
	local size = opts.size or Vector2.new(820, 500)
	local group = UIFx.group()

	local frame = UIKit.new("Frame", {
		Name = opts.name or (opts.title .. "Panel"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44), -- a little high: the PICK A DOOR pill sits under it
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	})
	frame:SetAttribute("Open", false)
	UIKit.registerPanel(frame)

	local stage = UIKit.new("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	UIFx.setRest(stage, UDim2.new())

	-- accent glow (hidden until the entrance fades it in)
	local glows: { Frame } = {}
	for i, spec in GLOWS do
		glows[i] = UIKit.new("Frame", {
			Name = "Glow" .. i,
			BackgroundColor3 = accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			ZIndex = 0,
			Parent = stage,
		}, { UIKit.corner(spec.radius) })
	end
	local shadow = UIKit.shadow(stage, RADIUS, 10, 0.9)
	shadow.ZIndex = 1

	-- the sheet: warm wood fading to ink, brass trim with a slowly turning highlight
	local sheet = UIKit.new("Frame", {
		Name = "Sheet",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = stage,
	}, {
		UIKit.corner(RADIUS),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WOOD, INK) }),
	})
	local trim = UIKit.new("UIStroke", {
		Color = WHITE,
		Thickness = 2,
		Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = sheet,
	})
	UIFx.spinGradient(
		trim,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, BRASS_DARK),
			ColorSequenceKeypoint.new(0.2, BRASS_LIGHT),
			ColorSequenceKeypoint.new(0.4, BRASS_DARK),
			ColorSequenceKeypoint.new(0.7, accent:Lerp(BRASS_LIGHT, 0.3)),
			ColorSequenceKeypoint.new(1, BRASS_DARK),
		}),
		group,
		24
	)

	-- a faint accent haze drifting slowly across the sheet
	local aura = UIKit.new("Frame", {
		Name = "Aura",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = sheet,
	}, { UIKit.corner(RADIUS) })
	local auraGradient = UIKit.new("UIGradient", {
		Rotation = 30,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = aura,
	})
	group:add(function(t)
		auraGradient.Rotation = 30 + t * 9
		auraGradient.Offset = Vector2.new(math.sin(t * 0.21) * 0.25, math.cos(t * 0.17) * 0.2)
	end)

	-- the header catches a little light; a fine cream inner trim gives the edge some depth
	UIKit.new("Frame", {
		Name = "TopLight",
		BackgroundColor3 = CREAM,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, HEADER + 20),
		ZIndex = 1,
		Parent = sheet,
	}, {
		UIKit.corner(RADIUS),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0.94, 1),
		}),
	})
	UIKit.new("Frame", {
		Name = "Trim",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10),
		ZIndex = 2,
		Parent = sheet,
	}, {
		UIKit.corner(RADIUS - 5),
		UIKit.new("UIStroke", { Color = CREAM, Thickness = 1, Transparency = 0.92 }),
	})

	-- header ---------------------------------------------------------------------------
	local header = UIKit.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER),
		ZIndex = 3,
		Parent = sheet,
	})
	local medallion = buildMedallion(header, accent, opts.icon, group)
	local rightReserve = opts.balance and 250 or 84

	local title = UIKit.new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = string.upper(opts.title),
		FontFace = Face.bold,
		TextSize = 30,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(TEXT_X, if opts.subtitle then 10 else (HEADER - 34) / 2),
		Size = UDim2.new(1, -(TEXT_X + rightReserve), 0, 34),
		ZIndex = 4,
		Parent = header,
	}, {
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(CREAM, CREAM:Lerp(BRASS_LIGHT, 0.55)) }),
	})
	local revealed: { GuiObject } = { medallion, title }

	if opts.subtitle then
		table.insert(
			revealed,
			UIKit.new("TextLabel", {
				Name = "Subtitle",
				BackgroundTransparency = 1,
				Text = opts.subtitle,
				FontFace = SERIF_ITALIC,
				TextSize = 14,
				TextColor3 = CREAM:Lerp(accent, 0.4),
				TextTransparency = 0.15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(TEXT_X + 1, 46),
				Size = UDim2.new(1, -(TEXT_X + rightReserve), 0, 18),
				ZIndex = 4,
				Parent = header,
			})
		)
	end

	local chip, amount, key = nil, nil, nil
	if opts.balance then
		chip, amount, key = buildChip(header)
		table.insert(revealed, chip)
	end
	table.insert(revealed, buildClose(header, frame))

	local rule = UIKit.new("Frame", {
		Name = "Rule",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, -INSET * 2, 0, 2),
		ZIndex = 4,
		Parent = header,
	}, { UIKit.new("UIGradient", { Transparency = fadeEnds(0.12, 0.2) }) })
	UIKit.new("Frame", {
		Name = "RuleGlow",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -1),
		Size = UDim2.new(1, -160, 0, 10),
		ZIndex = 3,
		Parent = header,
	}, { UIKit.corner(5), UIKit.new("UIGradient", { Transparency = fadeEnds(0.2, 0) }) })
	UIFx.shine(rule, group, { period = 3.4, width = 0.12, alpha = 0.9, color = WHITE })

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(INSET, HEADER + 16),
		Size = UDim2.new(1, -INSET * 2, 1, -(HEADER + 32)),
		ZIndex = 3,
		Parent = sheet,
	})

	local self = setmetatable({
		frame = frame,
		content = content,
		header = header,
		group = group,
		accent = accent,
		_stage = stage,
		_sheet = sheet,
		_chip = chip,
		_amount = amount,
		_key = key,
		_balance = nil,
		_opened = {},
		_closed = {},
	}, Shell) :: Shell

	-- open / close -------------------------------------------------------------------------
	local function entrance()
		group:setActive(true)
		stage.Position = UDim2.fromOffset(0, 30)
		UIFx.tween(stage, SLIDE_IN, { Position = UDim2.new() })
		for i, glow in glows do
			glow.BackgroundTransparency = 1
			UIFx.tween(glow, GLOW_IN, { BackgroundTransparency = GLOWS[i].alpha })
		end
		UIFx.stagger(revealed, 0.05, { delay = 0.06, offset = Vector2.new(0, 10), scale = 0.6, duration = 0.45 })
		rule.Size = UDim2.fromOffset(0, 2)
		UIFx.tween(rule, RULE_IN, { Size = UDim2.new(1, -INSET * 2, 0, 2) })
		for _, fn in self._opened do
			task.spawn(fn)
		end
	end

	local function exit()
		UIFx.tween(stage, SLIDE_OUT, { Position = UDim2.fromOffset(0, 14) })
		for _, glow in glows do
			UIFx.tween(glow, GLOW_OUT, { BackgroundTransparency = 1 })
		end
		for _, fn in self._closed do
			task.spawn(fn)
		end
	end

	frame:GetAttributeChangedSignal("Open"):Connect(function()
		if UIKit.isOpen(frame) then
			entrance()
		else
			exit()
		end
	end)
	-- the group keeps running through the close animation and stops once the panel is hidden
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible and not UIKit.isOpen(frame) then
			group:setActive(false)
			stage.Position = UDim2.new()
		end
	end)

	frame.Parent = gui
	return self
end

function Shell.onOpened(self: Shell, fn: () -> ())
	table.insert(self._opened, fn)
end

function Shell.onClosed(self: Shell, fn: () -> ())
	table.insert(self._closed, fn)
end

-- Show `keys` in the header chip. With `animate` the number counts from the previous value, and a
-- rise gives the chip a little pop + gold flash and spins its 3D key up. No-op when the shell has no
-- balance chip.
function Shell.setBalance(self: Shell, keys: number, animate: boolean?)
	local chip, amount = self._chip, self._amount
	if not chip or not amount then
		return
	end
	local previous = self._balance
	self._balance = keys
	if animate and previous ~= nil and previous ~= keys then
		UIFx.countUp(amount, previous, keys, 0.8)
		if self._key then
			self._key:kick(if keys > previous then 16 else 6)
		end
		if keys > previous then
			local scale = UIFx.scaleOf(chip)
			scale.Scale = 1.16
			UIFx.tween(scale, UIFx.Info.spring, { Scale = 1 })
			-- (no UIFx.flash here: the chip's UIListLayout would lay the cover out as an item)
			chip.BackgroundColor3 = CHIP_HOT
			UIFx.tween(chip, CHIP_COOL, { BackgroundColor3 = CHIP })
		end
	else
		UIFx.countUp(amount, keys, keys, 0) -- sets the text and cancels a running count
	end
end

function Shell.balanceTarget(self: Shell): GuiObject?
	return self._chip
end

function Shell.shake(self: Shell, intensity: number?, duration: number?)
	UIFx.shake(self._stage, intensity or 8, duration or 0.4)
end

function Shell.flash(self: Shell, color: Color3?, strength: number?)
	UIFx.flash(self._sheet, color or self.accent, strength or 0.35, 0.45)
end

return Shell
