--[[
	Client side of the items: the hotbar, item VFX/SFX, the laser pointer's input, and the generic
	Entity stun flare. Shared by the Lobby and Trial places (each has a thin Items.client.luau wrapper).

	  ItemsClient.start(gui, opts?) -> Frame   builds the hotbar into `gui` and wires everything up
	      opts.position / opts.anchorPoint    where the bar sits (default bottom-left)
	      opts._previewData                   Edit-mode preview: fake snapshot when there is no LocalPlayer
	  ItemsClient.isFiring() -> boolean       true while the local player holds the laser's trigger

	Hotbar: four ink tiles (one per Items.List entry), keys 1-4 or tap to use. Counts, a cooldown sweep
	that drains downward, an effect timer along the top, the laser's battery bar; greyed when empty.
	ItemEvent (server -> clients): "speed" / "heal" (character, duration), "unlock" (model), "stun"
	(entity), "laserHit" (position). The stun flare itself follows the `Stunned` attribute of any model
	tagged Entity (its Eye* Neon parts flash white/violet, then dim for the stun).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)
local Items = require(script.Parent.Items)
local Remotes = require(script.Parent.Remotes)
local Sfx = require(script.Parent.Sfx)
local UIKit = require(script.Parent.UIKit)

local ItemsClient = {}

local C, Face = UIKit.Colors, UIKit.Face
local player = Players.LocalPlayer -- nil in Edit-mode previews
local LASER_TAG = "LaserTool"
local TILE, GAP, ICON = 56, 8, 30
local BATTERY_MAX = Config.Items.LaserBatteryMax

local firing = false
function ItemsClient.isFiring(): boolean
	return firing
end

export type StartOptions = {
	position: UDim2?,
	anchorPoint: Vector2?,
	_previewData: any?,
}

type Slot = {
	def: Items.ItemDef,
	index: number,
	button: TextButton,
	face: Frame,
	stroke: UIStroke,
	iconHolder: Frame,
	badge: TextLabel,
	cooldown: Frame,
	cooldownText: TextLabel,
	active: Frame,
	batteryTrack: Frame?,
	batteryFill: Frame?,
	enabled: boolean?,
	readyAt: number,
}

local gui: ScreenGui
local data: any = nil -- latest profile snapshot (Inventory, LaserUnlocked, LaserBattery)
local slots: { Slot } = {}
local slotById: { [string]: Slot } = {}
local laserEquipped = false

local function tween(inst: Instance, info: TweenInfo, goal)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function isNear(position: Vector3, maxDistance: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= maxDistance
end

local function localCharacter(): Model?
	return player and player.Character
end

local function battery(): number
	local attr = player and player:GetAttribute("LaserBattery")
	if typeof(attr) == "number" then
		return attr
	end
	return data and tonumber(data.LaserBattery) or 0
end

------------------------------------------------------------------------------------------
-- Hotbar
------------------------------------------------------------------------------------------
local function setIcon(slot: Slot, color: Color3)
	for _, child in slot.iconHolder:GetChildren() do
		child:Destroy()
	end
	UIKit.icon(slot.def.icon, color, ICON).Parent = slot.iconHolder
end

local function pulse(slot: Slot)
	local scale = slot.button:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.18
		tween(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 })
	end
end

local function shake(slot: Slot)
	local face = slot.face
	face.Position = UDim2.fromOffset(-4, 0)
	tween(face, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Position = UDim2.new() })
end

-- The sweep shows the remaining fraction of the item's cooldown and drains down to nothing.
local function startCooldown(slot: Slot, seconds: number)
	if seconds <= 0 then
		return
	end
	slot.readyAt = os.clock() + seconds
	local total = math.max(slot.def.cooldown, seconds)
	slot.cooldown.Visible = true
	slot.cooldown.Size = UDim2.fromScale(1, math.clamp(seconds / total, 0, 1))
	slot.cooldownText.Visible = true
	local t = tween(slot.cooldown, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) })
	t.Completed:Connect(function()
		if os.clock() >= slot.readyAt - 0.05 then
			slot.cooldown.Visible = false
			slot.cooldownText.Visible = false
			pulse(slot)
		end
	end)
end

