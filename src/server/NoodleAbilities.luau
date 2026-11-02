--!strict
-- Active noodle abilities (E / ButtonY / mobile button), keyed by the
-- `Ability` name in Noodles.luau. CombatService has already checked the
-- cooldown, stun and that the player is alive before calling these.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)
local Friends = require(script.Parent.Friends)

export type AbilityContext = {
	player: Player,
	character: Model,
	root: BasePart,
	def: Noodles.NoodleDef,
	tool: Tool,
	combat: any, -- CombatService (passed in to avoid a circular require)
}

local Abilities: { [string]: (AbilityContext) -> () } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Plays a Config.Sounds entry for everyone, at a spot in the world.
local function sound(name: string, position: Vector3)
	Remotes.AbilityFx:FireAllClients("Sound", name, position)
end

-- Closest unprotected living target in front of the user, and its root.
local function findTarget(ctx: AbilityContext, range: number, arcDeg: number): (Model?, BasePart?)
	local target = HitQuery.findTargets(ctx.character, range, arcDeg, 1)[1]
	if not target or ctx.combat.isProtected(target) then
		return nil, nil
	end
	local _, targetRoot = ctx.combat.getLiving(target)
	if not targetRoot then
		return nil, nil
	end
	return target, targetRoot
end

-- Pogo: bounce up, then slam down. Everyone near where you land gets launched.
local POGO_RADIUS = 14
local POGO_POWER = 65

Abilities.PogoSlam = function(ctx)
	sound("Boing", ctx.root.Position)
	Remotes.Knockback:FireClient(ctx.player, {
		velocity = ctx.root.CFrame.LookVector * 20 + Vector3.yAxis * 85,
		ragdollTime = 0,
	})

	task.spawn(function()
		task.wait(0.4) -- let them leave the ground first

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ctx.character }

		local deadline = os.clock() + 3
		local landed = false
		while os.clock() < deadline and ctx.root.Parent do
			if workspace:Raycast(ctx.root.Position, Vector3.new(0, -4, 0), params) then
				landed = true
				break
			end
			task.wait()
		end
		if not landed then
			return -- bounced off the map
		end

		local center = ctx.root.Position
		sound("Slam", center)
		Remotes.AbilityFx:FireAllClients("Shockwave", center - Vector3.new(0, 2.5, 0), POGO_RADIUS)
		for _, target in HitQuery.findTargets(ctx.character, POGO_RADIUS, 360, 10) do
			local _, targetRoot = ctx.combat.getLiving(target)
			if targetRoot and not ctx.combat.isProtected(target) then
				local offset = targetRoot.Position - center
				local falloff = 1 - math.clamp(offset.Magnitude / POGO_RADIUS, 0, 1) * 0.5
				ctx.combat.strike(ctx.player, target, targetRoot, offset, POGO_POWER * falloff, 0.6, ctx.def)
			end
		end
	end)
end

-- Kraken: a tentacle grabs the closest person in front of you and throws
-- them over your head.
Abilities.Tentacle = function(ctx)
	local target, targetRoot = findTarget(ctx, 18, 70)
	if not target or not targetRoot then
		return
	end
	sound("Tentacle", ctx.root.Position)
	Remotes.AbilityFx:FireAllClients("Tentacle", ctx.root, targetRoot)
	task.wait(0.15) -- let the tentacle reach them first
	if not targetRoot.Parent or not ctx.root.Parent then
		return
	end
	local overHead = flat(ctx.root.Position - targetRoot.Position)
	ctx.combat.strike(ctx.player, target, targetRoot, overHead, 55, 1.35, ctx.def)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Invisible: you vanish for a few seconds. Every client hides characters
-- with a VanishedUntil time in the future (client/Vanish). Hitting someone
-- brings you back early (CombatService.strike).
Abilities.Vanish = function(ctx)
	sound("Vanish", ctx.root.Position)
	ctx.character:SetAttribute("VanishedUntil", serverNow() + Config.VanishTime)
end

-- Magnet: everyone nearby gets yanked toward you.
Abilities.Magnet = function(ctx)
	local center = ctx.root.Position
	local radius = Config.MagnetRadius
	sound("Magnet", center)
	Remotes.AbilityFx:FireAllClients("Shockwave", center - Vector3.new(0, 2.5, 0), radius)
	for _, target in HitQuery.findTargets(ctx.character, radius, 360, 12) do
		local _, targetRoot = ctx.combat.getLiving(target)
		if targetRoot and not ctx.combat.isProtected(target) then
			local pull = flat(center - targetRoot.Position)
			if pull.Magnitude > 3 then
				ctx.combat.applyKnockback(target, {
					velocity = pull.Unit * math.clamp(pull.Magnitude * 2.6, 30, 85) + Vector3.yAxis * 22,
					ragdollTime = 0.5,
				})
				ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
			end
		end
	end
end

-- Tornado: you spin on the spot for a few seconds. Your client spins your
-- character (client/CameraController), so your noodle whips around and hits
-- everyone it touches like a normal, very fast swing.
Abilities.Tornado = function(ctx)
	sound("Tornado", ctx.root.Position)
	ctx.character:SetAttribute("SpinningUntil", serverNow() + Config.TornadoTime)
end

-- Splash: spray water in front of you. Soaks everyone it reaches (so your
-- next hits launch them further) with only a small push.
Abilities.Spray = function(ctx)
	sound("Splash", ctx.root.Position)
	for _, target in HitQuery.findTargets(ctx.character, Config.SprayRange, 70, 8) do
		local _, targetRoot = ctx.combat.getLiving(target)
		if targetRoot and not ctx.combat.isProtected(target) then
			ctx.combat.addSoak(target, Config.SpraySoak)
			local push = flat(targetRoot.Position - ctx.root.Position)
			ctx.combat.applyKnockback(target, {
				velocity = (if push.Magnitude > 0.01 then push.Unit else Vector3.zero) * 14,
				ragdollTime = 0,
			})
			ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
			Remotes.AbilityFx:FireAllClients("Splash", targetRoot.Position)
		end
	end
end

-- Squad: leap over to your closest friend in the server.
Abilities.Rally = function(ctx)
	local _, friendRoot = Friends.nearestFriend(ctx.player, ctx.root.Position)
	if not friendRoot then
		return
	end
	local toFriend = flat(friendRoot.Position - ctx.root.Position)
	if toFriend.Magnitude < 6 then
		return -- already next to them
	end
	sound("Boing", ctx.root.Position)
	-- A jump arc that lands roughly next to them
	Remotes.Knockback:FireClient(ctx.player, {
		velocity = toFriend.Unit * math.clamp(toFriend.Magnitude * 1.1, 30, 110) + Vector3.yAxis * 55,
		ragdollTime = 0,
	})
end

return Abilities
