--[[
	Client module for the Studio test world "_test_lounge": the fire crackles (a positional loop on the
	fireplace). Everything lounge-generic (pickups, the collectible, captions) is WorldClient's.
]]
local TestLounge = {}

function TestLounge.enter(ctx): () -> ()
	local flame = ctx.model:FindFirstChild("Flame", true)
	local crackle = flame and ctx.Sfx.loop(flame, "FurnaceFire")
	return function()
		if crackle then
			crackle:Destroy()
		end
	end
end

return TestLounge
