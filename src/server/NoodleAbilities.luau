--!strict
-- Active noodle abilities (E / ButtonY / mobile button), keyed by the
-- `Ability` name in Noodles.luau. CombatService has already checked the
-- cooldown, stun and that the player is alive before calling these.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)

export type AbilityContext = {
	player: Player,
	character: Model,
	root: BasePart,
	def: Noodles.NoodleDef,
	combat: any, -- CombatService (passed in to avoid a circular require)
}

local Abilities: { [string]: (AbilityContext) -> () } = {}

-- Spring: bounce yourself high into the air to dodge or drop onto someone.
Abilities.Boing = function(ctx)
	local launch = ctx.root.CFrame.LookVector * 35 + Vector3.yAxis * 95
	-- ragdollTime 0 = launch without tumbling
	Remotes.Knockback:FireClient(ctx.player, launch, 0, nil)
end

-- Whip: lash the closest player in front of you and yank them toward you.
local LASH_RANGE = 24
local LASH_ARC = 60
local LASH_MAX_SPEED = 80

Abilities.Lash = function(ctx)
	local target = HitQuery.findTargets(ctx.character, LASH_RANGE, LASH_ARC, 1)[1]
	if not target or ctx.combat.isProtected(target) then
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return
	end

	local pull = ctx.root.Position - targetRoot.Position
	local flat = Vector3.new(pull.X, 0, pull.Z)
	if flat.Magnitude < 1 then
		return
	end

	local velocity = flat.Unit * math.min(flat.Magnitude * 4, LASH_MAX_SPEED) + Vector3.yAxis * 30
	ctx.combat.applyKnockback(target, velocity, 0.6, nil)
	ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
	Remotes.HitConfirm:FireAllClients(targetRoot.Position, ctx.def.Id)
end

return Abilities
