--[[
	Signage: the painted / enamel / lit lettering of the lobby, in one visual language.

	  stencil(parent, cf, width, height, text)    spray-stencilled red lettering straight on the wall
	                                              ("PICK A DOOR"): overspray mist, a misregistered dark
	                                              under-coat, uneven paint density, a stencil bridge cut,
	                                              real runs with beads at their ends, and splatter.
	  doorSign(pad, cf, mode, capacity)           chipped enamel plaque screwed above a door: red title on
	                                              cream enamel, the live count on a black strip below.
	  wallSign(parent, cf, text, opts)            wayfinding in the same language: "stencil", "plaque" or
	                                              "lit" (a warm backlit box sign), with an optional arrow.

	`cf` is always the centre of the sign ON the wall surface, its LookVector pointing out into the room.
	Every SurfaceGui sits on the part's Front face (= LookVector), so it reads from the room.

	Decorative GUI layers that should follow the main text when DoorFX glitches it carry the attribute
	SignLayer = true (TextLabels among them also take the glitched text); halo layers carry
	SignHalo = <base transparency> so the client can make them breathe.
]]
local TextService = game:GetService("TextService")

local Kit = require(script.Parent.Kit)

local Signage = {}

local C = Kit.C
local DETAIL = Kit.DETAIL
local INVISIBLE = Kit.INVISIBLE

local PAINT = Color3.fromRGB(196, 34, 28) -- fresh spray red: deeper than the old flat red, still loud
local PAINT_DARK = Color3.fromRGB(72, 14, 12) -- the misregistered first coat / dried runs
local ENAMEL = Color3.fromRGB(226, 222, 210) -- cool cream: warm lamplight turns it ivory, not yellow
local ENAMEL_RED = Color3.fromRGB(150, 28, 24)
local PLATE = Color3.fromRGB(30, 32, 38) -- bare steel where the enamel has chipped
local STRIP = Color3.fromRGB(26, 22, 22)
local CREAM = Color3.fromRGB(238, 226, 200)

local SPRAY_FONT = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)
local PLAQUE_FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local COUNT_FONT = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)

-- Deterministic per-sign randomness, so rebuilds look the same and each sign is still different.
local function rngFor(text: string, cf: CFrame): Random
	local seed = 0
	for i = 1, #text do
		seed = (seed * 31 + string.byte(text, i)) % 2147483647
	end
	local p = cf.Position
	return Random.new(seed + math.floor(p.X * 7 + p.Y * 13 + p.Z * 17))
end

-- Thin invisible carrier part flush on the wall, `out` studs in front of it, with a Front SurfaceGui.
local function carrier(parent: Instance, name: string, cf: CFrame, size: Vector2, out: number, pps: number)
	local part =
		Kit.box(parent, name, Vector3.new(size.X, size.Y, 0.02), cf * CFrame.new(0, 0, -out), C.block, nil, INVISIBLE)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.7
	gui.Brightness = 0.55 -- wet paint holds a little light; keeps it readable from the floor
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = part
	return part, gui
end

local function frame(
	parent: Instance,
	name: string,
	pos: UDim2,
	size: UDim2,
	color: Color3,
	transparency: number?,
	z: number?
)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
	return corner
end

