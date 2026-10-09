-- Mr. Ashby, the archivist, behind the Challenges desk. Built by Builders/Npcs/Archivist and baked
-- into the lobby by LobbyBuilder; this adopts that copy (Lobby.Archivist) or builds one if missing,
-- then starts his idle. His dialogue and head tracking run in Archivist.client.
local ServerStorage = game:GetService("ServerStorage")

local Npcs = require(ServerStorage:WaitForChild("Builders"):WaitForChild("Npcs"))

local ArchivistService = {}

function ArchivistService.start(lobby: Instance): Model?
	local rig = lobby:FindFirstChild("Archivist")
	if not (rig and rig:IsA("Model")) then
		rig = Npcs.buildArchivist(lobby)
	end
	if rig then
		Npcs.playIdle(rig :: Model, 0.8) -- an old man's breathing
	end
	return rig :: Model?
end

return ArchivistService
