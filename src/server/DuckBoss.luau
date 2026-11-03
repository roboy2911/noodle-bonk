--!strict
-- The Giant Rubber Duck boss. The duck jar (server/DuckJar) spawns it when
-- it's full. It waddles after the nearest player, belly-bumps anyone right
-- next to it and lets out a QUACK shockwave now and then. After each attack
-- it stops for a moment, which is your chance to hit back.
--
-- It can't be knocked around. Instead it has an HP bar: every noodle hit
-- does damage (more the more soaked it is). At 0 HP it's defeated, and
-- everyone who hit it gets +1 "DuckBosses", which unlocks the Duck noodle. If nobody manages it within
-- Config.DuckBoss.Lifetime, it gets bored and leaves.
--
-- Only affects the server it spawned in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ModelLibrary = require(script.Parent.ModelLibrary)

local TAG = "DuckBoss"
local NAME = "Giant Duck"
local THINK_EVERY = 0.2
local DUCK_YELLOW = Color3.fromRGB(255, 215, 40)
local BEAK_ORANGE = Color3.fromRGB(255, 140, 30)

local DuckBoss = {}

local updateBar: () -> () -- defined further down

local combat: any -- CombatService, set in start()
local boss: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local spawnedAt = 0
local lastQuack = 0
local restUntil = 0 -- it stands still after attacking
local hp = 0
local hpFill: Frame? = nil
local hpText: TextLabel? = nil
local hitters: { [Player]: boolean } = {}
local lastBump: { [Model]: number } = {}
local goneCallbacks: { () -> () } = {}

local function settings()
	return Config.DuckBoss
end

function DuckBoss.isActive(): boolean
	return boss ~= nil
end

-- Calls `callback` whenever the boss is gone (defeated, left or removed).
function DuckBoss.onGone(callback: () -> ())
	table.insert(goneCallbacks, callback)
end

-- Building ------------------------------------------------------------------------

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- The duck you see: the Blender rubber duck, or simple balls without models.
local function buildLook(model: Model, bottom: CFrame): Instance
	local s = settings()
	local look = ModelLibrary.spawn("RubberDuck", bottom, model, s.Scale)
	if look then
		return look
	end
	local folder = Instance.new("Model")
	folder.Name = "DuckLook"
	folder.Parent = model
	local height = 9 * s.Scale
	part(
		folder,
		"Body",
		Enum.PartType.Ball,
		Vector3.one * height * 0.75,
		bottom * CFrame.new(0, height * 0.35, 0),
		DUCK_YELLOW
	)
	part(
		folder,
		"Head",
		Enum.PartType.Ball,
		Vector3.one * height * 0.45,
		bottom * CFrame.new(0, height * 0.78, -height * 0.18),
		DUCK_YELLOW
	)
	part(
		folder,
		"Beak",
		Enum.PartType.Ball,
		Vector3.new(height * 0.22, height * 0.1, height * 0.2),
		bottom * CFrame.new(0, height * 0.74, -height * 0.42),
		BEAK_ORANGE
	)
	return folder
end

