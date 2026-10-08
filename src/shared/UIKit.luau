-- Small helpers for code-built UI with the library look (dark wood, brass trim, serif type).
-- Buttons get hover/press animation and sounds; panels pop open and closed; toasts slide in.
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Sfx)

local UIKit = {}

UIKit.Colors = {
	bg = Color3.fromRGB(20, 13, 10),
	panel = Color3.fromRGB(34, 23, 17),
	panelLight = Color3.fromRGB(54, 37, 27),
	gold = Color3.fromRGB(201, 160, 90),
	goldBright = Color3.fromRGB(255, 214, 140),
	text = Color3.fromRGB(240, 226, 200),
	muted = Color3.fromRGB(168, 146, 120),
	red = Color3.fromRGB(150, 45, 40),
	green = Color3.fromRGB(70, 120, 72),
}

UIKit.Fonts = {
	title = Enum.Font.Garamond,
	body = Enum.Font.Garamond,
	ui = Enum.Font.Oswald,
}

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function tween(inst: Instance, info: TweenInfo, goal: { [string]: any })
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end
UIKit.tween = tween

function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(radius: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function UIKit.stroke(color: Color3?, thickness: number?)
	return UIKit.new("UIStroke", {
		Color = color or UIKit.Colors.gold,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(px: number)
	local u = UDim.new(0, px)
	return UIKit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

-- Subtle top-lit wood sheen for panels and buttons.
function UIKit.sheen()
	return UIKit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 220), Color3.fromRGB(170, 150, 130)),
	})
end

function UIKit.label(props: { [string]: any })
	local merged = {
		BackgroundTransparency = 1,
		Font = UIKit.Fonts.body,
		TextColor3 = UIKit.Colors.text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("TextLabel", merged)
end

-- Hover: grows a touch, brightens, brass trim lights up, soft tick. Press: squashes. Click: sound.
function UIKit.animate(button: GuiButton, baseColor: Color3?)
	local scale = button:FindFirstChildOfClass("UIScale") or UIKit.new("UIScale", { Parent = button })
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local strokeColor = stroke and stroke.Color
	local color = baseColor or button.BackgroundColor3
	button.AutoButtonColor = false
	local hovering = false

	local function rest()
		tween(scale, FAST, { Scale = hovering and 1.05 or 1 })
		tween(button, FAST, { BackgroundColor3 = hovering and color:Lerp(UIKit.Colors.gold, 0.18) or color })
		if stroke then
			tween(stroke, FAST, { Color = hovering and UIKit.Colors.goldBright or strokeColor })
		end
	end
	button.MouseEnter:Connect(function()
		hovering = true
		Sfx.play("Hover", 0.08)
		rest()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		rest()
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, FAST, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(rest)
	button.Activated:Connect(function()
		Sfx.play("Click")
	end)
	-- callers that recolor a button (owned/equipped states) update the resting colour here
	button:GetAttributeChangedSignal("BaseColor"):Connect(function()
		color = button:GetAttribute("BaseColor")
		rest()
	end)
	return button
end

function UIKit.button(text: string, props: { [string]: any }?)
	local merged = {
		Text = text,
		Font = UIKit.Fonts.ui,
		TextSize = 20,
		TextColor3 = UIKit.Colors.text,
		BackgroundColor3 = UIKit.Colors.panelLight,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(150, 44),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local button = UIKit.new("TextButton", merged, { UIKit.corner(6), UIKit.stroke(), UIKit.sheen() })
	return UIKit.animate(button)
end

-- Panels -------------------------------------------------------------------------------------
local panelScales: { [Frame]: UIScale } = {}

function UIKit.isOpen(panel: Frame): boolean
	return panel:GetAttribute("Open") == true
end

function UIKit.show(panel: Frame)
	if UIKit.isOpen(panel) then
		return
	end
	panel:SetAttribute("Open", true)
	local scale = panelScales[panel]
	scale.Scale = 0.88
	panel.Visible = true
	tween(scale, POP, { Scale = 1 })
	Sfx.play("PanelOpen", 0.04)
end

function UIKit.hide(panel: Frame)
	if not UIKit.isOpen(panel) then
		return
	end
	panel:SetAttribute("Open", false)
	Sfx.play("PanelClose", 0.04)
	local t = tween(panelScales[panel], SHUT, { Scale = 0.9 })
	t.Completed:Connect(function()
		if not UIKit.isOpen(panel) then
			panel.Visible = false
		end
	end)
end

function UIKit.toggle(panel: Frame)
	if UIKit.isOpen(panel) then
		UIKit.hide(panel)
	else
		UIKit.show(panel)
	end
end

-- Centered modal panel. Returns the frame and the content area beneath its title bar.
-- Open/close it with UIKit.show / UIKit.hide / UIKit.toggle so it animates.
function UIKit.panel(parent: Instance, title: string, size: UDim2)
	local frame = UIKit.new("Frame", {
		Name = title .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = UIKit.Colors.panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = parent,
	}, { UIKit.corner(10), UIKit.stroke(UIKit.Colors.gold, 2), UIKit.sheen() })
	panelScales[frame] = UIKit.new("UIScale", { Parent = frame })
	frame:SetAttribute("Open", false)

	-- inner brass rule under the title, like a bookplate
	UIKit.new("Frame", {
		Name = "Rule",
		BackgroundColor3 = UIKit.Colors.gold,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 56),
		Size = UDim2.new(1, -48, 0, 1),
		Parent = frame,
	})
	UIKit.label({
		Name = "Title",
		Text = string.upper(title),
		Font = UIKit.Fonts.title,
		TextSize = 34,
		TextColor3 = UIKit.Colors.gold,
		Position = UDim2.fromOffset(24, 10),
		Size = UDim2.new(1, -80, 0, 44),
		Parent = frame,
	})

	local close = UIKit.button("X", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(36, 36),
		Parent = frame,
	})
	close.Activated:Connect(function()
		UIKit.hide(frame)
	end)

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 68),
		Size = UDim2.new(1, -40, 1, -88),
		Parent = frame,
	})
	return frame, content
