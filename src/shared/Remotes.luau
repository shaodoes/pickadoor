-- Single place where every RemoteEvent/RemoteFunction is declared.
-- The server calls Remotes.setup() once; both sides then use Remotes.get(name).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local DEFINITIONS = {
	DataUpdated = "RemoteEvent", -- server -> client: profile snapshot
	GetData = "RemoteFunction", -- client -> server: initial snapshot
	Notify = "RemoteEvent", -- server -> client: toast message
	BuyLantern = "RemoteFunction",
	EquipLantern = "RemoteFunction",
	LeaveQueue = "RemoteEvent",
	GuideSeen = "RemoteEvent", -- client -> server: finished the guide's introduction
}

function Remotes.setup()
	assert(RunService:IsServer(), "Remotes.setup is server-only")
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): any
	assert(DEFINITIONS[name], "Unknown remote: " .. tostring(name))
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

return Remotes
