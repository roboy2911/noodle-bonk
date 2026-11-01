--!strict
-- Thumbnail scene builder (Studio only). OFF by default.
--
-- Set Config.BuildThumbnailScene = true, then press Run (F8) in Studio. The
-- server builds a frozen action shot on the arena's edge and points the
-- camera at it:
--
--   * foreground: an attacker mid-swing with a big bent pink noodle, and a
--     shocked victim launched off the edge toward the camera, with a yellow
--     impact star where the noodle hits
--   * background: two players bonking each other (yellow and green noodles),
--     one floating in a bubble, one launched high into the sky
--   * cartoon water splashes, bright saturated lighting, and a low 16:9
--     camera with the top-left third left emptier for the logo
--   * a second, square close-up camera for the game icon
--     (Config.ThumbnailShot = "Icon")
--
-- Everything goes in Workspace.ThumbnailScene and is anchored. Lighting
-- effects are named "Thumbnail..." in Lighting. Each character gets a big
-- classic Roblox head with a real Roblox face image on it.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)

local ThumbnailScene = {}

-- Real Roblox face images, all uploaded by Roblox (checked against Roblox's
-- asset API and thumbnails). Each is the image inside a classic catalog face.
local FACE_EPIC_GRIN = 42070872 -- "Epic Face" (face 42070576): huge open grin
local FACE_PRANKSTER = 20052028 -- "Prankster" (face 20052135): squinting grin, tongue out
local FACE_DROOL = 7074882 -- "Drool" (face 7074893)
local FACE_BIG_D = 16132434 -- ":D" (face 16132514)
local FACE_SHOCKED = 66329844 -- "O_o": wide eyes, little "o" mouth

local SCENE_VERSION = 6 -- printed in Output so you can tell which version ran
local HEAD_SCALE = 1.6 -- classic head mesh size; bigger than normal so faces read in a thumbnail

local SKIN = Color3.fromRGB(255, 205, 150)
local WATER_LIGHT = Color3.fromRGB(150, 220, 255)
local WATER_WHITE = Color3.fromRGB(245, 252, 255)
local STAR_YELLOW = Color3.fromRGB(255, 230, 40)
local STAR_ORANGE = Color3.fromRGB(255, 150, 30)

-- Cylinders run along X; this stands one upright
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

type Outfit = { shirt: Color3, pants: Color3 }
type Pose = { [string]: Vector3 } -- joint name -> rotation in degrees (X, Y, Z)

-- Helpers ---------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function part(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Characters --------------------------------------------------------------------

-- Swaps the rig's head for a classic Roblox head (the shape classic faces
-- are drawn for) with `faceImage` on the front. Returns whether it worked.
local function giveClassicHead(rig: Model, faceImage: number): boolean
	local oldHead = rig:FindFirstChild("Head")
	if not oldHead then
		warn(`[Noodle Bonk] {rig.Name}: no Head found, face not applied`)
		return false
	end

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Color = SKIN
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.Anchored = true
	head.CanCollide = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.one * HEAD_SCALE
	mesh.Parent = head
	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Face = Enum.NormalId.Front
	decal.Texture = `rbxassetid://{faceImage}`
	decal.Parent = head

	-- Where the head meets the neck: its bottom, so the bigger head sits on the shoulders
	local neckAttachment = Instance.new("Attachment")
	neckAttachment.Name = "NeckRigAttachment"
	neckAttachment.CFrame = CFrame.new(0, -0.5 * HEAD_SCALE, 0)
	neckAttachment.Parent = head

	head.Parent = rig
	oldHead:Destroy()
	return true
end

