-- Lobby HUD: player card with the Keys counter, the bottom menu (PICK A DOOR + Shop / Lantern /
-- Titles / How to Play / Invite / Revive), shop + lantern + titles panels, queue status bar, and toasts.
-- Buttons and panels animate and click via UIKit; everything scales to the screen via UIKit.fit.
--
-- Instance names other scripts/tests rely on (keep them): ScreenGui "LobbyUI" with direct children
-- "Keys" (TextLabel, Text = "<n> Keys"), "Menu" > "PickADoor" (TextButton), "QueueBar" (its first
-- TextLabel child is the status line), "ShopPanel", "LanternsPanel", "TitlesPanel"; BindableEvent "OpenGuide".
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Lanterns = require(Shared.Lanterns)
local LanternBuilder = require(Shared.LanternBuilder)
local Remotes = require(Shared.Remotes)
local Titles = require(Shared.Titles)
local UIKit = require(Shared.UIKit)

local player = Players.LocalPlayer
local Colors, Face = UIKit.Colors, UIKit.Face

-- the lantern is always in hand: hide the hotbar so it can't be put away
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			return
		end
		task.wait(0.5)
	end
end)

local data = nil -- latest profile snapshot from the server
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui = UIKit.new("ScreenGui", {
	Name = "LobbyUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
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
-- Dialogue actions ("openShop" / "openLanterns") open the panels through these (wired below the panels).
local openShop = Instance.new("BindableEvent")
openShop.Name = "OpenShop"
openShop.Parent = script.Parent
local openLanterns = Instance.new("BindableEvent")
openLanterns.Name = "OpenLanterns"
openLanterns.Parent = script.Parent

local function text(props: { [string]: any })
	local merged = {
		BackgroundTransparency = 1,
		FontFace = Face.body,
		TextSize = 18,
		TextColor3 = Colors.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("TextLabel", merged)
end

-- Swap the icon inside a UIKit.button's face.
local function setIcon(button: GuiButton, name: string, color: Color3, size: number)
	local content = button:FindFirstChild("Face") and button.Face:FindFirstChild("Content")
	if not content then
		return
	end
	local old = content:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	local icon = UIKit.icon(name, color, size)
	icon.LayoutOrder = 1
	icon.Parent = content
end

------------------------------------------------------------------------------------------
-- Player card + Keys counter
------------------------------------------------------------------------------------------
-- The card itself is the "Keys" TextLabel: its Text is the count, everything else is children
-- laid out around it (UIPadding pushes the text to the right of the avatar).
local CARD_W, CARD_H = 236, 66
local keysLabel = UIKit.new("TextLabel", {
	Name = "Keys",
	Text = "...",
	FontFace = Face.bold,
	TextSize = 24,
	TextColor3 = Colors.paper,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	BackgroundColor3 = Colors.ink,
	BackgroundTransparency = 0.12,
	AnchorPoint = if isTouch then Vector2.new(1, 0) else Vector2.new(1, 1),
	-- desktop: bottom-right like the reference; touch: top-right, clear of the jump button
	Position = if isTouch then UDim2.new(1, -12, 0, 10) else UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(CARD_W, CARD_H),
	Parent = gui,
}, {
	UIKit.corner(14),
	UIKit.stroke(Colors.paper, 1.5, 0.82),
	UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 92),
		PaddingTop = UDim.new(0, 28),
		PaddingBottom = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 10),
	}),
})
UIKit.fit(keysLabel)
-- children are positioned relative to the padded box (origin at 92, 28)
local avatar = UIKit.new("ImageLabel", {
	Name = "Avatar",
	BackgroundColor3 = Colors.inkSoft,
	Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
	Position = UDim2.fromOffset(-82, -19),
	Size = UDim2.fromOffset(50, 50),
	Parent = keysLabel,
}, { UIKit.corner(25), UIKit.stroke(Colors.cream, 2, 0.2) })
avatar.ZIndex = 2
text({
	Name = "PlayerName",
	Text = player.DisplayName,
	FontFace = Face.semi,
	TextSize = 16,
	TextColor3 = Colors.muted,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(-24, -21),
	Size = UDim2.new(1, 24, 0, 18),
	Parent = keysLabel,
})
local keyIcon = UIKit.icon("key", Colors.gold, 20)
keyIcon.AnchorPoint = Vector2.new(0, 0.5)
keyIcon.Position = UDim2.new(0, -25, 0.5, 0)
keyIcon.Parent = keysLabel
local keyIconScale = UIKit.new("UIScale", { Parent = keyIcon })
local shopBalance: TextLabel? = nil -- the balance chip in the shop header, set up below
local shownKeys = nil

