--[[
	The Shopkeeper, "Teeth": the thing behind the gift-shop counter. A tall, hunched, black-violet
	figure with a huge jagged grin, two glowing eyes and gangly arms that reach the floor. Built at
	runtime from anchored parts (no Humanoid); Shopkeeper.client re-poses the parts every frame
	(head tracking, breathing, tics) from the rest pose stored here as attributes:
	  Rest      CFrame of the part relative to HumanoidRootPart at rest (every part but the root)
	  Bone      the animated bone the part follows: "Root" | "Torso" | "Head" | "ArmL" | "ArmR"
	  BoneName  on the four bone parts (UpperTorso, Head, LeftUpperArm, RightUpperArm), together with
	  Pivot     the joint that bone rotates about (CFrame relative to the root)
	  Row       "Top" | "Bottom" on teeth (the grin widens by spreading the rows); "Mouth" on the gash
	Part names other systems rely on: HumanoidRootPart (prompt host), UpperTorso, Head, EyeL, EyeR.
]]
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local ShopkeeperService = {}

local DEFAULT_POSITION = Vector3.new(-23.4, 6, 53.2)
local DEFAULT_FACING = Vector3.new(-12, 6, 53.2)

local SKIN = Color3.fromRGB(30, 20, 50)
local SKIN_MATERIAL = Enum.Material.Leather -- fine grain that catches the rim light; near-black otherwise
local CLAW = Color3.fromRGB(104, 92, 128)
local TOOTH = Color3.fromRGB(240, 236, 228)
local EYE = Color3.fromRGB(226, 226, 255)
local EYE_LIGHT = Color3.fromRGB(196, 196, 255)
local RIM_LIGHT = Color3.fromRGB(138, 90, 230)
local TAG = Color3.fromRGB(214, 200, 255)

-- Skeleton in the figure's own frame: origin on the floor between the feet, -Z forward, +Y up.
-- He is ~10 studs to the top of the stooped head (would be taller standing straight).
local ROOT_CF = CFrame.new(0, 3.85, 0.1) -- hips
local WAIST_CF = CFrame.new(0, 4.94, -0.035) * CFrame.Angles(math.rad(-12), 0, 0)
local WAIST_BASE = Vector3.new(0, 4.3, 0.1)
local CHEST_CF = CFrame.new(0, 6.55, -0.78) * CFrame.Angles(math.rad(-32), 0, 0)
local NECK_BASE = Vector3.new(0, 7.5, -1.45)
local NECK_TOP = Vector3.new(0, 8.05, -2.08)
local HEAD_CF = CFrame.new(0, 8.85, -2.3) * CFrame.Angles(math.rad(-22), 0, 0) -- stooped, eyes down
local HEAD_R = 1.2
local FACE_C = Vector3.new(0, -0.3, -0.25) -- in head space: the lower face / jaw ball the grin wraps
local FACE_R = 1.1
-- Arms: the right hangs to the floor behind the counter; the left reaches over and rests its claws
-- on the counter top (3.5 studs up, 1.3..3.9 studs in front of his feet), elbow cocked out.
local SHOULDER = { L = Vector3.new(-1.0, 7.3, -1.3), R = Vector3.new(1.0, 7.3, -1.3) }
local ELBOW = { L = Vector3.new(-2.0, 4.8, -0.5), R = Vector3.new(1.6, 4.5, -1.2) }
local WRIST = { L = Vector3.new(-1.3, 3.75, -2.95), R = Vector3.new(1.45, 1.65, -1.0) }
local PALM_L = CFrame.new(-1.3, 3.63, -3.4) * CFrame.Angles(math.rad(90), 0, 0) -- flat, fingers forward
local HIP = { L = Vector3.new(-0.5, 3.75, 0.1), R = Vector3.new(0.5, 3.75, 0.1) }
local KNEE = { L = Vector3.new(-0.55, 1.95, -0.05), R = Vector3.new(0.55, 1.95, -0.05) }
local ANKLE = { L = Vector3.new(-0.55, 0.3, 0.2), R = Vector3.new(0.55, 0.3, 0.2) }

