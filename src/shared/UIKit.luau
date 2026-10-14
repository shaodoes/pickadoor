-- Small helpers for code-built UI with the "night archive" look: dark charcoal glass panels with a
-- faint top-lit gradient, crisp off-white type, one cold spectral-teal accent, and warm gold kept
-- for Keys / currency only. Thin 1px strokes, generous corner radii, soft glows and drop shadows.
-- Buttons get springy hover/press animation with a little parallax tilt, and sounds; panels pop open
-- and closed; toasts slide in.
-- Everything is sized for a ~1280x720 screen and scaled to fit by UIKit.fit (phones get smaller UI).
--
-- Token names are kept from the older cream/ink "paper" theme so existing scripts keep working; their
-- meaning in the dark theme: `ink*` = dark surfaces (and dark text on bright faces), `paper*` = light
-- text/icons on those surfaces, `cream` = the bright primary (teal) face, `accent` = the teal accent.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Sfx = require(script.Parent.Sfx)

local UIKit = {}

UIKit.Colors = {
	-- light text / icons on the dark surfaces (were: the cream paper sheets)
	paper = Color3.fromRGB(232, 236, 243),
	paperLight = Color3.fromRGB(248, 250, 253),
	paperDark = Color3.fromRGB(46, 51, 64), -- dim fills: empty meter segments, muted buttons, idle pips
	-- the primary face (the PICK A DOOR pill) and its "hot" (queued / warning) variant
	cream = Color3.fromRGB(94, 232, 210),
	creamHot = Color3.fromRGB(255, 112, 118),
	-- dark surfaces (HUD cards, dark buttons) and dark text on bright faces
	ink = Color3.fromRGB(14, 16, 22),
	inkSoft = Color3.fromRGB(30, 34, 45),
	inkMuted = Color3.fromRGB(126, 136, 156), -- secondary text, disabled icons
	shadow = Color3.fromRGB(2, 3, 6),
	-- the one cool accent
	accent = Color3.fromRGB(45, 212, 191),
	accentDark = Color3.fromRGB(14, 92, 88),
	accentGlow = Color3.fromRGB(130, 255, 236),
	-- glass surfaces (panels, dialogue, rows) and hairline strokes
	glass = Color3.fromRGB(12, 14, 20),
	glassRaised = Color3.fromRGB(26, 30, 40),
	line = Color3.fromRGB(255, 255, 255),
	-- status
	danger = Color3.fromRGB(240, 84, 98),
	dangerGlow = Color3.fromRGB(255, 160, 166), -- trim on red buttons
	success = Color3.fromRGB(52, 196, 132),
	-- Keys / currency only
	key = Color3.fromRGB(236, 188, 96),
	keyBright = Color3.fromRGB(255, 220, 132),
	-- legacy keys (the Trial overlay and the reward panels use these)
	bg = Color3.fromRGB(8, 9, 13),
	panel = Color3.fromRGB(14, 16, 22),
	panelLight = Color3.fromRGB(30, 34, 45),
	gold = Color3.fromRGB(236, 188, 96),
	goldBright = Color3.fromRGB(255, 220, 132),
	text = Color3.fromRGB(232, 236, 243),
	muted = Color3.fromRGB(148, 157, 176),
	red = Color3.fromRGB(240, 84, 98),
	green = Color3.fromRGB(52, 178, 124),
}
local C = UIKit.Colors

-- Non-colour theme numbers: glass opacity, hairline stroke transparency, corner radii.
UIKit.Theme = {
	glassAlpha = 0.1, -- BackgroundTransparency of glass cards / HUD
	sheetAlpha = 0.04, -- ... of big sheets (panels, dialogue) that carry a lot of text
	lineAlpha = 0.86, -- 1px hairline stroke transparency
	radius = 12,
	radiusLarge = 18,
}
local Theme = UIKit.Theme

-- Legacy Enum.Font picks (UIKit.label); the FontFaces below are what the UI actually uses.
UIKit.Fonts = {
	title = Enum.Font.GothamBold,
	body = Enum.Font.Gotham,
	ui = Enum.Font.GothamMedium,
}

-- FontFaces. `bold` / `semi` stay Oswald (condensed caps: the reward panels' fixed layouts are sized
-- for it); `display` / `ui` are the clean BuilderSans faces for the HUD, buttons and panel titles.
UIKit.Face = {
	bold = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	semi = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
	body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	bodyBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	serif = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular),
	display = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold),
	ui = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	uiSemi = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold),
}
local Face = UIKit.Face

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function tween(inst: Instance, info: TweenInfo, goal: { [string]: any })
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end
UIKit.tween = tween

function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(radius: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?)
	return UIKit.new("UIStroke", {
		Color = color or C.gold,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(px: number)
	local u = UDim.new(0, px)
	return UIKit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

-- Soft top-lit sheen: the top of a surface catches the light, the bottom falls off a little cooler.
function UIKit.sheen(strength: number?)
	local s = strength or 1
	local low = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(150, 158, 178), s)
	return UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), low),
	})
end

-- A 1px hairline stroke in the theme's line colour.
function UIKit.hairline(transparency: number?, color: Color3?)
	return UIKit.stroke(color or C.line, 1, transparency or Theme.lineAlpha)
end

