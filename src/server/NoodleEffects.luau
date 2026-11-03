--!strict
-- Passive noodle gimmicks that happen when someone gets hit (CombatService.strike
-- calls into this). The noodle's `Gimmick` (see shared/Noodles) picks the effect:
--
--   Attacker's noodle:  Spin (Fish), Shrink, Sticky (Gum), Balloon, Burn (Fire),
--                       Paint, Squeaky (Hammer: every 3rd hit is a MEGA BONK)
--   Defender's noodle:  Spiky (Cactus pricks the attacker), Heavy (Anchor: half knockback)
--   Shields:            Mirror and Knight's parry bounce the hit back at the attacker
--   Clone decoys:       hitting one sets it off
--
-- Also counts the hit stats used for unlocks (Hits, TimesHit, MaxSoaks).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

type NoodleDef = Noodles.NoodleDef
type KnockbackInfo = Remotes.KnockbackInfo

local NoodleEffects = {}

local combat: any -- CombatService, set in init() (avoids a circular require)
local squeakCount: { [Player]: number } = {}

-- Clone decoys register here; hitting one calls its function (it explodes).
NoodleEffects.decoys = {} :: { [Model]: () -> () }

local PAINT_COLORS = {
	Color3.fromRGB(255, 60, 160),
	Color3.fromRGB(60, 200, 255),
	Color3.fromRGB(255, 220, 40),
	Color3.fromRGB(120, 255, 90),
	Color3.fromRGB(180, 90, 255),
	Color3.fromRGB(255, 120, 40),
}

function NoodleEffects.init(combatService: any)
	combat = combatService
	Players.PlayerRemoving:Connect(function(player)
		squeakCount[player] = nil
	end)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function stillOn(model: Model, attribute: string): boolean
	local value = model:GetAttribute(attribute)
	return type(value) == "number" and value > serverNow()
end

-- Floating text over everyone's screen (client/Effects shows it).
function NoodleEffects.pop(position: Vector3, text: string, color: Color3)
	Remotes.AbilityFx:FireAllClients("Pop", position, { text = text, color = color })
end

function NoodleEffects.sound(name: string, position: Vector3)
	Remotes.AbilityFx:FireAllClients("Sound", name, position)
end

local function heldGimmick(character: Model): string?
	local def = combat.getEquipped(character)
	return def and def.Gimmick
end

-- A highlight that removes itself after `duration`.
function NoodleEffects.glow(character: Model, name: string, color: Color3, duration: number, fill: number?)
	local old = character:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = fill or 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	Debris:AddItem(highlight, duration)
	return highlight
end

local function isPlayerCharacter(model: Model): Player?
	return Players:GetPlayerFromCharacter(model)
end

-- Before a hit lands ------------------------------------------------------------------