local function nameTag(head: BasePart)
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(200, 30)
	tag.StudsOffset = Vector3.new(0, 2.1, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	tag.Parent = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SpecialElite
	label.TextScaled = true
	label.TextColor3 = TAG
	label.TextStrokeColor3 = Color3.fromRGB(20, 8, 40)
	label.TextStrokeTransparency = 0.5
	label.Text = "teeth"
	label.Parent = tag
end

local function eyeLight(parent: BasePart)
	local light = Instance.new("PointLight")
	light.Color = EYE_LIGHT
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = parent
	return light
end

-- Build him in his own frame, then place the whole thing at `world`.
local function assemble(model: Model, world: CFrame)
	local rng = Random.new(31)
	local placed: { [BasePart]: CFrame } = {}

	local function add(name: string, size: Vector3, cf: CFrame, bone: string, props: { [string]: any }?): BasePart
		local part = Instance.new(if props and props.Wedge then "WedgePart" else "Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.Color = SKIN
		part.Material = SKIN_MATERIAL
		part.CanCollide = false
		part.CanQuery = true -- nothing collides with him, but the laser's raycast must be able to hit him
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if props then
			for key, value in props do
				if key ~= "Wedge" then
					part[key] = value
				end
			end
		end
		part:SetAttribute("Bone", bone)
		part.Parent = model
		placed[part] = cf
		return part
	end
	local function ball(name: string, diameter: number, cf: CFrame, bone: string, props: { [string]: any }?)
		local p = add(name, Vector3.new(diameter, diameter, diameter), cf, bone, props)
		p.Shape = Enum.PartType.Ball
		return p
	end
	-- a cylinder running from one joint to the next
	local function limb(name: string, from: Vector3, to: Vector3, diameter: number, bone: string, props)
		local len = (to - from).Magnitude
		local cf = CFrame.lookAt((from + to) / 2, to, Vector3.xAxis) * CFrame.Angles(0, math.rad(90), 0)
		local p = add(name, Vector3.new(len, diameter, diameter), cf, bone, props)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	---------------------------------------------------------------------------------------
	-- root, hips, legs
	---------------------------------------------------------------------------------------
	local root = add("HumanoidRootPart", Vector3.new(1.6, 1.6, 1.0), ROOT_CF, "Root", {
		Transparency = 1,
		CanCollide = true,
		CanQuery = true,
	})
	add("LowerTorso", Vector3.new(1.4, 0.9, 0.85), ROOT_CF, "Root", { CastShadow = true })
	for _, side in { "L", "R" } do
		local name = if side == "L" then "Left" else "Right"
		ball(name .. "Hip", 0.56, CFrame.new(HIP[side]), "Root")
		limb(name .. "UpperLeg", HIP[side], KNEE[side], 0.42, "Root", { CastShadow = true })
		ball(name .. "Knee", 0.46, CFrame.new(KNEE[side]), "Root")
		limb(name .. "LowerLeg", KNEE[side], ANKLE[side], 0.34, "Root")
		local footCf = CFrame.new(ANKLE[side].X, 0.14, ANKLE[side].Z - 0.42)
		add(name .. "Foot", Vector3.new(0.48, 0.28, 1.15), footCf, "Root")
		for i = -1, 1 do
			add(
				name .. "Toe",
				Vector3.new(0.11, 0.1, 0.5),
				footCf * CFrame.new(i * 0.16, 0.02, -0.75) * CFrame.Angles(math.rad(-18), math.rad(i * 10), 0),
				"Root",
				{ Color = CLAW }
			)
		end
	end
	-- a faint violet underlight just behind the counter, lighting his chest and chin from below and
	-- haloing the wall behind him, so the figure reads in the dark shop
	local rim = add("Rim", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 2.6, -1.1), "Root", { Transparency = 1 })
	local rimLight = Instance.new("PointLight")
	rimLight.Color = RIM_LIGHT
	rimLight.Range = 14
	rimLight.Brightness = 0.6
	rimLight.Shadows = false
	rimLight.Parent = rim

	---------------------------------------------------------------------------------------
	-- torso (the bone "Torso" pivots at the waist so the breathing lifts the chest and head)
	---------------------------------------------------------------------------------------
	add("Waist", Vector3.new(1.1, 1.4, 0.75), WAIST_CF, "Torso", { CastShadow = true })
	local chest = add("UpperTorso", Vector3.new(1.8, 2.3, 1.05), CHEST_CF, "Torso", { CastShadow = true })
	chest:SetAttribute("BoneName", "Torso")
	chest:SetAttribute("Pivot", CFrame.new(WAIST_BASE))
	-- the hunch: a hump over the shoulder blades
	ball("Hump", 1.5, CHEST_CF * CFrame.new(0, 0.55, 0.45), "Torso", { CastShadow = true })
	-- knobbly spine down the back, ribs and collarbones under the skin
	for i = -2, 2 do
		ball("Vertebra", 0.3, CHEST_CF * CFrame.new(0, i * 0.45, 0.56), "Torso")
	end
	for i = -1, 1, 2 do
		ball("Vertebra", 0.28, WAIST_CF * CFrame.new(0, i * 0.35, 0.4), "Torso")
	end
	for _, s in { -1, 1 } do
		for i, y in { -0.15, -0.5, -0.85 } do
			add(
				"Rib",
				Vector3.new(0.8 - i * 0.08, 0.07, 0.1),
				CHEST_CF * CFrame.new(s * 0.5, y, -0.5) * CFrame.Angles(0, 0, s * math.rad(14)),
				"Torso"
			)
		end
		add(
			"Collarbone",
			Vector3.new(0.95, 0.1, 0.14),
			CHEST_CF * CFrame.new(s * 0.5, 0.95, -0.48) * CFrame.Angles(0, 0, -s * math.rad(12)),
			"Torso"
		)
		ball(
			if s < 0 then "LeftShoulder" else "RightShoulder",
			0.7,
			CFrame.new(SHOULDER[if s < 0 then "L" else "R"]),
			"Torso"
		)
	end
	limb("Neck", NECK_BASE, NECK_TOP, 0.46, "Torso")

	---------------------------------------------------------------------------------------
	-- head: big round cranium, a lower face ball, hooded neon eyes and the grin
	---------------------------------------------------------------------------------------
	local head = ball("Head", HEAD_R * 2, HEAD_CF, "Head", { CastShadow = true })
	head:SetAttribute("BoneName", "Head")
	head:SetAttribute("Pivot", CFrame.new(NECK_TOP))
	ball("Crown", 2.0, HEAD_CF * CFrame.new(0, 0.42, 0.12), "Head", { CastShadow = true }) -- taller skull
	ball("Face", FACE_R * 2, HEAD_CF * CFrame.new(FACE_C), "Head", { CastShadow = true })
	for _, s in { -1, 1 } do
		local x = s * 0.44
		-- eyes sit in black pits (Neon black never catches light)
		ball(if s < 0 then "SocketL" else "SocketR", 0.7, HEAD_CF * CFrame.new(x, 0.14, -0.96), "Head", {
			Color = Color3.new(0, 0, 0),
			Material = Enum.Material.Neon,
		})
		local eye = ball(if s < 0 then "EyeL" else "EyeR", 0.44, HEAD_CF * CFrame.new(x, 0.14, -1.1), "Head", {
			Color = EYE,
			Material = Enum.Material.Neon,
		})
		eyeLight(eye)
	end

	-- The grin wraps the face ball well past the cheeks. Gum lines in head space; the corners curl up.
	local function gumTop(x: number)
		return -0.6 + 0.3 * x ^ 2
	end
	local function gumBottom(x: number)
		return -1.0 + 0.38 * x ^ 2
	end
	local function gumRoll(x: number)
		return math.atan(0.68 * x) -- the lips tilt with the curve so the corners sweep up
	end
	-- point on the face ball's surface at (x, y) in head space, and the outward yaw there
	local function onFace(x: number, y: number)
		local fy = y - FACE_C.Y
		local zf = -math.sqrt(math.max(FACE_R ^ 2 - fy ^ 2 - x ^ 2, 0.04))
		return FACE_C.Z + zf, math.atan2(-x, -zf)
	end
	-- the black gash behind the teeth (Neon black never catches light: a hole), hugging the face
	for _, x in { -0.8, -0.4, 0, 0.4, 0.8 } do
		local yc = (gumTop(x) + gumBottom(x)) / 2
		local z, yaw = onFace(x, yc)
		local gash = add(
			"Mouth",
			Vector3.new(0.46, gumTop(x) - gumBottom(x) + 0.06, 0.16),
			HEAD_CF * CFrame.new(x, yc, z + 0.02) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, gumRoll(x)),
			"Head",
			{ Color = Color3.new(0, 0, 0), Material = Enum.Material.Neon }
		)
		gash:SetAttribute("Row", "Mouth")
	end
	-- teeth: wedges turned so their taper shows from the front; uneven lengths, longer canines
	local function tooth(x: number, gumY: number, len: number, pointUp: boolean, mirror: boolean)
		local z, yaw = onFace(x, gumY)
		local cf = HEAD_CF
			* CFrame.new(x, gumY, z + 0.04)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(0, 0, gumRoll(x) * 0.6 + rng:NextNumber(-0.1, 0.1))
			* CFrame.new(0, if pointUp then len / 2 else -len / 2, 0)
			* CFrame.Angles(0, math.rad(90) + (if mirror then math.pi else 0), 0)
			* (if pointUp then CFrame.new() else CFrame.Angles(math.pi, 0, 0))
		local p = add("Tooth", Vector3.new(0.12, len, 0.16), cf, "Head", {
			Wedge = true,
			Color = TOOTH,
			Reflectance = 0.08,
		})
		p:SetAttribute("Row", if pointUp then "Bottom" else "Top")
		return p
	end
	for i = 1, 11 do
		local x = -1.0 + (i - 1) * 0.2
		local canine = i == 3 or i == 9
		local len = if canine then 0.66 else rng:NextNumber(0.32, 0.5)
		tooth(x, gumTop(x), len, false, i % 2 == 0)
	end
	for i = 1, 10 do
		local x = -0.9 + (i - 1) * 0.2
		local canine = i == 1 or i == 10
		local len = if canine then 0.46 else rng:NextNumber(0.24, 0.38)
		tooth(x, gumBottom(x), len, true, i % 2 == 1)
	end

	---------------------------------------------------------------------------------------
	-- arms: long and thin; each bone pivots at its shoulder. The left hand lies flat on the
	-- counter (Resting = true tells the client to keep it still), the right hangs to the floor.
	---------------------------------------------------------------------------------------
	local function hand(name: string, bone: string, palmCf: CFrame, s: number, flat: boolean)
		add(name .. "Hand", Vector3.new(0.5, 0.85, 0.26), palmCf, bone)
		for i, fx in { -0.18, -0.06, 0.06, 0.18 } do
			local curl = if flat then 3 else 6 + (i % 2) * 5
			local fingerCf = palmCf * CFrame.new(fx, -0.68, 0) * CFrame.Angles(math.rad(-curl), 0, math.rad(fx * 40))
			add(name .. "Finger", Vector3.new(0.11, 0.55, 0.11), fingerCf, bone)
			add(
				name .. "Claw",
				Vector3.new(0.09, 0.34, 0.09),
				fingerCf * CFrame.new(0, -0.42, -0.02) * CFrame.Angles(math.rad(if flat then -10 else -16), 0, 0),
				bone,
				{ Color = CLAW }
			)
		end
		add(
			name .. "Thumb",
			Vector3.new(0.11, 0.46, 0.11),
			palmCf * CFrame.new(-s * 0.3, -0.35, -0.02) * CFrame.Angles(0, 0, -s * math.rad(38)),
			bone
		)
	end
	for _, side in { "L", "R" } do
		local name = if side == "L" then "Left" else "Right"
		local bone = "Arm" .. side
		local resting = side == "L"
		local upper = limb(name .. "UpperArm", SHOULDER[side], ELBOW[side], 0.42, bone, { CastShadow = true })
		upper:SetAttribute("BoneName", bone)
		upper:SetAttribute("Pivot", CFrame.new(SHOULDER[side]))
		upper:SetAttribute("Resting", resting)
		ball(name .. "Elbow", 0.48, CFrame.new(ELBOW[side]), bone)
		limb(name .. "LowerArm", ELBOW[side], WRIST[side], 0.34, bone)
		ball(name .. "Wrist", 0.36, CFrame.new(WRIST[side]), bone)
		local s = if side == "L" then -1 else 1
		local palmCf = if resting
			then PALM_L
			else CFrame.new(WRIST[side] + Vector3.new(s * 0.04, -0.5, -0.05)) * CFrame.Angles(math.rad(-8), 0, 0)
		hand(name, bone, palmCf, s, resting)
	end

	---------------------------------------------------------------------------------------
	-- place everything and record the rest pose
	---------------------------------------------------------------------------------------
	local rootInverse = ROOT_CF:Inverse()
	for part, cf in placed do
		part.CFrame = world * cf
		if part ~= root then
			part:SetAttribute("Rest", rootInverse * cf)
		end
	end
	model.PrimaryPart = root
	nameTag(head)
	return root, head
