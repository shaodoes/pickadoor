--[[
	The trial's door sequence, one timeline shared by the server (DoorRoomFlow: commits, swings the leaf,
	places the player in their world) and the committing player's client (DoorRoom.client.luau: the
	first-person hand, the breath, the step into the black).

	A player commits by walking into a door's Zone during Pick. The server then fires that player alone
	(DoorEvent "commit") with { door, color, mode, world, t0, stepAt } (server times). All times below are
	seconds after t0.

	  mode "open"     the first player at a closed door: look down, the hand reaches and grips the
	                  handle, the handle turns, the leaf swings (server, LEAF_AT), the camera rises
	  mode "breathe"  the door is already open (or opening): stop, look down, breathe, look back up
	  then the step   from stepAt: walk through the opening into the black (fade over STEP_LEN), and
	                  the server places the player at their world's Arrive at stepAt + STEP_LEN + SETTLE

	Nobody in a Zone when Pick runs out: DoorEvent "glitch" { t0 }, the room tears apart around them for
	GLITCH_LEN seconds, then the server kills them.
]]
local DoorPick = {}

-- mode "open"
DoorPick.LOOK_DOWN = 0.55 -- camera tilts down to the handle while the player steps up to it
DoorPick.GRIP = 1.25 -- the hand closes on the handle
DoorPick.TURN = 1.6 -- the handle is down; the latch clicks
DoorPick.LEAF_AT = 1.65 -- the server starts swinging the leaf
DoorPick.SWING_TIME = 1.25 -- leaf swing duration (server tween)
DoorPick.RISE = 2.75 -- the camera starts back up as the black opens in front of it
DoorPick.OPEN_LEN = 3.4 -- end of the opening; the step follows

-- mode "breathe"
DoorPick.BREATHE_LEN = 2.7

-- the step into the black (both modes)
DoorPick.STEP_LEN = 1.2 -- walking in; the screen is fully black by its end
DoorPick.FADE_TIME = 0.5 -- the last FADE_TIME of the step fades to black
DoorPick.SETTLE = 0.2 -- a beat of black before the server moves the character

-- the glitch-out for nobody at a door when Pick ends
DoorPick.GLITCH_LEN = 2.4

-- the door is opening or open from this time on: a later arrival breathes until the leaf is mostly open
function DoorPick.openDoneAt(t0: number): number
	return t0 + DoorPick.LEAF_AT + DoorPick.SWING_TIME * 0.8
end

-- the server time at which the player is placed in their world
function DoorPick.enterAt(stepAt: number): number
	return stepAt + DoorPick.STEP_LEN + DoorPick.SETTLE
end

return DoorPick
