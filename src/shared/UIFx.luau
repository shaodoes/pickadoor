--[[
	UIFx: the motion / effects toolkit for the code-built UI (the reward-station panels first).

	Everything here is fire-and-forget and defensive: every function tolerates being called while
	its panel is hidden or after the object was destroyed (it just does nothing), and never errors.

	Looping animation goes through a Group: one RenderStepped connection per group, connected only
	while the group is active AND has callbacks. The Shell turns its group on while the panel is
	open, so nothing animates (or costs anything) while the panels are closed.

	  UIFx.Info.spring / springSoft / smooth / fast      shared TweenInfos
	  UIFx.tween(inst, info, goal): Tween                 create + play
	  UIFx.group(): Group
	    group:add(fn(t, dt)): remover                     fn runs every frame while active (t = active seconds)
	    group:setActive(on) / group:isActive()
	  UIFx.scaleOf(obj): UIScale                          obj's "FxScale" (or the UIScale it already has:
	                                                      Roblox honours only one UIScale per object)
	  UIFx.reveal(obj, {delay, offset, scale, duration})  springy entrance to the resting Position / scale 1
	  UIFx.stagger(objs, step, opts)                      reveal each, the i-th delayed (i - 1) * step (+ opts.delay)
	  UIFx.hover(obj, {scale, stroke, glow, onEnter, onLeave}): cleanup   hover lift (+ Sfx Hover once per enter)
	  UIFx.glow(parent, color, thickness, transparency): UIStroke
	  UIFx.spinGradient(target, colors, group, degPerSec, transparency): UIGradient   rotating gradient
	  UIFx.shine(obj, group, {period, width, color, alpha}): stop       light sweep every `period` s
	  UIFx.pulse(obj, group, amount, period): stop        FxScale breathing
	  UIFx.countUp(label, from, to, duration, format)     number count-up (a newer call on the label wins)
	  UIFx.fill(bar, alpha, duration)                     bar.Size.X.Scale -> alpha
	  UIFx.burst(parent, origin, {count, colors, spread, size})   sparkle burst (diamonds + streaks + ring)
	  UIFx.confetti(parent, {count, colors, duration})    confetti tumbling down across parent
	  UIFx.flyUp(parent, origin, text, {color, icon, size})        "+150 [key]" rising and fading
	  UIFx.flyTo(parent, from, to, {count, icon, color, onArrive}) icons arcing from `from` to `to`
	  UIFx.shake(obj, intensity, duration)                Position jitter, restored exactly
	  UIFx.flash(parent, color, strength, duration)       colour flash over parent
	  UIFx.stamp(obj)                                     slam-in with a soft thump
	Extras:
	  UIFx.setRest(obj, position)                         (re)define the resting Position reveal/shake return to
	  UIFx.formatInt(n): string                           1234567 -> "1,234,567" (countUp's default format)

	Notes:
	- `parent` arguments for particles / flashes may be any GuiObject or a ScreenGui; positions are UDim2s in
	  the parent's space. Particles are capped (burst <= 40, confetti <= 40, flyTo <= 12) and destroyed after.
	- reveal/shake remember an object's resting Position in the attribute "FxRestPos" the first time, so
	  repeated calls never drift. If you move such an object on purpose later, call UIFx.setRest(obj, newPos).
	  Children of a UIListLayout/UIGridLayout ignore Position: they still get the scale (and fade) part.
	- Fades need a CanvasGroup (reveal/stamp fade GroupTransparency if obj is one). Keep CanvasGroups small.
	- shine/flash/burst/confetti/flyUp/flyTo add a child frame to obj/parent: don't target an object that
	  has a UIListLayout/UIGridLayout (the layout would arrange the effect as an item); target its container.
	- Don't use hover() on a UIKit.button: it already has its own hover/press animation and sounds.
]]
local RunService = game:GetService("RunService")

local Sfx = require(script.Parent.Sfx)
local UIKit = require(script.Parent.UIKit)

local Colors = UIKit.Colors
local tween = UIKit.tween

local UIFx = {}

UIFx.Info = {
	spring = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	springSoft = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	smooth = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	fast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}