local function text(parent: Instance, name: string, str: string, font: Font, color: Color3, z: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = font
	label.Text = str
	label.TextScaled = true
	label.TextColor3 = color
	label.ZIndex = z
	label.Parent = parent
	return label
end

-- Pixel width of `str` at `size` (falls back to an estimate if the text service isn't available).
local function measure(str: string, font: Font, size: number): number
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = str
		params.Font = font
		params.Size = size
		params.Width = 100000
		return TextService:GetTextBoundsAsync(params)
	end)
	if ok and bounds then
		return bounds.X
	end
	return #str * size * 0.5
end

------------------------------------------------------------------------------------------
-- Painted arrow made of bars (no glyph needed, so any font works). Square box inside `parent`.
------------------------------------------------------------------------------------------
local ARROWS = {
	right = { shaft = { 0.5, 0.5, 0.8, 0 }, heads = { { 0.761, 0.341, 45 }, { 0.761, 0.659, -45 } } },
	left = { shaft = { 0.5, 0.5, 0.8, 0 }, heads = { { 0.239, 0.341, -45 }, { 0.239, 0.659, 45 } } },
	down = { shaft = { 0.5, 0.5, 0.8, 90 }, heads = { { 0.341, 0.761, 45 }, { 0.659, 0.761, -45 } } },
}
local function arrow(parent: Instance, dir: string, pos: UDim2, size: UDim2, color: Color3, z: number, mist: boolean)
	local spec = ARROWS[dir]
	if not spec then
		return nil
	end
	local box = frame(parent, "Arrow", pos, size, color, 1, z)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = box
	local thick = 0.15
	local function bar(cx: number, cy: number, length: number, rotation: number)
		local b = frame(box, "Bar", UDim2.fromScale(cx, cy), UDim2.fromScale(length, thick), color, 0, z)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Rotation = rotation
		round(b, UDim.new(0.3, 0))
		if mist then
			local stroke = Instance.new("UIStroke")
			stroke.Color = color
			stroke.Thickness = 4
			stroke.Transparency = 0.82
			stroke.Parent = b
		end
	end
	local s = spec.shaft
	bar(s[1], s[2], s[3], s[4])
	for _, h in spec.heads do
		bar(h[1], h[2], 0.47, h[3])
	end
	return box
end

------------------------------------------------------------------------------------------
-- Spray-stencil lettering
------------------------------------------------------------------------------------------
-- Transparency along a label's width: patchy paint density, cut by the thin bridges a stencil
-- needs to hold the middles of its letters in place. `bridges` are fractions of the label width.
local function stencilCut(bridges: { number }, bridgeW: number, rng: Random): NumberSequence
	local keys = { NumberSequenceKeypoint.new(0, rng:NextNumber(0.03, 0.12)) }
	local last = 0
	local function push(t: number, v: number)
		if t > last + 0.0005 and t < 0.9995 then
			table.insert(keys, NumberSequenceKeypoint.new(t, v))
			last = t
		end
	end
	for _, c in bridges do
		if #keys > 15 then
			break
		end
		local density = rng:NextNumber(0, 0.1)
		push(c - bridgeW / 2 - 0.001, density)
		push(c - bridgeW / 2, 0.94)
		push(c + bridgeW / 2, 0.94)
		push(c + bridgeW / 2 + 0.001, rng:NextNumber(0, 0.1))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, rng:NextNumber(0.03, 0.12)))
	return NumberSequence.new(keys)
end

-- Builds the paint layers of one line of sprayed text inside `gui` at pos/size (pixels; `px` is the
-- box height). Returns the main label; extra layers are tagged SignLayer so glitches move them too.
local function sprayText(
	gui: Instance,
	mainName: string,
	str: string,
	color: Color3,
	pos: UDim2,
	size: UDim2,
	px: number,
	rng: Random,
	bridges: { number },
	bridgeW: number
)
	local function layer(name: string, z: number, col: Color3, transparency: number, dx: number, dy: number)
		local l = text(gui, name, str, SPRAY_FONT, col, z)
		l.Position = pos + UDim2.fromOffset(dx, dy)
		l.Size = size
		l.TextTransparency = transparency
		l:SetAttribute("SignLayer", true)
		return l
	end

	-- soft overspray: the stencil lifted off the wall a little, so mist landed around every letter.
	-- Two rings of faint copies fake a blur without any image asset.
	for ring, spec in { { 0.035, 0.86 }, { 0.075, 0.93 } } do
		local r = math.max(2, px * spec[1])
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + ring * 0.4
			local m = layer("Mist", 1, color, spec[2], math.cos(a) * r, math.sin(a) * r)
			m:SetAttribute("SignHalo", spec[2])
		end
	end
	-- the first, darker coat, sprayed through the same stencil a few pixels off
	local under = layer("Under", 2, PAINT_DARK, 0.15, math.max(1, px * 0.03), math.max(1, px * 0.035))
	under.Rotation = rng:NextNumber(-0.8, 0.8)
	local underCut = Instance.new("UIGradient")
	underCut.Transparency = stencilCut(bridges, bridgeW, rng)
	underCut.Parent = under

	local main = text(gui, mainName, str, SPRAY_FONT, color, 3)
	main.Position = pos
	main.Size = size
	local paint = Instance.new("UIGradient")
	paint.Transparency = stencilCut(bridges, bridgeW, rng)
	-- lighter where the can passed closest, deeper red at the ends of each stroke
	-- (gradient colours multiply the text colour, so these are shading factors)
	paint.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.78, 0.74, 0.74)),
		ColorSequenceKeypoint.new(0.35, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.7, Color3.new(0.93, 0.9, 0.9)),
		ColorSequenceKeypoint.new(1, Color3.new(0.74, 0.7, 0.7)),
	})
	paint.Parent = main
	return main
