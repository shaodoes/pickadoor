--[[
	Reward station: the Wheel of Fate panel ("WheelPanel").

	  * A big wheel on the left: one gradient-shaded wedge per Shared.Rewards.Wheel segment with its icon and
	    label, a brass rim with RIM_LIGHTS bulbs (slow twinkle at rest, a fast chase while spinning, a blink
	    in the prize colour on a win), a brass hub and a pointer at 12 o'clock that flicks on every segment
	    boundary that passes under it.
	  * The side column: spins available + live countdown to the next free spin, banked spins, a pulsing
	    SPIN button, BUY A SPIN (Rewards.SpinCost Keys), and an odds table / last-win card toggle.
	  * Spins: SpinWheel remote (the server rolls). The UI wheel turns from its own rest angle by
	    Rewards.spinTravel over Rewards.SpinDuration from the server's start time with Rewards.spinEase,
	    exactly like the 3D wheel (StationFX), so both land on the same segment at the same moment. The
	    playback runs on its own RenderStepped connection (it always finishes and toasts, even with the
	    panel closed); all looping dressing runs in shell.group (only while the panel is open).
	  * Rest-angle sync with workspace.Lobby.Stations.WheelStation (SpinIndex / SpinOffset), at startup and
	    whenever the panel opens while idle.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rewards = require(Shared:WaitForChild("Rewards"))
local Sfx = require(Shared:WaitForChild("Sfx"))
local UIFx = require(Shared:WaitForChild("UIFx"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Common = require(script.Parent:WaitForChild("Common"))
local Shell = require(script.Parent:WaitForChild("Shell"))

local Colors, Face = UIKit.Colors, UIKit.Face
local text, circle = Common.text, Common.circle
local CURRENCY = Common.CURRENCY
local BRASS, BRASS_DARK, BRASS_LIGHT = Common.BRASS, Common.BRASS_DARK, Common.BRASS_LIGHT

local ACCENT = Rewards.Stations.Wheel.color
local VIOLET_DEEP = Color3.fromRGB(122, 64, 186)
local CARD = Color3.fromRGB(24, 27, 36)
local CARD_LIGHT = Color3.fromRGB(38, 43, 56)
local BULB = Color3.fromRGB(255, 236, 190)
local READY = Color3.fromRGB(150, 206, 140)
local OFF_FACE = Color3.fromRGB(46, 50, 62)
local BUY_FACE = Color3.fromRGB(56, 62, 78)

-- Wheel geometry (design px). Wedges are isosceles triangles, each split into two right triangles: a frame
-- whose UIGradient has a hard transparency edge along its diagonal (UIGradient rotates in pixel space, so
-- the angle comes from the box's aspect). Each segment is SUBS narrow wedges so the gap between the chord
-- and the rim stays ~2 px, hidden under a dark ring line and the brass rim. Everything that turns lives in
-- the Rotor; GuiObject.Rotation is clockwise and inherited by children.
local WHEEL = 420 -- outer diameter (brass rim included)
local RO = WHEEL / 2 -- outer radius
local RS = RO - 18 -- segment radius (the rim band shows outside it)
local HUB = 84
local SEG = Rewards.SegmentAngle
local SUBS = 2 -- wedges per segment
local RIM_LIGHTS = 20
local STAGE_W = 450

local HARD_EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.505, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local KIND_ICON = { keys = "key", item = "pills", spin = "play", lantern = "lantern" }
local ITEM_ICON = { speed_pills = "pills", bandage = "bandage", lockpicks = "lockpick", laser = "laser" }

local function segmentIcon(seg: Rewards.Segment): string
	if seg.kind == "item" and seg.item and ITEM_ICON[seg.item] then
		return ITEM_ICON[seg.item]
	end
	return seg.icon or KIND_ICON[seg.kind] or "key"
end

local function segmentName(seg: Rewards.Segment): string
	if seg.kind == "keys" then
		return string.format("%d %s", seg.amount, CURRENCY)
	elseif seg.kind == "item" then
		return Common.itemName(seg.item :: string)
	elseif seg.kind == "spin" then
		return "Free spin"
	end
	return "Lantern"
end

-- One half of a downward-pointing isosceles triangle (apex at the bottom inner corner).
local function triangleHalf(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, right: boolean)
	local f = UIKit.new("Frame", {
		Name = "Tri",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Parent = parent,
	})
	local angle = math.deg(math.atan(w / h))
	-- right half keeps its upper-left triangle, left half its upper-right one
	UIKit.new("UIGradient", {
		Rotation = if right then angle else 180 - angle,
		Transparency = HARD_EDGE,
		Parent = f,
	})
	return f
end

-- A wedge of the wheel centred on `centerDeg` (clockwise from 12 o'clock), `halfDeg` either side.
local function wedge(parent: Instance, centerDeg: number, halfDeg: number, radius: number, color: Color3, z: number)
	local holder = UIKit.new("Frame", {
		Name = "Wedge",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		Rotation = centerDeg,
		ZIndex = z,
		Parent = parent,
	})
	local h = radius * math.cos(math.rad(halfDeg))
	local hw = radius * math.sin(math.rad(halfDeg))
	local top = radius - h
	local tris = {
		triangleHalf(holder, radius - hw, top, hw, h, color, false),
		triangleHalf(holder, radius, top, hw, h, color, true),
	}
	-- a seam filler down the middle (the two halves meet on a fractional pixel)
	table.insert(
		tris,
		UIKit.new("Frame", {
			Name = "Seam",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(radius - 1, top + 2),
			Size = UDim2.fromOffset(2, h - HUB / 2),
			Parent = holder,
		})
	)
	for _, t in tris do
		t.ZIndex = z
	end
	return holder, tris
end

-- A frame of the wheel's size rotated to `deg`, for things placed along a radius.
local function spoke(parent: Instance, deg: number, z: number): Frame
	return UIKit.new("Frame", {
		Name = "Spoke",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL, WHEEL),
		Rotation = deg,
		ZIndex = z,
		Parent = parent,
	})
end

-- A ring: a transparent circle whose stroke (drawn outside the frame) covers radius `inner`..`inner + width`.
local function ring(parent: Instance, inner: number, width: number, color: Color3, alpha: number, z: number): Frame
	return UIKit.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(inner * 2, inner * 2),
		ZIndex = z,
		Parent = parent,
	}, { circle(), UIKit.stroke(color, width, alpha) })
end

local function disc(parent: Instance, radius: number, color: Color3, alpha: number, z: number): Frame
	return UIKit.new("Frame", {
		Name = "Disc",
		BackgroundColor3 = color,
		BackgroundTransparency = alpha,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		ZIndex = z,
		Parent = parent,
	}, { circle() })
end

local function card(props: { [string]: any }): Frame
	local merged = {
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.new("Frame", merged, {
		UIKit.corner(14),
		UIKit.stroke(ACCENT, 1.5, 0.72),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 180, 176)),
		}),
	})