-- A real R15 Roblox rig with bright body colors as "clothes" and a big
-- classic head showing a real Roblox face.
local function makeRig(parent: Instance, name: string, outfit: Outfit, faceImage: number): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.TorsoColor = outfit.shirt
	description.LeftArmColor = outfit.shirt
	description.RightArmColor = outfit.shirt
	description.LeftLegColor = outfit.pants
	description.RightLegColor = outfit.pants

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn(`[Noodle Bonk] Thumbnail scene couldn't build {name}: {result}`)
		return nil
	end
	local rig = result
	rig.Name = name

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- Stop Roblox from rebuilding the joints later (that would undo the pose)
		humanoid.AutomaticScalingEnabled = false
		humanoid.RequiresNeck = false
	end
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	-- Paint the "clothes" straight onto the body parts too
	for _, child in rig:GetChildren() do
		if child:IsA("BasePart") then
			if string.find(child.Name, "Leg") or string.find(child.Name, "Foot") then
				child.Color = outfit.pants
			elseif child.Name ~= "Head" and child.Name ~= "HumanoidRootPart" then
				child.Color = outfit.shirt
			end
		end
	end

	local headOk = giveClassicHead(rig, faceImage)
	rig:SetAttribute("ClassicHead", headOk)

	-- Everything stays anchored; poseAndFreeze places each part by hand
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	rig.Parent = parent
	return rig
end

