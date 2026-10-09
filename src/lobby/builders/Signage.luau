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

------------------------------------------------------------------------------------------
-- 3D signage kit: a part-built stroke font, bevelled panels, LED rows, bulbs, halos, FX tagging
------------------------------------------------------------------------------------------
--[[
	Every sign is drawn in a "view" frame: X to the viewer's right, Y up, +Z out toward the viewer.
	z = 0 is the mounting surface (the wall, or a panel's front face); things stand proud at z > 0.

	Signage.text3D(parent, view, str, spec) builds lettering centred on view (or left-aligned) from a
	block stroke font (A-Z, 0-9, space · - ! ' /). Each glyph is a Model "Letter<i>" (attributes
	Letter = i, Char, U = its centre u, V) holding one part per stroke per layer; layer names are free
	but SignFX knows three: "Body" (the extruded return), "Face" (the lit / painted cap: its Color is
	animated) and "Glow" (a rim behind: its Transparency is animated).

	SignFX contract (client/SignFX.client.luau animates every Model tagged "SignFX"):
	  Model.WorldPivot = the view frame. Attributes on the Model:
	    SignStyle  string   informational, plus: "plaque" (tension turns the Edge hot), "holo" (scan sweep)
	    Width, Height  number  panel / lettering extents in the view frame (sweep travel, haze size)
	    Accent     Color3   glow colour: halos, haze tint, sheen
	    Pulse      number   seconds per breath of the Glow rims / halos / lights (0 or nil = steady)
	    PulseAmt   number   0..1 depth of the breath (default 0.5)
	    Sweep      number   seconds between sheen sweeps across the face (nil = none); SweepColor Color3
	    Flicker    number   mean seconds between one letter stuttering (nil = never)
	    Haze       string   "haze" | "dust" | "motes" | "embers" | "drips" emitted from child part HazeVolume
	    HazeRate   number   particles/s at full graphics quality (default per kind)
	    Bob        number   studs of gentle float (the whole model, about WorldPivot)
	    Sway       number   degrees of swing about the top edge (hanging signs); SwayPivot CFrame (default pivot)
	    Chase      number   speed of the LedSeg / Bulb chase (nil = 1)
	    Tension    number   0..1 written client-side by DoorFX (PICK A DOOR + door plaques): faster pulse,
	                         brighter glow, more drips, more flicker
	    Blink      number   os.clock() stamp written client-side by DoorFX: a quick dropout of every letter
	    Cull       number   studs beyond which nothing animates (default 90)
	  Named descendants it animates:
	    Letter models (Face / Glow parts), LedSeg (Row, Index, U), Bulb (Index), Chevron (Step), Edge
	    (neon trim: breathes; hot red with Tension on plaques), Eye (Ball, hidden; EyeHalo BillboardGui),
	    DripRun parts (paint runs: a ParticleEmitter drop falls from the bottom of each), BillboardGui
	    "Halo" (Brightness breathes), every Light (Brightness breathes).
	  ObjectValue "Ghost" (child of the Model) -> a TextLabel whose Text DoorFX swaps for glitch words.
	    The label rests invisible; while its Text differs from its GhostBase attribute the 3D letters
	    cut out and jitter and the label shows instead (so "ONLY ONE OPENS" flashes up in their place).
]]

type Seg = { number }
type Glyph3D = { adv: number?, segs: { Seg } }

-- Centre-line strokes on a unit cell (x 0..1 left to right, y 0..1 bottom to top); { x0, y0, x1, y1 }.
local O_BOX = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 1, 1, 1 }, { 0, 0, 1, 0 } }
local function with(base: { Seg }, extra: { Seg }): { Seg }
	local out = table.clone(base)
	for _, s in extra do
		table.insert(out, s)
	end
	return out