-- Thin bar along the top of the tile while the item's effect is running.
local function startActive(slot: Slot, seconds: number)
	slot.active.Visible = true
	slot.active.Size = UDim2.new(1, -20, 0, 3)
	local t = tween(slot.active, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromOffset(0, 3) })
	t.Completed:Connect(function()
		if slot.active.Size.X.Offset == 0 then
			slot.active.Visible = false
		end
	end)
end

local function refreshSlot(slot: Slot)
	local def = slot.def
	local inventory = data and data.Inventory or {}
	local count = tonumber(inventory[def.id]) or 0
	local unlocked = data ~= nil and data.LaserUnlocked == true
	local enabled = if def.kind == "consumable" then count > 0 else unlocked
	if slot.enabled ~= enabled then
		slot.enabled = enabled
		setIcon(slot, enabled and def.color or C.inkMuted)
	end
	if def.kind == "consumable" then
		slot.badge.Text = tostring(count)
		slot.badge.BackgroundColor3 = count > 0 and C.cream or C.inkSoft
		slot.badge.TextColor3 = count > 0 and C.ink or C.muted
	else
		slot.badge.Visible = false
	end
	if def.id == "laser_pointer" and slot.batteryTrack and slot.batteryFill then
		slot.batteryTrack.Visible = unlocked
		local level = math.clamp(battery() / BATTERY_MAX, 0, 1)
		slot.batteryFill.Size = UDim2.fromScale(level, 1)
		slot.batteryFill.BackgroundColor3 = C.accent:Lerp(C.green, math.clamp((level - 0.15) / 0.5, 0, 1))
		if laserEquipped then
			slot.stroke.Color = def.color
			slot.stroke.Thickness = 2.5
			slot.stroke.Transparency = 0.05
		else
			slot.stroke.Color = C.paper
			slot.stroke.Thickness = 1.5
			slot.stroke.Transparency = 0.86
		end
	end
end

local function refreshAll()
	for _, slot in slots do
		refreshSlot(slot)
	end
end

local busy = false
local function use(slot: Slot)
	if not player or busy then
		return
	end
	local def = slot.def
	if def.kind == "consumable" and slot.readyAt > os.clock() then
		shake(slot)
		Sfx.play("Error")
		return
	end
	if not slot.enabled then
		shake(slot)
		if def.kind == "consumable" then
			UIKit.toast(gui, string.format("No %s. The shop sells them.", def.name), "error")
		else
			UIKit.toast(gui, string.format("You don't own the %s yet. The shop sells it.", def.name), "error")
		end
		return
	end
	busy = true
	local ok, res = pcall(function()
		return Remotes.get("UseItem"):InvokeServer(def.id)
	end)
	busy = false
	if not ok or typeof(res) ~= "table" then
		return
	end
	if typeof(res.cooldown) == "number" and res.cooldown > 0 then
		startCooldown(slot, res.cooldown)
	end
	if res.ok then
		pulse(slot)
		if def.id == "laser_pointer" then
			UIKit.toast(gui, tostring(res.message))
		end
	else
		shake(slot)
		UIKit.toast(gui, tostring(res.message), if res.kind == "info" then nil else "error")
	end
end

