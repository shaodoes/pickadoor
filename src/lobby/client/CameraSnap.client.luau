-- Swings the camera behind the character after a server teleport (shared module; see Shared.CameraSnap).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CameraSnap")).start()