export type GlassOpts = {
	radius: number?,
	color: Color3?, -- surface colour (default Colors.glass)
	alpha: number?, -- BackgroundTransparency (default Theme.glassAlpha)
	line: number?, -- hairline transparency (default Theme.lineAlpha); pass 1 for none
	tint: Color3?, -- colour the lower edge of the gradient leans toward (default a cool grey-blue)
	flat: boolean?, -- no gradient (a UIGradient on a TextLabel would tint its text too)
}

-- Turn `obj` into a dark glass card: translucent surface, a diagonal top-lit UIGradient, a
-- rounded corner and a 1px hairline. Replaces any UICorner / UIStroke / UIGradient obj already has.
-- (On a TextLabel / TextButton pass flat = true: a UIGradient tints the text as well.)
function UIKit.glass(obj: GuiObject, opts: GlassOpts?): GuiObject
	local o: GlassOpts = opts or {}
	for _, child in obj:GetChildren() do
		if child:IsA("UICorner") or child:IsA("UIStroke") or child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	obj.BackgroundColor3 = o.color or C.glass
	obj.BackgroundTransparency = o.alpha or Theme.glassAlpha
	obj.BorderSizePixel = 0
	UIKit.corner(o.radius or Theme.radius).Parent = obj
	if (o.line or Theme.lineAlpha) < 1 then
		UIKit.hairline(o.line).Parent = obj
	end
	if o.flat then
		return obj
	end
	-- UIGradient colours multiply the surface: lift the top-left a touch so the card reads as lit glass
	local top = Color3.fromRGB(255, 255, 255)
	local tint = o.tint or Color3.fromRGB(186, 198, 222)
	UIKit.new("UIGradient", {
		Rotation = 70,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(0.45, tint),
			ColorSequenceKeypoint.new(1, tint:Lerp(Color3.new(), 0.25)),
		}),
		Parent = obj,
	})
	return obj
end

function UIKit.label(props: { [string]: any })
	local merged = {
		BackgroundTransparency = 1,
		Font = UIKit.Fonts.body,
		TextColor3 = C.text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("TextLabel", merged)
end

------------------------------------------------------------------------------------------
-- Screen fitting
------------------------------------------------------------------------------------------
-- The UI is laid out for 1280x720. Smaller screens (phones) scale it down, big ones up a little.
local DESIGN = Vector2.new(1280, 720)
local fitScale = 1
local fitChanged = Instance.new("BindableEvent")

local function computeFit(): number
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or DESIGN
	if size.X < 2 or size.Y < 2 then
		return 1
	end
	return math.clamp(math.min(size.X / DESIGN.X, size.Y / DESIGN.Y), 0.6, 1.25)
end

local function refit()
	local s = computeFit()
	if math.abs(s - fitScale) > 0.001 then
		fitScale = s
		fitChanged:Fire(s)
	end
end

local viewportConn: RBXScriptConnection? = nil
local function watchCamera()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	end
	refit()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

function UIKit.fitScale(): number
	return fitScale
end

UIKit.FitChanged = fitChanged.Event

-- Give a top-level HUD element a UIScale named "Fit" that tracks the screen size.
function UIKit.fit(obj: GuiObject): UIScale
	local scale = UIKit.new("UIScale", { Name = "Fit", Scale = fitScale, Parent = obj })
	fitChanged.Event:Connect(function(s)
		scale.Scale = s
	end)
	return scale
end

------------------------------------------------------------------------------------------
-- Shadows
------------------------------------------------------------------------------------------
-- A soft drop shadow made of two stacked translucent shapes beneath an element's face. It has to
-- be a sibling of the face (children always draw above their parent), so it goes in `holder`.
function UIKit.shadow(holder: GuiObject, radius: number, depth: number?, strength: number?)
	local d = depth or 4
	local k = strength or 1
	local folder = UIKit.new("Frame", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = holder,
	})
	for i, spec in { { grow = 6, drop = d + 2, alpha = 0.86 }, { grow = 2, drop = d, alpha = 0.7 } } do
		UIKit.new("Frame", {
			Name = "Layer" .. i,
			BackgroundColor3 = C.shadow,
			BackgroundTransparency = 1 - (1 - spec.alpha) * k,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, spec.drop),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			ZIndex = 0,
			Parent = folder,
		}, { UIKit.corner(radius + spec.grow / 2) })
	end
	return folder
end

-- A soft coloured halo behind an element (like shadow(), a sibling of the face, so it goes in
-- `holder`): three stacked translucent rounded frames that grow outward. Centre-anchored, so a UIScale
-- on it (UIFx.pulse) breathes it in place.
function UIKit.glow(holder: GuiObject, radius: number, color: Color3?, strength: number?)
	local k = strength or 1
	local folder = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = holder,
	})
	for i, spec in { { grow = 34, alpha = 0.95 }, { grow = 18, alpha = 0.9 }, { grow = 6, alpha = 0.82 } } do
		UIKit.new("Frame", {
			Name = "Layer" .. i,
			BackgroundColor3 = color or C.accent,
			BackgroundTransparency = 1 - (1 - spec.alpha) * k,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 2),
			Size = UDim2.new(1, spec.grow, 1, spec.grow),
			ZIndex = 0,
			Parent = folder,
		}, { UIKit.corner(radius + spec.grow / 2) })
	end
	return folder
end