local function keysText(value: number): string
	return string.format("%d %s", value, Config.CurrencyName)
end

-- Count the number up/down to the new value; the key icon pops and the text flashes gold.
local function setKeys(value: number)
	if shopBalance then
		shopBalance.Text = tostring(value)
	end
	if shownKeys == nil then
		shownKeys = value
		keysLabel.Text = keysText(value)
		return
	end
	if value == shownKeys then
		return
	end
	local from = shownKeys
	shownKeys = value
	keyIconScale.Scale = 1.5
	keyIcon.Rotation = -25
	UIKit.tween(keyIconScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 })
	UIKit.tween(keyIcon, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Rotation = 0 })
	keysLabel.TextColor3 = Colors.goldBright
	UIKit.tween(keysLabel, TweenInfo.new(0.8), { TextColor3 = Colors.paper })
	local counter = Instance.new("NumberValue")
	counter.Value = from
	counter.Changed:Connect(function(v)
		keysLabel.Text = keysText(math.round(v))
	end)
	local t = UIKit.tween(counter, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Value = value })
	t.Completed:Connect(function()
		counter:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- Bottom menu: the big cream PICK A DOOR pill (quick join) with a row of ink buttons beneath,
-- after the reference lobby's HOST GAME / STORE bar.
------------------------------------------------------------------------------------------
local MENU_H = 140
local menu = UIKit.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(520, MENU_H),
	Parent = gui,
})
local menuFit = UIKit.fit(menu)

local playButton = UIKit.button("PICK A DOOR", {
	Name = "PickADoor",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(340, 72),
	TextSize = 40,
	ZIndex = 1,
	Parent = menu,
}, { style = "cream", icon = "play", iconSize = 34, radius = 14, depth = 5 })

local buttonRow = UIKit.new("Frame", {
	Name = "Row",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.new(1, 0, 0, 54),
	ZIndex = 2, -- tooltips pop up over the pill
	Parent = menu,
}, {
	UIKit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- name keeps the old convention (caption without spaces: SHOP, LANTERN, HOWTOPLAY, ...)
local function menuButton(caption: string, order: number, icon: string, showText: boolean)
	return UIKit.button(showText and caption or "", {
		Name = (caption:gsub("%s", "")),
		LayoutOrder = order,
		Size = UDim2.fromOffset(showText and 136 or 52, 52),
		TextSize = 24,
		Parent = buttonRow,
	}, {
		style = "ink",
		icon = icon,
		iconSize = showText and 22 or 26,
		radius = 12,
		tooltip = not showText and caption or nil,
	})
end
local shopButton = menuButton("SHOP", 1, "cart", true)
local lanternButton = menuButton("LANTERN", 2, "lantern", false)
local titlesButton = menuButton("TITLES", 3, "medal", false)
local helpButton = menuButton("HOW TO PLAY", 4, "help", false)
local inviteButton = menuButton("INVITE", 5, "invite", false)
local reviveButton = menuButton("REVIVE PASS", 6, "heart", false)

-- while you're queued the big button becomes LEAVE QUEUE
local function refreshPlayButton()
	local queued = player:GetAttribute("QueuedPad") ~= nil
	playButton.Text = queued and "LEAVE QUEUE" or "PICK A DOOR"
	setIcon(playButton, queued and "close" or "play", Colors.ink, queued and 26 or 34)
	playButton:SetAttribute("BaseColor", queued and Colors.creamHot or Colors.cream)
end
player:GetAttributeChangedSignal("QueuedPad"):Connect(refreshPlayButton)
playButton.Activated:Connect(function()
	if player:GetAttribute("QueuedPad") then
		Remotes.get("LeaveQueue"):FireServer()
	else
		Remotes.get("QuickJoin"):FireServer()
	end
end)

------------------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------------------
local shopPanel, shopContent = UIKit.panel(gui, "Shop", UDim2.fromOffset(640, 480))
local lanternPanel, lanternContent = UIKit.panel(gui, "Lanterns", UDim2.fromOffset(720, 480))
local titlesPanel, titlesContent = UIKit.panel(gui, "Titles", UDim2.fromOffset(640, 480))
local panels = { shopPanel, lanternPanel, titlesPanel }

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

-- open (never toggle shut) when a dialogue choice asks for a panel
openShop.Event:Connect(function()
	if not UIKit.isOpen(shopPanel) then
		open(shopPanel)
	end
end)
openLanterns.Event:Connect(function()
	if not UIKit.isOpen(lanternPanel) then
		open(lanternPanel)
	end
end)

-- your balance, in the shop's header next to the close button
do
	local header = shopPanel:FindFirstChild("Header", true)
	if header then
		local chip = UIKit.new("Frame", {
			Name = "Balance",
			BackgroundColor3 = Colors.inkSoft,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -60, 0.5, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			ZIndex = 2,
			Parent = header,
		}, {
			UIKit.corner(17),
			UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }),
			UIKit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local icon = UIKit.icon("key", Colors.gold, 18)
		icon.LayoutOrder = 1
		icon.Parent = chip
		shopBalance = text({
			Name = "Amount",
			Text = shownKeys and tostring(shownKeys) or "...",
			FontFace = Face.bold,
			TextSize = 20,
			TextColor3 = Colors.paper,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 34),
			LayoutOrder = 2,
			Parent = chip,
		})
	end
end

-- A dark rounded tile holding an icon (lantern colour swatches, the revive heart).
local function chip(icon: string, color: Color3, bg: Color3?)
	local tile = UIKit.new("Frame", {
		Name = "Chip",
		BackgroundColor3 = bg or Colors.ink,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
	}, { UIKit.corner(12) })
	local glyph = UIKit.icon(icon, color, 30)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = tile
	return tile
end

local function row(parent: Instance, order: number, height: number, highlight: Color3?)
	local frame = UIKit.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = Colors.paperLight,
		Parent = parent,
	}, {
		UIKit.corner(12),
		UIKit.stroke(highlight or Colors.ink, highlight and 2 or 1.5, highlight and 0.2 or 0.84),
	})
	UIKit.hoverRow(frame)
	return frame
