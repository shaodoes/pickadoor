-- Builds lantern models from a catalog entry. Used for the held Tool, lobby displays and UI previews.
-- The lantern stands on its base at the model origin and is about 2.4 studs tall.
local Lanterns = require(script.Parent.Lanterns)

local LanternBuilder = {}

local function addPart(model, handle, name, size, offset, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = handle.CFrame * offset
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in extra or {} do
		part[key] = value
	end
	part.Parent = model
	if handle ~= part then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

-- Returns a Model whose PrimaryPart is "Handle" (the base plate).
function LanternBuilder.buildModel(id: string?, anchored: boolean?): Model
	local def = Lanterns.getOrDefault(id)
	local model = Instance.new("Model")
	model.Name = def.name

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.1, 0.2, 1.1)
	handle.CFrame = CFrame.new(0, 0.1, 0)
	handle.Color = def.bodyColor
	handle.Material = def.bodyMaterial
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Anchored = anchored == true
	handle.Parent = model
	model.PrimaryPart = handle

	local body, mat = def.bodyColor, def.bodyMaterial
	addPart(
		model,
		handle,
		"Glass",
		Vector3.new(0.8, 1.25, 0.8),
		CFrame.new(0, 0.73, 0),
		def.glassColor,
		Enum.Material.Glass,
		{
			Transparency = 0.45,
		}
	)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		addPart(
			model,
			handle,
			"Post",
			Vector3.new(0.12, 1.3, 0.12),
			CFrame.new(corner.X * 0.45, 0.75, corner.Z * 0.45),
			body,
			mat
		)
	end
	addPart(model, handle, "Cap", Vector3.new(1.1, 0.2, 1.1), CFrame.new(0, 1.5, 0), body, mat)
	addPart(model, handle, "Roof", Vector3.new(0.7, 0.25, 0.7), CFrame.new(0, 1.72, 0), body, mat)
	addPart(model, handle, "RingStem", Vector3.new(0.12, 0.45, 0.12), CFrame.new(0, 2.05, 0), body, mat)
	addPart(model, handle, "RingTop", Vector3.new(0.12, 0.12, 0.6), CFrame.new(0, 2.3, 0), body, mat)
	addPart(model, handle, "RingLeft", Vector3.new(0.12, 0.3, 0.12), CFrame.new(0, 2.2, -0.3), body, mat)
	addPart(model, handle, "RingRight", Vector3.new(0.12, 0.3, 0.12), CFrame.new(0, 2.2, 0.3), body, mat)

	local flame = addPart(
		model,
		handle,
		"Flame",
		Vector3.new(0.3, 0.45, 0.3),
		CFrame.new(0, 0.6, 0),
		def.lightColor,
		Enum.Material.Neon,
		{
			Shape = Enum.PartType.Ball,
		}
	)
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = def.lightColor
	light.Brightness = def.brightness
	light.Range = def.range
	light.Shadows = true
	light.Parent = flame

	model:SetAttribute("LanternId", def.id)
	return model
end

-- Returns a Tool the character holds by the ring, lantern hanging upright.
function LanternBuilder.buildTool(id: string?): Tool
	local model = LanternBuilder.buildModel(id, false)
	local tool = Instance.new("Tool")
	tool.Name = "Lantern"
	tool.ToolTip = model.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- Hand sits at the ring; rotate so the lantern's +Y points up instead of forward.
	tool.Grip = CFrame.new(0, 2.25, 0) * CFrame.Angles(math.rad(90), 0, 0)
	tool:SetAttribute("LanternId", model:GetAttribute("LanternId"))
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	return tool
end

return LanternBuilder
