--[[
	Trial overlay (the world side; the door room's PICK A DOOR is DoorRoom.client.luau), in the lobby's
	dark-glass UIKit style. Driven by attributes: workspace Phase / TimeLeft, the local player's Status /
	World / Objective / Picked / LastWorld / Reward / RevivesLeft, and WorldEvent "escalate".

	  reveal card    when you arrive in a world: door colour, world name, SAFE / DANGER, the video's
	                 survival chance, up to three rule hints (5 s)
	  objective      top-left while you're inside: the world and the current step ("SEARCH THE CRATE")
	  escalation     "SOMETHING CHANGED" when a dangerous world escalates
	  FOLLOW THEM IN in a lounge, while the round runs (the server checks someone is still in there)
	  result         got out / didn't make it, then "waiting for the others" and WATCH (spectate) controls
	  return         BACK TO THE LIBRARY and its countdown
	The items hotbar and the lantern FX are separate LocalScripts beside this one.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)
local UIKit = require(Shared.UIKit)
local Worlds = require(Shared.Worlds)

local player = Players.LocalPlayer
local C = UIKit.Colors
local Face = UIKit.Face

local DOOR_COLORS = { Left = Color3.fromRGB(196, 44, 38), Right = Color3.fromRGB(56, 104, 214) }
local DOOR_NAMES = { Left = "THE RED DOOR", Right = "THE BLUE DOOR" }

local gui = UIKit.new("ScreenGui", {
	Name = "TrialUI",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad), goal)
	t:Play()
	return t
end

local function text(props: { [string]: any })
	local merged = {
		BackgroundTransparency = 1,
		FontFace = Face.body,
		TextSize = 18,
		TextColor3 = C.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		merged[k] = v
	end
	return UIKit.new("TextLabel", merged)
end

-- A glass card that pops in and out (a CanvasGroup so the whole card fades together).
local function card(name: string, size: UDim2, anchor: Vector2, position: UDim2)
	local holder = UIKit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		Visible = false,
		Parent = gui,
	})
	UIKit.fit(holder)
	local group = UIKit.new("CanvasGroup", {
		Name = "Group",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Parent = holder,
	})
	local face = UIKit.new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), Parent = group })
	UIKit.glass(face, { alpha = UIKit.Theme.sheetAlpha, radius = UIKit.Theme.radiusLarge })
	return holder, group, face
end

local function showCard(holder: Frame, group: CanvasGroup, on: boolean)
	if on then
		holder.Visible = true
		group.Position = UDim2.fromOffset(0, 10)
		tween(group, 0.35, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
	else
		tween(group, 0.3, { GroupTransparency = 1 })
		task.delay(0.32, function()
			if group.GroupTransparency > 0.99 then
				holder.Visible = false
			end
		end)
	end
end

------------------------------------------------------------------------------------------
-- Reveal card
------------------------------------------------------------------------------------------
local reveal, revealGroup, revealFace =
	card("Reveal", UDim2.fromOffset(520, 270), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.42))
local revealBar = UIKit.new("Frame", {
	Name = "DoorColor",
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(0, 8, 1, 0),
	Parent = revealFace,
}, { UIKit.corner(4) })
local revealKicker = text({
	Position = UDim2.fromOffset(30, 22),
	Size = UDim2.new(1, -60, 0, 20),
	FontFace = Face.uiSemi,
	TextSize = 16,
	TextColor3 = C.inkMuted,
	Parent = revealFace,
})
local revealName = text({
	Position = UDim2.fromOffset(30, 44),
	Size = UDim2.new(1, -180, 0, 52),
	FontFace = Face.display,
	TextSize = 44,
	TextColor3 = C.paperLight,
	TextScaled = true,
	Parent = revealFace,
})
local revealChip = text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -26, 0, 54),
	Size = UDim2.fromOffset(110, 32),
	FontFace = Face.ui,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.ink,
	BackgroundTransparency = 0,
	Parent = revealFace,
})
UIKit.corner(16).Parent = revealChip
local revealOdds = text({
	Position = UDim2.fromOffset(30, 100),
	Size = UDim2.new(1, -60, 0, 22),
	FontFace = Face.uiSemi,
	TextSize = 18,
	TextColor3 = C.paper,
	Parent = revealFace,
})
local revealHints = text({
	Position = UDim2.fromOffset(30, 132),
	Size = UDim2.new(1, -60, 0, 120),
	TextSize = 18,
	TextColor3 = C.paper,
	TextTransparency = 0.1,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	LineHeight = 1.25,
	Parent = revealFace,
})

