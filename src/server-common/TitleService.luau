--[[
	Titles, deaths and the overhead nameplate data. Used by both places (start it after DataService).

	- Unlocks: every time a profile changes (DataService.Changed) each locked title in Shared.Titles
	  is checked against the profile; newly earned ones are saved and toasted ("Title unlocked: X").
	- Deaths: every character death (Humanoid.Died) adds 1 to profile.Deaths and ends the current
	  Hunt streak (Stats.huntStreak, for "Unkillable").
	- EquipTitle remote: (titleId) -> { ok, message }; only earned titles can be equipped.
	- Nameplate data, replicated as Player attributes for every client's Shared.Nameplates:
	    Title (string, display text)  TitleId (string)  TitleColor (Color3, the rarity colour)
	    TitleIcon (string, UIKit.icon glyph)  Deaths (number)
	- Hides Roblox's default name/health display on every player character.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Titles = require(Shared.Titles)
local DataService = require(script.Parent.DataService)

local TitleService = {}

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text, "success")
end

local function publish(player: Player, data: any)
	local def = Titles.getOrDefault(data.EquippedTitle)
	player:SetAttribute("Title", def.text)
	player:SetAttribute("TitleId", def.id)
	player:SetAttribute("TitleColor", Titles.color(def))
	player:SetAttribute("TitleIcon", def.icon)
	player:SetAttribute("Deaths", data.Deaths or 0)
end

-- Runs inside DataService's push (Changed). New titles go straight into the live profile so the
-- next Changed can't unlock them twice; a deferred empty update then pushes them to the client.
local function onChanged(player: Player, copy: any)
	-- (BindableEvent:Fire hands handlers a copy of the table: unlock titles in the live profile)
	local data = DataService.get(player) or copy
	if not player.Parent then
		return
	end
	local earned = {}
	for _, def in Titles.List do
		if not data.Titles[def.id] and Titles.isMet(def, data) then
			data.Titles[def.id] = true
			table.insert(earned, def)
		end
	end
	publish(player, data)
	if #earned > 0 then
		task.defer(function()
			if player.Parent then
				DataService.update(player, function() end)
			end
		end)
		for _, def in earned do
			notify(player, string.format('Title unlocked: "%s". Equip it from TITLES in the lobby.', def.text))
		end
	end
end

local function hideDefaultName(humanoid: Humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
end

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	hideDefaultName(humanoid)
	humanoid.Died:Once(function()
		DataService.update(player, function(data)
			data.Deaths += 1
			data.Stats.huntStreak = 0
		end)
	end)
end

local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)
	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end

function TitleService.equip(player: Player, id: any)
	local def = Titles.get(id)
	if not def then
		return { ok = false, message = "No such title." }
	end
	local data = DataService.get(player)
	if not data then
		return { ok = false, message = "Your save isn't loaded yet." }
	end
	if not data.Titles[def.id] then
		return { ok = false, message = string.format('"%s" is locked: %s', def.text, def.hint) }
	end
	if data.EquippedTitle == def.id then
		return { ok = true, message = string.format('"%s" is already on.', def.text) }
	end
	DataService.update(player, function(d)
		d.EquippedTitle = def.id
	end)
	return { ok = true, message = string.format('Title equipped: "%s".', def.text) }
end

function TitleService.start()
	DataService.Changed:Connect(onChanged)
	Remotes.get("EquipTitle").OnServerInvoke = TitleService.equip

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	-- profiles that loaded before this started
	for _, player in Players:GetPlayers() do
		local data = DataService.get(player)
		if data then
			onChanged(player, data)
		end
	end
end

return TitleService
