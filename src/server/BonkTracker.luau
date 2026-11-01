--!strict
-- Watches for anyone falling off the island, credits the bonk to whoever hit
-- them last, and tells every client so they can show the banner and kill feed.
--
-- Dummies (anything tagged Config.DummyTag) reset to their starting spot
-- when bonked. DummySpawner makes a few automatically.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DUMMY_TAG = Config.DummyTag

-- Sent to clients through Remotes.Bonked
export type BonkInfo = {
	attacker: Player?, -- nil if nobody gets credit (they just fell)
	victim: Player?, -- nil for dummies
	victimName: string,
	noodleId: string?,
	position: Vector3,
}

local BonkTracker = {}

local combat: any -- CombatService, set in start()
local dummySpawns: { [Model]: CFrame } = {}

local function addLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local bonks = Instance.new("IntValue")
	bonks.Name = "Bonks"
	bonks.Parent = stats

	stats.Parent = player
end

local function creditBonk(attacker: Player)
	local stats = attacker:FindFirstChild("leaderstats")
	local bonks = stats and stats:FindFirstChild("Bonks")
	if bonks and bonks:IsA("IntValue") then
		bonks.Value += 1
	end
end

local function resetDummy(dummy: Model)
	local spawnCFrame = dummySpawns[dummy]
	if not dummy.Parent or not spawnCFrame then
		return
	end
	dummy:PivotTo(spawnCFrame)
	local root = dummy:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	dummy:SetAttribute("Soak", 0)
	dummy:SetAttribute("Bonked", nil)
end

local function bonk(character: Model, root: BasePart)
	character:SetAttribute("Bonked", true)

	local record = combat.getCredit(character)
	combat.clearHits(character)

	local victim = Players:GetPlayerFromCharacter(character)
	local attacker: Player? = record and record.attacker
	if attacker == victim then
		attacker = nil
	end
	if attacker then
		creditBonk(attacker)
	end

	local info: BonkInfo = {
		attacker = attacker,
		victim = victim,
		victimName = if victim then victim.DisplayName else character.Name,
		noodleId = record and record.noodleId,
		position = root.Position,
	}
	Remotes.Bonked:FireAllClients(info)

	if victim then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	else
		task.delay(Config.RespawnTime, resetDummy, character)
	end
end

local function check(character: Model?)
	if not character or character:GetAttribute("Bonked") then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.Position.Y < Config.KillY then
		bonk(character, root)
	end
end

local function addDummy(instance: Instance)
	if instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") then
		dummySpawns[instance] = instance:GetPivot()
	end
end

function BonkTracker.start(combatService: any)
	combat = combatService

	Players.PlayerAdded:Connect(addLeaderstats)
	for _, player in Players:GetPlayers() do
		addLeaderstats(player)
	end

	CollectionService:GetInstanceAddedSignal(DUMMY_TAG):Connect(addDummy)
	CollectionService:GetInstanceRemovedSignal(DUMMY_TAG):Connect(function(instance)
		dummySpawns[instance :: Model] = nil
	end)
	for _, instance in CollectionService:GetTagged(DUMMY_TAG) do
		addDummy(instance)
	end

	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			check(player.Character)
		end
		for dummy in dummySpawns do
			check(dummy)
		end
	end)
end

return BonkTracker