end

-- Build him under `parent`, standing on `position` and facing `facing` (defaults: Layout.Shopkeeper).
function ShopkeeperService.build(parent: Instance, position: Vector3?, facing: Vector3?): Model
	local at = position or DEFAULT_POSITION
	local toward = facing or DEFAULT_FACING
	local world = CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z))

	local model = Instance.new("Model")
	model.Name = "Shopkeeper"
	model:SetAttribute("EntityName", "Teeth")
	model:SetAttribute("Unstunnable", true)
	model:SetAttribute("Lasered", false)
	model:SetAttribute("Stunned", false)
	CollectionService:AddTag(model, "Entity")

	local root = assemble(model, world)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Teeth"
	prompt.ActionText = "Talk"
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute("Panel", "Shopkeeper")
	prompt.Parent = root

	model.Parent = parent
	return model
end

function ShopkeeperService.start(lobby: Instance)
	local position, facing = DEFAULT_POSITION, DEFAULT_FACING
	local builders = ServerStorage:FindFirstChild("Builders")
	local layoutModule = builders and builders:FindFirstChild("Layout")
	if layoutModule then
		local ok, layout = pcall(require, layoutModule)
		if ok and layout.Shopkeeper then
			position, facing = layout.Shopkeeper.position, layout.Shopkeeper.facing
		end
	end
	ShopkeeperService.build(lobby, position, facing)
end

return ShopkeeperService
