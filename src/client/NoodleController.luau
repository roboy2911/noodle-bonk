--!strict
-- Swing input and the active ability button for whatever noodle you're holding.
-- Swinging uses Tool.Activated, which covers mouse, touch and gamepad.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local HitQuery = require(Shared.HitQuery)
local Effects = require(script.Parent.Effects)

type NoodleDef = Noodles.NoodleDef

local ABILITY_ACTION = "NoodleAbility"

local player = Players.LocalPlayer

local NoodleController = {}

local currentTool: Tool? = nil
local currentDef: NoodleDef? = nil
local activatedConnection: RBXScriptConnection? = nil
local lastSwing = 0
local lastAbility = 0

local function isStunned(character: Model): boolean
	local stunnedUntil = character:GetAttribute("StunnedUntil")
	return type(stunnedUntil) == "number" and stunnedUntil > workspace:GetServerTimeNow()
end

local function swing(tool: Tool, def: NoodleDef)
	local character = player.Character
	if not character or isStunned(character) then
		return
	end
	local now = os.clock()
	if now - lastSwing < def.Cooldown then
		return
	end
	lastSwing = now

	-- The default Animate script plays its slash animation when it sees this value
	local slash = Instance.new("StringValue")
	slash.Name = "toolanim"
	slash.Value = "Slash"
	slash.Parent = tool

	Effects.playSound(Config.Sounds.Swing)

	-- Always tell the server about the swing, even a miss, so it can end spawn protection
	local targets = HitQuery.findTargets(character, def.Range, def.ArcDeg, def.MaxTargets)
	Remotes.Swing:FireServer(targets)
end

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
	if now - lastAbility < (def.AbilityCooldown or 5) then
		return Enum.ContextActionResult.Sink
	end
	lastAbility = now

	Remotes.UseAbility:FireServer()
	return Enum.ContextActionResult.Sink
end

local function unequip()
	if activatedConnection then
		activatedConnection:Disconnect()
		activatedConnection = nil
	end
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
	activatedConnection = tool.Activated:Connect(function()
		swing(tool, def)
	end)

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
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return NoodleController
