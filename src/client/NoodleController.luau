--!strict
-- Turns your noodle's movement into hits, and handles the ability button.
--
-- There's no swing button. Turn the camera (CameraController keeps your
-- character facing it) and the bendy noodle sweeps around. Whenever a part of
-- it moving fast enough touches someone, that's a hit; the server double-checks.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)
local Effects = require(script.Parent.Effects)
local NoodleVisuals = require(script.Parent.NoodleVisuals)
local CameraController = require(script.Parent.CameraController)

type NoodleDef = Noodles.NoodleDef

local ABILITY_ACTION = "NoodleAbility"
local WHOOSH_GAP = 0.3

local player = Players.LocalPlayer

local NoodleController = {}

local currentTool: Tool? = nil
local currentDef: NoodleDef? = nil
local lastAbility = -math.huge
local lastWhoosh = 0
local localHits: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local function isStunned(character: Model): boolean
	local stunnedUntil = character:GetAttribute("StunnedUntil")
	return type(stunnedUntil) == "number" and stunnedUntil > workspace:GetServerTimeNow()
end

-- Hit detection --------------------------------------------------------------

local function onLocalStep(visual: NoodleVisuals.Visual, dt: number)
	local character = visual.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if dt <= 0 or not humanoid or humanoid.Health <= 0 or isStunned(character) then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return -- no bonking while flopping around
	end

	local def = visual.def
	local sim = visual.sim
	local radius = def.Thickness * visual.scale / 2 + Config.HitPadding
	local now = os.clock()
	local fastest = 0
	overlap.FilterDescendantsInstances = { character }

	-- Skip the hand and the first segment; they barely move
	for i = 3, #sim.points do
		local current, previous = sim.points[i], sim.previous[i]
		local moved = (current - previous).Magnitude
		local speed = moved / dt
		fastest = math.max(fastest, speed)

		if speed >= Config.MinHitSpeed then
			-- Check the whole path this point swept since last frame
			local center = (current + previous) / 2
			for _, part in workspace:GetPartBoundsInRadius(center, radius + moved / 2, overlap) do
				local target, targetHumanoid = HitQuery.getCharacter(part)
				if
					target
					and targetHumanoid
					and target ~= character
					and targetHumanoid.Health > 0
					and now - (localHits[target] or -math.huge) >= def.Cooldown
				then
					localHits[target] = now
					local direction = (current - previous).Unit
					Remotes.NoodleHit:FireServer(target, center, direction, speed)
					-- Bounce the noodle back off them
					sim:impulse(i, -direction * speed * 0.35)
					CameraController.shake(0.25)
				end
			end
		end
	end

	if fastest >= Config.WhooshSpeed and now - lastWhoosh > WHOOSH_GAP then
		lastWhoosh = now
		Effects.playSound(Config.Sounds.Swing)
	end
end

-- Ability ------------------------------------------------------------------

local function onAbilityAction(_: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local def = currentDef
	local character = player.Character
	if not def or not def.Ability or not character then
		return Enum.ContextActionResult.Pass
	end
	if isStunned(character) then
		return Enum.ContextActionResult.Sink
	end

	local now = os.clock()
	local cooldown = if player:GetAttribute("AdminNoCooldown") then 0 else def.AbilityCooldown or 5
	if now - lastAbility < cooldown then
		return Enum.ContextActionResult.Sink
	end
	lastAbility = now

	Remotes.UseAbility:FireServer()
	return Enum.ContextActionResult.Sink
end

-- Name of the held noodle's ability (or nil) and how ready it is, 0 to 1.
function NoodleController.getAbilityState(): (string?, number)
	local def = currentDef
	if not def or not def.Ability then
		return nil, 0
	end
	if player:GetAttribute("AdminNoCooldown") then
		return def.Ability, 1
	end
	local cooldown = def.AbilityCooldown or 5
	return def.Ability, math.clamp((os.clock() - lastAbility) / cooldown, 0, 1)
end

-- Equipping --------------------------------------------------------------------

local function unequip()
	ContextActionService:UnbindAction(ABILITY_ACTION)
	currentTool = nil
	currentDef = nil
end

local function equip(tool: Tool)
	local id = tool:GetAttribute("NoodleId")
	local def = if type(id) == "string" then Noodles[id] else nil
	if not def then
		return
	end

	unequip()
	currentTool = tool
	currentDef = def
	if def.Ability then
		-- `true` adds an on-screen button on touch devices
		ContextActionService:BindAction(ABILITY_ACTION, onAbilityAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
		ContextActionService:SetTitle(ABILITY_ACTION, def.Ability)
	end
end

local function onCharacterAdded(character: Model)
	unequip()

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("NoodleId") ~= nil then
			equip(child)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child == currentTool then
			unequip()
		end
	end)

	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("NoodleId") ~= nil then
		equip(tool)
	end
end

function NoodleController.start()
	NoodleVisuals.onLocalStep(onLocalStep)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return NoodleController
