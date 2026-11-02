--!strict
-- Always-on shift lock. The mouse is locked to the center, the camera sits
-- over your shoulder, and your character always faces where the camera looks.
-- Turning the camera is how you swing your noodle.
--
-- The cursor is freed while the noodle menu, chat or the Roblox menu is open,
-- and Ctrl toggles it manually. Roblox's own shift lock is turned off in
-- default.project.json (StarterPlayer.EnableMouseLockOption).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local SHOULDER_OFFSET = Vector3.new(1.75, 0.25, 0)
local FREE_CURSOR_ACTION = "ToggleFreeCursor"

local CameraController = {}

local cursorToggledFree = false
local freeReasons: { [string]: boolean } = {}
local shakeAmount = 0

-- UI calls this to free the cursor while it's open, e.g. ("NoodleMenu", true).
function CameraController.setCursorFree(reason: string, free: boolean)
	if free then
		freeReasons[reason] = true
	else
		freeReasons[reason] = nil
	end
end

-- Adds a camera shake. Strength around 0.1 (light) to 1 (huge).
function CameraController.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

function CameraController.isCursorFree(): boolean
	return cursorToggledFree
		or next(freeReasons) ~= nil
		or GuiService.MenuIsOpen
		or UserInputService:GetFocusedTextBox() ~= nil
end

local function isStunned(character: Model): boolean
	local stunnedUntil = character:GetAttribute("StunnedUntil")
	return type(stunnedUntil) == "number" and stunnedUntil > workspace:GetServerTimeNow()
end

-- Tornado noodle: spinning on the spot instead of facing the camera
local function isSpinning(character: Model): boolean
	local spinningUntil = character:GetAttribute("SpinningUntil")
	return type(spinningUntil) == "number" and spinningUntil > workspace:GetServerTimeNow()
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = if CameraController.isCursorFree()
			then Enum.MouseBehavior.Default
			else Enum.MouseBehavior.LockCenter
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and root and root:IsA("BasePart") then
		humanoid.AutoRotate = false
		humanoid.CameraOffset = SHOULDER_OFFSET

		-- Face the camera, unless flopping around or stunned
		local state = humanoid:GetState()
		local canTurn = humanoid.Health > 0
			and state ~= Enum.HumanoidStateType.Physics
			and state ~= Enum.HumanoidStateType.Dead
			and not isStunned(character)
		if canTurn and isSpinning(character) then
			root.CFrame *= CFrame.Angles(0, Config.TornadoSpinSpeed * dt, 0)
		elseif canTurn then
			local look = camera.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
			end
		end
	end

	if shakeAmount > 0.001 then
		local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shakeAmount
		camera.CFrame *= CFrame.new(offset)
		shakeAmount = math.max(0, shakeAmount - dt * 2.5)
	end
end

function CameraController.start()
	-- Run right after Roblox's camera has updated for the frame
	RunService:BindToRenderStep("NoodleShiftLock", Enum.RenderPriority.Camera.Value + 1, update)

	ContextActionService:BindAction(FREE_CURSOR_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			cursorToggledFree = not cursorToggledFree
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
end

return CameraController
