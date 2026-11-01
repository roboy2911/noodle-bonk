--!strict
-- Dummy fight mode, switched on from the admin panel. Every dummy grabs a
-- noodle, chases the nearest player and swings at them. Hits work like a
-- player's: Soak, knockback, ragdoll, BONK! effects and the kill feed
-- ("Dummy 2 bonked you"). Dummies never earn stats or streaks.
--
-- It only affects the server it's switched on in. Workspace attribute
-- "DummyFight" is true while it's on, so the admin panel can show it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local CombatService = require(script.Parent.CombatService)
local NoodleTools = require(script.Parent.NoodleTools)

local THINK_EVERY = 0.15 -- seconds between chase updates
local WIND_UP_TIME = 0.18 -- turning away before the swing
local SWEEP_TIME = 0.16 -- the fast turn that hits
local WIND_UP_ANGLE = math.rad(110)
local FOLLOW_THROUGH_ANGLE = math.rad(80)
-- Roblox's own R15 "holding a tool" pose (arm out in front), the one players
-- get from their Animate script. Dummies' Animate script doesn't run, so we play it.
local HOLD_ANIMATION_ID = "rbxassetid://507768375"

local DummyFight = {}

local enabled = false
local swinging: { [Model]: boolean } = {}
local lastSwing: { [Model]: number } = {}
local holdTracks: { [Model]: AnimationTrack } = {}

local holdAnimation = Instance.new("Animation")
holdAnimation.AnimationId = HOLD_ANIMATION_ID

local function noodleDef()
	return Noodles[Config.DummyFight.Noodle] or Noodles[Config.DefaultNoodle]
end

local function heldNoodle(dummy: Model): Tool?
	local tool = dummy:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("NoodleId") ~= nil then tool else nil
end

