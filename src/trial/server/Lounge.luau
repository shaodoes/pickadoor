--[[
	Lounge: the shared logic of every safe world (a short reward lounge: explore, pick up keys, find the
	world's collectible, leave by the exit whenever you like; WorldHost wires the exit and FOLLOW THEM IN).

	A lounge's server module can be just:
	  return { start = function(ctx) return Lounge.start(ctx) end }
	or extend the controller it returns (add escalate / onClientEvent, wrap reset / roundStart).

	  Lounge.start(ctx, opts?) -> controller { reset, roundStart, escalate, onEnter, stop }
	    opts.pickupRadius   studs from a key pickup's centre that collects it (default 4)
	    opts.onPickup(player, part)   optional, after the keys are paid

	Pickups: every BasePart in the model's Pickups folder pays Config.Rewards.Pickup once per player per
	round; the client hides it for that player (WorldEvent "pickup", part name). Collectible: a part named
	Collectible gets a "Take" prompt; ctx.collect pays it once per player ever (save: Collectibles), and
	the client hides it (WorldEvent "collectible").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Lounge = {}

export type Opts = {
	pickupRadius: number?,
	onPickup: ((Player, BasePart) -> ())?,
}

function Lounge.start(ctx, opts: Opts?)
	local o: Opts = opts or {}
	local radius = o.pickupRadius or 4
	local model: Model = ctx.model
	local pickups: { BasePart } = {}
	local folder = model:FindFirstChild("Pickups")
	for _, part in if folder then folder:GetChildren() else {} do
		if part:IsA("BasePart") then
			table.insert(pickups, part)
		end
	end
	local got: { [Player]: { [BasePart]: boolean } } = {}
	local running = true
	local connections: { RBXScriptConnection } = {}

	-- the collectible: hold to take it
	local collectible = model:FindFirstChild("Collectible", true)
	local item = ctx.def.play and ctx.def.play.collectible
	if collectible and collectible:IsA("BasePart") and item then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"
		prompt.ObjectText = item.name
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = collectible
		table.insert(
			connections,
			prompt.Triggered:Connect(function(player)
				if ctx.inside(player) and ctx.collect(player) then
					ctx.fire(player, "collectible", collectible.Name)
				end
			end)
		)
	end

	-- key pickups: walk through them
	task.spawn(function()
		while running do
			for _, player in ctx.players() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local mine = got[player] or {}
					got[player] = mine
					for _, part in pickups do
						if not mine[part] and (part.Position - root.Position).Magnitude <= radius then
							mine[part] = true
							ctx.pay(player, Config.Rewards.Pickup)
							ctx.fire(player, "pickup", part.Name)
							if o.onPickup then
								task.spawn(o.onPickup, player, part)
							end
						end
					end
				end
			end
			task.wait(0.15)
		end
	end)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			got[player] = nil
		end)
	)

	return {
		reset = function()
			table.clear(got)
		end,
		roundStart = function() end,
		escalate = function(_level: number) end, -- lounges never escalate
		onEnter = function(player: Player)
			-- a fresh arrival (or a revive) sees the pickups they haven't taken yet this round
			local taken = {}
			for part in got[player] or {} do
				table.insert(taken, part.Name)
			end
			ctx.fire(player, "taken", taken)
		end,
		stop = function()
			running = false
			for _, c in connections do
				c:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return Lounge
