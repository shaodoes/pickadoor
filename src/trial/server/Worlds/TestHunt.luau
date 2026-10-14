--[[
	Server module for the Studio test world "_test_hunt" (the old threat corridor): The Follower hunts
	whoever is inside; two objective steps (search the crate, reach the far end) open the exit.
	Escalation: The Follower speeds up and a second one steps out of the far end.
]]
local TestHunt = {}

function TestHunt.start(ctx)
	local model: Model = ctx.model
	local home = (model:WaitForChild("End") :: BasePart).CFrame
	local figure = model:WaitForChild("Stalker") :: Model
	local template = figure:Clone() -- a spare for the escalation, before anything moves
	local extras: { any } = {}

	local function isTarget(player: Player): boolean
		return ctx.inside(player)
	end
	local stalker = ctx.Stalker.start(figure, { home = home, isTarget = isTarget })

	return {
		steps = {
			{
				id = "crate",
				text = "SEARCH THE CRATE FOR THE KEY",
				kind = "interact",
				targets = model:WaitForChild("Crate"),
				action = "Search",
				hold = 1.5,
			},
			{
				id = "end",
				text = "REACH THE FAR END",
				kind = "reach",
				targets = model:WaitForChild("End"),
				radius = 8,
			},
		},
		reset = function()
			stalker.setActive(false)
			stalker.setSpeed(ctx.Config.Stalker.walkSpeed)
			stalker.reset()
			for _, extra in extras do
				extra.ai.stop()
				extra.model:Destroy()
			end
			table.clear(extras)
		end,
		roundStart = function()
			stalker.setActive(true)
		end,
		escalate = function(_level: number)
			stalker.setSpeed(ctx.Config.Stalker.walkSpeed + 4)
			local second = template:Clone()
			second.Name = "Stalker2"
			second.Parent = model
			second:PivotTo(home * CFrame.new(3, 0, 0))
			local ai = ctx.Stalker.start(second, { home = home, isTarget = isTarget, aggroRange = 200 })
			ai.setActive(true)
			table.insert(extras, { model = second, ai = ai })
			ctx.caption(nil, "[Footsteps from the far end. Two sets.]", 4)
		end,
		stop = function()
			stalker.stop()
		end,
	}
end

return TestHunt