local function buildSlot(bar: Frame, index: number, def: Items.ItemDef): Slot
	local button = UIKit.new("TextButton", {
		Name = "Slot_" .. def.id,
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		LayoutOrder = index,
		Size = UDim2.fromOffset(TILE, TILE),
		Parent = bar,
	})
	UIKit.shadow(button, 12, 3, 0.9)
	local face = UIKit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = C.ink,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = button,
	}, { UIKit.corner(12), UIKit.sheen(0.6) })
	local stroke = UIKit.stroke(C.paper, 1.5, 0.86)
	stroke.Parent = face
	local iconHolder = UIKit.new("Frame", {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(ICON, ICON),
		ZIndex = 2,
		Parent = face,
	})
	UIKit.new("TextLabel", {
		Name = "Key",
		Text = tostring(index),
		FontFace = Face.semi,
		TextSize = 12,
		TextColor3 = C.muted,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(7, 6),
		Size = UDim2.fromOffset(12, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Parent = face,
	})
	local badge = UIKit.new("TextLabel", {
		Name = "Count",
		Text = "0",
		FontFace = Face.bold,
		TextSize = 13,
		TextColor3 = C.ink,
		BackgroundColor3 = C.cream,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 5, 1, 5),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 5,
		Parent = face,
	}, { UIKit.corner(10), UIKit.stroke(C.ink, 1.5, 0.3) })
	local cooldown = UIKit.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = C.shadow,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Visible = false,
		ZIndex = 3,
		Parent = face,
	}, { UIKit.corner(12) })
	local cooldownText = UIKit.new("TextLabel", {
		Name = "CooldownText",
		Text = "",
		FontFace = Face.bold,
		TextSize = 18,
		TextColor3 = C.paper,
		TextStrokeTransparency = 0.5,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 4,
		Parent = face,
	})
	local active = UIKit.new("Frame", {
		Name = "Active",
		BackgroundColor3 = def.color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 2),
		Size = UDim2.new(1, -20, 0, 3),
		Visible = false,
		ZIndex = 4,
		Parent = face,
	}, { UIKit.corner(2) })

	local slot: Slot = {
		def = def,
		index = index,
		button = button,
		face = face,
		stroke = stroke,
		iconHolder = iconHolder,
		badge = badge,
		cooldown = cooldown,
		cooldownText = cooldownText,
		active = active,
		readyAt = 0,
	}
	if def.id == "laser_pointer" then
		slot.batteryTrack = UIKit.new("Frame", {
			Name = "Battery",
			BackgroundColor3 = C.inkSoft,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 9, 1, -9),
			Size = UDim2.new(1, -18, 0, 4),
			Visible = false,
			ZIndex = 4,
			Parent = face,
		}, { UIKit.corner(2) })
		slot.batteryFill = UIKit.new("Frame", {
			Name = "Fill",
			BackgroundColor3 = C.green,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = slot.batteryTrack,
		}, { UIKit.corner(2) })
	end
	setIcon(slot, C.inkMuted)
	UIKit.animate(button)
	button.Activated:Connect(function()
		use(slot)
	end)
	return slot
end

