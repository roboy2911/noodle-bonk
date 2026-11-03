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

-- Fire noodle: your controls stop working and you run around in a panic.
local panicToken = 0
local panicControls: any = nil
local function panic(humanoid: Humanoid, duration: number)
	panicToken += 1
	local token = panicToken
	if not panicControls then
		pcall(function()
			local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any)
			panicControls = playerModule:GetControls()
		end)
	end
	local controls = panicControls
	if controls then
		controls:Disable()
	end
	task.spawn(function()
		local endTime = os.clock() + duration
		while os.clock() < endTime and token == panicToken and humanoid.Health > 0 do
			local angle = math.random() * math.pi * 2
			humanoid:Move(Vector3.new(math.cos(angle), 0, math.sin(angle)))
			if math.random() < 0.3 then
				humanoid.Jump = true
			end
			task.wait(0.3)
		end
		if token == panicToken then
			humanoid:Move(Vector3.zero)
			if controls then
				controls:Enable()
			end
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
	local follow = info.follow
	if follow then
		-- Stuck to someone's noodle (Gum): stay a set distance in front of
		-- them, then get flung
		local token = floatToken
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.spawn(function()
			local endTime = os.clock() + follow.time
			while os.clock() < endTime and token == floatToken and humanoid.Health > 0 and follow.target.Parent do
				local anchor = follow.target.CFrame
				local goal = anchor.Position + anchor.LookVector * follow.distance + Vector3.yAxis * 1.5
				root.AssemblyLinearVelocity = (goal - root.Position) * 12
				root.AssemblyAngularVelocity = Vector3.zero
				RunService.Heartbeat:Wait()
			end
			if token == floatToken and humanoid.Health > 0 then
				root.AssemblyLinearVelocity = follow.fling
				root.AssemblyAngularVelocity = randomSpin()
				task.delay(1, function()
					if token == floatToken then
						getUp(humanoid)
					end
				end)
			end
		end)
		return
	elseif float then
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
	if info.spin then
		root.AssemblyAngularVelocity = info.spin
	end
	if info.panic and info.panic > 0 then
		panic(humanoid, info.panic)
	end

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
		panicToken += 1
		if panicControls then
			panicControls:Enable() -- never respawn with your controls switched off
		end
	end)
end

return KnockbackController