-- The R15 body, parent part before child. Each row: joint name, parent
-- part, child part, and the rig attachment both parts share at that joint.
local R15_JOINTS: { { string } } = {
	{ "Root", "HumanoidRootPart", "LowerTorso", "RootRigAttachment" },
	{ "Waist", "LowerTorso", "UpperTorso", "WaistRigAttachment" },
	{ "Neck", "UpperTorso", "Head", "NeckRigAttachment" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", "RightShoulderRigAttachment" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", "RightElbowRigAttachment" },
	{ "RightWrist", "RightLowerArm", "RightHand", "RightWristRigAttachment" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", "LeftShoulderRigAttachment" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", "LeftElbowRigAttachment" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", "LeftWristRigAttachment" },
	{ "RightHip", "LowerTorso", "RightUpperLeg", "RightHipRigAttachment" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", "RightKneeRigAttachment" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", "RightAnkleRigAttachment" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", "LeftHipRigAttachment" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", "LeftKneeRigAttachment" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", "LeftAnkleRigAttachment" },
}

-- Bends joints (by name, in degrees) and freezes the rig in that pose.
-- Doesn't rely on Roblox's joint objects at all (they've changed type over
-- the years): each part is placed straight from the rig attachments it
-- shares with its parent, working out from the root. Then the leftover
-- joints and the Humanoid are removed so nothing can move it again.
-- Call after PivotTo.
local function poseAndFreeze(rig: Model, angles: Pose)
	local function partNamed(name: string): BasePart?
		local found = rig:FindFirstChild(name)
		return if found and found:IsA("BasePart") then found else nil
	end
	local function attachmentOn(part: BasePart, name: string): Attachment?
		local found = part:FindFirstChild(name)
		return if found and found:IsA("Attachment") then found else nil
	end

	local wanted, bent, placed = 0, 0, 0
	for _ in angles do
		wanted += 1
	end

	for _, joint in R15_JOINTS do
		local jointName, parentName, childName, attachmentName = joint[1], joint[2], joint[3], joint[4]
		local parentPart, childPart = partNamed(parentName), partNamed(childName)
		local parentAttachment = parentPart and attachmentOn(parentPart, attachmentName)
		local childAttachment = childPart and attachmentOn(childPart, attachmentName)
		if parentPart and childPart and parentAttachment and childAttachment then
			local degrees = angles[jointName]
			local bend = CFrame.identity
			if degrees then
				bend = CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
				bent += 1
			end
			childPart.CFrame = parentPart.CFrame * parentAttachment.CFrame * bend * childAttachment.CFrame:Inverse()
			placed += 1
		else
			warn(`[Noodle Bonk] {rig.Name}: missing {childName} or its {attachmentName}`)
		end
	end

	-- The pose lives in the anchored parts now; clear out anything that could move them
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
			descendant:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end

	print(
		`[Noodle Bonk] Thumbnail v{SCENE_VERSION} {rig.Name}: bent {bent}/{wanted} joints, placed {placed}/{#R15_JOINTS} parts, `
			.. `classic head {if rig:GetAttribute("ClassicHead") then "OK" else "FAILED"}`
	)
end

local function gripOf(rig: Model): CFrame?
	local hand = rig:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	if grip and grip:IsA("Attachment") then
		return grip.WorldCFrame
	end
	return nil
end

-- Props ---------------------------------------------------------------------------

-- A bent foam noodle built from segments, like NoodleVisuals draws them.
-- Each segment turns by `yawBend` / `pitchBend` degrees, so it curves.
-- Returns the tip position.
local function buildNoodle(
	parent: Instance,
	base: Vector3,
	direction: Vector3,
	color: Color3,
	length: number,
	thickness: number,
	yawBend: number,
	pitchBend: number
): Vector3
	local noodle = model(parent, "Noodle")
	local segments = Config.NoodleSegments + 2
	local segmentLength = length / segments
	local frame = CFrame.lookAt(base, base + direction)
	local previous = base

	for i = 1, segments do
		frame = frame * CFrame.Angles(math.rad(pitchBend), math.rad(yawBend), 0) * CFrame.new(0, 0, -segmentLength)
		local point = frame.Position
		part(
			noodle,
			"Segment",
			Enum.PartType.Cylinder,
			Vector3.new(segmentLength + thickness * 0.1, thickness, thickness),
			CFrame.lookAt((previous + point) / 2, point) * CFrame.Angles(0, math.rad(90), 0),
			color
		)
		part(noodle, "Joint", Enum.PartType.Ball, Vector3.one * thickness, CFrame.new(point), color)
		previous = point
	end
	return previous
end

-- A cartoon impact star facing the camera, with "BONK!" text.
local function buildImpactStar(parent: Instance, position: Vector3, cameraPosition: Vector3, size: number)
	local star = model(parent, "ImpactStar")
	local facing = CFrame.lookAt(position, cameraPosition)

	part(star, "Core", Enum.PartType.Ball, Vector3.one * size * 0.9, facing, STAR_YELLOW, Enum.Material.Neon)
	local spikes = 10
	for i = 0, spikes - 1 do
		local long = i % 2 == 0
		local spikeLength = size * (if long then 1.6 else 1.05)
		local spin = facing * CFrame.Angles(0, 0, math.rad(i * 360 / spikes))
		part(
			star,
			"Spike",
			Enum.PartType.Block,
			Vector3.new(size * 0.32, spikeLength, size * 0.12),
			spin * CFrame.new(0, size * 0.35 + spikeLength / 2, 0),
			if long then STAR_YELLOW else STAR_ORANGE,
			Enum.Material.Neon
		)
	end

	local label = Instance.new("BillboardGui")
	label.Name = "BonkText"
	label.Size = UDim2.fromScale(size * 3.2, size * 1.3)
	label.StudsOffsetWorldSpace = Vector3.new(0, size * 1.6, 0)
	label.LightInfluence = 0
	label.Parent = star:FindFirstChild("Core")
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = "BONK!"
	text.TextColor3 = STAR_YELLOW
	text.Rotation = -8
	text.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(120, 40, 0)
	stroke.Parent = text
end

-- A big cartoon water splash: foam ring, a crown of leaning columns with
-- droplet tips, a tall center spout, and flying drops.
local function buildSplash(parent: Instance, position: Vector3, scale: number, seed: number)
	local splash = model(parent, "Splash")
	local random = Random.new(seed)

	part(splash, "Foam", Enum.PartType.Cylinder, Vector3.new(0.4, 10 * scale, 10 * scale), CFrame.new(position) * UPRIGHT, WATER_WHITE)
	part(splash, "FoamInner", Enum.PartType.Cylinder, Vector3.new(0.5, 6.5 * scale, 6.5 * scale), CFrame.new(position) * UPRIGHT, WATER_LIGHT)

	local columns = 12
	for i = 0, columns - 1 do
		local angle = i / columns * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local height = (4.5 + (i % 3) * 1.7 + random:NextNumber(0, 1)) * scale
		local thickness = (0.9 + random:NextNumber(0, 0.4)) * scale
		local color = if i % 2 == 0 then WATER_WHITE else WATER_LIGHT
		-- Lean each column outward from the middle
		local base = CFrame.lookAt(position, position + outward) * CFrame.new(0, 0, -2.6 * scale) * CFrame.Angles(math.rad(-28), 0, 0)
		part(splash, "Column", Enum.PartType.Cylinder, Vector3.new(height, thickness, thickness), base * CFrame.new(0, height / 2, 0) * UPRIGHT, color)
		part(splash, "Drop", Enum.PartType.Ball, Vector3.one * thickness * 1.5, base * CFrame.new(0, height, 0), color)
	end

	local spoutHeight = 10 * scale
	part(splash, "Spout", Enum.PartType.Cylinder, Vector3.new(spoutHeight, 1.8 * scale, 1.8 * scale), CFrame.new(position + Vector3.new(0, spoutHeight / 2, 0)) * UPRIGHT, WATER_WHITE)
	part(splash, "SpoutTop", Enum.PartType.Ball, Vector3.one * 2.8 * scale, CFrame.new(position + Vector3.new(0, spoutHeight, 0)), WATER_WHITE)

	for _ = 1, 12 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(2, 7) * scale
		local height = random:NextNumber(3, 13) * scale
		local offset = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		part(splash, "FlyingDrop", Enum.PartType.Ball, Vector3.one * random:NextNumber(0.5, 1.3) * scale, CFrame.new(position + offset), if random:NextNumber() > 0.5 then WATER_WHITE else WATER_LIGHT)
	end
end

local function buildBubble(parent: Instance, center: Vector3)
	local bubble = model(parent, "Bubble")
	part(bubble, "Bubble", Enum.PartType.Ball, Vector3.one * 9, CFrame.new(center), Color3.fromRGB(130, 210, 255), Enum.Material.ForceField)
	local random = Random.new(7)
	for _ = 1, 6 do
		local offset = Vector3.new(random:NextNumber(-6, 6), random:NextNumber(-5, 3), random:NextNumber(-6, 6))
		local small = part(bubble, "SmallBubble", Enum.PartType.Ball, Vector3.one * random:NextNumber(0.6, 1.4), CFrame.new(center + offset), Color3.fromRGB(190, 235, 255), Enum.Material.Glass)
		small.Transparency = 0.4
	end
end

-- Puffs of cloud trailing behind someone flying through the air.
local function buildTrail(parent: Instance, from: Vector3, backward: Vector3)
	local trail = model(parent, "LaunchTrail")
	for i = 1, 7 do
		local puff = part(trail, "Puff", Enum.PartType.Ball, Vector3.one * (2.6 - i * 0.25), CFrame.new(from + backward.Unit * (2.5 + i * 3.2)), Color3.new(1, 1, 1))
		puff.Transparency = 0.15 + i * 0.1
	end
end

-- Lighting -------------------------------------------------------------------------

local function effect<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local instance = Instance.new(className :: any)
	instance.Name = name
	instance.Parent = Lighting
	return instance :: any
end

-- Bright and saturated. Picks the time of day that puts the sun closest to `sunGoal`.
local function setupLighting(sunGoal: Vector3)
	-- Turn off the place's own effects so they don't stack with ours
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and string.sub(child.Name, 1, 9) ~= "Thumbnail" then
			child.Enabled = false
		end
	end

	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(110, 110, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 165)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.15
	Lighting.GeographicLatitude = 30

	local bestTime, bestScore = 14, -math.huge
	for step = 0, 40 do
		local time = 8 + step * 0.25
		Lighting.ClockTime = time
		local score = Lighting:GetSunDirection():Dot(sunGoal)
		if score > bestScore then
			bestTime, bestScore = time, score
		end
	end
	Lighting.ClockTime = bestTime

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "ThumbnailSky"
		sky.SunAngularSize = 14
		sky.Parent = Lighting
	end

	local atmosphere: Atmosphere = effect("Atmosphere", "ThumbnailAtmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 225, 255)
	atmosphere.Decay = Color3.fromRGB(106, 170, 220)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2

	local bloom: BloomEffect = effect("BloomEffect", "ThumbnailBloom")
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.5

	local color: ColorCorrectionEffect = effect("ColorCorrectionEffect", "ThumbnailColor")
	color.Saturation = 0.35
	color.Contrast = 0.18
	color.Brightness = 0.02
	color.TintColor = Color3.fromRGB(255, 248, 240)

	local rays: SunRaysEffect = effect("SunRaysEffect", "ThumbnailSunRays")
	rays.Intensity = 0.05
	rays.Spread = 0.6

	local depth: DepthOfFieldEffect = effect("DepthOfFieldEffect", "ThumbnailDepthOfField")
	depth.FarIntensity = 0.2
	depth.FocusDistance = 16
	depth.InFocusRadius = 28
	depth.NearIntensity = 0
end

-- A bent noodle from `grip` reaching toward `target`. Returns the tip.
local function noodleToward(parent: Instance, grip: Vector3, target: Vector3, color: Color3, thickness: number, yawBend: number, pitchBend: number): Vector3
	local offset = target - grip
	-- The bend curls the noodle, so start it angled the other way to land near the target
	local aim = CFrame.lookAt(grip, target) * CFrame.Angles(math.rad(-pitchBend * 2.5), math.rad(-yawBend * 2.5), 0)
	return buildNoodle(parent, grip, aim.LookVector, color, offset.Magnitude * 1.02, thickness, yawBend, pitchBend)
end

-- Scene ------------------------------------------------------------------------------

function ThumbnailScene.build()
	print(`[Noodle Bonk] Building thumbnail scene v{SCENE_VERSION}...`)
	local old = workspace:FindFirstChild("ThumbnailScene")
	if old then
		old:Destroy()
	end
	local scene = model(workspace, "ThumbnailScene")
	local characters = Instance.new("Folder")
	characters.Name = "Characters"
	characters.Parent = scene
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = scene

	-- Raise the sea for the shot so the water (and splashes) sit in frame
	local waterTop = -6
	workspace.Terrain:FillBlock(CFrame.new(0, (Config.WaterLevel + waterTop) / 2, 0), Vector3.new(2048, waterTop - Config.WaterLevel, 2048), Enum.Material.Water)

	-- The shot looks along the deck's edge: deck on the right, open water on the left.
	local edge = Config.ArenaDiameter / 2
	local cameraPosition = Vector3.new(22, 2, edge + 5)
	local look = Vector3.new(-42, 0, -12).Unit
	local right = look:Cross(Vector3.yAxis).Unit -- screen right (toward the deck)
	local function at(forward: number, sideways: number, height: number): Vector3
		return Vector3.new(cameraPosition.X, 0, cameraPosition.Z) + look * forward + right * sideways + Vector3.new(0, height, 0)
	end

	-- Foreground attacker, mid-swing at the deck's edge -----------------------------
	local attackerPosition = at(13, 4, 3)
	local hitSpot = at(14, -3, 6) -- where the noodle meets the victim
	local attacker = makeRig(characters, "Attacker", {
		shirt = Color3.fromRGB(255, 70, 160),
		pants = Color3.fromRGB(40, 60, 200),
	}, FACE_EPIC_GRIN)
	if attacker then
		local toVictim = flat(hitSpot - attackerPosition).Unit
		attacker:PivotTo(CFrame.lookAt(attackerPosition, attackerPosition + toVictim))
		poseAndFreeze(attacker, {
			Waist = Vector3.new(0, 30, 0), -- twisted into the swing
			Neck = Vector3.new(10, 10, 0),
			RightShoulder = Vector3.new(80, 40, 0), -- arm whipped forward and across
			RightElbow = Vector3.new(15, 0, 0),
			LeftShoulder = Vector3.new(-35, 0, -45), -- other arm flung back
			LeftElbow = Vector3.new(30, 0, 0),
			RightHip = Vector3.new(35, 0, 5), -- lunge
			RightKnee = Vector3.new(-45, 0, 0),
			LeftHip = Vector3.new(-25, 0, -5),
			LeftKnee = Vector3.new(-30, 0, 0),
		})
	end

	-- The big bent pink noodle reaching the victim, and the impact star at its tip
	local tip = hitSpot
	local grip = attacker and gripOf(attacker)
	if grip then
		tip = noodleToward(props, grip.Position, hitSpot, Noodles.Classic.Color, 1.15, -7, -2)
	end
	buildImpactStar(props, tip, cameraPosition, 1.4)

	-- Victim, launched off the edge toward the camera ------------------------------
	local victim = makeRig(characters, "Victim", {
		shirt = Color3.fromRGB(60, 220, 120),
		pants = Color3.fromRGB(255, 200, 40),
	}, FACE_SHOCKED)
	if victim then
		-- Their hip sits at the hit point, body flying toward the camera
		local victimPosition = tip + flat(cameraPosition - tip).Unit * 1.6 - right * 0.8 + Vector3.new(0, 1.2, 0)
		victim:PivotTo(
			CFrame.lookAt(victimPosition, cameraPosition + Vector3.new(0, 2, 0))
				* CFrame.Angles(math.rad(-20), 0, math.rad(22)) -- tipped back, mid-tumble
		)
		poseAndFreeze(victim, {
			Neck = Vector3.new(-10, 0, 10),
			RightShoulder = Vector3.new(20, 0, 145), -- arms flailing up and out
			RightElbow = Vector3.new(40, 0, 0),
			LeftShoulder = Vector3.new(-10, 0, -120),
			LeftElbow = Vector3.new(55, 0, 0),
			RightHip = Vector3.new(30, 0, 35), -- legs kicking apart
			RightKnee = Vector3.new(-50, 0, 0),
			LeftHip = Vector3.new(-35, 0, -30),
			LeftKnee = Vector3.new(-25, 0, 0),
		})
	end

	-- Background: two players bonking each other on the deck, clear of the attacker
	local spotA = at(42, 20, 3)
	local spotB = spotA + look * 4 + right * 4
	local fighterA = makeRig(characters, "FighterYellow", {
		shirt = Color3.fromRGB(255, 220, 40),
		pants = Color3.fromRGB(150, 60, 220),
	}, FACE_PRANKSTER)
	local fighterB = makeRig(characters, "FighterGreen", {
		shirt = Color3.fromRGB(40, 200, 255),
		pants = Color3.fromRGB(255, 90, 60),
	}, FACE_SHOCKED)
	if fighterA and fighterB then
		-- Facing each other, turned a little toward the camera
		fighterA:PivotTo(CFrame.lookAt(spotA, Vector3.new(spotB.X, spotA.Y, spotB.Z)) * CFrame.Angles(0, math.rad(-35), 0))
		fighterB:PivotTo(CFrame.lookAt(spotB, Vector3.new(spotA.X, spotB.Y, spotA.Z)) * CFrame.Angles(0, math.rad(30), 0))
		poseAndFreeze(fighterA, {
			Waist = Vector3.new(0, 35, 0),
			RightShoulder = Vector3.new(95, 30, 0),
			LeftShoulder = Vector3.new(-30, 0, -35),
			RightHip = Vector3.new(30, 0, 0),
			RightKnee = Vector3.new(-35, 0, 0),
			LeftHip = Vector3.new(-20, 0, 0),
		})
		poseAndFreeze(fighterB, {
			Waist = Vector3.new(-15, -20, 0), -- recoiling
			Neck = Vector3.new(-15, 0, 0),
			RightShoulder = Vector3.new(150, -20, 0), -- noodle raised high
			RightElbow = Vector3.new(20, 0, 0),
			LeftShoulder = Vector3.new(30, 0, -60),
			RightHip = Vector3.new(-15, 0, 10),
			LeftHip = Vector3.new(20, 0, -10),
			LeftKnee = Vector3.new(-30, 0, 0),
		})
		local gripA = gripOf(fighterA)
		local headB = fighterB:FindFirstChild("Head")
		if gripA and headB and headB:IsA("BasePart") then
			-- A's yellow noodle bonks B on the head
			noodleToward(props, gripA.Position, headB.Position + Vector3.new(0, 0.6, 0), Noodles.Spring.Color, 0.9, 6, -3)
		end
		local gripB = gripOf(fighterB)
		if gripB then
			buildNoodle(props, gripB.Position, gripB.LookVector, Noodles.Whip.Color, 9, 0.75, -7, 6)
		end
	end

	-- Someone floating in a bubble, above the water near the middle of the shot
	local bubbleCenter = at(32, 1, 12)
	local floater = makeRig(characters, "BubbleFloater", {
		shirt = Color3.fromRGB(255, 140, 40),
		pants = Color3.fromRGB(60, 160, 255),
	}, FACE_DROOL)
	if floater then
		floater:PivotTo(CFrame.lookAt(bubbleCenter, cameraPosition) * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-12)))
		poseAndFreeze(floater, {
			RightHip = Vector3.new(80, 0, 10), -- curled up, sitting in the bubble
			RightKnee = Vector3.new(-85, 0, 0),
			LeftHip = Vector3.new(80, 0, -10),
			LeftKnee = Vector3.new(-85, 0, 0),
			RightShoulder = Vector3.new(60, 0, 30),
			LeftShoulder = Vector3.new(60, 0, -30),
			RightElbow = Vector3.new(60, 0, 0),
			LeftElbow = Vector3.new(60, 0, 0),
		})
	end
	buildBubble(props, bubbleCenter)

	-- Someone launched high into the sky, upper right
	local skySpot = at(45, 20, 27)
	local flyer = makeRig(characters, "SkyLaunched", {
		shirt = Color3.fromRGB(190, 90, 255),
		pants = Color3.fromRGB(255, 255, 255),
	}, FACE_BIG_D)
	if flyer then
		flyer:PivotTo(CFrame.lookAt(skySpot, cameraPosition) * CFrame.Angles(math.rad(-35), 0, math.rad(-30)))
		poseAndFreeze(flyer, {
			RightShoulder = Vector3.new(0, 0, 160),
			LeftShoulder = Vector3.new(0, 0, -160),
			RightHip = Vector3.new(0, 0, 40),
			LeftHip = Vector3.new(0, 0, -40),
			RightKnee = Vector3.new(-30, 0, 0),
			LeftKnee = Vector3.new(-30, 0, 0),
		})
	end
	buildTrail(props, skySpot, Vector3.new(0.3, -1, 0.6))

	-- Splashes where people hit the water, spread out so none hides another
	buildSplash(props, at(24, -15, waterTop), 1.1, 1)
	buildSplash(props, at(52, -10, waterTop), 1.4, 2)
	buildSplash(props, at(85, -38, waterTop), 1.8, 3)

	-- Camera: low and looking slightly up, 16:9. The top-left is open sky for the logo.
	local camera = Instance.new("Camera")
	camera.Name = "ThumbnailCamera"
	camera.FieldOfView = 55
	-- Aim a bit left of the action so it sits right of center
	camera.CFrame = CFrame.lookAt(cameraPosition, at(43, -4, 7))
	camera.Parent = scene

	-- Icon camera: a square close-up of the grinning attacker, the noodle and
	-- the hit. Set Config.ThumbnailShot = "Icon" to look through it.
	local iconCamera = Instance.new("Camera")
	iconCamera.Name = "IconCamera"
	iconCamera.FieldOfView = 40
	iconCamera.CFrame = camera.CFrame
	local head = attacker and attacker:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local face = head.CFrame
		-- In front of the face, off to the side away from the victim, a little low
		local iconPosition = face.Position + face.LookVector * 7 + face.RightVector * 3.5 - Vector3.new(0, 1.2, 0)
		-- Aim between the face and the noodle so both fill the square
		local focus = face.Position + face.LookVector * 1.5 - face.RightVector * 1.5 - Vector3.new(0, 0.6, 0)
		iconCamera.CFrame = CFrame.lookAt(iconPosition, focus)
	end
	iconCamera.Parent = scene

	local active = if Config.ThumbnailShot == "Icon" then iconCamera else camera
	scene:SetAttribute("ActiveCamera", active.Name)
	local current = workspace.CurrentCamera
	if current then
		current.CameraType = Enum.CameraType.Scriptable
		current.FieldOfView = active.FieldOfView
		current.CFrame = active.CFrame
	end

	-- Sun behind the camera and high, so faces are lit
	setupLighting((flat(cameraPosition - attackerPosition).Unit + Vector3.new(0, 1.1, 0)).Unit)

	print(`[Noodle Bonk] Thumbnail scene v{SCENE_VERSION} ready, looking through {active.Name}. See the README for screenshot steps.`)
end

return ThumbnailScene