end
local P_SEGS = { { 0, 0, 0, 1 }, { 0, 1, 1, 1 }, { 1, 1, 1, 0.5 }, { 0, 0.5, 1, 0.5 } }
local FONT: { [string]: Glyph3D } = {
	A = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 1, 1, 1 }, { 0, 0.48, 1, 0.48 } } },
	B = {
		segs = {
			{ 0, 0, 0, 1 },
			{ 0, 1, 0.8, 1 },
			{ 0.8, 1, 0.8, 0.5 },
			{ 0, 0.5, 1, 0.5 },
			{ 1, 0.5, 1, 0 },
			{ 0, 0, 1, 0 },
		},
	},
	C = { segs = { { 0, 0, 0, 1 }, { 0, 1, 1, 1 }, { 0, 0, 1, 0 }, { 1, 1, 1, 0.78 }, { 1, 0, 1, 0.22 } } },
	D = {
		segs = {
			{ 0, 0, 0, 1 },
			{ 0, 1, 0.68, 1 },
			{ 0.68, 1, 1, 0.7 },
			{ 1, 0.7, 1, 0.3 },
			{ 1, 0.3, 0.68, 0 },
			{ 0.68, 0, 0, 0 },
		},
	},
	E = { segs = { { 0, 0, 0, 1 }, { 0, 1, 1, 1 }, { 0, 0.5, 0.75, 0.5 }, { 0, 0, 1, 0 } } },
	F = { segs = { { 0, 0, 0, 1 }, { 0, 1, 1, 1 }, { 0, 0.5, 0.75, 0.5 } } },
	G = {
		segs = {
			{ 0, 0, 0, 1 },
			{ 0, 1, 1, 1 },
			{ 1, 1, 1, 0.78 },
			{ 0, 0, 1, 0 },
			{ 1, 0, 1, 0.48 },
			{ 1, 0.48, 0.5, 0.48 },
		},
	},
	H = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 0.5, 1, 0.5 } } },
	I = { adv = 0.6, segs = { { 0.5, 0, 0.5, 1 }, { 0, 1, 1, 1 }, { 0, 0, 1, 0 } } },
	J = { segs = { { 1, 1, 1, 0 }, { 1, 0, 0, 0 }, { 0, 0, 0, 0.3 }, { 0.35, 1, 1, 1 } } },
	K = { segs = { { 0, 0, 0, 1 }, { 0, 0.5, 0.4, 0.5 }, { 0.4, 0.5, 1, 1 }, { 0.4, 0.5, 1, 0 } } },
	L = { segs = { { 0, 0, 0, 1 }, { 0, 0, 1, 0 } } },
	M = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 1, 0.5, 0.45 }, { 0.5, 0.45, 1, 1 } } },
	N = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 1, 1, 0 } } },
	O = { segs = O_BOX },
	P = { segs = P_SEGS },
	Q = { segs = with(O_BOX, { { 0.55, 0.35, 1, 0 } }) },
	R = { segs = with(P_SEGS, { { 0.4, 0.5, 1, 0 } }) },
	S = {
		segs = {
			{ 0, 1, 1, 1 },
			{ 1, 1, 1, 0.8 },
			{ 0, 1, 0, 0.5 },
			{ 0, 0.5, 1, 0.5 },
			{ 1, 0.5, 1, 0 },
			{ 0, 0, 1, 0 },
			{ 0, 0, 0, 0.2 },
		},
	},
	T = { segs = { { 0, 1, 1, 1 }, { 0.5, 1, 0.5, 0 } } },
	U = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 0, 1, 0 } } },
	V = { segs = { { 0, 1, 0.5, 0 }, { 0.5, 0, 1, 1 } } },
	W = { segs = { { 0, 0, 0, 1 }, { 1, 0, 1, 1 }, { 0, 0, 1, 0 }, { 0.5, 0, 0.5, 0.6 } } },
	X = { segs = { { 0, 1, 1, 0 }, { 0, 0, 1, 1 } } },
	Y = { segs = { { 0, 1, 0.5, 0.5 }, { 1, 1, 0.5, 0.5 }, { 0.5, 0.5, 0.5, 0 } } },
	Z = { segs = { { 0, 1, 1, 1 }, { 1, 1, 0, 0 }, { 0, 0, 1, 0 } } },
	["0"] = { segs = with(O_BOX, { { 0.3, 0.3, 0.7, 0.7 } }) },
	["1"] = { adv = 0.6, segs = { { 0.5, 0, 0.5, 1 }, { 0.5, 1, 0.05, 0.78 }, { 0, 0, 1, 0 } } },
	["2"] = { segs = { { 0, 1, 1, 1 }, { 1, 1, 1, 0.5 }, { 1, 0.5, 0, 0.5 }, { 0, 0.5, 0, 0 }, { 0, 0, 1, 0 } } },
	["3"] = { segs = { { 0, 1, 1, 1 }, { 1, 1, 1, 0 }, { 0.3, 0.5, 1, 0.5 }, { 0, 0, 1, 0 } } },
	["4"] = { segs = { { 0, 1, 0, 0.45 }, { 0, 0.45, 1, 0.45 }, { 1, 1, 1, 0 } } },
	["5"] = { segs = { { 1, 1, 0, 1 }, { 0, 1, 0, 0.5 }, { 0, 0.5, 1, 0.5 }, { 1, 0.5, 1, 0 }, { 1, 0, 0, 0 } } },
	["6"] = { segs = { { 1, 1, 0, 1 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 1, 0, 1, 0.5 }, { 1, 0.5, 0, 0.5 } } },
	["7"] = { segs = { { 0, 1, 1, 1 }, { 1, 1, 0.4, 0 } } },
	["8"] = { segs = with(O_BOX, { { 0, 0.5, 1, 0.5 } }) },
	["9"] = { segs = { { 0, 0, 1, 0 }, { 1, 0, 1, 1 }, { 1, 1, 0, 1 }, { 0, 1, 0, 0.5 }, { 0, 0.5, 1, 0.5 } } },
	["·"] = { adv = 0.45, segs = { { 0.5, 0.5, 0.5, 0.5 } } },
	["-"] = { adv = 0.7, segs = { { 0.1, 0.5, 0.9, 0.5 } } },
	["!"] = { adv = 0.4, segs = { { 0.5, 0.32, 0.5, 1 }, { 0.5, 0, 0.5, 0 } } },
	["'"] = { adv = 0.35, segs = { { 0.5, 1, 0.5, 0.72 } } },
	["/"] = { segs = { { 0, 0, 1, 1 } } },
}
Signage.FONT = FONT

