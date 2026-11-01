--!strict
-- Spawns practice dummies. BonkTracker resets them after a bonk. When a player
-- is alone in a server, server/SoloDummy spawns one that fights them. The
-- admin panel can add more or clear them.

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

local function spawnAt(position: Vector3, folder: Folder, solo: boolean?): boolean
	local rig = buildRig()
	if not rig then
		return false
	end

	local name = if solo then Config.SoloDummyName else `Dummy {nextNumber}`
	if not solo then
		nextNumber += 1
	end
	rig.Name = name
	if solo then
		rig:SetAttribute("SoloDummy", true) -- server/SoloDummy manages it, and it always fights
	end
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
-- `solo` marks them as the solo-player dummy (see server/SoloDummy).
function DummySpawner.spawn(count: number?, solo: boolean?): number
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
		if spawnAt(position, folder, solo) then
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