end

-- Runs of paint hanging under lettering, with a bead at the end of each, plus fine splatter.
-- `slots` are x positions (pixels in `gui`) where letters touch the baseline at `baseY`.
local function runs(
	gui: Instance,
	slots: { number },
	baseY: number,
	maxLen: number,
	color: Color3,
	rng: Random,
	count: number
)
	for _ = 1, count do
		if #slots == 0 then
			break
		end
		local x = table.remove(slots, rng:NextInteger(1, #slots)) + rng:NextNumber(-6, 6)
		local w = rng:NextNumber(2.5, 5)
		local len = maxLen * rng:NextNumber(0.2, 1) ^ 1.5
		local run = frame(gui, "Run", UDim2.fromOffset(x - w / 2, baseY - 6), UDim2.fromOffset(w, len + 6), color, 0, 2)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.6, 0.55, 0.55)) -- multiplies: darker as it pools
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.1),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		fade.Parent = run
		round(run, UDim.new(0.5, 0))
		local bead = frame(
			gui,
			"Bead",
			UDim2.fromOffset(x - w * 0.95, baseY + len - w * 1.4),
			UDim2.fromOffset(w * 1.9, w * 2.3),
			color:Lerp(PAINT_DARK, 0.45),
			0,
			2
		)
		round(bead, UDim.new(1, 0))
	end
end

local function splatter(gui: Instance, w: number, h: number, color: Color3, rng: Random, count: number, avoid: Rect?)
	for _ = 1, count do
		local x, y = rng:NextNumber(0, w), rng:NextNumber(0, h)
		if avoid and x > avoid.Min.X and x < avoid.Max.X and y > avoid.Min.Y and y < avoid.Max.Y then
			continue
		end
		local d = rng:NextNumber(1.5, 4.5) ^ (rng:NextNumber() < 0.15 and 1.4 or 1)
		local dot =
			frame(gui, "Speck", UDim2.fromOffset(x, y), UDim2.fromOffset(d, d), color, rng:NextNumber(0.05, 0.5), 1)
		round(dot, UDim.new(1, 0))
	end
end

-- Where each glyph of `str` lands (pixels from the left of a `labelW`-wide label, text centred).
type Glyph = { char: string, left: number, width: number }
local function glyphs(str: string, size: number, labelW: number): { Glyph }
	local total = measure(str, SPRAY_FONT, size)
	local left = (labelW - total) / 2
	local out = {}
	for i = 1, #str do
		local ch = string.sub(str, i, i)
		if ch ~= " " then
			table.insert(out, {
				char = ch,
				left = left + measure(string.sub(str, 1, i - 1), SPRAY_FONT, size),
				width = measure(ch, SPRAY_FONT, size),
			})
		end
	end
	return out
end

-- letters with a closed counter need a stencil bridge
local BOWLS = {
	A = true,
	B = true,
	D = true,
	O = true,
	P = true,
	Q = true,
	R = true,
	["0"] = true,
	["4"] = true,
	["6"] = true,
	["8"] = true,
	["9"] = true,
}

-- Font size TextScaled will land on for one line of `str` in a w x h pixel box.
local function fittedSize(str: string, w: number, h: number): number
	local wAt100 = math.max(1, measure(str, SPRAY_FONT, 100))
	return math.min(100, math.floor(math.min(w / wAt100 * 100, h / 1.05)))
end

