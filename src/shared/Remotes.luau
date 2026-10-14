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
	QuickJoin = "RemoteEvent", -- client -> server: put me on the best mat
	GuideSeen = "RemoteEvent", -- client -> server: finished the guide's introduction
	-- [items] item purchase / use / laser remotes
	BuyItem = "RemoteFunction", -- client -> server: item id -> { ok, message }
	UseItem = "RemoteFunction", -- client -> server: item id -> { ok, message, cooldown? } (laser: toggles the tool)
	LaserFire = "RemoteEvent", -- client -> server: firing: boolean
	LaserAim = "RemoteEvent", -- client -> server: aim point (Vector3), ~10 Hz while firing
	ItemEvent = "RemoteEvent", -- server -> client: kind ("speed" | "heal" | "unlock" | "stun" | "laserHit"), ...
	-- [trial] door-room remotes
	FollowIn = "RemoteEvent", -- client -> server: a lounge player follows the others into the dangerous world
	DoorEvent = "RemoteEvent", -- server -> one client: the door sequence ("commit" | "glitch" | "reveal", data)
	WorldEvent = "RemoteEvent", -- both ways: (worldId, kind, ...) between a world's server and client modules
	-- [shopkeeper] shopkeeper remotes
	-- [rewards] daily reward / Wheel of Fate / challenges (see Shared.Rewards)
	ClaimDaily = "RemoteFunction", -- client -> server: () -> { ok, message, day?, keys?, spins?, items? }
	SpinWheel = "RemoteFunction", -- client -> server: (buy: boolean?) -> { ok, message, index?, offset?, start?, reward? }
	ClaimChallenge = "RemoteFunction", -- client -> server: (scope "daily"|"weekly", slot 1..3) -> { ok, message }
	Talked = "RemoteEvent", -- client -> server: finished a conversation with "Teeth" | "Librarian" | "Archivist"
	RewardsDebug = "RemoteEvent", -- client -> server, Studio only: "nextDay" | "skipDay" | "resetDay" | "resetAll"
	-- [titles] nameplate titles (see Shared.Titles, Common.TitleService)
	EquipTitle = "RemoteFunction", -- client -> server: title id -> { ok, message }
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
