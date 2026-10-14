--[[
	_Template: the copy-me world client module (see builders/Worlds/_Template.luau for the three-file
	contract and WorldClient.client.luau for everything ctx offers).

	  enter(ctx) -> cleanup
	Runs when the local player arrives in the world (and again after a revive); cleanup runs when they
	leave it (escape, death, round end). Only local effects belong here: sounds, screen effects, local
	looks (e.g. "is the player looking at this painting" -> ctx.fire("looking", ...)); the server module
	decides everything that matters. Give every sound cue a ctx.caption line.
]]
local Template = {}

function Template.enter(ctx): () -> ()
	local hum = ctx.Sfx.make(workspace.CurrentCamera, "LampHum", { volume = 0.15, looped = true })
	if hum then
		hum:Play()
	end
	local off = ctx.onEvent(function(kind: string, level: number?)
		if kind == "flicker" then
			ctx.caption("[The lights stutter.]", 2)
			ctx.Screen.vignette(0.4 * (level or 1), 0.2)
			task.delay(0.6, function()
				ctx.Screen.vignette(0, 0.8)
			end)
		end
	end)
	return function()
		off()
		if hum then
			hum:Destroy()
		end
	end
end

return Template