local Info = UIFx.Info

local EMPTY = table.freeze({})
local REST_ATTR = "FxRestPos"
local SHAKE_ATTR = "FxShakeRest"
local ROT_ATTR = "FxRestRot"
local TAU = math.pi * 2

local SPARK_COLORS = { Colors.goldBright, Color3.fromRGB(255, 240, 200), Colors.gold }
local CONFETTI_COLORS = {
	Colors.goldBright,
	Color3.fromRGB(196, 120, 255),
	Color3.fromRGB(120, 214, 220),
	Color3.fromRGB(236, 118, 96),
	Color3.fromRGB(246, 234, 214),
}

local function alive(obj: Instance?): boolean
	return obj ~= nil and obj.Parent ~= nil
end

function UIFx.tween(inst: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	return tween(inst, info, goal)
end

------------------------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------------------------
type Callback = (t: number, dt: number) -> ()

local Group = {}
Group.__index = Group

export type Group = typeof(setmetatable(
	{} :: {
		_fns: { Callback | false },
		_count: number,
		_active: boolean,
		_conn: RBXScriptConnection?,
		_t: number,
		_iterating: boolean,
		_dirty: boolean,
	},
	Group
))

-- squeeze out removed (false) slots in place
local function compact(self: Group)
	local fns = self._fns
	local n = #fns
	local j = 0
	for i = 1, n do
		local fn = fns[i]
		if fn then
			j += 1
			fns[j] = fn
		end
	end
	for i = j + 1, n do
		fns[i] = nil
	end
	self._dirty = false
end

local step: (self: Group, dt: number) -> ()

local function sync(self: Group)
	local want = self._active and self._count > 0
	local conn = self._conn
	if want and not conn then
		self._conn = RunService.RenderStepped:Connect(function(dt)
			step(self, dt)
		end)
	elseif not want and conn then
		conn:Disconnect()
		self._conn = nil
	end
end

step = function(self: Group, dt: number)
	self._t += dt
	local t = self._t
	local fns = self._fns
	self._iterating = true
	for i = 1, #fns do
		local fn = fns[i]
		if fn then
			local ok, err = pcall(fn, t, dt)
			if not ok and fns[i] == fn then
				fns[i] = false
				self._count -= 1
				self._dirty = true
				warn("[UIFx] a group callback errored and was removed: " .. tostring(err))
			end
		end
	end
	self._iterating = false
	if self._dirty then
		compact(self)
	end
	sync(self)
end

function UIFx.group(): Group
	return setmetatable({
		_fns = {},
		_count = 0,
		_active = false,
		_conn = nil,
		_t = 0,
		_iterating = false,
		_dirty = false,
	}, Group) :: Group
end

-- Run fn(t, dt) every frame while the group is active. Returns a remover (safe to call twice, and
-- from inside the callback itself).
function Group.add(self: Group, fn: Callback): () -> ()
	table.insert(self._fns, fn)
	self._count += 1
	sync(self)
	local removed = false
	return function()
		if removed then
			return
		end
		removed = true
		local fns = self._fns
		local i = table.find(fns, fn)
		if not i then
			return -- already dropped after an error
		end
		fns[i] = false
		self._count -= 1
		self._dirty = true
		if not self._iterating then
			compact(self)
			sync(self)
		end
	end
end

function Group.setActive(self: Group, on: boolean)
	self._active = on == true
	if not self._iterating then
		sync(self)
	end
end

function Group.isActive(self: Group): boolean
	return self._active
end

------------------------------------------------------------------------------------------
-- Basics
------------------------------------------------------------------------------------------
function UIFx.scaleOf(obj: GuiObject): UIScale
	local named = obj:FindFirstChild("FxScale")
	if named and named:IsA("UIScale") then
		return named
	end
	local existing = obj:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	pcall(function()
		scale.Parent = obj -- fails (harmlessly) if obj was destroyed
	end)
	return scale
end

function UIFx.setRest(obj: GuiObject, position: UDim2?)
	if obj then
		pcall(obj.SetAttribute, obj, REST_ATTR, position or obj.Position)
	end
end

local function restOf(obj: GuiObject): UDim2
	local p = obj:GetAttribute(REST_ATTR)
	if typeof(p) == "UDim2" then
		return p
	end
	-- mid-shake the current Position is jittered; the shake knows the real one
	local shaking = obj:GetAttribute(SHAKE_ATTR)
	local rest = if typeof(shaking) == "UDim2" then shaking else obj.Position
	obj:SetAttribute(REST_ATTR, rest)
	return rest
end

function UIFx.formatInt(n: number): string
	local v = math.floor(n + 0.5)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if v < 0 then "-" .. out else out
end

-- A transparent full-size frame to hold one effect's pieces (destroyed as a whole afterwards).
local function holderIn(parent: Instance, name: string, z: number): Frame
	return UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
	})