local revealToken = 0
local function showReveal(id: string, followed: boolean)
	local def = Worlds.get(id)
	if not def then
		return
	end
	local picked = player:GetAttribute("Picked")
	local doorColor = DOOR_COLORS[picked] or C.accent
	revealBar.BackgroundColor3 = if followed then C.accent else doorColor
	revealKicker.Text = if followed then "YOU FOLLOWED THEM IN" else (DOOR_NAMES[picked] or "BEHIND THE DOOR")
	revealName.Text = def.name
	local safe = def.kind == "safe"
	revealChip.Text = if safe then "SAFE" else "DANGER"
	revealChip.BackgroundColor3 = if safe then C.success else C.danger
	revealOdds.Text = if def.survival
		then string.format("Survival: %d%%", def.survival)
		else (if safe then "You can rest here." else "Survival: unknown")
	local lines = {}
	for i, line in (def.play and def.play.hints) or {} do
		if i > 3 then
			break
		end
		table.insert(lines, "-  " .. line)
	end
	if #lines == 0 then
		table.insert(lines, def.blurb)
	end
	revealHints.Text = table.concat(lines, "\n")
	revealToken += 1
	local token = revealToken
	showCard(reveal, revealGroup, true)
	Sfx.play("RevealSting", 0.02)
	task.delay(5.5, function()
		if revealToken == token then
			showCard(reveal, revealGroup, false)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Objective (top-left)
------------------------------------------------------------------------------------------
local objective, objectiveGroup, objectiveFace =
	card("Objective", UDim2.fromOffset(380, 78), Vector2.new(0, 0), UDim2.fromOffset(16, 16))
local objWorld = text({
	Position = UDim2.fromOffset(18, 10),
	Size = UDim2.new(1, -36, 0, 18),
	FontFace = Face.uiSemi,
	TextSize = 14,
	TextColor3 = C.inkMuted,
	Parent = objectiveFace,
})
local objText = text({
	Position = UDim2.fromOffset(18, 30),
	Size = UDim2.new(1, -36, 0, 40),
	FontFace = Face.ui,
	TextSize = 20,
	TextColor3 = C.paperLight,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Parent = objectiveFace,
})

------------------------------------------------------------------------------------------
-- SOMETHING CHANGED
------------------------------------------------------------------------------------------
local changed = text({
	Name = "Escalated",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.fromOffset(900, 70),
	FontFace = Face.display,
	TextSize = 58,
	TextColor3 = C.danger,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 1,
	TextTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Center,
	Text = "SOMETHING CHANGED",
	Parent = gui,
})
UIKit.fit(changed)

local function somethingChanged()
	Sfx.play("Escalate", 0.02)
	changed.TextTransparency = 0
	changed.TextStrokeTransparency = 0.6
	for i = 1, 4 do
		task.delay(i * 0.09, function()
			changed.TextTransparency = if i % 2 == 1 then 0.6 else 0
		end)
	end
	task.delay(2.6, function()
		tween(changed, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
end

Remotes.get("WorldEvent").OnClientEvent:Connect(function(id, kind)
	if kind == "escalate" and id == player:GetAttribute("World") then
		somethingChanged()
	end
end)

------------------------------------------------------------------------------------------
-- FOLLOW THEM IN
------------------------------------------------------------------------------------------
local followButton = UIKit.button("FOLLOW THEM IN", {
	Name = "FollowIn",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -96),
	Size = UDim2.fromOffset(250, 48),
	TextSize = 20,
	Visible = false,
	Parent = gui,
}, { style = "accent", icon = "play", tooltip = "Into the dangerous world, after the others. No way back." })
UIKit.fit(followButton)
followButton.Activated:Connect(function()
	Remotes.get("FollowIn"):FireServer()
end)

------------------------------------------------------------------------------------------
-- Result + spectate (bottom centre) and the return countdown
------------------------------------------------------------------------------------------
local result, resultGroup, resultFace =
	card("Result", UDim2.fromOffset(460, 132), Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -24))
local resultTitle = text({
	Position = UDim2.fromOffset(22, 14),
	Size = UDim2.new(1, -44, 0, 34),
	FontFace = Face.display,
	TextSize = 30,
	TextColor3 = C.paperLight,
	Parent = resultFace,
})
local resultSub = text({
	Position = UDim2.fromOffset(22, 50),
	Size = UDim2.new(1, -44, 0, 22),
	TextSize = 18,
	TextColor3 = C.paper,
	Parent = resultFace,
})
local watchLabel = text({
	Position = UDim2.fromOffset(22, 86),
	Size = UDim2.new(1, -200, 0, 30),
	FontFace = Face.uiSemi,
	TextSize = 17,
	TextColor3 = C.inkMuted,
	Parent = resultFace,
})
local watchPrev = UIKit.button("<", {
	Name = "Prev",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -112, 0, 82),
	Size = UDim2.fromOffset(44, 36),
	TextSize = 18,
	Parent = resultFace,
})
local watchNext = UIKit.button(">", {
	Name = "Next",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -62, 0, 82),
	Size = UDim2.fromOffset(44, 36),
	TextSize = 18,
	Parent = resultFace,
})
local watchStop = UIKit.button("X", {
	Name = "Stop",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 82),
	Size = UDim2.fromOffset(44, 36),
	TextSize = 18,
	Parent = resultFace,
}, { tooltip = "Stop watching" })

