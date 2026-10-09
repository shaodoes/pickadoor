--[[
	Builds lantern models from a catalog entry. Used for the held Tool, lobby displays and UI previews.
	Shape follows the reference art: square body with crossbarred glass panes, a flared stepped roof,
	a vented cap, a short chain and a large ten-sided ring handle. One pane is a little door (hinge
	knuckles + latch), the posts are riveted, the glass is tinted and sooted at the top.

	The lantern stands on its base at the model origin; the ring centre is at RING_Y.
	Flame: a layered Neon flame (outer teardrop "Flame" + brighter "FlameCore", both SpecialMesh
	spheres so clients can animate Scale/Offset), a particle tongue, a few slow embers and, for the
	dark lanterns, a faint smoke wisp from the chimney. "Flame" carries the "Halo" BillboardGui and
	the "Light" PointLight; other scripts read those by name.

	Budget: <= 60 parts per lantern (there are a dozen in the lobby plus the one in hand).
	Public: LanternBuilder.Height, .RingHeight, .buildModel(id, anchored), .buildTool(id),
	        .flameParts(modelOrTool) -> FlameParts?
]]
local Lanterns = require(script.Parent.Lanterns)

local LanternBuilder = {}

local K = 0.8 -- overall scale; all dimensions below are pre-scale
local RING_Y = 3.2 * K
LanternBuilder.Height = 3.67 * K
LanternBuilder.RingHeight = RING_Y -- height of the ring centre above the base, for hanging it from things

local TEX = {
	glow = "rbxasset://textures/particles/explosion01_core_main.dds", -- broad round glow (the tongue)
	dot = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- small soft dot (embers)
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

export type FlameParts = {
	outer: BasePart, -- "Flame": the Neon teardrop (Halo + Light live inside it)
	inner: BasePart?, -- "FlameCore": the bright core
	outerMesh: SpecialMesh?,
	innerMesh: SpecialMesh?,
	light: PointLight?,
	halo: BillboardGui?,
	flame: ParticleEmitter?, -- "FlameTongue"
	embers: ParticleEmitter?, -- "Embers"
	smoke: ParticleEmitter?, -- "Smoke" (dark lanterns only)
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x * K, y * K, z * K)
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x * K, y * K, z * K)
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- cylinders run along X; stand them up
local FACING_Z = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along Z

-- NumberSequence from flat {time, value, time, value, ...}
local function ns(points: { number }): NumberSequence
	local keys = {}
	for i = 1, #points, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function cs(...: Color3): ColorSequence
	local colors = { ... }
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	if #keys == 1 then
		return ColorSequence.new(colors[1])
	end
	return ColorSequence.new(keys)
end

local function addPart(model: Model, handle: Part?, name: string, size: Vector3, cf: CFrame, color, material, extra)
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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

-- A Neon sphere-mesh part: the flame layers. Size is the bounding box; the mesh is animated by Scale/Offset.
local function flamePart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number)
	local part = addPart(model, nil, name, size, cf, color, Enum.Material.Neon, { Transparency = transparency })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one
	mesh.Parent = part
	return part
end

-- Per-material dressing: bone is carved, bloodglass wears gems, verdigris streaks and drips.
local function addTrim(model: Model, def, body: Color3, mat: Enum.Material)
	if def.id == "bone" then
		local groove = Color3.fromRGB(118, 94, 68)
		for _, y in { 0.05, 0.165 } do
			addPart(model, nil, "Groove", v(1.215, 0.016, 1.215), at(0, y, 0), groove, Enum.Material.SmoothPlastic)
		end
		addPart(model, nil, "Groove", v(0.935, 0.016, 0.935), at(0, 1.94, 0), groove, Enum.Material.SmoothPlastic)
	elseif def.id == "bloodglass" then
		-- a faceted gem on the roof's front face and two smaller ones at the sides
		local gem = Color3.fromRGB(190, 22, 28)
		local facet = CFrame.Angles(math.rad(45), 0, math.rad(45))
		addPart(model, nil, "Gem", v(0.14, 0.14, 0.14), at(0, 1.94, -0.5) * facet, gem, Enum.Material.Neon, {
			Transparency = 0.12,
		})
		for _, s in { -1, 1 } do
			addPart(model, nil, "Gem", v(0.1, 0.1, 0.1), at(s * 0.5, 1.94, 0) * facet, gem, Enum.Material.Neon, {
				Transparency = 0.12,
			})
		end
	elseif def.id == "verdigris" then
		local streak = Color3.fromRGB(112, 206, 164)
		addPart(model, nil, "Streak", v(0.15, 0.34, 0.15), at(0.5, 1.18, -0.5), streak, Enum.Material.SmoothPlastic)
		addPart(model, nil, "Streak", v(0.15, 0.26, 0.15), at(-0.5, 0.55, 0.5), streak, Enum.Material.SmoothPlastic)
		-- a drip hanging off the eave
		addPart(model, nil, "Streak", v(0.07, 0.2, 0.05), at(0.3, 1.54, -0.72), streak, Enum.Material.SmoothPlastic)
	elseif def.id == "iron" then
		-- a heavier foot: a second, darker band under the base
		addPart(model, nil, "Foot", v(1.3, 0.05, 1.3), at(0, 0.025, 0), body:Lerp(Color3.new(), 0.3), mat)
	end