end

-- Recolour a UIKit.button in place with any face/text colours (Common.paint only knows UIKit.Styles).
local function setButton(
	button: GuiButton,
	caption: string,
	faceColor: Color3,
	textColor: Color3,
	icon: string?,
	size: number?
)
	if button.Text ~= caption then
		button.Text = caption
	end
	if button:GetAttribute("IconName") ~= (icon or "") or button:GetAttribute("IconColor") ~= textColor then
		button:SetAttribute("IconName", icon or "")
		button:SetAttribute("IconColor", textColor)
		Common.setIcon(button, icon, textColor, size or 20)
	end
	button:SetAttribute("BaseColor", faceColor)
	local face = button:FindFirstChild("Face")
	local stroke = face and face:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = faceColor:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	local content = face and face:FindFirstChild("Content")
	local label = content and content:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextColor3 = textColor
	end
end

local Wheel = {}

function Wheel.build(ctx: any)
	local snapshot: any = ctx.getSnapshot()

	local shell = Shell.new(ctx.gui, {
		name = "WheelPanel",
		title = "Wheel of Fate",
		subtitle = "One free spin every day",
		accent = ACCENT,
		size = Vector2.new(900, 560),
		icon = "play",
		balance = true,
	})
	local content: Frame = shell.content
	local group = shell.group

	--------------------------------------------------------------------------------------
	-- The wheel
	--------------------------------------------------------------------------------------
	local stage = UIKit.new("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, STAGE_W, 1, 0),
		Parent = content,
	})
	-- violet halo behind it (breathes slowly, brightens while spinning)
	local halo = UIKit.new("Frame", {
		Name = "Halo",
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WHEEL + 34, WHEEL + 34),
		ZIndex = 1,
		Parent = stage,
	}, {
		circle(),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(1, 0.3),
			}),
		}),
	})

	local wheelHolder = UIKit.new("Frame", {
		Name = "Wheel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.fromOffset(WHEEL, WHEEL),
		ZIndex = 2,
		Parent = stage,
	})
	UIKit.shadow(wheelHolder, 999, 8, 1)

	-- brass rim: a full brass disc behind the segments, top-lit, with a dark outer edge
	UIKit.new("Frame", {
		Name = "Rim",
		BackgroundColor3 = BRASS,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = wheelHolder,
	}, {
		circle(),
		UIKit.stroke(Colors.shadow, 2.5, 0.15),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, BRASS_LIGHT),
				ColorSequenceKeypoint.new(0.5, BRASS),
				ColorSequenceKeypoint.new(1, BRASS_DARK),
			}),
		}),
	})
	-- a slow highlight travelling round the rim (the idle shimmer)
	local rimShine = ring(wheelHolder, RO - 3, 3, Color3.new(1, 1, 1), 0, 2)
	UIFx.spinGradient(
		rimShine:FindFirstChildOfClass("UIStroke") :: UIStroke,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, BRASS_LIGHT),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, BRASS_LIGHT),
		}),
		group,
		24,
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.58, 0.9),
			NumberSequenceKeypoint.new(1, 1),
		})
	)

	local rotor = UIKit.new("Frame", {
		Name = "Rotor",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = wheelHolder,
	})

	local glowTris: { { Frame } } = {} -- per segment: the cream overlay that throbs on a win
	local segLabelScales: { UIScale } = {}
	local half = SEG / SUBS / 2
	for i, seg in Rewards.Wheel do
		local center = (i - 1) * SEG
		local fill = seg.color:Lerp(Color3.new(1, 1, 1), 0.1)
		glowTris[i] = {}
		for k = 1, SUBS do
			local subCenter = center - SEG / 2 + (k - 0.5) * SEG / SUBS
			-- a hair of overlap between the sub-wedges of one segment hides their seam
			wedge(rotor, subCenter, half + 0.35, RS, fill, 1)
			local _, tris = wedge(rotor, subCenter, half + 0.35, RS, Colors.paperLight, 3)
			for _, t in tris do
				t.BackgroundTransparency = 1
				table.insert(glowTris[i], t)
			end
		end
		-- icon near the rim and the label inside it, upright along the radius
		local arm = spoke(rotor, center, 5)
		local icon =
			UIKit.icon(segmentIcon(seg), if seg.kind == "keys" then Colors.goldBright else Colors.paperLight, 30)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromOffset(RO, RO - RS * 0.8)
		icon.ZIndex = 5
		icon.Parent = arm
		local labelRadius = RS * 0.58
		local labelWidth = 2 * labelRadius * math.tan(math.rad(SEG / 2)) * 0.95
		local label = text({
			Name = "Label",
			Text = seg.label,
			FontFace = Face.bold,
			TextScaled = true,
			TextColor3 = Colors.paperLight,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeColor3 = Colors.shadow,
			TextStrokeTransparency = 0.45,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(RO, RO - labelRadius),
			Size = UDim2.fromOffset(labelWidth, 24),
			ZIndex = 5,
			Parent = arm,
		})
		UIKit.new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 9, Parent = label })
		segLabelScales[i] = UIKit.new("UIScale", { Parent = label })
	end

	-- radial shading (rotation-invariant, so it can turn with the rotor): darker towards the rim, a soft
	-- lamp-lit glow towards the hub
	ring(rotor, RS - 14, 14, Colors.shadow, 0.68, 2)
	ring(rotor, RS - 30, 16, Colors.shadow, 0.86, 2)
	disc(rotor, RS * 0.62, Colors.paperLight, 0.94, 2)
	disc(rotor, RS * 0.42, Colors.paperLight, 0.93, 2)

	-- brass dividers at every boundary
	for i = 1, #Rewards.Wheel do
		local arm = spoke(rotor, (i - 1) * SEG + SEG / 2, 4)
		UIKit.new("Frame", {
			Name = "Divider",
			BackgroundColor3 = BRASS,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(RO, RO - RS),
			Size = UDim2.fromOffset(3, RS - HUB / 2 + 4),
			ZIndex = 4,
			Parent = arm,
		}, { UIKit.stroke(BRASS_DARK, 1, 0.4) })
	end

	-- hub: a brass knob with a keyhole and a violet gem ring (it turns with the wheel)
	local hub = UIKit.new("Frame", {
		Name = "Hub",
		BackgroundColor3 = BRASS,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(HUB, HUB),
		ZIndex = 6,
		Parent = rotor,
	}, {
		circle(),
		UIKit.stroke(Colors.shadow, 2, 0.2),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BRASS_LIGHT, BRASS_DARK) }),
	})
	UIKit.new("Frame", {
		Name = "Boss",
		BackgroundColor3 = VIOLET_DEEP,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(HUB - 24, HUB - 24),
		ZIndex = 6,
		Parent = hub,
	}, {
		circle(),
		UIKit.stroke(BRASS_LIGHT, 2, 0.2),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT, Color3.fromRGB(64, 30, 104)) }),
	})
	UIKit.new("Frame", {
		Name = "KeyholeTop",
		BackgroundColor3 = Colors.shadow,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -5),
		Size = UDim2.fromOffset(13, 13),
		ZIndex = 7,
		Parent = hub,
	}, { circle() })
	UIKit.new("Frame", {
		Name = "KeyholeSlot",
		BackgroundColor3 = Colors.shadow,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, -2),
		Size = UDim2.fromOffset(6, 15),
		ZIndex = 7,
		Parent = hub,
	}, { UIKit.corner(2) })

	-- static dressing over the rotor: a dark line where the segments meet the rim, and a lamp-lit sheen
	ring(wheelHolder, RS - 3, 3, Colors.shadow, 0.2, 4)
	UIKit.new("Frame", {
		Name = "Sheen",
		BackgroundColor3 = Color3.fromRGB(255, 240, 214),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RS * 2 - 6, RS * 2 - 6),
		ZIndex = 5,
		Parent = wheelHolder,
	}, {
		circle(),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.78),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	-- rim lights: bulbs on the brass band, each with a soft halo
	local lightsFrame = UIKit.new("Frame", {
		Name = "Lights",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = wheelHolder,
	})
	local bulbs: { Frame } = {}
	local bulbHalos: { Frame } = {}
	local lightRadius = (RO + RS) / 2
	for i = 1, RIM_LIGHTS do
		local a = math.rad((i - 1) * 360 / RIM_LIGHTS + 360 / RIM_LIGHTS / 2)
		local pos = UDim2.fromOffset(RO + lightRadius * math.sin(a), RO - lightRadius * math.cos(a))
		bulbHalos[i] = UIKit.new("Frame", {
			Name = "Halo",
			BackgroundColor3 = BULB,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(22, 22),
			ZIndex = 6,
			Parent = lightsFrame,
		}, { circle() })
		bulbs[i] = UIKit.new("Frame", {
			Name = "Bulb",
			BackgroundColor3 = BULB,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(10, 10),
			ZIndex = 7,
			Parent = lightsFrame,
		}, { circle(), UIKit.stroke(BRASS_DARK, 1, 0.2) })
	end

	local function setBulbColor(color: Color3)
		for i = 1, RIM_LIGHTS do
			bulbs[i].BackgroundColor3 = color
			bulbHalos[i].BackgroundColor3 = color
		end
	end

	-- the pointer at 12 o'clock: its frame is centred on the brass cap so Rotation pivots there
	local pointer = UIKit.new("Frame", {
		Name = "Pointer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(44, 88),
		ZIndex = 8,
		Parent = wheelHolder,
	})
	UIKit.new("Frame", {
		Name = "Diamond",
		BackgroundColor3 = Colors.goldBright,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, 60),
		Size = UDim2.fromOffset(26, 26),
		Rotation = 45,
		ZIndex = 8,
		Parent = pointer,
	}, {
		UIKit.corner(4),
		UIKit.stroke(Colors.shadow, 2, 0.15),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Colors.paperLight, BRASS_DARK) }),
	})
	UIKit.new("Frame", {
		Name = "Stem",
		BackgroundColor3 = BRASS,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(22, 44),
		Size = UDim2.fromOffset(8, 14),
		ZIndex = 8,
		Parent = pointer,
	}, { UIKit.stroke(Colors.shadow, 1.5, 0.3) })
	local cap = UIKit.new("Frame", {
		Name = "Cap",
		BackgroundColor3 = BRASS,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, 44),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 9,
		Parent = pointer,
	}, {
		circle(),
		UIKit.stroke(Colors.shadow, 2, 0.15),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(BRASS_LIGHT, BRASS_DARK) }),
	})
	UIKit.new("Frame", {
		Name = "Gem",
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(11, 11),
		ZIndex = 9,
		Parent = cap,
	}, { circle(), UIKit.stroke(Colors.paperLight, 1, 0.5) })

	--------------------------------------------------------------------------------------
	-- Wheel state
	--------------------------------------------------------------------------------------
	local wheelAngle = 0 -- the rotor's resting rotation (degrees, 0..360)
	local spinning = false
	local spinVel = 0 -- deg/s while a spin plays (drives the rim chase)
	local pointerAngle, pointerVel = 0, 0
	local winIndex, winAt = 0, -math.huge
	local openedAt = -math.huge
	local chase = 0

	local function setWheelAngle(angle: number)
		wheelAngle = angle % 360
		rotor.Rotation = wheelAngle
	end

	-- the pointer is a damped spring: a flick kicks it, it settles by itself (no tweens, no allocations)
	local function stepPointer(dt: number)
		local step = math.min(dt, 1 / 30)
		local accel = -900 * pointerAngle - 24 * pointerVel
		pointerVel += accel * step
		pointerAngle += pointerVel * step
		if math.abs(pointerAngle) < 0.02 and math.abs(pointerVel) < 0.5 then
			pointerAngle, pointerVel = 0, 0
		end
		pointer.Rotation = pointerAngle
	end

	local function flickPointer()
		pointerAngle = math.max(math.min(pointerAngle, 0) - 20, -30)
		pointerVel = -80
		pointer.Rotation = pointerAngle
	end

	local function clearGlow()
		winIndex = 0
		for _, tris in glowTris do
			for _, t in tris do
				t.BackgroundTransparency = 1
			end
		end
		for _, s in segLabelScales do
			s.Scale = 1
		end
	end

	--------------------------------------------------------------------------------------
	-- Side column
	--------------------------------------------------------------------------------------
	local SIDE_X = STAGE_W + 18
	local side = UIKit.new("Frame", {
		Name = "Side",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDE_X, 0),
		Size = UDim2.new(1, -SIDE_X, 1, 0),
		Parent = content,
	})

	-- spins + free-spin status
	local statusCard = card({
		Name = "Status",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 104),
		Parent = side,
	})
	local spinsCount = text({
		Name = "Count",
		Text = "-",
		FontFace = Face.bold,
		TextSize = 60,
		TextColor3 = Colors.goldBright,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 52, 0.5, 0),
		Size = UDim2.fromOffset(84, 96),
		Parent = statusCard,
	})
	local spinsCaption = text({
		Name = "Caption",
		Text = "SPINS AVAILABLE",
		FontFace = Face.bold,
		TextSize = 21,
		TextColor3 = Colors.paper,
		Position = UDim2.fromOffset(104, 14),
		Size = UDim2.new(1, -116, 0, 26),
		Parent = statusCard,
	})
	local freeDot = UIKit.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = READY,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(104, 55),
		Size = UDim2.fromOffset(9, 9),
		Parent = statusCard,
	}, { circle() })
	local freeStatus = text({
		Name = "Free",
		Text = "",
		FontFace = Face.semi,
		TextSize = 16,
		TextColor3 = Colors.muted,
		Position = UDim2.fromOffset(120, 45),
		Size = UDim2.new(1, -132, 0, 20),
		Parent = statusCard,
	})
	local bankedLabel = text({
		Name = "Banked",
		Text = "",
		FontFace = Face.body,
		TextSize = 15,
		TextColor3 = Colors.muted,
		Position = UDim2.fromOffset(104, 70),
		Size = UDim2.new(1, -116, 0, 20),
		Parent = statusCard,
	})

	-- the SPIN button (in a holder so its pulse doesn't fight the button's own hover UIScale)
	local spinHolder = UIKit.new("Frame", {
		Name = "SpinHolder",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 64),
		Parent = side,
	})
	local spinButton = UIKit.button("SPIN", {
		Name = "Spin",
		Size = UDim2.fromScale(1, 1),
		TextSize = 30,
		Parent = spinHolder,
	}, { style = "accent", icon = "play", iconSize = 26, radius = 16, depth = 4 })
	local spinFace = spinButton:FindFirstChild("Face") :: Frame

	local buyHolder = UIKit.new("Frame", {
		Name = "BuyHolder",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 194),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = side,
	})
	local BUY_CAPTION = string.format("BUY A SPIN — %d %s", Rewards.SpinCost, string.upper(CURRENCY))
	local buyButton = UIKit.button(BUY_CAPTION, {
		Name = "BuySpin",
		Size = UDim2.fromScale(1, 1),
		TextSize = 19,
		Parent = buyHolder,
	}, { style = "ink", icon = "key", iconSize = 20, radius = 12, depth = 3 })

	-- view toggle: ODDS | LAST WIN, with a sliding indicator
	local tabs = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 254),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = side,
	}, { UIKit.corner(16), UIKit.stroke(ACCENT, 1, 0.8) })
	local indicator = UIKit.new("Frame", {
		Name = "Indicator",
		BackgroundColor3 = VIOLET_DEEP,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(0.5, -6, 1, -6),
		Parent = tabs,
	}, {
		UIKit.corner(13),
		UIKit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT, VIOLET_DEEP) }),
	})
	local function tabButton(caption: string, x: number): TextButton
		return UIKit.new("TextButton", {
			Name = "Tab",
			Text = caption,
			FontFace = Face.bold,
			TextSize = 15,
			TextColor3 = Colors.paperLight,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(0.5, 1),
			ZIndex = 2,
			Parent = tabs,
		})
	end
	local oddsTab = tabButton("ODDS", 0)
	local resultTab = tabButton("LAST WIN", 0.5)

	local VIEW_Y = 298
	local view = UIKit.new("Frame", {
		Name = "View",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, VIEW_Y),
		Size = UDim2.new(1, 0, 1, -VIEW_Y),
		Parent = side,
	})

	-- odds table: two columns of rows, each with a bar sized by its odds
	local oddsCard = card({
		Name = "Odds",
		Size = UDim2.fromScale(1, 1),
		Parent = view,
	})
	local oddsRows: { GuiObject } = {}
	local odds = Rewards.odds()
	local maxOdds = 0
	for _, p in odds do
		maxOdds = math.max(maxOdds, p)
	end
	local rowsPerColumn = math.ceil(#Rewards.Wheel / 2)
	for i, seg in Rewards.Wheel do
		local col = (i - 1) // rowsPerColumn
		local rowIndex = (i - 1) % rowsPerColumn
		local row = UIKit.new("Frame", {
			Name = "Row" .. i,
			BackgroundColor3 = CARD_LIGHT,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Position = UDim2.new(col * 0.5, if col == 0 then 10 else 4, 0, 10 + rowIndex * 28),
			Size = UDim2.new(0.5, -14, 0, 24),
			Parent = oddsCard,
		}, { UIKit.corner(7) })
		UIKit.new("Frame", {
			Name = "Bar",
			BackgroundColor3 = seg.color:Lerp(ACCENT, 0.25),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(math.clamp(odds[i] / maxOdds, 0.08, 1), 1),
			Parent = row,
		}, { UIKit.corner(7) })
		local icon = UIKit.icon(segmentIcon(seg), if seg.kind == "keys" then Colors.goldBright else Colors.paper, 14)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 6, 0.5, 0)
		icon.ZIndex = 2
		icon.Parent = row
		text({
			Name = "Name",
			Text = segmentName(seg),
			FontFace = Face.body,
			TextSize = 14,
			TextColor3 = Colors.paperLight,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(26, 0),
			Size = UDim2.new(1, -68, 1, 0),
			ZIndex = 2,
			Parent = row,
		})
		text({
			Name = "Odds",
			Text = string.format("%d%%", math.round(odds[i])),
			FontFace = Face.bold,
			TextSize = 14,
			TextColor3 = Colors.goldBright,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 40, 1, 0),
			ZIndex = 2,
			Parent = row,
		})
		table.insert(oddsRows, row)
	end

	-- result card (a small CanvasGroup so it can fade in)
	local resultCard = UIKit.new("CanvasGroup", {
		Name = "Result",
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = view,
	}, {
		UIKit.corner(14),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 180, 176)),
		}),
	})
	local resultStroke = UIKit.stroke(ACCENT, 2, 0.6)
	resultStroke.Parent = resultCard
	local resultTile = UIKit.new("Frame", {
		Name = "Tile",
		BackgroundColor3 = VIOLET_DEEP,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(78, 78),
		Parent = resultCard,
	}, {
		UIKit.corner(16),
		UIKit.stroke(BRASS_LIGHT, 2, 0.35),
		UIKit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 110, 120)),
		}),
	})
	local resultCaption = text({
		Name = "Caption",
		Text = "THE WHEEL SAYS",
		FontFace = Face.semi,
		TextSize = 15,
		TextColor3 = ACCENT,
		Position = UDim2.fromOffset(110, 16),
		Size = UDim2.new(1, -124, 0, 18),
		Parent = resultCard,
	})
	local resultPrize = text({
		Name = "Prize",
		Text = "?",
		FontFace = Face.bold,
		TextSize = 32,
		TextColor3 = Colors.paperLight,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(110, 36),
		Size = UDim2.new(1, -124, 0, 38),
		Parent = resultCard,
	})
	local resultText = text({
		Name = "Text",
		Text = "Spin it and see what fate keeps in the drawer.",
		FontFace = Face.body,
		TextSize = 15,
		TextColor3 = Colors.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(110, 78),
		Size = UDim2.new(1, -124, 1, -86),
		Parent = resultCard,
	})
	local function setResultIcon(name: string, color: Color3)
		local old = resultTile:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		local icon = UIKit.icon(name, color, 42)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = resultTile
	end
	setResultIcon("help", Colors.goldBright)

	--------------------------------------------------------------------------------------
	-- View toggle
	--------------------------------------------------------------------------------------
	local viewMode = "odds"
	local rowRevealOpts = { offset = Vector2.new(18, 0), scale = 0.9 }
	local function setView(mode: string, animate: boolean)
		viewMode = mode
		local isOdds = mode == "odds"
		oddsCard.Visible = isOdds
		resultCard.Visible = not isOdds
		oddsTab.TextColor3 = if isOdds then Colors.paperLight else Colors.muted
		resultTab.TextColor3 = if isOdds then Colors.muted else Colors.paperLight
		local goal = if isOdds then UDim2.fromOffset(3, 3) else UDim2.new(0.5, 3, 0, 3)
		if animate then
			UIFx.tween(indicator, UIFx.Info.smooth, { Position = goal })
			if isOdds then
				UIFx.stagger(oddsRows, 0.03, rowRevealOpts)
			else
				UIFx.reveal(resultCard, { scale = 0.85, offset = Vector2.new(0, 12) })
			end
		else
			indicator.Position = goal
		end
	end
	setView("odds", false)
	oddsTab.Activated:Connect(function()
		if viewMode ~= "odds" then
			Sfx.play("Click")
			setView("odds", true)
		end
	end)
	resultTab.Activated:Connect(function()
		if viewMode ~= "result" then
			Sfx.play("Click")
			setView("result", true)
		end
	end)

	--------------------------------------------------------------------------------------
	-- Side state
	--------------------------------------------------------------------------------------
	local stopPulse: (() -> ())? = nil
	local stopShine: (() -> ())? = nil
	local lastAvailable: number? = nil
	local balanceHeld = false
	local balanceShown = false

	local function pushBalance()
		if snapshot then
			shell:setBalance(tonumber(snapshot.Keys) or 0, balanceShown)
			balanceShown = true
		end
	end

	local function releaseBalance()
		if balanceHeld then
			balanceHeld = false
			pushBalance()
		end
	end

	local function setInviting(on: boolean)
		if on and not stopPulse then
			stopPulse = UIFx.pulse(spinHolder, group, 0.035, 1.3)
			stopShine = UIFx.shine(spinFace, group, { period = 2.6 })
		elseif not on and stopPulse then
			stopPulse()
			stopPulse = nil
			if stopShine then
				stopShine()
				stopShine = nil
			end
		end
	end

	local function updateFreeStatus()
		if not snapshot then
			freeStatus.Text = ""
			freeDot.Visible = false
		elseif Rewards.freeSpinReady(snapshot.Spins) then
			freeStatus.Text = "Free spin ready!"
			freeStatus.TextColor3 = READY
			freeDot.Visible = true
		else
			freeStatus.Text = "Next free spin in " .. Rewards.formatDuration(Rewards.secondsToNextDay())
			freeStatus.TextColor3 = Colors.muted
			freeDot.Visible = false
		end
	end

	local function updateSide()
		local spins = snapshot and snapshot.Spins
		local available = if snapshot then Rewards.spinsAvailable(spins) else 0
		local free = snapshot ~= nil and Rewards.freeSpinReady(spins)
		local keys = snapshot and tonumber(snapshot.Keys) or 0
		local banked = if type(spins) == "table" then tonumber(spins.extra) or 0 else 0
		spinsCount.Text = if snapshot then tostring(available) else "-"
		spinsCount.TextColor3 = if available > 0 then Colors.goldBright else Colors.muted
		spinsCaption.Text = if available == 1 then "SPIN AVAILABLE" else "SPINS AVAILABLE"
		bankedLabel.Text = if snapshot then string.format("Banked spins: %d", banked) else ""
		if lastAvailable ~= nil and lastAvailable ~= available and UIKit.isOpen(shell.frame) then
			UIFx.reveal(spinsCount, { offset = Vector2.new(0, 0), scale = 1.5, duration = 0.35 })
		end
		lastAvailable = if snapshot then available else nil
		updateFreeStatus()
		if spinning then
			setButton(spinButton, "SPINNING...", OFF_FACE, Colors.muted, nil)
		elseif available > 0 then
			setButton(spinButton, if free then "SPIN  (FREE)" else "SPIN", VIOLET_DEEP, Colors.paperLight, "play", 26)
		else
			setButton(spinButton, "NO SPINS LEFT", OFF_FACE, Colors.muted, nil)
		end
		setInviting(not spinning and available > 0)
		local canBuy = snapshot ~= nil and not spinning and keys >= Rewards.SpinCost
		setButton(
			buyButton,
			BUY_CAPTION,
			if canBuy then BUY_FACE else OFF_FACE,
			if canBuy then Colors.goldBright else Colors.muted,
			"key",
			20
		)
		if not balanceHeld then
			pushBalance()
		end
	end

	--------------------------------------------------------------------------------------
	-- Spinning
	--------------------------------------------------------------------------------------
	local confettiOpts = { count = 36, colors = { ACCENT, Colors.goldBright, Colors.paperLight }, duration = 2.2 }
	local burstOpts = { count = 20, colors = { Colors.goldBright, Colors.paperLight, ACCENT }, spread = 120 }
	local function prizeFormat(n: number): string
		return string.format("+%d %s", math.round(n), string.upper(CURRENCY))
	end

	-- the wheel has landed on `index` with the server's `res`: show it (always), celebrate (if open)
	local function finishSpin(res: any, index: number)
		spinning = false
		spinVel = 0
		local reward = type(res.reward) == "table" and res.reward or {}
		local message = tostring(reward.text or res.message or "")
		local seg = Rewards.Wheel[index]
		local isKeys = reward.kind == "keys"
		local amount = math.floor(tonumber(reward.amount) or 0)

		resultCaption.Text = "YOU WON"
		resultText.Text = message
		resultPrize.Text = if isKeys then prizeFormat(amount) else string.upper(segmentName(seg))
		resultTile.BackgroundColor3 = seg.color:Lerp(Color3.new(1, 1, 1), 0.12)
		setResultIcon(segmentIcon(seg), if isKeys then Colors.goldBright else Colors.paperLight)
		resultStroke.Color = seg.color:Lerp(Colors.goldBright, 0.5)
		resultStroke.Transparency = 0.05

		winIndex = index
		winAt = os.clock()
		setBulbColor(seg.color:Lerp(Color3.new(1, 1, 1), 0.45))

		local open = UIKit.isOpen(shell.frame)
		setView("result", false)
		if open then
			Sfx.play("WheelWin", 0.02)
			shell:shake(7, 0.4)
			shell:flash(seg.color:Lerp(Color3.new(1, 1, 1), 0.3), 0.45)
			confettiOpts.colors[3] = seg.color:Lerp(Color3.new(1, 1, 1), 0.3)
			UIFx.confetti(shell.frame, confettiOpts)
			UIFx.burst(wheelHolder, UDim2.new(0.5, 0, 0, 14), burstOpts)
			UIFx.tween(indicator, UIFx.Info.smooth, { Position = UDim2.new(0.5, 3, 0, 3) })
			UIFx.reveal(resultCard, { scale = 0.6, offset = Vector2.new(0, 16), duration = 0.5 })
			task.delay(0.18, function()
				UIFx.stamp(resultTile)
			end)
			UIFx.tween(resultStroke, TweenInfo.new(1.8), { Transparency = 0.6 })
			if isKeys and amount > 0 then
				UIFx.countUp(resultPrize, 0, amount, 0.9, prizeFormat)
				UIFx.flyUp(
					wheelHolder,
					UDim2.fromScale(0.5, 0.32),
					"+" .. amount,
					{ icon = "key", color = Colors.goldBright }
				)
				local target = shell:balanceTarget()
				if target then
					balanceHeld = true
					UIFx.flyTo(shell.frame, resultTile, target, {
						count = math.clamp(amount // 25, 4, 10),
						icon = "key",
						color = Colors.goldBright,
						onArrive = releaseBalance,
					})
					task.delay(1.8, releaseBalance)
				end
			end
		else
			resultStroke.Transparency = 0.6
		end
		ctx.toast(message, "success")
		updateSide()
	end

	local spinConn: RBXScriptConnection? = nil

	-- Animate the UI wheel to the server's result, in step with the 3D wheel (same start time and curve).
	local function playSpin(res: any)
		local index = math.clamp(math.floor(tonumber(res.index) or 1), 1, #Rewards.Wheel)
		local offset = tonumber(res.offset) or 0
		local start = tonumber(res.start) or workspace:GetServerTimeNow()
		local from = wheelAngle
		local travel = Rewards.spinTravel(from, index, offset)
		local lastBoundary = math.floor((from - SEG / 2) / SEG)
		local lastTick = 0
		local lastAngle = from
		clearGlow()
		setBulbColor(BULB)
		resultCaption.Text = "THE WHEEL SAYS"
		resultPrize.Text = "..."
		resultText.Text = "The wheel is turning..."
		resultTile.BackgroundColor3 = VIOLET_DEEP
		setResultIcon("help", Colors.goldBright)

		if spinConn then
			spinConn:Disconnect()
		end
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function(dt: number)
			local elapsed = workspace:GetServerTimeNow() - start
			local alpha = math.clamp(elapsed / Rewards.SpinDuration, 0, 1)
			local angle = from + travel * Rewards.spinEase(alpha)
			rotor.Rotation = angle % 360
			if dt > 0 then
				spinVel = (angle - lastAngle) / dt
			end
			lastAngle = angle
			-- a boundary is under the pointer whenever the rotation is a half segment off a centre
			local boundary = math.floor((angle - SEG / 2) / SEG)
			if boundary ~= lastBoundary then
				lastBoundary = boundary
				local now = os.clock()
				if UIKit.isOpen(shell.frame) and now - lastTick > 0.04 then
					lastTick = now
					Sfx.play("WheelTick", 0.05)
					flickPointer()
				end
			end
			stepPointer(dt)
			if alpha < 1 then
				return
			end
			conn:Disconnect()
			if spinConn == conn then
				spinConn = nil
			end
			setWheelAngle(from + travel)
			finishSpin(res, index)
		end)
		spinConn = conn
	end

	local function spin(buy: boolean)
		if spinning or not snapshot then
			return
		end
		if buy then
			if (tonumber(snapshot.Keys) or 0) < Rewards.SpinCost then
				ctx.toast(string.format("A spin costs %d %s.", Rewards.SpinCost, CURRENCY), "error")
				return
			end
		elseif Rewards.spinsAvailable(snapshot.Spins) <= 0 then
			ctx.toast(
				string.format(
					"No spins left. Buy one for %d %s, or come back in %s.",
					Rewards.SpinCost,
					CURRENCY,
					Rewards.formatDuration(Rewards.secondsToNextDay())
				),
				"error"
			)
			return
		end
		spinning = true
		updateSide()
		local ok, res = pcall(function()
			return Remotes.get("SpinWheel"):InvokeServer(buy)
		end)
		if not ok or type(res) ~= "table" or not res.ok then
			spinning = false
			updateSide()
			ctx.toast(type(res) == "table" and tostring(res.message) or "The wheel is stuck. Try again.", "error")
			return
		end
		playSpin(res)
	end

	spinButton.Activated:Connect(function()
		spin(false)
	end)
	buyButton.Activated:Connect(function()
		spin(true)
	end)

	--------------------------------------------------------------------------------------
	-- Rest-angle sync with the 3D wheel (workspace.Lobby.Stations.WheelStation)
	--------------------------------------------------------------------------------------
	local station: Instance? = nil
	local function syncRest()
		local model = station
		if spinning or not model or not model.Parent then
			return
		end
		local index = model:GetAttribute("SpinIndex")
		if type(index) ~= "number" then
			return
		end
		-- someone else's spin still turning in the hall: leave ours where it is for now
		local started = tonumber(model:GetAttribute("SpinStart"))
		if started and workspace:GetServerTimeNow() < started + Rewards.SpinDuration then
			return
		end
		setWheelAngle(Rewards.restAngle(index, tonumber(model:GetAttribute("SpinOffset")) or 0))
	end
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		local folder = lobby and lobby:WaitForChild("Stations", 30)
		local model = folder and folder:WaitForChild("WheelStation", 30)
		if not model then
			return
		end
		station = model
		syncRest()
		-- another player's spin: once it has landed, follow it while our panel is closed
		model:GetAttributeChangedSignal("SpinSeq"):Connect(function()
			task.defer(function()
				if model:GetAttribute("SpinBy") == Players.LocalPlayer.UserId then
					return
				end
				local started = tonumber(model:GetAttribute("SpinStart")) or workspace:GetServerTimeNow()
				local remaining = started + Rewards.SpinDuration - workspace:GetServerTimeNow()
				task.delay(math.max(remaining, 0) + 0.05, function()
					if not UIKit.isOpen(shell.frame) then
						syncRest()
					end
				end)
			end)
		end)
	end)

	--------------------------------------------------------------------------------------
	-- Looping dressing (only while open): rim lights, halo, winning segment throb, pointer settle
	--------------------------------------------------------------------------------------
	group:add(function(t: number, dt: number)
		local now = os.clock()
		local sinceOpen = now - openedAt
		local sinceWin = now - winAt
		if spinning then
			chase = (chase + dt * (6 + math.abs(spinVel) * 0.035)) % RIM_LIGHTS
		end
		for i = 1, RIM_LIGHTS do
			local b
			if spinning then
				local d = (chase - (i - 1)) % RIM_LIGHTS
				b = if d < 4 then 1 - d / 4 else 0.06
			elseif sinceWin < 2.6 then
				b = if (i + math.floor(sinceWin * 8)) % 2 == 0 then 1 else 0.15
			else
				b = 0.5 + 0.35 * math.sin(t * 1.1 + i * 2.3)
			end
			-- wake-up: the bulbs come on one after another as the panel opens
			b *= math.clamp(sinceOpen * 26 - i, 0, 1)
			bulbs[i].BackgroundTransparency = 0.72 * (1 - b)
			bulbHalos[i].BackgroundTransparency = 1 - 0.5 * b
		end

		halo.BackgroundTransparency = if spinning then 0.55 + 0.08 * math.sin(t * 9) else 0.8 + 0.05 * math.sin(t * 0.7)

		if winIndex > 0 then
			local alpha, scale
			if sinceWin < 1.5 then
				local wave = math.abs(math.sin(sinceWin * math.pi * 2))
				alpha = 0.85 - 0.45 * wave
				scale = 1 + 0.28 * wave
			else
				local wave = (math.sin(sinceWin * 3) + 1) / 2
				alpha = 0.86 - 0.12 * wave
				scale = 1 + 0.08 * wave
			end
			for _, tri in glowTris[winIndex] do
				tri.BackgroundTransparency = alpha
			end
			segLabelScales[winIndex].Scale = scale
		end

		if not spinning and (pointerAngle ~= 0 or pointerVel ~= 0) then
			stepPointer(dt)
		end
	end)

	shell:onOpened(function()
		openedAt = os.clock()
		syncRest()
		local scale = UIFx.scaleOf(wheelHolder)
		scale.Scale = 0.84
		UIFx.tween(scale, UIFx.Info.springSoft, { Scale = 1 })
		wheelHolder.Rotation = -14
		UIFx.tween(wheelHolder, UIFx.Info.springSoft, { Rotation = 0 })
		UIFx.stagger({ statusCard, spinHolder, buyHolder, tabs, view }, 0.06, { delay = 0.08 })
		if viewMode == "odds" then
			UIFx.stagger(oddsRows, 0.03, { delay = 0.3, offset = Vector2.new(18, 0), scale = 0.9 })
		end
	end)

	--------------------------------------------------------------------------------------
	-- StationUI
	--------------------------------------------------------------------------------------
	local function update(data: any?)
		snapshot = if data ~= nil then data else ctx.getSnapshot()
		updateSide()
	end

	update(snapshot)

	return {
		panel = shell.frame,
		update = update,
		tick = updateFreeStatus,
	}
end

return Wheel
