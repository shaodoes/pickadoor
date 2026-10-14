--[[
	WorldMood: per-world Lighting, applied on the client (the two halves of a party are in different
	worlds at the same time, so the server can't own Lighting once the doors open).

	  WorldMood.apply(mood?, time?)   tween to a world's mood (Shared.Worlds play.mood); nil = the door
	                                  room's look (the TrialBuilder baseline)
	Mood keys: Lighting properties Ambient, OutdoorAmbient, Brightness, ClockTime, FogColor, FogStart,
	FogEnd, ExposureCompensation, EnvironmentDiffuseScale, EnvironmentSpecularScale; and a
	ColorCorrectionEffect's TintColor, Saturation, Contrast (and its Brightness as CCBrightness).
	Anything a mood leaves out falls back to the door room's value.
]]
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local WorldMood = {}

-- the door room's look: TrialBuilder.build's Lighting (keep the two in step). Hard-coded rather than read
-- from Lighting, because this client may start before the server has set it.
local DOOR_ROOM: { [string]: any } = {
	Ambient = Color3.fromRGB(16, 14, 12),
	OutdoorAmbient = Color3.fromRGB(10, 10, 10),
	Brightness = 0,
	ClockTime = 0,
	FogColor = Color3.fromRGB(6, 6, 8),
	FogStart = 40,
	FogEnd = 160,
	TintColor = Color3.new(1, 1, 1),
	Saturation = 0,
	Contrast = 0,
	CCBrightness = 0,
}
WorldMood.DoorRoom = DOOR_ROOM

local LIGHTING_KEYS = {
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"FogColor",
	"FogStart",
	"FogEnd",
	"ExposureCompensation",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
}

-- the rest TrialBuilder doesn't touch: whatever the place has
for _, key in LIGHTING_KEYS do
	if DOOR_ROOM[key] == nil then
		DOOR_ROOM[key] = (Lighting :: any)[key]
	end
end

local cc: ColorCorrectionEffect? = nil
local current: { [string]: any }? = nil

function WorldMood.apply(mood: { [string]: any }?, time: number?)
	if mood == current and mood ~= nil then
		return
	end
	current = mood
	local m = mood or {}
	local function value(key: string): any
		local v = m[key]
		if v == nil then
			return DOOR_ROOM[key]
		end
		return v
	end
	local info = TweenInfo.new(time or 1.2, Enum.EasingStyle.Sine)
	local goal = {}
	for _, key in LIGHTING_KEYS do
		goal[key] = value(key)
	end
	TweenService:Create(Lighting, info, goal):Play()
	Lighting.ClockTime = value("ClockTime") -- (tweening the clock spins the sky)
	if not cc or not cc.Parent then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "WorldMood"
		cc.Parent = Lighting
	end
	TweenService:Create(cc :: ColorCorrectionEffect, info, {
		TintColor = value("TintColor"),
		Saturation = value("Saturation"),
		Contrast = value("Contrast"),
		Brightness = value("CCBrightness"),
	}):Play()
end

return WorldMood