local function build(at: Vector3): Model
	local s = settings()
	local model = Instance.new("Model")
	model.Name = NAME

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = s.BodySize
	body.Transparency = 1
	body.CFrame = CFrame.new(at)
	body.CustomPhysicalProperties = PhysicalProperties.new(2, 0.4, 0.2)
	body.Parent = model
	model.PrimaryPart = body

	-- Everything you see hangs off one invisible part, joined to the body by a
	-- Motor6D that every client wobbles for the waddle (client/DuckFx)
	local bottom = body.CFrame * CFrame.new(0, -s.BodySize.Y / 2, 0)
	local anchor = Instance.new("Part")
	anchor.Name = "DuckAnchor"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.CFrame = bottom
	anchor.Parent = model

	local look = buildLook(model, bottom)
	for _, item in look:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchor
			weld.Part1 = item
			weld.Parent = item
		end
	end
	if look:IsA("BasePart") then
		look.Anchored = false
	end
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Massless = true

	local waddle = Instance.new("Motor6D")
	waddle.Name = "Waddle"
	waddle.Part0 = body
	waddle.Part1 = anchor
	waddle.C0 = CFrame.new(0, -s.BodySize.Y / 2, 0)
	waddle.Parent = body

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 0.2
	hum.MaxHealth = 1e6
	hum.Health = 1e6
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = s.WalkSpeed
	hum.DisplayName = "GIANT DUCK"
	hum.NameDisplayDistance = 200
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = model

	model:SetAttribute("NoKnockback", true)
	model:SetAttribute("NoRagdoll", true)
	model:SetAttribute("MaxHP", s.MaxHP)
	model:SetAttribute("HP", s.MaxHP)

	-- Big HP bar over its head
	local bar = Instance.new("BillboardGui")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromScale(16, 2.2) -- studs
	bar.StudsOffset = Vector3.new(0, s.BodySize.Y / 2 + 9 * s.Scale * 0.55, 0)
	bar.AlwaysOnTop = true
	bar.MaxDistance = 400
	bar.LightInfluence = 0
	bar.Parent = body

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.55)
	back.Position = UDim2.fromScale(0, 0.45)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	back.BorderSizePixel = 0
	back.Parent = bar
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.4, 0)
	backCorner.Parent = back
	local backStroke = Instance.new("UIStroke")
	backStroke.Thickness = 2
	backStroke.Parent = back

	local fillFrame = Instance.new("Frame")
	fillFrame.Size = UDim2.fromScale(1, 1)
	fillFrame.BackgroundColor3 = DUCK_YELLOW
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent = fillFrame

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.45)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = bar
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2
	textStroke.Parent = text

	hpFill, hpText = fillFrame, text
	model:SetAttribute("ExtraRadius", math.max(s.BodySize.X, s.BodySize.Z) / 2 - Config.BodyRadius)
	model:AddTag(TAG)
	return model
end

-- Ending --------------------------------------------------------------------------

local function cleanup()
	local model = boss
	if not model then
		return
	end
	boss, humanoid, root = nil, nil, nil -- first, so the removed signal below doesn't run this twice
	model:Destroy()
	table.clear(hitters)
	table.clear(lastBump)
	for _, callback in goneCallbacks do
		task.spawn(callback)
	end
end

local function defeated(position: Vector3)
	local names = {}
	for player in hitters do
		if player.Parent then
			DataService.increment(player, "DuckBosses", 1)
			table.insert(names, player.DisplayName)
		end
	end
	local splashAt = Vector3.new(position.X, Config.WaterLevel, position.Z)
	Remotes.AbilityFx:FireAllClients("Splash", splashAt)
	Remotes.AbilityFx:FireAllClients("Sound", "Splash", splashAt)
	Remotes.DuckBoss:FireAllClients("Defeated", names)
	print(`[Noodle Bonk] Giant Duck defeated by {#names} players`)
	cleanup()
end

-- Spawning ------------------------------------------------------------------------

function DuckBoss.spawn(): boolean
	if boss then
		return false
	end
	local model = build(Vector3.new(0, 35, 0)) -- drops in over the middle
	model.Parent = workspace
	local body = model.PrimaryPart :: BasePart
	if body:CanSetNetworkOwnership() then
		body:SetNetworkOwner(nil)
	end
	boss, root, humanoid = model, body, model:FindFirstChildOfClass("Humanoid")
	spawnedAt = os.clock()
	lastQuack = os.clock()
	restUntil = os.clock() + 3 -- a moment to get ready after it lands
	hp = settings().MaxHP
	updateBar()
	Remotes.DuckBoss:FireAllClients("Spawned")
	print("[Noodle Bonk] The Giant Duck has appeared!")
	return true
end

-- Admin: take it away without anyone winning.
function DuckBoss.remove(): boolean
	if not boss then
		return false
	end
	cleanup()
	return true
end

