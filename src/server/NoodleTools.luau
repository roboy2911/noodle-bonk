--!strict
-- Builds noodle Tools and hands them out on spawn.
--
-- The Tool itself is just an invisible handle in the hand. Every client draws
-- the bendy noodle on top of it (client/NoodleVisuals).
--
-- The noodle a player gets comes from the "Noodle" attribute on their Player,
-- which is loaded from their save and changed through the noodle menu.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local DataService = require(script.Parent.DataService)

type NoodleDef = Noodles.NoodleDef

local NoodleTools = {}

local lastSelect: { [Player]: number } = {}

local function buildTool(def: NoodleDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.DisplayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new()
	tool:SetAttribute("NoodleId", def.Id)
	tool:SetAttribute("Scale", 1)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(def.Thickness, def.Thickness, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	return tool
end

local function removeNoodles(container: Instance?)
	if not container then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("NoodleId") ~= nil then
			child:Destroy()
		end
	end
end

-- Whether the player has unlocked this noodle.
function NoodleTools.canUse(player: Player, id: string): boolean
	local def = Noodles[id]
	return def ~= nil and Unlocks.isUnlocked(def, Unlocks.readStats(player))
end

function NoodleTools.getNoodleDef(player: Player): NoodleDef
	local id = player:GetAttribute("Noodle")
	if type(id) == "string" and NoodleTools.canUse(player, id) then
		return Noodles[id]
	end
	return Noodles[Config.DefaultNoodle]
end

-- Replaces whatever noodle the player has with their current one and equips it.
function NoodleTools.give(player: Player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not backpack or not humanoid or humanoid.Health <= 0 then
		return
	end

	removeNoodles(backpack)
	removeNoodles(character)

	local def = NoodleTools.getNoodleDef(player)
	local tool = buildTool(def)
	tool.Equipped:Connect(function()
		humanoid.WalkSpeed = def.WalkSpeed or Config.DefaultWalkSpeed
	end)
	tool.Unequipped:Connect(function()
		humanoid.WalkSpeed = Config.DefaultWalkSpeed
	end)
	tool.Parent = backpack
	humanoid:EquipTool(tool)
end

-- A pick from the noodle menu. Setting the attribute triggers give().
local function onSelectNoodle(player: Player, id: unknown)
	if type(id) ~= "string" or not NoodleTools.canUse(player, id) then
		return
	end
	local now = os.clock()
	if now - (lastSelect[player] or 0) < Config.SelectCooldown then
		return
	end
	lastSelect[player] = now
	DataService.setSelected(player, id)
	if player:GetAttribute("Noodle") ~= id then
		player:SetAttribute("Noodle", id)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	if not character:FindFirstChildOfClass("ForceField") then
		local forceField = Instance.new("ForceField")
		forceField.Parent = character
		Debris:AddItem(forceField, Config.SpawnProtection)
	end
	character:WaitForChild("Humanoid")
	player:WaitForChild("Backpack")
	NoodleTools.give(player)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:GetAttributeChangedSignal("Noodle"):Connect(function()
		NoodleTools.give(player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	-- Restore their saved noodle once their data (and unlock stats) is in
	local data = DataService.waitForData(player)
	if data and player.Parent then
		player:SetAttribute("Noodle", if NoodleTools.canUse(player, data.Selected) then data.Selected else Config.DefaultNoodle)
	end
end

function NoodleTools.start()
	Remotes.SelectNoodle.OnServerEvent:Connect(onSelectNoodle)
	Players.PlayerRemoving:Connect(function(player)
		lastSelect[player] = nil
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return NoodleTools
