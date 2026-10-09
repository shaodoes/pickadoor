--[[
	Overhead nameplates (client; started by each place's Nameplates.client script).

	Every other player's character gets a BillboardGui on its Head, replacing Roblox's default name
	and health bar:
		  DisplayName                 bold white, dark stroke (always, out to MAX_DISTANCE studs)
		  (badge) Title  |  (skull) 12   the equipped title in cream beside its rarity-coloured badge,
		                                  then the death count; only when you're close

	Distance: each client measures from its own character (or the camera while it has none) to the
	other player's head. Closer than NEAR_IN studs the title row fades + slides in and the name lifts
	above it; further than NEAR_OUT it fades back out and the name settles where the row was. The gap
	between NEAR_IN and NEAR_OUT is hysteresis so it doesn't flicker at the edge.

	The plate's pixel size is fixed (crisp at any distance), so its height above the head is
	re-solved each frame from the camera distance: the lowest line always sits just above the head.
	Data comes from Player attributes set by Common.TitleService: Title, TitleColor, TitleIcon, Deaths.
	Your own plate is hidden (Nameplates.start({ showOwn = true }) shows it).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = script.Parent
local UIKit = require(Shared.UIKit)

local Colors, Face = UIKit.Colors, UIKit.Face

local Nameplates = {}

local NEAR_IN = 9 -- studs: the title row appears inside this ...
local NEAR_OUT = 11 -- ... and goes again beyond this
local MAX_DISTANCE = 80
local WIDTH, HEIGHT = 280, 66
local NAME_H, ROW_H = 28, 24
local NAME_Y_NEAR, ROW_Y = 6, 36 -- pixel rows (top edges) inside the plate
local NAME_Y_FAR = ROW_Y + ROW_H - NAME_H -- name's bottom edge on the row's bottom edge
local BOTTOM = ROW_Y + ROW_H -- lowest content pixel
local HEAD_GAP = 0.35 -- studs between the top of the head and the plate's lowest line
local FADE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local TITLE_TEXT = Colors.cream
local OUTLINE = Color3.fromRGB(16, 10, 8)

type Plate = {
	player: Player,
	character: Model,
	head: BasePart,
	humanoid: Humanoid?,
	gui: BillboardGui,
	name: TextLabel,
	row: Frame,
	badge: Frame,
	titleLabel: TextLabel,
	deathsLabel: TextLabel,
	alpha: NumberValue,
	faders: { { inst: Instance, prop: string, base: number } },
	near: boolean,
	offsetY: number,
	connections: { RBXScriptConnection },
}

local plates: { [Player]: Plate } = {}
local showOwn = false

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	return UIKit.new(className, props, children)
end

local function outline(thickness: number, transparency: number?)
	return new("UIStroke", {
		Color = OUTLINE,
		Thickness = thickness,
		Transparency = transparency or 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

-- Remember the resting transparency of everything in the title row, so one 0..1 alpha can fade it.
-- A value is read the first time its instance is seen (new instances are at rest) and kept after.
local function collectFaders(plate: Plate)
	local known = {}
	for _, entry in plate.faders do
		known[entry.inst] = known[entry.inst] or {}
		known[entry.inst][entry.prop] = entry.base
	end
	local list = {}
	local function add(inst: Instance, prop: string)
		local base = known[inst] and known[inst][prop]
		if base == nil then
			base = (inst :: any)[prop]
		end
		table.insert(list, { inst = inst, prop = prop, base = base })
	end
	for _, inst in plate.row:GetDescendants() do
		if inst:IsA("TextLabel") then
			add(inst, "TextTransparency")
		elseif
			inst:IsA("GuiObject")
			and (known[inst] and known[inst].BackgroundTransparency or inst.BackgroundTransparency) < 1
		then
			add(inst, "BackgroundTransparency")
		elseif inst:IsA("UIStroke") then
			add(inst, "Transparency")
		end
	end
	plate.faders = list
end

local function applyAlpha(plate: Plate)
	local a = plate.alpha.Value
	for _, entry in plate.faders do
		(entry.inst :: any)[entry.prop] = entry.base + (1 - entry.base) * (1 - a)
	end
	plate.row.Visible = a > 0.01
end

-- Title text, badge colour + glyph and the death count from the player's attributes.
local function refresh(plate: Plate)
	local player = plate.player
	local color = player:GetAttribute("TitleColor")
	plate.titleLabel.Text = tostring(player:GetAttribute("Title") or "Welcome")
	plate.deathsLabel.Text = tostring(player:GetAttribute("Deaths") or 0)
	plate.badge.BackgroundColor3 = if typeof(color) == "Color3" then color else Colors.accent
	local old = plate.badge:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local glyph = UIKit.icon(tostring(player:GetAttribute("TitleIcon") or "door"), Colors.paperLight, 12)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = plate.badge
	collectFaders(plate)
	applyAlpha(plate)
end

local function setNear(plate: Plate, near: boolean, instant: boolean?)
	plate.near = near
	local info = if instant then TweenInfo.new(0) else FADE
	TweenService:Create(plate.alpha, info, { Value = near and 1 or 0 }):Play()
	TweenService:Create(plate.name, info, {
		Position = UDim2.new(0.5, 0, 0, near and NAME_Y_NEAR or NAME_Y_FAR),
	}):Play()
	TweenService:Create(plate.row, info, {
		Position = UDim2.fromOffset(0, near and ROW_Y or ROW_Y + 8),
	}):Play()
end

local function destroyPlate(player: Player)
	local plate = plates[player]
	if not plate then
		return
	end
	plates[player] = nil
	for _, c in plate.connections do
		c:Disconnect()
	end
	plate.gui:Destroy()
	plate.alpha:Destroy()
end

local function hideDefaultName(humanoid: Humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
end

local function buildPlate(player: Player, character: Model)
	destroyPlate(player)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or player.Character ~= character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hideDefaultName(humanoid)
	end

	local gui = new("BillboardGui", {
		Name = "Nameplate",
		Adornee = head,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		StudsOffsetWorldSpace = Vector3.new(0, 2, 0),
		MaxDistance = MAX_DISTANCE,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		ClipsDescendants = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local name = new("TextLabel", {
		Name = "PlayerName",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, NAME_Y_FAR),
		Size = UDim2.new(1, -8, 0, NAME_H),
		Text = player.DisplayName,
		FontFace = Face.bold,
		TextSize = 24,
		TextColor3 = Color3.new(1, 1, 1),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
		Parent = gui,
	}, { outline(2.2) })

	local row = new("Frame", {
		Name = "TitleRow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, ROW_Y + 8),
		Size = UDim2.new(1, 0, 0, ROW_H),
		Visible = false,
		Parent = gui,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- round badge in the title's rarity colour, a brass rim and the title's glyph
	local badge = new("Frame", {
		Name = "Badge",
		BackgroundColor3 = Colors.accent,
		Size = UDim2.fromOffset(20, 20),
		LayoutOrder = 1,
		Parent = row,
	}, {
		UIKit.corner(10),
		new("UIStroke", { Color = Colors.gold, Thickness = 1.5, Transparency = 0.1 }),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)),
		}),
	})
	local titleLabel = new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_H),
		Text = "",
		FontFace = Face.semi,
		TextSize = 18,
		TextColor3 = TITLE_TEXT,
		LayoutOrder = 2,
		Parent = row,
	}, { outline(1.6) })
	new("Frame", {
		Name = "Separator",
		BackgroundColor3 = Colors.paper,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(2, 14),
		LayoutOrder = 3,
		Parent = row,
	})
	local skull = UIKit.icon("skull", Colors.paper, 15)
	skull.Name = "Skull"
	skull.LayoutOrder = 4
	skull.Parent = row
	local deathsLabel = new("TextLabel", {
		Name = "Deaths",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_H),
		Text = "0",
		FontFace = Face.semi,
		TextSize = 17,
		TextColor3 = Colors.paper,
		LayoutOrder = 5,
		Parent = row,
	}, { outline(1.6) })

	local plate: Plate = {
		player = player,
		character = character,
		head = head,
		humanoid = humanoid,
		gui = gui,
		name = name,
		row = row,
		badge = badge,
		titleLabel = titleLabel,
		deathsLabel = deathsLabel,
		alpha = Instance.new("NumberValue"),
		faders = {},
		near = false,
		offsetY = 2,
		connections = {},
	}
	plates[player] = plate
	table.insert(
		plate.connections,
		plate.alpha.Changed:Connect(function()
			applyAlpha(plate)
		end)
	)
	for _, attr in { "Title", "TitleColor", "TitleIcon", "Deaths" } do
		table.insert(
			plate.connections,
			player:GetAttributeChangedSignal(attr):Connect(function()
				refresh(plate)
			end)
		)
	end
	table.insert(
		plate.connections,
		player:GetPropertyChangedSignal("DisplayName"):Connect(function()
			name.Text = player.DisplayName
		end)
	)
	refresh(plate)
	setNear(plate, false, true)
	gui.Parent = head
end

local function watchPlayer(player: Player)
	if player == Players.LocalPlayer and not showOwn then
		return
	end
	player.CharacterAdded:Connect(function(character)
		buildPlate(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		local plate = plates[player]
		if plate and plate.character == character then
			destroyPlate(player)
		end
	end)
	if player.Character then
		task.spawn(buildPlate, player, player.Character)
	end
end

-- Distance checks + the plate's height above the head, every frame.
local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local myCharacter = Players.LocalPlayer.Character
	local root = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local viewer = if root then root.Position else camPos
	-- studs per screen pixel at 1 stud from the camera
	local perPixel = 2 * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(camera.ViewportSize.Y, 1)

	for _, plate in plates do
		local head = plate.head
		if not head.Parent then
			continue
		end
		local alive = not plate.humanoid or plate.humanoid.Health > 0
		if plate.gui.Enabled ~= alive then
			plate.gui.Enabled = alive
		end
		local headPos = head.Position
		local distance = (headPos - viewer).Magnitude
		if plate.near and distance > NEAR_OUT then
			setNear(plate, false)
		elseif not plate.near and distance < NEAR_IN then
			setNear(plate, true)
		end
		-- the plate is centred on its offset point: lift it so its lowest line clears the head
		local spp = (headPos - camPos).Magnitude * perPixel
		local y = head.Size.Y / 2 + HEAD_GAP + (BOTTOM - HEIGHT / 2) * spp
		if math.abs(y - plate.offsetY) > 0.01 then
			plate.offsetY = y
			plate.gui.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
		end
	end
end

local started = false

function Nameplates.start(options: { showOwn: boolean? }?)
	if started then
		return
	end
	started = true
	showOwn = options ~= nil and options.showOwn == true

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(destroyPlate)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	RunService.RenderStepped:Connect(step)
end

return Nameplates