end

local function destroyLater(inst: Instance, delay: number)
	task.delay(delay, function()
		inst:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- Entrances
------------------------------------------------------------------------------------------
export type RevealOpts = { delay: number?, offset: Vector2?, scale: number?, duration: number? }

function UIFx.reveal(obj: GuiObject, opts: RevealOpts?)
	if not alive(obj) then
		return
	end
	local o: RevealOpts = opts or EMPTY :: any
	local delay = o.delay or 0
	local duration = o.duration or 0.5
	local offset = o.offset or Vector2.new(0, 24)
	local rest = restOf(obj)
	local scale = UIFx.scaleOf(obj)

	local info = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
	obj.Position = rest + UDim2.fromOffset(offset.X, offset.Y)
	scale.Scale = o.scale or 0.85
	tween(obj, info, { Position = rest })
	tween(scale, info, { Scale = 1 })
	if obj:IsA("CanvasGroup") then
		obj.GroupTransparency = 1
		local fade = TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay)
		tween(obj, fade, { GroupTransparency = 0 })
	end
end

function UIFx.stagger(objs: { GuiObject }, gap: number, opts: RevealOpts?)
	local o: RevealOpts = opts or EMPTY :: any
	local base = o.delay or 0
	for i, obj in objs do
		UIFx.reveal(obj, {
			delay = base + (i - 1) * gap,
			offset = o.offset,
			scale = o.scale,
			duration = o.duration,
		})
	end
end

------------------------------------------------------------------------------------------
-- Hover, glow, gradients
------------------------------------------------------------------------------------------
export type HoverOpts = {
	scale: number?,
	stroke: UIStroke?,
	glow: Instance?,
	onEnter: (() -> ())?,
	onLeave: (() -> ())?,
}

local HOVER_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- which property fades a glow in/out
local function fadeProp(inst: Instance): string
	if inst:IsA("UIStroke") then
		return "Transparency"
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return "ImageTransparency"
	elseif inst:IsA("CanvasGroup") then
		return "GroupTransparency"
	end
	return "BackgroundTransparency"
end

-- Hover lift. `glow` starts hidden and fades in to the transparency it had when hover() was called
-- (0.4 if that was fully transparent). Returns a cleanup that disconnects the hover.
function UIFx.hover(obj: GuiObject, opts: HoverOpts?): () -> ()
	if not alive(obj) then
		return function() end
	end
	local o: HoverOpts = opts or EMPTY :: any
	local scale = UIFx.scaleOf(obj)
	local up = o.scale or 1.04
	local stroke = o.stroke
	local strokeRest = stroke and stroke.Transparency or 0
	local glow = o.glow
	local glowProp = glow and fadeProp(glow) or ""
	local glowLit = 0.4
	if glow then
		local current = (glow :: any)[glowProp]
		if typeof(current) == "number" and current < 0.99 then
			glowLit = current
		end
		(glow :: any)[glowProp] = 1
	end

	local hovering = false
	local function set(on: boolean)
		tween(scale, on and HOVER_IN or Info.fast, { Scale = on and up or 1 })
		if stroke then
			tween(stroke, Info.fast, { Transparency = on and math.max(strokeRest - 0.4, 0) or strokeRest })
		end
		if glow then
			tween(glow, Info.smooth, { [glowProp] = on and glowLit or 1 })
		end
	end
	local enter = obj.MouseEnter:Connect(function()
		if hovering then
			return
		end
		hovering = true
		Sfx.play("Hover", 0.08)
		set(true)
		if o.onEnter then
			task.spawn(o.onEnter)
		end
	end)
	local leave = obj.MouseLeave:Connect(function()
		if not hovering then
			return
		end
		hovering = false
		set(false)
		if o.onLeave then
			task.spawn(o.onLeave)
		end
	end)
	return function()
		enter:Disconnect()
		leave:Disconnect()
	end
