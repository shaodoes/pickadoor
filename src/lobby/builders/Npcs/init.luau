--[[
	The lobby's three residents, baked into the map by LobbyBuilder so they stand in place in Studio's
	Edit mode and in the saved place, not only once the server runs:
		Shopkeeper  "Teeth", behind the gift-shop counter (Layout.Shopkeeper)
		Guide       the Librarian with his lantern, in the foyer (Layout.Guide), plus his Lectern
		Archivist   Mr. Ashby, behind the Challenges desk (Layout.Stations.Challenges.npc)
	The baked copies are static (no idle playing). At runtime the lobby services adopt them by name
	(Lobby.Shopkeeper / Guide / Archivist / Lectern), building any that are missing, and bring them
	to life; the clients (Shopkeeper/Guide/Archivist.client, AmbientSound) WaitForChild those names,
	so there is exactly one of each.
]]
local Shopkeeper = require(script.Shopkeeper)
local Librarian = require(script.Librarian)
local Archivist = require(script.Archivist)

local IDLE_ANIMATION = "rbxassetid://507766666" -- default R15 idle

local Npcs = {}

function Npcs.buildShopkeeper(parent: Instance): Model
	return Shopkeeper.build(parent)
end

-- The Librarian and, beside him, his lectern (a separate model, "Lectern").
function Npcs.buildGuide(parent: Instance): Model?
	local guide = Librarian.build(parent)
	if guide and not parent:FindFirstChild("Lectern") then
		Librarian.lectern(parent, guide)
	end
	return guide
end

function Npcs.buildArchivist(parent: Instance): Model?
	return Archivist.build(parent)
end

-- Bake all three (and the lectern) into the lobby model.
function Npcs.build(root: Instance)
	Npcs.buildShopkeeper(root)
	Npcs.buildGuide(root)
	Npcs.buildArchivist(root)
end

-- Runtime: loop the default idle on a Humanoid rig (Guide, Archivist). Call on the server only.
function Npcs.playIdle(rig: Model, speed: number?)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local idle = Instance.new("Animation")
	idle.AnimationId = IDLE_ANIMATION
	local played = pcall(function()
		local track = (animator :: Animator):LoadAnimation(idle)
		track.Looped = true
		track:Play()
		if speed then
			track:AdjustSpeed(speed)
		end
	end)
	if not played then
		warn("[Npcs] idle animation failed to load on " .. rig.Name)
	end
end

return Npcs