end

local function sectionHeader(parent: Instance, order: number, caption: string)
	local holder = UIKit.new("Frame", {
		Name = "Section",
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = parent,
	})
	text({
		Text = caption,
		FontFace = Face.semi,
		TextSize = 15,
		TextColor3 = Colors.inkMuted,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	return holder
end

local function rowTitle(parent: Instance, caption: string, rightInset: number, y: number?)
	return text({
		Name = "Title",
		Text = caption,
		FontFace = Face.bold,
		TextSize = 22,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(74, y or 10),
		Size = UDim2.new(1, -(74 + rightInset), 0, 28),
		Parent = parent,
	})
end

local function rowBlurb(parent: Instance, caption: string, rightInset: number)
	return text({
		Name = "Blurb",
		Text = caption,
		TextSize = 16,
		TextColor3 = Colors.inkMuted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(74, 40),
		Size = UDim2.new(1, -(74 + rightInset), 0, 22),
		Parent = parent,
	})
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

	sectionHeader(shopList, -20, "GAME PASS")
	local owned = player:GetAttribute("HasRevivePass") == true
	local pass = row(shopList, -19, 76, Colors.accent)
	pass.BackgroundColor3 = Color3.fromRGB(251, 236, 226)
	chip("heart", Colors.paperLight, Colors.accent).Parent = pass
	rowTitle(pass, "REVIVE PASS", 170)
	rowBlurb(pass, "Come back once per trial. Game pass (Robux).", 170)
	local passButton = UIKit.button(owned and "OWNED" or "BUY", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(136, 44),
		Parent = pass,
	}, { style = owned and "muted" or "accent", icon = owned and "check" or nil })
	passButton.Activated:Connect(promptRevivePass)

	-- items: consumables stack to a cap, the laser is a one-time unlock (used from the hotbar, keys 1-4)
	sectionHeader(shopList, -10, "ITEMS")
	for i, def in Items.List do
		local item = row(shopList, -10 + i, 76)
		chip(def.icon, def.color).Parent = item
		rowTitle(item, string.upper(def.name), 180)
		local inventory = data and data.Inventory or {}
		local count = tonumber(inventory[def.id]) or 0
		local unlocked = def.kind == "unlock" and data ~= nil and data.LaserUnlocked == true
		local full = def.kind == "consumable" and count >= def.cap
		local status = if unlocked
			then "OWNED"
			elseif def.kind == "consumable" then string.format("%d/%d owned", count, def.cap)
			else "one-time unlock"
		rowBlurb(item, status .. "  -  " .. def.description, 180) -- status first: the blurb truncates at the end
		local caption = if unlocked then "OWNED" elseif full then "FULL" else tostring(def.price)
		local buy = UIKit.button(caption, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(146, 44),
			Parent = item,
		}, {
			style = if unlocked or full then "muted" else "ink",
			icon = if unlocked then "check" elseif full then nil else "key",
			iconSize = 20,
		})
		buy.Activated:Connect(function()
			if unlocked then
				toast(string.format("You own the %s. Press %d to use it.", def.name, i))
				return
			elseif full then
				toast(string.format("You can't carry more than %d %s.", def.cap, def.name), "error")
				return
			end
			local res = Remotes.get("BuyItem"):InvokeServer(def.id)
			toast(res.message, res.ok and "success" or "error")
		end)
	end

	sectionHeader(shopList, 0, "LANTERNS")
	for i, def in Lanterns.List do
		if def.price > 0 then
			local item = row(shopList, i, 76)
			chip("lantern", def.lightColor).Parent = item
			rowTitle(item, string.upper(def.name), 180)
			rowBlurb(item, def.description, 180)
			local isOwned = data and data.OwnedLanterns[def.id]
			local buy = UIKit.button(isOwned and "OWNED" or tostring(def.price), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(146, 44),
				Parent = item,
			}, { style = isOwned and "muted" or "ink", icon = isOwned and "check" or "key", iconSize = 20 })
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
-- Left column: a viewport with the lantern turning (its flame animated by LanternFX, since particles
-- don't render in viewports) over an info card: rarity pill, description, LIGHT and GLOW meters.
local LanternFX = require(Shared.LanternFX)
local VIEW_W = 272
local VIEW_H = 226
local viewport = UIKit.new("ViewportFrame", {
	Name = "Preview",
	Size = UDim2.fromOffset(VIEW_W, VIEW_H),
	BackgroundColor3 = Color3.fromRGB(44, 31, 25),
	Ambient = Color3.fromRGB(128, 108, 90),
	LightColor = Color3.fromRGB(255, 220, 180),
	LightDirection = Vector3.new(-1, -1, -1),
	Parent = lanternContent,
}, {
	UIKit.corner(12),
	UIKit.stroke(Colors.ink, 2, 0.4),
	-- warm pool of light behind the lantern
	UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 232, 196), Color3.fromRGB(128, 104, 90)),
	}),
})
-- warm vignette over the render: two dark sheets that clear toward the middle (top/bottom, left/right)
for _, rotation in { 90, 0 } do
	UIKit.new("Frame", {
		Name = "Vignette",
		BackgroundColor3 = Color3.fromRGB(22, 11, 6),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = viewport,
	}, {
		UIKit.corner(12),
		UIKit.new("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(0.28, 1),
				NumberSequenceKeypoint.new(0.72, 1),
				NumberSequenceKeypoint.new(1, 0.45),
			}),
		}),
	})
