--!strict
-- Builds the arena: a big round pool deck floating over water, with a few
-- obstacles to fight around. Skipped if Workspace already has a model named
-- "Arena" (so you can build your own in Studio), or if Config.AutoBuildArena
-- is false.
--
-- Layout, from the middle out:
--   spawn pad (center) -> benches (r 40) -> umbrellas (r 75) -> crates (r 120) -> open edge (r 165)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local ArenaBuilder = {}

local DECK_THICKNESS = 6

local DECK_COLOR = Color3.fromRGB(235, 225, 200)
local WOOD_COLOR = Color3.fromRGB(170, 120, 75)
local POLE_COLOR = Color3.fromRGB(240, 240, 240)
local UMBRELLA_COLORS = {
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(255, 220, 70),
	Color3.fromRGB(110, 220, 130),
}

-- Cylinders run along X. These turn one to stand upright or lie flat.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A point on the deck at `radius` from the middle, at `angleDeg`, facing the middle.
local function ringCFrame(radius: number, angleDeg: number, height: number): CFrame
	local angle = math.rad(angleDeg)
	local position = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
	return CFrame.lookAt(position, Vector3.new(0, height, 0))
end

local function buildUmbrella(parent: Instance, base: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Umbrella"
	model.Parent = parent

	local pole = part(model, "Pole", Vector3.new(10, 0.6, 0.6), base * CFrame.new(0, 5, 0) * UPRIGHT, POLE_COLOR)
	pole.Shape = Enum.PartType.Cylinder

	-- Solid canopy: people can land on it after a big launch
	local canopy = part(model, "Canopy", Vector3.new(0.6, 14, 14), base * CFrame.new(0, 10, 0) * UPRIGHT, color, Enum.Material.Fabric)
	canopy.Shape = Enum.PartType.Cylinder
end

local function buildCrates(parent: Instance, base: CFrame, stacked: boolean)
	local model = Instance.new("Model")
	model.Name = "Crates"
	model.Parent = parent
	part(model, "Crate", Vector3.new(5, 5, 5), base * CFrame.new(0, 2.5, 0), WOOD_COLOR, Enum.Material.WoodPlanks)
	part(model, "Crate", Vector3.new(5, 5, 5), base * CFrame.new(5.5, 2.5, 0.5) * CFrame.Angles(0, math.rad(12), 0), WOOD_COLOR, Enum.Material.WoodPlanks)
	if stacked then
		part(model, "Crate", Vector3.new(5, 5, 5), base * CFrame.new(2.7, 7.5, 0.2) * CFrame.Angles(0, math.rad(-8), 0), WOOD_COLOR, Enum.Material.WoodPlanks)
	end
end

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

	-- The deck. Top surface sits at Y = 0.
	local deck = part(
		arena,
		"PoolDeck",
		Vector3.new(DECK_THICKNESS, Config.ArenaDiameter, Config.ArenaDiameter),
		CFrame.new(0, -DECK_THICKNESS / 2, 0) * UPRIGHT,
		DECK_COLOR,
		Enum.Material.Concrete
	)
	deck.Shape = Enum.PartType.Cylinder

	-- Blue stripe around the edge so the drop is easy to see
	local edge = part(
		arena,
		"EdgeStripe",
		Vector3.new(0.2, Config.ArenaDiameter, Config.ArenaDiameter),
		CFrame.new(0, 0.05, 0) * UPRIGHT,
		Color3.fromRGB(80, 200, 255)
	)
	edge.Shape = Enum.PartType.Cylinder
	edge.CanCollide = false
	local inner = part(
		arena,
		"EdgeInner",
		Vector3.new(0.25, Config.ArenaDiameter - 6, Config.ArenaDiameter - 6),
		CFrame.new(0, 0.06, 0) * UPRIGHT,
		DECK_COLOR,
		Enum.Material.Concrete
	)
	inner.Shape = Enum.PartType.Cylinder
	inner.CanCollide = false

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(0, 0.5, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0 -- NoodleTools adds its own spawn protection
	spawnLocation.Color = Color3.fromRGB(80, 200, 255)
	spawnLocation.Parent = arena

	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = arena

	-- Low benches near the middle, long side running along the ring
	for i = 0, 3 do
		local base = ringCFrame(40, i * 90 + 45, 0)
		part(obstacles, "Bench", Vector3.new(12, 2.5, 3), base * CFrame.new(0, 1.25, 0), WOOD_COLOR, Enum.Material.Wood)
	end

	-- Umbrellas in the middle ring
	for i = 0, 5 do
		buildUmbrella(obstacles, ringCFrame(75, i * 60, 0), UMBRELLA_COLORS[i % #UMBRELLA_COLORS + 1])
	end

	-- Crate piles in the outer ring, between the umbrellas
	for i = 0, 7 do
		buildCrates(obstacles, ringCFrame(120, i * 45 + 22.5, 0), i % 2 == 0)
	end

	arena.Parent = workspace

	-- The pool everyone gets bonked into
	workspace.Terrain:FillBlock(
		CFrame.new(0, Config.WaterLevel - 10, 0),
		Vector3.new(2048, 20, 2048),
		Enum.Material.Water
	)
end

return ArenaBuilder