------------------------------------------------------------------------------------------
-- NPC / station marker
------------------------------------------------------------------------------------------
-- The "something waiting here" marker floated over NPCs and reward stations (in a BillboardGui): a
-- dark glass diamond with a rim and halo in `color` (default: the accent) and a white "!". Returns
-- the holder and step(t), which bobs it around `position`, breathes the halo and rocks the diamond a
-- little; call it every frame only while the marker is showing.
function UIKit.alertMarker(parent: Instance, position: UDim2, size: number?, color: Color3?): (Frame, (t: number) -> ())
	local s = size or 34
	local tint = color or C.accent -- rim and halo (e.g. the station's own colour)
	local d = math.floor(s * 0.72) -- the diamond's side (its diagonal is ~s)
	local holder = UIKit.new("Frame", {
		Name = "Alert",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(s, s),
		Parent = parent,
	})
	local halos = {}
	for i, spec in { { grow = 16, alpha = 0.86 }, { grow = 7, alpha = 0.7 } } do
		halos[i] = UIKit.new("Frame", {
			Name = "Halo" .. i,
			BackgroundColor3 = tint,
			BackgroundTransparency = spec.alpha,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(d + spec.grow, d + spec.grow),
			Rotation = 45,
			Parent = holder,
		}, { UIKit.corner(6 + spec.grow / 2) })
	end
	local diamond = UIKit.new("Frame", {
		Name = "Diamond",
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(d, d),
		Rotation = 45,
		ZIndex = 2,
		Parent = holder,
	}, {
		UIKit.corner(6),
		UIKit.stroke(tint, 1.5, 0),
		UIKit.new("UIGradient", {
			Rotation = 45, -- (in the diamond's frame: lit from the top corner)
			Color = ColorSequence.new(Color3.fromRGB(150, 168, 190), Color3.new(1, 1, 1)),
		}),
	})
	UIKit.new("TextLabel", {
		Name = "Bang",
		Text = "!",
		FontFace = Face.display,
		TextSize = math.floor(s * 0.62),
		TextColor3 = C.paperLight,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = holder,
	})
	local function step(t: number)
		holder.Position = position + UDim2.fromOffset(0, math.sin(t * 3) * 5)
		diamond.Rotation = 45 + math.sin(t * 1.7) * 5
		local breathe = 0.5 + 0.5 * math.sin(t * 4)
		halos[1].BackgroundTransparency = 0.9 - 0.06 * breathe
		halos[2].BackgroundTransparency = 0.76 - 0.1 * breathe
	end
	return holder, step
end

------------------------------------------------------------------------------------------
-- Icons (built from frames so they're crisp at any size and never fail to load)
------------------------------------------------------------------------------------------
local function part(parent: Instance, props: { [string]: any }, round: number?)
	props.BorderSizePixel = 0
	props.Parent = parent
	local f = UIKit.new("Frame", props)
	if round then
		UIKit.corner(round).Parent = f
	end
	return f
end

local function ring(parent: Instance, x: number, y: number, d: number, s: number, color: Color3, z: number?)
	local f = part(parent, {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(d, d),
		ZIndex = z or 1,
	}, 999)
	UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.09), Parent = f })
	return f
end

-- Solid filled rectangle in icon-relative coordinates.
local function bar(
	parent: Instance,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	round: number?,
	z: number?
)
	return part(parent, {
		BackgroundColor3 = color,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		ZIndex = z or 1,
	}, round)
end

-- Solid right triangle filling the lower-left (`flip`: upper-left) half of a w x h box. UIGradient
-- rotates in pixel space, so the hard edge's angle is taken from the box's aspect to hit its corners.
local function halfTriangle(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, flip: boolean)
	local f = bar(parent, color, x, y, w, h)
	local angle = math.deg(math.atan(w / h))
	UIKit.new("UIGradient", {
		Rotation = flip and angle or -angle,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.51, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = f,
	})
	return f
end