end
local previewCamera = UIKit.new("Camera", { FieldOfView = 40, Parent = viewport })
viewport.CurrentCamera = previewCamera
previewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 1.8, 5.3), Vector3.new(0, 1.42, 0))
local previewName = text({
	Name = "Name",
	Text = "",
	FontFace = Face.bold,
	TextSize = 22,
	TextColor3 = Colors.paper,
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundColor3 = Colors.ink,
	BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -24, 0, 34),
	ZIndex = 2,
	Parent = viewport,
})
UIKit.corner(10).Parent = previewName

-- info card under the viewport
local info = UIKit.new("Frame", {
	Name = "Info",
	BackgroundColor3 = Colors.paperLight,
	Position = UDim2.fromOffset(0, VIEW_H + 10),
	Size = UDim2.new(0, VIEW_W, 1, -(VIEW_H + 10)),
	Parent = lanternContent,
}, { UIKit.corner(12), UIKit.stroke(Colors.ink, 1.5, 0.84) })
local rarityPill = text({
	Name = "Rarity",
	Text = "",
	FontFace = Face.bold,
	TextSize = 12,
	TextColor3 = Colors.paperLight,
	TextXAlignment = Enum.TextXAlignment.Center,
	BackgroundTransparency = 0,
	BackgroundColor3 = Colors.inkMuted,
	AutomaticSize = Enum.AutomaticSize.X,
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(0, 20),
	Parent = info,
})
UIKit.corner(10).Parent = rarityPill
UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }).Parent = rarityPill
local priceNote = text({
	Name = "Price",
	Text = "",
	FontFace = Face.semi,
	TextSize = 13,
	TextColor3 = Colors.inkMuted,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(120, 20),
	Parent = info,
})
local blurb = text({
	Name = "Description",
	Text = "",
	TextSize = 14,
	TextColor3 = Colors.inkSoft,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	Position = UDim2.fromOffset(12, 36),
	Size = UDim2.new(1, -24, 0, 50),
	Parent = info,
})
-- a 5-segment meter: `set(n)` lights the first n segments in the given colour
local METER_SEGMENTS = 5
local function meter(order: number, caption: string)
	local y = 92 + (order - 1) * 22
	text({
		Name = caption,
		Text = caption,
		FontFace = Face.semi,
		TextSize = 12,
		TextColor3 = Colors.inkMuted,
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.fromOffset(48, 16),
		Parent = info,
	})
	local segments = {}
	local segW = (VIEW_W - 24 - 60 - (METER_SEGMENTS - 1) * 4) / METER_SEGMENTS
	for i = 1, METER_SEGMENTS do
		segments[i] = UIKit.new("Frame", {
			Name = "Seg" .. i,
			BackgroundColor3 = Colors.paperDark,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12 + 60 + (i - 1) * (segW + 4), y + 4),
			Size = UDim2.fromOffset(segW, 8),
			Parent = info,
		}, { UIKit.corner(4) })
	end
	return function(lit: number, color: Color3)
		for i, seg in segments do
			seg.BackgroundColor3 = i <= lit and color or Colors.paperDark
		end
	end
