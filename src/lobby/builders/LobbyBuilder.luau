--[[
	Builds the lobby: a basement that someone turned into a library, spread over several rooms at
	different levels. Its windows look out onto something that can't be there: an endless flooded
	natatorium of tiled vaults, lit cold and still.

	Run from the Studio command bar (or MCP) to bake it into the place:
		require(game.ServerStorage.Builders.LobbyBuilder).build()
	The lobby server also calls build() at runtime if Workspace.Lobby is missing.

	Floor plan (see Layout.luau for coordinates; +Z is the front, -Z the doors):
		Foyer (y +6)     arrival: old wooden stairs down from the house, spawn, leaderboard, notices
		Shop (y +6)      the store, through a lit storefront on the foyer's left wall
		Grand stair      a wide concrete flight down from the foyer into the reading hall
		Hall (y 0)       reading hall: study desks, bookcases, armchairs at the natatorium windows
		Workshop (y -5)  boiler room + lantern workbench, down a timber stair through the hall's right wall
		DoorHall (y 0)   through the arch at the back of the hall: six doors, the clock, PICK A DOOR

	Modules: Kit (helpers), Layout (plan), Shell (floors/walls/ceilings), Furniture, Clutter, Signage,
	Rooms/* (one per room), Npcs (Teeth, the Librarian, Mr. Ashby), Natatorium.
]]
local Lighting = game:GetService("Lighting")

local Builders = script.Parent
local Kit = require(Builders.Kit)
local Shell = require(Builders.Shell)
local Natatorium = require(Builders.Natatorium)
local Rooms = Builders:WaitForChild("Rooms")
local Foyer = require(Rooms.Foyer)

local LobbyBuilder = {}

local function optionalRoom(name: string)
	local module = Rooms:FindFirstChild(name)
	return module and require(module)
end

------------------------------------------------------------------------------------------
-- Lighting: dark, warm, dusty inside; the cold comes in through the glass
------------------------------------------------------------------------------------------
local function setupLighting()
	-- Technology is engine-protected from scripts; set Lighting.Technology = Future in Studio.
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	-- A NEUTRAL base: the per-room mood (Shared/RoomMoods, blended client-side by Mood.client) owns the
	-- Atmosphere / ColorCorrection / Bloom / ambients at runtime. These values mirror RoomMoods.Base so
	-- Edit mode and the first frame in game look the same. Exposure and bloom stay low: highlights
	-- (neon, halos, the white avatar under a lantern) must hold detail instead of blowing out.
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.fromRGB(13, 13, 14) -- dim: light lives in pools around the lamps
	Lighting.OutdoorAmbient = Color3.fromRGB(14, 17, 19)
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(60, 60, 56)
	atmosphere.Decay = Color3.fromRGB(28, 32, 34)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrection"
	cc.TintColor = Color3.fromRGB(255, 246, 236)
	cc.Contrast = 0.16
	cc.Saturation = -0.06
	cc.Brightness = 0
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 1.7 -- only the hottest cores (flames, neon rims) bloom; halos do the soft glow
	bloom.Parent = Lighting

	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = 0.16
	dof.FocusDistance = 30
	dof.InFocusRadius = 40
	dof.NearIntensity = 0
	dof.Parent = Lighting
end

function LobbyBuilder.build()
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	for _, name in { "Baseplate", "SpawnLocation" } do
		local default = workspace:FindFirstChild(name)
		if default then
			default:Destroy()
		end
	end
	Kit.reseed(1337)

	local root = Instance.new("Model")
	root.Name = "Lobby"
	local shells = Kit.folder(root, "Shell")
	local hs = Foyer.HOUSE_STAIR
	Shell.buildRoom(shells, "Foyer", { { x0 = hs.x0, x1 = hs.x1, z0 = hs.z0, z1 = hs.z1 } })
	for _, name in { "Shop", "Stair", "Hall", "DoorHall", "Workshop" } do
		Shell.buildRoom(shells, name)
	end

	Foyer.build(root)
	for _, name in { "Hall", "DoorHall", "Shop", "Workshop" } do
		local room = optionalRoom(name)
		if room then
			room.build(root)
		end
	end
	require(Builders.Locks).build(root) -- the lockpick demo chest (Workshop)
	local stations = optionalRoom("Stations") -- reward stations in the reading hall (rings + chest/wheel/desk)
	if stations then
		stations.build(root)
	end
	-- the residents, baked in so they stand in place in Edit mode too: Teeth behind the store counter,
	-- the Librarian (and his lectern) in the foyer, Mr. Ashby at the Challenges desk. Static here; the
	-- lobby services adopt these copies at runtime and bring them to life.
	require(Builders.Npcs).build(root)
	-- keep the vaults out of the stairwell shaft that rises above the foyer
	Natatorium.build(root, { { hs.x0 - 2, hs.x1 + 2, hs.z0 - 2, hs.z1 + 2 } })
	root.Parent = workspace

	setupLighting()
	return root
end

return LobbyBuilder