local ICONS: { [string]: (Frame, Color3, number) -> () } = {
	play = function(f, color)
		-- two half-triangles make a right-pointing arrowhead
		halfTriangle(f, 0.2, 0.1, 0.68, 0.4, color, false)
		halfTriangle(f, 0.2, 0.5, 0.68, 0.4, color, true)
	end,
	close = function(f, color)
		for _, r in { 45, -45 } do
			part(f, {
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.9, 0.16),
				Rotation = r,
			}, 999)
		end
	end,
	key = function(f, color, s)
		ring(f, 0.04, 0.3, 0.4, s, color)
		bar(f, color, 0.42, 0.44, 0.56, 0.13, 2)
		bar(f, color, 0.7, 0.5, 0.1, 0.22, 1)
		bar(f, color, 0.86, 0.5, 0.1, 0.17, 1)
	end,
	cart = function(f, color, s)
		bar(f, color, 0, 0.12, 0.2, 0.1, 2) -- handle
		bar(f, color, 0.14, 0.12, 0.1, 0.5, 2)
		bar(f, color, 0.22, 0.24, 0.74, 0.4, math.floor(s * 0.08)) -- basket
		bar(f, color, 0.2, 0.66, 0.7, 0.08, 2) -- rail
		bar(f, color, 0.24, 0.76, 0.18, 0.18, 999) -- wheels
		bar(f, color, 0.68, 0.76, 0.18, 0.18, 999)
	end,
	lantern = function(f, color, s)
		ring(f, 0.39, -0.02, 0.22, s, color)
		bar(f, color, 0.34, 0.12, 0.32, 0.08, 2) -- cap
		bar(f, color, 0.2, 0.18, 0.6, 0.1, 2)
		local glass = bar(f, color, 0.28, 0.28, 0.44, 0.5)
		glass.BackgroundTransparency = 0.6
		bar(f, color, 0.22, 0.26, 0.1, 0.56, 1) -- posts
		bar(f, color, 0.68, 0.26, 0.1, 0.56, 1)
		bar(f, color, 0.42, 0.38, 0.16, 0.3, 999) -- flame
		bar(f, color, 0.18, 0.8, 0.64, 0.12, 2) -- base
	end,
	help = function(f, color)
		UIKit.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = "?",
			FontFace = Face.bold,
			TextScaled = true,
			TextColor3 = color,
			Size = UDim2.fromScale(1, 1.1),
			Position = UDim2.fromScale(0, -0.05),
			Parent = f,
		})
	end,
	invite = function(f, color, s)
		part(
			f,
			{ BackgroundColor3 = color, Position = UDim2.fromScale(0.16, 0.08), Size = UDim2.fromScale(0.36, 0.36) },
			999
		)
		part(f, {
			BackgroundColor3 = color,
			Position = UDim2.fromScale(0.02, 0.5),
			Size = UDim2.fromScale(0.64, 0.44),
		}, math.floor(s * 0.2))
		part(
			f,
			{ BackgroundColor3 = color, Position = UDim2.fromScale(0.66, 0.28), Size = UDim2.fromScale(0.34, 0.11) },
			1
		)
		part(
			f,
			{ BackgroundColor3 = color, Position = UDim2.fromScale(0.775, 0.165), Size = UDim2.fromScale(0.11, 0.34) },
			1
		)
	end,
	heart = function(f, color)
		part(
			f,
			{ BackgroundColor3 = color, Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.46, 0.46) },
			999
		)
		part(
			f,
			{ BackgroundColor3 = color, Position = UDim2.fromScale(0.46, 0.14), Size = UDim2.fromScale(0.46, 0.46) },
			999
		)
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.53),
			Size = UDim2.fromScale(0.47, 0.47),
			Rotation = 45,
		}, 2)
	end,
	check = function(f, color)
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.32, 0.62),
			Size = UDim2.fromScale(0.42, 0.15),
			Rotation = 45,
		}, 999)
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.6, 0.48),
			Size = UDim2.fromScale(0.72, 0.15),
			Rotation = -50,
		}, 999)
	end,
	lock = function(f, color, s)
		ring(f, 0.27, 0.06, 0.46, s, color, 1)
		part(f, {
			BackgroundColor3 = color,
			Position = UDim2.fromScale(0.15, 0.4),
			Size = UDim2.fromScale(0.7, 0.54),
			ZIndex = 2,
		}, math.floor(s * 0.1))
	end,
	-- items --------------------------------------------------------------------------------
	pills = function(f, color, s)
		-- a tilted two-tone capsule (solid half + outline half) with a loose round pill beside it
		local tilt = part(f, {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.44, 0.38),
			Size = UDim2.fromScale(0.94, 0.38),
			Rotation = -28,
		})
		local outline = part(tilt, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, 999)
		UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.075), Parent = outline })
		-- solid half: a fully rounded bar whose inner end is squared off by a plain bar
		bar(tilt, color, 0, 0, 0.5, 1, 999, 2)
		bar(tilt, color, 0.3, 0, 0.21, 1, nil, 2)
		bar(f, color, 0.6, 0.66, 0.3, 0.3, 999)
	end,
	bandage = function(f, color, s)
		-- a roll seen end-on, unrolling into a strip with a cross on it
		ring(f, 0.02, 0.06, 0.48, s, color)
		bar(f, color, 0.19, 0.23, 0.14, 0.14, 999) -- the roll's core
		bar(f, color, 0.24, 0.5, 0.18, 0.32, 1) -- the strip's start, tucked under the roll
		local strip = part(f, {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.38, 0.5),
			Size = UDim2.fromScale(0.62, 0.32),
		}, 3)
		UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.07), Parent = strip })
		bar(f, color, 0.65, 0.54, 0.08, 0.24, 1) -- stitched cross
		bar(f, color, 0.57, 0.62, 0.24, 0.08, 1)
	end,
	lockpick = function(f, color, s)
		-- a padlock with a thin pick slid into it from the right; the shaft vanishes into the body
		ring(f, 0.1, 0.0, 0.42, s, color, 1)
		part(f, {
			BackgroundColor3 = color,
			Position = UDim2.fromScale(0.0, 0.34),
			Size = UDim2.fromScale(0.62, 0.5),
			ZIndex = 2,
		}, math.floor(s * 0.1))
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.68, 0.5),
			Size = UDim2.fromScale(0.64, 0.08),
			Rotation = -21,
			ZIndex = 3,
		}, 999)
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.93, 0.405),
			Size = UDim2.fromScale(0.16, 0.15),
			Rotation = -21,
			ZIndex = 3,
		}, 2)
	end,
	laser = function(f, color, s)
		-- a pen from the bottom-left aimed at a dot in the top-right, three rays off the dot
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.34, 0.66),
			Size = UDim2.fromScale(0.6, 0.2),
			Rotation = -45,
		}, math.floor(s * 0.06))
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.595, 0.405),
			Size = UDim2.fromScale(0.13, 0.12),
			Rotation = -45,
		}, 1)
		bar(f, color, 0.72, 0.1, 0.2, 0.2, 999) -- the dot
		bar(f, color, 0.8, -0.04, 0.04, 0.1, 1) -- rays: up, right, diagonal
		bar(f, color, 0.96, 0.18, 0.1, 0.04, 1)
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.95, 0.05),
			Size = UDim2.fromScale(0.11, 0.04),
			Rotation = -45,
		}, 1)
	end,
	battery = function(f, color, s)
		local shell = part(f, {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.02, 0.26),
			Size = UDim2.fromScale(0.84, 0.48),
		}, math.floor(s * 0.08))
		UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.07), Parent = shell })
		bar(f, color, 0.88, 0.4, 0.1, 0.2, 1) -- terminal
		for i = 0, 2 do
			bar(f, color, 0.1 + i * 0.22, 0.36, 0.16, 0.28, 1)
		end
	end,
	-- titles / nameplates ---------------------------------------------------------------------
	skull = function(f, color, s)
		local hollow = Color3.fromRGB(24, 15, 12) -- sockets and teeth gaps read dark on any badge
		bar(f, color, 0.12, 0.02, 0.76, 0.66, 999) -- cranium
		bar(f, color, 0.27, 0.5, 0.46, 0.4, math.floor(s * 0.08)) -- jaw
		bar(f, hollow, 0.24, 0.32, 0.2, 0.2, 999, 2) -- eye sockets
		bar(f, hollow, 0.56, 0.32, 0.2, 0.2, 999, 2)
		bar(f, hollow, 0.46, 0.54, 0.08, 0.1, 1, 2) -- nose
		bar(f, hollow, 0.405, 0.72, 0.05, 0.18, nil, 2) -- teeth gaps
		bar(f, hollow, 0.545, 0.72, 0.05, 0.18, nil, 2)
	end,
	medal = function(f, color, s)
		for _, spec in { { 0.36, 20 }, { 0.64, -20 } } do
			part(f, {
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec[1], 0.2),
				Size = UDim2.fromScale(0.2, 0.42),
				Rotation = spec[2],
			}, 1)
		end
		ring(f, 0.2, 0.36, 0.6, s, color, 2)
		bar(f, color, 0.35, 0.51, 0.3, 0.3, 999, 2)
	end,
	door = function(f, color, s)
		local frame = part(f, {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.2, 0.04),
			Size = UDim2.fromScale(0.6, 0.92),
		}, math.floor(s * 0.08))
		UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.09), Parent = frame })
		bar(f, color, 0.3, 0.14, 0.4, 0.3, 1) -- upper panel
		bar(f, color, 0.58, 0.54, 0.12, 0.12, 999) -- knob
	end,
	moon = function(f, color)
		-- a disc cut by a hard gradient edge: a fat crescent, with a small star beside it
		local disc = bar(f, color, 0.04, 0.1, 0.78, 0.78, 999)
		UIKit.new("UIGradient", {
			Rotation = 35,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0),
				NumberSequenceKeypoint.new(0.56, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = disc,
		})
		part(f, {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.8, 0.26),
			Size = UDim2.fromScale(0.16, 0.16),
			Rotation = 45,
		}, 1)
	end,
	eye = function(f, color, s)
		local lid = part(f, {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.04, 0.24),
			Size = UDim2.fromScale(0.92, 0.52),
		}, 999)
		UIKit.new("UIStroke", { Color = color, Thickness = math.max(1.5, s * 0.09), Parent = lid })
		bar(f, color, 0.34, 0.34, 0.32, 0.32, 999) -- pupil
	end,
	wheel = function(f, color, s)
		ring(f, 0.06, 0.06, 0.88, s, color)
		for _, r in { 0, 60, 120 } do
			part(f, {
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.8, 0.08),
				Rotation = r,
			}, 1)
		end
		bar(f, color, 0.38, 0.38, 0.24, 0.24, 999, 2) -- hub
	end,
}

