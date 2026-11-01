--!strict
-- Sunny, slightly saturated lighting for normal play (the thumbnail scene sets
-- its own, stronger look). Effects are named "Noodle..." in Lighting. Set
-- Config.SetupLighting = false to keep your place's own Lighting instead.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Environment = {}

local function effect<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing then
		return existing :: any
	end
	local instance = Instance.new(className :: any)
	instance.Name = name
	instance.Parent = Lighting
	return instance :: any
end

function Environment.setup()
	if not Config.SetupLighting then
		return
	end

	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(105, 105, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 155)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.ExposureCompensation = 0.1

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "NoodleSky"
		sky.SunAngularSize = 14
		sky.Parent = Lighting
	end

	local atmosphere: Atmosphere = effect("Atmosphere", "NoodleAtmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(110, 170, 220)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 0.8

	local bloom: BloomEffect = effect("BloomEffect", "NoodleBloom")
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.8

	local color: ColorCorrectionEffect = effect("ColorCorrectionEffect", "NoodleColor")
	color.Saturation = 0.15
	color.Contrast = 0.08
	color.Brightness = 0.01

	local rays: SunRaysEffect = effect("SunRaysEffect", "NoodleSunRays")
	rays.Intensity = 0.03
	rays.Spread = 0.6
end

return Environment
