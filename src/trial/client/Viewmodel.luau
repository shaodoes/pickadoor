--[[
	Viewmodel: a first-person forearm and hand built from parts on the client (the door room's
	"reach for the handle" shot). Skin from the character's BodyColors, a dark sleeve.

	  local arm = Viewmodel.new(character, side)   -- side 1 = right arm, -1 = left arm
	  arm.pose(shoulder: Vector3, wrist: Vector3, curl: number, palmUp: Vector3?)
	      sleeve from `shoulder` to `wrist` (world space), the hand beyond the wrist; curl 0 = open
	      hand, 1 = fingers closed round a bar
	  arm.show(visible), arm.destroy()
	The parts are anchored, non-colliding and parented to the camera, so only this client sees them.
]]
local Viewmodel = {}

local SLEEVE = Color3.fromRGB(38, 40, 48)

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Viewmodel.new(character: Model?, side: number)
	local skin = Color3.fromRGB(204, 160, 128)
	local colors = character and character:FindFirstChildOfClass("BodyColors")
	if colors then
		skin = if side > 0 then colors.RightArmColor3 else colors.LeftArmColor3
	else
		local hand = character and character:FindFirstChild(if side > 0 then "RightHand" else "LeftHand")
		if hand and hand:IsA("BasePart") then
			skin = hand.Color
		end
	end

	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local sleeve = part("Sleeve", Vector3.new(1.7, 0.34, 0.34), SLEEVE, Enum.Material.Fabric, model)
	sleeve.Shape = Enum.PartType.Cylinder
	local cuff =
		part("Cuff", Vector3.new(0.16, 0.48, 0.48), SLEEVE:Lerp(Color3.new(), 0.3), Enum.Material.Fabric, model)
	cuff.Shape = Enum.PartType.Cylinder
	local wristPart = part("Wrist", Vector3.new(0.28, 0.28, 0.28), skin, Enum.Material.SmoothPlastic, model)
	wristPart.Shape = Enum.PartType.Ball
	local palm = part("Palm", Vector3.new(0.38, 0.16, 0.42), skin, Enum.Material.SmoothPlastic, model)
	local fingers = part("Fingers", Vector3.new(0.36, 0.13, 0.34), skin, Enum.Material.SmoothPlastic, model)
	local tips = part("Tips", Vector3.new(0.34, 0.12, 0.16), skin, Enum.Material.SmoothPlastic, model)
	local thumb = part("Thumb", Vector3.new(0.11, 0.11, 0.3), skin, Enum.Material.SmoothPlastic, model)
	model.Parent = workspace.CurrentCamera

	local arm = {}

	-- `palmUp` is the direction the back of the hand faces (default: world up)
	function arm.pose(shoulder: Vector3, wrist: Vector3, curl: number, palmUp: Vector3?)
		local dir = wrist - shoulder
		if dir.Magnitude < 1e-3 then
			return
		end
		local forward = dir.Unit
		local up = palmUp or Vector3.yAxis
		if math.abs(forward:Dot(up)) > 0.98 then
			up = Vector3.zAxis
		end
		-- the sleeve ends a little short of the wrist; cylinders run along their X axis
		local sleeveEnd = wrist - forward * 0.12
		local length = math.max(0.4, (sleeveEnd - shoulder).Magnitude)
		sleeve.Size = Vector3.new(length, 0.34, 0.34)
		local along = CFrame.lookAt((shoulder + sleeveEnd) / 2, sleeveEnd, up) * CFrame.Angles(0, math.rad(90), 0)
		sleeve.CFrame = along
		cuff.CFrame = CFrame.lookAt(sleeveEnd, sleeveEnd + forward, up) * CFrame.Angles(0, math.rad(90), 0)
		wristPart.CFrame = CFrame.new(wrist)
		-- the hand: palm forward of the wrist, fingers bending down round the bar as `curl` rises
		local hand = CFrame.lookAt(wrist, wrist + forward, up)
		palm.CFrame = hand * CFrame.new(0, 0, -0.24)
		local knuckle = hand * CFrame.new(0, 0, -0.45)
		local bend = math.rad(80) * math.clamp(curl, 0, 1)
		fingers.CFrame = knuckle * CFrame.Angles(-bend, 0, 0) * CFrame.new(0, 0, -0.16)
		local tipJoint = knuckle * CFrame.Angles(-bend, 0, 0) * CFrame.new(0, 0, -0.32)
		tips.CFrame = tipJoint * CFrame.Angles(-bend * 0.9, 0, 0) * CFrame.new(0, 0, -0.07)
		thumb.CFrame = hand
			* CFrame.new(-side * 0.2 * (if curl > 0.5 then 0.6 else 1), -0.06, -0.22)
			* CFrame.Angles(0, side * math.rad(25), 0)
			* CFrame.Angles(-bend * 0.5, 0, 0)
	end

	function arm.show(visible: boolean)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end

	function arm.destroy()
		model:Destroy()
	end

	return arm
end

return Viewmodel
