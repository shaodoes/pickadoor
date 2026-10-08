-- Small helpers for code-built UI with the library look (dark wood, brass trim, serif type).
local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Colors = {
	bg = Color3.fromRGB(20, 13, 10),
	panel = Color3.fromRGB(34, 23, 17),
	panelLight = Color3.fromRGB(54, 37, 27),
	gold = Color3.fromRGB(201, 160, 90),
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

function UIKit.button(text: string, props: { [string]: any }?)
	local merged = {
		Text = text,
		Font = UIKit.Fonts.ui,
		TextSize = 20,
		TextColor3 = UIKit.Colors.text,
		BackgroundColor3 = UIKit.Colors.panelLight,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(150, 44),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return UIKit.new("TextButton", merged, { UIKit.corner(6), UIKit.stroke() })
end

-- Centered modal panel. Returns the frame and the content area beneath its title bar.
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
	}, { UIKit.corner(10), UIKit.stroke(UIKit.Colors.gold, 2) })

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
		frame.Visible = false
	end)

	local content = UIKit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 64),
		Size = UDim2.new(1, -40, 1, -84),
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
	})
end

local toastHolder: Frame? = nil

function UIKit.toast(screenGui: ScreenGui, text: string)
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
	local label = UIKit.label({
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(500, 40),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = UIKit.Colors.bg,
		Parent = toastHolder,
	})
	UIKit.corner(6).Parent = label
	UIKit.stroke(UIKit.Colors.gold, 1).Parent = label
	UIKit.padding(8).Parent = label
	task.delay(3.5, function()
		local info = TweenInfo.new(0.6)
		TweenService:Create(label, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		label:Destroy()
	end)
end

return UIKit
