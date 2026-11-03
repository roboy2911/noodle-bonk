--!strict
-- Moon noodle: while you hold it you're floaty. A force pushes up on your
-- character so gravity feels like Config.MoonGravity of normal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)

local player = Players.LocalPlayer

local LowGravity = {}

local FORCE_NAME = "MoonFloat"

local function holdingMoon(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("NoodleId")
	local def = if type(id) == "string" then Noodles[id] else nil
	return def ~= nil and def.Gimmick == "LowGravity"
end

local function step()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	local force = root:FindFirstChild(FORCE_NAME)
	if holdingMoon(character) then
		if not force then
			local attachment = Instance.new("Attachment")
			attachment.Name = FORCE_NAME .. "Attachment"
			attachment.Parent = root
			local vectorForce = Instance.new("VectorForce")
			vectorForce.Name = FORCE_NAME
			vectorForce.Attachment0 = attachment
			vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
			vectorForce.ApplyAtCenterOfMass = true
			vectorForce.Parent = root
			force = vectorForce
		end
		local mass = root.AssemblyMass;
		(force :: VectorForce).Force = Vector3.new(0, mass * workspace.Gravity * (1 - Config.MoonGravity), 0)
	elseif force then
		force:Destroy()
		local attachment = root:FindFirstChild(FORCE_NAME .. "Attachment")
		if attachment then
			attachment:Destroy()
		end
	end
end

function LowGravity.start()
	RunService.Heartbeat:Connect(step)
end

return LowGravity
