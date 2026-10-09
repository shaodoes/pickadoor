--[[
	Client-side lantern feel (shared by the Lobby and Trial places).

	LanternFX.start()
	    Watches the local character and Backpack for the "Lantern" Tool and, while it is in hand:
	      sway     the lantern swings like a pendulum hung from the ring: a damped spring on pitch/roll
	               driven by the character's acceleration, applied to tool.Grip every frame (the client
	               owns its character, so the local player sees it at once; others don't, which is fine).
	      flicker  noise-driven stretch/lean of the Neon flame layers (SpecialMesh Scale/Offset, so the
	               welded parts never move) plus the PointLight and halo breathing with it.
	      burst    on equip: the flame flares to 1.6x and relaxes, the light pulses, the embers puff,
	               a soft ignite whoosh plays and a quiet crackle loop starts at the handle.
	    Everything runs in one RenderStepped connection with no per-frame allocations.

	LanternFX.animatePreview(model: Model) -> () -> ()
	    Animates a lantern copy inside a ViewportFrame: ParticleEmitters, Beams and BillboardGuis don't
	    render there, so the flame layers flicker the same way and a small recycled pool of Neon ember
	    parts rises and fades out of the flame. Returns a stop function.

	LanternFX.flameParts = LanternBuilder.flameParts (re-exported for convenience).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LanternBuilder = require(script.Parent.LanternBuilder)
local Sfx = require(script.Parent.Sfx)

local LanternFX = {}
LanternFX.flameParts = LanternBuilder.flameParts

local noise = math.noise
local rng = Random.new()

local SWAY_LIMIT = math.rad(8) -- pendulum amplitude clamp
local SWAY_K = 80 -- spring stiffness (~1.4 Hz, a short pendulum)
local SWAY_C = 4.5 -- damping (under-damped: it swings a few times and settles)
local SWAY_GAIN = 0.0032 -- radians per stud/s^2 of horizontal acceleration
local BURST_TIME = 0.7 -- seconds for the equip flare to relax

------------------------------------------------------------------------------------------
-- Flame flicker (shared by the held lantern and previews)
------------------------------------------------------------------------------------------
export type FlameState = {
	parts: LanternBuilder.FlameParts,
	seed: number,
	baseLight: number,
	baseHalo: number,
	burst: number, -- 1 right after the equip flare, decaying to 0
}

local function newFlameState(parts: LanternBuilder.FlameParts): FlameState
	return {
		parts = parts,
		seed = rng:NextNumber(0, 1000),
		baseLight = parts.light and parts.light.Brightness or 0,
		baseHalo = parts.halo and parts.halo.Brightness or 0,
		burst = 0,
	}
end

-- One frame of flicker. `burst` adds the equip flare on top.
local function stepFlame(state: FlameState, t: number, dt: number)
	local parts, s = state.parts, state.seed
	if state.burst > 0 then
		state.burst = math.max(state.burst - dt / BURST_TIME, 0)
	end
	-- an eased flare: quick up, slow settle
	local burst = state.burst * state.burst
	local flick = noise(t * 7, s) * 0.6 + noise(t * 19, s + 3) * 0.4 -- ~ -1..1
	local leanX = noise(t * 1.3, s + 7) * 0.5 + noise(t * 9, s + 8) * 0.12
	local leanZ = noise(t * 1.1, s + 9) * 0.5 + noise(t * 8, s + 10) * 0.12
	local stretch = 1 + flick * 0.14 + burst * 0.6
	local width = 1 - flick * 0.06 + burst * 0.25

	-- the flame is a sphere mesh: stretch it up from its base and lean the top over (object space)
	local outerMesh, innerMesh = parts.outerMesh, parts.innerMesh
	if outerMesh then
		outerMesh.Scale = Vector3.new(width, stretch, width)
		outerMesh.Offset = Vector3.new(leanX * 0.03, (stretch - 1) * 0.16, leanZ * 0.03)
	end
	if innerMesh then
		local innerStretch = 1 + flick * 0.1 + burst * 0.5
		innerMesh.Scale = Vector3.new(1 - flick * 0.04, innerStretch, 1 - flick * 0.04)
		innerMesh.Offset = Vector3.new(leanX * 0.02, (innerStretch - 1) * 0.08, leanZ * 0.02)
	end
	if parts.light then
		parts.light.Brightness = state.baseLight * (1 + flick * 0.16 + burst * 0.9)
	end
	if parts.halo then
		parts.halo.Brightness = state.baseHalo * (1 + flick * 0.1 + burst * 0.6)
	end
end

local function resetFlame(state: FlameState)
	local parts = state.parts
	if parts.outerMesh then
		parts.outerMesh.Scale = Vector3.one
		parts.outerMesh.Offset = Vector3.zero
	end
	if parts.innerMesh then
		parts.innerMesh.Scale = Vector3.one
		parts.innerMesh.Offset = Vector3.zero
	end
	if parts.light then
		parts.light.Brightness = state.baseLight
	end
	if parts.halo then
		parts.halo.Brightness = state.baseHalo
	end
end

------------------------------------------------------------------------------------------
-- The held lantern: sway + flicker + equip burst
------------------------------------------------------------------------------------------
local held = nil :: any -- the bound tool record, or nil
local renderConn: RBXScriptConnection? = nil

local function unbind()
	local h = held
	if not h then
		return
	end
	held = nil
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	for _, c in h.conns do
		c:Disconnect()
	end
	if h.crackle then
		h.crackle:Destroy()
	end
	if h.tool.Parent then
		h.tool.Grip = h.baseGrip
		if h.flame then
			resetFlame(h.flame)
		end
	end
end

-- Set the grip on the Tool and, belt and braces, on the Humanoid's RightGrip weld (the engine mirrors
-- Tool.Grip into the weld's C1, but writing the weld too makes the local swing immediate and certain).
local function applyGrip(h, grip: CFrame)
	h.tool.Grip = grip
	local weld = h.gripWeld
	if not weld or weld.Parent == nil then
		local hand = h.character:FindFirstChild("RightHand") or h.character:FindFirstChild("Right Arm")
		weld = hand and hand:FindFirstChild("RightGrip")
		h.gripWeld = weld
	end
	if weld and weld:IsA("Weld") and weld.Part1 == h.handle then
		weld.C1 = grip
	end
end

local function stepHeld(dt: number)
	local h = held
	if not h then
		return
	end
	local root, humanoid = h.root, h.humanoid
	if not root.Parent or not humanoid.Parent then
		unbind()
		return
	end
	local t = os.clock()
	dt = math.min(dt, 1 / 20) -- a hitch shouldn't kick the spring

	-- pendulum driven by horizontal acceleration in the character's frame
	local vel = root.AssemblyLinearVelocity
	vel = Vector3.new(vel.X, 0, vel.Z)
	local accel = (vel - h.lastVel) / dt
	h.lastVel = vel
	local la = root.CFrame:VectorToObjectSpace(accel)
	local moving = humanoid.MoveDirection.Magnitude > 0.05
	-- speeding up forward (-Z) swings the lantern back (positive pitch); sideways rolls it
	local drivePitch = math.clamp(la.Z * SWAY_GAIN, -SWAY_LIMIT, SWAY_LIMIT)
	local driveRoll = math.clamp(-la.X * SWAY_GAIN, -SWAY_LIMIT, SWAY_LIMIT)
	if moving then
		-- a small bob at step cadence keeps it alive on a steady walk
		local speed = math.min(vel.Magnitude / 16, 1.5)
		driveRoll += math.sin(t * 2 * math.pi * 1.55) * 0.035 * speed
		drivePitch += math.sin(t * 2 * math.pi * 3.1 + 0.6) * 0.012 * speed
	end
	-- damped spring toward the drive
	h.pitchV += (-SWAY_K * (h.pitch - drivePitch) - SWAY_C * h.pitchV) * dt
	h.rollV += (-SWAY_K * (h.roll - driveRoll) - SWAY_C * h.rollV) * dt
	h.pitch = math.clamp(h.pitch + h.pitchV * dt, -SWAY_LIMIT, SWAY_LIMIT)
	h.roll = math.clamp(h.roll + h.rollV * dt, -SWAY_LIMIT, SWAY_LIMIT)
	local settled = not moving
		and math.abs(h.pitch) < 0.0008
		and math.abs(h.roll) < 0.0008
		and math.abs(h.pitchV) < 0.004
		and math.abs(h.rollV) < 0.004
	if settled then
		if not h.atRest then
			h.atRest = true
			h.pitch, h.roll, h.pitchV, h.rollV = 0, 0, 0, 0
			applyGrip(h, h.baseGrip)
		end
	else
		h.atRest = false
		-- rotate about the grip point (the ring): Grip = base * R puts the swing on the hand, not the base
		applyGrip(h, h.baseGrip * CFrame.fromEulerAnglesXYZ(h.pitch, 0, h.roll))
	end

	if h.flame then
		stepFlame(h.flame, t, dt)
	end
end

local function burst(h)
	if h.flame then
		h.flame.burst = 1
	end
	local parts = h.flame and h.flame.parts
	if parts and parts.embers then
		parts.embers:Emit(12)
	end
	if parts and parts.flame then
		parts.flame:Emit(6)
	end
	Sfx.at(h.handle, "LanternEquip")
end

local function bind(tool: Tool, character: Model)
	if held and held.tool == tool then
		return
	end
	unbind()
	local handle = tool:FindFirstChild("Handle")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not handle or not humanoid or not root then
		return
	end
	local parts = LanternBuilder.flameParts(tool)
	local h = {
		tool = tool,
		handle = handle,
		character = character,
		humanoid = humanoid,
		root = root,
		gripWeld = nil :: Weld?,
		baseGrip = tool.Grip,
		pitch = 0,
		roll = 0,
		pitchV = 0,
		rollV = 0,
		atRest = true,
		lastVel = Vector3.zero,
		flame = parts and newFlameState(parts) or nil,
		crackle = Sfx.loop(handle, "LanternFlame"),
		conns = {},
	}
	held = h
	table.insert(
		h.conns,
		tool.AncestryChanged:Connect(function()
			if tool.Parent ~= character then
				unbind()
			end
		end)
	)
	renderConn = RunService.RenderStepped:Connect(stepHeld)
	burst(h)
end

local function watchCharacter(character: Model)
	local function consider(child: Instance)
		if child:IsA("Tool") and child.Name == "Lantern" then
			bind(child, character)
		end
	end
	character.ChildAdded:Connect(consider)
	character.ChildRemoved:Connect(function(child)
		if held and held.tool == child then
			unbind()
		end
	end)
	for _, child in character:GetChildren() do
		consider(child)
	end
end

local started = false
function LanternFX.start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(unbind)
	if player.Character then
		watchCharacter(player.Character)
	end
end

------------------------------------------------------------------------------------------
-- Viewport previews
------------------------------------------------------------------------------------------
local EMBER_POOL = 6

function LanternFX.animatePreview(model: Model): () -> ()
	local parts = LanternBuilder.flameParts(model)
	if not parts then
		return function() end
	end
	local state = newFlameState(parts)
	local emberColor = parts.embers and parts.embers.Color.Keypoints[1].Value or parts.outer.Color

	-- recycled ember sparks: tiny Neon parts, parented to the model so they live and die with it
	local embers = {}
	for i = 1, EMBER_POOL do
		local p = Instance.new("Part")
		p.Name = "PreviewEmber"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = emberColor
		p.Size = Vector3.new(0.05, 0.05, 0.05)
		p.Transparency = 1
		p.Parent = model
		embers[i] = { part = p, life = -1, dur = 1, pos = Vector3.zero, vel = Vector3.zero }
	end
	local nextSpawn = 0

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock()
		stepFlame(state, t, dt)

		nextSpawn -= dt
		if nextSpawn <= 0 then
			nextSpawn = rng:NextNumber(0.2, 0.55)
			for _, e in embers do
				if e.life < 0 then
					e.life = 0
					e.dur = rng:NextNumber(0.8, 1.4)
					e.pos = parts.outer.Position
						+ Vector3.new(rng:NextNumber(-0.05, 0.05), 0.05, rng:NextNumber(-0.05, 0.05))
					e.vel =
						Vector3.new(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0.45, 0.8), rng:NextNumber(-0.12, 0.12))
					e.part.Transparency = 0.1
					break
				end
			end
		end
		for i, e in embers do
			if e.life >= 0 then
				e.life += dt
				local k = e.life / e.dur
				if k >= 1 then
					e.life = -1
					e.part.Transparency = 1
				else
					e.vel += Vector3.new(noise(t * 2, i) * 0.4, 0.15, noise(t * 2, i + 50) * 0.4) * dt
					e.pos += e.vel * dt
					e.part.CFrame = CFrame.new(e.pos)
					e.part.Transparency = 0.1 + k * k * 0.9
					local size = 0.05 * (1 - k * 0.6)
					e.part.Size = Vector3.new(size, size, size)
				end
			end
		end
	end)

	return function()
		conn:Disconnect()
		for _, e in embers do
			e.part:Destroy()
		end
		if model.Parent then
			resetFlame(state)
		end
	end
end

return LanternFX