-- A rollered block of darker paint where someone buffed out older graffiti before this went up:
-- it frames the lettering and gives the red something to stand on. Two slightly skewed passes
-- under the main one make the edges uneven; the body is streaked by the roller.
local BUFF = C.block:Lerp(C.wainscot, 0.75)
local function buffPatch(gui: Instance, x0: number, y0: number, x1: number, y1: number, rng: Random)
	local w, h = x1 - x0, y1 - y0
	for i, spec in { { -0.9, 0.55, 0.02 }, { 0.7, 0.6, -0.015 } } do
		local pass = frame(
			gui,
			"BuffPass" .. i,
			UDim2.fromOffset(x0 + spec[3] * w, y0 - spec[3] * h),
			UDim2.fromOffset(w, h),
			BUFF,
			spec[2],
			-1
		)
		pass.Rotation = spec[1]
		round(pass, UDim.new(0, h * 0.03))
	end
	local base = frame(gui, "Buff", UDim2.fromOffset(x0, y0), UDim2.fromOffset(w, h), BUFF, 0.08, 0)
	round(base, UDim.new(0, h * 0.03))
	local streaks = Instance.new("UIGradient")
	local keys = { NumberSequenceKeypoint.new(0, 0.3) }
	for i = 1, 8 do
		table.insert(keys, NumberSequenceKeypoint.new(i / 9 + rng:NextNumber(-0.03, 0.03), rng:NextNumber(0, 0.22)))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 0.35))
	streaks.Transparency = NumberSequence.new(keys)
	streaks.Parent = base
end

type SprayOpts = { runs: number, arrows: { string }?, patch: boolean? }

