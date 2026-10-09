--[[
	Reward stations, client side: the coordinator for the three glowing rings in the reading hall and
	their panels. The panels themselves live in RewardsUI/ (Daily, Wheel, Challenges, built on
	RewardsUI/Shell + Shared/UIFx); this script owns everything between them and the world:

	  * Ring detection: standing on a station's ring (workspace.Lobby.Stations.*, attributes Station +
	    RingRadius, child part Ring) opens that station's panel and sets LocalPlayer attribute
	    AtStation = "Daily" | "Wheel" | "Challenges". Stepping off closes it and clears AtStation.
	    Closing the panel yourself while still on the ring latches that station: it won't re-open
	    until you step off and back on.
	  * ScreenGui "RewardsUI" holding the panels "DailyPanel", "WheelPanel" and "ChallengesPanel".
	  * BindableEvent script.Parent.OpenChallenges (created here): fire it to open the ledger.
	    Fires script.Parent.TalkArchivist (created by Archivist.client, may be missing) from TALK.
	  * A bobbing "!" BillboardGui "Badge" over each station's LabelAnchor while something is waiting.
	  * Data fan-out: every DataUpdated snapshot (and the UTC day turning) re-renders each panel;
	    each panel's tick() runs once a second for its countdowns.

	All rules, tables and maths come from Shared.Rewards; the server decides everything.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local UIKit = require(Shared.UIKit)

local RewardsUI = script.Parent:WaitForChild("RewardsUI")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Colors, Face = UIKit.Colors, UIKit.Face

local snapshot: any = nil -- latest profile snapshot from the server

local gui = UIKit.new("ScreenGui", {
	Name = "RewardsUI",
	ResetOnSpawn = false,
	DisplayOrder = 6,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Toasts go through the lobby HUD's holder when it exists so they stack with the server's Notify toasts
-- instead of drawing on top of them.
local function toast(message: string, kind: string?)
	local lobbyGui = playerGui:FindFirstChild("LobbyUI")
	UIKit.toast(if lobbyGui and lobbyGui:IsA("ScreenGui") then lobbyGui else gui, message, kind)
end

local talkEvent: BindableEvent? = nil
task.spawn(function()
	local found = script.Parent:WaitForChild("TalkArchivist", 5)
	if found and found:IsA("BindableEvent") then
		talkEvent = found
	end
end)
local function talkArchivist()
	local event = talkEvent or script.Parent:FindFirstChild("TalkArchivist")
	if event and event:IsA("BindableEvent") then
		event:Fire()
	else
		toast(Rewards.ArchivistName .. " is buried in his ledgers. Try again in a moment.")
	end
end

local ctx = {
	gui = gui,
	getSnapshot = function()
		return snapshot
	end,
	toast = toast,
	talkArchivist = talkArchivist,
}

type StationUI = { panel: Frame, update: (any?) -> (), tick: () -> () }

local stations: { [string]: StationUI } = {}
for _, name in { "Daily", "Wheel", "Challenges" } do
	local ok, result = pcall(function()
		return require(RewardsUI:WaitForChild(name)).build(ctx)
	end)
	if ok and result then
		stations[name] = result
	else
		warn("[Rewards] couldn't build the " .. name .. " panel: " .. tostring(result))
	end
end

------------------------------------------------------------------------------------------
-- Panels + open / close bookkeeping
------------------------------------------------------------------------------------------
local panelsByStation: { [string]: Frame } = {}
for name, station in stations do
	panelsByStation[name] = station.panel
end

local currentStation: string? = nil -- the ring we're standing on
local latched: { [string]: boolean } = {} -- closed by the player while still on the ring

local function hideLobbyPanels()
	local lobbyGui = playerGui:FindFirstChild("LobbyUI")
	if not lobbyGui then
		return
	end
	for _, child in lobbyGui:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute("Open") == true then
			UIKit.hide(child)
		end
	end
end

local function openPanel(panel: Frame)
	hideLobbyPanels()
	for _, other in panelsByStation do
		if other ~= panel then
			UIKit.hide(other)
		end
	end
	UIKit.show(panel)
end

local function hideAll()
	for _, panel in panelsByStation do
		UIKit.hide(panel)
	end
end

-- Closing a station's panel any way at all (X, another panel, TALK) while on its ring latches it.
for name, panel in panelsByStation do
	panel:GetAttributeChangedSignal("Open"):Connect(function()
		if panel:GetAttribute("Open") ~= true and currentStation == name then
			latched[name] = true
		end
	end)
end

-- Opening one of the lobby HUD's panels (Shop, Lanterns, ...) puts ours away.
task.spawn(function()
	local lobbyGui = playerGui:WaitForChild("LobbyUI", 30)
	if not lobbyGui then
		return
	end
	local function watch(child: Instance)
		if not child:IsA("Frame") then
			return
		end
		-- UIKit.panel parents the frame before it sets Open, so listen for any Open change
		child.AttributeChanged:Connect(function(attr)
			if attr == "Open" and child:GetAttribute("Open") == true then
				hideAll()
			end
		end)
	end
	for _, child in lobbyGui:GetChildren() do
		watch(child)
	end
	lobbyGui.ChildAdded:Connect(watch)
end)

-- The archivist's dialogue opens the ledger through this (always opens, never toggles).
local openChallenges = Instance.new("BindableEvent")
openChallenges.Name = "OpenChallenges"
openChallenges.Parent = script.Parent
openChallenges.Event:Connect(function()
	local panel = panelsByStation.Challenges
	if panel then
		openPanel(panel)
	end
end)

------------------------------------------------------------------------------------------
-- Stations: ring detection + "!" badges
------------------------------------------------------------------------------------------
local stationModels: { [string]: Instance } = {}
local badges: { [string]: { gui: BillboardGui, bang: TextLabel } } = {}

local function refreshBadges()
	local waiting = Rewards.badges(snapshot)
	for name, badge in badges do
		badge.gui.Enabled = (waiting :: any)[name] == true
	end
end

local function makeBadge(name: string, model: Instance)
	task.spawn(function()
		local anchor = model:WaitForChild("LabelAnchor", 15)
		if not anchor or badges[name] then
			return
		end
		local bb = UIKit.new("BillboardGui", {
			Name = "Badge",
			Size = UDim2.fromOffset(46, 46),
			StudsOffset = Vector3.new(0, 2.4, 0),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 60,
			Enabled = false,
		})
		-- sit just above the title billboard: when it's sized in pixels, share its centre and make our
		-- canvas tall enough that the "!" lands above its top edge at any distance
		local label = anchor:FindFirstChild("Label")
		if label and label:IsA("BillboardGui") then
			if label.Size.Y.Scale == 0 then
				local labelH = label.Size.Y.Offset
				bb.StudsOffset = label.StudsOffset
				bb.StudsOffsetWorldSpace = label.StudsOffsetWorldSpace
				bb.Size = UDim2.fromOffset(46, labelH + 2 * 50)
			else
				bb.StudsOffset = label.StudsOffset + Vector3.new(0, label.Size.Y.Scale / 2 + 1.2, 0)
				bb.StudsOffsetWorldSpace = label.StudsOffsetWorldSpace
			end
		end
		-- a cream badge with a red ring and an ink "!", bobbing gently (as over the Librarian)
		local bang = UIKit.new("TextLabel", {
			Text = "!",
			FontFace = Face.bold,
			TextScaled = true,
			TextColor3 = Colors.ink,
			BackgroundColor3 = Colors.cream,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 23),
			Size = UDim2.fromOffset(36, 36),
			Parent = bb,
		}, {
			UIKit.corner(18),
			UIKit.stroke(Colors.accent, 3),
			UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
		})
		bb.Parent = anchor
		badges[name] = { gui = bb, bang = bang }
		refreshBadges()
	end)
end

local function addStation(model: Instance)
	local name = model:GetAttribute("Station")
	if type(name) ~= "string" or not panelsByStation[name] then
		return
	end
	stationModels[name] = model
	makeBadge(name, model)
end

local function rootPosition(): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- On the ring = the root's floor position within the ring's radius (the bright rim), plus `margin`.
local function onRing(model: Instance, position: Vector3, margin: number): boolean
	local ring = model:FindFirstChild("Ring")
	if not ring or not ring:IsA("BasePart") then
		return false
	end
	local radius = tonumber(model:GetAttribute("RingRadius")) or 5
	local d = position - ring.Position
	return d.X * d.X + d.Z * d.Z <= (radius + margin) * (radius + margin) and math.abs(d.Y) < 5
end

local function enterStation(name: string)
	player:SetAttribute("AtStation", name)
	latched[name] = nil
	local panel = panelsByStation[name]
	if panel and not UIKit.isOpen(panel) then
		openPanel(panel)
	end
end

local function leaveStation(name: string)
	player:SetAttribute("AtStation", nil)
	local panel = panelsByStation[name]
	if panel then
		UIKit.hide(panel)
	end
	latched[name] = nil
end

local function checkRings()
	local position = rootPosition()
	local found: string? = nil
	if position then
		-- a little hysteresis on the ring you're already on, so its edge doesn't flicker the panel
		local currentModel = currentStation and stationModels[currentStation]
		if currentModel and onRing(currentModel, position, 1) then
			found = currentStation
		else
			for name, model in stationModels do
				if model.Parent and onRing(model, position, 0) then
					found = name
					break
				end
			end
		end
	end
	if found == currentStation then
		return
	end
	local previous = currentStation
	currentStation = nil
	if previous then
		leaveStation(previous)
	end
	currentStation = found
	if found and not latched[found] then
		enterStation(found)
	end
end

task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local folder = lobby and lobby:WaitForChild("Stations", 30)
	if not folder then
		return -- no stations in this build of the lobby: nothing to detect
	end
	for _, model in folder:GetChildren() do
		addStation(model)
	end
	folder.ChildAdded:Connect(addStation)
	while true do
		checkRings()
		task.wait(0.1)
	end
end)

-- Bobbing badges (only while one is showing).
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, badge in badges do
		if badge.gui.Enabled then
			badge.bang.Position = UDim2.new(0.5, 0, 0, 23 + math.sin(t * 3) * 5)
		end
	end
end)