-- One layer of extrusion: every stroke of every glyph gets one part per layer.
export type Layer3D = {
	name: string,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	grow: number?, -- studs added to the stroke's length and thickness (negative = inset)
	z: number, -- back of the layer (view z)
	d: number, -- thickness along z
}
export type Text3DSpec = {
	height: number,
	width: number?, -- cell width as a fraction of height (default 0.78)
	gap: number?, -- letter spacing, fraction of height (default 0.2)
	stroke: number?, -- stroke thickness, fraction of height (default 0.2)
	space: number?, -- advance of a space, fraction of height (default 0.5)
	align: string?, -- "center" (default) or "left" (u = 0 is the left edge)
	layers: { Layer3D },
	jitter: { rot: number?, v: number?, seed: number? }?, -- hand-made wobble per letter (degrees, studs)
	name: string?, -- glyph model name prefix (default "Letter")
}

local function glyphOf(ch: string): Glyph3D?
	return FONT[string.upper(ch)]
end

-- utf8-aware characters of a string (so "·" is one glyph)
local function chars(str: string): { string }
	local out = {}
	for _, code in utf8.codes(str) do
		table.insert(out, utf8.char(code))
	end
	return out
end

local function advanceOf(ch: string, spec: Text3DSpec): number
	local h = spec.height
	if ch == " " then
		return h * (spec.space or 0.5)
	end
	local g = glyphOf(ch)
	return h * (spec.width or 0.78) * (g and g.adv or 1)
end

-- Overall width of `str` set in `spec`.
function Signage.measure3D(str: string, spec: Text3DSpec): number
	local list = chars(str)
	local total, gap = 0, spec.height * (spec.gap or 0.2)
	for i, ch in list do
		total += advanceOf(ch, spec)
		if i < #list and ch ~= " " and list[i + 1] ~= " " then
			total += gap
		end
	end
	return total
end

