--!strict
-- Active noodle abilities (E / ButtonY / mobile button), keyed by the
-- `Ability` name in Noodles.luau. CombatService has already checked the
-- cooldown, stun and that the player is alive before calling these.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)

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

-- Spring: bounce yourself high into the air to dodge or drop onto someone.
Abilities.Boing = function(ctx)
	sound("Boing", ctx.root.Position)
	Remotes.Knockback:FireClient(ctx.player, {
		velocity = ctx.root.CFrame.LookVector * 35 + Vector3.yAxis * 95,
		ragdollTime = 0,
	})
end

-- Whip: lash the closest player in front of you and yank them toward you.
Abilities.Lash = function(ctx)
	local target, targetRoot = findTarget(ctx, 24, 60)
	if not target or not targetRoot then
		return
	end
	local pull = flat(ctx.root.Position - targetRoot.Position)
	if pull.Magnitude < 1 then
		return
	end
	sound("Lash", targetRoot.Position)
	ctx.combat.applyKnockback(target, {
		velocity = pull.Unit * math.min(pull.Magnitude * 4, 80) + Vector3.yAxis * 30,
		ragdollTime = 0.6,
	})
	ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
	Remotes.HitConfirm:FireAllClients(targetRoot.Position, ctx.def.Id, ctx.player)
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

-- Bubble: trap the closest person in front of you in a bubble that floats
-- away. Hitting them pops it early.
local BUBBLE_TIME = 3

Abilities.BubbleTrap = function(ctx)
	local target, targetRoot = findTarget(ctx, 20, 70)
	if not target or not targetRoot or target:GetAttribute("Bubbled") then
		return
	end

	local look = flat(ctx.root.CFrame.LookVector)
	local drift = (if look.Magnitude > 0.01 then look.Unit else Vector3.zero) * 7 + Vector3.yAxis * 6

	local bubble = Instance.new("Part")
	bubble.Name = "NoodleBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * 7
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(130, 210, 255)
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Massless = true
	bubble.CFrame = targetRoot.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = targetRoot
	weld.Part1 = bubble
	weld.Parent = bubble
	bubble.Parent = targetRoot
	Debris:AddItem(bubble, BUBBLE_TIME)

	sound("BubbleTrap", targetRoot.Position)
	target:SetAttribute("Bubbled", true)
	task.delay(BUBBLE_TIME, function()
		-- Pop at the end, unless a hit already popped it
		if targetRoot:FindFirstChild("NoodleBubble") then
			sound("BubblePop", targetRoot.Position)
		end
	end)
	task.delay(BUBBLE_TIME + 0.05, function()
		if not targetRoot:FindFirstChild("NoodleBubble") then
			target:SetAttribute("Bubbled", nil)
		end
	end)

	ctx.combat.applyKnockback(target, {
		velocity = drift,
		ragdollTime = 0,
		stunTime = BUBBLE_TIME,
		float = { velocity = drift, time = BUBBLE_TIME },
	})
	ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
	Remotes.HitConfirm:FireAllClients(targetRoot.Position, ctx.def.Id, ctx.player)
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

-- Inflatable: your noodle grows huge for a few seconds. Bigger reach, harder
-- hits. The size is a Tool attribute, so every client draws it bigger.
Abilities.Inflate = function(ctx)
	local tool = ctx.tool
	sound("Inflate", ctx.root.Position)
	tool:SetAttribute("Scale", Config.InflateScale)
	task.delay(Config.InflateTime, function()
		if tool.Parent then
			tool:SetAttribute("Scale", 1)
		end
	end)
end

return Abilities
