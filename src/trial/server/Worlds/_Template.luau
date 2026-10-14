--[[
	_Template: the copy-me world server module (see builders/Worlds/_Template.luau for the three-file
	contract and WorldHost.luau for everything ctx offers).

	  start(ctx) -> controller {
	      steps = { Objectives.Step }?,  -- danger worlds: 2-3 steps; the exit opens after the last one
	      reset(), roundStart(), escalate(level), onEnter(player)?, onClientEvent(player, kind, ...)?, stop()
	  }

	Rules of thumb: hurt players with ctx.damage / ctx.kill (DoorRoomFlow handles death, revives and
	spectating); pay only through ctx.escape / ctx.pay / ctx.collect; every sound cue the client plays
	gets a ctx.caption line; keep per-round state in locals that reset() clears; entities come from
	ctx.Stalker.start(model, { home, isTarget = ctx.inside, pathfind = true }) and are told to stop
	hunting in reset(). Lounges (safe worlds) should start from Lounge.start(ctx) instead.
]]
local Template = {}

function Template.start(ctx)
	local model: Model = ctx.model
	local pressedBy: Player? = nil

	return {
		steps = {
			{
				id = "button",
				text = "PRESS THE RED BUTTON",
				kind = "interact",
				targets = model:WaitForChild("Button"),
				action = "Press",
				hold = 1,
				canUse = function(player: Player)
					pressedBy = player -- (a gate can also refuse: return false, "It's stuck.")
					return true
				end,
			},
			{
				id = "exit",
				text = "REACH THE EXIT",
				kind = "reach",
				targets = model:WaitForChild("ExitZone"),
				radius = 6,
			},
		},
		reset = function()
			pressedBy = nil
		end,
		roundStart = function()
			ctx.caption(nil, "[A low hum fills the room.]", 3)
		end,
		escalate = function(level: number)
			-- spawn more / faster entities here; WorldHost already shows the blue guide path
			ctx.fire(nil, "flicker", level)
		end,
		onEnter = function(player: Player)
			if pressedBy then
				ctx.notify(player, pressedBy.DisplayName .. " already pressed the button.")
			end
		end,
		onClientEvent = function(_player: Player, _kind: string)
			-- messages from client/Worlds/_Template.luau (validate everything: it's a client)
		end,
		stop = function() end,
	}
end

return Template