-- Builds `str` in 3D. Returns the glyph models (in order, spaces skipped) and the total width.
function Signage.text3D(parent: Instance, view: CFrame, str: string, spec: Text3DSpec): ({ Model }, number)
	local h = spec.height
	local t = h * (spec.stroke or 0.2)
	local gap = h * (spec.gap or 0.2)
	local list = chars(str)
	local width = Signage.measure3D(str, spec)
	local u = if spec.align == "left" then 0 else -width / 2
	local jitter = spec.jitter
	local rng = Random.new(jitter and jitter.seed or #str)
	local letters = {}
	for i, ch in list do
		local adv = advanceOf(ch, spec)
		local g = glyphOf(ch)
		if ch ~= " " and g then
			local cu = u + adv / 2
			local cv = 0
			local rot = 0
			if jitter then
				cv = rng:NextNumber(-1, 1) * (jitter.v or 0)
				rot = math.rad(rng:NextNumber(-1, 1) * (jitter.rot or 0))
			end
			local model = Kit.folder(parent, (spec.name or "Letter") .. (#letters + 1))
			model:SetAttribute("Letter", #letters + 1)
			model:SetAttribute("Char", ch)
			model:SetAttribute("U", cu)
			model:SetAttribute("V", cv)
			local cell = view * CFrame.new(cu, cv, 0) * CFrame.Angles(0, 0, rot)
			local cw = adv
			for _, s in g.segs do
				local x0 = -cw / 2 + t / 2 + s[1] * (cw - t)
				local y0 = -h / 2 + t / 2 + s[2] * (h - t)
				local x1 = -cw / 2 + t / 2 + s[3] * (cw - t)
				local y1 = -h / 2 + t / 2 + s[4] * (h - t)
				local dx, dy = x1 - x0, y1 - y0
				local len = math.sqrt(dx * dx + dy * dy)
				local straight = math.abs(dx) < 1e-4 or math.abs(dy) < 1e-4
				local long = if straight then len + t else len + t * 0.35
				local angle = if len > 1e-4 then math.atan2(dy, dx) else 0
				local mid = cell * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, angle)
				for _, layer in spec.layers do
					local grow = layer.grow or 0
					local part = Kit.box(
						model,
						layer.name,
						Vector3.new(math.max(0.02, long + grow), math.max(0.02, t + grow), layer.d),
						mid * CFrame.new(0, 0, layer.z + layer.d / 2),
						layer.color,
						layer.material,
						DETAIL
					)
					part.Transparency = layer.transparency or 0
					part.Reflectance = layer.reflectance or 0
				end
			end
			model.WorldPivot = cell
			table.insert(letters, model)
		end
		u += adv
		if i < #list and ch ~= " " and list[i + 1] ~= " " then
			u += gap
		end
	end
	return letters, width
end

export type PanelSpec = {
	bodyColor: Color3,
	bodyMaterial: Enum.Material?,
	faceColor: Color3,
	faceMaterial: Enum.Material?,
	faceReflectance: number?,
	bevelColor: Color3,
	bevelMaterial: Enum.Material?,
	bevelReflectance: number?,
	bevel: number?, -- chamfer size (default 0.18)
	name: string?,
}

-- A bevelled panel w x h x d whose FRONT face is at view z = 0 (it extends back to z = -d).
-- Brushed body set back by the bevel, a face slab in front, chamfered wedges round the front edges
-- (the STORE construction). Returns the body and the face.
function Signage.panel(parent: Instance, view: CFrame, w: number, h: number, d: number, spec: PanelSpec)
	local c = math.min(spec.bevel or 0.18, d * 0.8, h / 3)
	local prefix = spec.name or "Panel"
	local body = Kit.box(
		parent,
		prefix .. "Body",
		Vector3.new(w, h, d - c),
		view * CFrame.new(0, 0, -d + (d - c) / 2),
		spec.bodyColor,
		spec.bodyMaterial or Enum.Material.Metal,
		DETAIL
	)
	local face = Kit.box(
		parent,
		prefix .. "Face",
		Vector3.new(w - 2 * c, h - 2 * c, c),
		view * CFrame.new(0, 0, -c / 2),
		spec.faceColor,
		spec.faceMaterial or Enum.Material.SmoothPlastic,
		DETAIL
	)
	face.Reflectance = spec.faceReflectance or 0
	local zb = -c / 2
	local function at(u: number, v: number): CFrame
		return view * CFrame.new(u, v, zb)
	end
	for _, s in
		{
			{ Vector3.new(w, c, c), at(0, h / 2 - c / 2) * CFrame.Angles(0, math.pi, 0) },
			{ Vector3.new(w, c, c), at(0, -h / 2 + c / 2) * CFrame.Angles(math.pi, 0, 0) },
			{
				Vector3.new(h - 2 * c, c, c),
				at(w / 2 - c / 2, 0) * CFrame.Angles(0, 0, -math.pi / 2) * CFrame.Angles(0, math.pi, 0),
			},
			{
				Vector3.new(h - 2 * c, c, c),
				at(-w / 2 + c / 2, 0) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0, math.pi, 0),
			},
		}
	do
		local bevel = Kit.wedge(
			parent,
			prefix .. "Bevel",
			s[1],
			s[2],
			spec.bevelColor,
			spec.bevelMaterial or Enum.Material.Metal,
			DETAIL
		)
		bevel.Reflectance = spec.bevelReflectance or 0.15
	end
	return body, face
end

-- A rectangular trim of four bars (name "Edge" by default: SignFX breathes it) round a w x h
-- rectangle centred on view, `thick` wide, standing from z to z + depth.
function Signage.edgeFrame(
	parent: Instance,
	view: CFrame,
	w: number,
	h: number,
	thick: number,
	z: number,
	depth: number,
	color: Color3,
	material: Enum.Material?,
	name: string?
): { BasePart }
	local out = {}
	for _, s in
		{
			{ Vector3.new(w, thick, depth), 0, h / 2 - thick / 2 },
			{ Vector3.new(w, thick, depth), 0, -h / 2 + thick / 2 },
			{ Vector3.new(thick, h - 2 * thick, depth), -w / 2 + thick / 2, 0 },
			{ Vector3.new(thick, h - 2 * thick, depth), w / 2 - thick / 2, 0 },
		}
	do
		table.insert(
			out,
			Kit.box(
				parent,
				name or "Edge",
				s[1],
				view * CFrame.new(s[2], s[3], z + depth / 2),
				color,
				material or Enum.Material.Neon,
				DETAIL
			)
		)
	end
	return out
end

-- A recessed run of `segs` LED segments along u at height v (SignFX chases them; Row 1 runs right,
-- any other row left). Returns the segments.
function Signage.ledRow(
	parent: Instance,
	view: CFrame,
	length: number,
	v: number,
	z: number,
	segs: number,
	color: Color3,
	row: number,
	thick: number?
): { BasePart }
	local th = thick or 0.05
	Kit.box(
		parent,
		"LedChannel",
		Vector3.new(length + 0.1, th + 0.07, 0.02),
		view * CFrame.new(0, v, z + 0.01),
		Color3.fromRGB(6, 5, 5),
		Enum.Material.SmoothPlastic,
		DETAIL
	)
	local out = {}
	for i = 1, segs do
		local u = -length / 2 + (i - 0.5) * length / segs
		local seg = Kit.box(
			parent,
			"LedSeg",
			Vector3.new(length / segs - 0.06, th, 0.02),
			view * CFrame.new(u, v, z + 0.025),
			color,
			Enum.Material.Neon,
			DETAIL
		)
		seg:SetAttribute("Row", row)
		seg:SetAttribute("Index", i)
		seg:SetAttribute("U", u)
		table.insert(out, seg)
	end
	return out
end

-- Marquee bulbs (Neon balls named "Bulb", Index in order) at view-frame points (u, v), at depth z.
function Signage.bulbs(
	parent: Instance,
	view: CFrame,
	points: { Vector2 },
	z: number,
	diameter: number,
	color: Color3,
	socket: Color3?
): { BasePart }
	local out = {}
	for i, p in points do
		if socket then
			local s = Kit.box(
				parent,
				"Socket",
				Vector3.new(diameter * 0.5, diameter * 1.15, diameter * 1.15),
				view * CFrame.new(p.X, p.Y, z + diameter * 0.2) * CFrame.Angles(0, math.rad(90), 0),
				socket,
				Enum.Material.Metal,
				DETAIL
			)
			s.Shape = Enum.PartType.Cylinder
		end
		local b = Kit.box(
			parent,
			"Bulb",
			Vector3.new(diameter, diameter, diameter),
			view * CFrame.new(p.X, p.Y, z + diameter * 0.55),
			color,
			Enum.Material.Neon,
			DETAIL
		)
		b.Shape = Enum.PartType.Ball
		b:SetAttribute("Index", i)
		table.insert(out, b)
	end
	return out
end

-- Soft bloom with no hot core (sits behind lettering without washing it out). Named "Halo".
function Signage.softHalo(part: BasePart, studs: number, color: Color3, brightness: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Halo"
	gui.Size = UDim2.fromScale(studs, studs)
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1.3
	gui.MaxDistance = 110
	gui.Parent = part
	for i, s in { { 1, 0.965 }, { 0.74, 0.945 }, { 0.5, 0.925 }, { 0.3, 0.9 } } do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(s[1], s[1])
		ring.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), (i - 1) / 6)
		ring.BackgroundTransparency = s[2]
		ring.BorderSizePixel = 0
		ring.ZIndex = i
		ring.Parent = gui
		round(ring, UDim.new(1, 0))
	end
	return gui
end

-- An invisible anchor part at view (u, v, z) carrying a soft halo (for per-letter / per-feature bloom).
function Signage.haloAt(
	parent: Instance,
	view: CFrame,
	u: number,
	v: number,
	z: number,
	studs: number,
	color: Color3,
	brightness: number?
): BasePart
	local anchor =
		Kit.box(parent, "HaloAnchor", Vector3.new(0.2, 0.2, 0.2), view * CFrame.new(u, v, z), color, nil, INVISIBLE)
	Signage.softHalo(anchor, studs, color, brightness)
	return anchor
end

-- The invisible volume SignFX fills with haze / dust / motes / embers (view-frame centre and size).
function Signage.hazeVolume(parent: Instance, view: CFrame, u: number, v: number, z: number, size: Vector3): BasePart
	return Kit.box(parent, "HazeVolume", size, view * CFrame.new(u, v, z), Color3.new(1, 1, 1), nil, INVISIBLE)
end

-- Marks `model` as an animated sign (see the SignFX contract above). `view` becomes its pivot.
function Signage.tagFX(model: Model, view: CFrame, style: string, attrs: { [string]: any })
	model.WorldPivot = view
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("SignStyle", style)
	for key, value in attrs do
		model:SetAttribute(key, value)
	end
	model:AddTag("SignFX")
end

-- Points every 'step' studs round a w x h rectangle (for marquee bulbs), clockwise from top-left.
function Signage.rectPoints(w: number, h: number, step: number): { Vector2 }
	local out = {}
	local nx = math.max(1, math.floor(w / step + 0.5))
	local ny = math.max(1, math.floor(h / step + 0.5))
	for i = 0, nx - 1 do
		table.insert(out, Vector2.new(-w / 2 + i * w / nx, h / 2))
	end
	for i = 0, ny - 1 do
		table.insert(out, Vector2.new(w / 2, h / 2 - i * h / ny))
	end
	for i = 0, nx - 1 do
		table.insert(out, Vector2.new(w / 2 - i * w / nx, -h / 2))
	end
	for i = 0, ny - 1 do
		table.insert(out, Vector2.new(-w / 2, -h / 2 + i * h / ny))
	end
	return out
end

------------------------------------------------------------------------------------------
-- PICK A DOOR: the hero sign over the clock
------------------------------------------------------------------------------------------
--[[
	Two lines of thick red letters standing proud of a rollered-out patch of wall: spray-painted steel
	(deep red returns, a wet glossy cap), a misregistered dark first coat and a red neon rim on the
	wall behind each stroke so the paint seems to bleed light, runs of paint hanging under the
	letters as real geometry with beads at their ends, and an eye hidden in each O of DOOR.

	Instances (DoorFX + SignFX depend on them):
	  queue.Stencil      thin invisible strip along the bottom of DOOR: SurfaceGui (Adornee = the
	                     StencilPatch part) with the ghost Label (rests invisible; DoorFX swaps its text
	                     for glitch words and SignFX shows it in place of the letters), PointLight Glow,
	                     ParticleEmitter Drip (drops falling off the letters)
	  queue.StencilSign  the 3D sign (SignFX tag, style "spray"; DoorFX writes Tension / Blink on it)
	`centre` is the point on the wall between the two lines; `normal` points out into the room.
]]
local HERO_RED_BODY = Color3.fromRGB(112, 16, 13)
local HERO_RIM = Color3.fromRGB(150, 12, 8) -- Neon renders far paler than its colour: keep it deep
local HERO_HOT = Color3.fromRGB(255, 50, 40)

function Signage.heroStencil(queue: Instance, centre: Vector3, normal: Vector3, maxWidth: number): Model
	local view = CFrame.lookAt(centre, centre - normal) * CFrame.Angles(0, 0, math.rad(-1.2))
	local sign = Kit.folder(queue, "StencilSign")
	local rng = Random.new(4242)

	-- lettering: "PICK A" over a slightly bigger "DOOR", both fitted inside maxWidth
	local function spec(h: number): Text3DSpec
		return {
			height = h,
			width = 0.78,
			gap = 0.17,
			stroke = 0.215,
			layers = {
				-- first coat sprayed through the stencil a little off: a dark outline on the wall
				{ name = "Under", color = PAINT_DARK, z = 0.004, d = 0.012, grow = 0.13 },
				{
					name = "Glow",
					color = HERO_RIM,
					material = Enum.Material.Neon,
					transparency = 0.42,
					z = 0.02,
					d = 0.02,
					grow = 0.34,
				},
				{ name = "Body", color = HERO_RED_BODY, z = 0.12, d = 0.5 },
				{
					name = "Face",
					color = PAINT,
					reflectance = 0.12,
					z = 0.62,
					d = 0.04,
					grow = -0.05,
				},
			},
			jitter = { rot = 2.2, v = 0.07, seed = 77 },
		}
	end
	local topH, botH = 2.5, 2.65
	local topW = Signage.measure3D("PICK A", spec(topH))
	local botW = Signage.measure3D("DOOR", spec(botH))
	local k = math.min(1, maxWidth / math.max(topW, botW))
	topH, botH = topH * k, botH * k
	local topV, botV = 0.18 + topH / 2, -0.18 - botH / 2
	local top = Kit.folder(sign, "Line1")
	local topLetters = Signage.text3D(top, view * CFrame.new(0, topV, 0), "PICK A", spec(topH))
	local bot = Kit.folder(sign, "Line2")
	local botLetters, botWidth = Signage.text3D(bot, view * CFrame.new(0, botV, 0), "DOOR", spec(botH))
	-- one index across both lines, so SignFX picks flicker letters from the whole sign
	local index = 0
	for _, list in { topLetters, botLetters } do
		for _, letter in list do
			index += 1
			letter:SetAttribute("Letter", index)
			letter.Parent = sign
			letter.Name = "Letter" .. index
		end
	end
	top:Destroy()
	bot:Destroy()
	local width = math.max(topW, botW) * k
	local height = topH + botH + 0.36

	-- an eye in each O of DOOR, set back in its counter (SignFX opens them, rarely)
	for _, letter in botLetters do
		if letter:GetAttribute("Char") == "O" then
			local cell = letter.WorldPivot
			local eye = Kit.box(
				letter,
				"Eye",
				Vector3.new(0.26, 0.26, 0.26) * k,
				cell * CFrame.new(0, 0.05, 0.3),
				Color3.fromRGB(255, 120, 100),
				Enum.Material.Neon,
				DETAIL
			)
			eye.Shape = Enum.PartType.Ball
			eye.Transparency = 1
			local halo = Signage.softHalo(eye, 1.4, HERO_HOT, 1.6)
			halo.Name = "EyeHalo"
			halo.Enabled = false
		end
	end

	-- runs of paint down the wall from the bottoms of the strokes, with a bead at each end. Under
	-- DOOR they run long except over the clock (|u| < 2.2), under PICK A they just hang.
	local function run(u: number, v: number, len: number)
		local w = rng:NextNumber(0.09, 0.15)
		local part = Kit.box(
			sign,
			"DripRun",
			Vector3.new(w, len, 0.03),
			view * CFrame.new(u, v - len / 2, 0.025),
			PAINT:Lerp(PAINT_DARK, rng:NextNumber(0.05, 0.3)),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
		part.Reflectance = 0.1
		local bead = Kit.box(
			sign,
			"DripBead",
			Vector3.new(w * 1.7, w * 2.1, w * 1.2),
			view * CFrame.new(u, v - len, 0.03),
			PAINT:Lerp(PAINT_DARK, 0.4),
			Enum.Material.SmoothPlastic,
			DETAIL
		)
		bead.Shape = Enum.PartType.Ball
		bead.Reflectance = 0.15
	end
	local function stems(letters: { Model }, lineV: number, h: number, count: number, short: boolean)
		local slots = {}
		local t = h * 0.215
		for _, letter in letters do
			local cu = letter:GetAttribute("U") :: number
			local cw = h * 0.78
			table.insert(slots, cu - cw / 2 + t / 2)
			table.insert(slots, cu + cw / 2 - t / 2)
		end
		for _ = 1, count do
			if #slots == 0 then
				break
			end
			local u = table.remove(slots, rng:NextInteger(1, #slots)) + rng:NextNumber(-0.06, 0.06)
			local base = lineV - h / 2 + 0.02
			local len
			if short then
				len = rng:NextNumber(0.12, 0.3)
			elseif math.abs(u) < 2.3 then
				len = rng:NextNumber(0.2, 0.75)
			else
				len = rng:NextNumber(0.6, 2.6) ^ 1.1
			end
			run(u, base, len)
		end
	end
	stems(botLetters, botV, botH, 7, false)
	stems(topLetters, topV, topH, 4, true)

	-- the rollered-out patch of wall and the splatter round it, drawn on one big carrier; the ghost
	-- label (glitch words) lives in the same gui
	local patchW, patchH = width + 1.2, height + 1.6
	local patch = Kit.box(
		sign,
		"StencilPatch",
		Vector3.new(patchW, patchH, 0.02),
		view * CFrame.new(0, -0.15, 0.008),
		C.block,
		nil,
		INVISIBLE
	)
	local stencil = Kit.box(
		queue,
		"Stencil",
		Vector3.new(botWidth * 0.9, 0.05, 0.05),
		view * CFrame.new(0, botV - botH / 2 - 0.05, 0.3),
		C.block,
		nil,
		INVISIBLE
	)
	local pps = 40
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Adornee = patch
	gui.Face = Enum.NormalId.Back -- the patch sits in the view frame: +Z (Back) faces the room
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 1 -- lit like the wall it's painted on (and by the red glow)
	gui.Brightness = 0.15
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = stencil
	local W, H = patchW * pps, patchH * pps
	buffPatch(gui, W * 0.03, H * 0.04, W * 0.97, H * 0.96, rng)
	splatter(gui, W, H, PAINT, rng, 70, Rect.new(W * 0.08, H * 0.1, W * 0.92, H * 0.9))
	local ghost = text(gui, "Label", "PICK A DOOR", SPRAY_FONT, PAINT, 5)
	ghost.Position = UDim2.fromOffset(W * 0.02, H * 0.3)
	ghost.Size = UDim2.fromOffset(W * 0.96, H * 0.4)
	ghost.TextTransparency = 1
	ghost:SetAttribute("Ghost", true)
	ghost:SetAttribute("GhostBase", "PICK A DOOR")
	ghost.TextStrokeColor3 = PAINT_DARK
	ghost.TextStrokeTransparency = 1
	local link = Instance.new("ObjectValue")
	link.Name = "Ghost"
	link.Value = ghost
	link.Parent = sign

	-- the paint catches the light, breathing red (DoorFX drives Glow, SignFX the rest)
	local glow = Kit.pointLight(stencil, math.max(10, width), 0.25, false, Color3.fromRGB(255, 50, 40))
	glow.Name = "Glow"
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "Drip"
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.Rate = 1.2
	drip.Lifetime = NumberRange.new(0.6, 1)
	drip.Speed = NumberRange.new(0, 0.2)
	drip.Acceleration = Vector3.new(0, -14, 0)
	drip.Size = NumberSequence.new(0.07)
	drip.Squash = NumberSequence.new(-1.2)
	drip.Color = ColorSequence.new(PAINT)
	drip.LightEmission = 0.1
	drip.LightInfluence = 1
	drip.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.3) })
	drip.Parent = stencil

	-- red light bleeding up the wall from behind the top line (SignFX breathes it with the heartbeat)
	local wash =
		Kit.box(sign, "WashLight", Vector3.new(0.2, 0.2, 0.2), view * CFrame.new(0, topV, 0.9), PAINT, nil, INVISIBLE)
	Kit.pointLight(wash, 11, 0.35, false, Color3.fromRGB(255, 40, 30))
	Signage.haloAt(sign, view, 0, topV, 0.7, 9, HERO_HOT, 0.9)
	Signage.haloAt(sign, view, 0, botV, 0.7, 8, HERO_HOT, 0.9)

	Signage.tagFX(sign, view, "spray", {
		Width = width,
		Height = height,
		Depth = 0.66,
		Accent = HERO_HOT,
		Pulse = 4.6,
		PulseAmt = 0.6,
		Flicker = 16,
		Haze = "drips",
	})
	return sign
end

------------------------------------------------------------------------------------------
-- Door plaques: modern lit plaques over each door (SOLO / DUO / SQUAD)
------------------------------------------------------------------------------------------
--[[
	A bevelled enamel plaque in the mode's colour with a neon edge, the title in 3D neon letters and
	the live count in a recessed counter window. Instances (QueueService / DoorFX / SignFX):
	  pad.Sign    the face carrier: SurfaceGui with Title (the ghost: rests invisible, DoorFX glitches
	              its text and SignFX shows it in place of the 3D title), StatusStrip, Status (the count)
	  pad.Plaque  the 3D plaque (SignFX tag, style "plaque"; DoorFX writes Tension on it)
	`cf` is the plaque's centre on the wall, LookVector out into the room.
]]
function Signage.doorPlaque(pad: Instance, cf: CFrame, mode: string, capacity: number, color: Color3): Model
	local title = string.upper(mode)
	local view = CFrame.lookAt(cf.Position, cf.Position - cf.LookVector)
	local model = Kit.folder(pad, "Plaque")
	local w, h, d, stand = 4.7, 2.45, 0.28, 0.14
	local front = view * CFrame.new(0, 0, stand + d) -- z = 0 here is the model's face
	local neon = color:Lerp(Color3.new(1, 1, 1), 0.18)
	local body, face = Signage.panel(model, front, w, h, d, {
		bodyColor = Color3.fromRGB(26, 24, 26),
		faceColor = color:Lerp(Color3.fromRGB(10, 9, 10), 0.8),
		faceReflectance = 0.12,
		bevelColor = color:Lerp(Color3.fromRGB(150, 150, 156), 0.55),
		bevelReflectance = 0.25,
		bevel = 0.14,
	})
	body.Name = "PlaqueBody"
	face.Name = "PlaqueFace"
	-- stand-offs to the wall
	for _, u in { -1.7, 1.7 } do
		local post = Kit.box(
			model,
			"Standoff",
			Vector3.new(stand + 0.02, 0.16, 0.16),
			view * CFrame.new(u, 0, stand / 2) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(70, 70, 74),
			Enum.Material.Metal,
			DETAIL
		)
		post.Shape = Enum.PartType.Cylinder
	end
	-- neon edge inset round the face, and a glow strip under the model onto the door header
	Signage.edgeFrame(model, front, w - 0.42, h - 0.42, 0.055, 0.002, 0.03, neon)
	local under = Kit.box(
		model,
		"Edge",
		Vector3.new(w - 0.6, 0.05, 0.08),
		view * CFrame.new(0, -h / 2 - 0.03, stand + d * 0.5),
		neon,
		Enum.Material.Neon,
		DETAIL
	)
	under.Transparency = 0.2
	-- brushed screw heads in the corners
	for _, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
		local screw = Kit.box(
			model,
			"Screw",
			Vector3.new(0.03, 0.12, 0.12),
			front * CFrame.new(c[1] * (w / 2 - 0.12), c[2] * (h / 2 - 0.12), 0.0) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(150, 150, 156),
			Enum.Material.Metal,
			DETAIL
		)
		screw.Shape = Enum.PartType.Cylinder
	end

	-- the title in 3D: dark returns, a neon face in the mode's colour, a rim on the enamel behind
	local titleV = 0.4
	local spec: Text3DSpec = {
		height = 0.84,
		width = 0.72,
		gap = 0.17,
		stroke = 0.2,
		layers = {
			{
				name = "Glow",
				color = color,
				material = Enum.Material.Neon,
				transparency = 0.6,
				z = 0.004,
				d = 0.012,
				grow = 0.14,
			},
			{ name = "Body", color = Color3.fromRGB(34, 32, 34), material = Enum.Material.Metal, z = 0.02, d = 0.16 },
			{ name = "Face", color = neon, material = Enum.Material.Neon, z = 0.18, d = 0.025, grow = -0.035 },
		},
	}
	local maxW = w - 0.9
	local titleW = Signage.measure3D(title, spec)
	if titleW > maxW then
		spec.height *= maxW / titleW
	end
	Signage.text3D(model, front * CFrame.new(0, titleV, 0), title, spec)

	-- the counter window: a steel bezel round a recessed black strip carrying the live count
	local stripW, stripH, stripV = 3.0, 0.58, -0.56
	Signage.edgeFrame(
		model,
		front * CFrame.new(0, stripV, 0),
		stripW + 0.12,
		stripH + 0.12,
		0.06,
		0,
		0.05,
		Color3.fromRGB(120, 120, 126),
		Enum.Material.Metal,
		"Bezel"
	)
	local fw, fh = w - 0.28, h - 0.28
	local pps = 100
	local sign =
		Kit.box(pad, "Sign", Vector3.new(fw, fh, 0.02), front * CFrame.new(0, 0, 0.012), C.block, nil, INVISIBLE)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = Enum.NormalId.Back -- the part sits on view's frame: its +Z (Back) faces the room
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = 0
	gui.Brightness = 1.1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.MaxDistance = 140
	gui.Parent = sign
	local W, H = fw * pps, fh * pps
	local function px(u: number, v: number): (number, number)
		return W / 2 + u * pps, H / 2 - v * pps
	end
	local tx, ty = px(-(w - 0.9) / 2, titleV + 0.5)
	local ghost = text(gui, "Title", title, PLAQUE_FONT, neon, 4)
	ghost.Position = UDim2.fromOffset(tx, ty)
	ghost.Size = UDim2.fromOffset((w - 0.9) * pps, 1.0 * pps)
	ghost.TextTransparency = 1
	ghost:SetAttribute("Ghost", true)
	ghost:SetAttribute("GhostBase", title)
	local sx, sy = px(-stripW / 2, stripV + stripH / 2)
	local strip = frame(
		gui,
		"StatusStrip",
		UDim2.fromOffset(sx, sy),
		UDim2.fromOffset(stripW * pps, stripH * pps),
		Color3.fromRGB(8, 8, 9),
		0,
		2
	)
	round(strip, UDim.new(0, 4))
	local status = text(gui, "Status", string.format("0 / %d", capacity), COUNT_FONT, CREAM, 5)
	status.Position = UDim2.fromOffset(sx + stripW * pps * 0.05, sy + stripH * pps * 0.12)
	status.Size = UDim2.fromOffset(stripW * pps * 0.9, stripH * pps * 0.76)
	local link = Instance.new("ObjectValue")
	link.Name = "Ghost"
	link.Value = ghost
	link.Parent = model

	-- a little of the mode's colour onto the wall and header
	local lamp = Kit.box(
		model,
		"PlaqueLight",
		Vector3.new(0.2, 0.2, 0.2),
		view * CFrame.new(0, -h / 2 + 0.1, stand + d + 0.5),
		color,
		nil,
		INVISIBLE
	)
	Kit.pointLight(lamp, 7, 0.4, false, neon)

	Signage.tagFX(model, front, "plaque", {
		Width = w,
		Height = h,
		Depth = 0.24,
		Accent = neon,
		Pulse = 3.4,
		PulseAmt = 0.45,
		Sweep = 9 + (cf.Position.X % 7) * 0.3,
		SweepColor = neon:Lerp(Color3.new(1, 1, 1), 0.5),
		Flicker = 34,
	})
	return model
end

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
