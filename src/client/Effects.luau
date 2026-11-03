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
local DuckFx = require(script.Parent.DuckFx)

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

-- A jagged lightning bolt through `points` (Lightning noodle).
function Effects.zap(points: { Vector3 })
	for i = 1, #points - 1 do
		local from, to = points[i], points[i + 1]
		local previous = from
		local steps = 6
		for step = 1, steps do
			local t = step / steps
			local point = from:Lerp(to, t)
			if step < steps then
				point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.5
			end
			local length = (point - previous).Magnitude
			if length > 0.05 then
				local bolt = effectPart()
				bolt.Size = Vector3.new(0.35, 0.35, length)
				bolt.CFrame = CFrame.lookAt((previous + point) / 2, point)
				bolt.Color = Color3.fromRGB(255, 245, 120)
				bolt.Material = Enum.Material.Neon
				bolt.Parent = workspace
				Debris:AddItem(bolt, 0.25)
			end
			previous = point
		end
	end
end

-- A rope from `from` to a point for a moment (Grapple noodle).
function Effects.rope(from: BasePart, to: Vector3)
	local rope = effectPart()
	rope.Color = Color3.fromRGB(130, 110, 90)
	rope.Parent = workspace
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		if os.clock() - started > 0.45 or not from.Parent then
			connection:Disconnect()
			rope:Destroy()
			return
		end
		local a = from.Position
		local length = (to - a).Magnitude
		rope.Size = Vector3.new(0.3, 0.3, math.max(length, 0.1))
		rope.CFrame = CFrame.lookAt((a + to) / 2, to)
	end)
end

-- A quick white puff of smoke (Swap and Clone noodles).
function Effects.poof(position: Vector3)
	local part = effectPart()
	part.Transparency = 1
	part.Position = position
	part.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(30)
	Debris:AddItem(part, 1.5)
end

-- Paint splats across this player's screen (hit by the Paint noodle).
function Effects.paintSplat(color: Color3)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaintSplat"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	for _ = 1, 7 do
		local blob = Instance.new("Frame")
		local size = math.random(140, 320)
		blob.Size = UDim2.fromOffset(size, size * math.random(70, 100) / 100)
		blob.Position = UDim2.fromScale(math.random(5, 85) / 100, math.random(5, 85) / 100)
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.BackgroundColor3 = color
		blob.BackgroundTransparency = 0.05
		blob.Rotation = math.random(0, 360)
		blob.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
	end
	gui.Parent = playerGui
	task.delay(1.5, function()
		for _, blob in gui:GetChildren() do
			if blob:IsA("Frame") then
				game:GetService("TweenService"):Create(blob, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(gui, 2.1)
end

-- Time Stop (??? noodle). Frozen players see gray and can't move; the one who
-- stopped time sees a purple tint.
function Effects.timeStop(duration: number, isCaster: boolean)
	local lighting = game:GetService("Lighting")
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "TimeStopTint"
	if isCaster then
		tint.TintColor = Color3.fromRGB(215, 190, 255)
		tint.Saturation = -0.2
	else
		tint.Saturation = -1
		tint.Contrast = 0.15
	end
	tint.Parent = lighting
	Debris:AddItem(tint, duration)
	Effects.playSound("Zap")

	if not isCaster then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = true -- your client runs your physics, so this holds you still
			task.delay(duration, function()
				if root.Parent then
					root.Anchored = false
				end
			end)
		end
	end
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
		elseif kind == "Stampede" and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			DuckFx.stampede(a, b)
		elseif kind == "Splash" and typeof(a) == "Vector3" then
			Effects.splash(a) -- Splash noodle spray
		elseif kind == "Shockwave" and typeof(a) == "Vector3" and type(b) == "number" then
			Effects.shockwave(a, b)
		elseif kind == "Zap" and type(a) == "table" then
			Effects.zap(a)
		elseif kind == "Rope" and typeof(a) == "Instance" and a:IsA("BasePart") and typeof(b) == "Vector3" then
			Effects.rope(a, b)
		elseif kind == "Poof" and typeof(a) == "Vector3" then
			Effects.poof(a)
		elseif kind == "Pop" and typeof(a) == "Vector3" and type(b) == "table" then
			Effects.popText(a, tostring(b.text), if typeof(b.color) == "Color3" then b.color else Color3.new(1, 1, 1))
		elseif kind == "TimeStop" and type(a) == "number" then
			Effects.timeStop(a, false)
		elseif kind == "TimeStopCaster" and type(a) == "number" then
			Effects.timeStop(a, true)
		elseif kind == "PaintSplat" and typeof(a) == "Color3" then
			Effects.paintSplat(a)
		elseif kind == "Tentacle" and typeof(a) == "Instance" and typeof(b) == "Instance" then
			if a:IsA("BasePart") and b:IsA("BasePart") then
				Effects.tentacle(a, b)
			end
		end
	end)
end

return Effects
