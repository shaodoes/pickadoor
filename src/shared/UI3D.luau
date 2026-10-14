--[[
	UI3D: small 3D objects for the 2D UI, rendered in ViewportFrames and turning slowly.

	  UI3D.keyModel(color?): Model             a key built from parts (bow ring, collar, shaft, teeth and a
	                                           little accent gem), centred on its pivot, lying in the XY plane
	  UI3D.spinner(parent, model, opts): Spinner   a ViewportFrame showing `model`, framed to fit and turning
	    spinner:kick(power?)                   a burst of extra spin that decays (a reward landing)
	    spinner:setSpeed(radPerSec)
	    spinner:destroy()
	  UI3D.key(parent, size, opts?): Spinner   shorthand: a spinning gold key `size` px square

	All spinners share ONE RenderStepped connection, connected only while at least one spinner exists
	(and it drops spinners whose viewport was destroyed). A spinner that isn't on screen (it, or any
	ancestor up to its ScreenGui, is hidden / disabled: e.g. inside a closed panel) is skipped, so idle
	ones cost a short ancestor walk and nothing else. Viewports don't render particles or lights, so the
	"shine" is the ViewportFrame's own Ambient + LightColor and the parts' colours.
	(Standalone on purpose: UIFx uses it for the reward key floaters, so it can't require UIFx.)
]]
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent.UIKit)

local Colors = UIKit.Colors

local UI3D = {}

------------------------------------------------------------------------------------------
-- Models
------------------------------------------------------------------------------------------
local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = model
	return p
end

-- An old-fashioned door key, ~1.3 studs long, bow on the left (-X), teeth hanging down on the right.
function UI3D.keyModel(color: Color3?): Model
	local gold = color or Colors.key
	local dark = gold:Lerp(Color3.new(), 0.28)
	local model = Instance.new("Model")
	model.Name = "Key"

	-- bow: a ring of short blocks in the XY plane
	local BOW_X, R, N = -0.5, 0.25, 14
	local seg = 2 * math.pi * R / N * 1.2
	for i = 1, N do
		local a = (i - 1) / N * 2 * math.pi
		part(
			model,
			"Bow" .. i,
			Vector3.new(0.09, seg, 0.1),
			CFrame.new(BOW_X + R * math.cos(a), R * math.sin(a), 0) * CFrame.Angles(0, 0, a),
			if i % 2 == 0 then gold else gold:Lerp(Color3.new(1, 1, 1), 0.08)
		)
	end
	-- a small cold gem set in the bow
	local gem =
		part(model, "Gem", Vector3.new(0.13, 0.13, 0.13), CFrame.new(BOW_X, 0, 0), Colors.accent, Enum.PartType.Ball)
	gem.Material = Enum.Material.Neon
	-- collar, shaft and tip
	part(model, "Collar", Vector3.new(0.07, 0.17, 0.17), CFrame.new(-0.2, 0, 0), dark, Enum.PartType.Cylinder)
	part(model, "Shaft", Vector3.new(0.72, 0.09, 0.09), CFrame.new(0.17, 0, 0), gold, Enum.PartType.Cylinder)
	-- teeth
	part(model, "ToothA", Vector3.new(0.08, 0.17, 0.07), CFrame.new(0.32, -0.11, 0), gold)
	part(model, "ToothB", Vector3.new(0.07, 0.12, 0.07), CFrame.new(0.46, -0.085, 0), dark)
	part(model, "ToothC", Vector3.new(0.05, 0.08, 0.07), CFrame.new(0.4, -0.13, 0), gold)

	local center = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(center.Position)
	return model
end

------------------------------------------------------------------------------------------
-- Spinners
------------------------------------------------------------------------------------------
export type SpinnerOpts = {
	size: number?, -- px square (default 32)
	position: UDim2?,
	anchor: Vector2?,
	zIndex: number?,
	speed: number?, -- radians per second around the vertical axis (default 1.6)
	tilt: number?, -- radians the model leans toward the camera (default 0.25)
	wobble: number?, -- radians of slow side-to-side rock (default 0.12)
	fov: number?, -- camera field of view (default 30)
	ambient: Color3?,
	light: Color3?,
	name: string?,
}