local function buildHotbar(opts: StartOptions): Frame
	local bar = UIKit.new("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		AnchorPoint = opts.anchorPoint or Vector2.new(0, 1),
		Position = opts.position or UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(#Items.List * TILE + (#Items.List - 1) * GAP, TILE),
		Parent = gui,
	}, {
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	UIKit.fit(bar)
	for i, def in Items.List do
		local slot = buildSlot(bar, i, def)
		slots[i] = slot
		slotById[def.id] = slot
	end
	return bar
end

-- The cooldown numbers only need a few updates a second, and only while a sweep is running.
local function runCooldownTexts()
	while true do
		local any = false
		for _, slot in slots do
			if slot.cooldown.Visible then
				any = true
				slot.cooldownText.Text = tostring(math.max(math.ceil(slot.readyAt - os.clock()), 1))
			end
		end
		task.wait(if any then 0.25 else 0.5)
	end
end

------------------------------------------------------------------------------------------
-- VFX helpers
------------------------------------------------------------------------------------------
local fxFolder: Folder? = nil
local function fxParent(): Folder
	if not fxFolder or not fxFolder.Parent then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "ItemsFX"
		fxFolder.Parent = workspace
	end
	return fxFolder :: Folder
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARKLE
	e.LightInfluence = 0
	e.Enabled = false
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

-- Speed streaks fly backward off the character's root while the pills work.
local function speedFx(character: Instance, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not isNear(root.Position, 120) then
		return
	end
	local def = Items.get("speed_pills")
	local color = def and def.color or Color3.new(1, 1, 1)
	local e = emitter(root, "SpeedStreaks", {
		Color = ColorSequence.new(color, Color3.new(1, 1, 1)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Squash = NumberSequence.new(-2.5),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.25, 0.4),
		Rate = 36,
		Speed = NumberRange.new(10, 16),
		SpreadAngle = Vector2.new(22, 22),
		EmissionDirection = Enum.NormalId.Back,
		Drag = 2,
		LightEmission = 0.8,
	})
	e.Enabled = true
	Sfx.at(root, "PillSwallow")
	local token = (e:GetAttribute("Token") or 0) + 1
	e:SetAttribute("Token", token)
	task.delay(duration, function()
		if e.Parent and e:GetAttribute("Token") == token then
			e.Enabled = false
		end
	end)

	if character == localCharacter() then
		local camera = workspace.CurrentCamera
		if camera then
			local base = camera.FieldOfView
			tween(
				camera,
				TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = base + 6 }
			)
			task.delay(duration - 0.6, function()
				if workspace.CurrentCamera == camera then
					tween(camera, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { FieldOfView = base })
				end
			end)
		end
		startActive(slotById.speed_pills, duration)
	end
end

-- Soft green motes rise off the character while bandaging.
local function healFx(character: Instance, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not isNear(root.Position, 120) then
		return
	end
	local e = emitter(root, "HealMotes", {
		Color = ColorSequence.new(Color3.fromRGB(150, 255, 170), Color3.fromRGB(240, 255, 240)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.0, 1.6),
		Rate = 14,
		Speed = NumberRange.new(1.2, 2.2),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 0.8, 0),
		LightEmission = 1,
	})
	e.Enabled = true
	Sfx.at(root, "BandageWrap")
	local token = (e:GetAttribute("Token") or 0) + 1
	e:SetAttribute("Token", token)
	task.delay(duration, function()
		if e.Parent and e:GetAttribute("Token") == token then
			e.Enabled = false
		end
	end)
	if character == localCharacter() then
		startActive(slotById.bandage, duration)
	end
end

-- One pooled attachment + emitter for sparkle bursts anywhere in the world.
local sparklePoint: Attachment? = nil
local function sparkleAt(position: Vector3)
	if not sparklePoint or not sparklePoint.Parent then
		sparklePoint = Instance.new("Attachment")
		sparklePoint.Name = "ItemsSparkle"
		sparklePoint.Parent = workspace.Terrain
		emitter(sparklePoint, "Sparkle", {
			Color = ColorSequence.new(Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 250, 230)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -6, 0),
			LightEmission = 1,
		})
	end
	local point = sparklePoint :: Attachment
	point.WorldPosition = position
	local e = point:FindFirstChild("Sparkle") :: ParticleEmitter
	e:Emit(28)
end

------------------------------------------------------------------------------------------
-- Entity stun flare: Eye* parts flash white/violet, then stay dim for the stun
------------------------------------------------------------------------------------------
local WHITE = Color3.fromRGB(255, 255, 255)
local VIOLET = Color3.fromRGB(190, 120, 255)
type EyeState =
	{ part: BasePart, color: Color3, transparency: number, lights: { { light: Light, brightness: number } } }
local eyeOriginals: { [Model]: { EyeState } } = {}
local flareTokens: { [Model]: number } = {}

local function collectEyes(entity: Model): { EyeState }
	local eyes = {}
	for _, d in entity:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 3) == "Eye" then
			local lights = {}
			for _, l in d:GetChildren() do
				if l:IsA("Light") then
					table.insert(lights, { light = l, brightness = l.Brightness })
				end
			end
			table.insert(eyes, { part = d, color = d.Color, transparency = d.Transparency, lights = lights })
		end
	end
	return eyes
end

local function restoreEyes(entity: Model)
	local eyes = eyeOriginals[entity]
	if not eyes then
		return
	end
	for _, e in eyes do
		if e.part.Parent then
			e.part.Color = e.color
			e.part.Transparency = e.transparency
			for _, l in e.lights do
				l.light.Brightness = l.brightness
			end
		end
	end
	eyeOriginals[entity] = nil
end

local function flare(entity: Model)
	if not isNear(entity:GetPivot().Position, 160) then
		return
	end
	local eyes = eyeOriginals[entity] or collectEyes(entity)
	if #eyes == 0 then
		return
	end
	eyeOriginals[entity] = eyes
	local token = (flareTokens[entity] or 0) + 1
	flareTokens[entity] = token
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.4 and flareTokens[entity] == token do
			for _, e in eyes do
				e.part.Color = if math.random() < 0.5 then WHITE else VIOLET
				e.part.Transparency = math.random() * 0.6
				for _, l in e.lights do
					l.light.Brightness = l.brightness * (2.4 + math.random() * 1.2)
				end
			end
			RunService.Heartbeat:Wait()
		end
		if flareTokens[entity] ~= token then
			return
		end
		for _, e in eyes do
			e.part.Color = e.color:Lerp(Color3.new(0, 0, 0), 0.65)
			e.part.Transparency = e.transparency
			for _, l in e.lights do
				l.light.Brightness = l.brightness * 0.3
			end
		end
		while entity.Parent and entity:GetAttribute("Stunned") == true and flareTokens[entity] == token do
			task.wait(0.1)
		end
		if flareTokens[entity] == token then
			restoreEyes(entity)
			flareTokens[entity] = nil
		end
	end)
