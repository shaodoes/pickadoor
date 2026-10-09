--[[
	Locks: the lockpick demo. A locked, iron-banded strongbox against the Workshop's west wall, just
	outside the storage cage, with a "LOCKED" board and a note sending people to the shop.

	Contract with ItemService (which puts the "Pick lock" ProximityPrompt on it and handles the loot):
	  * the Model is tagged `Lockable`, attributes LockId (string), Reward (Keys, once per player)
	  * part `Lid`:  attribute `Hinge` = CFrame in the Lid's OWN space whose X axis is the hinge line;
	    a positive rotation about it opens; `OpenAngle` (degrees)
	  * part `Lock`: the padlock (prompt host, CanQuery); same Hinge / OpenAngle so it swings aside
	  * PointLight named `GlintLight` anywhere inside: lit while the chest is open
	Swinging parts carry their details as unanchored, massless parts WeldConstraint'ed to them, so a
	CFrame tween on the anchored Lid / Lock drags the details along.

	Public API: Locks.build(root: Instance) -> Model ("Locks" under root).
]]
local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local C = Kit.C
local box = Kit.box
local DETAIL = Kit.DETAIL

local PLANKS = Enum.Material.WoodPlanks
local METAL = Enum.Material.Metal

local R = Layout.Rooms.Workshop
local FLOOR = R.y + 0.2 -- the Workshop's plank floor sits 0.2 over the slab
local LINING = 0.65 -- the Workshop's board lining stands this far off the concrete (see Workshop.luau IN)

local DARK_WOOD = Color3.fromRGB(74, 50, 34)
local LID_WOOD = Color3.fromRGB(86, 58, 38)
local IRON = Color3.fromRGB(44, 42, 40)
local BRASS = C.brass
local VELVET = Color3.fromRGB(34, 22, 20)

-- chest dimensions (local: X across the width, Z front(-)/back(+), Y up)
local W, D, H = 1.9, 1.25, 0.8
local LID_T = 0.2

-- unanchored detail welded to a swinging part
local SWING_DETAIL = {
	Anchored = false,
	Massless = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}
