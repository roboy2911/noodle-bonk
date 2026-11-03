--!strict
-- Watches for anyone falling off the island, credits the bonk to whoever hit
-- them last, updates saved stats, and tells every client so they can show
-- the banner, kill feed and splash.
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
local DataService = require(script.Parent.DataService)
local Streaks = require(script.Parent.Streaks)
local MonetizationService = require(script.Parent.MonetizationService)
local DuckJar = require(script.Parent.DuckJar)
local SecretService = require(script.Parent.SecretService)

-- Sent to clients through Remotes.Bonked
export type BonkInfo = {
	attacker: Player?, -- nil if nobody gets credit (they just fell) or a dummy did it
	attackerName: string?, -- set when a dummy did it
	victim: Player?, -- nil for dummies
	victimName: string,
	noodleId: string?,
	position: Vector3,
	attackerStreak: number?, -- attacker's streak after this bonk
	milestoneTitle: string?, -- e.g. "ON FIRE" when a streak tier was just reached
	milestoneColor: Color3?,
	endedStreak: number?, -- the victim's streak this bonk ended (only if big)
	bonus: number?, -- bonus Bonks for ending it
}

local BonkTracker = {}

local combat: any -- CombatService, set in start()
local dummySpawns: { [Model]: CFrame } = {}

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
	combat.popBubble(dummy)
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
	-- A dummy did it (dummy fight mode): show its name, no stats or streak for it
	local dummyName = if record and not record.attacker then record.attackerName else nil

	-- Dummy bonks only count in Studio, so nobody can farm unlocks on them live.
	-- The solo dummy (Noodle Bot, there when you're alone) always counts, so a
	-- player alone in a server can still earn Bonks and unlock noodles.
	local counts = victim ~= nil
		or character:GetAttribute("SoloDummy") == true
		or (RunService:IsStudio() and Config.DummyBonksCountInStudio)
	if attacker and counts then
		-- 2x Bonks pass and Pool Parties make a bonk worth more
		DataService.increment(attacker, "Bonks", MonetizationService.bonkValue(attacker))
		-- Every counted bonk is a lottery ticket for the Lucky noodle
		if DataService.getStat(attacker, "Lucky") < 1 and math.random(Config.LuckyChance) == 1 then
			DataService.setStat(attacker, "Lucky", 1)
			Remotes.LuckyNoodle:FireAllClients(attacker)
			print(`[Noodle Bonk] {attacker.Name} found the Lucky noodle!`)
		end
	end
	if victim then
		DataService.increment(victim, "Splashes", 1)
	end
	local streak = Streaks.onBonk(attacker, victim, counts)
	local milestone = streak and streak.milestone

	local info: BonkInfo = {
		attacker = attacker,
		attackerName = dummyName,
		victim = victim,
		victimName = if victim then victim.DisplayName else character.Name,
		noodleId = record and record.noodleId,
		position = root.Position,
		attackerStreak = streak and streak.streak,
		milestoneTitle = milestone and milestone.Title,
		milestoneColor = milestone and milestone.Color,
		endedStreak = streak and streak.ended,
		bonus = streak and streak.bonus,
	}
	Remotes.Bonked:FireAllClients(info)

	-- Secret noodles: Clown (bonked by Tornado) and the ??? infection
	SecretService.onBonk(attacker, victim, record and record.noodleId)

	-- Every bonk (by a player or a dummy) drops a rubber duck in the jar
	if attacker or dummyName then
		DuckJar.add(1)
	end

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
		local player = Players:GetPlayerFromCharacter(character)
		if player and player:GetAttribute("AdminGod") then
			-- God mode: put them back on the deck instead
			character:PivotTo(CFrame.new(Config.RescuePosition))
			combat.clearHits(character)
			return
		end
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

	CollectionService:GetInstanceAddedSignal(Config.DummyTag):Connect(addDummy)
	CollectionService:GetInstanceRemovedSignal(Config.DummyTag):Connect(function(instance)
		dummySpawns[instance :: Model] = nil
	end)
	for _, instance in CollectionService:GetTagged(Config.DummyTag) do
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
