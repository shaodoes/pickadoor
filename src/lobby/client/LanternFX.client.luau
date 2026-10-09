-- The carried lantern's sway, flicker and equip flare (shared module; see Shared.LanternFX).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LanternFX")).start()
