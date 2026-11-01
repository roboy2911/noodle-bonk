--!strict
-- Builds a quick test arena (a round pool deck floating over water) so the
-- game is playable in an empty place. Skipped if Workspace already has a
-- model named "Arena", or if Config.AutoBuildArena is false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local ArenaBuilder = {}

local DECK_DIAMETER = 110
local DECK_THICKNESS = 6

function ArenaBuilder.build()
	if not Config.AutoBuildArena or workspace:FindFirstChild("Arena") then
		return
	end

	-- The default Baseplate would catch everyone who gets knocked off
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"

	-- Cylinders run along X, so tip it 90 degrees to stand it upright. Top surface sits at Y = 0.
	local deck = Instance.new("Part")
	deck.Name = "PoolDeck"
	deck.Shape = Enum.PartType.Cylinder
	deck.Size = Vector3.new(DECK_THICKNESS, DECK_DIAMETER, DECK_DIAMETER)
	deck.CFrame = CFrame.new(0, -DECK_THICKNESS / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	deck.Anchored = true
	deck.Material = Enum.Material.Concrete
	deck.Color = Color3.fromRGB(235, 225, 200)
	deck.Parent = arena

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = CFrame.new(0, 0.5, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0 -- NoodleTools adds its own spawn protection
	spawnLocation.Color = Color3.fromRGB(80, 200, 255)
	spawnLocation.Parent = arena

	arena.Parent = workspace

	-- The pool everyone gets bonked into
	workspace.Terrain:FillBlock(
		CFrame.new(0, Config.WaterLevel - 10, 0),
		Vector3.new(1024, 20, 1024),
		Enum.Material.Water
	)
end

return ArenaBuilder
