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
local NoodleEffects = require(script.Parent.NoodleEffects)

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type AbilityContext = {
	player: Player,
	character: Model,
	root: BasePart,
	def: Noodles.NoodleDef,
	tool: Tool,
	combat: any, -- CombatService (passed in to avoid a circular require)
	aim: Vector3, -- where the player's camera points (unit vector)
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
local POGO_RADIUS = 18
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
	local target, targetRoot = findTarget(ctx, Config.AbilityRange, 70)
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

-- Everyone who can be hit: players, dummies and the duck boss.
local function everyone(except: Model): { Model }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character ~= except then
			table.insert(list, player.Character)
		end
	end
	for _, tag in { Config.DummyTag, "DuckBoss" } do
		for _, model in CollectionService:GetTagged(tag) do
			if model:IsA("Model") and model ~= except then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Duck: a row of rubber ducks charges forward and bowls over everyone in
-- the way. Every client draws the ducks; the server checks who they reach.
local STAMPEDE_WIDTH = 8 -- studs either side of the middle of the charge
local STAMPEDE_TIME = 1.2

Abilities.Stampede = function(ctx)
	local look = flat(ctx.root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return
	end
	local direction = look.Unit
	local origin = ctx.root.Position
	sound("Stampede", origin)
	Remotes.AbilityFx:FireAllClients("Stampede", origin, direction)

	task.spawn(function()
		local hit: { [Model]: boolean } = {}
		local steps = 12
		for step = 1, steps do
			task.wait(STAMPEDE_TIME / steps)
			local front = Config.StampedeLength * step / steps
			for _, target in everyone(ctx.character) do
				local _, targetRoot = ctx.combat.getLiving(target)
				if targetRoot and not hit[target] and not ctx.combat.isProtected(target) then
					local offset = targetRoot.Position - origin
					local along = offset:Dot(direction)
					local side = flat(offset - direction * along).Magnitude
					if along > 0 and along <= front + 2 and side <= STAMPEDE_WIDTH and math.abs(offset.Y) < 10 then
						hit[target] = true
						ctx.combat.strike(ctx.player, target, targetRoot, direction, Config.StampedePower, 0.7, ctx.def)
					end
				end
			end
		end
	end)
end

-- ==========================================================================================
-- Gimmick noodles
-- ==========================================================================================

-- A living, unprotected target's root, or nil.
local function rootOf(ctx: AbilityContext, target: Model): BasePart?
	local _, targetRoot = ctx.combat.getLiving(target)
	if not targetRoot or ctx.combat.isProtected(target) then
		return nil
	end
	return targetRoot
end

-- Where the floor is under `position` (ignoring characters), or nil over the water.
local function floorBelow(position: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), params)
	return if result then result.Position else nil
end

local function effectPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Moves `part` along `pathAt(seconds)` (nil = done) and hits anyone it passes
-- within `radius`. `onHit` returns true to stop the flight.
local function fly(
	ctx: AbilityContext,
	part: BasePart,
	radius: number,
	pathAt: (number) -> Vector3?,
	onHit: (Model, BasePart, Vector3) -> boolean,
	done: (() -> ())?
)
	part.Parent = workspace
	local hit: { [Model]: boolean } = {}
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		local position = pathAt(elapsed)
		if not position or not ctx.character.Parent then
			connection:Disconnect()
			part:Destroy()
			if done then
				done()
			end
			return
		end
		part.CFrame = CFrame.new(position) * CFrame.Angles(elapsed * 9, elapsed * 13, 0)
		for _, target in everyone(ctx.character) do
			if not hit[target] then
				local targetRoot = rootOf(ctx, target)
				if targetRoot and (targetRoot.Position - position).Magnitude <= radius + Config.BodyRadius then
					hit[target] = true
					if onHit(target, targetRoot, position) then
						connection:Disconnect()
						part:Destroy()
						if done then
							done()
						end
						return
					end
				end
			end
		end
	end)
end

local function aim(ctx: AbilityContext): Vector3
	local look = flat(ctx.root.CFrame.LookVector)
	return if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
end

-- Baguette: break off a chunk of bread and throw it.
Abilities.ThrowBread = function(ctx)
	local direction = aim(ctx)
	local origin = ctx.root.Position + Vector3.new(0, 1.5, 0) + direction * 2
	local flight = Config.ProjectileRange / Config.ProjectileSpeed
	sound("Throw", origin)
	local bread = effectPart("BreadChunk", Vector3.new(1.3, 1.3, 2.6), Color3.fromRGB(215, 160, 80))
	fly(ctx, bread, 2, function(t)
		if t > flight then
			return nil
		end
		return origin + direction * Config.ProjectileSpeed * t + Vector3.new(0, 6 * t - 12 * t * t, 0)
	end, function(target, targetRoot)
		ctx.combat.strike(ctx.player, target, targetRoot, direction, 60, 0.5, ctx.def)
		return true
	end)