end
local setLight = meter(1, "LIGHT")
local setGlow = meter(2, "GLOW")
-- map a stat across the catalog's spread onto 2..5 lit segments, so even the cheapest lantern shows some
local statMin, statMax = {}, {}
for _, key in { "lightRadius", "brightness" } do
	statMin[key], statMax[key] = math.huge, -math.huge
	for _, def in Lanterns.List do
		statMin[key] = math.min(statMin[key], def[key])
		statMax[key] = math.max(statMax[key], def[key])
	end
end
local function segmentsFor(key: string, value: number): number
	local span = statMax[key] - statMin[key]
	local k = span > 0 and (value - statMin[key]) / span or 1
	return 2 + math.round(k * (METER_SEGMENTS - 2))
end

local previewModel: Model? = nil
local stopPreviewFX: (() -> ())? = nil
local function stopPreview()
	if stopPreviewFX then
		stopPreviewFX()
		stopPreviewFX = nil
	end
end
local function preview(id: string)
	stopPreview()
	if previewModel then
		previewModel:Destroy()
	end
	local def = Lanterns.getOrDefault(id)
	previewModel = LanternBuilder.buildModel(id, true)
	previewModel.Parent = viewport
	if lanternPanel.Visible then
		stopPreviewFX = LanternFX.animatePreview(previewModel)
	end
	previewName.Text = string.upper(def.name)
	local rarityColor = Lanterns.rarityColor(def.rarity)
	rarityPill.Text = string.upper(def.rarity)
	rarityPill.BackgroundColor3 = rarityColor
	local owned = data and data.OwnedLanterns[def.id]
	priceNote.Text = if owned
		then (data and data.EquippedLantern == def.id) and "EQUIPPED" or "OWNED"
		else string.format("%d %s", def.price, Config.CurrencyName)
	blurb.Text = def.description
	setLight(segmentsFor("lightRadius", def.lightRadius), Colors.gold)
	setGlow(segmentsFor("brightness", def.brightness), def.lightColor:Lerp(Colors.ink, 0.25))
end

lanternPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if lanternPanel.Visible and data then
		preview(data.EquippedLantern)
	elseif not lanternPanel.Visible then
		stopPreview()
	end
end)

RunService.RenderStepped:Connect(function()
	if previewModel and lanternPanel.Visible then
		previewModel:PivotTo(CFrame.Angles(0, os.clock() * 0.8, 0))
	end
end)

local lanternList = UIKit.scrollList(lanternContent, {
	Position = UDim2.fromOffset(VIEW_W + 16, 0),
	Size = UDim2.new(1, -(VIEW_W + 16), 1, 0),
})