end

function UIFx.glow(parent: GuiObject, color: Color3, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = "FxGlow"
	stroke.Color = color
	stroke.Thickness = thickness or 3
	stroke.Transparency = transparency or 0.4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	pcall(function()
		stroke.Parent = parent
	end)
	return stroke
end

function UIFx.spinGradient(
	target: Instance,
	colors: ColorSequence,
	group: Group,
	degPerSec: number?,
	transparency: NumberSequence?
): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "FxSpin"
	gradient.Color = colors
	if transparency then
		gradient.Transparency = transparency
	end
	local ok = pcall(function()
		gradient.Parent = target
	end)
	if not ok or not group then
		return gradient
	end
	local speed = degPerSec or 60
	local remove: () -> ()
	remove = group:add(function(_t, dt)
		if not gradient.Parent then
			remove()
			return
		end
		gradient.Rotation = (gradient.Rotation + speed * dt) % 360
	end)
	return gradient
end

------------------------------------------------------------------------------------------
-- Loops: shine, pulse
------------------------------------------------------------------------------------------
export type ShineOpts = { period: number?, width: number?, color: Color3?, alpha: number? }

local SWEEP = 0.75 -- seconds a sweep takes

-- A full-size overlay whose UIGradient carries a narrow tilted light band; the sweep moves the
-- gradient's Offset (no new instances per sweep, and no clipping needed: the overlay is obj's shape).
function UIFx.shine(obj: GuiObject, group: Group, opts: ShineOpts?): () -> ()
	if not alive(obj) or not group then
		return function() end
	end
	local o: ShineOpts = opts or EMPTY :: any
	local period = math.max(o.period or 2.8, SWEEP + 0.1)
	local half = math.clamp((o.width or 0.18) / 2, 0.02, 0.45)
	local peak = 1 - math.clamp(o.alpha or 0.35, 0, 1)

	local overlay = UIKit.new("Frame", {
		Name = "FxShine",
		BackgroundColor3 = o.color or Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = obj,
	})
	local corner = obj:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = overlay
	end
	local gradient = UIKit.new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1.2, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5 - half, 1),
			NumberSequenceKeypoint.new(0.5, peak),
			NumberSequenceKeypoint.new(0.5 + half, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = overlay,
	})

	local stopped = false
	local elapsed = math.random() * period * 0.5 -- desync shines that start together
	local remove: () -> ()
	local function stop()
		if stopped then
			return
		end
		stopped = true
		remove()
		overlay:Destroy()
	end
	remove = group:add(function(_t, dt)
		if not overlay.Parent then
			stop()
			return
		end
		elapsed = (elapsed + dt) % period
		local sweeping = elapsed < SWEEP
		if overlay.Visible ~= sweeping then
			overlay.Visible = sweeping
		end
		if sweeping then
			local u = elapsed / SWEEP
			u = u * u * (3 - 2 * u)
			gradient.Offset = Vector2.new(-1.2 + 2.4 * u, 0)
		end
	end)
	return stop
end

function UIFx.pulse(obj: GuiObject, group: Group, amount: number?, period: number?): () -> ()
	if not alive(obj) or not group then
		return function() end
	end
	local scale = UIFx.scaleOf(obj)
	local a = amount or 0.04
	local w = TAU / (period or 1.4)
	local stopped = false
	local remove: () -> ()
	local function stop()
		if stopped then
			return
		end
		stopped = true
		remove()
		scale.Scale = 1
	end
	remove = group:add(function(t)
		if not scale.Parent then
			stop()
			return
		end
		scale.Scale = 1 + a * (0.5 - 0.5 * math.cos(t * w))
	end)
	return stop