end

local function watchEntity(entity: Instance)
	if not entity:IsA("Model") then
		return
	end
	entity:GetAttributeChangedSignal("Stunned"):Connect(function()
		if entity:GetAttribute("Stunned") == true then
			flare(entity)
		end
	end)
	if entity:GetAttribute("Stunned") == true then
		flare(entity)
	end
end

------------------------------------------------------------------------------------------
-- Laser pointer: the red dot + sparks at every firing beam's end, the hum, and local input
------------------------------------------------------------------------------------------
type Dot = { tool: Tool, part: Part, hum: Sound? }
local dots: { [Tool]: Dot } = {}

local function removeDot(tool: Instance)
	local dot = dots[tool :: Tool]
	if not dot then
		return
	end
	dots[tool :: Tool] = nil
	dot.part:Destroy()
	if dot.hum then
		dot.hum:Destroy()
	end
end

local function ensureDot(tool: Tool)
	if dots[tool] then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local part = Instance.new("Part")
	part.Name = "LaserDot"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.16, 0.16, 0.16)
	part.Color = Color3.fromRGB(255, 60, 60)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local sparks = emitter(part, "Sparks", {
		Color = ColorSequence.new(Color3.fromRGB(255, 90, 70), Color3.fromRGB(255, 220, 200)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.12, 0.3),
		Rate = 40,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	})
	sparks.Enabled = true
	part.Parent = fxParent()
	dots[tool] = { tool = tool, part = part, hum = Sfx.loop(handle, "LaserHum") }
end