end

-- Returns a Model whose PrimaryPart is "Handle" (the base).
function LanternBuilder.buildModel(id: string?, anchored: boolean?): Model
	local def = Lanterns.getOrDefault(id)
	local flame = def.flame
	local body, mat = def.bodyColor, def.bodyMaterial
	local trim = def.trimColor or body:Lerp(Color3.new(1, 1, 1), 0.18)
	local tmat = def.trimMaterial or mat
	local dark = Color3.fromRGB(26, 22, 20)
	local iron = Color3.fromRGB(58, 54, 52)
	local model = Instance.new("Model")
	model.Name = def.name

	local handle = Instance.new("Part")
	handle.Parent = model
	model.PrimaryPart = handle
	addPart(model, handle, "Handle", v(1.2, 0.22, 1.2), at(0, 0.11, 0), body, mat, { Anchored = anchored == true })
	addPart(model, nil, "BaseBand", v(1.28, 0.08, 1.28), at(0, 0.26, 0), trim, tmat)

	-- glass body: a tinted pane box, four riveted corner posts, a cross of mullions on each face
	addPart(model, nil, "Glass", v(0.9, 1.2, 0.9), at(0, 0.9, 0), def.glassColor, Enum.Material.Glass, {
		Transparency = 0.42,
		Reflectance = 0.08,
	})
	-- soot smudge inside the top of the glass
	addPart(model, nil, "Soot", v(0.84, 0.03, 0.84), at(0, 1.46, 0), dark, Enum.Material.SmoothPlastic, {
		Transparency = flame.smoke and 0.4 or 0.58,
	})
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		addPart(model, nil, "Post", v(0.14, 1.26, 0.14), at(c[1] * 0.5, 0.9, c[2] * 0.5), body, mat)
		for _, y in { 0.36, 1.44 } do
			addPart(
				model,
				nil,
				"Rivet",
				v(0.08, 0.08, 0.08),
				at(c[1] * 0.55, y, c[2] * 0.55),
				trim,
				Enum.Material.Metal,
				{
					Shape = Enum.PartType.Ball,
				}
			)
		end
	end
	for _, s in { -1, 1 } do
		addPart(model, nil, "MullionV", v(0.07, 1.2, 0.07), at(0, 0.9, s * 0.47), trim, tmat)
		addPart(model, nil, "MullionH", v(0.9, 0.07, 0.07), at(0, 0.98, s * 0.47), trim, tmat)
		addPart(model, nil, "MullionV", v(0.07, 1.2, 0.07), at(s * 0.47, 0.9, 0), trim, tmat)
		addPart(model, nil, "MullionH", v(0.07, 0.07, 0.9), at(s * 0.47, 0.98, 0), trim, tmat)
	end
	-- the +X pane is a little door: hinge knuckles on one post, a latch bar across to the other
	for _, y in { 0.58, 1.22 } do
		addPart(model, nil, "Hinge", v(0.13, 0.07, 0.07), at(0.585, y, 0.5) * UPRIGHT, trim, Enum.Material.Metal, {
			Shape = Enum.PartType.Cylinder,
		})
	end
	addPart(model, nil, "Latch", v(0.03, 0.06, 0.2), at(0.585, 1.12, -0.4), trim, Enum.Material.Metal)
	addPart(model, nil, "LatchPin", v(0.06, 0.06, 0.06), at(0.6, 1.12, -0.33), trim, Enum.Material.Metal, {
		Shape = Enum.PartType.Ball,
	})
	addPart(model, nil, "TopRail", v(1.2, 0.12, 1.2), at(0, 1.56, 0), body, mat)

	-- flared, stepped roof with a slotted vent cap and a chimney ring
	addPart(model, nil, "Eave", v(1.5, 0.1, 1.5), at(0, 1.67, 0), trim, tmat)
	for i, w in { 1.22, 0.92, 0.62, 0.36 } do
		addPart(model, nil, "Roof", v(w, 0.14, w), at(0, 1.66 + i * 0.14, 0), body, mat)
	end
	addPart(model, nil, "VentCap", v(0.5, 0.07, 0.5), at(0, 2.325, 0), trim, tmat)
	for _, z in { -0.17, 0.17 } do
		addPart(model, nil, "Slot", v(0.36, 0.025, 0.05), at(0, 2.365, z), dark, Enum.Material.SmoothPlastic)
	end
	addPart(model, nil, "ChimneyRing", v(0.06, 0.3, 0.3), at(0, 2.39, 0) * UPRIGHT, body, mat, {
		Shape = Enum.PartType.Cylinder,
	})
	addPart(model, nil, "Neck", v(0.12, 0.14, 0.12), at(0, 2.47, 0), body, mat)
	addPart(model, nil, "Eyelet", v(0.2, 0.2, 0.2), at(0, 2.55, 0), trim, tmat, { Shape = Enum.PartType.Ball })
	-- two flattened dark-iron links join the eyelet to the ring
	addPart(model, nil, "Link", v(0.05, 0.2, 0.13), at(0, 2.64, 0) * FACING_Z, iron, Enum.Material.Metal, {
		Shape = Enum.PartType.Cylinder,
	})
	addPart(model, nil, "Link", v(0.05, 0.2, 0.13), at(0, 2.75, 0), iron, Enum.Material.Metal, {
		Shape = Enum.PartType.Cylinder,
	})

	-- ten-sided ring handle in the X-Y plane
	local radius, sides = 0.42, 10
	local chord = 2 * radius * math.sin(math.pi / sides)
	for i = 0, sides - 1 do
		local a = (i + 0.5) * 2 * math.pi / sides
		local cf = at(math.cos(a) * radius, 3.2 + math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		addPart(model, nil, "Ring", v(chord + 0.05, 0.09, 0.09), cf, trim, tmat)
	end

	-- candle, wick and the layered flame
	addPart(
		model,
		nil,
		"Candle",
		v(0.22, 0.36, 0.22),
		at(0, 0.48, 0),
		Color3.fromRGB(235, 225, 200),
		Enum.Material.SmoothPlastic
	)
	addPart(model, nil, "Wick", v(0.03, 0.1, 0.03), at(0, 0.7, 0), Color3.fromRGB(40, 30, 24), Enum.Material.Fabric)
	local outer = flamePart(model, "Flame", v(0.24, 0.42, 0.24), at(0, 0.9, 0), flame.color, 0.3)
	flamePart(model, "FlameCore", v(0.12, 0.22, 0.12), at(0, 0.83, 0), flame.tip, 0.05)

	-- soft glow around the flame so the lantern reads as light, not a bulb; tinted per flame
	local glow = Instance.new("BillboardGui")
	glow.Name = "Halo"
	glow.Size = UDim2.fromScale(2.2 * K * (0.8 + def.brightness * 0.15), 2.2 * K * (0.8 + def.brightness * 0.15))
	glow.LightInfluence = 0
	glow.Brightness = 1.4
	glow.MaxDistance = 80
	glow.Parent = outer
	for i, spec in { { 1, 0.94 }, { 0.65, 0.88 }, { 0.38, 0.75 }, { 0.18, 0.5 } } do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(spec[1], spec[1])
		ring.BackgroundColor3 = def.lightColor:Lerp(flame.tip, (i - 1) / 4)
		ring.BackgroundTransparency = spec[2]
		ring.BorderSizePixel = 0
		ring.ZIndex = i
		ring.Parent = glow
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = ring
	end

	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = def.lightColor
	light.Brightness = def.brightness
	light.Range = def.range
	light.Shadows = true
	light.Parent = outer

	-- particle flame: a short tongue licking up off the wick, a few slow embers inside the glass,
	-- and for the dark lanterns a wisp from the chimney. All locked to the lantern so nothing trails.
	local wickTop = Instance.new("Attachment")
	wickTop.Name = "FlameAt"
	wickTop.Position = v(0, 0.75 - 0.11, 0) -- relative to the Handle's centre
	wickTop.Parent = handle
	emitter(wickTop, {
		Name = "FlameTongue",
		Texture = TEX.glow,
		EmissionDirection = Enum.NormalId.Top,
		Rate = math.min(flame.rate, 12),
		Lifetime = NumberRange.new(0.28, 0.45),
		Speed = NumberRange.new(0.5, 0.9),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(0, 0.6, 0),
		Drag = 1.5,
		Size = ns({ 0, 0.26 * K, 0.4, 0.2 * K, 1, 0.04 * K }),
		Transparency = ns({ 0, 0.25, 0.6, 0.45, 1, 1 }),
		Color = cs(flame.tip, flame.color, flame.color:Lerp(Color3.new(), 0.35)),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2,
		LockedToPart = true,
		Rotation = NumberRange.new(-20, 20),
	})
	emitter(wickTop, {
		Name = "Embers",
		Texture = TEX.dot,
		EmissionDirection = Enum.NormalId.Top,
		Rate = flame.smoke and 3 or 2,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.3, 0.6),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 0.3, 0),
		Drag = 0.5,
		Size = ns({ 0, 0.035, 1, 0.012 }),
		Transparency = ns({ 0, 0.2, 0.7, 0.4, 1, 1 }),
		Color = cs(flame.emberColor),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		LockedToPart = true,
	})
	if flame.smoke then
		local chimney = Instance.new("Attachment")
		chimney.Name = "ChimneyAt"
		chimney.Position = v(0, 2.42 - 0.11, 0)
		chimney.Parent = handle
		emitter(chimney, {
			Name = "Smoke",
			Texture = TEX.smoke,
			EmissionDirection = Enum.NormalId.Top,
			Rate = 1.2,
			Lifetime = NumberRange.new(1.6, 2.6),
			Speed = NumberRange.new(0.4, 0.7),
			SpreadAngle = Vector2.new(6, 6),
			Acceleration = Vector3.new(0, 0.2, 0),
			Drag = 0.8,
			Size = ns({ 0, 0.08, 1, 0.5 }),
			Transparency = ns({ 0, 1, 0.15, 0.82, 1, 1 }),
			RotSpeed = NumberRange.new(-40, 40),
			Rotation = NumberRange.new(0, 360),
			Color = cs(flame.smokeColor or Color3.fromRGB(60, 56, 54)),
			LightEmission = 0,
			LightInfluence = 0,
		})
	end

	addTrim(model, def, body, mat)

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
	-- the lobby is dim now, so the lantern you carry is what lights your way: near full strength,
	-- a little wider, softened only enough that the avatar holding it doesn't blow out
	local light = model:FindFirstChild("Light", true)
	if light then
		light.Brightness *= 0.65
		light.Range += 7
	end
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	return tool
end

-- The animatable flame pieces of a lantern Model or Tool (nil if it has no flame).
function LanternBuilder.flameParts(root: Instance): FlameParts?
	local outer = root:FindFirstChild("Flame", true)
	if not outer or not outer:IsA("BasePart") then
		return nil
	end
	local inner = root:FindFirstChild("FlameCore", true)
	return {
		outer = outer,
		inner = inner,
		outerMesh = outer:FindFirstChildOfClass("SpecialMesh"),
		innerMesh = inner and inner:FindFirstChildOfClass("SpecialMesh"),
		light = outer:FindFirstChild("Light"),
		halo = outer:FindFirstChild("Halo"),
		flame = root:FindFirstChild("FlameTongue", true),
		embers = root:FindFirstChild("Embers", true),
		smoke = root:FindFirstChild("Smoke", true),
	}
end

return LanternBuilder