end

------------------------------------------------------------------------------------------
-- Numbers and bars
------------------------------------------------------------------------------------------
local counting: { [TextLabel]: number } = {}

function UIFx.countUp(label: TextLabel, from: number, to: number, duration: number?, format: ((n: number) -> string)?)
	if not label then
		return
	end
	local fmt = format or UIFx.formatInt
	local token = (counting[label] or 0) + 1
	counting[label] = token
	local dur = duration or 0.7
	if not alive(label) or dur <= 0 or from == to then
		counting[label] = nil
		pcall(function()
			label.Text = fmt(to)
		end)
		return
	end
	label.Text = fmt(from)
	local elapsed = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if counting[label] ~= token or not label.Parent then
			conn:Disconnect()
			if counting[label] == token then
				counting[label] = nil
			end
			return
		end
		elapsed += dt
		local a = math.min(elapsed / dur, 1)
		local e = 1 - (1 - a) ^ 3
		local text = fmt(from + (to - from) * e)
		if label.Text ~= text then
			label.Text = text
		end
		if a >= 1 then
			conn:Disconnect()
			counting[label] = nil
		end
	end)
end

function UIFx.fill(bar: Frame, alpha: number, duration: number?)
	if not alive(bar) then
		return
	end
	local a = math.clamp(alpha, 0, 1)
	local size = bar.Size
	-- springy, but a nearly full bar eases in without overshooting its track
	local style = if a < 0.95 then Enum.EasingStyle.Back else Enum.EasingStyle.Quint
	tween(
		bar,
		TweenInfo.new(duration or 0.6, style, Enum.EasingDirection.Out),
		{ Size = UDim2.new(a, size.X.Offset, size.Y.Scale, size.Y.Offset) }
	)
end

------------------------------------------------------------------------------------------
-- Particles
------------------------------------------------------------------------------------------
export type BurstOpts = { count: number?, colors: { Color3 }?, spread: number?, size: number? }

