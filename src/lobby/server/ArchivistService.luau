-- Mr. Ashby, the archivist: a thin, stooped, faintly ghostly clerk who keeps the ledger of everyone
-- who has gone through the doors. He stands behind his little desk at the Challenges station
-- (Layout.Stations.Challenges.npc; the desk itself is built by builders/Rooms/Stations). No
-- ProximityPrompt: stepping onto the station's ring opens the challenges panel, and his dialogue
-- is started from the client (Archivist.client, BindableEvent TalkArchivist).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared.Rewards)

local ArchivistService = {}

-- fallback if Builders.Layout can't be read: behind the desk in the reading hall, facing -Z
local DEFAULT_CFRAME = CFrame.lookAt(Vector3.new(-11, 0, 28.05), Vector3.new(-11, 0, 20))
local IDLE_ANIMATION = "rbxassetid://507766666" -- default R15 idle
local STOOP = math.rad(-9) -- forward lean at the waist: forty years over a ledger

local SKIN = Color3.fromRGB(178, 192, 198) -- pale grey-blue: not quite alive
local SHIRT = Color3.fromRGB(226, 228, 222)
local WAISTCOAT = Color3.fromRGB(40, 44, 46)
local TROUSERS = Color3.fromRGB(48, 48, 52)
local GARTER = Color3.fromRGB(118, 34, 36)
local BRASS = Color3.fromRGB(176, 142, 74)
local WIRE = Color3.fromRGB(150, 154, 156)
local VISOR = Color3.fromRGB(56, 150, 96) -- green celluloid eyeshade
local HAIR = Color3.fromRGB(222, 228, 232)
local INK = Color3.fromRGB(24, 30, 54)
local GHOST = Color3.fromRGB(130, 220, 226) -- his cold glow (eyes and light)

-- Attach a clothing part to a body part; the rig animates, so everything welds rather than anchors.
-- (Same approach as GuideService.)
local function wear(
	rig: Model,
	bodyPartName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	extra: { [string]: any }?
): BasePart
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
	part.CastShadow = false -- small trims; the lobby keeps its shadow budget for the big shapes
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in extra or {} do
		(part :: any)[key] = value
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = part
	weld.Parent = part
	part.Parent = rig
	return part
end

-- Tilt a joint's rest pose (Motor6D C0, or the parent-side attachment of an AnimationConstraint
-- on newer rigs). The idle animation plays on top of it.
local function bend(part: Instance?, jointName: string, rotation: CFrame)
	local joint = part and part:FindFirstChild(jointName)
	if not joint then
		return
	end
	if joint:IsA("Motor6D") then
		joint.C0 *= rotation
	elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
		joint.Attachment0.CFrame *= rotation
	end
end

