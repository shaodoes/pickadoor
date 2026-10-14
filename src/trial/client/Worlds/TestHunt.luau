--[[
	Client module for the Studio test world "_test_hunt": a low drone while you're in the corridor, and
	the lights stutter when it escalates.
]]
local Lighting = game:GetService("Lighting")

local TestHunt = {}

function TestHunt.enter(ctx): () -> ()
	local drone = ctx.Sfx.make(workspace.CurrentCamera, "DoorDrone", { volume = 0.25 })
	if drone then
		drone:Play()
	end
	local off = ctx.onEvent(function(kind: string)
		if kind == "escalate" then
			-- one hard stutter of the whole picture
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Brightness = -0.6
			cc.Parent = Lighting
			task.delay(0.12, function()
				cc.Brightness = 0
				task.wait(0.08)
				cc.Brightness = -0.4
				task.wait(0.1)
				cc:Destroy()
			end)
		end
	end)
	return function()
		off()
		if drone then
			drone:Destroy()
		end
	end
end

return TestHunt
