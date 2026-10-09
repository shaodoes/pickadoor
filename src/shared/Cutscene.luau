--[[
	Code-authored camera cutscenes (client only): what a Moon Animator camera track would do, as data.

	Tracks
	  local track = Cutscene.track({
	      { t = 0,   pos = Vector3, look = Vector3, fov = 60 },     -- or cf = CFrame instead of pos/look
	      { t = 1.2, pos = ..., look = ..., fov = 55, roll = 0.05 },
	  }, { interp = "catmull" | "linear", ease = Cutscene.ease.sineInOut | Cutscene.bezier(.2,0,.1,1) })
	  track:sample(t) -> (CFrame, fov)        -- t in seconds from the track's first key
	  Positions/FOV follow a Catmull-Rom spline through the keys (or straight lines), rotations slerp between
	  neighbouring keys; `ease` remaps the whole track's time (a cubic-bezier like CSS, or a named curve).

	Director (one per playing cutscene)
	  local d = Cutscene.new("Name")           -- its own ScreenGui: letterbox bars + fade
	  d:run({ { start = 0, track = a }, { start = 2, track = b } }, clock)  -- hard cuts between shots;
	                                           -- clock() returns the cutscene time (lets clients sync)
	  d:shake(amplitude, duration, frequency?) -- decaying noise shake on top of the camera
	  d:letterbox(true|false, time?)           d:fade(0..1 (1 = black), time?, color?)
	  d:stopCamera()                           -- give the camera back (Custom, on the current humanoid)
	  d:destroy()
	  d.gui                                    -- ScreenGui to add title cards to (ZIndex > 10 sits above the fade)
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cutscene = {}

------------------------------------------------------------------------------------------
-- Easing
------------------------------------------------------------------------------------------
export type Ease = (number) -> number

Cutscene.ease = {
	linear = function(a: number): number
		return a
	end,
	sineInOut = function(a: number): number
		return -(math.cos(math.pi * a) - 1) / 2
	end,
	quadOut = function(a: number): number
		return 1 - (1 - a) * (1 - a)
	end,
	quadIn = function(a: number): number
		return a * a
	end,
	cubicInOut = function(a: number): number
		return if a < 0.5 then 4 * a * a * a else 1 - (-2 * a + 2) ^ 3 / 2
	end,
}

-- CSS-style cubic-bezier(x1, y1, x2, y2) easing: solve x(s) = a for s (Newton, then bisection), return y(s).
function Cutscene.bezier(x1: number, y1: number, x2: number, y2: number): Ease
	local function coord(s: number, p1: number, p2: number): number
		local u = 1 - s
		return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
	end
	local function slope(s: number, p1: number, p2: number): number
		local u = 1 - s
		return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2)
	end
	return function(a: number): number
		if a <= 0 then
			return 0
		elseif a >= 1 then
			return 1
		end
		local s = a
		for _ = 1, 6 do
			local d = slope(s, x1, x2)
			if math.abs(d) < 1e-6 then
				break
			end
			s -= (coord(s, x1, x2) - a) / d
		end
		if s < 0 or s > 1 or math.abs(coord(s, x1, x2) - a) > 1e-4 then
			local lo, hi = 0, 1
			for _ = 1, 24 do
				s = (lo + hi) / 2
				if coord(s, x1, x2) < a then
					lo = s
				else
					hi = s
				end
			end
		end
		return coord(s, y1, y2)
	end
end

------------------------------------------------------------------------------------------
-- Tracks
------------------------------------------------------------------------------------------
export type Key = {
	t: number,
	cf: CFrame?,
	pos: Vector3?,
	look: Vector3?,
	fov: number?,
	roll: number?,
}
export type TrackOpts = { interp: string?, ease: Ease? }

type Node = { t: number, pos: Vector3, rot: CFrame, fov: number }

local Track = {}
Track.__index = Track
export type Track = typeof(setmetatable({} :: { nodes: { Node }, duration: number, interp: string, ease: Ease }, Track))

local function catmull(p0, p1, p2, p3, s: number)
	local s2, s3 = s * s, s * s * s
	return (p1 * 2 + (p2 - p0) * s + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * s2 + (p1 * 3 - p0 - p2 * 3 + p3) * s3) * 0.5
end

function Cutscene.track(keys: { Key }, opts: TrackOpts?): Track
	assert(#keys >= 1, "Cutscene.track needs at least one key")
	local o = opts or {}
	local nodes: { Node } = {}
	local lastFov = 70
	for _, k in keys do
		local cf: CFrame
		if k.cf then
			cf = k.cf
		else
			local pos = k.pos or Vector3.zero
			cf = CFrame.lookAt(pos, k.look or (pos + Vector3.new(0, 0, -1)))
		end
		if k.roll then
			cf *= CFrame.Angles(0, 0, k.roll)
		end
		lastFov = k.fov or lastFov
		table.insert(nodes, { t = k.t, pos = cf.Position, rot = cf.Rotation, fov = lastFov })
	end
	table.sort(nodes, function(a, b)
		return a.t < b.t
	end)
	local t0 = nodes[1].t
	for _, n in nodes do
		n.t -= t0
	end
	return setmetatable({
		nodes = nodes,
		duration = nodes[#nodes].t,
		interp = o.interp or "catmull",
		ease = o.ease or Cutscene.ease.linear,
	}, Track)
end

function Track.sample(self: Track, t: number): (CFrame, number)
	local nodes = self.nodes
	local n = #nodes
	if n == 1 or self.duration <= 0 then
		return nodes[1].rot + nodes[1].pos, nodes[1].fov
	end
	local et = self.ease(math.clamp(t / self.duration, 0, 1)) * self.duration
	local i = 1
	while i < n - 1 and et > nodes[i + 1].t do
		i += 1
	end
	local a, b = nodes[i], nodes[i + 1]
	local span = b.t - a.t
	local s = if span > 0 then math.clamp((et - a.t) / span, 0, 1) else 1
	local pos: Vector3
	local fov: number
	if self.interp == "linear" then
		pos = a.pos:Lerp(b.pos, s)
		fov = a.fov + (b.fov - a.fov) * s
	else
		-- phantom end points mirror the neighbours so the curve starts and ends without overshoot
		local p = nodes[i - 1]
		local q = nodes[i + 2]
		local p0 = if p then p.pos else a.pos * 2 - b.pos
		local p3 = if q then q.pos else b.pos * 2 - a.pos
		pos = catmull(p0, a.pos, b.pos, p3, s)
		local f0 = if p then p.fov else a.fov * 2 - b.fov
		local f3 = if q then q.fov else b.fov * 2 - a.fov
		fov = catmull(f0, a.fov, b.fov, f3, s)
	end
	return a.rot:Lerp(b.rot, s) + pos, fov
end

------------------------------------------------------------------------------------------
-- Director
------------------------------------------------------------------------------------------
export type Shot = { start: number, track: Track }

local Director = {}
Director.__index = Director

local BAR = 0.11 -- letterbox bar height (fraction of the screen)

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local tw =
		TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), goal)
	tw:Play()
	return tw
end

function Cutscene.new(name: string)
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cutscene_" .. name
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local function bar(barName: string, top: boolean): Frame
		local f = Instance.new("Frame")
		f.Name = barName
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.Size = UDim2.new(1, 0, BAR, 2)
		f.AnchorPoint = Vector2.new(0, if top then 1 else 0)
		f.Position = UDim2.fromScale(0, if top then 0 else 1)
		f.ZIndex = 5
		f.Parent = gui
		return f
	end
	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.BorderSizePixel = 0
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.Size = UDim2.fromScale(1, 1)
	fade.ZIndex = 10
	fade.Parent = gui

	local self = setmetatable({
		name = name,
		gui = gui,
		top = bar("BarTop", true),
		bottom = bar("BarBottom", false),
		fadeFrame = fade,
		bound = false,
		bindName = "Cutscene_" .. name .. "_" .. tostring(math.random(1, 1e9)),
		shakes = {} :: { { amp: number, dur: number, freq: number, t0: number, seed: number } },
		savedType = nil :: Enum.CameraType?,
		savedFov = nil :: number?,
	}, Director)
	gui.Parent = player:WaitForChild("PlayerGui")
	return self
end

function Director.letterbox(self, show: boolean, time: number?)
	local t = time or 0.5
	tween(self.top, t, { Position = UDim2.fromScale(0, if show then BAR else 0) })
	tween(self.bottom, t, { Position = UDim2.fromScale(0, if show then 1 - BAR else 1) })
end

-- alpha 1 = fully black (or `color`), 0 = clear
function Director.fade(self, alpha: number, time: number?, color: Color3?)
	if color then
		self.fadeFrame.BackgroundColor3 = color
	end
	local t = time or 0.4
	if t <= 0 then
		self.fadeFrame.BackgroundTransparency = 1 - alpha
	else
		tween(self.fadeFrame, t, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine)
	end
end

function Director.shake(self, amplitude: number, duration: number, frequency: number?)
	table.insert(self.shakes, {
		amp = amplitude,
		dur = duration,
		freq = frequency or 18,
		t0 = os.clock(),
		seed = math.random() * 100,
	})
end

-- Sum of the live shakes as a small rotation (radians-ish amplitude) plus a tiny positional jolt.
function Director.shakeOffset(self): CFrame
	local now = os.clock()
	local rx, ry, rz, px = 0, 0, 0, 0
	for i = #self.shakes, 1, -1 do
		local s = self.shakes[i]
		local age = now - s.t0
		if age >= s.dur then
			table.remove(self.shakes, i)
			continue
		end
		local k = s.amp * (1 - age / s.dur) ^ 2
		local x = age * s.freq
		rx += math.noise(x, s.seed, 0) * k
		ry += math.noise(x, s.seed, 10) * k
		rz += math.noise(x, s.seed, 20) * k * 0.6
		px += math.noise(x, s.seed, 30) * k * 3
	end
	if rx == 0 and ry == 0 and rz == 0 then
		return CFrame.identity
	end
	return CFrame.new(0, px * 0.5, 0) * CFrame.Angles(rx, ry, rz)
end

-- Drive the camera through `shots` (sorted by start; each holds until the next one starts).
function Director.run(self, shots: { Shot }, clock: () -> number)
	local camera = workspace.CurrentCamera
	if not self.bound then
		self.savedType = camera.CameraType
		self.savedFov = camera.FieldOfView
	end
	table.sort(shots, function(a, b)
		return a.start < b.start
	end)
	if self.bound then
		RunService:UnbindFromRenderStep(self.bindName)
	end
	self.bound = true
	RunService:BindToRenderStep(self.bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		local t = clock()
		local shot = shots[1]
		for _, s in shots do
			if t >= s.start then
				shot = s
			end
		end
		if not shot then
			return
		end
		local cf, fov = shot.track:sample(t - shot.start)
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
		cam.CFrame = cf * self:shakeOffset()
		cam.FieldOfView = fov
	end)
end

function Director.stopCamera(self)
	if not self.bound then
		return
	end
	self.bound = false
	RunService:UnbindFromRenderStep(self.bindName)
	local camera = workspace.CurrentCamera
	local player = Players.LocalPlayer
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = if self.savedType == Enum.CameraType.Scriptable
		then Enum.CameraType.Custom
		else (self.savedType or Enum.CameraType.Custom)
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.FieldOfView = self.savedFov or 70
end

function Director.destroy(self)
	self:stopCamera()
	self.gui:Destroy()
end

return Cutscene