local function buildLanterns()
	for _, child in lanternList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, def in Lanterns.List do
		local owned = data and data.OwnedLanterns[def.id]
		local equipped = data and data.EquippedLantern == def.id
		local item = row(lanternList, i, 70, equipped and Colors.green or nil)
		local rarityColor = Lanterns.rarityColor(def.rarity)
		local tile = chip("lantern", def.lightColor)
		UIKit.stroke(rarityColor, 2, 0).Parent = tile
		tile.Parent = item
		rowTitle(item, string.upper(def.name), 150, 8)
		-- rarity in its colour, and the price while it's still locked
		local sub = rowBlurb(item, "", 150)
		sub.RichText = true
		sub.TextSize = 14
		sub.Position = UDim2.fromOffset(74, 38)
		local rarityText = string.format(
			'<font color="#%s"><b>%s</b></font>',
			rarityColor:Lerp(Colors.ink, 0.2):ToHex(),
			string.upper(def.rarity)
		)
		sub.Text = if owned
			then rarityText
			else string.format("%s  ·  %d %s", rarityText, def.price, Config.CurrencyName)
		local action = UIKit.button(equipped and "EQUIPPED" or owned and "EQUIP" or "LOCKED", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(128, 40),
			TextSize = 18,
			ZIndex = 2,
			Parent = item,
		}, {
			style = equipped and "green" or owned and "ink" or "muted",
			icon = equipped and "check" or not owned and "lock" or nil,
			iconSize = 16,
		})
		-- clicking the row previews; the button equips
		local hit = UIKit.new(
			"TextButton",
			{ Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0), Parent = item }
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

-- Titles ---------------------------------------------------------------------------------
-- Every title in Shared.Titles: earned ones equip (the line under your name on your nameplate),
-- locked ones are greyed with their hint and progress.
local titlesList = UIKit.scrollList(titlesContent)

local function buildTitles()
	for _, child in titlesList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local earnedCount = 0
	for _, def in Titles.List do
		if data and data.Titles and data.Titles[def.id] then
			earnedCount += 1
		end
	end
	sectionHeader(titlesList, 0, string.format("SHOWN ABOVE YOUR HEAD  ·  %d / %d EARNED", earnedCount, #Titles.List))
	for i, def in Titles.List do
		local earned = data ~= nil and data.Titles ~= nil and data.Titles[def.id] == true
		local equipped = data ~= nil and data.EquippedTitle == def.id
		local rarityColor = Titles.color(def)
		local item = row(titlesList, i, 70, equipped and Colors.green or nil)
		-- round badge in the rarity colour (grey while locked), like the one on the nameplate
		local badge =
			chip(def.icon, earned and Colors.paperLight or Colors.muted, earned and rarityColor or Colors.paperDark)
		badge:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 24)
		UIKit.stroke(earned and Colors.gold or Colors.inkMuted, 2, earned and 0.1 or 0.6).Parent = badge
		badge.Parent = item
		local title = rowTitle(item, def.text, 150, 8)
		if not earned then
			title.TextColor3 = Colors.inkMuted
		end
		local sub = rowBlurb(item, "", 150)
		sub.RichText = true
		sub.TextSize = 14
		sub.Position = UDim2.fromOffset(74, 38)
		local rarityText = string.format(
			'<font color="#%s"><b>%s</b></font>',
			rarityColor:Lerp(Colors.ink, 0.2):ToHex(),
			string.upper(def.rarity)
		)
		if earned then
			sub.Text = string.format("%s  ·  %s", rarityText, def.hint)
		else
			local current, target = Titles.progress(def, data)
			sub.Text = string.format("%s  ·  %s (%d / %d)", rarityText, def.hint, current, target)
		end
		local action = UIKit.button(equipped and "EQUIPPED" or earned and "EQUIP" or "LOCKED", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(128, 40),
			TextSize = 18,
			ZIndex = 2,
			Parent = item,
		}, {
			style = equipped and "green" or earned and "ink" or "muted",
			icon = equipped and "check" or not earned and "lock" or nil,
			iconSize = 16,
		})
		action.Activated:Connect(function()
			if equipped then
				return
			elseif not earned then
				toast(string.format("%s is locked. %s", def.text, def.hint), "error")
				return
			end
			local res = Remotes.get("EquipTitle"):InvokeServer(def.id)
			toast(res.message, not res.ok and "error" or nil)
		end)
	end
