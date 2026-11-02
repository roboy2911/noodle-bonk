--!strict
-- Hit juice: sounds, pop-up "BONK!" text, splashes, and ability visuals.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local CameraController = require(script.Parent.CameraController)

local HIT_WORDS = { "BONK!", "BOING!", "WHAP!", "FWUMP!", "SPLOT!" }
local WATER_COLOR = Color3.fromRGB(150, 220, 255)
local TENTACLE_COLOR = Color3.fromRGB(120, 60, 160)

local player = Players.LocalPlayer

local Effects = {}

local function effectPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Plays a sound from Config.Sounds by name, in 3D at `position` if given,
-- otherwise flat for this player only.
function Effects.playSound(name: string, position: Vector3?)
	local entry = Config.Sounds[name]
	if not entry or #entry.Ids == 0 then
		warn(`[Noodle Bonk] No sound named {name} in Config.Sounds`)
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = `rbxassetid://{entry.Ids[math.random(#entry.Ids)]}`
	sound.Volume = entry.Volume
	sound.PlaybackSpeed = 0.95 + math.random() * 0.1 -- slight variety so repeats don't grate
	sound.RollOffMaxDistance = 250

	local holder: Instance = sound
	if position then
		local attachment = Instance.new("Attachment")
		attachment.Position = position
		attachment.Parent = workspace.Terrain
		sound.Parent = attachment
		holder = attachment
	else
		sound.Parent = SoundService
	end
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	Debris:AddItem(holder, 30) -- in case it never loads
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
	label.Font = Enum.Font.LuckiestGuy
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

-- A burst of water droplets at `position`.
function Effects.splash(position: Vector3)
	local part = effectPart()
	part.Transparency = 1
	part.Size = Vector3.new(4, 1, 4)
	part.Position = position
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(WATER_COLOR)
	emitter.LightEmission = 0.3
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(25, 45)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -80, 0)
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = part
	emitter:Emit(60)

	Debris:AddItem(part, 2)
end

-- A burst of colorful confetti (Party noodle hits).
function Effects.confetti(position: Vector3)
	local part = effectPart()
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 160)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 255, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
	})
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new(0.35)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(18, 34)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -35, 0)
	emitter.RotSpeed = NumberRange.new(-300, 300)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(45)

	Debris:AddItem(part, 2)
end

-- An expanding ring on the ground (Pogo slam).
function Effects.shockwave(position: Vector3, radius: number)
	local ring = effectPart()
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = WATER_COLOR
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 2, 2)
	-- Cylinders run along X; tip it on its side so it lies flat
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - position).Magnitude < radius * 2 then
		CameraController.shake(0.5)
	end
end

-- A tentacle that shoots from one part to another, then retracts (Kraken).
function Effects.tentacle(from: BasePart, to: BasePart)
	local tentacle = effectPart()
	tentacle.Shape = Enum.PartType.Cylinder
	tentacle.Material = Enum.Material.SmoothPlastic
	tentacle.Color = TENTACLE_COLOR
	tentacle.Parent = workspace

	local REACH_TIME, HOLD_TIME = 0.15, 0.25
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		if elapsed > REACH_TIME + HOLD_TIME or not from.Parent or not to.Parent then
			connection:Disconnect()
			tentacle:Destroy()
			return
		end
		local reach = math.clamp(elapsed / REACH_TIME, 0.05, 1)
		local a = from.Position
		local b = a:Lerp(to.Position, reach)
		local length = (b - a).Magnitude
		if length > 0.05 then
			tentacle.Size = Vector3.new(length, 0.9, 0.9)
			tentacle.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
		end
	end)
end

function Effects.start()
	Remotes.HitConfirm.OnClientEvent:Connect(function(position: Vector3, noodleId: string, attacker: Player?)
		local def = Noodles[noodleId]
		Effects.playSound("Hit", position)
		Effects.playSound("HitBoink", position)
		Effects.popText(position, HIT_WORDS[math.random(#HIT_WORDS)], if def then def.Color else Color3.new(1, 1, 1))
		if def and def.Confetti then
			Effects.confetti(position)
		end
		if attacker == player then
			CameraController.shake(0.2)
		end
	end)

	Remotes.AbilityFx.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "Sound" and type(a) == "string" then
			Effects.playSound(a, if typeof(b) == "Vector3" then b else nil)
		elseif kind == "Splash" and typeof(a) == "Vector3" then
			Effects.splash(a) -- Splash noodle spray
		elseif kind == "Shockwave" and typeof(a) == "Vector3" and type(b) == "number" then
			Effects.shockwave(a, b)
		elseif kind == "Tentacle" and typeof(a) == "Instance" and typeof(b) == "Instance" then
			if a:IsA("BasePart") and b:IsA("BasePart") then
				Effects.tentacle(a, b)
			end
		end
	end)
end

return Effects
