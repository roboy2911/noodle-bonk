--!strict
-- Validates noodle hits and abilities from clients and applies knockback.
--
-- There's no swing button: you swing by turning (client/CameraController
-- keeps your character facing the camera). The attacker's client simulates
-- its bendy noodle and reports when it actually touches someone
-- (Remotes.NoodleHit). The server checks that claim against reach, cooldowns
-- and how fast it saw the attacker turning, then launches the target.
--
-- Player characters are physically owned by their own client, so launches are
-- sent to the victim's client to apply. Dummies are pushed here on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local NoodleAbilities = require(script.Parent.NoodleAbilities)
local Ragdoll = require(script.Parent.Ragdoll)

type NoodleDef = Noodles.NoodleDef
type KnockbackInfo = Remotes.KnockbackInfo

export type HitRecord = {
	attacker: Player,
	noodleId: string,
	time: number,
}

type YawSample = { t: number, yaw: number }

local YAW_WINDOW = 0.4 -- seconds of turning history kept per player

local CombatService = {}

local lastAbility: { [Player]: number } = {}
local pairHits: { [Player]: { [Model]: number } } = {}
local yawHistory: { [Player]: { YawSample } } = {}
local lastHit: { [Model]: HitRecord } = setmetatable({}, { __mode = "k" }) :: any
local soaked: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local floatTokens: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Helpers ------------------------------------------------------------------

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function randomSpin(): Vector3
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
end

