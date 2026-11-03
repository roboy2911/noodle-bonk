--!strict
-- Builds the arena: a big round pool deck floating over water, dressed with
-- the Blender models (ModelLibrary). If a model didn't load, simple parts
-- stand in for it, so the game always works. Skipped if Workspace already
-- has a model named "Arena" (so you can build your own in Studio), or if
-- Config.AutoBuildArena is false.
--
-- Layout, from the middle out:
--   spawn pad -> lounge chairs (r 40) -> umbrellas (r 75) -> lifeguard tower,
--   crates (r 120) -> palm trees (r 150) -> open edge (r 165)
-- Beach balls, swim rings and a giant rubber duck are scattered around.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local ModelLibrary = require(script.Parent.ModelLibrary)

local ArenaBuilder = {}

local DECK_THICKNESS = 6

local DECK_COLOR = Color3.fromRGB(238, 228, 205)
local WOOD_COLOR = Color3.fromRGB(170, 120, 75)
local POLE_COLOR = Color3.fromRGB(240, 240, 240)
local WHITE = Color3.fromRGB(250, 250, 250)
local UMBRELLA_COLORS = {
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(255, 214, 50),
	Color3.fromRGB(100, 215, 120),
}
local RING_COLORS = {
	Color3.fromRGB(235, 64, 64),
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(60, 140, 255),
	Color3.fromRGB(255, 140, 30),
}

-- Cylinders run along X. This stands one upright.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
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

-- Simple stand-ins for when the models aren't available -------------------------