------------------------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------------------------
local function refreshAll()
	for name, station in stations do
		local ok, err = pcall(station.update, snapshot)
		if not ok then
			warn("[Rewards] " .. name .. " update failed: " .. tostring(err))
		end
	end
	refreshBadges()
end

Remotes.get("DataUpdated").OnClientEvent:Connect(function(data)
	snapshot = data
	refreshAll()
end)

refreshAll()
task.spawn(function()
	local ok, data = pcall(function()
		return Remotes.get("GetData"):InvokeServer()
	end)
	if ok and data and snapshot == nil then
		snapshot = data
		refreshAll()
	end
end)

-- countdowns tick every second; the badges are re-checked every 10 s and whenever the day turns
task.spawn(function()
	local lastDay = Rewards.today()
	local lastBadges = 0
	local warned: { [string]: boolean } = {}
	while true do
		task.wait(1)
		local today = Rewards.today()
		if today ~= lastDay then
			lastDay = today
			refreshAll()
		end
		for name, station in stations do
			local ok, err = pcall(station.tick)
			if not ok and not warned[name] then
				warned[name] = true -- once: this runs every second
				warn("[Rewards] " .. name .. " tick failed: " .. tostring(err))
			end
		end
		if os.clock() - lastBadges >= 10 then
			lastBadges = os.clock()
			refreshBadges()
		end
	end
end)