type SpinnerData = {
	viewport: ViewportFrame,
	model: Model,
	speed: number,
	boost: number,
	angle: number,
	tilt: number,
	wobble: number,
	phase: number,
}

local Spinner = {}
Spinner.__index = Spinner
export type Spinner = typeof(setmetatable({} :: SpinnerData, Spinner))

local spinners: { Spinner } = {}

-- Visible all the way up (to the first LayerCollector, which must be enabled)?
local function onScreen(obj: Instance): boolean
	local node: Instance? = obj
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end
local conn: RBXScriptConnection? = nil
local clock = 0

local function step(dt: number)
	clock += dt
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		local viewport = s.viewport
		if not viewport.Parent then
			table.remove(spinners, i)
			s.model:Destroy()
		elseif onScreen(viewport) then
			-- a kick decays smoothly back to the resting speed
			s.boost *= math.exp(-dt * 2.6)
			s.angle = (s.angle + (s.speed + s.boost) * dt) % (2 * math.pi)
			local rock = math.sin(clock * 1.3 + s.phase) * s.wobble
			s.model:PivotTo(CFrame.Angles(s.tilt, 0, 0) * CFrame.Angles(0, s.angle, rock))
		end
	end
	if #spinners == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function track(s: Spinner)
	table.insert(spinners, s)
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

-- Frame `model` (pivoted at its centre) in a square viewport: the camera backs off until the model's
-- bounding sphere fits the view, so it never clips while turning.
function UI3D.spinner(parent: Instance, model: Model, opts: SpinnerOpts?): Spinner
	local o: SpinnerOpts = opts or {}
	local size = o.size or 32
	local fov = o.fov or 30
	local viewport = UIKit.new("ViewportFrame", {
		Name = o.name or "Spinner3D",
		BackgroundTransparency = 1,
		AnchorPoint = o.anchor or Vector2.zero,
		Position = o.position or UDim2.new(),
		Size = UDim2.fromOffset(size, size),
		ZIndex = o.zIndex or 1,
		Ambient = o.ambient or Color3.fromRGB(150, 140, 128),
		LightColor = o.light or Color3.fromRGB(255, 244, 222),
		LightDirection = Vector3.new(-0.6, -1, -0.8),
	})
	model:PivotTo(CFrame.new())
	local _, extents = model:GetBoundingBox()
	local radius = extents.Magnitude / 2
	local distance = radius / math.sin(math.rad(fov / 2)) * 1.02
	local camera = UIKit.new("Camera", {
		FieldOfView = fov,
		CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero),
		Parent = viewport,
	})
	viewport.CurrentCamera = camera
	model.Parent = viewport
	viewport.Parent = parent

	local self = setmetatable(
		{
			viewport = viewport,
			model = model,
			speed = o.speed or 1.6,
			boost = 0,
			angle = math.random() * 2 * math.pi,
			tilt = o.tilt or 0.25,
			wobble = o.wobble or 0.12,
			phase = math.random() * 6,
		} :: SpinnerData,
		Spinner
	)
	track(self)
	return self
end

function Spinner.kick(self: Spinner, power: number?)
	self.boost += power or 14
end

function Spinner.setSpeed(self: Spinner, radPerSec: number)
	self.speed = radPerSec
end

function Spinner.destroy(self: Spinner)
	self.viewport:Destroy() -- the step loop drops it (and its model) next frame
end

function UI3D.key(parent: Instance, size: number, opts: SpinnerOpts?): Spinner
	local o: SpinnerOpts = table.clone(opts or {}) :: any
	o.size = size
	o.name = o.name or "Key3D"
	return UI3D.spinner(parent, UI3D.keyModel(), o)
end

return UI3D
