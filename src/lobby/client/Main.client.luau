-- Lobby HUD: Keys counter, menu (How to Play / Shop / Lantern / Invite / Revive), shop + lantern
-- panels, queue status bar, and toasts. Buttons and panels animate and click via UIKit.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)
local Remotes = require(Shared.Remotes)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors, Fonts = UIKit.Colors, UIKit.Fonts

local data = nil -- latest profile snapshot from the server

local gui = UIKit.new("ScreenGui", {
	Name = "LobbyUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local function toast(text: string, kind: string?)
	UIKit.toast(gui, text, kind)
end

-- The guide's dialogue lives in Guide.client; the menu button asks it to start through this.
local openGuide = Instance.new("BindableEvent")
openGuide.Name = "OpenGuide"
openGuide.Parent = script.Parent

------------------------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------------------------
local keysLabel = UIKit.label({
	Name = "Keys",
	Text = "...",
	Font = Fonts.ui,
	TextSize = 24,
	TextColor3 = Colors.gold,
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundTransparency = 0.15,
	BackgroundColor3 = Colors.bg,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16), -- bottom-left, clear of Roblox's chat window
	Size = UDim2.fromOffset(190, 44),
	Parent = gui,
})
UIKit.corner(6).Parent = keysLabel
UIKit.stroke().Parent = keysLabel
local keysScale = UIKit.new("UIScale", { Parent = keysLabel })
local shownKeys = nil

-- Count the number up/down to the new value with a little pop.
local function setKeys(value: number)
	if shownKeys == nil then
		shownKeys = value
		keysLabel.Text = string.format("%d %s", value, Config.CurrencyName)
		return
	end
	if value == shownKeys then
		return
	end
	local from = shownKeys
	shownKeys = value
	keysScale.Scale = 1.15
	UIKit.tween(keysScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 })
	local counter = Instance.new("NumberValue")
	counter.Value = from
	counter.Changed:Connect(function(v)
		keysLabel.Text = string.format("%d %s", math.round(v), Config.CurrencyName)
	end)
	local t = UIKit.tween(counter, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Value = value })
	t.Completed:Connect(function()
		counter:Destroy()
	end)
end

local menu = UIKit.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(160, 280),
	Parent = gui,
}, {
	UIKit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local function menuButton(text: string, order: number)
	return UIKit.button(text, {
		Name = (text:gsub("%s", "")),
		LayoutOrder = order,
		Size = UDim2.fromOffset(160, 46),
		Parent = menu,
	})
end
local helpButton = menuButton("HOW TO PLAY", 0)
local shopButton = menuButton("SHOP", 1)
local lanternButton = menuButton("LANTERN", 2)
local inviteButton = menuButton("INVITE", 3)
local reviveButton = menuButton("REVIVE PASS", 4)

------------------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------------------
local shopPanel, shopContent = UIKit.panel(gui, "Shop", UDim2.fromOffset(620, 470))
local lanternPanel, lanternContent = UIKit.panel(gui, "Lanterns", UDim2.fromOffset(700, 470))
local panels = { shopPanel, lanternPanel }

local function open(panel: Frame)
	if UIKit.isOpen(panel) then
		UIKit.hide(panel)
		return
	end
	for _, other in panels do
		if other ~= panel then
			UIKit.hide(other)
		end
	end
	UIKit.show(panel)
end

local function swatch(color: Color3)
	return UIKit.new("Frame", {
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 10, 0.5, -17),
		BackgroundColor3 = color,
	}, { UIKit.corner(17), UIKit.stroke(Colors.gold, 1) })
end

local function row(parent: Instance, order: number, height: number)
	local frame = UIKit.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -14, 0, height),
		BackgroundColor3 = Colors.panelLight,
		BackgroundTransparency = 0.45,
		Parent = parent,
	}, { UIKit.corner(6), UIKit.stroke(Colors.gold, 1) })
	frame.UIStroke.Transparency = 0.75
	UIKit.hoverRow(frame)
	return frame
end

-- Shop -----------------------------------------------------------------------------------
local shopList = UIKit.scrollList(shopContent)

local function promptRevivePass()
	if Config.ReviveGamePassId == 0 then
		toast("Revive pass isn't set up yet (Config.ReviveGamePassId).", "error")
	elseif player:GetAttribute("HasRevivePass") then
		toast("You already own Revive.")
	else
		MarketplaceService:PromptGamePassPurchase(player, Config.ReviveGamePassId)
	end
