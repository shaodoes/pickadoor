--[[
	The Librarian: a tall, quiet guide standing in the arrival foyer with a lantern, beside a small
	reading lectern. Baked into the lobby by Npcs.build (so he shows in Studio's Edit mode as well);
	at runtime GuideService adopts that copy (or builds one if it's missing) and starts his idle.
	Players talk to him (ProximityPrompt, Panel = "Guide"); the dialogue itself runs in Guide.client.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Parent.Layout)
local LanternBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LanternBuilder"))

local Librarian = {}

-- In the arrival foyer, at the top of the grand stair and just off the walkway, turned toward the
-- spawn so he's the first thing you see when you come down from the house (Layout.Guide).
local POSITION = Layout.Guide.position
local FACING = Layout.Guide.facing

local SKIN = Color3.fromRGB(196, 186, 172)
local COAT = Color3.fromRGB(56, 46, 38)
local SCARF = Color3.fromRGB(96, 32, 28)
local HAIR = Color3.fromRGB(214, 214, 220) -- old-man white-grey, cool so it reads against warm skin

-- Attach a clothing part to a body part; the rig animates, so everything welds rather than anchors.
local function wear(
	rig: Model,
	bodyPartName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	extra
)
	local bodyPart = rig:FindFirstChild(bodyPartName) :: BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = bodyPart.CFrame * offset
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in extra or {} do
		part[key] = value
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = rig
	return part
end

local function dress(rig: Model)
	local upper = rig.UpperTorso.Size
	local lower = rig.LowerTorso.Size
	local head = rig.Head.Size
	local arm = rig.RightUpperArm.Size

	-- long coat: body, skirt to the knees, sleeves
	wear(
		rig,
		"UpperTorso",
		"Coat",
		upper + Vector3.new(0.18, 0.1, 0.2),
		CFrame.new(0, -0.02, 0),
		COAT,
		Enum.Material.SmoothPlastic
	)
	wear(
		rig,
		"LowerTorso",
		"CoatSkirt",
		Vector3.new(lower.X + 0.4, 2.3, lower.Z + 0.4),
		CFrame.new(0, -0.95, 0),
		COAT,
		Enum.Material.SmoothPlastic
	)
	for _, side in { "Left", "Right" } do
		wear(
			rig,
			side .. "UpperArm",
			"Sleeve",
			arm + Vector3.new(0.12, 0.05, 0.12),
			CFrame.new(),
			COAT,
			Enum.Material.SmoothPlastic
		)
		wear(
			rig,
			side .. "LowerArm",
			"Cuff",
			rig[side .. "LowerArm"].Size + Vector3.new(0.1, -0.2, 0.1),
			CFrame.new(0, 0.1, 0),
			COAT,
			Enum.Material.SmoothPlastic
		)
	end
	for i = -1, 1, 2 do
		wear(
			rig,
			"UpperTorso",
			"Button",
			Vector3.new(0.12, 0.12, 0.05),
			CFrame.new(0.15 * i, -0.3, -(upper.Z / 2 + 0.11)),
			Color3.fromRGB(150, 112, 56),
			Enum.Material.Metal
		)
	end
	wear(
		rig,
		"UpperTorso",
		"Scarf",
		Vector3.new(upper.X * 0.7, 0.35, upper.Z + 0.3),
		CFrame.new(0, upper.Y / 2 - 0.05, 0),
		SCARF,
		Enum.Material.SmoothPlastic
	)
	wear(
		rig,
		"UpperTorso",
		"ScarfTail",
		Vector3.new(0.35, 1.1, 0.1),
		CFrame.new(0.3, upper.Y / 2 - 0.65, -(upper.Z / 2 + 0.15)),
		SCARF,
		Enum.Material.SmoothPlastic
	)

	-- thin grey hair: a balding librarian's fringe round the sides and back, wild tufts over the
	-- ears and a few combed-over strands on top. Rounded (sphere-mesh) tufts sit partly inside the
	-- round head so nothing reads as a box; head front is -Z.
	local hx, hy, hz = head.X / 2, head.Y / 2, head.Z / 2
	local function tuft(name: string, size: Vector3, offset: Vector3, tilt: CFrame?)
		local part = wear(
			rig,
			"Head",
			name,
			size,
			CFrame.new(offset) * (tilt or CFrame.new()),
			HAIR,
			Enum.Material.SmoothPlastic
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		part.CastShadow = false
		return part
	end
	tuft("HairBack", Vector3.new(hx * 2.1, hy * 1.05, hz * 0.75), Vector3.new(0, -0.06, hz * 0.85))
	for _, s in { -1, 1 } do
		-- fringe hugging each side, from the temple round to the back, standing proud of the skull
		tuft("HairSide", Vector3.new(hx * 0.55, hy * 0.85, hz * 1.55), Vector3.new(s * hx * 1.0, -0.02, hz * 0.28))
		-- the unruly tuft over each ear, sticking out
		tuft(
			"HairTuft",
			Vector3.new(hx * 0.62, hy * 0.48, hz * 0.75),
			Vector3.new(s * hx * 1.1, hy * 0.42, hz * 0.05),
			CFrame.Angles(0, 0, s * math.rad(-30))
		)
	end
	-- a sparse comb-over: three thin strands lying across the crown
	for i, x in { -0.2, 0, 0.2 } do
		tuft(
			"HairStrand",
			Vector3.new(hx * 0.36, 0.1, hz * 1.65),
			Vector3.new(x * hx * 2, hy * 1.02, hz * 0.12),
			CFrame.Angles(math.rad(-6), math.rad((i - 2) * 6), 0)
		)
	end

	local front = -(head.Z / 2)
	for _, x in { -0.2, 0.2 } do
		wear(
			rig,
			"Head",
			"Lens",
			Vector3.new(0.03, 0.34, 0.34),
			CFrame.new(x, 0.27, front - 0.07) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(220, 230, 225),
			Enum.Material.Glass,
			{
				Shape = Enum.PartType.Cylinder,
				Transparency = 0.5,
			}
		)
		wear(
			rig,
			"Head",
			"LensRim",
			Vector3.new(0.02, 0.38, 0.38),
			CFrame.new(x, 0.27, front - 0.06) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(120, 92, 50),
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	wear(
		rig,
		"Head",
		"Bridge",
		Vector3.new(0.14, 0.03, 0.03),
		CFrame.new(0, 0.3, front - 0.07),
		Color3.fromRGB(120, 92, 50),
		Enum.Material.Metal
	)
end

local function nameTag(rig: Model)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 30)
	tag.StudsOffset = Vector3.new(0, 2.4, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	tag.Parent = rig.Head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(230, 214, 186)
	label.TextStrokeTransparency = 0.5
	label.Text = "the librarian"
	label.Parent = tag
end

function Librarian.build(parent: Instance): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.LeftArmColor = SKIN
	description.RightArmColor = SKIN
	description.TorsoColor = COAT
	description.LeftLegColor = Color3.fromRGB(36, 30, 26)
	description.RightLegColor = Color3.fromRGB(36, 30, 26)
	description.HeightScale = 1.12
	description.WidthScale = 0.9
	description.DepthScale = 0.92

	local ok, rig = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[Npcs.Librarian] couldn't build the guide rig: " .. tostring(rig))
		return nil
	end
	rig.Name = "Guide"
	local face = rig.Head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy()
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- we drive the idle ourselves
	end

	-- stand on the floor, facing the stairs
	rig:PivotTo(CFrame.lookAt(POSITION, Vector3.new(FACING.X, POSITION.Y, FACING.Z)))
	local cf, size = rig:GetBoundingBox()
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, POSITION.Y - (cf.Position.Y - size.Y / 2), 0))
	rig.HumanoidRootPart.Anchored = true

	dress(rig)
	nameTag(rig)
	rig.Parent = parent

	-- a lantern of its own, hanging upright from its right hand by the ring
	local hand = rig.RightHand
	local lantern = LanternBuilder.buildModel("copper", false)
	lantern.Name = "Lantern"
	local scale = 0.65 -- a smaller lantern, so it hangs at knee height from a lowered arm
	lantern:ScaleTo(scale)
	local hangAt = hand.Position - Vector3.new(0, LanternBuilder.RingHeight * scale + 0.05, 0)
	lantern:PivotTo(CFrame.new(hangAt) * rig.HumanoidRootPart.CFrame.Rotation)
	local light = lantern:FindFirstChild("Light", true)
	if light then
		light.Brightness *= 0.6
	end
	local grip = Instance.new("WeldConstraint")
	grip.Part0 = hand
	grip.Part1 = lantern.PrimaryPart
	grip.Parent = lantern.PrimaryPart
	lantern.Parent = rig

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "The Librarian"
	prompt.ActionText = "Talk"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute("Panel", "Guide")
	prompt.Parent = rig.HumanoidRootPart

	return rig
end

-- A small reading lectern next to the guide: post, slanted top, an open book and a candle.
function Librarian.lectern(parent: Instance, guide: Model): Model
	local root = guide.HumanoidRootPart.CFrame
	-- on the floor beside him (the root part is ~3 studs up; the lectern must stand on the floor)
	local beside = (root * CFrame.new(2.6, 0, -0.6)).Position -- on his far side, clear of the stair approach
	local base = CFrame.new(beside.X, POSITION.Y, beside.Z) * root.Rotation * CFrame.Angles(0, math.rad(25), 0)
	local model = Instance.new("Model")
	model.Name = "Lectern"
	local function part(name, size, cf, color, material, extra)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in extra or {} do
			p[k] = v
		end
		p.Parent = model
		return p
	end
	local wood = Color3.fromRGB(78, 52, 34)
	part("Foot", Vector3.new(1.8, 0.3, 1.4), base * CFrame.new(0, 0.15, 0), wood, Enum.Material.Wood)
	part("Post", Vector3.new(0.5, 3.4, 0.5), base * CFrame.new(0, 1.9, 0), wood, Enum.Material.Wood)
	local top = part(
		"Top",
		Vector3.new(2.2, 0.2, 1.6),
		base * CFrame.new(0, 3.7, 0) * CFrame.Angles(math.rad(-22), 0, 0),
		Color3.fromRGB(96, 64, 40),
		Enum.Material.Wood
	)
	for _, side in { -1, 1 } do
		part(
			"Page",
			Vector3.new(0.95, 0.06, 1.3),
			top.CFrame * CFrame.new(side * 0.5, 0.13, 0) * CFrame.Angles(0, 0, math.rad(side * -4)),
			Color3.fromRGB(226, 216, 190),
			Enum.Material.SmoothPlastic,
			{ CanCollide = false }
		)
	end
	part(
		"Candle",
		Vector3.new(0.22, 0.5, 0.22),
		top.CFrame * CFrame.new(0.95, 0.35, -0.55),
		Color3.fromRGB(235, 225, 200),
		Enum.Material.SmoothPlastic,
		{ CanCollide = false }
	)
	local flame = part(
		"Flame",
		Vector3.new(0.14, 0.24, 0.14),
		top.CFrame * CFrame.new(0.95, 0.72, -0.55),
		Color3.fromRGB(255, 150, 60),
		Enum.Material.Neon,
		{
			CanCollide = false,
			CastShadow = false,
			Shape = Enum.PartType.Ball,
		}
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 100)
	light.Range = 10
	light.Brightness = 1.2
	light.Shadows = true
	light.Parent = flame
	light:SetAttribute("Flicker", "furnace") -- the lobby's flicker loop makes it waver like a flame
	model.Parent = parent
	return model
end

return Librarian
