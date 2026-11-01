--!strict
-- Applies knockback sent by the server. Your own character's physics run on
-- your client, so the push has to be applied here for it to look smooth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local KnockbackController = {}

-- Tokens let a newer ragdoll or stun cancel the timer of an older one
local ragdollToken = 0
local stunToken = 0
local savedMovement: { walkSpeed: number, jumpPower: number, jumpHeight: number }? = nil

local function randomSpin(): Vector3
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
end

local function stun(humanoid: Humanoid, duration: number)
	stunToken += 1
	local token = stunToken

	if not savedMovement then
		savedMovement = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
		}
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	task.delay(duration, function()
		local saved = savedMovement
		if token ~= stunToken or not saved then
			return
		end
		savedMovement = nil
		if humanoid.Parent then
			humanoid.WalkSpeed = saved.walkSpeed
			humanoid.JumpPower = saved.jumpPower
			humanoid.JumpHeight = saved.jumpHeight
		end
	end)
end

local function onKnockback(velocity: Vector3, ragdollTime: number, stunTime: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	if ragdollTime > 0 then
		-- Physics state turns off the Humanoid's balance so the body tumbles
		ragdollToken += 1
		local token = ragdollToken
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		root.AssemblyAngularVelocity = randomSpin()
		task.delay(ragdollTime, function()
			if
				token == ragdollToken
				and humanoid.Health > 0
				and humanoid:GetState() == Enum.HumanoidStateType.Physics
			then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	else
		-- Leave the ground first so floor friction doesn't eat the push
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	root.AssemblyLinearVelocity = velocity

	if stunTime and stunTime > 0 then
		stun(humanoid, stunTime)
	end
end

function KnockbackController.start()
	Remotes.Knockback.OnClientEvent:Connect(onKnockback)
	player.CharacterAdded:Connect(function()
		-- Fresh character, fresh movement values
		savedMovement = nil
		stunToken += 1
		ragdollToken += 1
	end)
end

return KnockbackController