end

local function buildShop()
	for _, child in shopList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local pass = row(shopList, 0, 74)
	pass.BackgroundColor3 = Color3.fromRGB(70, 28, 24)
	UIKit.label({
		Text = "Revive Pass",
		Font = Fonts.title,
		TextSize = 26,
		TextColor3 = Colors.gold,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -170, 0, 30),
		Parent = pass,
	})
	UIKit.label({
		Text = "Come back once per trial. Game pass (Robux).",
		TextSize = 18,
		TextColor3 = Colors.muted,
		Position = UDim2.fromOffset(14, 38),
		Size = UDim2.new(1, -170, 0, 26),
		Parent = pass,
	})
	local owned = player:GetAttribute("HasRevivePass") == true
	local passButton = UIKit.button(owned and "OWNED" or "BUY", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(130, 42),
		BackgroundColor3 = owned and Colors.panel or Colors.red,
		Parent = pass,
	})
	passButton.Activated:Connect(promptRevivePass)

	for i, def in Lanterns.List do
		if def.price > 0 then
			local item = row(shopList, i, 74)
			swatch(def.lightColor).Parent = item
			UIKit.label({
				Text = def.name,
				Font = Fonts.title,
				TextSize = 24,
				Position = UDim2.fromOffset(56, 6),
				Size = UDim2.new(1, -220, 0, 30),
				Parent = item,
			})
			UIKit.label({
				Text = def.description,
				TextSize = 17,
				TextColor3 = Colors.muted,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(56, 38),
				Size = UDim2.new(1, -220, 0, 26),
				Parent = item,
			})
			local isOwned = data and data.OwnedLanterns[def.id]
			local buy = UIKit.button(isOwned and "OWNED" or string.format("%d %s", def.price, Config.CurrencyName), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(140, 42),
				BackgroundColor3 = isOwned and Colors.panel or Colors.panelLight,
				Parent = item,
			})
			buy.Activated:Connect(function()
				if isOwned then
					open(lanternPanel)
					return
				end
				local res = Remotes.get("BuyLantern"):InvokeServer(def.id)
				toast(res.message, res.ok and "success" or "error")
			end)
		end
	end
end

-- Lanterns -------------------------------------------------------------------------------
local viewport = UIKit.new("ViewportFrame", {
	Size = UDim2.fromOffset(250, 330),
	BackgroundColor3 = Colors.bg,
	Ambient = Color3.fromRGB(150, 130, 110),
	LightColor = Color3.fromRGB(255, 220, 180),
	LightDirection = Vector3.new(-1, -1, -1),
	Parent = lanternContent,
}, { UIKit.corner(8), UIKit.stroke(Colors.gold, 1) })
local previewCamera = UIKit.new("Camera", { FieldOfView = 40, Parent = viewport })
viewport.CurrentCamera = previewCamera
previewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 1.9, 6.4), Vector3.new(0, 1.35, 0))
local previewName = UIKit.label({
	Text = "",
	Font = Fonts.title,
	TextSize = 24,
	TextColor3 = Colors.gold,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.new(0, 0, 1, -40),
	Size = UDim2.new(1, 0, 0, 34),
	ZIndex = 2,
	Parent = viewport,
})

local previewModel: Model? = nil
local function preview(id: string)
	if previewModel then
		previewModel:Destroy()
	end
	previewModel = LanternBuilder.buildModel(id, true)
	previewModel.Parent = viewport
	previewName.Text = Lanterns.getOrDefault(id).name
end

lanternPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if lanternPanel.Visible and data then
		preview(data.EquippedLantern)
	end
end)

RunService.RenderStepped:Connect(function()
	if previewModel and lanternPanel.Visible then
		previewModel:PivotTo(CFrame.Angles(0, os.clock() * 0.8, 0))
	end
end)

local lanternList = UIKit.scrollList(lanternContent, {
	Position = UDim2.fromOffset(266, 0),
	Size = UDim2.new(1, -266, 1, 0),
})