end

------------------------------------------------------------------------------------------
-- Queue status bar (slides up above the menu while you're on a mat)
------------------------------------------------------------------------------------------
local queueBar = UIKit.new("Frame", {
	Name = "QueueBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 120), -- parked below the screen
	Size = UDim2.fromOffset(470, 64),
	BackgroundColor3 = Colors.ink,
	BackgroundTransparency = 0.06,
	Visible = false,
	Parent = gui,
}, { UIKit.corner(14), UIKit.stroke(Colors.paper, 1.5, 0.82) })
UIKit.fit(queueBar)
-- (must stay the bar's first TextLabel: tests read it)
local queueLabel = text({
	Name = "Status",
	FontFace = Face.semi,
	TextSize = 22,
	TextColor3 = Colors.paper,
	Position = UDim2.fromOffset(26, 0),
	Size = UDim2.new(1, -160, 1, -6),
	Parent = queueBar,
})
UIKit.new("Frame", {
	Name = "Tab",
	BackgroundColor3 = Colors.accent,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(10, 12),
	Size = UDim2.new(0, 5, 1, -24),
	Parent = queueBar,
}, { UIKit.corner(3) })
local timerTrack = UIKit.new("Frame", {
	Name = "Timer",
	BackgroundColor3 = Colors.inkSoft,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 26, 1, -12),
	Size = UDim2.new(1, -160, 0, 4),
	Parent = queueBar,
}, { UIKit.corner(2) })
local timerFill = UIKit.new("Frame", {
	Name = "Fill",
	BackgroundColor3 = Colors.cream,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = timerTrack,
}, { UIKit.corner(2) })
local leaveButton = UIKit.button("LEAVE", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(112, 42),
	Parent = queueBar,
}, { style = "accent", icon = "close", iconSize = 14 })
leaveButton.Activated:Connect(function()
	Remotes.get("LeaveQueue"):FireServer()
end)

local function queueShownOffset(): number
	return -(MENU_H * menuFit.Scale + 30)
end

local function findPad(padName: string): Instance?
	local lobby = workspace:FindFirstChild("Lobby")
	local pads = lobby and lobby:FindFirstChild("Pads")
	return pads and pads:FindFirstChild(padName)
end

task.spawn(function()
	while true do
		local padName = player:GetAttribute("QueuedPad")
		local pad = padName and findPad(padName)
		local queued = pad ~= nil
		if queued ~= (queueBar:GetAttribute("Shown") == true) then
			queueBar:SetAttribute("Shown", queued)
			queueBar.Visible = true
			UIKit.tween(
				queueBar,
				TweenInfo.new(0.35, queued and Enum.EasingStyle.Back or Enum.EasingStyle.Quad),
				{ Position = UDim2.new(0.5, 0, 1, queued and queueShownOffset() or 120) }
			)
		end
		if pad then
			local timeLeft = pad:GetAttribute("TimeLeft") or 0
			queueLabel.Text = string.format(
				"%s   %d/%d   -   door opens in %ds",
				string.upper(tostring(pad:GetAttribute("Mode") or "")),
				pad:GetAttribute("Count") or 0,
				pad:GetAttribute("Capacity") or 0,
				timeLeft
			)
			local frac = math.clamp(timeLeft / math.max(Config.QueueCountdown, 1), 0, 1)
			UIKit.tween(timerFill, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(frac, 1) })
		end
		task.wait(0.2)
	end
end)
UIKit.FitChanged:Connect(function()
	if queueBar:GetAttribute("Shown") then
		queueBar.Position = UDim2.new(0.5, 0, 1, queueShownOffset())
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
	buildTitles()
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
titlesButton.Activated:Connect(function()
	open(titlesPanel)
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
refreshPlayButton()
preview(data and data.EquippedLantern or Lanterns.DefaultId)

-- the bar slides up from the bottom edge, the player card from the side
local menuTarget = menu.Position
menu.Position = menuTarget + UDim2.fromOffset(0, 200)
local cardTarget = keysLabel.Position
keysLabel.Position = cardTarget + UDim2.fromOffset(CARD_W + 40, 0)
task.delay(0.5, function()
	UIKit.tween(menu, TweenInfo.new(0.55, Enum.EasingStyle.Back), { Position = menuTarget })
	task.wait(0.12)
	UIKit.tween(keysLabel, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Position = cardTarget })
end)
