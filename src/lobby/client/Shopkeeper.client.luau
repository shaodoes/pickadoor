--[[
	The Shopkeeper ("Teeth") on the client. ShopkeeperService builds him from anchored parts and
	stores the rest pose as attributes (Rest / Bone / BoneName / Pivot, see the service); here the
	parts are re-posed every frame (a local, visual-only change) so he
	  * breathes, sways and lets his arms drift while idle
	  * turns his head to follow you when you're near
	  * twitches now and then: eyes flicker or go out, the grin widens, the head snaps round
	  * reacts to the laser pointer (model attribute Lasered): hiss, flaring eyes, teeth flash
	and the Talk prompt opens his dialogue tree (Dialogue / DialogueTrees in Shared).
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(150, 110, 230)
local LOOK_RANGE = 24 -- studs: he follows you with his head inside this
local NEAR_RANGE = 5 -- studs: his eyes brighten when you're this close
local TRACK_RATE = 4 -- head smoothing (per second); doubled for a snap
local FAR_UPDATE = 70 -- beyond this camera distance he's posed at a low rate

local lobby = workspace:WaitForChild("Lobby")
local model = lobby:WaitForChild("Shopkeeper", 30)
if not model then
	warn("[Shopkeeper] no shopkeeper in the lobby")
	return
end
local root = model:WaitForChild("HumanoidRootPart") :: BasePart
local head = model:WaitForChild("Head") :: BasePart
local prompt = root:WaitForChild("ProximityPrompt") :: ProximityPrompt
model:WaitForChild("RightUpperArm")

-- Modules written alongside this one; absent until the place is synced, so never hard-require them.
local function tryRequire(name: string)
	local module = Shared:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn("[Shopkeeper] " .. name .. " failed to load: " .. tostring(result))
		return nil
	end
	return result
end

------------------------------------------------------------------------------------------
-- Rig: bones and the parts that follow them
------------------------------------------------------------------------------------------
type Bone = { part: BasePart, parent: string?, pivotLocal: CFrame, world: CFrame, resting: boolean }
local BONE_ORDER = { "Root", "Torso", "Head", "ArmL", "ArmR" }
local bones: { [string]: Bone } = {
	Root = { part = root, parent = nil, pivotLocal = CFrame.new(), world = root.CFrame, resting = false },
}
local pivots: { [string]: CFrame } = { Root = CFrame.new() } -- bone pivots relative to the root
for _, part in model:GetDescendants() do
	local boneName = part:IsA("BasePart") and part:GetAttribute("BoneName")
	if boneName then
		pivots[boneName] = part:GetAttribute("Pivot") or part:GetAttribute("Rest")
	end
end
for _, part in model:GetDescendants() do
	local boneName = part:IsA("BasePart") and part:GetAttribute("BoneName")
	if boneName then
		local parent = part:GetAttribute("Bone") or "Root"
		if parent == boneName then
			parent = if boneName == "Head" or boneName:sub(1, 3) == "Arm" then "Torso" else "Root"
		end
		bones[boneName] = {
			part = part,
			parent = parent,
			pivotLocal = pivots[parent]:Inverse() * pivots[boneName],
			world = root.CFrame,
			resting = part:GetAttribute("Resting") == true,
		}
	end
end
for _, name in BONE_ORDER do
	if not bones[name] then
		warn("[Shopkeeper] rig is missing bone " .. name)
		return
	end
end

type Entry = { part: BasePart, bone: string, rest: CFrame, row: string?, size: Vector3, material: Enum.Material }
local entries: { Entry } = {}
local teeth: { Entry } = {}
local eyes: { BasePart } = {}
local eyeLights: { PointLight } = {}
for _, part in model:GetDescendants() do
	if part:IsA("BasePart") and part ~= root and part:GetAttribute("Rest") then
		local bone = part:GetAttribute("Bone") or "Root"
		if not bones[bone] then
			bone = "Root"
		end
		local entry: Entry = {
			part = part,
			bone = bone,
			rest = pivots[bone]:Inverse() * part:GetAttribute("Rest"),
			row = part:GetAttribute("Row"),
			size = part.Size,
			material = part.Material,
		}
		table.insert(entries, entry)
		if entry.row then
			table.insert(teeth, entry)
		end
		if part.Name == "EyeL" or part.Name == "EyeR" then
			table.insert(eyes, part)
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				table.insert(eyeLights, light)
			end
		end
	end
end
local baseCF = root.CFrame
local eyeColor = if #eyes > 0 then eyes[1].Color else Color3.new(1, 1, 1)
local eyeSize = if #eyes > 0 then eyes[1].Size else Vector3.one
local lightBase = if #eyeLights > 0 then eyeLights[1].Brightness else 1
-- his neutral gaze is stooped; tracking pitch is relative to it
local headRest = pivots.Head:Inverse() * head:GetAttribute("Rest")
local restPitch = math.asin(math.clamp(headRest.LookVector.Y, -1, 1))

------------------------------------------------------------------------------------------
-- Animation state
------------------------------------------------------------------------------------------
local yaw, pitch = 0, 0
local snapUntil = 0 -- head tracks twice as fast until then
local jerkUntil, jerkYaw = 0, 0 -- head wrenched aside (laser)
local grin, grinTarget = 0, 0 -- 0 = resting grin, 1 = widened
local lastGrin = -1
local flare = 0 -- eye flare after a laser hit, decays
local armRaise = 0 -- arms lift after a laser hit, decays
local near = 0 -- 0..1 as you come within NEAR_RANGE
local eyesOn = true
local flicker = 0 -- 0..1 transparency stutter
local lasered = false -- session flag for the dialogue context
local talking = false
local rng = Random.new()

local function applyEyes()
	local glow = (1 + 0.4 * near + 2 * flare) * (1 - flicker)
	for _, eye in eyes do
		eye.Transparency = if eyesOn then flicker * 0.8 else 1
		eye.Color = eyeColor:Lerp(Color3.new(1, 1, 1), flare)
		eye.Size = eyeSize * (1 + 0.6 * flare)
	end
	for _, light in eyeLights do
		light.Brightness = if eyesOn then lightBase * glow else 0
	end
end

local function nearestHead(): Vector3?
	local character = player.Character
	local myHead = character and character:FindFirstChild("Head")
	if myHead and (myHead.Position - head.Position).Magnitude < LOOK_RANGE then
		return myHead.Position
	end
	return nil
end

local camera = workspace.CurrentCamera
local farAccumulator = 0
RunService.RenderStepped:Connect(function(dt)
	-- far away: pose at ~10 Hz, it's a silhouette at that distance
	local camDistance = (camera.CFrame.Position - root.Position).Magnitude
	if camDistance > FAR_UPDATE then
		farAccumulator += dt
		if farAccumulator < 0.1 then
			return
		end
		dt = farAccumulator
		farAccumulator = 0
	end
	local now = os.clock()
	local t = now

	-- decays
	flare = math.max(flare - dt / 1.2, 0)
	armRaise = math.max(armRaise - dt / 1.6, 0)
	grin += (grinTarget - grin) * math.min(dt * (if grinTarget > grin then 14 else 4), 1)
	if math.abs(grin - grinTarget) < 0.005 then
		grin = grinTarget -- settle exactly so the teeth stop being resized every frame
	end

	-- idle: a slow sway at the hips, breathing at the waist, arms drifting
	local sway = math.rad(2) * math.sin(t * 2 * math.pi * 0.1)
	local breath = math.sin(t * 2 * math.pi * 0.25)
	bones.Root.world = baseCF * CFrame.Angles(0, sway, 0)
	bones.Torso.world = bones.Root.world
		* bones.Torso.pivotLocal
		* CFrame.new(0, 0.08 * breath, 0)
		* CFrame.Angles(math.rad(1.2) * breath, 0, 0)

	-- head tracking toward your head, in the neck pivot's frame
	local target = nearestHead()
	local targetYaw, targetPitch = 0, 0
	local headPivot = bones.Torso.world * bones.Head.pivotLocal
	if target then
		local rel = headPivot:PointToObjectSpace(target)
		targetYaw = math.clamp(math.atan2(-rel.X, -rel.Z), math.rad(-70), math.rad(70))
		local elevation = math.atan2(rel.Y, Vector2.new(rel.X, rel.Z).Magnitude)
		targetPitch = math.clamp(elevation - restPitch, math.rad(-30), math.rad(28))
	end
	if now < jerkUntil then
		targetYaw = math.clamp(targetYaw + jerkYaw, math.rad(-80), math.rad(80))
	end
	local rate = if now < snapUntil or now < jerkUntil then TRACK_RATE * 2 else TRACK_RATE
	local alpha = math.min(dt * rate, 1)
	yaw += (targetYaw - yaw) * alpha
	pitch += (targetPitch - pitch) * alpha
	bones.Head.world = headPivot * CFrame.Angles(pitch, yaw, 0)

	-- arms: a lazy drift from the shoulder; the resting hand stays on the counter
	for i, name in { "ArmL", "ArmR" } do
		local bone = bones[name]
		local amount = if bone.resting then 0.12 else 1
		local drift = CFrame.Angles(
			(math.rad(1.6) * math.sin(t * 2 * math.pi * 0.13 + i * 2.1) + math.rad(22) * armRaise) * amount,
			0,
			math.rad(1.3) * math.sin(t * 2 * math.pi * 0.09 + i * 1.3) * amount
		)
		bone.world = bones.Torso.world * bone.pivotLocal * drift
	end

	-- pose every part from its bone
	for _, entry in entries do
		entry.part.CFrame = bones[entry.bone].world * entry.rest
	end
	-- the grin: rows spread apart and the teeth lengthen out of the gums
	if grin ~= lastGrin then
		lastGrin = grin
		local spread = 0.14 * grin
		for _, entry in teeth do
			local part = entry.part
			if entry.row == "Mouth" then
				part.Size = Vector3.new(entry.size.X, entry.size.Y * (1 + 0.5 * grin), entry.size.Z)
			else
				local extra = entry.size.Y * 0.35 * grin
				local dir = if entry.row == "Top" then 1 else -1
				part.Size = Vector3.new(entry.size.X, entry.size.Y + extra, entry.size.Z)
				-- the point is always at the tooth's local +Y; shift so the gum end stays put
				part.CFrame = bones.Head.world
					* CFrame.new(0, dir * spread, 0)
					* entry.rest
					* CFrame.new(0, extra / 2, 0)
			end
		end
	elseif grin > 0 then
		local spread = 0.14 * grin
		for _, entry in teeth do
			if entry.row ~= "Mouth" then
				local extra = entry.size.Y * 0.35 * grin
				local dir = if entry.row == "Top" then 1 else -1
				entry.part.CFrame = bones.Head.world
					* CFrame.new(0, dir * spread, 0)
					* entry.rest
					* CFrame.new(0, extra / 2, 0)
			end
		end
	end

	-- eyes brighten a little as you come close
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart")
	local nearTarget = if myRoot and (myRoot.Position - root.Position).Magnitude < NEAR_RANGE then 1 else 0
	near += (nearTarget - near) * math.min(dt * 3, 1)
	applyEyes()
end)

------------------------------------------------------------------------------------------
-- Tics
------------------------------------------------------------------------------------------
local function tic()
	Sfx.at(head, "ShopkeeperTic", { volume = 0.2 })
end

-- eyes stutter like a failing bulb
local function flickerTic()
	tic()
	local stop = os.clock() + rng:NextNumber(0.4, 0.8)
	while os.clock() < stop do
		flicker = rng:NextNumber(0.2, 0.9)
		task.wait(rng:NextNumber(0.03, 0.08))
	end
	flicker = 0
end

local TICS = {
	flickerTic,
	-- both eyes go out, then come back
	function()
		eyesOn = false
		task.wait(rng:NextNumber(0.3, 1))
		eyesOn = true
		tic()
	end,
	-- the grin widens
	function()
		tic()
		grinTarget = 1
		task.wait(rng:NextNumber(0.8, 1.3))
		grinTarget = 0
	end,
	-- the head snaps toward you (only worth it when you're near; otherwise flicker)
	function()
		if nearestHead() then
			tic()
			snapUntil = os.clock() + 0.6
			-- a little overshoot: look away for a blink, then whip round
			jerkYaw = math.rad(rng:NextNumber(14, 24)) * (if rng:NextNumber() < 0.5 then -1 else 1)
			jerkUntil = os.clock() + 0.12
		else
			flickerTic()
		end
	end,
}
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(6, 20))
		if not talking then
			TICS[rng:NextInteger(1, #TICS)]()
		end
	end
end)

------------------------------------------------------------------------------------------
-- Laser reaction
------------------------------------------------------------------------------------------
local lastReact = 0
local function flashTeeth()
	for _, entry in teeth do
		if entry.row ~= "Mouth" then
			entry.part.Material = Enum.Material.Neon
		end
	end
	task.delay(0.15, function()
		for _, entry in teeth do
			if entry.row ~= "Mouth" then
				entry.part.Material = entry.material
			end
		end
	end)
end

local function localPlayerIsFiring(): boolean
	local ItemsClient = tryRequire("ItemsClient")
	if ItemsClient and type(ItemsClient.isFiring) == "function" then
		local ok, firing = pcall(ItemsClient.isFiring)
		return ok and firing == true
	end
	return false
end

local function reactToLaser()
	local now = os.clock()
	if now - lastReact < 1.5 then
		return
	end
	lastReact = now
	Sfx.at(head, "ShopkeeperHiss")
	flare = 1
	armRaise = 1
	eyesOn = true
	flashTeeth()
	-- wrench the head away from the beam, then stare back fast
	jerkYaw = math.rad(45) * (if yaw > 0 then -1 else 1)
	jerkUntil = now + 0.3
	snapUntil = now + 1.2
	grinTarget = 1
	task.delay(0.9, function()
		if os.clock() - lastReact >= 0.85 then
			grinTarget = 0
		end
	end)
	if localPlayerIsFiring() then
		lasered = true
		local Dialogue = tryRequire("Dialogue")
		if Dialogue and type(Dialogue.say) == "function" then
			pcall(Dialogue.say, "Teeth", "Don't.", ACCENT)
		end
	end
end
model:GetAttributeChangedSignal("Lasered"):Connect(function()
	if model:GetAttribute("Lasered") then
		reactToLaser()
	end
end)

------------------------------------------------------------------------------------------
-- Talking
------------------------------------------------------------------------------------------
local data = nil
Remotes.get("DataUpdated").OnClientEvent:Connect(function(snapshot)
	data = snapshot
end)

local function fireEvent(name: string)
	local event = script.Parent:FindFirstChild(name) or script.Parent:WaitForChild(name, 5)
	if event and event:IsA("BindableEvent") then
		event:Fire()
	else
		warn("[Shopkeeper] no " .. name .. " event to fire")
	end
end

local function talk()
	if talking then
		return
	end
	local Dialogue = tryRequire("Dialogue")
	local trees = tryRequire("DialogueTrees")
	local tree = trees and trees.Shopkeeper
	if not Dialogue or not tree then
		warn("[Shopkeeper] dialogue isn't available yet")
		return
	end
	if type(Dialogue.isOpen) == "function" and Dialogue.isOpen() then
		return
	end
	talking = true
	prompt.Enabled = false
	-- look at the customer while talking
	snapUntil = os.clock() + 0.8
	local ok, err = pcall(Dialogue.start, tree, {
		context = {
			trialsPlayed = data and data.TrialsPlayed or 0,
			keys = data and data.Keys or 0,
			currency = Config.CurrencyName,
			lasered = lasered,
		},
		onAction = function(action: string)
			if action == "openShop" then
				fireEvent("OpenShop")
			elseif action == "openLanterns" then
				fireEvent("OpenLanterns")
			end
		end,
		onClose = function()
			talking = false
			prompt.Enabled = true
			Remotes.get("Talked"):FireServer("Teeth") -- counts for the "Have a word with Teeth" challenge
		end,
		anchor = head,
	})
	if not ok then
		warn("[Shopkeeper] dialogue failed: " .. tostring(err))
		talking = false
		prompt.Enabled = true
	end
end

ProximityPromptService.PromptTriggered:Connect(function(triggered)
	if triggered == prompt then
		talk()
	end
end)

data = Remotes.get("GetData"):InvokeServer()