local function fallbackUmbrella(parent: Instance, base: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Umbrella"
	model.Parent = parent
	local pole = part(model, "Pole", Vector3.new(10, 0.6, 0.6), base * CFrame.new(0, 5, 0) * UPRIGHT, POLE_COLOR)
	pole.Shape = Enum.PartType.Cylinder
	local canopy = part(
		model,
		"Canopy",
		Vector3.new(0.6, 14, 14),
		base * CFrame.new(0, 10, 0) * UPRIGHT,
		color,
		Enum.Material.Fabric
	)
	canopy.Shape = Enum.PartType.Cylinder
end

local function crate(parent: Instance, cframe: CFrame)
	if not ModelLibrary.spawn("Crate", cframe, parent) then
		part(
			parent,
			"Crate",
			Vector3.new(5, 5, 5),
			cframe * CFrame.new(0, 2.5, 0),
			WOOD_COLOR,
			Enum.Material.WoodPlanks
		)
	end
end

-- Arena pieces ------------------------------------------------------------------------

local function buildDeck(arena: Model)
	-- The plain cylinder is always the floor players stand on (exact collision).
	local deck = part(
		arena,
		"PoolDeck",
		Vector3.new(DECK_THICKNESS, Config.ArenaDiameter, Config.ArenaDiameter),
		CFrame.new(0, -DECK_THICKNESS / 2, 0) * UPRIGHT,
		DECK_COLOR,
		Enum.Material.Concrete
	)
	deck.Shape = Enum.PartType.Cylinder

	local model = ModelLibrary.spawn("PoolDeck", CFrame.new(0, -DECK_THICKNESS, 0), arena)
	if model then
		-- The mesh is the look; the cylinder underneath stays as the floor
		deck.Transparency = 1
		-- Line the mesh's deck surface up with Y = 0 (its rounded lip pokes up a little)
		local box, size = model:GetBoundingBox()
		local top = box.Position.Y + size.Y / 2
		model:PivotTo(model:GetPivot() * CFrame.new(0, 0.45 - top, 0))
		return
	end

	-- Fallback: blue stripe around the edge so the drop is easy to see
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
end

local function buildSpawn(arena: Model)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(0, 0.5, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0 -- NoodleTools adds its own spawn protection
	spawnLocation.Color = Color3.fromRGB(80, 200, 255)
	spawnLocation.Parent = arena

	if ModelLibrary.spawn("SpawnPad", CFrame.new(0, 0, 0), arena) then
		-- The pad model is what you see and stand on
		spawnLocation.Transparency = 1
		spawnLocation.CanCollide = false
		local decal = spawnLocation:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
	end
end

local function buildProps(obstacles: Folder)
	local random = Random.new(42) -- same layout every server

	-- Lounge chairs in pairs near the middle
	for i = 0, 3 do
		local base = ringCFrame(40, i * 90 + 45, 0)
		for _, side in { -2.4, 2.4 } do
			local spot = base * CFrame.new(side, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			if not ModelLibrary.spawn("LoungeChair", spot, obstacles) then
				part(
					obstacles,
					"Bench",
					Vector3.new(3, 2.5, 6),
					spot * CFrame.new(0, 1.25, 0),
					WOOD_COLOR,
					Enum.Material.Wood
				)
			end
		end
	end

	-- Umbrellas in the middle ring (their tops are solid, so you can land on them)
	for i = 0, 5 do
		local color = UMBRELLA_COLORS[i % #UMBRELLA_COLORS + 1]
		local base = ringCFrame(75, i * 60, 0) * CFrame.Angles(0, math.rad(i * 17), 0)
		if not ModelLibrary.spawn("Umbrella", base, obstacles, 1, { ColorA = color, ColorB = WHITE }) then
			fallbackUmbrella(obstacles, base, color)
		end
	end

	-- Crate piles in the outer ring, between the umbrellas
	for i = 0, 7 do
		local base = ringCFrame(120, i * 45 + 22.5, 0)
		crate(obstacles, base)
		crate(obstacles, base * CFrame.new(5.6, 0, 0.5) * CFrame.Angles(0, math.rad(12), 0))
		if i % 2 == 0 then
			crate(obstacles, base * CFrame.new(2.8, 5, 0.2) * CFrame.Angles(0, math.rad(-8), 0))
		end
	end

	-- Everything below is decoration only, so it's skipped without models
	ModelLibrary.spawn("LifeguardTower", ringCFrame(100, 200, 0), obstacles)

	for i = 0, 5 do
		local base = ringCFrame(150, i * 60 + 8, 0) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		local palm = ModelLibrary.spawn("PalmTree", base, obstacles, random:NextNumber(0.85, 1.15))
		if palm and i == 1 then
			-- Secret: a coconut hidden at the top of this palm (Coconut noodle)
			local cframe, size = palm:GetBoundingBox()
			local coconut = Instance.new("Part")
			coconut.Name = "SecretCoconut"
			coconut.Shape = Enum.PartType.Ball
			coconut.Size = Vector3.one * 2.2
			coconut.Color = Color3.fromRGB(110, 70, 40)
			coconut.Anchored = true
			coconut.CanCollide = false
			coconut.Position = cframe.Position + Vector3.new(0, size.Y / 2 - 2.5, 0)
			coconut.Parent = obstacles
		end
	end

	local bigDuck =
		ModelLibrary.spawn("RubberDuck", ringCFrame(128, 300, 0) * CFrame.Angles(0, math.rad(200), 0), obstacles)
	if bigDuck then
		bigDuck.Name = "SecretDuck" -- stand on it long enough... (Quack noodle)
	end

	for i = 1, 6 do
		local angle = random:NextNumber(0, 360)
		local radius = random:NextNumber(22, 140)
		local ball = ringCFrame(radius, angle, 0) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		ModelLibrary.spawn("BeachBall", ball, obstacles, random:NextNumber(0.9, 1.3))
	end

	for i = 1, 5 do
		local angle = random:NextNumber(0, 360)
		local radius = random:NextNumber(25, 145)
		local color = RING_COLORS[(i - 1) % #RING_COLORS + 1]
		ModelLibrary.spawn("SwimRing", ringCFrame(radius, angle, 0), obstacles, 1, { ColorA = color, ColorB = WHITE })
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

	buildDeck(arena)
	buildSpawn(arena)

	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = arena
	buildProps(obstacles)

	arena.Parent = workspace

	-- The pool everyone gets bonked into
	workspace.Terrain:FillBlock(
		CFrame.new(0, Config.WaterLevel - 10, 0),
		Vector3.new(2048, 20, 2048),
		Enum.Material.Water
	)
end

return ArenaBuilder