local function watchLaserTool(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end
	local function update()
		if tool:GetAttribute("Firing") == true and tool:IsDescendantOf(workspace) then
			ensureDot(tool)
		else
			removeDot(tool)
		end
	end
	tool:GetAttributeChangedSignal("Firing"):Connect(update)
	tool.AncestryChanged:Connect(update)
	update()
end

-- Every frame: park each dot at its beam's far end (the replicated End attachment).
local function updateDots()
	for tool, dot in dots do
		local handle = tool:FindFirstChild("Handle")
		local beam = handle and handle:FindFirstChild("Beam")
		local endAtt = beam and beam:IsA("Beam") and beam.Attachment1
		if endAtt then
			dot.part.Position = endAtt.WorldPosition
		end
	end
end

local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function computeAim(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local at = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(at.X, at.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = localCharacter()
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * 500
end

-- Hold the trigger (mouse / touch via Tool.Activated) to fire; the aim streams to the server at 10 Hz.
local function hookLocalLaser(tool: Tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	local function setFiring(on: boolean)
		if firing == on then
			return
		end
		firing = on
		Remotes.get("LaserFire"):FireServer(on)
		if on then
			task.spawn(function()
				while firing and tool.Parent do
					local aim = computeAim()
					if aim then
						Remotes.get("LaserAim"):FireServer(aim)
					end
					task.wait(0.1)
				end
			end)
		end
	end
	tool.Activated:Connect(function()
		setFiring(true)
	end)
	tool.Deactivated:Connect(function()
		setFiring(false)
	end)
	tool.Unequipped:Connect(function()
		setFiring(false)
	end)
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(workspace) then
			setFiring(false)
		end
	end)
end

local function watchCharacter(character: Model)
	local function check()
		local tool = nil
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("ItemId") == "laser_pointer" then
				tool = child
			end
		end
		laserEquipped = tool ~= nil
		if tool then
			hookLocalLaser(tool)
		elseif firing then
			firing = false
		end
		local slot = slotById.laser_pointer
		if slot then
			refreshSlot(slot)
		end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			check()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(check)
		end
	end)
	check()
end

------------------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------------------
function ItemsClient.start(screenGui: ScreenGui, options: StartOptions?): Frame
	local opts: StartOptions = options or {}
	gui = screenGui
	local bar = buildHotbar(opts)

	if not player then
		-- Edit-mode preview: no remotes, no input; show a plausible state
		local preview = opts._previewData or {}
		data = preview
		laserEquipped = preview.laserEquipped == true
		refreshAll()
		for id, fraction in preview.cooldownFraction or {} do
			local slot = slotById[id]
			if slot then
				slot.cooldown.Visible = true
				slot.cooldown.Size = UDim2.fromScale(1, fraction)
				slot.cooldownText.Visible = true
				slot.cooldownText.Text = tostring(math.ceil(fraction * slot.def.cooldown))
			end
		end
		for id, fraction in preview.activeFraction or {} do
			local slot = slotById[id]
			if slot then
				slot.active.Visible = true
				slot.active.Size = UDim2.new(fraction, -20 * fraction, 0, 3)
			end
		end
		return bar
	end

	-- data
	Remotes.get("DataUpdated").OnClientEvent:Connect(function(snapshot)
		data = snapshot
		refreshAll()
	end)
	task.spawn(function()
		local snapshot = Remotes.get("GetData"):InvokeServer()
		if snapshot and not data then
			data = snapshot
			refreshAll()
		end
	end)
	player:GetAttributeChangedSignal("LaserBattery"):Connect(function()
		refreshSlot(slotById.laser_pointer)
	end)
	task.spawn(runCooldownTexts)

	-- keys 1-4
	local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4 }
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local index = KEYS[input.KeyCode]
		local slot = index and slots[index]
		if slot then
			Sfx.play("Click")
			use(slot)
		end
	end)

	-- the local character: laser equipped state + trigger input
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end

	-- events from the server
	local handlers: { [string]: (...any) -> () } = {
		speed = function(character, duration)
			if typeof(character) == "Instance" then
				speedFx(character, tonumber(duration) or 20)
			end
		end,
		heal = function(character, duration)
			if typeof(character) == "Instance" then
				healFx(character, tonumber(duration) or 4)
			end
		end,
		unlock = function(model)
			if typeof(model) == "Instance" and model:IsA("Model") then
				local position = model:GetPivot().Position
				local lid = model:FindFirstChild("Lid")
				if lid and lid:IsA("BasePart") then
					position = lid.Position
				end
				if isNear(position, 150) then
					sparkleAt(position + Vector3.new(0, 0.4, 0))
					Sfx.at(position, "LockOpen")
				end
			end
		end,
		stun = function(entity)
			if typeof(entity) == "Instance" and entity:IsA("Model") then
				local position = entity:GetPivot().Position
				if isNear(position, 200) then
					Sfx.at(position, "Stun")
				end
			end
		end,
		laserHit = function(position)
			if typeof(position) == "Vector3" then
				Sfx.at(position, "LaserHiss")
			end
		end,
	}
	Remotes.get("ItemEvent").OnClientEvent:Connect(function(kind, ...)
		local handler = handlers[kind]
		if handler then
			handler(...)
		end
	end)

	-- stun flare on every Entity, red dot on every firing laser
	for _, entity in CollectionService:GetTagged("Entity") do
		watchEntity(entity)
	end
	CollectionService:GetInstanceAddedSignal("Entity"):Connect(watchEntity)
	CollectionService:GetInstanceRemovedSignal("Entity"):Connect(function(entity)
		flareTokens[entity] = nil
		eyeOriginals[entity] = nil
	end)
	for _, tool in CollectionService:GetTagged(LASER_TAG) do
		watchLaserTool(tool)
	end
	CollectionService:GetInstanceAddedSignal(LASER_TAG):Connect(watchLaserTool)
	CollectionService:GetInstanceRemovedSignal(LASER_TAG):Connect(removeDot)
	RunService.RenderStepped:Connect(updateDots)

	-- lockpick ticks while holding a lock prompt (the prompt itself is the server's)
	local picking: Sound? = nil
	local function stopPicking()
		if picking then
			picking:Destroy()
			picking = nil
		end
	end
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt:GetAttribute("Panel") == "Lock" and prompt.Parent then
			stopPicking()
			picking = Sfx.loop(prompt.Parent, "LockpickClick")
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(stopPicking)
	ProximityPromptService.PromptTriggered:Connect(stopPicking)

	-- slide in from the bottom edge like the menu
	local target = bar.Position
	bar.Position = target + UDim2.fromOffset(0, 160)
	task.delay(0.7, function()
		tween(bar, TweenInfo.new(0.55, Enum.EasingStyle.Back), { Position = target })
	end)
	return bar
end

return ItemsClient