-- A square icon of `size` px. Names: play, close, key, cart, lantern, help, invite, heart, check, lock,
-- pills, bandage, lockpick, laser, battery, skull, medal, door, moon, eye, wheel.
function UIKit.icon(name: string, color: Color3?, size: number?): Frame
	local s = size or 24
	local f = UIKit.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(s, s),
	})
	local draw = ICONS[name]
	if draw then
		draw(f, color or C.text, s)
	end
	return f
end

------------------------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------------------------
-- Colour schemes: face colour, text/icon colour, trim colour + trim transparency, and optionally the
-- face's BackgroundTransparency (`alpha`: glass buttons) and a halo colour (`glow`: the primary).
UIKit.Styles = {
	cream = { face = C.cream, text = C.ink, trim = C.accentGlow, trimAlpha = 0.45, glow = C.accent },
	ink = { face = C.ink, text = C.paper, trim = C.line, trimAlpha = 0.84, alpha = 0.12 },
	accent = { face = C.accent, text = C.ink, trim = C.accentGlow, trimAlpha = 0.5 },
	paper = { face = C.inkSoft, text = C.paper, trim = C.line, trimAlpha = 0.82, alpha = 0.06 },
	green = { face = C.green, text = C.paperLight, trim = C.line, trimAlpha = 0.72 },
	muted = { face = C.paperDark, text = C.inkMuted, trim = C.line, trimAlpha = 0.9 },
	danger = { face = C.danger, text = C.paperLight, trim = C.dangerGlow, trimAlpha = 0.45 },
}
-- clearer names for new code (same tables)
UIKit.Styles.primary = UIKit.Styles.cream
UIKit.Styles.glass = UIKit.Styles.ink

local TILT = 3 -- degrees a hovered face leans toward the pointer
local PARALLAX = Vector2.new(4, 3) -- px it drifts toward the pointer (its shadow drifts away)

