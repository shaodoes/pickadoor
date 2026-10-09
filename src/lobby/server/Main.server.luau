-- Lobby place entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
Remotes.setup()

local Common = ServerStorage:WaitForChild("Common")
local DataService = require(Common.DataService)
local Monetization = require(Common.Monetization)
local LanternService = require(Common.LanternService)

-- The map is normally baked into the place; build it on the fly if it isn't.
local lobby = workspace:FindFirstChild("Lobby")
if not lobby then
	lobby = require(ServerStorage.Builders.LobbyBuilder).build()
end

DataService.start()
Monetization.start()
LanternService.start()
require(Common.ItemService).start({ recharge = true }) -- items + laser battery recharge (lobby only)
require(script.Parent.ShopService).start()
require(script.Parent.QueueService).start(lobby)
require(script.Parent.LeaderboardService).start(lobby)
require(script.Parent.GuideService).start(lobby)
require(script.Parent.ShopkeeperService).start(lobby)

-- Lights tagged with a "Flicker" attribute by the builder: the furnace breathes, one bulb won't stay on.
task.spawn(function()
	local lights = {}
	for _, inst in lobby:GetDescendants() do
		if inst:IsA("Light") and inst:GetAttribute("Flicker") then
			table.insert(lights, { light = inst, base = inst.Brightness, kind = inst:GetAttribute("Flicker") })
		end
	end
	while true do
		for _, entry in lights do
			if entry.kind == "furnace" then
				entry.light.Brightness = entry.base * (0.8 + math.random() * 0.35)
			elseif math.random() < 0.06 then
				-- the glowing core goes dark with the light, so the lamp really blinks
				local core = entry.light.Parent
				entry.light.Brightness = 0
				local glow = core:FindFirstChild("Halo")
				if core:IsA("BasePart") then
					core.Transparency = 0.85
				end
				if glow then
					glow.Enabled = false
				end
				task.delay(0.05 + math.random() * 0.25, function()
					entry.light.Brightness = entry.base
					if core:IsA("BasePart") then
						core.Transparency = 0.35
					end
					if glow then
						glow.Enabled = true
					end
				end)
			end
		end
		task.wait(0.12)
	end
end)
