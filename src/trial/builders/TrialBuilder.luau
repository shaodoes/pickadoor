-- Builds the Door Room: the dim antechamber where the party picks one of two doors.
-- Workspace.DoorRoom.Doors.Left / .Right each have a "Zone" part players stand in to vote.
local Lighting = game:GetService("Lighting")

local TrialBuilder = {}

local W, D, H = 40, 44, 18

local function box(parent, name, size, cf, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in extra or {} do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function buildDoor(parent: Instance, name: string, x: number, numeral: string)
	local door = Instance.new("Model")
	door.Name = name
	local wallZ = -D / 2
	for _, s in { -1, 1 } do
		box(
			door,
			"Jamb",
			Vector3.new(1, 11, 1.2),
			Vector3.new(x + s * 3.8, 5.5, wallZ + 0.6),
			Color3.fromRGB(70, 60, 50),
			Enum.Material.Wood
		)
	end
	box(
		door,
		"Header",
		Vector3.new(8.6, 1, 1.2),
		Vector3.new(x, 11.5, wallZ + 0.6),
		Color3.fromRGB(70, 60, 50),
		Enum.Material.Wood
	)
	box(
		door,
		"Slab",
		Vector3.new(6.6, 11, 0.4),
		Vector3.new(x, 5.5, wallZ + 0.2),
		Color3.fromRGB(196, 186, 168),
		Enum.Material.Wood
	)
	box(
		door,
		"Knob",
		Vector3.new(0.4, 0.4, 0.4),
		Vector3.new(x + 2.4, 5.2, wallZ + 0.6),
		Color3.fromRGB(150, 112, 56),
		Enum.Material.Metal,
		{ Shape = Enum.PartType.Ball }
	)
	local plate = box(
		door,
		"Plate",
		Vector3.new(1.6, 1.1, 0.1),
		Vector3.new(x, 8.6, wallZ + 0.45),
		Color3.fromRGB(150, 112, 56),
		Enum.Material.Metal
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(30, 22, 16)
	label.Text = numeral
	label.Parent = gui
	box(door, "Zone", Vector3.new(12, 8, 12), Vector3.new(x, 4, wallZ + 7), Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	box(
		door,
		"Mat",
		Vector3.new(10, 0.1, 10),
		Vector3.new(x, 0.05, wallZ + 7),
		Color3.fromRGB(90, 70, 50),
		Enum.Material.Fabric,
		{ CanCollide = false }
	)
	door.Parent = parent
	return door
end

function TrialBuilder.build()
	local existing = workspace:FindFirstChild("DoorRoom")
	if existing then
		existing:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local default = workspace:FindFirstChild(name)
		if default then
			default:Destroy()
		end
	end

	local room = Instance.new("Model")
	room.Name = "DoorRoom"
	local wall = Color3.fromRGB(176, 164, 128) -- faded liminal wallpaper
	box(room, "Floor", Vector3.new(W, 1, D), Vector3.new(0, -0.5, 0), Color3.fromRGB(110, 92, 70), Enum.Material.Carpet)
	box(
		room,
		"Ceiling",
		Vector3.new(W, 1, D),
		Vector3.new(0, H + 0.5, 0),
		Color3.fromRGB(190, 186, 170),
		Enum.Material.SmoothPlastic
	)
	for _, s in { -1, 1 } do
		box(room, "Wall", Vector3.new(1, H, D), Vector3.new(s * (W / 2 + 0.5), H / 2, 0), wall, Enum.Material.Fabric)
		box(room, "Wall", Vector3.new(W, H, 1), Vector3.new(0, H / 2, s * (D / 2 + 0.5)), wall, Enum.Material.Fabric)
	end

	local doors = Instance.new("Folder")
	doors.Name = "Doors"
	doors.Parent = room
	buildDoor(doors, "Left", -8, "I")
	buildDoor(doors, "Right", 8, "II")

	local bulb = box(
		room,
		"Bulb",
		Vector3.new(0.6, 0.8, 0.6),
		Vector3.new(0, H - 2, 0),
		Color3.fromRGB(255, 230, 190),
		Enum.Material.Neon
	)
	box(room, "Cord", Vector3.new(0.1, 1.6, 0.1), Vector3.new(0, H - 0.8, 0), Color3.fromRGB(20, 20, 20))
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Range = 34
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 226, 180)
	light.Shadows = true
	light.Parent = bulb

	local spawnPoint = Instance.new("SpawnLocation")
	spawnPoint.Name = "Spawn"
	spawnPoint.Anchored = true
	spawnPoint.Size = Vector3.new(10, 0.2, 6)
	spawnPoint.CFrame = CFrame.new(0, 0.1, D / 2 - 6)
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.Neutral = true
	spawnPoint.Duration = 0
	spawnPoint.Parent = room

	room.Parent = workspace

	-- Technology is engine-protected from scripts; set Lighting.Technology = Future in Studio.
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(16, 14, 12)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 10)
	return room
end

return TrialBuilder
