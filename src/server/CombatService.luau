--!strict
-- Validates swings and abilities from clients and applies knockback.
--
-- Flow: the client picks targets with HitQuery and sends them in Remotes.Swing.
-- The server re-checks cooldown, range and arc (with lag tolerance), then
-- pushes each valid target. Player characters are physically owned by their
-- own client, so the push is sent to the victim's client to apply.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)
local NoodleAbilities = require(script.Parent.NoodleAbilities)

type NoodleDef = Noodles.NoodleDef

export type HitRecord = {
	attacker: Player,
	noodleId: string,
	time: number,
}

local CombatService = {}

local lastSwing: { [Player]: number } = {}
local lastAbility: { [Player]: number } = {}
local lastHit: { [Model]: HitRecord } = setmetatable({}, { __mode = "k" }) :: any
local soaked: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function randomSpin(): Vector3
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
end

-- Humanoid and root of a living character, or nil.
local function getLiving(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function endSpawnProtection(character: Model)
	-- A SpawnLocation can add its own ForceField on top of ours, so clear them all
	for _, child in character:GetChildren() do
		if child:IsA("ForceField") then
			child:Destroy()
		end
	end
end

function CombatService.isStunned(character: Model): boolean
	local stunnedUntil = character:GetAttribute("StunnedUntil")
	return type(stunnedUntil) == "number" and stunnedUntil > serverNow()
end

function CombatService.isProtected(character: Model): boolean
	return character:FindFirstChildOfClass("ForceField") ~= nil
end

function CombatService.getEquipped(character: Model): NoodleDef?
	local tool = character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("NoodleId")
	if type(id) == "string" then
		return Noodles[id]
	end
	return nil
end

function CombatService.recordHit(target: Model, attacker: Player, noodleId: string)
	lastHit[target] = { attacker = attacker, noodleId = noodleId, time = os.clock() }
end

-- Who gets credit if `target` falls right now.
function CombatService.getCredit(target: Model): HitRecord?
	local record = lastHit[target]
	if record and os.clock() - record.time <= Config.CreditWindow and record.attacker.Parent then
		return record
	end
	return nil
end

function CombatService.clearHits(target: Model)
	lastHit[target] = nil
end

function CombatService.addSoak(target: Model, amount: number): number
	local current = target:GetAttribute("Soak")
	local soak = math.clamp((if type(current) == "number" then current else 0) + amount, 0, Config.MaxSoak)
	target:SetAttribute("Soak", soak)
	soaked[target] = true
	return soak
end

-- Launch velocity pushing `to` away from `from`.
function CombatService.knockbackVelocity(
	from: BasePart,
	to: BasePart,
	power: number,
	upward: number,
	soak: number
): Vector3
	local offset = to.Position - from.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.1 then
		local look = from.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	local scaled = power * (1 + soak / 100)
	return flat.Unit * scaled + Vector3.yAxis * scaled * upward
end

function CombatService.applyKnockback(target: Model, velocity: Vector3, ragdollTime: number, stunTime: number?)
	if stunTime and stunTime > 0 then
		target:SetAttribute("StunnedUntil", serverNow() + stunTime)
	end

	local player = Players:GetPlayerFromCharacter(target)
	if player then
		Remotes.Knockback:FireClient(player, velocity, ragdollTime, stunTime)
		return
	end

	-- NPCs and test dummies are simulated here on the server
	local humanoid, root = getLiving(target)
	if not humanoid or not root then
		return
	end
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
	if ragdollTime > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		root.AssemblyAngularVelocity = randomSpin()
		task.delay(ragdollTime, function()
			if humanoid.Parent and humanoid:GetState() == Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	root.AssemblyLinearVelocity = velocity
end

-- One validated noodle hit.
function CombatService.hit(attacker: Player, attackerRoot: BasePart, target: Model, targetRoot: BasePart, def: NoodleDef)
	local soak = CombatService.addSoak(target, def.SoakGain)
	local velocity =
		CombatService.knockbackVelocity(attackerRoot, targetRoot, def.Knockback, def.Upward or Config.BaseUpward, soak)
	CombatService.applyKnockback(target, velocity, def.RagdollTime or Config.RagdollTime, def.StunTime)
	CombatService.recordHit(target, attacker, def.Id)
	Remotes.HitConfirm:FireAllClients(targetRoot.Position, def.Id)
end

local function onSwing(player: Player, targets: unknown)
	local character = player.Character
	if not character then
		return
	end
	local _, root = getLiving(character)
	local def = CombatService.getEquipped(character)
	if not root or not def or CombatService.isStunned(character) then
		return
	end

	local now = os.clock()
	if now - (lastSwing[player] or 0) < def.Cooldown * Config.CooldownTolerance then
		return
	end
	lastSwing[player] = now

	-- Swinging ends spawn protection, so nobody can attack from inside a ForceField
	endSpawnProtection(character)

	if type(targets) ~= "table" then
		return
	end

	local maxRange = def.Range + Config.BodyRadius + Config.RangeTolerance
	local maxArc = def.ArcDeg + Config.ArcToleranceDeg
	local list = targets :: { unknown }
	local seen: { [Model]: boolean } = {}
	local hits = 0

	for i = 1, math.min(#list, Config.MaxTargetsPerRequest) do
		if hits >= def.MaxTargets then
			break
		end
		local target = list[i]
		if typeof(target) == "Instance" and target:IsA("Model") and target ~= character and not seen[target] then
			seen[target] = true
			local _, targetRoot = getLiving(target)
			if
				targetRoot
				and not CombatService.isProtected(target)
				and HitQuery.isInCone(root.CFrame, targetRoot.Position, maxRange, maxArc)
			then
				hits += 1
				CombatService.hit(player, root, target, targetRoot, def)
			end
		end
	end
end

local function onUseAbility(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local _, root = getLiving(character)
	local def = CombatService.getEquipped(character)
	if not root or not def or not def.Ability or CombatService.isStunned(character) then
		return
	end
	local ability = NoodleAbilities[def.Ability]
	if not ability then
		warn(`[Noodle Bonk] Noodle {def.Id} has unknown ability {def.Ability}`)
		return
	end

	local now = os.clock()
	if now - (lastAbility[player] or 0) < (def.AbilityCooldown or 5) * Config.CooldownTolerance then
		return
	end
	lastAbility[player] = now

	endSpawnProtection(character)
	ability({
		player = player,
		character = character,
		root = root,
		def = def,
		combat = CombatService,
	})
end

function CombatService.start()
	Remotes.Swing.OnServerEvent:Connect(onSwing)
	Remotes.UseAbility.OnServerEvent:Connect(onUseAbility)

	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		lastAbility[player] = nil
	end)

	-- Soak slowly dries off
	task.spawn(function()
		local STEP = 0.25
		while true do
			task.wait(STEP)
			for model in soaked do
				local soak = model:GetAttribute("Soak")
				if not model.Parent or type(soak) ~= "number" or soak <= 0 then
					soaked[model] = nil
				else
					model:SetAttribute("Soak", math.max(0, soak - Config.SoakDecayPerSecond * STEP))
				end
			end
		end
	end)
end

return CombatService
