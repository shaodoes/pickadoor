--[[
	Drifting papers (client-only): a few loose sheets keep drifting down inside the lobby's rooms,
	fluttering as they fall, landing on whatever is below them (floor, desk, stair tread, at any floor
	height), resting a while and then fading away to start again near the ceiling.

	Spawn areas come from `Room` anchors placed by the builders: invisible parts with attribute
	FX = "Room" and attribute Room = <name>, sized to the room's interior. Rooms not listed in SHEETS
	get none. Anchors added later (rebuilds, streaming) are picked up too.
]]
local RunService = game:GetService("RunService")

local FX = {}

FX.SHEETS = { Foyer = 2, Shop = 1, Hall = 4, DoorHall = 3, Workshop = 1 } -- Stair: none
local MARGIN = 2 -- keep clear of the walls
local CULL = 110 -- sheets this far from the camera stop animating
local REPROBE = 0.2 -- seconds between ground raycasts while a sheet falls

local rng = Random.new()
local gameSettings = UserSettings():GetService("UserGameSettings")

FX.parent = nil :: Instance?
FX.rayParams = RaycastParams.new()
FX.rayParams.FilterType = Enum.RaycastFilterType.Exclude
FX.rayParams.IgnoreWater = true

local sheets = {}
local byRoom: { [BasePart]: { any } } = {}
FX.sheets = sheets

local function newSheet(room: BasePart)
	local part = Instance.new("Part")
	part.Name = "DriftingPaper"
	part.Size = Vector3.new(1, 0.02, 1.35)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(200, 194, 178):Lerp(Color3.fromRGB(172, 162, 136), rng:NextNumber())
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = FX.parent
	return { part = part, room = room }
end

