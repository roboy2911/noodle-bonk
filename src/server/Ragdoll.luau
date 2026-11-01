--!strict
-- Floppy ragdoll. Each body joint (Motor6D) gets a matching BallSocketConstraint.
-- Ragdolling turns the motors off and the sockets on, so limbs flop freely.
-- It's toggled on the server so every player sees it. The victim's client
-- puts its Humanoid into the Physics state (see client/KnockbackController).

local Ragdoll = {}

local ROOT_JOINTS = { Root = true, RootJoint = true } -- R15 and R6 names; these stay on

local tokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function isBodyJoint(instance: Instance): boolean
	return instance:IsA("Motor6D") and not ROOT_JOINTS[instance.Name]
end

local function noCollide(a: BasePart, b: BasePart, parent: Instance)
	local constraint = Instance.new("NoCollisionConstraint")
	constraint.Part0 = a
	constraint.Part1 = b
	constraint.Parent = parent
end

-- Adds the sockets once per character. Safe to call again.
function Ragdoll.setup(character: Model)
	if character:GetAttribute("RagdollReady") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	humanoid.RequiresNeck = false -- otherwise turning off the neck joint kills them

	local folder = Instance.new("Folder")
	folder.Name = "RagdollConstraints"
	folder.Parent = character

	for _, motor in character:GetDescendants() do
		if isBodyJoint(motor) then
			local joint = motor :: Motor6D
			local part0, part1 = joint.Part0, joint.Part1
			if part0 and part1 then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollAttachment"
				a0.CFrame = joint.C0
				a0.Parent = part0

				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollAttachment"
				a1.CFrame = joint.C1
				a1.Parent = part1

				local socket = Instance.new("BallSocketConstraint")
				socket.Name = joint.Name
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 60
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -45
				socket.TwistUpperAngle = 45
				socket.Enabled = false
				socket.Parent = folder

				-- Joined parts overlap, so they must not collide with each other
				noCollide(part0, part1, folder)
			end
		end
	end

	-- The root part overlaps the torso; keep it from shoving limbs around
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			noCollide(root, part, folder)
		end
	end

	character:SetAttribute("RagdollReady", true)
end

local function setRagdolled(character: Model, on: boolean)
	for _, descendant in character:GetDescendants() do
		if isBodyJoint(descendant) then
			(descendant :: Motor6D).Enabled = not on
		elseif descendant:IsA("BallSocketConstraint") and descendant.Parent and descendant.Parent.Name == "RagdollConstraints" then
			descendant.Enabled = on
		end
	end

	-- Limbs normally don't collide; while ragdolled they need to, or they sink through the floor
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if on then
				if part:GetAttribute("RagdollCollide") == nil then
					part:SetAttribute("RagdollCollide", part.CanCollide)
				end
				part.CanCollide = true
			else
				local original = part:GetAttribute("RagdollCollide")
				if type(original) == "boolean" then
					part.CanCollide = original
				end
				part:SetAttribute("RagdollCollide", nil)
			end
		end
	end
	character:SetAttribute("Ragdolled", on or nil)
end

-- Ragdolls `character` for `duration` seconds. A newer call extends it.
function Ragdoll.enable(character: Model, duration: number)
	Ragdoll.setup(character)
	if not character:GetAttribute("RagdollReady") then
		return
	end
	local token = (tokens[character] or 0) + 1
	tokens[character] = token
	setRagdolled(character, true)

	task.delay(duration, function()
		if tokens[character] ~= token or not character.Parent then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			setRagdolled(character, false)
		end
	end)
end

return Ragdoll