function UIFx.burst(parent: GuiBase2d, origin: UDim2, opts: BurstOpts?)
	if not alive(parent) then
		return
	end
	local o: BurstOpts = opts or EMPTY :: any
	local count = math.clamp(math.floor(o.count or 14), 1, 40)
	local colors = if o.colors and #o.colors > 0 then o.colors else SPARK_COLORS
	local spread = o.spread or 90
	local size = o.size or 10
	local holder = holderIn(parent, "FxBurst", 50)

	-- a quick expanding ring at the origin
	local ring = UIKit.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = origin,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	}, {
		UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	local ringStroke = UIKit.new("UIStroke", { Color = colors[1], Thickness = 3, Transparency = 0.1, Parent = ring })
	local ringInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tween(ring, ringInfo, { Size = UDim2.fromOffset(spread * 1.3, spread * 1.3) })
	tween(ringStroke, ringInfo, { Transparency = 1, Thickness = 1 })

	local longest = 0.5
	for i = 1, count do
		local angle = (i / count) * TAU + (math.random() - 0.5) * 0.6
		local dist = spread * (0.55 + math.random() * 0.6)
		local cx, cy = math.cos(angle), math.sin(angle)
		local life = 0.55 + math.random() * 0.4
		longest = math.max(longest, life)
		local color = colors[math.random(#colors)]
		local move = TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local fade = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if i % 3 == 0 then
			-- streak: a thin line flying along its own direction, stretching as it goes
			local streak = UIKit.new("Frame", {
				Name = "Streak",
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = origin + UDim2.fromOffset(cx * 8, cy * 8),
				Size = UDim2.fromOffset(size * 0.8, 3),
				Rotation = math.deg(angle),
				Parent = holder,
			}, { UIKit.new("UICorner", { CornerRadius = UDim.new(0, 2) }) })
			tween(streak, move, {
				Position = origin + UDim2.fromOffset(cx * dist * 1.25, cy * dist * 1.25),
				Size = UDim2.fromOffset(size * 2.6, 2),
			})
			tween(streak, fade, { BackgroundTransparency = 1 })
		else
			-- diamond: a rotated square that spins and shrinks as it fades
			local s = size * (0.6 + math.random() * 0.7)
			local diamond = UIKit.new("Frame", {
				Name = "Diamond",
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = origin,
				Size = UDim2.fromOffset(s, s),
				Rotation = 45,
				Parent = holder,
			}, { UIKit.new("UICorner", { CornerRadius = UDim.new(0, 2) }) })
			tween(diamond, move, {
				Position = origin + UDim2.fromOffset(cx * dist, cy * dist),
				Rotation = 45 + (math.random() - 0.5) * 240,
			})
			tween(diamond, fade, { BackgroundTransparency = 1, Size = UDim2.fromOffset(s * 0.3, s * 0.3) })
		end
	end
	destroyLater(holder, longest + 0.1)
end

export type ConfettiOpts = { count: number?, colors: { Color3 }?, duration: number? }

function UIFx.confetti(parent: GuiBase2d, opts: ConfettiOpts?)
	if not alive(parent) then
		return
	end
	local o: ConfettiOpts = opts or EMPTY :: any
	local count = math.clamp(math.floor(o.count or 36), 1, 40)
	local colors = if o.colors and #o.colors > 0 then o.colors else CONFETTI_COLORS
	local duration = math.max(o.duration or 2.4, 0.5)
	local holder = holderIn(parent, "FxConfetti", 48)
	holder.ClipsDescendants = true

	-- parallel arrays: built once, updated in place every frame
	local frames: { Frame } = table.create(count)
	local px, py, vx, vy =
		table.create(count, 0), table.create(count, 0), table.create(count, 0), table.create(count, 0)
	local rot, vrot, phase, vphase =
		table.create(count, 0), table.create(count, 0), table.create(count, 0), table.create(count, 0)
	local w, h = table.create(count, 0), table.create(count, 0)
	for i = 1, count do
		px[i] = math.random()
		py[i] = -0.04 - math.random() * 0.35 -- staggered: they fall in over the first moments
		vx[i] = (math.random() - 0.5) * 0.24
		vy[i] = 0.05 + math.random() * 0.25
		rot[i] = math.random() * 360
		vrot[i] = (math.random() - 0.5) * 540
		phase[i] = math.random() * TAU
		vphase[i] = 6 + math.random() * 8
		w[i] = 7 + math.random() * 5
		h[i] = 11 + math.random() * 6
		frames[i] = UIKit.new("Frame", {
			Name = "Bit",
			BackgroundColor3 = colors[math.random(#colors)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(px[i], py[i]),
			Size = UDim2.fromOffset(w[i], h[i]),
			Rotation = rot[i],
			Parent = holder,
		})
	end

	local GRAVITY, TERMINAL = 0.9, 0.55
	local fadeFrom = duration * 0.72
	local elapsed = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration or not holder.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local fading = elapsed > fadeFrom
		local alpha = fading and (elapsed - fadeFrom) / (duration - fadeFrom) or 0
		for i = 1, count do
			vy[i] = math.min(vy[i] + GRAVITY * dt, TERMINAL)
			px[i] += (vx[i] + math.sin(phase[i] * 0.35) * 0.04) * dt
			py[i] += vy[i] * dt
			rot[i] += vrot[i] * dt
			phase[i] += vphase[i] * dt
			local f = frames[i]
			f.Position = UDim2.fromScale(px[i], py[i])
			f.Rotation = rot[i]
			f.Size = UDim2.fromOffset(w[i] * (0.2 + 0.8 * math.abs(math.cos(phase[i]))), h[i])
			if fading then
				f.BackgroundTransparency = alpha
			end
		end
	end)
end

export type FlyUpOpts = { color: Color3?, icon: string?, size: number? }

-- Pass icon = "none" for text only (the default icon is the key).
function UIFx.flyUp(parent: GuiBase2d, origin: UDim2, text: string, opts: FlyUpOpts?)
	if not alive(parent) then
		return
	end
	local o: FlyUpOpts = opts or EMPTY :: any
	local color = o.color or Colors.goldBright
	local size = o.size or 34
	local iconName = o.icon or "key"

	local group = UIKit.new("CanvasGroup", {
		Name = "FxFlyUp",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = origin,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		ZIndex = 55,
		Parent = parent,
	}, {
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UIKit.padding(6),
	})
	local label = UIKit.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Text = text,
		FontFace = UIKit.Face.bold,
		TextSize = size,
		TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 4),
		LayoutOrder = 1,
		Parent = group,
	})
	UIKit.new("UIStroke", {
		Color = Colors.shadow,
		Thickness = 2,
		Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
	if iconName ~= "none" then
		local icon = UIKit.icon(iconName, color, math.floor(size * 0.8))
		icon.LayoutOrder = 2
		icon.Parent = group
	end

	local scale = UIKit.new("UIScale", { Name = "FxScale", Scale = 0.4, Parent = group })
	tween(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	tween(
		group,
		TweenInfo.new(1.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = origin + UDim2.fromOffset(0, -70) }
	)
	tween(
		group,
		TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.65),
		{ GroupTransparency = 1 }
	)
	destroyLater(group, 1.3)
end

export type FlyToOpts = { count: number?, icon: string?, color: Color3?, onArrive: (() -> ())? }

-- Icons arc from `from`'s centre to `to`'s centre. Positions are computed in absolute pixels and
-- placed with scale coordinates of `parent` ((abs - parent.AbsolutePosition) / parent.AbsoluteSize),
-- which is UIScale-proof. onArrive fires once when the first icon lands (or at once if nothing can fly).
function UIFx.flyTo(parent: GuiBase2d, from: GuiBase2d, to: GuiBase2d, opts: FlyToOpts?)
	local o: FlyToOpts = opts or EMPTY :: any
	local arrived = false
	local function arrive()
		if arrived then
			return
		end
		arrived = true
		if o.onArrive then
			task.spawn(o.onArrive)
		end
	end
	if not (alive(parent) and alive(from) and alive(to)) then
		arrive()
		return
	end
	local origin = parent.AbsolutePosition
	local pw, ph = parent.AbsoluteSize.X, parent.AbsoluteSize.Y
	if pw < 1 or ph < 1 then
		arrive()
		return
	end
	local a = from.AbsolutePosition + from.AbsoluteSize / 2 - origin
	local b = to.AbsolutePosition + to.AbsoluteSize / 2 - origin
	local count = math.clamp(math.floor(o.count or 6), 1, 12)
	local color = o.color or Colors.goldBright
	local iconName = o.icon or "key"
	local holder = holderIn(parent, "FxFlyTo", 60)

	local dx, dy = b.X - a.X, b.Y - a.Y
	local len = math.max(math.sqrt(dx * dx + dy * dy), 1)
	local nx, ny = -dy / len, dx / len -- perpendicular, for the arc's bulge

	local icons: { Frame } = table.create(count)
	local sx, sy, cx, cy =
		table.create(count, 0), table.create(count, 0), table.create(count, 0), table.create(count, 0)
	local delays, durs = table.create(count, 0), table.create(count, 0)
	local done = table.create(count, false)
	for i = 1, count do
		-- each starts scattered a little around `from`, bulges to one side, then homes in on `to`
		sx[i] = a.X + (math.random() - 0.5) * 50
		sy[i] = a.Y + (math.random() - 0.5) * 30
		local bulge = (math.random() * 0.5 + 0.2) * len * (if i % 2 == 0 then 1 else -1)
		cx[i] = (sx[i] + b.X) / 2 + nx * bulge
		cy[i] = (sy[i] + b.Y) / 2 + ny * bulge - len * 0.15
		delays[i] = (i - 1) * 0.06
		durs[i] = 0.55 + math.random() * 0.2
		local icon = UIKit.icon(iconName, color, 26)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(sx[i] / pw, sy[i] / ph)
		icon.Visible = false
		icon.Parent = holder
		icons[i] = icon
	end

	local remaining = count
	local elapsed = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			arrive()
			return
		end
		elapsed += dt
		for i = 1, count do
			if not done[i] then
				local u = (elapsed - delays[i]) / durs[i]
				if u >= 1 then
					done[i] = true
					remaining -= 1
					icons[i]:Destroy()
					arrive()
				elseif u >= 0 then
					local e = u * u * (3 - 2 * u)
					local k = 1 - e
					local x = k * k * sx[i] + 2 * k * e * cx[i] + e * e * b.X
					local y = k * k * sy[i] + 2 * k * e * cy[i] + e * e * b.Y
					local icon = icons[i]
					icon.Visible = true
					icon.Position = UDim2.fromScale(x / pw, y / ph)
					icon.Rotation = math.sin(u * math.pi) * 25
				end
			end
		end
		if remaining <= 0 then
			conn:Disconnect()
			holder:Destroy()
		end
	end)
end

------------------------------------------------------------------------------------------
-- Impacts: shake, flash, stamp
------------------------------------------------------------------------------------------
local shakeTokens: { [GuiObject]: number } = {}

function UIFx.shake(obj: GuiObject, intensity: number?, duration: number?)
	if not alive(obj) then
		return
	end
	local amp = intensity or 6
	local dur = math.max(duration or 0.35, 0.05)
	-- the true resting Position: an in-progress shake's, else the reveal rest, else the current one
	local saved = obj:GetAttribute(SHAKE_ATTR)
	local stored = obj:GetAttribute(REST_ATTR)
	local rest: UDim2 = if typeof(saved) == "UDim2"
		then saved
		elseif typeof(stored) == "UDim2" then stored
		else obj.Position
	obj:SetAttribute(SHAKE_ATTR, rest)
	local token = (shakeTokens[obj] or 0) + 1
	shakeTokens[obj] = token
	local seed = math.random() * 100
	local elapsed = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		if shakeTokens[obj] ~= token then
			conn:Disconnect() -- a newer shake took over (it restores the same rest)
			return
		end
		elapsed += dt
		if elapsed >= dur or not obj.Parent then
			conn:Disconnect()
			shakeTokens[obj] = nil
			pcall(function()
				obj.Position = rest
				obj:SetAttribute(SHAKE_ATTR, nil)
			end)
			return
		end
		local k = (1 - elapsed / dur) ^ 2 * amp
		local t = seed + elapsed
		obj.Position = rest
			+ UDim2.fromOffset(
				math.round((math.sin(t * 53) + math.sin(t * 31) * 0.5) * 0.67 * k),
				math.round((math.cos(t * 47) + math.sin(t * 23) * 0.5) * 0.67 * k)
			)
	end)
end

function UIFx.flash(parent: GuiBase2d, color: Color3?, strength: number?, duration: number?)
	if not alive(parent) then
		return
	end
	local cover = UIKit.new("Frame", {
		Name = "FxFlash",
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 1 - math.clamp(strength or 0.45, 0, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 45,
		Parent = parent,
	})
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = cover
	end
	local dur = duration or 0.4
	tween(cover, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	destroyLater(cover, dur + 0.05)
end

local SLAM = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SETTLE = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Slam-in: starts big, tilted (and transparent, if obj is a CanvasGroup), hits, settles with a thump.
function UIFx.stamp(obj: GuiObject)
	if not alive(obj) then
		return
	end
	local scale = UIFx.scaleOf(obj)
	local restRot = obj:GetAttribute(ROT_ATTR)
	if typeof(restRot) ~= "number" then
		restRot = obj.Rotation
		obj:SetAttribute(ROT_ATTR, restRot)
	end
	obj.Visible = true
	scale.Scale = 2.1
	obj.Rotation = restRot - 14
	if obj:IsA("CanvasGroup") then
		obj.GroupTransparency = 1
		tween(obj, SLAM, { GroupTransparency = 0 })
	end
	tween(obj, SLAM, { Rotation = restRot })
	local slam = tween(scale, SLAM, { Scale = 0.92 })
	slam.Completed:Once(function(state)
		if state ~= Enum.PlaybackState.Completed or not obj.Parent then
			return
		end
		Sfx.play("PickTick", 0.05)
		tween(scale, SETTLE, { Scale = 1 })
	end)
end

return UIFx