-- What's under `pos`? Returns the landing point and its normal (the room's floor if nothing is hit).
local function ground(sheet, pos: Vector3): (Vector3, Vector3)
	local hit = workspace:Raycast(pos, Vector3.new(0, -40, 0), FX.rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	local room = sheet.room
	return Vector3.new(pos.X, room.Position.Y - room.Size.Y / 2, pos.Z), Vector3.yAxis
end

local function reset(sheet, firstTime: boolean)
	local room = sheet.room
	local half = room.Size / 2
	local local0 = Vector3.new(
		rng:NextNumber(-half.X + MARGIN, math.max(half.X - MARGIN, -half.X + MARGIN)),
		half.Y - 1,
		rng:NextNumber(-half.Z + MARGIN, math.max(half.Z - MARGIN, -half.Z + MARGIN))
	)
	local top = room.CFrame:PointToWorldSpace(local0)
	sheet.origin = Vector3.new(top.X, 0, top.Z)
	local at, normal = ground(sheet, top)
	sheet.groundY, sheet.normal = at.Y, normal
	sheet.y = firstTime and rng:NextNumber(sheet.groundY + 0.5, top.Y) or top.Y
	sheet.fall = rng:NextNumber(1.1, 1.8) -- studs per second
	sheet.swing = rng:NextNumber(0.8, 1.6) -- sideways sway, studs
	sheet.freq = rng:NextNumber(1.4, 2.2)
	sheet.phase = rng:NextNumber(0, math.pi * 2)
	sheet.yaw = rng:NextNumber(0, math.pi * 2)
	sheet.spin = rng:NextNumber(-1, 1)
	sheet.probe = 0
	sheet.landed = nil
	sheet.part.Transparency = 0
end

-- Lay the sheet flat on a surface with normal `n`, turned to its yaw.
local function restingCFrame(pos: Vector3, n: Vector3, yaw: number): CFrame
	local flat = CFrame.Angles(0, yaw, 0)
	if n.Y > 0.999 then
		return CFrame.new(pos + n * 0.012) * flat
	end
	local axis = Vector3.new(0, 1, 0):Cross(n).Unit
	local angle = math.acos(math.clamp(n.Y, -1, 1))
	return CFrame.new(pos + n * 0.012) * CFrame.fromAxisAngle(axis, angle) * flat
end

local function sheetCount(room: BasePart): number
	local n = FX.SHEETS[room:GetAttribute("Room")] or 0
	if
		gameSettings.SavedQualityLevel ~= Enum.SavedQualitySetting.Automatic
		and gameSettings.SavedQualityLevel.Value <= 3
	then
		n = math.ceil(n / 2)
	end
	return n
end

function FX.addRoom(room: BasePart)
	if byRoom[room] then
		return
	end
	local list = {}
	byRoom[room] = list
	for _ = 1, sheetCount(room) do
		local sheet = newSheet(room)
		reset(sheet, true)
		table.insert(list, sheet)
		table.insert(sheets, sheet)
	end
end

function FX.removeRoom(room: BasePart)
	local list = byRoom[room]
	if not list then
		return
	end
	byRoom[room] = nil
	for _, sheet in list do
		sheet.part:Destroy()
		local i = table.find(sheets, sheet)
		if i then
			sheets[i] = sheets[#sheets]
			sheets[#sheets] = nil
		end
	end
end

function FX.consider(inst: Instance)
	if inst:IsA("BasePart") and inst:GetAttribute("FX") == "Room" then
		FX.addRoom(inst)
	end
end

function FX.step(dt: number, t: number, camPos: Vector3)
	for _, sheet in sheets do
		local part = sheet.part
		if (sheet.origin - Vector3.new(camPos.X, 0, camPos.Z)).Magnitude > CULL then
			continue
		end
		if sheet.landed then
			-- lie there a while, then fade and start again from the ceiling
			local age = t - sheet.landed
			if age > sheet.rest then
				part.Transparency = math.min(1, (age - sheet.rest) / 1.5)
				if age > sheet.rest + 1.5 then
					reset(sheet, false)
				end
			end
		else
			sheet.y -= sheet.fall * dt
			sheet.yaw += sheet.spin * dt
			local wave = t * sheet.freq + sheet.phase
			local pos = sheet.origin
				+ Vector3.new(math.sin(wave) * sheet.swing, sheet.y, math.cos(wave * 0.7) * sheet.swing * 0.5)
			-- the sway carries it sideways, so keep checking what's underneath (cheap: a few rays a second)
			sheet.probe -= dt
			if sheet.probe <= 0 or sheet.y - sheet.groundY < 0.6 then
				sheet.probe = REPROBE
				local at, normal = ground(sheet, pos + Vector3.new(0, 0.5, 0))
				sheet.groundY, sheet.normal = at.Y, normal
			end
			if sheet.y <= sheet.groundY then
				sheet.landed = t
				sheet.rest = rng:NextNumber(6, 14)
				part.CFrame = restingCFrame(Vector3.new(pos.X, sheet.groundY, pos.Z), sheet.normal, sheet.yaw)
			else
				-- tilt into the swing like a falling leaf
				part.CFrame = CFrame.new(pos) * CFrame.Angles(math.cos(wave) * 0.6, sheet.yaw, math.sin(wave) * 0.5)
			end
		end
	end
end

-- BOOT (tests cut the script here) -------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = "DriftingPapers"
folder.Parent = workspace
FX.parent = folder

local function excludeCharacters()
	local list = { folder }
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	FX.rayParams.FilterDescendantsInstances = list
end
excludeCharacters()
task.spawn(function()
	while true do
		task.wait(2)
		excludeCharacters()
	end
end)

local function watchLobby(lobby: Instance)
	for _, d in lobby:GetDescendants() do
		FX.consider(d)
	end
	lobby.DescendantAdded:Connect(function(d)
		task.defer(FX.consider, d)
	end)
	lobby.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			FX.removeRoom(d)
		end
	end)
end
watchLobby(workspace:WaitForChild("Lobby"))
workspace.ChildAdded:Connect(function(child)
	if child.Name == "Lobby" then
		watchLobby(child)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if camera then
		FX.step(dt, os.clock(), camera.CFrame.Position)
	end
end)
