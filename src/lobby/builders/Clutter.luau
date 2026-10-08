--[[
	Paper clutter shared by the rooms: loose sheets on the floor (some with handwriting), notes taped
	to walls, and a pinned notice. Sheets are only laid where the floor is clear (blocked rects).
]]
local Kit = require(script.Parent.Kit)

local box = Kit.box
local DETAIL = Kit.DETAIL

local Clutter = {}

local INK = Color3.fromRGB(40, 34, 30)
Clutter.INK = INK
Clutter.NOTES = {
	"it was behind the green door",
	"DON'T COUNT THE DOORS",
	"day 4. the clock went backwards again",
	"they can hear the mats",
	"if it hums, RUN",
	"bring a lantern. always.",
	"I picked the left one. I'm still here?",
	"the water outside isn't water",
	"ask the librarian about the ladder",
	"10 seconds is not enough",
	"no exit no exit no exit",
	"she says the red one is kind. she lies.",
	"QUIET PLEASE",
	"overdue since 1987",
}
local noteIndex = 0
local function nextNote(): string
	noteIndex = noteIndex % #Clutter.NOTES + 1
	return Clutter.NOTES[noteIndex]
end

function Clutter.paperColor(): Color3
	return Color3.fromRGB(200, 194, 178):Lerp(Color3.fromRGB(172, 162, 136), Kit.rng:NextNumber())
end

-- Handwriting on one face of a sheet.
function Clutter.scribble(part: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 1
	gui.MaxDistance = 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.08, 0.08)
	label.Size = UDim2.fromScale(0.84, 0.84)
	label.Font = Enum.Font.IndieFlower
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = INK
	label.Text = text
	label.Rotation = Kit.rng:NextNumber(-6, 6)
	label.Parent = gui
end

local function insideAny(x: number, z: number, rects): boolean
	for _, r in rects do
		if x > r[1] and x < r[2] and z > r[3] and z < r[4] then
			return true
		end
	end
	return false
end

-- Scatter `count` sheets over the rectangle {x0,x1,z0,z1} at floor height y, skipping `blocked`
-- rects ({x0,x1,z0,z1} each). `trail` (optional) biases sheets toward a line from a to b.
function Clutter.papers(parent: Instance, area, y: number, count: number, blocked, trail: { Vector3 }?)
	local rng = Kit.rng
	for i = 1, count do
		local x, z
		if trail and i % 2 == 0 then
			local t = rng:NextNumber()
			local p = trail[1]:Lerp(trail[2], t)
			x, z = p.X + rng:NextNumber(-4, 4), p.Z + rng:NextNumber(-3, 3)
		else
			x, z = rng:NextNumber(area[1] + 1.5, area[2] - 1.5), rng:NextNumber(area[3] + 1.5, area[4] - 1.5)
		end
		if not insideAny(x, z, blocked or {}) then
			local cf = CFrame.new(x, y + 0.05, z)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-2, 2)))
			local paper = box(
				parent,
				"Paper",
				Vector3.new(1.0, 0.02, 1.35),
				cf,
				Clutter.paperColor(),
				Enum.Material.SmoothPlastic,
				DETAIL
			)
			if rng:NextNumber() < 0.16 then
				Clutter.scribble(paper, Enum.NormalId.Top, nextNote())
			end
		end
	end
end

-- A sheet taped to a wall. `pos` is on the wall surface, `normal` points into the room.
function Clutter.wallNote(parent: Instance, pos: Vector3, normal: Vector3, text: string?)
	local rng = Kit.rng
	local cf = CFrame.lookAt(pos + normal * 0.03, pos + normal * 2)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8)))
	local sheet =
		box(parent, "Note", Vector3.new(1.1, 1.45, 0.02), cf, Clutter.paperColor(), Enum.Material.SmoothPlastic, DETAIL)
	box(
		parent,
		"Tape",
		Vector3.new(0.5, 0.18, 0.025),
		cf * CFrame.new(0, 0.68, -0.01) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-12, 12))),
		Color3.fromRGB(230, 220, 170),
		Enum.Material.SmoothPlastic,
		{
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}
	)
	if text ~= "" then
		Clutter.scribble(sheet, Enum.NormalId.Front, text or nextNote())
	end
	return sheet
end

-- A cluster of notes on a wall around `pos` (reference: papers stuck all over the walls).
function Clutter.noteCluster(parent: Instance, pos: Vector3, normal: Vector3, count: number)
	local rng = Kit.rng
	local right = normal:Cross(Vector3.yAxis).Unit
	for i = 1, count do
		local offset = right * rng:NextNumber(-2.2, 2.2) + Vector3.new(0, rng:NextNumber(-1.2, 1.2), 0)
		Clutter.wallNote(parent, pos + offset + normal * (i * 0.004), normal, (i % 2 == 0) and "" or nil)
	end
end

return Clutter