-- Brain ---------------------------------------------------------------------------

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function livingPlayers(): { { character: Model, root: BasePart } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and not character:GetAttribute("Bonked") then
			local _, playerRoot = combat.getLiving(character)
			if playerRoot then
				table.insert(list, { character = character, root = playerRoot })
			end
		end
	end
	return list
end

local function hit(character: Model, targetRoot: BasePart, from: Vector3, power: number, upward: number)
	if combat.isProtected(character) then
		return
	end
	local away = flat(targetRoot.Position - from)
	combat.strike(nil, character, targetRoot, away, power, upward, Noodles.Duck, NAME)
end

updateBar = function()
	local s = settings()
	local fraction = math.clamp(hp / s.MaxHP, 0, 1)
	if hpFill then
		hpFill.Size = UDim2.fromScale(fraction, 1)
		hpFill.BackgroundColor3 = Color3.fromRGB(230, 60, 60):Lerp(DUCK_YELLOW, fraction)
	end
	if hpText then
		hpText.Text = `GIANT DUCK  {math.ceil(hp)} / {s.MaxHP}`
	end
	if boss then
		boss:SetAttribute("HP", math.ceil(hp))
	end
end

-- A noodle hit: damage based on how hard it was (Soak makes it hit harder).
local function damage(amount: number)
	local body = root
	if not boss or not body or hp <= 0 then
		return
	end
	hp -= amount
	updateBar()
	if hp <= 0 then
		defeated(body.Position)
	end
end

local function think()
	local model, hum, body = boss, humanoid, root
	if not model or not hum or not body then
		return
	end
	if body.Position.Y < Config.KillY then
		defeated(body.Position)
		return
	end
	local s = settings()
	if os.clock() - spawnedAt > s.Lifetime then
		Remotes.DuckBoss:FireAllClients("Left")
		cleanup()
		return
	end

	local players = livingPlayers()
	local here = body.Position
	local nearest, nearestDistance = nil, math.huge
	for _, entry in players do
		local distance = flat(entry.root.Position - here).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = entry, distance
		end
	end

	local now = os.clock()
	local reach = s.BumpRange + math.max(s.BodySize.X, s.BodySize.Z) / 2

	-- Resting after an attack: stand still and take hits
	if now < restUntil then
		hum:MoveTo(here)
		return
	end

	-- Chase the nearest player (stopping once it's next to them), but never
	-- walk off the deck by itself
	if nearest and nearestDistance > reach - 1 then
		local limit = Config.ArenaDiameter / 2 - s.StayInside
		local goal = flat(nearest.root.Position)
		if goal.Magnitude > limit then
			goal = goal.Unit * limit
		end
		hum:MoveTo(Vector3.new(goal.X, here.Y, goal.Z))
	else
		hum:MoveTo(here)
	end

	-- Belly bump anyone right next to it
	local bumped = false
	for _, entry in players do
		if
			flat(entry.root.Position - here).Magnitude <= reach
			and now - (lastBump[entry.character] or 0) >= s.BumpCooldown
		then
			lastBump[entry.character] = now
			hit(entry.character, entry.root, here, s.BumpPower, 0.6)
			bumped = true
		end
	end
	if bumped then
		Remotes.AbilityFx:FireAllClients("Sound", "Quack", here)
		restUntil = now + s.RestAfterAttack
	end

	-- QUACK! A shockwave that throws everyone nearby back
	if now - lastQuack >= s.QuackEvery and nearest and nearestDistance <= s.QuackRadius then
		lastQuack = now
		restUntil = now + s.RestAfterAttack
		local ground = here - Vector3.new(0, s.BodySize.Y / 2, 0)
		Remotes.AbilityFx:FireAllClients("Sound", "Quack", here)
		Remotes.AbilityFx:FireAllClients("Shockwave", ground, s.QuackRadius)
		for _, entry in players do
			local distance = flat(entry.root.Position - here).Magnitude
			if distance <= s.QuackRadius then
				local falloff = 1 - math.clamp(distance / s.QuackRadius, 0, 1) * 0.5
				hit(entry.character, entry.root, here, s.QuackPower * falloff, 0.7)
			end
		end
	end
end

function DuckBoss.start(combatService: any)
	combat = combatService
	-- Remember everyone who hits the boss: they all share the win
	combat.onHit(function(target: Model, attacker: Player?)
		if attacker and target == boss then
			hitters[attacker] = true
		end
	end)
	-- Every noodle hit on it does damage
	combat.onStrike(function(target: Model, attacker: Player?, power: number)
		if attacker and target == boss then
			damage(power * settings().DamagePerPower)
			DataService.increment(attacker, "DuckHits", 1) -- unlocks the Squeaky Hammer
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= THINK_EVERY then
			elapsed = 0
			think()
		end
	end)
	-- In case it's removed some other way (e.g. a script or the admin clearing Workspace)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		if instance == boss then
			cleanup()
		end
	end)
end

return DuckBoss