local function weldTo(part: BasePart, host: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = host
	weld.Part1 = part
	weld.Parent = part
	return part
end

local Locks = {}

local function buildChest(parent: Instance, base: CFrame, lockId: string, reward: number): Model
	local model = Kit.folder(parent, "Chest")
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	-- body with corner brackets and two iron straps running down the front and back
	local body = box(model, "Body", Vector3.new(W, H, D), at(0, H / 2, 0), DARK_WOOD, PLANKS)
	model.PrimaryPart = body
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(model, "Bracket", Vector3.new(0.1, H, 0.1), at(sx * W / 2, H / 2, sz * D / 2), IRON, METAL, DETAIL)
		end
		local x = sx * W * 0.28
		for _, sz in { -1, 1 } do
			box(model, "Strap", Vector3.new(0.16, H, 0.04), at(x, H / 2, sz * (D / 2 + 0.02)), IRON, METAL, DETAIL)
		end
	end
	box(model, "BottomBand", Vector3.new(W + 0.06, 0.1, D + 0.06), at(0, 0.05, 0), IRON, METAL, DETAIL)

	-- the inside: a velvet floor, three brass keys and a glint that lights up when the lid lifts
	box(model, "Inner", Vector3.new(W - 0.16, 0.04, D - 0.16), at(0, H + 0.02, 0), VELVET, Enum.Material.Fabric, DETAIL)
	for _, spec in { { -0.45, -0.2, 0.4 }, { 0.1, 0.18, -0.9 }, { 0.5, -0.12, 1.9 } } do
		local kcf = at(spec[1], H + 0.07, spec[2]) * CFrame.Angles(0, spec[3], 0)
		box(model, "KeyShaft", Vector3.new(0.34, 0.04, 0.05), kcf, BRASS, METAL, DETAIL)
		box(model, "KeyBit", Vector3.new(0.06, 0.04, 0.1), kcf * CFrame.new(0.12, 0, 0.04), BRASS, METAL, DETAIL)
		local bow = box(
			model,
			"KeyBow",
			Vector3.new(0.04, 0.17, 0.17),
			kcf * CFrame.new(-0.2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
			BRASS,
			METAL,
			DETAIL
		)
		bow.Shape = Enum.PartType.Cylinder
	end
	local glint = box(
		model,
		"Glint",
		Vector3.new(0.14, 0.14, 0.14),
		at(0.05, H + 0.12, 0),
		Color3.fromRGB(255, 214, 120),
		Enum.Material.Neon,
		DETAIL
	)
	glint.Shape = Enum.PartType.Ball
	glint.Transparency = 0.35
	local light = Instance.new("PointLight")
	light.Name = "GlintLight"
	light.Color = Color3.fromRGB(255, 200, 110)
	light.Range = 5
	light.Brightness = 1.4
	light.Shadows = false
	light.Enabled = false
	light.Parent = glint

	-- lid: a plank slab with a raised cap, two straps over it and a hasp strap hanging down the front
	local lid = box(model, "Lid", Vector3.new(W + 0.08, LID_T, D + 0.08), at(0, H + LID_T / 2, 0), LID_WOOD, PLANKS)
	weldTo(
		box(
			model,
			"LidCap",
			Vector3.new(W - 0.3, 0.14, D - 0.3),
			at(0, H + LID_T + 0.07, 0),
			LID_WOOD,
			PLANKS,
			SWING_DETAIL
		),
		lid
	)
	for _, sx in { -1, 1 } do
		local x = sx * W * 0.28
		weldTo(
			box(
				model,
				"LidStrap",
				Vector3.new(0.16, 0.04, D + 0.14),
				at(x, H + LID_T + 0.02, 0),
				IRON,
				METAL,
				SWING_DETAIL
			),
			lid
		)
		for _, sz in { -1, 1 } do
			weldTo(
				box(
					model,
					"LidStrapLip",
					Vector3.new(0.16, LID_T + 0.04, 0.04),
					at(x, H + LID_T / 2, sz * (D / 2 + 0.06)),
					IRON,
					METAL,
					SWING_DETAIL
				),
				lid
			)
		end
	end
	local front = -D / 2
	weldTo(
		box(model, "Hasp", Vector3.new(0.3, 0.46, 0.04), at(0, H - 0.08, front - 0.07), IRON, METAL, SWING_DETAIL),
		lid
	)
	-- hinge line along the back-top edge of the body (local X), stored in the lid's own space
	local lidHinge = base * CFrame.new(0, H, D / 2)
	lid:SetAttribute("Hinge", lid.CFrame:ToObjectSpace(lidHinge))
	lid:SetAttribute("OpenAngle", 105)

	-- staple on the body front that the hasp drops over, and the padlock hanging through it
	local stapleY = H - 0.22
	for _, sx in { -1, 1 } do
		box(model, "Staple", Vector3.new(0.04, 0.14, 0.12), at(sx * 0.07, stapleY, front - 0.1), IRON, METAL, DETAIL)
	end
	box(model, "StapleBar", Vector3.new(0.18, 0.04, 0.04), at(0, stapleY + 0.05, front - 0.15), IRON, METAL, DETAIL)

	local lockZ = front - 0.15
	local lock = box(
		model,
		"Lock",
		Vector3.new(0.34, 0.3, 0.14),
		at(0, stapleY - 0.34, lockZ),
		Color3.fromRGB(56, 52, 48),
		METAL,
		{ CanCollide = false }
	)
	for _, sx in { -1, 1 } do
		weldTo(
			box(
				model,
				"Shackle",
				Vector3.new(0.04, 0.26, 0.04),
				at(sx * 0.1, stapleY - 0.08, lockZ),
				IRON,
				METAL,
				SWING_DETAIL
			),
			lock
		)
	end
	weldTo(
		box(model, "ShackleTop", Vector3.new(0.24, 0.04, 0.04), at(0, stapleY + 0.05, lockZ), IRON, METAL, SWING_DETAIL),
		lock
	)
	weldTo(
		box(
			model,
			"LockPlate",
			Vector3.new(0.26, 0.22, 0.02),
			at(0, stapleY - 0.34, lockZ - 0.075),
			BRASS,
			METAL,
			SWING_DETAIL
		),
		lock
	)
	weldTo(
		box(
			model,
			"Keyhole",
			Vector3.new(0.05, 0.09, 0.02),
			at(0, stapleY - 0.36, lockZ - 0.09),
			Color3.fromRGB(18, 16, 14),
			Enum.Material.SmoothPlastic,
			SWING_DETAIL
		),
		lock
	)
	-- the padlock swings outward about the staple bar when picked
	local lockHinge = base * CFrame.new(0, stapleY + 0.05, lockZ)
	lock:SetAttribute("Hinge", lock.CFrame:ToObjectSpace(lockHinge))
	lock:SetAttribute("OpenAngle", 35)

	model:SetAttribute("LockId", lockId)
	model:SetAttribute("Reward", reward)
	model:SetAttribute("Locked", true)
	model:SetAttribute("PromptName", "Locked chest")
	CollectionService:AddTag(model, "Lockable")
	return model
end

function Locks.build(root: Instance): Model
	local model = Kit.folder(root, "Locks")

	-- against the Workshop's west wall between the storage cage (z 11.8) and the bucket (z 9); front faces east
	local cx, cz = R.x0 + LINING + 0.08 + D / 2, 10.4
	local base = CFrame.lookAt(Vector3.new(cx, FLOOR, cz), Vector3.new(cx + 10, FLOOR, cz))
	buildChest(model, base, "workshop_chest", 25)

	-- "LOCKED" board and a note on the boards above it
	local wallX = R.x0 + LINING + 0.08
	local board = box(
		model,
		"LockedSign",
		Vector3.new(0.06, 0.6, 1.7),
		Vector3.new(wallX, FLOOR + 2.35, cz - 0.3),
		Color3.fromRGB(200, 184, 150),
		Enum.Material.Wood,
		DETAIL
	)
	Kit.surfaceText(board, Enum.NormalId.Right, "LOCKED", Enum.Font.SpecialElite, Color3.fromRGB(150, 30, 24))
	local note = box(
		model,
		"Note",
		Vector3.new(0.03, 1.2, 1.0),
		CFrame.new(wallX, FLOOR + 2.4, cz + 1.15) * CFrame.Angles(math.rad(4), 0, 0),
		Color3.fromRGB(224, 214, 188),
		nil,
		DETAIL
	)
	Kit.surfaceText(
		note,
		Enum.NormalId.Right,
		"lockpicks\nsold at\nthe shop",
		Enum.Font.SpecialElite,
		Color3.fromRGB(60, 40, 30)
	)
	return model
end

return Locks