-- Shared builder: sprayed lettering centred on `cf` (width x height studs of lettering), with mist,
-- and on a larger backing carrier behind it: a buffed-out patch, painted arrows, runs and splatter.
-- Returns the lettering part, its main label and its gui.
local function sprayPanel(
	parent: Instance,
	name: string,
	cf: CFrame,
	width: number,
	height: number,
	str: string,
	color: Color3,
	opts: SprayOpts
)
	local rng = rngFor(str, cf)
	local pps = math.clamp(math.floor(110 / height), 20, 100)
	local margin = height * 0.18
	local arrows = opts.arrows or {}

	local letterCf = cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-1.2, 1.2)))
	local m = margin * pps
	local w, h = width * pps, height * pps
	local size = fittedSize(str, w, h)
	local placed = glyphs(str, size, w)

	-- the painted area: wider for arrows, taller for the runs that hang well below the letters
	local inkL, inkR = 0, w -- how far the letters reach, relative to the lettering box
	if #placed > 0 then
		inkL, inkR = placed[1].left, placed[#placed].left + placed[#placed].width
	end
	local side = (#arrows > 0 and height * 1.5 or 0) + margin * 2
	local drop = height * 1.3
	local backW, backH = width + side * 2, height + margin * 2 + drop
	local out = CFrame.new(0, 0, -0.02)
	local back = Kit.box(
		parent,
		name .. "Runs",
		Vector3.new(backW, backH, 0.02),
		letterCf * CFrame.new(0, -drop / 2, 0) * out,
		C.block,
		nil,
		INVISIBLE
	)

	-- The lettering part (drips fall from it, glow sits in it) owns the one SurfaceGui, drawn onto the
	-- bigger backing part: every layer of paint lives in a single gui, so ZIndex alone orders them
	-- (two overlapping transparent guis would swap order with camera distance).
	local part = Kit.box(
		parent,
		name,
		Vector3.new(width + margin * 2, height + margin * 2, 0.02),
		letterCf * out,
		C.block,
		nil,
		INVISIBLE
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Adornee = back
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.7
	gui.Brightness = 0.55 -- wet paint holds a little light; keeps it readable from the floor
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = part

	local offsetX = side * pps -- the lettering box starts here
	local bridges = {}
	for _, g in placed do
		if BOWLS[string.upper(g.char)] then
			-- the face leans right, so its middle (at mid-height) sits right of the advance centre
			table.insert(bridges, (g.left + g.width * 0.5 + size * 0.07) / w)
		end
	end
	local main = sprayText(
		gui,
		"Label",
		str,
		color,
		UDim2.fromOffset(offsetX, m),
		UDim2.fromOffset(w, h),
		h,
		rng,
		bridges,
		size * 0.04 / w
	)
	local baseY = m + h / 2 + size * 0.36

	local arrowSize = h * 0.62
	local leftReach, rightReach = offsetX + inkL, offsetX + inkR
	for _, dir in arrows do
		local onLeft = dir == "left"
		local x = onLeft and (offsetX + inkL - arrowSize * 0.75) or (offsetX + inkR + arrowSize * 0.75)
		arrow(gui, dir, UDim2.fromOffset(x, m + h / 2), UDim2.fromOffset(arrowSize, arrowSize), color, 3, true)
		if onLeft then
			leftReach = x - arrowSize / 2
		else
			rightReach = x + arrowSize / 2
		end
	end
	if opts.patch then
		local pad = h * 0.3
		buffPatch(gui, leftReach - pad, m - pad * 0.6, rightReach + pad, m + h + pad * 0.7, rng)
	end

	local slots = {}
	for _, g in placed do
		-- two candidate drip spots per glyph, near its stems
		table.insert(slots, offsetX + g.left + g.width * 0.28)
		table.insert(slots, offsetX + g.left + g.width * 0.72)
	end
	runs(gui, slots, baseY, drop * pps * 0.85, color:Lerp(PAINT_DARK, 0.15), rng, opts.runs)
	splatter(
		gui,
		backW * pps,
		(height + margin * 2) * pps,
		color,
		rng,
		math.floor(width * 5),
		Rect.new(leftReach, m, rightReach, m + h)
	)
	return part, main, gui
end

function Signage.stencil(parent: Instance, cf: CFrame, width: number, height: number, str: string): BasePart
	local part = sprayPanel(parent, "Stencil", cf, width, height, str, PAINT, {
		runs = math.floor(#str * 0.9),
		patch = true,
	})

	-- the paint catches the light a little, breathing red (DoorFX drives Brightness)
	local glow = Kit.pointLight(part, math.max(9, width), 0.25, false, Color3.fromRGB(255, 50, 40))
	glow.Name = "Glow"

	-- wet drops still falling from the lettering
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Drip"
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.Rate = 1.2
	drip.Lifetime = NumberRange.new(0.6, 1)
	drip.Speed = NumberRange.new(0, 0.2)
	drip.Acceleration = Vector3.new(0, -14, 0)
	drip.Size = NumberSequence.new(0.06)
	drip.Squash = NumberSequence.new(-1.2) -- stretch into drops
	drip.Color = ColorSequence.new(PAINT)
	drip.LightEmission = 0
	drip.LightInfluence = 1
	drip.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.3) })
	drip.Parent = part
	return part
end

------------------------------------------------------------------------------------------
-- Enamel plaque
------------------------------------------------------------------------------------------
-- A steel plate with cream enamel, an inset red rule, chips at the edges, corner screws and a rust
-- run from one of them. `cf` is the plate's centre on the wall. Returns the plate part and its gui.
local function plaque(parent: Instance, name: string, cf: CFrame, w: number, h: number, rng: Random)
	local pps = math.clamp(math.floor(150 / h), 20, 100)
	local tilt = cf * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-1.5, 1.5)))
	local plate = Kit.box(
		parent,
		name,
		Vector3.new(w, h, 0.1),
		tilt * CFrame.new(0, 0, -0.05),
		PLATE,
		Enum.Material.Metal,
		DETAIL
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0.65 -- a touch of self-light: enamel stays legible in the dim hall
	gui.Brightness = 0.32
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = plate
	local W, H = w * pps, h * pps

	local enamel =
		frame(gui, "Enamel", UDim2.fromOffset(W * 0.02, W * 0.02), UDim2.new(1, -W * 0.04, 1, -W * 0.04), ENAMEL, 0, 1)
	round(enamel, UDim.new(0, W * 0.035))
	local age = Instance.new("UIGradient") -- yellowed and grimy toward the bottom edge
	age.Rotation = 90 + rng:NextNumber(-12, 12)
	age.Color = ColorSequence.new({ -- multiplies the enamel colour
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.7, Color3.new(0.98, 0.95, 0.9)),
		ColorSequenceKeypoint.new(1, Color3.new(0.8, 0.74, 0.64)),
	})
	age.Parent = enamel
	local rule = frame(
		gui,
		"Rule",
		UDim2.fromOffset(W * 0.055, W * 0.055),
		UDim2.new(1, -W * 0.11, 1, -W * 0.11),
		ENAMEL_RED,
		1,
		2
	)
	round(rule, UDim.new(0, W * 0.02))
	local stroke = Instance.new("UIStroke")
	stroke.Color = ENAMEL_RED
	stroke.Thickness = math.max(2, H * 0.025)
	stroke.Parent = rule

	-- chips knocked out of the enamel along the edges, showing the dark steel
	for _ = 1, rng:NextInteger(3, 6) do
		local side = rng:NextInteger(1, 4)
		local d = rng:NextNumber(0.03, 0.07) * H
		local x = (side == 1 or side == 2) and rng:NextNumber(0.05, 0.95) * W
			or (side == 3 and rng:NextNumber(0, W * 0.02) or W - d - rng:NextNumber(0, W * 0.02))
		local y = (side == 3 or side == 4) and rng:NextNumber(0.1, 0.9) * H
			or (side == 1 and rng:NextNumber(0, H * 0.03) or H - d - rng:NextNumber(0, H * 0.03))
		local chip =
			frame(gui, "Chip", UDim2.fromOffset(x, y), UDim2.fromOffset(d * rng:NextNumber(1, 1.8), d), PLATE, 0, 6)
		chip.Rotation = rng:NextNumber(-30, 30)
		round(chip, UDim.new(rng:NextNumber(0.2, 0.5), 0))
	end

	-- screws in the corners, and a rust run from one of them
	local sx, sy = w / 2 - 0.16, h / 2 - 0.16
	local rustCorner = rng:NextInteger(1, 2)
	for i, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
		local screw = Kit.cylinder(
			parent,
			"Screw",
			0.05,
			0.13,
			(tilt * CFrame.new(c[1] * sx, c[2] * sy, -0.11)).Position,
			"z",
			Color3.fromRGB(120, 108, 90),
			Enum.Material.Metal,
			DETAIL
		)
		screw.CFrame = tilt * CFrame.new(c[1] * sx, c[2] * sy, -0.11) * CFrame.Angles(0, math.rad(90), 0)
		if i == rustCorner then
			local rx = W / 2 + c[1] * sx * pps
			local run = frame(
				gui,
				"Rust",
				UDim2.fromOffset(rx - H * 0.02, H / 2 - sy * pps),
				UDim2.fromOffset(H * 0.04, H * rng:NextNumber(0.3, 0.55)),
				Color3.fromRGB(122, 64, 34),
				0,
				5
			)
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.4, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = run
		end
	end
	return plate, gui, W, H
