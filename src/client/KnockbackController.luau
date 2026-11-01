--!strict
-- Applies knockback sent by the server. Your own character's physics run on
-- your client, so the push has to be applied here for it to look smooth.
-- (The server turns the joints floppy at the same time; see server/Ragdoll.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local CameraController = require(script.Parent.CameraController)

type KnockbackInfo = Remotes.KnockbackInfo

local player = Players.LocalPlayer

local KnockbackController = {}

-- Tokens let a newer launch cancel the timers of an older one
local ragdollToken = 0
local floatToken = 0
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

local function getUp(humanoid: Humanoid)
	if humanoid.Health > 0 and humanoid:GetState() == Enum.HumanoidStateType.Physics then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function onKnockback(info: KnockbackInfo)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	floatToken += 1 -- any new launch ends a float
	ragdollToken += 1

	local float = info.float
	if float then
		-- Drift along at a steady speed (bubble)
		local token = floatToken
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.spawn(function()
			local endTime = os.clock() + float.time
			while os.clock() < endTime and token == floatToken and humanoid.Health > 0 do
				root.AssemblyLinearVelocity = float.velocity
				root.AssemblyAngularVelocity = Vector3.zero
				RunService.Heartbeat:Wait()
			end
			if token == floatToken then
				getUp(humanoid)
			end
		end)
	elseif info.ragdollTime > 0 then
		-- Physics state turns off the Humanoid's balance so the body flops
		local token = ragdollToken
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		root.AssemblyAngularVelocity = randomSpin()
		task.delay(info.ragdollTime, function()
			if token == ragdollToken then
				getUp(humanoid)
			end
		end)
	else
		-- Leave the ground first so floor friction doesn't eat the push
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	root.AssemblyLinearVelocity = info.velocity

	if info.stunTime and info.stunTime > 0 then
		stun(humanoid, info.stunTime)
	end
	if info.shake then
		CameraController.shake(info.shake)
	end
end

function KnockbackController.start()
	Remotes.Knockback.OnClientEvent:Connect(onKnockback)
	player.CharacterAdded:Connect(function()
		-- Fresh character, fresh movement values
		savedMovement = nil
		stunToken += 1
		ragdollToken += 1
		floatToken += 1
	end)
end

return KnockbackController
