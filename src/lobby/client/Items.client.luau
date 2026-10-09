-- Lobby: the items hotbar sits bottom-left, clear of the PICK A DOOR menu (bottom-centre) and the Keys card.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemsClient = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemsClient"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:FindFirstChild("ItemsUI")
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "ItemsUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
end

ItemsClient.start(gui, { position = UDim2.new(0, 16, 1, -16), anchorPoint = Vector2.new(0, 1) })
