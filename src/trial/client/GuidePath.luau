--[[
	GuidePath: the DOORS-style blue path. Once a dangerous world escalates, the server points the
	local player's GuideTarget (an ObjectValue under the Player) at the current objective's target
	(then the exit); this draws a line of glowing blue discs on the floor from you toward it, with a
	brightness wave travelling along it, and outlines the target in blue.

	  GuidePath.start()   once (WorldClient does it)

	Routing, re-done every Config.Worlds.guide.refresh seconds: PathfindingService first; if that
	fails, A* over the world's authored Guide nodes (parts with a Links attribute, "a,b,c"); if there
	are none, a straight line. The discs are a pool of Config.Worlds.guide.discs local parts, spacing
	studs apart, dropped onto the floor with a raycast.
]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sfx = require(Shared:WaitForChild("Sfx"))

local GuidePath = {}

local player = Players.LocalPlayer
local G = Config.Worlds.guide

local started = false

-- A* over a world's Guide folder (node parts, Links = "name,name").
local function nodeRoute(folder: Instance, from: Vector3, to: Vector3): { Vector3 }?
	local nodes: { [string]: BasePart } = {}
	for _, n in folder:GetChildren() do
		if n:IsA("BasePart") then
			nodes[n.Name] = n
		end
	end
	local function nearest(p: Vector3): string?
		local best, bestD = nil, math.huge
		for name, n in nodes do
			local d = (n.Position - p).Magnitude
			if d < bestD then
				best, bestD = name, d
			end
		end
		return best
	end
	local start, goal = nearest(from), nearest(to)
	if not start or not goal then
		return nil
	end
	local open = { [start] = true }
	local came: { [string]: string } = {}
	local g: { [string]: number } = { [start] = 0 }
	local f: { [string]: number } = { [start] = (nodes[start].Position - nodes[goal].Position).Magnitude }
	while next(open) do
		local current, best = nil, math.huge
		for name in open do
			if f[name] < best then
				current, best = name, f[name]
			end
		end
		if current == goal then
			local path = { to }
			local at: string? = goal
			while at do
				table.insert(path, 1, nodes[at].Position)
				at = came[at]
			end
			table.insert(path, 1, from)
			return path
		end
		open[current :: string] = nil
		local links = nodes[current :: string]:GetAttribute("Links")
		for link in string.gmatch(if typeof(links) == "string" then links else "", "[^,%s]+") do
			local n = nodes[link]
			if n then
				local cost = g[current :: string] + (n.Position - nodes[current :: string].Position).Magnitude
				if cost < (g[link] or math.huge) then
					came[link] = current :: string
					g[link] = cost
					f[link] = cost + (n.Position - nodes[goal].Position).Magnitude
					open[link] = true
				end
			end
		end
	end
	return nil
end

function GuidePath.start()
	if started then
		return
	end
	started = true
	local value = player:WaitForChild("GuideTarget", math.huge) :: ObjectValue

	local folder = Instance.new("Folder")
	folder.Name = "GuidePath"
	folder.Parent = workspace.CurrentCamera
	local discs: { BasePart } = {}
	for i = 1, G.discs do
		local disc = Instance.new("Part")
		disc.Name = "Disc" .. i
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.08, 1.5, 1.5)
		disc.Color = G.color
		disc.Material = Enum.Material.Neon
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Transparency = 1
		disc.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = G.color
		light.Range = 5
		light.Brightness = 0.6
		light.Enabled = i % 3 == 1 -- a few lights carry the glow onto the walls
		light.Parent = disc
		discs[i] = disc
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "GuideHighlight"
	highlight.FillColor = G.color
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = G.color:Lerp(Color3.new(1, 1, 1), 0.3)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = folder

	local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5, AgentCanJump = true })
	local points: { Vector3 } = {}
	local shown = 0
	local lastRoute = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local function route(from: Vector3, to: Vector3): { Vector3 }
		local ok = pcall(path.ComputeAsync, path, from, to)
		if ok and path.Status == Enum.PathStatus.Success then
			local out = {}
			for _, w in path:GetWaypoints() do
				table.insert(out, w.Position)
			end
			return out
		end
		local id = player:GetAttribute("World")
		local trial = workspace:FindFirstChild("Trial")
		local worlds = trial and trial:FindFirstChild("Worlds")
		local model = worlds and id and worlds:FindFirstChild(id)
		local guide = model and model:FindFirstChild("Guide")
		return (guide and nodeRoute(guide, from, to)) or { from, to }
	end

	-- discs every `spacing` studs along the route, from the player outwards, dropped onto the floor
	local function layout(waypoints: { Vector3 })
		local character = player.Character
		params.FilterDescendantsInstances = { folder, character :: any }
		local placed = 0
		local carry = G.spacing * 0.75
		for i = 1, #waypoints - 1 do
			local a, b = waypoints[i], waypoints[i + 1]
			local seg = b - a
			local len = seg.Magnitude
			local d = carry
			while d <= len and placed < #discs do
				local p = a + seg.Unit * d
				local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
				placed += 1
				points[placed] = if hit then hit.Position + Vector3.new(0, 0.06, 0) else p
				d += G.spacing
			end
			carry = d - len
			if placed >= #discs then
				break
			end
		end
		shown = placed
	end

	RunService.RenderStepped:Connect(function()
		local target = value.Value
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local on = target ~= nil and target:IsA("BasePart") and root ~= nil
		if not on then
			if highlight.Enabled or shown > 0 then
				highlight.Enabled = false
				shown = 0
				for _, disc in discs do
					disc.Transparency = 1
				end
			end
			return
		end
		local targetPart = target :: BasePart
		if not highlight.Enabled or highlight.Adornee ~= targetPart then
			if not highlight.Enabled then
				Sfx.play("GuideChime", 0.03)
			end
			highlight.Adornee = targetPart
			highlight.Enabled = true
			lastRoute = 0
		end
		local now = os.clock()
		if now - lastRoute >= G.refresh then
			lastRoute = now
			local from = (root :: BasePart).Position
			task.spawn(function()
				layout(route(from, targetPart.Position))
			end)
		end
		-- the travelling wave: a bright band runs out from your feet along the line
		local t = now * 14
		for i, disc in discs do
			if i <= shown then
				local wave = math.max(0, math.cos((i * G.spacing - t) / 6)) ^ 3
				disc.Transparency = 0.55 - wave * 0.4
				disc.CFrame = CFrame.new(points[i]) * CFrame.Angles(0, 0, math.rad(90))
			else
				disc.Transparency = 1
			end
		end
	end)
end

return GuidePath
