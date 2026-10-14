--[[
	Server module for the Studio test world "_test_lounge": nothing but the shared lounge logic
	(key pickups, the Brass Bell collectible; WorldHost wires the exit and FOLLOW THEM IN).
]]
local Lounge = require(script.Parent.Parent.Lounge)

local TestLounge = {}

function TestLounge.start(ctx)
	return Lounge.start(ctx)
end

return TestLounge