end

function Signage.doorSign(pad: Model, cf: CFrame, mode: string, capacity: number): BasePart
	local title = string.upper(mode)
	local rng = rngFor(title, cf)
	local w, h = 4.4, 2.3
	local sign, gui, W, H = plaque(pad, "Sign", cf, w, h, rng)

	-- title, with a faint dark shadow under it that follows it about
	local shade = text(gui, "TitleShade", title, PLAQUE_FONT, Color3.fromRGB(70, 20, 16), 3)
	shade.Position = UDim2.fromOffset(W * 0.1 + 2, H * 0.1 + 3)
	shade.Size = UDim2.fromOffset(W * 0.8, H * 0.5)
	shade.TextTransparency = 0.75
	shade:SetAttribute("SignLayer", true)
	local titleLabel = text(gui, "Title", title, PLAQUE_FONT, ENAMEL_RED, 4)
	titleLabel.Position = UDim2.fromOffset(W * 0.1, H * 0.1)
	titleLabel.Size = UDim2.fromOffset(W * 0.8, H * 0.5)

	-- live count on a black strip, like a mechanical counter window
	local strip = frame(
		gui,
		"StatusStrip",
		UDim2.fromOffset(W * 0.17, H * 0.62),
		UDim2.fromOffset(W * 0.66, H * 0.26),
		STRIP,
		0,
		4
	)
	round(strip, UDim.new(0, H * 0.04))
	local status = text(gui, "Status", string.format("0 / %d", capacity), COUNT_FONT, CREAM, 5)
	status.Position = UDim2.fromOffset(W * 0.19, H * 0.645)
	status.Size = UDim2.fromOffset(W * 0.62, H * 0.21)

	return sign
end

------------------------------------------------------------------------------------------
-- Wayfinding
------------------------------------------------------------------------------------------
type WallSignOpts = {
	style: string?,
	width: number?,
	height: number?,
	color: Color3?,
	arrow: string?,
}