local function buildLanterns()
	for _, child in lanternList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, def in Lanterns.List do
		local item = row(lanternList, i, 60)
		swatch(def.lightColor).Parent = item
		local owned = data and data.OwnedLanterns[def.id]
		local equipped = data and data.EquippedLantern == def.id
		UIKit.label({
			Text = def.name,
			Font = Fonts.title,
			TextSize = 22,
			Position = UDim2.fromOffset(56, 0),
			Size = UDim2.new(1, -190, 1, 0),
			Parent = item,
		})
		local action = UIKit.button(equipped and "EQUIPPED" or owned and "EQUIP" or "LOCKED", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(120, 38),
			BackgroundColor3 = equipped and Colors.green or Colors.panelLight,
			Parent = item,
		})
		-- clicking the row previews; the button equips
		local hit = UIKit.new(
			"TextButton",
			{ Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, -140, 1, 0), Parent = item }
		)
		hit.Activated:Connect(function()
			preview(def.id)
		end)
		action.Activated:Connect(function()
			preview(def.id)
			if equipped then
				return
			elseif not owned then
				toast(string.format("Buy %s in the Shop for %d %s.", def.name, def.price, Config.CurrencyName), "error")
				return
			end
			local res = Remotes.get("EquipLantern"):InvokeServer(def.id)
			toast(res.message, not res.ok and "error" or nil)
		end)
	end
end

------------------------------------------------------------------------------------------
-- Queue status bar
------------------------------------------------------------------------------------------
local queueBar = UIKit.new("Frame", {
	Name = "QueueBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 90), -- parked below the screen; slides up while queued
	Size = UDim2.fromOffset(460, 64),
	BackgroundColor3 = Colors.bg,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { UIKit.corner(8), UIKit.stroke() })
local queueLabel = UIKit.label({
	Font = Fonts.ui,
	TextSize = 22,
	Position = UDim2.fromOffset(18, 0),
	Size = UDim2.new(1, -150, 1, 0),
	Parent = queueBar,
})
local leaveButton = UIKit.button("LEAVE", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(110, 42),
	BackgroundColor3 = Colors.red,
	Parent = queueBar,
})
leaveButton.Activated:Connect(function()
	Remotes.get("LeaveQueue"):FireServer()
end)

task.spawn(function()
	local pads = workspace:WaitForChild("Lobby"):WaitForChild("Pads")
	while true do
		local padName = player:GetAttribute("QueuedPad")
		local pad = padName and pads:FindFirstChild(padName)
		local queued = pad ~= nil
		if queued ~= (queueBar:GetAttribute("Shown") == true) then
			queueBar:SetAttribute("Shown", queued)
			queueBar.Visible = true
			UIKit.tween(
				queueBar,
				TweenInfo.new(0.3, queued and Enum.EasingStyle.Back or Enum.EasingStyle.Quad),
				{ Position = UDim2.new(0.5, 0, 1, queued and -24 or 90) }
			)
		end
		if pad then
			queueLabel.Text = string.format(
				"%s   %d/%d   -   door opens in %ds",
				string.upper(pad:GetAttribute("Mode")),
				pad:GetAttribute("Count") or 0,
				pad:GetAttribute("Capacity") or 0,
				pad:GetAttribute("TimeLeft") or 0
			)
		end
		task.wait(0.2)
	end
end)

------------------------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------------------------
local function refresh()
	if data then
		setKeys(data.Keys)
	end
	buildShop()
	buildLanterns()
end

helpButton.Activated:Connect(function()
	for _, panel in panels do
		UIKit.hide(panel)
	end
	openGuide:Fire()
end)
shopButton.Activated:Connect(function()
	open(shopPanel)
end)
lanternButton.Activated:Connect(function()
	open(lanternPanel)
end)
reviveButton.Activated:Connect(promptRevivePass)
inviteButton.Activated:Connect(function()
	local ok, canSend = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and canSend then
		SocialService:PromptGameInvite(player)
	else
		toast("Invites aren't available right now (they work in the published game).", "error")
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local panel = prompt:GetAttribute("Panel")
	if panel == "Shop" then
		open(shopPanel)
	elseif panel == "Lanterns" then
		open(lanternPanel)
	end
end)

player:GetAttributeChangedSignal("HasRevivePass"):Connect(refresh)
Remotes.get("Notify").OnClientEvent:Connect(toast)
Remotes.get("DataUpdated").OnClientEvent:Connect(function(snapshot)
	data = snapshot
	refresh()
end)

data = Remotes.get("GetData"):InvokeServer()
refresh()
preview(data and data.EquippedLantern or Lanterns.DefaultId)

-- the menu slides in from the right edge
local menuTarget = menu.Position
menu.Position = menuTarget + UDim2.fromOffset(240, 0)
task.delay(0.5, function()
	UIKit.tween(menu, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Position = menuTarget })
end)