end

-- Water Cannon: a fast blast of water that soaks and knocks back from far away.
Abilities.WaterCannon = function(ctx)
	local direction = aim(ctx)
	local origin = ctx.root.Position + Vector3.new(0, 1.5, 0) + direction * 3
	local flight = Config.CannonRange / Config.CannonSpeed
	sound("Splash", origin)
	local blast = effectPart("WaterBlast", Vector3.one * 3, Color3.fromRGB(120, 210, 255), Enum.PartType.Ball)
	blast.Material = Enum.Material.Glass
	blast.Transparency = 0.25
	fly(ctx, blast, 2.5, function(t)
		return if t <= flight then origin + direction * Config.CannonSpeed * t else nil
	end, function(target, targetRoot, position)
		ctx.combat.addSoak(target, 20)
		ctx.combat.strike(ctx.player, target, targetRoot, direction, 70, 0.35, ctx.def)
		Remotes.AbilityFx:FireAllClients("Splash", position)
		return true
	end)
end

-- Boomerang: throw the noodle itself; it curves out and comes back.
local BOOMERANG_TIME = 1.6

Abilities.Boomerang = function(ctx)
	local tool = ctx.tool
	if tool:GetAttribute("Thrown") then
		return
	end
	tool:SetAttribute("Thrown", true) -- every client hides the noodle; swings can't hit
	local direction = aim(ctx)
	local side = direction:Cross(Vector3.yAxis)
	local origin = ctx.root.Position + Vector3.new(0, 1.5, 0)
	local reach = Config.BoomerangRange
	sound("Throw", origin)
	local spinner =
		effectPart("Boomerang", Vector3.new(ctx.def.Length, ctx.def.Thickness, ctx.def.Thickness), ctx.def.Color)
	spinner.Shape = Enum.PartType.Cylinder
	fly(ctx, spinner, 3, function(t)
		local s = t / BOOMERANG_TIME
		if s >= 1 then
			return nil
		end
		-- Out and back in a curve, finishing wherever the thrower is now
		local out = origin + direction * reach * math.sin(math.pi * s) + side * reach * 0.35 * math.sin(2 * math.pi * s)
		local home = ctx.root.Position + Vector3.new(0, 1.5, 0)
		return out + (home - origin) * s
	end, function(target, targetRoot, position)
		ctx.combat.strike(ctx.player, target, targetRoot, flat(targetRoot.Position - position), 55, 0.5, ctx.def)
		return false -- keeps flying through everyone
	end, function()
		if tool.Parent then
			tool:SetAttribute("Thrown", nil)
		end
	end)
end

