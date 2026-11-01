--!strict
-- Hit juice: sounds and pop-up "BONK!" text where a noodle lands.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)

local HIT_WORDS = { "BONK!", "BOING!", "WHAP!", "FWUMP!", "SPLOT!" }

local Effects = {}

-- Plays a sound, in 3D at `position` if given, otherwise flat for this player only.
function Effects.playSound(soundId: string, position: Vector3?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2 -- slight variety so repeats don't grate

	if position then
		local attachment = Instance.new("Attachment")
		attachment.Position = position
		attachment.Parent = workspace.Terrain
		sound.Parent = attachment
		Debris:AddItem(attachment, 4)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 4)
	end
	sound:Play()
end

-- Floating text that pops up and fades out.
function Effects.popText(position: Vector3, text: string, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Parent = workspace.Terrain

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(5, 2)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Rotation = math.random(-12, 12)
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label

	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(attachment, 1)
end

function Effects.start()
	Remotes.HitConfirm.OnClientEvent:Connect(function(position: Vector3, noodleId: string)
		local def = Noodles[noodleId]
		Effects.playSound(Config.Sounds.Bonk, position)
		Effects.popText(position, HIT_WORDS[math.random(#HIT_WORDS)], if def then def.Color else Color3.new(1, 1, 1))
	end)
end

return Effects