-- The pointer's position over `obj` as -0.5..0.5 on each axis (nil if obj has no size yet).
local function pointerIn(obj: GuiObject): Vector2?
	local size = obj.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local gui = obj:FindFirstAncestorWhichIsA("ScreenGui")
	if not (gui and gui.IgnoreGuiInset) then
		mouse -= GuiService:GetGuiInset()
	end
	local rel = (mouse - obj.AbsolutePosition) / size - Vector2.new(0.5, 0.5)
	return Vector2.new(math.clamp(rel.X, -0.5, 0.5), math.clamp(rel.Y, -0.5, 0.5))
end

-- Hover: springs up a touch, lightens, and the face leans toward the pointer (a tilt plus a little
-- parallax against its shadow, so it reads as a raised tile). Press: squashes and sinks onto its
-- shadow. Click: sound. Works on UIKit.button()s (which have a Face) and on plain GuiButtons.
function UIKit.animate(button: GuiButton, baseColor: Color3?)
	local scale = button:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = button })
	local face = button:FindFirstChild("Face") :: GuiObject?
	local surface: GuiObject = face or button
	local stroke = surface:FindFirstChildOfClass("UIStroke")
	local strokeAlpha = stroke and stroke.Transparency
	local color = baseColor or surface.BackgroundColor3
	local faceRest = face and face.Position
	local shadow = face and button:FindFirstChild("Shadow") :: GuiObject?
	local shadowRest = shadow and shadow.Position
	button.AutoButtonColor = false
	local hovering, pressed = false, false
	local settling: { Tween } = {}

	local function stopSettling()
		for _, t in settling do
			t:Cancel()
		end
		table.clear(settling)
	end

	-- place the face (and its shadow) for a pointer at `rel` (nil = centred)
	local function lean(rel: Vector2?)
		if not (face and faceRest) then
			return
		end
		stopSettling()
		local r = rel or Vector2.zero
		local sink = if pressed then 2 else 0
		face.Position = faceRest + UDim2.fromOffset(math.round(r.X * PARALLAX.X), math.round(r.Y * PARALLAX.Y) + sink)
		face.Rotation = r.X * TILT
		if shadow and shadowRest then
			shadow.Position = shadowRest
				+ UDim2.fromOffset(math.round(-r.X * PARALLAX.X), math.round(-r.Y * PARALLAX.Y * 0.5))
		end
	end

	local function rest()
		tween(scale, hovering and SPRING or FAST, { Scale = hovering and 1.06 or 1 })
		tween(surface, FAST, { BackgroundColor3 = hovering and color:Lerp(Color3.new(1, 1, 1), 0.12) or color })
		if stroke and strokeAlpha then
			tween(stroke, FAST, { Transparency = hovering and math.max(strokeAlpha - 0.3, 0) or strokeAlpha })
		end
		if hovering and UserInputService.MouseEnabled then
			lean(pointerIn(button))
		elseif face and faceRest then
			stopSettling()
			table.insert(settling, tween(face, SPRING, { Position = faceRest, Rotation = 0 }))
			if shadow and shadowRest then
				table.insert(settling, tween(shadow, SPRING, { Position = shadowRest }))
			end
		end
	end
	button.MouseEnter:Connect(function()
		hovering = true
		Sfx.play("Hover", 0.08)
		rest()
	end)
	button.MouseMoved:Connect(function()
		if hovering and UserInputService.MouseEnabled then
			lean(pointerIn(button))
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressed = false
		rest()
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		tween(scale, FAST, { Scale = 0.94 })
		lean(if hovering and UserInputService.MouseEnabled then pointerIn(button) else nil)
	end)
	button.MouseButton1Up:Connect(function()
		if pressed then
			pressed = false
			rest()
		end
	end)
	button.Activated:Connect(function()
		Sfx.play("Click")
		if not hovering then
			-- touch: no hover, so spring back from the press explicitly
			pressed = false
			rest()
		end
	end)
	-- callers that recolor a button (owned/equipped states) update the resting colour here
	button:GetAttributeChangedSignal("BaseColor"):Connect(function()
		local c = button:GetAttribute("BaseColor")
		if typeof(c) == "Color3" then
			color = c
			rest()
		end
	end)
	return button
end

local FACE_PROPS = { BackgroundColor3 = true }
local LABEL_PROPS = { TextColor3 = true, FontFace = true, Font = true, TextSize = true }

export type ButtonOptions = {
	style: string?, -- key of UIKit.Styles (default "ink")
	icon: string?, -- UIKit.icon name shown left of the text
	iconSize: number?,
	radius: number?,
	depth: number?, -- shadow drop in px
	tooltip: string?, -- shown above the button on hover (good for icon-only buttons)
	glow: boolean?, -- false hides the style's halo (the primary style has one)
}

