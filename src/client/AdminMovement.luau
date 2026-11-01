--!strict
-- Fly and noclip, switched on from the admin panel (the server sets the
-- AdminFly / AdminNoclip attributes on the Player). Your client owns your
-- character's physics, so the movement itself runs here.
--
-- Flying: move as usual, Space to go up, Q to go down.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FLY_SPEED = 70

local player = Players.LocalPlayer

local AdminMovement = {}

local flyVelocity: LinearVelocity? = nil
local flyAttachment: Attachment? = nil
local flying = false
local noclipSaved: { [BasePart]: boolean } = {}

local function stopFlying(humanoid: Humanoid?)
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
	if flyAttachment then
		flyAttachment:Destroy()
		flyAttachment = nil
	end
	if flying and humanoid then
		humanoid.PlatformStand = false
	end
	flying = false
end

local function updateFly()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not player:GetAttribute("AdminFly") or not humanoid or not root or not root:IsA("BasePart") then
		if flying then
			stopFlying(humanoid)
		end
		return
	end

	if not flyVelocity or flyVelocity.Parent ~= root then
		stopFlying(nil)
		local attachment = Instance.new("Attachment")
		attachment.Name = "AdminFlyAttachment"
		attachment.Parent = root
		local velocity = Instance.new("LinearVelocity")
		velocity.Name = "AdminFly"
		velocity.Attachment0 = attachment
		velocity.MaxForce = math.huge
		velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.Parent = root
		flyAttachment = attachment
		flyVelocity = velocity
	end
	flying = true
	humanoid.PlatformStand = true

	local vertical = 0
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vertical += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			vertical -= 1
		end
	end
	local velocity = flyVelocity :: LinearVelocity
	velocity.VectorVelocity = humanoid.MoveDirection * FLY_SPEED + Vector3.yAxis * vertical * FLY_SPEED
end

local function updateNoclip()
	local character = player.Character
	if player:GetAttribute("AdminNoclip") and character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				noclipSaved[part] = true
				part.CanCollide = false
			end
		end
	elseif next(noclipSaved) then
		-- Put back exactly what we turned off
		for part in noclipSaved do
			if part.Parent then
				part.CanCollide = true
			end
		end
		table.clear(noclipSaved)
	end
end

function AdminMovement.start()
	RunService.Heartbeat:Connect(updateFly)
	-- Stepped runs before physics, so collisions are off by the time they'd happen
	RunService.Stepped:Connect(updateNoclip)
	player.CharacterAdded:Connect(function()
		flying = false
		flyVelocity = nil
		flyAttachment = nil
		table.clear(noclipSaved)
	end)
end

return AdminMovement