-- Mirror shield, Knight parry and Clone decoys. Returns true if the hit was
-- taken over (and the normal knockback shouldn't happen).
function NoodleEffects.intercept(
	attacker: Player?,
	target: Model,
	targetRoot: BasePart,
	direction: Vector3,
	power: number
): boolean
	local decoy = NoodleEffects.decoys[target]
	if decoy then
		decoy()
		return true
	end

	local parry = stillOn(target, "ParryUntil")
	local mirror = stillOn(target, "MirrorUntil")
	local attackerCharacter = attacker and attacker.Character
	if not (parry or mirror) or not attacker or not attackerCharacter then
		return false
	end
	local _, attackerRoot = combat.getLiving(attackerCharacter)
	if not attackerRoot then
		return false
	end

	target:SetAttribute(if parry then "ParryUntil" else "MirrorUntil", nil)
	local shield = target:FindFirstChild("MirrorShield")
	if shield and not parry then
		shield:Destroy()
	end
	local back = flat(attackerRoot.Position - targetRoot.Position)
	if back.Magnitude < 0.01 then
		back = -flat(direction)
	end
	local strength = power * (if parry then Config.ParryPower else 1)
	combat.applyKnockback(attackerCharacter, {
		velocity = back.Unit * strength + Vector3.yAxis * strength * 0.45,
		ragdollTime = 1.0,
		stunTime = if parry then 0.8 else nil,
		shake = 0.5,
	})
	local defender = isPlayerCharacter(target)
	local defenderDef = combat.getEquipped(target)
	combat.recordHit(attackerCharacter, defender, defenderDef and defenderDef.Id or "Classic", target.Name)
	Remotes.HitConfirm:FireAllClients(attackerRoot.Position, defenderDef and defenderDef.Id or "Classic", defender)
	NoodleEffects.pop(
		targetRoot.Position + Vector3.new(0, 4, 0),
		if parry then "PARRY!" else "REFLECTED!",
		if parry then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(190, 230, 255)
	)
	NoodleEffects.sound("Squeak", targetRoot.Position)
	return true
end

-- How hard the hit lands, after Soak.
function NoodleEffects.scalePower(
	attacker: Player?,
	target: Model,
	targetRoot: BasePart,
	def: NoodleDef,
	power: number
): number
	-- Squeaky Hammer: every 3rd hit is a MEGA BONK
	if attacker and def.Gimmick == "Squeaky" then
		local count = (squeakCount[attacker] or 0) + 1
		squeakCount[attacker] = count
		if count % 3 == 0 then
			power *= 2
			NoodleEffects.pop(targetRoot.Position + Vector3.new(0, 4, 0), "MEGA BONK!", Color3.fromRGB(255, 60, 60))
			NoodleEffects.sound("Squeak", targetRoot.Position)
		end
	end
	-- Shrunk players fly further
	if target:GetAttribute("Shrunk") then
		power *= Config.ShrinkKnockback
	end
	-- Holding the Anchor noodle: half knockback
	if heldGimmick(target) == "Heavy" then
		power *= 0.5
	end
	return power
end

-- Shaping the hit -------------------------------------------------------------------------

local function npcLoop(duration: number, step: (number) -> boolean?)
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < duration do
			if step(os.clock() - started) == false then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function attachBalloon(target: Model, targetRoot: BasePart)
	local head = target:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or head:FindFirstChild("HitBalloon") then
		return
	end
	local balloon = Instance.new("Part")
	balloon.Name = "HitBalloon"
	balloon.Shape = Enum.PartType.Ball
	balloon.Size = Vector3.new(2.6, 3.2, 2.6)
	balloon.Color = Color3.fromRGB(255, 70, 80)
	balloon.Material = Enum.Material.SmoothPlastic
	balloon.CanCollide = false
	balloon.CanQuery = false
	balloon.CanTouch = false
	balloon.Massless = true
	balloon.CFrame = head.CFrame * CFrame.new(0, 3.2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = balloon
	weld.Parent = balloon
	balloon.Parent = head
	Debris:AddItem(balloon, Config.BalloonTime)
end

-- Changes the knockback `info` (and does side effects) for the attacker's gimmick.
function NoodleEffects.shape(
	attacker: Player?,
	target: Model,
	targetRoot: BasePart,
	def: NoodleDef,
	info: KnockbackInfo
)
	local gimmick = def.Gimmick
	if not gimmick or target:GetAttribute("NoKnockback") then
		return
	end
	local isPlayer = isPlayerCharacter(target) ~= nil

	if gimmick == "Spin" then
		info.spin = Vector3.new(0, 40, 0)
		info.ragdollTime = math.max(info.ragdollTime, 1.4)
	elseif gimmick == "Balloon" then
		local drift = flat(info.velocity)
		info.float = {
			velocity = Vector3.new(0, 9, 0) + (if drift.Magnitude > 0.01 then drift.Unit * 3 else Vector3.zero),
			time = Config.BalloonTime,
		}
		info.ragdollTime = 0
		info.stunTime = Config.BalloonTime
		attachBalloon(target, targetRoot)
	elseif gimmick == "Sticky" then
		local attackerCharacter = attacker and attacker.Character
		local attackerRoot = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart")
		if attackerRoot and attackerRoot:IsA("BasePart") then
			local fling = info.velocity
			local distance = def.Length + 2
			info.follow = { target = attackerRoot, distance = distance, time = Config.StickyTime, fling = fling }
			info.ragdollTime = 0
			info.velocity = Vector3.zero
			if not isPlayer then
				-- Dummies: the server drags them along itself
				npcLoop(Config.StickyTime, function()
					if not targetRoot.Parent or not attackerRoot.Parent then
						return false
					end
					local goal = attackerRoot.Position + attackerRoot.CFrame.LookVector * distance + Vector3.yAxis * 1.5
					targetRoot.AssemblyLinearVelocity = (goal - targetRoot.Position) * 12
					return nil
				end)
				task.delay(Config.StickyTime, function()
					if targetRoot.Parent then
						targetRoot.AssemblyLinearVelocity = fling
					end
				end)
			end
			NoodleEffects.pop(targetRoot.Position + Vector3.new(0, 4, 0), "STUCK!", Color3.fromRGB(255, 130, 200))
		end
	elseif gimmick == "Burn" then
		info.panic = Config.BurnTime
		info.ragdollTime = 0
		info.velocity *= 0.5
		local fire = Instance.new("Fire")
		fire.Heat = 12
		fire.Size = 6
		fire.Parent = targetRoot
		Debris:AddItem(fire, Config.BurnTime)
		if not isPlayer then
			-- Dummies: the server runs them around itself
			local humanoid = target:FindFirstChildOfClass("Humanoid")
			task.spawn(function()
				local endTime = os.clock() + Config.BurnTime
				while humanoid and humanoid.Parent and os.clock() < endTime do
					local angle = math.random() * math.pi * 2
					humanoid:MoveTo(targetRoot.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 8)
					task.wait(0.3)
				end
			end)
		end
	elseif gimmick == "Shrink" then
		if not target:GetAttribute("Shrunk") then
			target:SetAttribute("Shrunk", true)
			local ok = pcall(function()
				target:ScaleTo(target:GetScale() * 0.5)
			end)
			if ok then
				NoodleEffects.pop(targetRoot.Position + Vector3.new(0, 3, 0), "shrunk!", Color3.fromRGB(120, 255, 160))
				task.delay(Config.ShrinkTime, function()
					if target.Parent and target:GetAttribute("Shrunk") then
						target:SetAttribute("Shrunk", nil)
						pcall(function()
							target:ScaleTo(target:GetScale() * 2)
						end)
					end
				end)
			else
				target:SetAttribute("Shrunk", nil)
			end
		end
	elseif gimmick == "Paint" then
		local color = PAINT_COLORS[math.random(#PAINT_COLORS)]
		NoodleEffects.glow(target, "PaintCoat", color, 4, 0.2)
		local victim = isPlayerCharacter(target)
		if victim then
			Remotes.AbilityFx:FireClient(victim, "PaintSplat", color)
		end
	end
end

-- After a hit lands ----------------------------------------------------------------------------

function NoodleEffects.after(
	attacker: Player?,
	target: Model,
	targetRoot: BasePart,
	soakBefore: number,
	soakAfter: number
)
	-- Cactus: hitting a spiky player pricks you back
	local attackerCharacter = attacker and attacker.Character
	if attackerCharacter and heldGimmick(target) == "Spiky" then
		local _, attackerRoot = combat.getLiving(attackerCharacter)
		if attackerRoot then
			local away = flat(attackerRoot.Position - targetRoot.Position)
			if away.Magnitude > 0.01 then
				combat.applyKnockback(attackerCharacter, {
					velocity = away.Unit * 45 + Vector3.yAxis * 22,
					ragdollTime = 0.6,
					shake = 0.3,
				})
				NoodleEffects.pop(attackerRoot.Position + Vector3.new(0, 4, 0), "OUCH!", Color3.fromRGB(80, 200, 90))
			end
		end
	end

	-- Unlock stats
	if attacker then
		DataService.increment(attacker, "Hits", 1)
		if soakBefore < Config.MaxSoak and soakAfter >= Config.MaxSoak then
			DataService.increment(attacker, "MaxSoaks", 1)
		end
	end
	local victim = isPlayerCharacter(target)
	if victim then
		DataService.increment(victim, "TimesHit", 1)
	end
end

return NoodleEffects