-- A chunky button: an invisible hit box holding a shadow (and, for the primary style, a soft accent
-- halo) and a rounded Face with icon + text. The button's own Text property still holds the caption
-- (set it as usual; the face follows).
-- `props` may include BackgroundColor3 / TextColor3 / FontFace / TextSize to override the style.
function UIKit.button(text: string, props: { [string]: any }?, options: ButtonOptions?)
	local opts: ButtonOptions = options or {}
	local style = UIKit.Styles[opts.style or "ink"] or UIKit.Styles.ink
	local radius = opts.radius or Theme.radius

	local buttonProps = {
		Text = text,
		TextTransparency = 1,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(150, 44),
	}
	local faceColor: Color3 = style.face
	local labelProps: { [string]: any } = {
		TextColor3 = style.text,
		FontFace = Face.bold,
		TextSize = 20,
	}
	local parent = nil
	for key, value in props or {} do
		if FACE_PROPS[key] then
			faceColor = value
		elseif LABEL_PROPS[key] then
			labelProps[key] = value
		elseif key == "Parent" then
			parent = value
		else
			buttonProps[key] = value
		end
	end
	local button = UIKit.new("TextButton", buttonProps)
	if style.glow and opts.glow ~= false then
		UIKit.glow(button, radius, style.glow, 1)
	end
	UIKit.shadow(button, radius, opts.depth or 3, 0.9)
	local face = UIKit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = faceColor,
		BackgroundTransparency = style.alpha or 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = button,
	}, {
		UIKit.corner(radius),
		UIKit.stroke(style.trim, 1, style.trimAlpha),
		UIKit.sheen(0.45),
	})

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		Parent = face,
	}, {
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local labelSize = labelProps.TextSize :: number
	if opts.icon then
		local icon = UIKit.icon(opts.icon, labelProps.TextColor3, opts.iconSize or math.floor(labelSize * 1.05))
		icon.LayoutOrder = 1
		icon.Parent = content
	end
	local label = UIKit.new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, labelSize + 4),
		LayoutOrder = 2,
		Visible = text ~= "",
		Parent = content,
	})
	for key, value in labelProps do
		label[key] = value
	end
	button:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = button.Text
		label.Visible = button.Text ~= ""
	end)

	if opts.tooltip then
		UIKit.tooltip(button, opts.tooltip)
	end
	if parent then
		button.Parent = parent
	end
	return UIKit.animate(button)
end

-- Little glass tag above a button while hovered (or briefly after a tap on touch screens).
function UIKit.tooltip(button: GuiButton, text: string)
	local tip = UIKit.new("TextLabel", {
		Name = "Tooltip",
		Text = text,
		FontFace = Face.uiSemi,
		TextSize = 15,
		TextColor3 = C.paper,
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		Visible = false,
		ZIndex = 10,
		Parent = button,
	}, {
		UIKit.corner(8),
		UIKit.hairline(0.8),
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	local token, hovering = 0, false
	button.MouseEnter:Connect(function()
		token += 1
		hovering = true
		tip.Visible = true
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		tip.Visible = false
	end)
	button.Activated:Connect(function()
		token += 1
		local mine = token
		tip.Visible = true
		task.delay(1.2, function()
			if token == mine and not hovering then
				tip.Visible = false
			end
		end)
	end)
	return tip
end

------------------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------------------
local panelScales: { [Frame]: UIScale } = {}

function UIKit.isOpen(panel: Frame): boolean
	return panel:GetAttribute("Open") == true
end

function UIKit.show(panel: Frame)
	if UIKit.isOpen(panel) then
		return
	end
	panel:SetAttribute("Open", true)
	local scale = panelScales[panel]
	local body = panel:FindFirstChild("Body") :: GuiObject?
	if scale then
		scale.Scale = fitScale * 0.86
		tween(scale, POP, { Scale = fitScale })
	end
	if body then
		body.Position = UDim2.fromOffset(0, 18)
		tween(body, POP, { Position = UDim2.new() })
	end
	panel.Visible = true
	Sfx.play("PanelOpen", 0.04)
end

function UIKit.hide(panel: Frame)
	if not UIKit.isOpen(panel) then
		return
	end
	panel:SetAttribute("Open", false)
	Sfx.play("PanelClose", 0.04)
	local scale = panelScales[panel]
	if not scale then
		panel.Visible = false
		return
	end
	local t = tween(scale, SHUT, { Scale = fitScale * 0.9 })
	t.Completed:Connect(function()
		if not UIKit.isOpen(panel) then
			panel.Visible = false
			scale.Scale = fitScale
		end
	end)
end

function UIKit.toggle(panel: Frame)
	if UIKit.isOpen(panel) then
		UIKit.hide(panel)
	else
		UIKit.show(panel)
	end
end

-- Opt a code-built panel (one that doesn't come from UIKit.panel, e.g. RewardsUI/Shell) into the
-- show/hide pop and fit-to-screen scaling: gives it a UIScale named "Fit" (Scale = the current fit)
-- that UIKit.show/hide animate and FitChanged rescales. Safe to call twice (returns the same scale).
function UIKit.registerPanel(panel: Frame): UIScale
	local existing = panelScales[panel]
	if existing then
		return existing
	end
	local scale = UIKit.new("UIScale", { Name = "Fit", Scale = fitScale, Parent = panel })
	panelScales[panel] = scale
	if panel:GetAttribute("Open") == nil then
		panel:SetAttribute("Open", false)
	end
	return scale
end

fitChanged.Event:Connect(function(s)
	for panel, scale in panelScales do
		if panel.Parent then
			scale.Scale = s
		else
			panelScales[panel] = nil
		end
	end
end)

local HEADER = 58

-- Centered modal panel: a sheet of dark glass with a faintly lit header strip and a thin accent
-- rule that fades out to the right.
-- Returns the frame (named <title>Panel) and the content area beneath the header.
-- Open/close it with UIKit.show / UIKit.hide / UIKit.toggle so it animates.
function UIKit.panel(parent: Instance, title: string, size: UDim2)
	local R = Theme.radiusLarge
	local frame = UIKit.new("Frame", {
		Name = title .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = size,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})
	panelScales[frame] = UIKit.new("UIScale", { Scale = fitScale, Parent = frame })
	frame:SetAttribute("Open", false)

	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	})
	UIKit.glow(body, R, C.accent, 0.35)
	UIKit.shadow(body, R, 10, 1)
	local sheet = UIKit.new("Frame", {
		Name = "Sheet",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = body,
	})
	UIKit.glass(sheet, { radius = R, alpha = Theme.sheetAlpha, line = 0.8 })

	-- header: a barely-lit strip (rounded top, square bottom) with an accent rule beneath it
	local header = UIKit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = C.line,
		BackgroundTransparency = 0.965,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, HEADER),
		Parent = sheet,
	}, { UIKit.corner(R) })
	UIKit.new("Frame", {
		Name = "Square",
		BackgroundColor3 = C.line,
		BackgroundTransparency = 0.965,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -R),
		Size = UDim2.new(1, 0, 0, R),
		Parent = header,
	})
	UIKit.new("Frame", {
		Name = "Rule",
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = header,
	}, {
		UIKit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.35, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	UIKit.new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = string.upper(title),
		FontFace = Face.display,
		TextSize = 28,
		TextColor3 = C.paperLight,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -90, 1, 0),
		ZIndex = 2,
		Parent = header,
	})

	local close = UIKit.button("", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 3,
		Parent = header,
	}, { style = "ink", icon = "close", iconSize = 12, radius = 18, depth = 2 })
	close.Activated:Connect(function()
		UIKit.hide(frame)
	end)

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, HEADER + 18),
		Size = UDim2.new(1, -40, 1, -(HEADER + 36)),
		Parent = sheet,
	})
	return frame, content
