--!strict
-- Passive noodle gimmicks that happen when someone gets hit (CombatService.strike
-- calls into this). The noodle's `Gimmick` (see shared/Noodles) picks the effect:
--
--   Attacker's noodle:  Spin (Fish), Shrink, Balloon (after pressing E), Burn (Fire),
--                       Paint, Squeaky (Hammer: every 3rd hit is a MEGA BONK),
--                       and the secret ones: DuckForm (Quack), Coconut, Reverse
--                       (Clown), Slime (Snail)
--   Defender's noodle:  Spiky (Cactus pricks the attacker), Heavy (Anchor: half knockback)
--   Shields:            Mirror and Knight's parry bounce the hit back at the attacker
--   Clone decoys:       hitting one sets it off
--
-- Also counts the hit stats used for unlocks (Hits, TimesHit, MaxSoaks).

local CollectionService = game:GetService("CollectionService")
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

-- Clone decoys register here. Anyone but their owner hitting one sets it off.
NoodleEffects.decoys = {} :: { [Model]: { owner: Player, explode: () -> () } }
local slimePuddles: { BasePart } = {}
local MAX_SLIME = 12

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
	task.spawn(function()
		while true do
			task.wait(0.2)
			NoodleEffects.updateSlowed()
		end
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
		if attacker ~= decoy.owner then
			decoy.explode()
		end
		return true -- decoys never take knockback themselves
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
		-- Only the hit right after pressing E balloons them
		local attackerCharacter = attacker and attacker.Character
		if not attackerCharacter or not attackerCharacter:GetAttribute("BalloonReady") then
			return
		end
		attackerCharacter:SetAttribute("BalloonReady", nil)
		local readyGlow = attackerCharacter:FindFirstChild("BalloonReadyGlow")
		if readyGlow then
			readyGlow:Destroy()
		end
		local drift = flat(info.velocity)
		info.float = {
			velocity = Vector3.new(0, 9, 0) + (if drift.Magnitude > 0.01 then drift.Unit * 3 else Vector3.zero),
			time = Config.BalloonTime,
		}
		info.ragdollTime = 0
		info.stunTime = Config.BalloonTime
		attachBalloon(target, targetRoot)
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
	elseif gimmick == "DuckForm" then
		NoodleEffects.duckForm(target)
	elseif gimmick == "Coconut" then
		NoodleEffects.dropCoconut(attacker, target)
	elseif gimmick == "Reverse" then
		if isPlayer then
			info.reverse = Config.ReverseTime
			NoodleEffects.pop(targetRoot.Position + Vector3.new(0, 4, 0), "REVERSED!", Color3.fromRGB(255, 70, 70))
		end
	elseif gimmick == "Slime" then
		NoodleEffects.slime(attacker, targetRoot.Position)
	elseif gimmick == "Paint" then
		local color = PAINT_COLORS[math.random(#PAINT_COLORS)]
		NoodleEffects.glow(target, "PaintCoat", color, 4, 0.2)
		local victim = isPlayerCharacter(target)
		if victim then
			Remotes.AbilityFx:FireClient(victim, "PaintSplat", color)
		end
	end
end

-- Secret noodle effects ------------------------------------------------------------------------

-- Quack: turns the target into a rubber duck for a few seconds.
function NoodleEffects.duckForm(target: Model)
	if target:GetAttribute("DuckForm") then
		return
	end
	local root = target:FindFirstChild("HumanoidRootPart")
	local library = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local template = library and library:FindFirstChild("RubberDuck")
	if not root or not root:IsA("BasePart") then
		return
	end
	target:SetAttribute("DuckForm", true)

	-- Hide the body
	local hidden: { [Instance]: number } = {}
	for _, item in target:GetDescendants() do
		if (item:IsA("BasePart") and item ~= root) or item:IsA("Decal") then
			hidden[item] = (item :: any).Transparency;
			(item :: any).Transparency = 1
		end
	end
	-- Show a duck instead
	local duck: Instance
	if template and template:IsA("Model") then
		local model = template:Clone()
		model:ScaleTo(model:GetScale() * 4 / 9) -- 4 studs tall
		model:PivotTo(root.CFrame * CFrame.new(0, -2.8, 0))
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = false
				item.CanCollide = false
				item.CanQuery = false
				item.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = item
				weld.Parent = item
			end
		end
		duck = model
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * 3.5
		ball.Color = Color3.fromRGB(255, 220, 40)
		ball.CanCollide = false
		ball.Massless = true
		ball.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ball
		weld.Parent = ball
		duck = ball
	end
	duck.Name = "DuckForm"
	duck.Parent = target
	NoodleEffects.sound("Quack", root.Position)
	NoodleEffects.pop(root.Position + Vector3.new(0, 4, 0), "QUACK!", Color3.fromRGB(255, 225, 60))

	task.delay(Config.DuckFormTime, function()
		duck:Destroy()
		for item, transparency in hidden do
			if item.Parent then
				(item :: any).Transparency = transparency
			end
		end
		if target.Parent then
			target:SetAttribute("DuckForm", nil)
		end
	end)
end

-- Coconut: a coconut drops on their head a moment later (a second, gimmick-free bonk).
function NoodleEffects.dropCoconut(attacker: Player?, target: Model)
	task.delay(0.5, function()
		local _, root = combat.getLiving(target)
		if not root then
			return
		end
		local coconut = Instance.new("Part")
		coconut.Name = "FallingCoconut"
		coconut.Shape = Enum.PartType.Ball
		coconut.Size = Vector3.one * 1.8
		coconut.Color = Color3.fromRGB(110, 70, 40)
		coconut.Anchored = true
		coconut.CanCollide = false
		coconut.CanQuery = false
		coconut.Position = root.Position + Vector3.new(0, 24, 0)
		coconut.Parent = workspace
		local started = os.clock()
		while os.clock() - started < 0.45 and root.Parent do
			local t = (os.clock() - started) / 0.45
			coconut.Position = root.Position + Vector3.new(0, 24 * (1 - t * t) + 2.5, 0)
			RunService.Heartbeat:Wait()
		end
		coconut:Destroy()
		local _, stillRoot = combat.getLiving(target)
		if stillRoot then
			local angle = math.random() * math.pi * 2
			NoodleEffects.pop(stillRoot.Position + Vector3.new(0, 4, 0), "BONK!", Color3.fromRGB(150, 100, 60))
			-- Classic stats, so the coconut doesn't drop another coconut
			combat.strike(
				attacker,
				target,
				stillRoot,
				Vector3.new(math.cos(angle), 0, math.sin(angle)),
				45,
				0.9,
				Noodles.Classic
			)
		end
	end)
end

-- Snail: leaves a slime puddle; anyone else walking through it is slowed.
function NoodleEffects.slime(owner: Player?, position: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = CollectionService:GetTagged(Config.DummyTag)
	local floor = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	if not floor then
		return
	end
	local puddle = Instance.new("Part")
	puddle.Name = "SnailSlime"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.15, 7, 7)
	puddle.CFrame = CFrame.new(floor.Position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	puddle.Color = Color3.fromRGB(140, 210, 90)
	puddle.Transparency = 0.3
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.CanTouch = false
	puddle.Parent = workspace
	Debris:AddItem(puddle, Config.SlimeTime)
	table.insert(slimePuddles, puddle)
	while #slimePuddles > MAX_SLIME do
		local oldest = table.remove(slimePuddles, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local ownerCharacter = owner and owner.Character
	task.spawn(function()
		while puddle.Parent do
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if character and character ~= ownerCharacter and root and root:IsA("BasePart") then
					local offset = root.Position - puddle.Position
					if flat(offset).Magnitude <= 3.6 and offset.Y < 5 then
						character:SetAttribute("SlowedUntil", serverNow() + 2)
					end
				end
			end
			task.wait(0.2)
		end
	end)
end

-- Keeps slowed players (Snail slime) at half speed, then puts them back.
function NoodleEffects.updateSlowed()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid then
			local slowed = stillOn(character, "SlowedUntil")
			local base = character:GetAttribute("SlowBase")
			if slowed and type(base) ~= "number" then
				character:SetAttribute("SlowBase", humanoid.WalkSpeed)
				humanoid.WalkSpeed = humanoid.WalkSpeed * 0.5
			elseif not slowed and type(base) == "number" then
				humanoid.WalkSpeed = base
				character:SetAttribute("SlowBase", nil)
				character:SetAttribute("SlowedUntil", nil)
			end
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
