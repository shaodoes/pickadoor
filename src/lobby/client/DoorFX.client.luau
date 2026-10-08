-- Door wall VFX (client-only, so every player sees their own glitches):
--   doors     light leaks from underneath and builds with the pad countdown; the door rattles
--             near zero and swings open onto black when the party leaves
--   stencils  labels above the doors glitch to other words; the count pulses red in the last seconds
--   PICK A DOOR breathes a red glow, drips, and occasionally says something else
--   clock     the second hand ticks and slips back; while any pad counts down the hands run backwards
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local lobby = workspace:WaitForChild("Lobby")
local pads = lobby:WaitForChild("Pads")
local queue = lobby:WaitForChild("Queue")

local RED = Color3.fromRGB(150, 40, 32)
local HOT_RED = Color3.fromRGB(230, 50, 40)

local LABEL_GLITCHES = {
	Solo = { "ALONE", "S0LO", "JUST YOU" },
	Duo = { "BOTH", "DU0", "ONE OF YOU" },
	Squad = { "ALL OF YOU", "SQU4D", "NOT ALL" },
}
local STENCIL_GLITCHES = { "ONLY ONE OPENS", "PICK ONE", "YOU ALREADY DID", "DON'T", "PICK  A  DOOR" }

-- Swap a label's text for a moment, nudged off-register like a misprint.
local function glitch(label: TextLabel, options: { string }, original: string, basePosition: UDim2)
	label.Text = options[math.random(#options)]
	label.Position = basePosition + UDim2.fromOffset(math.random(-8, 8), math.random(-4, 4))
	task.delay(0.08 + math.random() * 0.2, function()
		label.Text = original
		label.Position = basePosition
	end)
end

------------------------------------------------------------------------------------------
-- Doors
------------------------------------------------------------------------------------------
local doors = {}
for _, pad in pads:GetChildren() do
	local leaf = pad:WaitForChild("Leaf")
	local gui = pad:WaitForChild("Sign"):WaitForChild("SurfaceGui")
	local title = gui:WaitForChild("Title")
	local status = gui:WaitForChild("Status")
	local mode = pad:GetAttribute("Mode")
	table.insert(doors, {
		pad = pad,
		leaf = leaf,
		hinge = leaf:GetAttribute("Hinge") or leaf:GetPivot(),
		leak = pad:WaitForChild("UnderGlow"):WaitForChild("Leak"),
		spill = pad:WaitForChild("FloorSpill"),
		fog = pad:WaitForChild("Fog"):WaitForChild("Fog"),
		title = title,
		titleText = title.Text,
		titlePos = title.Position,
		status = status,
		statusColor = status.TextColor3,
		counter = pad:WaitForChild("Zone"):WaitForChild("Counter"),
		shownCount = -1,
		glitches = LABEL_GLITCHES[mode] or { "?" },
		nextGlitch = os.clock() + 3 + math.random() * 10,
		open = 0,
		lastAngle = 0,
		seed = math.random() * 1000,
	})
end

-- 0 when nobody is queued; ramps 0.25 -> 1 as the countdown runs out.
local function tensionOf(pad: Instance): number
	if (pad:GetAttribute("Count") or 0) == 0 then
		return 0
	end
	local timeLeft = pad:GetAttribute("TimeLeft") or Config.QueueCountdown
	return 0.25 + 0.75 * math.clamp(1 - timeLeft / Config.QueueCountdown, 0, 1)
end

local function updateDoor(d, t: number, dt: number): number
	local pad = d.pad
	local tension = tensionOf(pad)
	local launching = pad:GetAttribute("Launching") == true
	local timeLeft = pad:GetAttribute("TimeLeft") or 0

	-- light under the door: a slow uneven breathing that swells with the countdown
	local breathe = math.noise(t * 1.3, d.seed) * 0.35
	d.leak.Brightness = launching and 2.2 or (0.5 + breathe + tension * 1.4)
	d.leak.Range = launching and 13 or (9 + tension * 4)
	d.spill.Transparency = launching and 0.45 or (0.86 - tension * 0.35)
	d.fog.Rate = launching and 25 or (2 + tension * 10)

	-- the leaf: rattles harder as time runs out, swings open when the party leaves
	d.open += ((launching and 1 or 0) - d.open) * math.min(dt * 2.5, 1)
	local rattle = 0
	if tension > 0 then
		local strength = (timeLeft <= 5 and 0.05 or 0.012) * tension
		rattle = math.noise(t * 22, d.seed) * strength
	end
	local angle = -d.open * math.rad(32) + rattle
	if math.abs(angle - d.lastAngle) > 1e-4 then
		d.leaf:PivotTo(d.hinge * CFrame.Angles(0, angle, 0))
		d.lastAngle = angle
	end

	-- floating counter: fill one ring per player; it throbs while the door is about to open
	local count = pad:GetAttribute("Count") or 0
	if count ~= d.shownCount then
		d.shownCount = count
		for _, dot in d.counter.Dots:GetChildren() do
			if dot:IsA("Frame") then
				dot.BackgroundTransparency = dot.LayoutOrder <= count and 0 or 1
			end
		end
		d.counter.Count.Text = string.format("%d / %d", count, pad:GetAttribute("Capacity") or 0)
	end
	local throb = (tension > 0 and timeLeft <= 5 or launching) and (1 + math.sin(t * 12) * 0.06) or 1
	d.counter.Size = UDim2.fromOffset(160 * throb, 50 * throb)

	-- the count pulses red in the last five seconds
	if tension > 0 and timeLeft <= 5 then
		d.status.TextColor3 = d.statusColor:Lerp(HOT_RED, (math.sin(t * 10) + 1) / 2)
	else
		d.status.TextColor3 = d.statusColor
	end

	-- the label above glitches now and then, more often while someone is waiting
	if t >= d.nextGlitch then
		glitch(d.title, d.glitches, d.titleText, d.titlePos)
		d.nextGlitch = t + (5 + math.random() * 14) / (1 + tension * 3)
	end
	return tension
end

------------------------------------------------------------------------------------------
-- PICK A DOOR stencil
------------------------------------------------------------------------------------------
local stencil = queue:WaitForChild("Stencil")
local stencilLabel = stencil:WaitForChild("SurfaceGui"):WaitForChild("Label")
local stencilGlow = stencil:WaitForChild("Glow")
local stencilDrip = stencil:WaitForChild("Drip")
local stencilText, stencilPos = stencilLabel.Text, stencilLabel.Position
local nextStencilGlitch = os.clock() + 6

local function updateStencil(t: number, tension: number)
	local pulse = (math.sin(t * 0.9) + 1) / 2
	stencilGlow.Brightness = 0.15 + pulse * 0.3 + tension * 0.8
	stencilLabel.TextColor3 = RED:Lerp(HOT_RED, pulse * 0.5 + tension * 0.5)
	stencilDrip.Rate = 1.2 + tension * 6
	if t >= nextStencilGlitch then
		if math.random() < 0.3 then
			-- a quick flicker instead of different words
			stencilLabel.TextTransparency = 0.7
			task.delay(0.06, function()
				stencilLabel.TextTransparency = 0
			end)
		else
			glitch(stencilLabel, STENCIL_GLITCHES, stencilText, stencilPos)
		end
		nextStencilGlitch = t + (8 + math.random() * 14) / (1 + tension * 2)
	end
end

------------------------------------------------------------------------------------------
-- Clock
------------------------------------------------------------------------------------------
local clock = queue:WaitForChild("Clock")
local center = clock:GetAttribute("Center")
local clockGlow = clock:WaitForChild("Face"):WaitForChild("Glow")
local hands = {
	hour = clock:WaitForChild("HandHour"),
	minute = clock:WaitForChild("HandMinute"),
	second = clock:WaitForChild("HandSecond"),
}
local hourAngle, minuteAngle = math.rad(20), math.rad(300) -- stopped at about ten to one
local STUCK = { 0, 1, 2, 1 } -- tick, tick, tick, back

local function placeHand(part: BasePart, angle: number)
	local depth = part:GetAttribute("Depth")
	local length = part:GetAttribute("Length")
	part.CFrame = CFrame.new(center + Vector3.new(0, 0, depth))
		* CFrame.Angles(0, 0, -angle)
		* CFrame.new(0, length * 0.4, 0)
end

local function updateClock(t: number, dt: number, tension: number)
	-- second hand: ticks forward, but every fourth second it slips back one
	local sec = math.floor(t)
	local shown = math.floor(sec / 4) * 2 + STUCK[sec % 4 + 1]
	local settle = math.clamp((t - sec) * 12, 0, 1) -- snap into each tick
	local secondAngle = (shown - 1 + settle) / 60 * math.pi * 2
	if tension > 0 then
		-- while a door is counting down, time runs backwards
		minuteAngle -= dt * (1 + tension * 7)
		hourAngle -= dt * (1 + tension * 7) / 12
		secondAngle = -t * (4 + tension * 10)
	end
	placeHand(hands.second, secondAngle)
	placeHand(hands.minute, minuteAngle)
	placeHand(hands.hour, hourAngle)
	clockGlow.Brightness = 0.3 + tension * 0.9
end

------------------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local maxTension = 0
	for _, d in doors do
		maxTension = math.max(maxTension, updateDoor(d, t, dt))
	end
	updateStencil(t, maxTension)
	updateClock(t, dt, maxTension)
end)
