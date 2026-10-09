--[[
	Builds the Laser Pointer Tool: a matte-black pen/torch body with a red lens, held so it points forward
	from the hand.

	Tool frame: the Handle is an invisible block whose -Z is the pen's front (Tool.Grip has no rotation, so
	the Handle's axes are the hand's grip axes: -Z away from the player, +Y up). Visible parts are
	welded to the Handle. Attachment `Lens` sits at the front; the `Beam` runs from it to an `End`
	attachment the server moves to the hit point each tick (it lives under workspace.Terrain so it
	replicates). The server toggles the Beam / the lens light and sets attribute `Firing`.

	Names other code relies on: Tool "Laser Pointer" (attribute ItemId = "laser_pointer", tag "LaserTool"),
	Handle, Handle.Lens (Attachment), Handle.Beam, Handle.LensLight (PointLight).
]]
local CollectionService = game:GetService("CollectionService")

local LaserBuilder = {}

LaserBuilder.ToolName = "Laser Pointer"
LaserBuilder.Tag = "LaserTool"
LaserBuilder.BeamColor = Color3.fromRGB(255, 40, 40)

local BODY = Color3.fromRGB(26, 26, 29)
local TRIM = Color3.fromRGB(64, 64, 68)
local GRIP = Color3.fromRGB(40, 40, 43)
local LENS = Color3.fromRGB(255, 50, 46)

local LENGTH = 1.2 -- pen length along Z
local FRONT = -LENGTH / 2 -- lens end

local function addPart(tool: Tool, handle: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, props)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = handle.CFrame * cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props or {} do
		part[key] = value
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
	part.Parent = tool
	return part
end

-- Cylinder along the pen axis (Part cylinders run along X, so roll them onto Z).
local function ring(tool: Tool, handle: BasePart, name: string, z: number, diameter: number, length: number, color)
	return addPart(
		tool,
		handle,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(90), 0),
		color,
		{ Shape = Enum.PartType.Cylinder }
	)
end

function LaserBuilder.buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = LaserBuilder.ToolName
	tool.ToolTip = "Laser Pointer"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = false
	tool:SetAttribute("ItemId", "laser_pointer")
	tool:SetAttribute("Firing", false)
	CollectionService:AddTag(tool, LaserBuilder.Tag)

	-- invisible handle: defines the grip frame and carries the lens attachment + beam
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.24, 0.24, LENGTH)
	handle.CFrame = CFrame.new()
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Parent = tool

	-- body, nose, grip bands, tail, clip, button
	ring(tool, handle, "Body", 0.02, 0.22, LENGTH - 0.26, BODY)
	ring(tool, handle, "Nose", FRONT + 0.09, 0.19, 0.18, TRIM)
	ring(tool, handle, "Bezel", FRONT + 0.015, 0.15, 0.03, GRIP)
	ring(tool, handle, "LensGlass", FRONT + 0.005, 0.11, 0.025, LENS).Material = Enum.Material.Neon
	for i = 0, 2 do
		ring(tool, handle, "GripBand", 0.12 + i * 0.13, 0.245, 0.06, GRIP)
	end
	ring(tool, handle, "Tail", LENGTH / 2 - 0.06, 0.2, 0.12, TRIM)
	addPart(tool, handle, "Clip", Vector3.new(0.05, 0.03, 0.5), CFrame.new(0.0, 0.125, 0.32), TRIM)
	addPart(tool, handle, "ClipFoot", Vector3.new(0.05, 0.05, 0.05), CFrame.new(0.0, 0.135, 0.55), TRIM)
	addPart(
		tool,
		handle,
		"Button",
		Vector3.new(0.08, 0.03, 0.12),
		CFrame.new(0, 0.12, -0.18),
		Color3.fromRGB(120, 30, 28)
	)

	-- the lens: beam origin, facing the pen's front (-Z)
	local lens = Instance.new("Attachment")
	lens.Name = "Lens"
	lens.CFrame = CFrame.new(0, 0, FRONT - 0.02)
	lens.Parent = handle

	local light = Instance.new("PointLight")
	light.Name = "LensLight"
	light.Color = LENS
	light.Brightness = 0.8
	light.Range = 4
	light.Shadows = false
	light.Enabled = false
	light.Parent = lens

	local beam = Instance.new("Beam")
	beam.Name = "Beam"
	beam.Attachment0 = lens
	beam.Color = ColorSequence.new(LaserBuilder.BeamColor)
	beam.Width0 = 0.07
	beam.Width1 = 0.04
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = 3
	beam.Transparency = NumberSequence.new(0.05)
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = handle

	-- the hand holds the pen a little behind its middle so most of it sticks out forward
	tool.Grip = CFrame.new(0, 0, 0.22)
	return tool
end

return LaserBuilder