local returnCard, returnGroup, returnFace =
	card("Return", UDim2.fromOffset(420, 64), Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 24))
local returnText = text({
	Position = UDim2.fromOffset(22, 0),
	Size = UDim2.new(1, -44, 1, 0),
	FontFace = Face.ui,
	TextSize = 22,
	TextColor3 = C.paperLight,
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = returnFace,
})

-- spectating: the camera on someone still inside a world
local watching: Player? = nil
local function candidates(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Status") == "In" then
			table.insert(out, p)
		end
	end
	return out
end
local function watch(target: Player?)
	local camera = workspace.CurrentCamera
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if target and humanoid then
		watching = target
		camera.CameraSubject = humanoid
	else
		watching = nil
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if own then
			camera.CameraSubject = own
		end
	end
end
local function cycle(step: number)
	local list = candidates()
	if #list == 0 then
		watch(nil)
		return
	end
	local i = (watching and table.find(list, watching)) or 0
	watch(list[(i - 1 + step) % #list + 1])
end
watchPrev.Activated:Connect(function()
	cycle(-1)
end)
watchNext.Activated:Connect(function()
	cycle(1)
end)
watchStop.Activated:Connect(function()
	watch(nil)
end)

------------------------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------------------------
local lastWorld: string? = nil
local resultShown, objectiveShown, returnShown = false, false, false

local function setShown(which: string, on: boolean)
	if which == "result" and on ~= resultShown then
		resultShown = on
		showCard(result, resultGroup, on)
	elseif which == "objective" and on ~= objectiveShown then
		objectiveShown = on
		showCard(objective, objectiveGroup, on)
	elseif which == "return" and on ~= returnShown then
		returnShown = on
		showCard(returnCard, returnGroup, on)
	end
end

local function render()
	local phase = workspace:GetAttribute("Phase") or "Waiting"
	local status = player:GetAttribute("Status") or "Door"
	local worldId = player:GetAttribute("World")
	local def = Worlds.get(worldId)

	-- arriving somewhere new: the reveal card (a lounge -> its dangerous world is a follow). The
	-- World attribute lands a moment before Status "In": only count the arrival once both have.
	local arrived = if status == "In" then worldId else nil
	if arrived ~= lastWorld and (arrived or not worldId) then
		local previous = lastWorld
		lastWorld = arrived
		if arrived then
			showReveal(arrived, previous ~= nil)
		end
	end

	-- out of the world before the reveal card timed out: take it down
	if status ~= "In" and reveal.Visible then
		revealToken += 1
		showCard(reveal, revealGroup, false)
	end

	-- objective
	local inside = status == "In" and def ~= nil
	setShown("objective", inside and phase ~= "Return")
	if inside and def then
		objWorld.Text = string.upper(def.name)
		if def.kind == "safe" then
			objText.Text = "Look around. Leave by the exit whenever you like."
		else
			local revives = player:GetAttribute("RevivesLeft") or 0
			objText.Text = (player:GetAttribute("Objective") or "FIND A WAY OUT")
				.. (if revives > 0 then "   (revive ready)" else "")
		end
	end
	followButton.Visible = inside and def ~= nil and def.kind == "safe" and phase == "Round"

	-- result + spectate
	local out = status == "Escaped" or status == "Dead" or status == "Spectating"
	setShown("result", out)
	if out then
		local reward = player:GetAttribute("Reward") or 0
		local last = Worlds.get(player:GetAttribute("LastWorld"))
		if status == "Escaped" then
			resultTitle.Text = if last and last.kind == "safe"
				then "YOU LEFT " .. string.upper(last.name)
				else "YOU GOT OUT"
			resultTitle.TextColor3 = C.success
			resultSub.Text = string.format("+%d %s.  Waiting for the others.", reward, Config.CurrencyName)
		elseif status == "Dead" then
			resultTitle.Text = "YOU DIDN'T MAKE IT"
			resultTitle.TextColor3 = C.danger
			resultSub.Text = if last then "No keys this time. Waiting for the others." else "You never chose a door."
		else
			resultTitle.Text = "THE DOORS ARE CLOSED"
			resultTitle.TextColor3 = C.paperLight
			resultSub.Text = "This round started without you. Wait for the next one."
		end
		local list = if phase == "Return" then {} else candidates()
		if watching and not table.find(list, watching) then
			watch(nil)
		end
		watchLabel.Text = if watching
			then "Watching " .. watching.DisplayName
			elseif #list > 0 then string.format("%d still inside. Watch them:", #list)
			else "Nobody left inside."
		watchPrev.Visible = #list > 0
		watchNext.Visible = #list > 0
		watchStop.Visible = watching ~= nil
	elseif watching then
		watch(nil)
	end

	-- return
	setShown("return", phase == "Return")
	if phase == "Return" then
		returnText.Text = string.format("BACK TO THE LIBRARY  %d", workspace:GetAttribute("TimeLeft") or 0)
		if watching then
			watch(nil)
		end
	end
end

for _, name in { "Phase", "TimeLeft" } do
	workspace:GetAttributeChangedSignal(name):Connect(render)
end
for _, name in { "Status", "World", "Objective", "RevivesLeft", "Reward", "LastWorld" } do
	player:GetAttributeChangedSignal(name):Connect(render)
end
-- other players coming and going change who can be watched
task.spawn(function()
	while true do
		task.wait(1)
		if resultShown then
			render()
		end
	end
end)

-- Toasts go top-right so they never sit on the objective card.
Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
	UIKit.toast(gui, message, kind)
	local toasts = gui:FindFirstChild("Toasts")
	if toasts then
		toasts.AnchorPoint = Vector2.new(1, 0)
		toasts.Position = UDim2.new(1, -16, 0, 80)
	end
end)

render()
