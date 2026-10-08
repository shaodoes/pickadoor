-- Ambient lobby VFX (client-only): a few loose sheets of paper keep drifting down from the joists,
-- fluttering as they fall, settling on the floor for a while and then fading away.
local RunService = game:GetService("RunService")

local lobby = workspace:WaitForChild("Lobby")

local SHEETS = 7
local AREA = { xMin = -30, xMax = 30, zMin = -40, zMax = 38 } -- open floor, clear of the walls
local START_Y, FLOOR_Y = 14.2, 0.07

local rng = Random.new()
local folder = Instance.new("Folder")
folder.Name = "DriftingPapers"
folder.Parent = lobby

local function newSheet()
	local part = Instance.new("Part")
	part.Name = "DriftingPaper"
	part.Size = Vector3.new(1, 0.02, 1.35)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(200, 194, 178):Lerp(Color3.fromRGB(172, 162, 136), rng:NextNumber())
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = folder
	return { part = part }
end

local function reset(sheet, firstTime: boolean)
	sheet.origin = Vector3.new(rng:NextNumber(AREA.xMin, AREA.xMax), 0, rng:NextNumber(AREA.zMin, AREA.zMax))
	sheet.y = firstTime and rng:NextNumber(FLOOR_Y, START_Y) or START_Y
	sheet.fall = rng:NextNumber(1.1, 1.8) -- studs per second
	sheet.swing = rng:NextNumber(0.8, 1.6) -- sideways sway, studs
	sheet.freq = rng:NextNumber(1.4, 2.2)
	sheet.phase = rng:NextNumber(0, math.pi * 2)
	sheet.yaw = rng:NextNumber(0, math.pi * 2)
	sheet.spin = rng:NextNumber(-1, 1)
	sheet.landed = nil
	sheet.part.Transparency = 0
end

local sheets = {}
for _ = 1, SHEETS do
	local sheet = newSheet()
	reset(sheet, true)
	table.insert(sheets, sheet)
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, sheet in sheets do
		if sheet.landed then
			-- lie on the floor a while, then fade and start again from the ceiling
			local age = t - sheet.landed
			if age > sheet.rest then
				sheet.part.Transparency = math.min(1, (age - sheet.rest) / 1.5)
				if age > sheet.rest + 1.5 then
					reset(sheet, false)
				end
			end
		else
			sheet.y -= sheet.fall * dt
			sheet.yaw += sheet.spin * dt
			local wave = t * sheet.freq + sheet.phase
			local offset = Vector3.new(math.sin(wave) * sheet.swing, 0, math.cos(wave * 0.7) * sheet.swing * 0.5)
			-- tilt into the swing like a falling leaf
			local tilt = CFrame.Angles(math.cos(wave) * 0.6, sheet.yaw, math.sin(wave) * 0.5)
			if sheet.y <= FLOOR_Y then
				sheet.y = FLOOR_Y
				sheet.landed = t
				sheet.rest = rng:NextNumber(6, 14)
				tilt = CFrame.Angles(0, sheet.yaw, 0)
			end
			sheet.part.CFrame = CFrame.new(sheet.origin + offset + Vector3.new(0, sheet.y, 0)) * tilt
		end
	end
end)
