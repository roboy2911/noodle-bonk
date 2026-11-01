--!strict
-- Builds noodle Tools and hands them out on spawn.
--
-- The noodle a player gets comes from the "Noodle" attribute on their Player.
-- Changing it (from a shop, a badge reward, or the Properties panel while
-- testing) gives them the new noodle right away.
--
-- For custom models, put a Tool named after the noodle Id in
-- ServerStorage/NoodleModels (e.g. ServerStorage/NoodleModels/Frozen).
-- Otherwise a plain foam cylinder is built.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)

type NoodleDef = Noodles.NoodleDef

local NoodleTools = {}

local function makeNonPhysical(part: BasePart)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function buildFoamNoodle(def: NoodleDef): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.DisplayName
	tool.RequiresHandle = true

	-- Invisible handle running along Z, which is the direction a tool points out of the hand
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(def.Thickness, def.Thickness, def.Length)
	handle.Transparency = 1
	makeNonPhysical(handle)
	handle.Parent = tool

	-- Cylinders run along X, so turn the foam 90 degrees to line it up with the handle
	local foam = Instance.new("Part")
	foam.Name = "Foam"
	foam.Shape = Enum.PartType.Cylinder
	foam.Size = Vector3.new(def.Length, def.Thickness, def.Thickness)
	foam.Color = def.Color
	foam.Material = Enum.Material.SmoothPlastic
	makeNonPhysical(foam)
	foam.CFrame = handle.CFrame * CFrame.Angles(0, math.rad(90), 0)
	foam.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = foam
	weld.Parent = handle

	-- Hold it near one end so most of the noodle sticks out in front
	tool.Grip = CFrame.new(0, 0, Config.GripSign * (def.Length / 2 - Config.GripOffset))
	return tool
end

local function buildTool(def: NoodleDef): Tool
	local models = ServerStorage:FindFirstChild("NoodleModels")
	local template = models and models:FindFirstChild(def.Id)
	local tool = if template and template:IsA("Tool") then template:Clone() else buildFoamNoodle(def)
	tool.CanBeDropped = false
	tool:SetAttribute("NoodleId", def.Id)
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

function NoodleTools.getNoodleDef(player: Player): NoodleDef
	local id = player:GetAttribute("Noodle")
	local def = if type(id) == "string" then Noodles[id] else nil
	return def or Noodles[Config.DefaultNoodle]
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
	if player:GetAttribute("Noodle") == nil then
		player:SetAttribute("Noodle", Config.DefaultNoodle)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:GetAttributeChangedSignal("Noodle"):Connect(function()
		NoodleTools.give(player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function NoodleTools.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return NoodleTools