-- Humanoid and root of a living character, or nil.
function CombatService.getLiving(character: Model): (Humanoid?, BasePart?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

function CombatService.endSpawnProtection(character: Model)
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

-- The noodle the character is holding, and its Tool.
function CombatService.getEquipped(character: Model): (NoodleDef?, Tool?)
	local tool = character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("NoodleId")
	if tool and type(id) == "string" and Noodles[id] then
		return Noodles[id], tool
	end
	return nil, nil
end

-- Size multiplier from the Inflate ability.
function CombatService.getScale(tool: Tool): number
	local scale = tool:GetAttribute("Scale")
	return if type(scale) == "number" then scale else 1
end

-- Bonk credit ---------------------------------------------------------------

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

-- Knockback -----------------------------------------------------------------

function CombatService.popBubble(target: Model)
	local root = target:FindFirstChild("HumanoidRootPart")
	local bubble = root and root:FindFirstChild("NoodleBubble")
	if bubble then
		bubble:Destroy()
	end
	floatTokens[target] = (floatTokens[target] or 0) + 1
	target:SetAttribute("Bubbled", nil)
end

-- Dummies and NPCs are simulated by the server.
local function pushNpc(target: Model, humanoid: Humanoid, root: BasePart, info: KnockbackInfo)
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
	local token = (floatTokens[target] or 0) + 1
	floatTokens[target] = token

	local float = info.float
	if float then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		task.spawn(function()
			local endTime = os.clock() + float.time
			while os.clock() < endTime and floatTokens[target] == token and root.Parent do
				root.AssemblyLinearVelocity = float.velocity
				root.AssemblyAngularVelocity = Vector3.zero
				RunService.Heartbeat:Wait()
			end
			if floatTokens[target] == token and humanoid.Parent then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		return
	end

	if info.ragdollTime > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		root.AssemblyAngularVelocity = randomSpin()
		task.delay(info.ragdollTime, function()
			if
				floatTokens[target] == token
				and humanoid.Parent
				and humanoid:GetState() == Enum.HumanoidStateType.Physics
			then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end
	root.AssemblyLinearVelocity = info.velocity
end

function CombatService.applyKnockback(target: Model, info: KnockbackInfo)
	if info.stunTime and info.stunTime > 0 then
		local current = target:GetAttribute("StunnedUntil")
		local untilTime = serverNow() + info.stunTime
		if type(current) ~= "number" or current < untilTime then
			target:SetAttribute("StunnedUntil", untilTime)
		end
	end
	if info.ragdollTime > 0 then
		Ragdoll.enable(target, info.ragdollTime)
	end

	local player = Players:GetPlayerFromCharacter(target)
	if player then
		Remotes.Knockback:FireClient(player, info)
		return
	end

	local humanoid, root = CombatService.getLiving(target)
	if humanoid and root then
		pushNpc(target, humanoid, root, info)
	end
end

-- Launch `target` along `direction` (flattened) with `power`, using `def`
-- for ragdoll, stun and Soak. Credits `attacker` and plays hit effects.
function CombatService.strike(
	attacker: Player,
	target: Model,
	targetRoot: BasePart,
	direction: Vector3,
	power: number,
	upward: number,
	def: NoodleDef
)
	if target:GetAttribute("Bubbled") then
		CombatService.popBubble(target)
	end

	local soak = CombatService.addSoak(target, def.SoakGain)
	local scaled = power * (1 + soak / 100)
	local flatDirection = flat(direction)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = flat(targetRoot.CFrame.LookVector) * -1
	end

	CombatService.applyKnockback(target, {
		velocity = flatDirection.Unit * scaled + Vector3.yAxis * scaled * upward,
		ragdollTime = def.RagdollTime or Config.RagdollTime,
		stunTime = def.StunTime,
		shake = math.clamp(scaled / 150, 0.15, 0.7),
	})
	CombatService.recordHit(target, attacker, def.Id)
	Remotes.HitConfirm:FireAllClients(targetRoot.Position, def.Id, attacker)
end

-- Swing validation ----------------------------------------------------------

local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.atan2(look.X, look.Z)
end

local function angleBetween(a: number, b: number): number
	local diff = (a - b) % (2 * math.pi)
	if diff > math.pi then
		diff -= 2 * math.pi
	end
	return math.abs(diff)
end

local function sampleYaw()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local history = yawHistory[player]
			if not history then
				history = {}
				yawHistory[player] = history
			end
			table.insert(history, { t = now, yaw = yawOf(root.CFrame) })
			while #history > 0 and now - history[1].t > YAW_WINDOW do
				table.remove(history, 1)
			end
		end
	end
end

-- Fastest the noodle tip could plausibly have been moving, based on how fast
-- the server saw the attacker turn and move recently.
local function estimateTipSpeed(player: Player, root: BasePart, reach: number): number
	local history = yawHistory[player] or {}
	local maxTurnRate = 0
	for i = 2, #history do
		for j = i - 1, 1, -1 do
			local dt = history[i].t - history[j].t
			if dt >= 0.05 then
				maxTurnRate = math.max(maxTurnRate, angleBetween(history[i].yaw, history[j].yaw) / dt)
				break
			end
		end
	end
	return maxTurnRate * reach + root.AssemblyLinearVelocity.Magnitude
end

-- 0 to 1 power from swing speed.
local function powerScale(speed: number): number
	local t = math.clamp((speed - Config.MinHitSpeed) / (Config.FullPowerSpeed - Config.MinHitSpeed), 0, 1)
	return Config.MinPowerScale + (1 - Config.MinPowerScale) * t
end

local function onNoodleHit(player: Player, target: unknown, hitPos: unknown, direction: unknown, speed: unknown)
	if typeof(target) ~= "Instance" or typeof(hitPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if type(speed) ~= "number" or speed ~= speed then
		return -- not a number, or NaN
	end
	local targetModel = target :: Instance
	if not targetModel:IsA("Model") then
		return
	end
	local victim = targetModel :: Model
	local hitPosition = hitPos :: Vector3
	local swingDirection = direction :: Vector3
	local claimedSpeed = speed :: number

	local character = player.Character
	if not character or victim == character then
		return
	end
	local _, root = CombatService.getLiving(character)
	local def, tool = CombatService.getEquipped(character)
	if not root or not def or not tool or CombatService.isStunned(character) then
		return
	end
	local _, targetRoot = CombatService.getLiving(victim)
	if not targetRoot or CombatService.isProtected(victim) then
		return
	end

	-- Same target can only be hit once per noodle cooldown
	local now = os.clock()
	local hits = pairHits[player]
	if not hits then
		hits = setmetatable({}, { __mode = "k" }) :: any
		pairHits[player] = hits
	end
	if now - (hits[victim] or 0) < def.Cooldown * Config.CooldownTolerance then
		return
	end

	-- Was the noodle close enough to touch them?
	local scale = CombatService.getScale(tool)
	local reach = def.Length * scale + Config.ArmReach
	local slack = Config.RangeTolerance
	if (targetRoot.Position - root.Position).Magnitude > reach + Config.BodyRadius + slack then
		return
	end
	if (hitPosition - targetRoot.Position).Magnitude > Config.BodyRadius * 2 + slack then
		return
	end
	if (hitPosition - root.Position).Magnitude > reach + slack then
		return
	end

	-- Was the attacker really turning that fast?
	local allowed = estimateTipSpeed(player, root, reach) * 1.5 + 15
	local effectiveSpeed = math.min(claimedSpeed, allowed, Config.MaxHitSpeed)
	if effectiveSpeed < Config.MinHitSpeed * 0.5 then
		return
	end
	hits[victim] = now

	CombatService.endSpawnProtection(character)

	-- Mostly the way the noodle was moving, partly away from the attacker
	local away = flat(targetRoot.Position - root.Position)
	local swing = flat(swingDirection)
	local launchDirection = Vector3.zero
	if swing.Magnitude > 0.01 then
		launchDirection += swing.Unit * 0.65
	end
	if away.Magnitude > 0.01 then
		launchDirection += away.Unit * 0.35
	end

	local bonus = if scale > 1 then Config.InflateKnockbackBonus else 1
	local power = def.Knockback * powerScale(effectiveSpeed) * bonus
	CombatService.strike(player, victim, targetRoot, launchDirection, power, def.Upward or Config.BaseUpward, def)
end

local function onUseAbility(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local _, root = CombatService.getLiving(character)
	local def, tool = CombatService.getEquipped(character)
	if not root or not def or not tool or not def.Ability or CombatService.isStunned(character) then
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

	CombatService.endSpawnProtection(character)
	ability({
		player = player,
		character = character,
		root = root,
		def = def,
		tool = tool,
		combat = CombatService,
	})
end

function CombatService.start()
	Remotes.NoodleHit.OnServerEvent:Connect(onNoodleHit)
	Remotes.UseAbility.OnServerEvent:Connect(onUseAbility)
	RunService.Heartbeat:Connect(sampleYaw)

	Players.PlayerRemoving:Connect(function(player)
		lastAbility[player] = nil
		pairHits[player] = nil
		yawHistory[player] = nil
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