end

function UIKit.scrollList(parent: Instance, props: { [string]: any }?)
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.gold,
		Parent = parent,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return UIKit.new("ScrollingFrame", merged, {
		UIKit.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
	})
end

-- Make a list row light up gently under the mouse.
function UIKit.hoverRow(row: GuiObject)
	local base = row.BackgroundTransparency
	row.MouseEnter:Connect(function()
		tween(row, FAST, { BackgroundTransparency = math.max(base - 0.2, 0) })
	end)
	row.MouseLeave:Connect(function()
		tween(row, FAST, { BackgroundTransparency = base })
	end)
end

-- Toasts ---------------------------------------------------------------------------------------
local toastHolder: Frame? = nil

-- kind: nil (neutral), "error" (red trim + buzz) or "success" (green trim + chime)
function UIKit.toast(screenGui: ScreenGui, text: string, kind: string?)
	if not toastHolder or toastHolder.Parent ~= screenGui then
		toastHolder = UIKit.new("Frame", {
			Name = "Toasts",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(520, 300),
			Parent = screenGui,
		}, {
			UIKit.new("UIListLayout", {
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end
	local trim = kind == "error" and UIKit.Colors.red or kind == "success" and UIKit.Colors.green or UIKit.Colors.gold
	if kind == "error" then
		Sfx.play("Error")
	elseif kind == "success" then
		Sfx.play("Purchase", 0.02)
	end

	-- the holder animates a wrapper so the list layout doesn't fight the slide
	local wrapper = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(500, 0),
		Parent = toastHolder,
	})
	local label = UIKit.label({
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(500, 40),
		Position = UDim2.fromOffset(0, -16),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		BackgroundColor3 = UIKit.Colors.bg,
		Parent = wrapper,
	})
	UIKit.corner(6).Parent = label
	local stroke = UIKit.stroke(trim, 1)
	stroke.Transparency = 1
	stroke.Parent = label
	UIKit.padding(8).Parent = label
	local slide = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween(label, slide, { Position = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.1, TextTransparency = 0 })
	tween(stroke, slide, { Transparency = 0 })
	task.delay(3.5, function()
		local fade = TweenInfo.new(0.5)
		tween(label, fade, { TextTransparency = 1, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -10) })
		tween(stroke, fade, { Transparency = 1 })
		task.wait(0.55)
		wrapper:Destroy()
	end)
end

return UIKit
