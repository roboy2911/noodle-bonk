--!strict
-- Spawns practice dummies in a ring around the arena when the server starts,
-- so there's always something to bonk. BonkTracker resets them after a bonk.
-- Set Config.DummyCount to 0 to turn this off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local DummySpawner = {}

local function buildRig(): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Config.DummyColor
	description.TorsoColor = Config.DummyColor
	description.LeftArmColor = Config.DummyColor
	description.RightArmColor = Config.DummyColor
	description.LeftLegColor = Config.DummyColor
	description.RightLegColor = Config.DummyColor

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn(`[Noodle Bonk] Couldn't build a dummy: {result}`)
		return nil
	end
	return result
end

local function spawnDummy(index: number, total: number, folder: Folder)
	local rig = buildRig()
	if not rig then
		return
	end

	local name = `Dummy {index}`
	rig.Name = name
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
	end

	-- Evenly spaced around the ring, facing the middle. The root sits about
	-- 3 studs above the floor on an R15 rig.
	local center = Config.DummyRingCenter
	local angle = (index - 1) / total * math.pi * 2
	local position = center
		+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.DummyRingRadius
		+ Vector3.new(0, 3, 0)
	rig:PivotTo(CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))

	-- Tag after positioning: BonkTracker saves the spot it sees when the tag appears
	rig:AddTag(Config.DummyTag)
	rig.Parent = folder

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
end

function DummySpawner.spawn()
	if Config.DummyCount <= 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	for i = 1, Config.DummyCount do
		spawnDummy(i, Config.DummyCount, folder)
	end
end

return DummySpawner