-- Yaw for CFrame.Angles(0, yaw, 0) that looks along `direction`.
local function yawToward(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function yawOf(root: BasePart): number
	return yawToward(root.CFrame.LookVector)
end

-- The same angle, moved to within half a turn of `near` (so turns take the short way).
local function wrapNear(angle: number, near: number): number
	return near + (angle - near + math.pi) % (2 * math.pi) - math.pi
end

local function faceYaw(root: BasePart, yaw: number)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
end

-- Can this dummy act right now (not ragdolled, stunned, bubbled or bonked)?
local function canAct(dummy: Model, humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Physics
		and state ~= Enum.HumanoidStateType.Ragdoll
		and state ~= Enum.HumanoidStateType.FallingDown
		and not dummy:GetAttribute("Bonked")
		and not dummy:GetAttribute("Bubbled")
		and dummy:GetAttribute("Ragdolled") ~= true
		and not CombatService.isStunned(dummy)
end

-- Keeps the arm held out in front while the dummy has a noodle.
local function holdOut(dummy: Model, humanoid: Humanoid)
	local track = holdTracks[dummy]
	if track and track.IsPlaying then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(holdAnimation)
	end)
	if not ok then
		warn(`[Noodle Bonk] Couldn't load the noodle hold pose: {result}`)
		return
	end
	result.Priority = Enum.AnimationPriority.Action
	result.Looped = true
	result:Play(0.1)
	holdTracks[dummy] = result
end

local function letGo(dummy: Model)
	local track = holdTracks[dummy]
	if track then
		track:Stop(0.2)
		track:Destroy()
		holdTracks[dummy] = nil
	end
end

local function arm(dummy: Model)
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid or heldNoodle(dummy) then
		return
	end
	local tool = NoodleTools.buildTool(noodleDef())
	tool.Parent = dummy
	humanoid:EquipTool(tool)
	humanoid.WalkSpeed = Config.DummyFight.WalkSpeed
	holdOut(dummy, humanoid)
end

local function disarm(dummy: Model)
	local tool = heldNoodle(dummy)
	if tool then
		tool:Destroy()
	end
	letGo(dummy)
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	local root = dummy:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.WalkSpeed = Config.DefaultWalkSpeed
		if root and root:IsA("BasePart") then
			humanoid:MoveTo(root.Position) -- stop chasing
		end
	end
	swinging[dummy] = nil
end

local function nearestPlayer(position: Vector3): (Model?, BasePart?)
	local best, bestRoot, bestDistance = nil, nil, Config.DummyFight.ChaseRange
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local _, root = CombatService.getLiving(character)
			if root and not character:GetAttribute("Bonked") then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance then
					best, bestRoot, bestDistance = character, root, distance
				end
			end
		end
	end
	return best, bestRoot
end

-- A real swing: turn away (wind-up), then whip around past the target. Clients
-- draw the noodle bending from the turn. The hit lands halfway through the sweep.
local function swing(dummy: Model, humanoid: Humanoid, root: BasePart, target: Model)
	swinging[dummy] = true
	lastSwing[dummy] = os.clock()
	humanoid.AutoRotate = false

	local def = noodleDef()
	local side = if math.random() < 0.5 then 1 else -1
	local _, targetRoot = CombatService.getLiving(target)
	local towardYaw = if targetRoot then yawToward(targetRoot.Position - root.Position) else 0
	local startYaw = yawOf(root)
	local windYaw = wrapNear(towardYaw + side * WIND_UP_ANGLE, startYaw)
	local endYaw = windYaw - side * (WIND_UP_ANGLE + FOLLOW_THROUGH_ANGLE)

	local function turn(fromYaw: number, toYaw: number, duration: number, onHalf: (() -> ())?)
		local started = os.clock()
		local halfDone = false
		while enabled and dummy.Parent and canAct(dummy, humanoid) do
			local t = math.min((os.clock() - started) / duration, 1)
			faceYaw(root, fromYaw + (toYaw - fromYaw) * t)
			if onHalf and not halfDone and t >= 0.5 then
				halfDone = true
				onHalf()
			end
			if t >= 1 then
				return true
			end
			RunService.Heartbeat:Wait()
		end
		return false
	end

	if turn(startYaw, windYaw, WIND_UP_TIME) then
		turn(windYaw, endYaw, SWEEP_TIME, function()
			local _, nowRoot = CombatService.getLiving(target)
			if not nowRoot or CombatService.isProtected(target) then
				return
			end
			local offset = nowRoot.Position - root.Position
			local reach = def.Length + Config.ArmReach + Config.BodyRadius
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > reach or math.abs(offset.Y) > 6 then
				return -- they got away
			end
			-- Mostly the way the noodle sweeps, partly away from the dummy
			local look = root.CFrame.LookVector
			local sweep = Vector3.new(-look.Z, 0, look.X) * side
			local away = Vector3.new(offset.X, 0, offset.Z)
			local direction = sweep * 0.5 + (if away.Magnitude > 0.01 then away.Unit * 0.5 else Vector3.zero)
			local power = def.Knockback * Config.DummyFight.Power
			CombatService.strike(
				nil,
				target,
				nowRoot,
				direction,
				power,
				def.Upward or Config.BaseUpward,
				def,
				dummy.Name
			)
		end)
	end

	if humanoid.Parent then
		humanoid.AutoRotate = true
	end
	swinging[dummy] = nil
end

local function think(dummy: Model)
	local humanoid, root = CombatService.getLiving(dummy)
	if not humanoid or not root or swinging[dummy] then
		return
	end
	if not heldNoodle(dummy) then
		arm(dummy) -- e.g. a dummy spawned after the fight started
	else
		holdOut(dummy, humanoid) -- in case the pose stopped
	end
	if not canAct(dummy, humanoid) then
		return
	end
	local target, targetRoot = nearestPlayer(root.Position)
	if not target or not targetRoot then
		humanoid:MoveTo(root.Position)
		return
	end

	local def = noodleDef()
	local offset = targetRoot.Position - root.Position
	local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local swingRange = def.Length + Config.ArmReach
	if flatDistance <= swingRange and os.clock() - (lastSwing[dummy] or 0) >= Config.DummyFight.SwingCooldown then
		humanoid:MoveTo(root.Position)
		task.spawn(swing, dummy, humanoid, root, target)
	elseif flatDistance > swingRange * 0.6 then
		humanoid:MoveTo(targetRoot.Position)
	end
end

function DummyFight.isOn(): boolean
	return enabled
end

function DummyFight.setEnabled(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	workspace:SetAttribute("DummyFight", on or nil)
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") then
			if on then
				arm(dummy)
			else
				disarm(dummy)
			end
		end
	end
end

function DummyFight.start()
	CollectionService:GetInstanceRemovedSignal(Config.DummyTag):Connect(function(instance)
		swinging[instance :: Model] = nil
		lastSwing[instance :: Model] = nil
		holdTracks[instance :: Model] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(THINK_EVERY)
			if enabled then
				for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
					if dummy:IsA("Model") and dummy.Parent then
						think(dummy)
					end
				end
			end
		end
	end)
end

return DummyFight
