--!strict
-- Spawns practice dummies so there's always something to bonk. BonkTracker
-- resets them after a bonk. On server start, Config.DummyCount of them stand
-- in a ring around the arena (0 turns that off). The admin panel can add more
-- or clear them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local DummySpawner = {}

local nextNumber = 1

local function getFolder(): Folder
	local existing = workspace:FindFirstChild("Dummies")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace
	return folder
end

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

local function spawnAt(position: Vector3, folder: Folder): boolean
	local rig = buildRig()
	if not rig then
		return false
	end

	local name = `Dummy {nextNumber}`
	nextNumber += 1
	rig.Name = name
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
	end

	-- Face the middle of the ring. The root sits about 3 studs above the floor on R15.
	local center = Config.DummyRingCenter
	local raised = position + Vector3.new(0, 3, 0)
	rig:PivotTo(CFrame.lookAt(raised, Vector3.new(center.X, raised.Y, center.Z)))

	-- Tag after positioning: BonkTracker saves the spot it sees when the tag appears
	rig:AddTag(Config.DummyTag)
	rig.Parent = folder

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
	return true
end

-- Spawns `count` dummies (default Config.DummyCount). The first batch forms an
-- even ring; later batches land at random spots on the deck. Returns how many spawned.
function DummySpawner.spawn(count: number?): number
	local amount = count or Config.DummyCount
	if amount <= 0 then
		return 0
	end
	local folder = getFolder()
	local firstBatch = #folder:GetChildren() == 0
	local center = Config.DummyRingCenter
	local spawned = 0

	for i = 1, amount do
		local angle, radius
		if firstBatch then
			angle = (i - 1) / amount * math.pi * 2
			radius = Config.DummyRingRadius
		else
			angle = math.random() * math.pi * 2
			radius = 10 + math.random() * (Config.DummyRingRadius + 15)
		end
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		if spawnAt(position, folder) then
			spawned += 1
		end
	end
	return spawned
end

-- Removes every dummy. Returns how many were removed.
function DummySpawner.clear(): number
	local folder = getFolder()
	local removed = #folder:GetChildren()
	folder:ClearAllChildren()
	return removed
end

return DummySpawner
