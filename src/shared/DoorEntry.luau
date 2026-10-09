--[[
	The door-entry sequence (a queue pad's countdown hit zero and the party walks through its door).
	One timeline shared by the server (QueueService: walks the party in, waits, teleports), every client's
	DoorFX (door swing, light, fog, slam: what onlookers see) and the party's DoorCutscene (camera + titles).

	Signalling (attributes only, no remotes):
	  pad    Launching      true for the whole launch (as before)
	  pad    CutsceneStart  workspace:GetServerTimeNow() at which t = 0 (set a little ahead: LEAD)
	  player CutscenePad    name of the pad whose cutscene this player is in; cleared by the server when
	                        it's over (after the mock eject, a failed teleport, or the post-teleport timeout)
	  player CutsceneSlot   1-based walk order inside the party;  pad CutsceneCount = party size

	All times below are seconds after CutsceneStart.
]]
local DoorEntry = {}

DoorEntry.LEAD = 0.35 -- the server schedules t = 0 this far ahead so every client starts in step

-- shot 1: push in over the party while the door creaks open
DoorEntry.OPEN_START = 0.15
DoorEntry.OPEN_CREAK = 0.75 -- end of the hesitant first creak
DoorEntry.OPEN_END = 1.75
-- shot 2: low side angle, the party walks in one after another
DoorEntry.SHOT2 = 2.0
DoorEntry.WALK_START = 2.15
DoorEntry.WALK_GAP = 0.4
DoorEntry.WALK_SPEED = 10
-- shot 3: the empty doorway; the light gutters, the door slams, black
DoorEntry.SHOT3 = 4.5
DoorEntry.GUTTER = 4.6
DoorEntry.SLAM = 5.3
DoorEntry.SLAM_TIME = 0.12
DoorEntry.BLACK = 5.6
DoorEntry.TITLE = 5.75
DoorEntry.LENGTH = 7.0 -- the server waits this long after t = 0 before teleporting

DoorEntry.OPEN_ANGLE = math.rad(100) -- DoorFX's countdown rattle tops out at 32 degrees
local CREAK_ANGLE = math.rad(22)

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function outBack(a: number): number
	a = math.clamp(a, 0, 1)
	local c1 = 1.4
	local c3 = c1 + 1
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end

-- How far open the leaf is (radians, positive = open into the room) at time t.
function DoorEntry.doorAngle(t: number): number
	if t < DoorEntry.OPEN_START then
		return 0
	elseif t < DoorEntry.OPEN_CREAK then
		-- a reluctant first creak
		return CREAK_ANGLE * smooth((t - DoorEntry.OPEN_START) / (DoorEntry.OPEN_CREAK - DoorEntry.OPEN_START))
	elseif t < DoorEntry.OPEN_END then
		-- then it swings the rest of the way and settles past its stop
		local a = (t - DoorEntry.OPEN_CREAK) / (DoorEntry.OPEN_END - DoorEntry.OPEN_CREAK)
		return CREAK_ANGLE + (DoorEntry.OPEN_ANGLE - CREAK_ANGLE) * outBack(a)
	elseif t < DoorEntry.SLAM then
		-- hangs open, drifting a hair
		return DoorEntry.OPEN_ANGLE + math.sin((t - DoorEntry.OPEN_END) * 1.7) * math.rad(1.2)
	elseif t < DoorEntry.SLAM + DoorEntry.SLAM_TIME then
		local a = (t - DoorEntry.SLAM) / DoorEntry.SLAM_TIME
		return DoorEntry.OPEN_ANGLE * (1 - a * a) -- accelerates shut
	elseif t < DoorEntry.SLAM + DoorEntry.SLAM_TIME + 0.3 then
		-- bounces off the frame once
		local a = (t - DoorEntry.SLAM - DoorEntry.SLAM_TIME) / 0.3
		return math.rad(4) * math.sin(a * math.pi) * (1 - a)
	end
	return 0
end

-- 0..1: how much light pours out of the doorway. `seed` decorrelates doors' flicker.
function DoorEntry.light(t: number, seed: number?): number
	local s = seed or 0
	if t < DoorEntry.OPEN_START then
		return 0
	elseif t < DoorEntry.OPEN_END then
		return smooth((t - DoorEntry.OPEN_START) / (DoorEntry.OPEN_END - DoorEntry.OPEN_START))
	elseif t < DoorEntry.GUTTER then
		return 0.92 + math.noise(t * 3, s) * 0.16
	elseif t < DoorEntry.SLAM then
		-- guttering: hard drop-outs that come more often as it dies
		local a = (t - DoorEntry.GUTTER) / (DoorEntry.SLAM - DoorEntry.GUTTER)
		local n = math.noise(t * 18, s, 0.5)
		if n < -0.15 + a * 0.5 then
			return 0.05
		end
		return (1 - a * 0.65) * (0.8 + n * 0.4)
	end
	return 0
end

-- The door's frame: centre of the opening at floor level, +Z pointing out into the room, X along the wall.
-- Built from the leaf's Hinge (the left edge of the leaf, 2.6 studs from the centre, 4.6 up).
function DoorEntry.frame(pad: Instance): CFrame
	local leaf = pad:FindFirstChild("Leaf")
	local hinge = leaf and leaf:GetAttribute("Hinge")
	if typeof(hinge) ~= "CFrame" then
		local exit = pad:FindFirstChild("Exit") :: BasePart?
		hinge = CFrame.new((exit and exit.Position or Vector3.zero) + Vector3.new(-2.6, 1.6, -15))
	end
	return (hinge :: CFrame) * CFrame.new(2.6, -4.6, -0.15)
end

-- Where walker `slot` of `count` goes: straight at the door, through the opening, a few steps into the black.
-- The passage behind each door is 5.4 wide and ~3.9 deep; the slots fan out across it.
function DoorEntry.walkPoints(pad: Instance, slot: number, count: number): { Vector3 }
	local f = DoorEntry.frame(pad)
	local spread = if count > 1 then (slot - (count + 1) / 2) * (2.8 / (count - 1)) else 0
	return {
		f:PointToWorldSpace(Vector3.new(spread * 0.35, 0, 2.2)),
		f:PointToWorldSpace(Vector3.new(spread * 0.6, 0, -0.9)),
		f:PointToWorldSpace(Vector3.new(spread, 0, -2.75)),
	}
end

function DoorEntry.walkStart(slot: number): number
	return DoorEntry.WALK_START + (slot - 1) * DoorEntry.WALK_GAP
end

-- True once a point is through the opening (past the door line, inside the passage).
function DoorEntry.inside(pad: Instance, position: Vector3, margin: number?): boolean
	local rel = DoorEntry.frame(pad):PointToObjectSpace(position)
	return rel.Z < -(margin or 0.6) and math.abs(rel.X) < 3 and rel.Z > -4.5 and rel.Y > -2 and rel.Y < 10
end

return DoorEntry