local function dress(rig: Model)
	local upper = (rig :: any).UpperTorso.Size
	local lower = (rig :: any).LowerTorso.Size
	local head = (rig :: any).Head.Size
	local front = -(upper.Z / 2)

	-- trousers over the lower torso (the description colours the whole torso white for the shirt)
	wear(
		rig,
		"LowerTorso",
		"Trousers",
		lower + Vector3.new(0.06, 0.02, 0.06),
		CFrame.new(),
		TROUSERS,
		Enum.Material.Fabric
	)

	-- white shirt sleeves with red garters round the upper arms, ink on the fingertips
	for _, side in { "Left", "Right" } do
		local arm = (rig :: any)[side .. "UpperArm"].Size
		wear(
			rig,
			side .. "UpperArm",
			"Sleeve",
			arm + Vector3.new(0.08, 0.02, 0.08),
			CFrame.new(),
			SHIRT,
			Enum.Material.Fabric
		)
		wear(
			rig,
			side .. "UpperArm",
			"Garter",
			Vector3.new(arm.X + 0.14, 0.12, arm.Z + 0.14),
			CFrame.new(0, -arm.Y * 0.05, 0),
			GARTER,
			Enum.Material.SmoothPlastic
		)
		wear(
			rig,
			side .. "LowerArm",
			"Cuff",
			(rig :: any)[side .. "LowerArm"].Size + Vector3.new(0.08, 0, 0.08),
			CFrame.new(),
			SHIRT,
			Enum.Material.Fabric
		)
		local hand = (rig :: any)[side .. "Hand"].Size
		wear(
			rig,
			side .. "Hand",
			"InkStain",
			Vector3.new(hand.X * 0.7, 0.14, hand.Z + 0.02),
			CFrame.new(0, -hand.Y / 2 + 0.07, 0),
			INK,
			Enum.Material.SmoothPlastic
		)
	end

	-- dark waistcoat with the shirt front and a black tie showing in the V
	wear(
		rig,
		"UpperTorso",
		"Waistcoat",
		upper + Vector3.new(0.1, -0.12, 0.1),
		CFrame.new(0, -0.06, 0),
		WAISTCOAT,
		Enum.Material.Fabric
	)
	wear(
		rig,
		"UpperTorso",
		"ShirtFront",
		Vector3.new(upper.X * 0.22, upper.Y * 0.42, 0.04),
		CFrame.new(0, upper.Y * 0.29, front - 0.06),
		SHIRT,
		Enum.Material.Fabric
	)
	wear(
		rig,
		"UpperTorso",
		"Collar",
		Vector3.new(upper.X * 0.42, 0.2, upper.Z * 0.62),
		CFrame.new(0, upper.Y / 2 + 0.02, 0),
		SHIRT,
		Enum.Material.Fabric
	)
	wear(
		rig,
		"UpperTorso",
		"Tie",
		Vector3.new(0.12, upper.Y * 0.36, 0.04),
		CFrame.new(0, upper.Y * 0.28, front - 0.09),
		Color3.fromRGB(20, 20, 22),
		Enum.Material.SmoothPlastic
	)
	for i = 1, 3 do
		wear(
			rig,
			"UpperTorso",
			"Button",
			Vector3.new(0.1, 0.1, 0.04),
			CFrame.new(0, upper.Y * (0.02 - 0.16 * i), front - 0.08),
			BRASS,
			Enum.Material.Metal
		)
	end
	-- a watch chain sagging from the middle button to a pocket, and the fob hanging out of it
	local chainY = -upper.Y * 0.18
	for _, s in { -1, 1 } do
		wear(
			rig,
			"UpperTorso",
			"WatchChain",
			Vector3.new(upper.X * 0.17, 0.035, 0.035),
			CFrame.new(s * upper.X * 0.08, chainY - 0.05, front - 0.08) * CFrame.Angles(0, 0, s * math.rad(14)),
			BRASS,
			Enum.Material.Metal
		)
	end
	wear(
		rig,
		"UpperTorso",
		"PocketWatch",
		Vector3.new(0.04, 0.17, 0.17),
		CFrame.new(upper.X * 0.17, chainY, front - 0.08) * CFrame.Angles(0, math.rad(90), 0),
		BRASS,
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }
	)

	-- head: thin white wisps at the sides and back (bald on top, under the eyeshade's band)
	local hx, hy, hz = head.X / 2, head.Y / 2, head.Z / 2
	local function wisp(size: Vector3, offset: Vector3)
		local part = wear(rig, "Head", "Hair", size, CFrame.new(offset), HAIR, Enum.Material.SmoothPlastic)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	wisp(Vector3.new(hx * 1.9, hy * 0.8, hz * 0.6), Vector3.new(0, -hy * 0.15, hz * 0.85))
	for _, s in { -1, 1 } do
		wisp(Vector3.new(hx * 0.45, hy * 0.7, hz * 1.2), Vector3.new(s * hx * 0.98, -hy * 0.1, hz * 0.3))
	end

	-- the clerk's green celluloid eyeshade: a band round the head and a translucent brim over the eyes
	local band = wear(
		rig,
		"Head",
		"VisorBand",
		Vector3.new(0.14, head.X + 0.08, head.Z + 0.08),
		CFrame.new(0, hy * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
		VISOR:Lerp(Color3.new(), 0.45),
		Enum.Material.SmoothPlastic
	)
	local bandMesh = Instance.new("SpecialMesh")
	bandMesh.MeshType = Enum.MeshType.Cylinder
	bandMesh.Parent = band
	wear(
		rig,
		"Head",
		"Visor",
		Vector3.new(head.X * 0.95, 0.05, 0.6),
		CFrame.new(0, hy * 0.5, -hz - 0.22) * CFrame.Angles(math.rad(-20), 0, 0),
		VISOR,
		Enum.Material.SmoothPlastic,
		{ Transparency = 0.3 }
	)

	-- round wire spectacles, and behind them two faint cold pinpricks where the eyes should be
	local eyeY = hy * 0.12
	for _, x in { -0.19, 0.19 } do
		wear(
			rig,
			"Head",
			"Eye",
			Vector3.new(0.09, 0.09, 0.09),
			CFrame.new(x, eyeY, -hz + 0.02),
			GHOST,
			Enum.Material.Neon,
			{ Shape = Enum.PartType.Ball }
		)
		wear(
			rig,
			"Head",
			"Lens",
			Vector3.new(0.02, 0.28, 0.28),
			CFrame.new(x, eyeY, -hz - 0.08) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(210, 228, 230),
			Enum.Material.Glass,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.6 }
		)
		wear(
			rig,
			"Head",
			"LensRim",
			Vector3.new(0.015, 0.31, 0.31),
			CFrame.new(x, eyeY, -hz - 0.07) * CFrame.Angles(0, math.rad(90), 0),
			WIRE,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	wear(
		rig,
		"Head",
		"Bridge",
		Vector3.new(0.12, 0.025, 0.025),
		CFrame.new(0, eyeY + 0.03, -hz - 0.08),
		WIRE,
		Enum.Material.Metal
	)

	-- a dip pen in his right hand
	wear(
		rig,
		"RightHand",
		"Pen",
		Vector3.new(0.65, 0.06, 0.06),
		CFrame.new(0, -0.1, -0.18) * CFrame.Angles(0, math.rad(90), math.rad(-25)),
		Color3.fromRGB(26, 22, 20),
		Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder }
	)
end

local function nameTag(rig: Model)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(260, 30)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	tag.Parent = (rig :: any).Head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(196, 226, 226) -- the lobby's cream, gone cold
	label.TextStrokeTransparency = 0.5
	label.Text = "the archivist"
	label.Parent = tag
end

function ArchivistService.build(parent: Instance, at: CFrame): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.LeftArmColor = SKIN -- sleeves cover the arms; this is for the hands
	description.RightArmColor = SKIN
	description.TorsoColor = SHIRT
	description.LeftLegColor = TROUSERS
	description.RightLegColor = TROUSERS
	-- thin and a little shrunken
	description.HeightScale = 1.02
	description.WidthScale = 0.78
	description.DepthScale = 0.82
	description.HeadScale = 0.96

	local ok, rig = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok then
		warn("[ArchivistService] couldn't build the archivist rig: " .. tostring(rig))
		return nil
	end
	rig.Name = "Archivist"
	local face = rig.Head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy() -- the spectacles and the two cold pinpricks are his face
	end
	-- dynamic heads paint the default smile into the head mesh's texture: wipe it so the face is blank
	-- and pale (only his eyes glow), which reads as a ghost rather than a default avatar
	pcall(function()
		local head = (rig :: any).Head
		if head:IsA("MeshPart") then
			head.TextureID = ""
		end
	end)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy() -- we drive the idle ourselves
	end

	-- stand on the floor behind the desk, facing the ring
	rig:PivotTo(at)
	local cf, size = rig:GetBoundingBox()
	rig:PivotTo(rig:GetPivot() + Vector3.new(0, at.Position.Y - (cf.Position.Y - size.Y / 2), 0))
	rig.HumanoidRootPart.Anchored = true

	-- stooped over his ledger (rest pose; the idle animation layers on top)
	bend(rig:FindFirstChild("UpperTorso"), "Waist", CFrame.Angles(STOOP, 0, 0))

	dress(rig)
	nameTag(rig)

	-- a faint, cold, shadowless glow: you notice it more than you see it (Archivist.client flickers it)
	local light = Instance.new("PointLight")
	light.Name = "GhostLight"
	light.Color = GHOST
	light.Range = 6
	light.Brightness = 0.45
	light.Shadows = false
	light.Parent = rig.UpperTorso

	rig:SetAttribute("DisplayName", Rewards.ArchivistName)
	CollectionService:AddTag(rig, "NPC")
	rig.Parent = parent

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local idle = Instance.new("Animation")
	idle.AnimationId = IDLE_ANIMATION
	local played = pcall(function()
		local track = (animator :: Animator):LoadAnimation(idle)
		track.Looped = true
		track:Play()
		track:AdjustSpeed(0.8) -- an old man's breathing
	end)
	if not played then
		warn("[ArchivistService] idle animation failed to load")
	end
	return rig
end

function ArchivistService.start(lobby: Instance)
	local at = DEFAULT_CFRAME
	local builders = ServerStorage:FindFirstChild("Builders")
	local layoutModule = builders and builders:FindFirstChild("Layout")
	if layoutModule then
		local ok, layout = pcall(require, layoutModule)
		local station = ok and layout.Stations and layout.Stations.Challenges
		if station and station.npc then
			at = station.npc
		end
	end
	return ArchivistService.build(lobby, at)
end

return ArchivistService