end

function UIKit.scrollList(parent: Instance, props: { [string]: any }?)
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.inkMuted,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return UIKit.new("ScrollingFrame", merged, {
		UIKit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.new("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 3),
			PaddingRight = UDim.new(0, 3),
		}),
	})
end

-- Make a list row light up gently under the mouse.
function UIKit.hoverRow(row: GuiObject)
	local baseColor = row.BackgroundColor3
	local stroke = row:FindFirstChildOfClass("UIStroke")
	local strokeAlpha = stroke and stroke.Transparency
	row.MouseEnter:Connect(function()
		tween(row, FAST, { BackgroundColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.07) })
		if stroke and strokeAlpha then
			tween(stroke, FAST, { Transparency = math.max(strokeAlpha - 0.25, 0) })
		end
	end)
	row.MouseLeave:Connect(function()
		tween(row, FAST, { BackgroundColor3 = baseColor })
		if stroke and strokeAlpha then
			tween(stroke, FAST, { Transparency = strokeAlpha })
		end
	end)
end

------------------------------------------------------------------------------------------
-- Toasts
------------------------------------------------------------------------------------------
local toastHolders: { [ScreenGui]: Frame } = {}
local TOAST_W = 460

-- kind: nil (neutral: accent tab), "error" (red tab + buzz) or "success" (green tab + chime)
function UIKit.toast(screenGui: ScreenGui, text: string, kind: string?)
	local holder = toastHolders[screenGui]
	if not holder or holder.Parent ~= screenGui then
		holder = UIKit.new("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.fromOffset(TOAST_W + 20, 320),
			ZIndex = 20,
			Parent = screenGui,
		}, {
			UIKit.new("UIListLayout", {
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		UIKit.fit(holder)
		toastHolders[screenGui] = holder
	end
	local tab = kind == "error" and C.danger or kind == "success" and C.success or C.accent
	if kind == "error" then
		Sfx.play("Error")
	elseif kind == "success" then
		Sfx.play("Purchase", 0.02)
	end

	-- the holder lays out a wrapper; the card inside it slides so the list layout doesn't fight it
	local wrapper = UIKit.new("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(TOAST_W, 0),
		Parent = holder,
	})
	local card = UIKit.new("TextLabel", {
		Name = "Card",
		Text = text,
		FontFace = Face.body,
		TextSize = 19,
		TextColor3 = C.paper,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(TOAST_W, 46),
		Position = UDim2.fromOffset(0, -14),
		BackgroundColor3 = C.glass,
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Parent = wrapper,
	}, {
		UIKit.corner(Theme.radius),
		UIKit.new("UIPadding", {
			PaddingTop = UDim.new(0, 11),
			PaddingBottom = UDim.new(0, 11),
			PaddingLeft = UDim.new(0, 26),
			PaddingRight = UDim.new(0, 16),
		}),
	})
	local stroke = UIKit.stroke(C.line, 1, 1)
	stroke.Parent = card
	local accentBar = UIKit.new("Frame", {
		Name = "Tab",
		BackgroundColor3 = tab,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-16, -3),
		Size = UDim2.new(0, 5, 1, 6),
		Parent = card,
	}, { UIKit.corner(3) })

	local slide = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(card, slide, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.06, TextTransparency = 0 })
	tween(stroke, slide, { Transparency = 0.85 })
	tween(accentBar, slide, { BackgroundTransparency = 0 })
	task.delay(3.6, function()
		local fade = TweenInfo.new(0.45)
		tween(card, fade, { TextTransparency = 1, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -10) })
		tween(stroke, fade, { Transparency = 1 })
		tween(accentBar, fade, { BackgroundTransparency = 1 })
		task.wait(0.5)
		wrapper:Destroy()
	end)
end

return UIKit
