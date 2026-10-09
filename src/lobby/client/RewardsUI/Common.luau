--[[
	Small helpers shared by the reward-station panels (RewardsUI/Daily, Wheel, Challenges) and the
	coordinator (Rewards.client). Pure UI building blocks: no state, no remotes except the Studio-only
	debug button.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Remotes = require(Shared.Remotes)
local UIKit = require(Shared.UIKit)

local Colors, Face = UIKit.Colors, UIKit.Face

local Common = {}

Common.Colors = Colors
Common.Face = Face
Common.CURRENCY = Config.CurrencyName
Common.IS_STUDIO = RunService:IsStudio()
Common.BRASS = Colors.gold
Common.BRASS_DARK = Color3.fromRGB(150, 112, 56)
Common.BRASS_LIGHT = Color3.fromRGB(240, 206, 140)

-- A TextLabel with the panels' defaults (transparent, body face, ink, left aligned).
function Common.text(props: { [string]: any }): TextLabel
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

function Common.circle(): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- Recolour a UIKit.icon (its pieces are frames, strokes and the odd label).
function Common.tint(icon: Instance, color: Color3)
	for _, d in icon:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundColor3 = color
		elseif d:IsA("UIStroke") then
			d.Color = color
		elseif d:IsA("TextLabel") then
			d.TextColor3 = color
		end
	end
end

local function buttonContent(button: GuiButton): Instance?
	local face = button:FindFirstChild("Face")
	return face and face:FindFirstChild("Content")
end

-- Swap (or remove, with nil) the icon inside a UIKit.button's face.
function Common.setIcon(button: GuiButton, name: string?, color: Color3, size: number)
	local content = buttonContent(button)
	if not content then
		return
	end
	local old = content:FindFirstChild("Icon")
	if old then
		old:Destroy()
	end
	if name then
		local icon = UIKit.icon(name, color, size)
		icon.LayoutOrder = 1
		icon.Parent = content
	end
end

-- Restyle a UIKit.button in place (face via the BaseColor attribute UIKit.animate listens to).
function Common.paint(button: GuiButton, styleName: string)
	local style = UIKit.Styles[styleName] or UIKit.Styles.ink
	button:SetAttribute("BaseColor", style.face)
	local face = button:FindFirstChild("Face")
	local stroke = face and face:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.trim
	end
	local content = buttonContent(button)
	local label = content and content:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = style.text
	end
	local icon = content and content:FindFirstChild("Icon")
	if icon then
		Common.tint(icon, style.text)
	end
end

-- Set a button's caption, style and icon in one go (icon colour follows the style's text colour).
function Common.restyle(button: GuiButton, caption: string, styleName: string, icon: string?, iconSize: number?)
	local style = UIKit.Styles[styleName] or UIKit.Styles.ink
	button.Text = caption
	Common.setIcon(button, icon, style.text, iconSize or 20)
	Common.paint(button, styleName)
end

function Common.itemName(id: string): string
	local def = Items.get(id)
	return def and def.name or id
end

-- Small muted Studio-only debug button (fires RewardsDebug with `action`: nextDay, skipDay, resetDay,
-- resetAll). Returns nil outside Studio.
function Common.debugButton(
	parent: Instance,
	caption: string,
	action: string,
	position: UDim2,
	anchor: Vector2?
): GuiButton?
	if not Common.IS_STUDIO then
		return nil
	end
	local button = UIKit.button(caption, {
		Name = "Debug_" .. action,
		AnchorPoint = anchor or Vector2.new(0, 0),
		Position = position,
		Size = UDim2.fromOffset(124, 28),
		TextSize = 13,
		ZIndex = 20,
		Parent = parent,
	}, { style = "muted", radius = 8, depth = 2, tooltip = "Studio only" })
	button.Activated:Connect(function()
		Remotes.get("RewardsDebug"):FireServer(action)
	end)
	return button
end

return Common
