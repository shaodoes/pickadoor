-- Overhead nameplates for every other player: name, and up close the equipped title + death count
-- (shared module; see Shared.Nameplates).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Nameplates")).start()