-- Rocket: blast yourself forward and bonk whoever you crash into.
Abilities.Rocket = function(ctx)
	local direction = aim(ctx)
	sound("Throw", ctx.root.Position)
	Remotes.Knockback:FireClient(ctx.player, {
		velocity = direction * 110 + Vector3.yAxis * 12,
		ragdollTime = 0,
	})
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 0
	fire.Parent = ctx.root
	Debris:AddItem(fire, 0.8)
	task.spawn(function()
		local hit: { [Model]: boolean } = {}
		local endTime = os.clock() + 0.7
		while os.clock() < endTime and ctx.root.Parent do
			for _, target in everyone(ctx.character) do
				local targetRoot = not hit[target] and rootOf(ctx, target)
				if targetRoot and (targetRoot.Position - ctx.root.Position).Magnitude <= 6 then
					hit[target] = true
					ctx.combat.strike(ctx.player, target, targetRoot, direction, 72, 0.5, ctx.def)
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Lightning: zap the nearest player in front; the bolt chains to 2 more.
Abilities.Lightning = function(ctx)
	local first, firstRoot = findTarget(ctx, Config.AbilityRange + 6, 100)
	if not first or not firstRoot then
		return
	end
	local points: { Vector3 } = { ctx.root.Position + Vector3.new(0, 1.5, 0) }
	local hit: { [Model]: boolean } = {}
	local current, currentRoot = first, firstRoot
	for _ = 1, 3 do
		hit[current] = true
		table.insert(points, currentRoot.Position)
		ctx.combat.strike(
			ctx.player,
			current,
			currentRoot,
			flat(currentRoot.Position - ctx.root.Position),
			55,
			0.7,
			ctx.def
		)
		-- next: the closest other target near this one
		local nextTarget, nextRoot, best = nil, nil, 22
		for _, other in everyone(ctx.character) do
			local otherRoot = not hit[other] and rootOf(ctx, other)
			if otherRoot then
				local distance = (otherRoot.Position - currentRoot.Position).Magnitude
				if distance < best then
					nextTarget, nextRoot, best = other, otherRoot, distance
				end
			end
		end
		if not nextTarget or not nextRoot then
			break
		end
		current, currentRoot = nextTarget, nextRoot
	end
	sound("Zap", firstRoot.Position)
	Remotes.AbilityFx:FireAllClients("Zap", points)
end

-- Swap: trade places with whoever you're aiming at.
Abilities.Swap = function(ctx)
	local target, targetRoot = findTarget(ctx, Config.AbilityRange + 8, 50)
	if not target or not targetRoot then
		return
	end
	local mine, theirs = ctx.root.CFrame, targetRoot.CFrame
	ctx.character:PivotTo(theirs)
	target:PivotTo(mine)
	ctx.combat.recordHit(target, ctx.player, ctx.def.Id) -- your bonk if they fall now
	sound("Poof", mine.Position)
	Remotes.AbilityFx:FireAllClients("Poof", mine.Position)
	Remotes.AbilityFx:FireAllClients("Poof", theirs.Position)
end

-- Clone: send out a decoy of yourself that explodes into a bonk.
Abilities.Clone = function(ctx)
	local character = ctx.character
	character.Archivable = true
	local ok, decoy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = false
	if not ok or not decoy then
		return
	end
	for _, item in decoy:GetDescendants() do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("Tool") or item:IsA("ForceField") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
		end
	end
	decoy.Name = character.Name
	local direction = aim(ctx)
	local start = ctx.root.CFrame + direction * 4 -- a step in front of you
	decoy:PivotTo(start)
	decoy.Parent = workspace
	sound("Poof", start.Position)
	Remotes.AbilityFx:FireAllClients("Poof", start.Position)

	local exploded = false
	local function explode()
		if exploded then
			return
		end
		exploded = true
		NoodleEffects.decoys[decoy] = nil
		local center = decoy:GetPivot().Position
		decoy:Destroy()
		sound("Poof", center)
		Remotes.AbilityFx:FireAllClients("Poof", center)
		Remotes.AbilityFx:FireAllClients("Shockwave", center - Vector3.new(0, 2.5, 0), 12)
		for _, target in everyone(character) do
			local targetRoot = rootOf(ctx, target)
			if targetRoot and (targetRoot.Position - center).Magnitude <= 12 then
				ctx.combat.strike(ctx.player, target, targetRoot, flat(targetRoot.Position - center), 70, 0.7, ctx.def)
			end
		end
	end
	NoodleEffects.decoys[decoy] = { owner = ctx.player, explode = explode }

	task.spawn(function()
		local started = os.clock()
		while not exploded and os.clock() - started < Config.CloneTime do
			local elapsed = os.clock() - started
			decoy:PivotTo(start + direction * math.min(elapsed, 2.5) * 14)
			local here = decoy:GetPivot().Position
			for _, target in everyone(character) do
				local targetRoot = target ~= decoy and rootOf(ctx, target)
				if targetRoot and (targetRoot.Position - here).Magnitude <= 6 then
					explode()
					return
				end
			end
			RunService.Heartbeat:Wait()
		end
		explode()
	end)
end

-- Gravity: everyone nearby floats up, then crashes down.
Abilities.Gravity = function(ctx)
	local center = ctx.root.Position
	sound("Boing", center)
	Remotes.AbilityFx:FireAllClients("Shockwave", center - Vector3.new(0, 2.5, 0), Config.GravityRadius)
	for _, target in HitQuery.findTargets(ctx.character, Config.GravityRadius, 360, 12) do
		if rootOf(ctx, target) then
			ctx.combat.applyKnockback(target, {
				velocity = Vector3.yAxis * 28,
				ragdollTime = 0,
				float = { velocity = Vector3.yAxis * 28, time = 1.1 },
			})
			ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
			task.delay(1.1, function()
				if target.Parent then
					local angle = math.random() * math.pi * 2
					ctx.combat.applyKnockback(target, {
						velocity = Vector3.new(math.cos(angle) * 18, -95, math.sin(angle) * 18),
						ragdollTime = 1.0,
						shake = 0.5,
					})
				end
			end)
		end
	end
end

-- Knight: a short parry window. Get hit during it and the attacker flies instead.
Abilities.Parry = function(ctx)
	ctx.character:SetAttribute("ParryUntil", serverNow() + Config.ParryWindow)
	NoodleEffects.glow(ctx.character, "ParryFlash", Color3.fromRGB(255, 255, 255), Config.ParryWindow, 0.6)
	sound("Throw", ctx.root.Position)
end

-- Mirror: a shield that bounces the next hit back.
Abilities.Mirror = function(ctx)
	ctx.character:SetAttribute("MirrorUntil", serverNow() + Config.MirrorTime)
	NoodleEffects.glow(ctx.character, "MirrorShield", Color3.fromRGB(200, 230, 255), Config.MirrorTime, 0.35)
	sound("Zap", ctx.root.Position)
end

-- Anchor: can't be moved at all for a few seconds.
Abilities.DropAnchor = function(ctx)
	ctx.character:SetAttribute("AnchoredUntil", serverNow() + Config.AnchorTime)
	NoodleEffects.glow(ctx.character, "AnchorGlow", Color3.fromRGB(70, 75, 90), Config.AnchorTime, 0.45)
	sound("Slam", ctx.root.Position)
	NoodleEffects.pop(ctx.root.Position + Vector3.new(0, 4, 0), "ANCHORED!", Color3.fromRGB(150, 160, 180))
end

-- Banana: drop a peel. Anyone who steps on it slips (3 peels each at most).
local peels: { [Player]: { BasePart } } = {}

Abilities.BananaPeel = function(ctx)
	local direction = aim(ctx)
	local floor = floorBelow(ctx.root.Position + direction * 3, { ctx.character })
	if not floor then
		return
	end
	local list = peels[ctx.player] or {}
	peels[ctx.player] = list
	while #list >= 3 do
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local peel = effectPart("BananaPeel", Vector3.new(2.2, 0.3, 1.3), Color3.fromRGB(255, 225, 50))
	peel.CFrame = CFrame.new(floor + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	peel.Parent = workspace
	table.insert(list, peel)
	Debris:AddItem(peel, Config.BananaTime)
	sound("Throw", floor)

	local placed = os.clock()
	task.spawn(function()
		while peel.Parent do
			for _, target in everyone(nil :: any) do
				local isOwner = target == ctx.character
				local targetRoot = (not isOwner or os.clock() - placed > 1.5) and rootOf(ctx, target)
				if targetRoot then
					local offset = targetRoot.Position - peel.Position
					if flat(offset).Magnitude <= 2.4 and offset.Y < 5 then
						local slide = flat(targetRoot.AssemblyLinearVelocity)
						local push = if slide.Magnitude > 1 then slide.Unit else flat(targetRoot.CFrame.LookVector)
						ctx.combat.applyKnockback(target, {
							velocity = push * 30 + Vector3.yAxis * 32,
							ragdollTime = 1.4,
							shake = 0.4,
						})
						if not isOwner then
							ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
						end
						sound("Slip", peel.Position)
						NoodleEffects.pop(peel.Position + Vector3.new(0, 3, 0), "SLIP!", Color3.fromRGB(255, 225, 50))
						peel:Destroy()
						return
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

-- Rubber Chicken: SQUAWK! Stuns everyone nearby for a second.
Abilities.Squawk = function(ctx)
	local center = ctx.root.Position
	sound("Squawk", center)
	Remotes.AbilityFx:FireAllClients("Shockwave", center - Vector3.new(0, 2.5, 0), Config.SquawkRadius)
	NoodleEffects.pop(center + Vector3.new(0, 4, 0), "SQUAWK!", Color3.fromRGB(255, 250, 235))
	for _, target in HitQuery.findTargets(ctx.character, Config.SquawkRadius, 360, 12) do
		local targetRoot = rootOf(ctx, target)
		if targetRoot then
			local away = flat(targetRoot.Position - center)
			ctx.combat.applyKnockback(target, {
				velocity = (if away.Magnitude > 0.01 then away.Unit else Vector3.zero) * 12 + Vector3.yAxis * 8,
				ragdollTime = 0,
				stunTime = 1.0,
			})
			ctx.combat.recordHit(target, ctx.player, ctx.def.Id)
		end
	end
end

-- Trampoline: put down a pad that bounces anyone who lands on it sky-high.
Abilities.Trampoline = function(ctx)
	local direction = aim(ctx)
	local floor = floorBelow(ctx.root.Position + direction * 6, { ctx.character })
	if not floor then
		return
	end
	local pad = effectPart("Trampoline", Vector3.new(0.6, 8, 8), Color3.fromRGB(60, 90, 255), Enum.PartType.Cylinder)
	pad.CFrame = CFrame.new(floor + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.CanCollide = true
	pad.Parent = workspace
	Debris:AddItem(pad, Config.TrampolineTime)
	sound("Boing", floor)

	local lastBounce: { [Model]: number } = {}
	task.spawn(function()
		while pad.Parent do
			for _, target in everyone(nil :: any) do
				local _, targetRoot = ctx.combat.getLiving(target)
				if targetRoot then
					local offset = targetRoot.Position - pad.Position
					local now = os.clock()
					if
						flat(offset).Magnitude <= 4.2
						and offset.Y > 0.5
						and offset.Y < 6
						and targetRoot.AssemblyLinearVelocity.Y <= 5
						and now - (lastBounce[target] or 0) > 0.7
					then
						lastBounce[target] = now
						ctx.combat.applyKnockback(target, {
							velocity = flat(targetRoot.AssemblyLinearVelocity) * 0.5
								+ Vector3.yAxis * Config.TrampolineBounce,
							ragdollTime = 0,
						})
						sound("Boing", pad.Position)
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

-- Grapple: shoot your noodle where you're looking and zip there. If it hits
-- nothing it still yanks you that way. Falling off? It aims for the deck.
local GRAPPLE_RANGE = 110

Abilities.Grapple = function(ctx)
	local origin = ctx.root.Position + Vector3.new(0, 1.5, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.character }

	local point: Vector3
	local falling = ctx.root.Position.Y < -2
	local result = workspace:Raycast(origin, ctx.aim * GRAPPLE_RANGE, params)
	if result and not (falling and result.Instance:IsA("Terrain")) then
		local hitModel = HitQuery.getCharacter(result.Instance)
		local hitRoot = hitModel and hitModel:FindFirstChild("HumanoidRootPart")
		point = if hitRoot and hitRoot:IsA("BasePart") then hitRoot.Position else result.Position
	elseif falling then
		-- Zip back to the nearest bit of the deck edge
		local out = flat(ctx.root.Position)
		local toward = if out.Magnitude > 1 then out.Unit else Vector3.new(1, 0, 0)
		point = toward * (Config.ArenaDiameter / 2 - 6) + Vector3.new(0, 3, 0)
	else
		point = origin + ctx.aim * 45 -- nothing to grab: a shorter yank that way
	end

	local delta = point - ctx.root.Position
	if delta.Magnitude < 2 then
		return
	end
	sound("Throw", origin)
	Remotes.AbilityFx:FireAllClients("Rope", ctx.root, point)
	Remotes.Knockback:FireClient(ctx.player, {
		velocity = delta.Unit * math.clamp(delta.Magnitude * 2.4, 55, 160)
			+ Vector3.yAxis * (12 + math.max(0, delta.Y) * 0.5),
		ragdollTime = 0,
	})
end

-- Pufferfish: puff up big and spiky; anyone touching you gets launched.
Abilities.Puff = function(ctx)
	local character = ctx.character
	if character:GetAttribute("Puffed") then
		return
	end
	character:SetAttribute("Puffed", true)
	local grown = pcall(function()
		character:ScaleTo(character:GetScale() * 1.6)
	end)
	NoodleEffects.glow(character, "PuffGlow", Color3.fromRGB(255, 200, 90), Config.PuffTime, 0.4)
	sound("Boing", ctx.root.Position)
	NoodleEffects.pop(ctx.root.Position + Vector3.new(0, 5, 0), "PUFF!", Color3.fromRGB(255, 200, 90))
	local lastHit: { [Model]: number } = {}
	task.spawn(function()
		local endTime = os.clock() + Config.PuffTime
		while os.clock() < endTime and character.Parent do
			for _, target in everyone(character) do
				local targetRoot = rootOf(ctx, target)
				local now = os.clock()
				if
					targetRoot
					and (targetRoot.Position - ctx.root.Position).Magnitude <= 6.5
					and now - (lastHit[target] or 0) > 0.8
				then
					lastHit[target] = now
					ctx.combat.strike(
						ctx.player,
						target,
						targetRoot,
						flat(targetRoot.Position - ctx.root.Position),
						65,
						0.6,
						ctx.def
					)
				end
			end
			task.wait(0.1)
		end
		if character.Parent then
			character:SetAttribute("Puffed", nil)
			if grown then
				pcall(function()
					character:ScaleTo(character:GetScale() / 1.6)
				end)
			end
		end
	end)
end

-- Balloon: your next hit floats the victim up (see NoodleEffects "Balloon").
Abilities.ArmBalloon = function(ctx)
	local token = os.clock()
	ctx.character:SetAttribute("BalloonReady", token)
	NoodleEffects.glow(ctx.character, "BalloonReadyGlow", Color3.fromRGB(255, 90, 90), 15, 0.7)
	sound("Boing", ctx.root.Position)
	task.delay(15, function()
		-- not used within 15 seconds: put it away
		if ctx.character.Parent and ctx.character:GetAttribute("BalloonReady") == token then
			ctx.character:SetAttribute("BalloonReady", nil)
		end
	end)
end

-- Lifeguard: throw a life ring to the nearest player falling off the deck and
-- pull them back to safety (so nobody gets the bonk).
Abilities.LifeRing = function(ctx)
	local best, bestRoot, bestDistance = nil, nil, 120
	for _, target in everyone(ctx.character) do
		local _, targetRoot = ctx.combat.getLiving(target)
		if targetRoot and targetRoot.Position.Y < -1 and not target:GetAttribute("Bonked") then
			local distance = (targetRoot.Position - ctx.root.Position).Magnitude
			if distance < bestDistance then
				best, bestRoot, bestDistance = target, targetRoot, distance
			end
		end
	end
	if not best or not bestRoot then
		NoodleEffects.pop(ctx.root.Position + Vector3.new(0, 4, 0), "Nobody to save!", Color3.fromRGB(255, 255, 255))
		return
	end
	local out = flat(bestRoot.Position)
	local safe = (if out.Magnitude > 1 then out.Unit else Vector3.new(1, 0, 0)) * (Config.ArenaDiameter / 2 - 12)
		+ Vector3.new(0, 4, 0)
	local delta = safe - bestRoot.Position
	ctx.combat.clearHits(best) -- saved: whoever knocked them off doesn't get the bonk
	Remotes.AbilityFx:FireAllClients("Rope", ctx.root, bestRoot.Position)
	sound("Throw", ctx.root.Position)
	ctx.combat.applyKnockback(best, {
		velocity = flat(delta).Unit * math.clamp(flat(delta).Magnitude * 2, 30, 90)
			+ Vector3.yAxis * (40 + math.max(0, delta.Y) * 1.2),
		ragdollTime = 0,
	})
	NoodleEffects.pop(bestRoot.Position + Vector3.new(0, 4, 0), "SAVED!", Color3.fromRGB(255, 80, 80))
end

-- ???: TIME STOP. Everyone else freezes for a few seconds; hits you land on
-- them are saved up and all hit at once when time starts again.
Abilities.TimeStop = function(ctx)
	local duration = Config.TimeStopTime
	local frozenUntil = serverNow() + duration
	local frozen: { Model } = {}
	local anchoredRoots: { BasePart } = {}
	for _, target in everyone(ctx.character) do
		local _, targetRoot = ctx.combat.getLiving(target)
		if targetRoot then
			target:SetAttribute("TimeFrozenUntil", frozenUntil)
			table.insert(frozen, target)
			if not Players:GetPlayerFromCharacter(target) and not targetRoot.Anchored then
				targetRoot.Anchored = true -- dummies and the duck: the server holds them still
				table.insert(anchoredRoots, targetRoot)
			end
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= ctx.player then
			Remotes.AbilityFx:FireClient(other, "TimeStop", duration)
		end
	end
	Remotes.AbilityFx:FireClient(ctx.player, "TimeStopCaster", duration)
	sound("Zap", ctx.root.Position)
	NoodleEffects.pop(ctx.root.Position + Vector3.new(0, 5, 0), "TIME STOP!", Color3.fromRGB(190, 130, 255))

	task.delay(duration, function()
		for _, root in anchoredRoots do
			if root.Parent then
				root.Anchored = false
			end
		end
		for _, target in frozen do
			if target.Parent then
				target:SetAttribute("TimeFrozenUntil", nil)
			end
		end
		-- a moment for clients to let go of their characters, then everything hits
		task.wait(0.1)
		for _, target in frozen do
			ctx.combat.releaseFrozen(target)
		end
	end)
end

return Abilities
