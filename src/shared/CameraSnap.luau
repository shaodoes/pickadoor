--[[
	Re-aims the camera after the server teleports the local character (shared by the Lobby and Trial
	places).

	CameraSnap.start()
	    The server places characters with a chosen facing (the queue's "facing the door", the trial's
	    spawn / SafeRoom / ThreatCorridor Arrive parts, pivoted a frame after LoadCharacter). The default
	    camera only follows position, so it kept its old yaw and players arrived looking sideways or
	    back the way they came. Each frame, before the camera scripts run, the root's jump since the
	    last frame is compared with what its velocity allows; a bigger jump is a teleport, and the
	    camera is swung behind the character's new facing, keeping the player's zoom and a sane pitch.
	    Only touches a Custom camera that follows the local humanoid (cutscenes are left alone).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraSnap = {}

local SLACK = 4 -- studs a root may move per frame beyond its velocity before it counts as a teleport
local FOCUS_HEIGHT = 1.5 -- the default camera's focus above the HumanoidRootPart
local PITCH_MIN, PITCH_MAX = math.rad(-40), math.rad(-8)

local started = false

function CameraSnap.start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local lastPos: Vector3? = nil
	local lastRoot: BasePart? = nil

	local function snap(root: BasePart, camera: Camera)
		local look = root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local focus = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
		local offset = camera.CFrame.Position - camera.Focus.Position
		local distance = offset.Magnitude
		if distance < 1 then -- first person: just turn the head, level
			camera.CFrame = CFrame.new(focus) * CFrame.fromOrientation(0, yaw, 0)
			return
		end
		local pitch = math.clamp(math.asin(math.clamp(-offset.Y / distance, -1, 1)), PITCH_MIN, PITCH_MAX)
		camera.CFrame = CFrame.new(focus) * CFrame.fromOrientation(pitch, yaw, 0) * CFrame.new(0, 0, distance)
		camera.Focus = CFrame.new(focus)
	end

	-- before the camera scripts, so they build this frame's view from the corrected CFrame
	RunService:BindToRenderStep("CameraSnap", Enum.RenderPriority.Camera.Value - 1, function(dt)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			lastPos, lastRoot = nil, nil
			return
		end
		local pos = root.Position
		if root ~= lastRoot or not lastPos then
			lastPos, lastRoot = pos, root
			return
		end
		local jump = (pos - lastPos).Magnitude
		lastPos = pos
		if jump <= SLACK + root.AssemblyLinearVelocity.Magnitude * dt * 2 then
			return
		end
		local camera = workspace.CurrentCamera
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if camera and camera.CameraType == Enum.CameraType.Custom and camera.CameraSubject == humanoid then
			snap(root, camera)
		end
	end)
end

return CameraSnap
