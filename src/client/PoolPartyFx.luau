--!strict
-- What everyone sees during a Pool Party: a banner naming who started it,
-- a crowd cheer, confetti raining around your camera, and a countdown at
-- the top of the screen. Reads Workspace's PoolPartyUntil / PoolPartyBy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local BonkUI = require(script.Parent.BonkUI)
local Effects = require(script.Parent.Effects)

local PARTY_PINK = Color3.fromRGB(255, 105, 180)
local CONFETTI = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 170)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(80, 200, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(110, 230, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
})

local player = Players.LocalPlayer

local PoolPartyFx = {}

local function secondsLeft(): number
	local untilTime = workspace:GetAttribute("PoolPartyUntil")
	if type(untilTime) ~= "number" then
		return 0
	end
	return math.max(0, untilTime - workspace:GetServerTimeNow())
end

function PoolPartyFx.start()
	-- Countdown at the top of the screen
	local gui = Instance.new("ScreenGui")
	gui.Name = "PoolParty"
	gui.ResetOnSpawn = false
	local timer = Instance.new("TextLabel")
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.new(0.5, 0, 0, 8)
	timer.Size = UDim2.fromOffset(460, 40)
	timer.BackgroundColor3 = PARTY_PINK
	timer.BackgroundTransparency = 0.1
	timer.Font = Enum.Font.LuckiestGuy
	timer.TextSize = 24
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.Visible = false
	timer.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = timer
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = timer
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Confetti emitter that hovers above the camera
	local holder = Instance.new("Part")
	holder.Name = "PoolPartyConfetti"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(70, 1, 70)
	holder.Parent = workspace
	local confetti = Instance.new("ParticleEmitter")
	confetti.Color = CONFETTI
	confetti.Size = NumberSequence.new(0.45)
	confetti.Lifetime = NumberRange.new(4, 6)
	confetti.Speed = NumberRange.new(2, 6)
	confetti.SpreadAngle = Vector2.new(30, 30)
	confetti.Acceleration = Vector3.new(0, -8, 0)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.EmissionDirection = Enum.NormalId.Bottom
	confetti.LightEmission = 0.2
	confetti.Rate = 0
	confetti.Parent = holder

	RunService.RenderStepped:Connect(function()
		local left = secondsLeft()
		local active = left > 0
		timer.Visible = active
		confetti.Rate = if active then 90 else 0
		if active then
			timer.Text = string.format(
				"🎉 POOL PARTY %d:%02d · %dX BONKS",
				math.floor(left / 60),
				math.floor(left % 60),
				Config.PoolParty.BonkMultiplier
			)
			local camera = workspace.CurrentCamera
			if camera then
				holder.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 22, 0))
			end
		end
	end)

	Remotes.PoolParty.OnClientEvent:Connect(function(starterName: string, _duration: number)
		Effects.playSound("StreakEnded") -- crowd cheer
		Effects.playSound("Announcement")
		BonkUI.showBanner(`{string.upper(starterName)} STARTED A POOL PARTY!`, PARTY_PINK, 3.5)
	end)
end

return PoolPartyFx