function Signage.wallSign(parent: Instance, cf: CFrame, str: string, opts: WallSignOpts?): Model
	local o: WallSignOpts = opts or {}
	local style = o.style or "plaque"
	local model = Kit.folder(parent, "WallSign")
	model:SetAttribute("Text", str)
	local rng = rngFor(str, cf)
	local arrowDir = o.arrow
	local hasArrow = arrowDir ~= nil and ARROWS[arrowDir] ~= nil

	if style == "stencil" then
		local height = o.height or 1.4
		local width = o.width or math.max(height * 2, #str * height * 0.5)
		sprayPanel(model, "Lettering", cf, width, height, str, o.color or PAINT, {
			runs = math.floor(#str * 0.4),
			arrows = hasArrow and { arrowDir :: string } or nil,
			patch = true,
		})
	elseif style == "lit" then
		local height = o.height or 1.6
		local width = o.width or math.max(height * 2.5, #str * height * 0.55 + (hasArrow and height or 0) + height)
		local color = o.color or Kit.C.warm
		-- dark steel box standing off the wall, frosted face lit from inside
		Kit.box(
			model,
			"Case",
			Vector3.new(width + 0.3, height + 0.3, 0.5),
			cf * CFrame.new(0, 0, -0.25),
			Color3.fromRGB(28, 26, 24),
			Enum.Material.Metal,
			{ CanCollide = false }
		)
		local face, gui =
			carrier(model, "Face", cf, Vector2.new(width, height), 0.51, math.clamp(math.floor(130 / height), 20, 100))
		face.Color = color
		face.Material = Enum.Material.Neon
		face.Transparency = 0.2
		face:SetAttribute("NeonFlicker", true)
		gui.LightInfluence = 0
		gui.Brightness = 1.6
		local W, H = width * gui.PixelsPerStud, height * gui.PixelsPerStud
		local panel = frame(
			gui,
			"Panel",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			color:Lerp(Color3.new(1, 1, 1), 0.35),
			0,
			1
		)
		local glow = Instance.new("UIGradient") -- hotter in the middle where the tubes are
		glow.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0.72, 0.68, 0.66)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(0.72, 0.68, 0.66)),
		})
		glow.Parent = panel
		local ink = Color3.fromRGB(36, 16, 12)
		-- painted inner border, like the lettering, on the inside of the diffuser
		local rule =
			frame(gui, "Rule", UDim2.fromOffset(H * 0.08, H * 0.08), UDim2.new(1, -H * 0.16, 1, -H * 0.16), ink, 1, 2)
		round(rule, UDim.new(0, H * 0.06))
		local ruleStroke = Instance.new("UIStroke")
		ruleStroke.Color = ink
		ruleStroke.Thickness = math.max(2, H * 0.03)
		ruleStroke.Transparency = 0.2
		ruleStroke.Parent = rule
		local textW = hasArrow and W - H or W
		local label = text(gui, "Label", str, PLAQUE_FONT, ink, 3)
		label.Position = UDim2.fromOffset(H * 0.3 + (arrowDir == "left" and H * 0.8 or 0), H * 0.14)
		label.Size = UDim2.fromOffset(textW - H * 0.6, H * 0.72)
		if hasArrow then
			arrow(
				gui,
				arrowDir :: string,
				UDim2.fromOffset(arrowDir == "left" and H * 0.65 or W - H * 0.65, H / 2),
				UDim2.fromOffset(H * 0.6, H * 0.6),
				ink,
				3,
				false
			)
		end
		local light = Kit.pointLight(face, 8, 0.7, false, color)
		light.Name = "Spill"
	else
		local height = o.height or 1.4
		local width = o.width
			or math.max(height * 2.4, #str * height * 0.3 + height * 0.9 + (hasArrow and height * 0.8 or 0))
		local _, gui, W, H = plaque(model, "Plate", cf, width, height, rng)
		local ink = o.color or ENAMEL_RED
		local pad = H * 0.16
		local textW = W - pad * 2 - (hasArrow and H * 0.75 or 0)
		local label = text(gui, "Label", str, PLAQUE_FONT, ink, 4)
		label.Position = UDim2.fromOffset(pad + (arrowDir == "left" and H * 0.75 or 0), H * 0.2)
		label.Size = UDim2.fromOffset(textW, H * 0.6)
		if hasArrow then
			arrow(
				gui,
				arrowDir :: string,
				UDim2.fromOffset(arrowDir == "left" and pad + H * 0.35 or W - pad - H * 0.35, H / 2),
				UDim2.fromOffset(H * 0.5, H * 0.5),
				ink,
				4,
				false
			)
		end
	end
	return model
end

return Signage
