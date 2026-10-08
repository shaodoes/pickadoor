-- Builds lantern models from a catalog entry. Used for the held Tool, lobby displays and UI previews.
-- Shape follows the reference art: square body with crossbarred glass panes, a flared stepped roof,
-- a neck and knob, and a large ten-sided ring handle.
-- The lantern stands on its base at the model origin; ring centre is at RING_Y.
local Lanterns = require(script.Parent.Lanterns)

local LanternBuilder = {}

local K = 0.8 -- overall scale; all dimensions below are pre-scale
local RING_Y = 3.0 * K
LanternBuilder.Height = 3.45 * K

local function v(x, y, z)
	return Vector3.new(x * K, y * K, z * K)
end

local function addPart(model, handle, name, size, cf, color, material, extra)
	local part = handle
	if not part then
		part = Instance.new("Part")
	end
	part.Name = name
	part.Size = size
	part.CFrame = cf
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
	if model.PrimaryPart and model.PrimaryPart ~= part then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = model.PrimaryPart
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

local function at(x, y, z)
	return CFrame.new(x * K, y * K, z * K)
end

-- Returns a Model whose PrimaryPart is "Handle" (the base).
function LanternBuilder.buildModel(id: string?, anchored: boolean?): Model
	local def = Lanterns.getOrDefault(id)
	local body, mat = def.bodyColor, def.bodyMaterial
	local trim = def.trimColor or body:Lerp(Color3.new(1, 1, 1), 0.18)
	local model = Instance.new("Model")
	model.Name = def.name

	local handle = Instance.new("Part")
	handle.Parent = model
	model.PrimaryPart = handle
	addPart(model, handle, "Handle", v(1.2, 0.22, 1.2), at(0, 0.11, 0), body, mat, { Anchored = anchored == true })
	addPart(model, nil, "BaseBand", v(1.28, 0.08, 1.28), at(0, 0.26, 0), trim, mat)

	-- glass body: four corner posts, a pane box, and a cross of mullions on each face
	addPart(model, nil, "Glass", v(0.9, 1.2, 0.9), at(0, 0.9, 0), def.glassColor, Enum.Material.Glass, {
		Transparency = 0.5,
	})
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		addPart(model, nil, "Post", v(0.14, 1.26, 0.14), at(c[1] * 0.5, 0.9, c[2] * 0.5), body, mat)
	end
	for _, s in { -1, 1 } do
		addPart(model, nil, "MullionV", v(0.07, 1.2, 0.07), at(0, 0.9, s * 0.47), trim, mat)
		addPart(model, nil, "MullionH", v(0.9, 0.07, 0.07), at(0, 0.98, s * 0.47), trim, mat)
		addPart(model, nil, "MullionV", v(0.07, 1.2, 0.07), at(s * 0.47, 0.9, 0), trim, mat)
		addPart(model, nil, "MullionH", v(0.07, 0.07, 0.9), at(s * 0.47, 0.98, 0), trim, mat)
	end
	addPart(model, nil, "TopRail", v(1.2, 0.12, 1.2), at(0, 1.56, 0), body, mat)

	-- flared, stepped roof
	addPart(model, nil, "Eave", v(1.5, 0.1, 1.5), at(0, 1.67, 0), trim, mat)
	for i, w in { 1.22, 0.92, 0.62, 0.36 } do
		addPart(model, nil, "Roof", v(w, 0.14, w), at(0, 1.66 + i * 0.14, 0), body, mat)
	end
	addPart(model, nil, "Neck", v(0.14, 0.25, 0.14), at(0, 2.37, 0), body, mat)
	addPart(model, nil, "Knob", v(0.26, 0.26, 0.26), at(0, 2.55, 0), trim, mat, { Shape = Enum.PartType.Ball })

	-- ten-sided ring handle in the X-Y plane
	local radius, sides = 0.42, 10
	local chord = 2 * radius * math.sin(math.pi / sides)
	for i = 0, sides - 1 do
		local a = (i + 0.5) * 2 * math.pi / sides
		local cf = at(math.cos(a) * radius, 3.0 + math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		addPart(model, nil, "Ring", v(chord + 0.05, 0.09, 0.09), cf, trim, mat)
	end

	-- candle and flame
	addPart(
		model,
		nil,
		"Candle",
		v(0.22, 0.36, 0.22),
		at(0, 0.48, 0),
		Color3.fromRGB(235, 225, 200),
		Enum.Material.SmoothPlastic
	)
	local flame = addPart(model, nil, "Flame", v(0.2, 0.32, 0.2), at(0, 0.8, 0), def.lightColor, Enum.Material.Neon, {
		Shape = Enum.PartType.Ball,
	})
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
	-- Grip point is the ring, measured from the Handle's centre; no rotation, so it hangs upright below the hand.
	tool.Grip = CFrame.new(0, RING_Y - 0.11 * K, 0)
	tool:SetAttribute("LanternId", model:GetAttribute("LanternId"))
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	return tool
end

return LanternBuilder
