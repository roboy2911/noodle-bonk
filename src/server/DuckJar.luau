--!strict
-- A big glass jar on the deck that fills with rubber ducks: one per bonk.
-- When it reaches Config.DuckJar.Target, it empties and the Giant Rubber
-- Duck boss appears (server/DuckBoss). While the boss is out, the jar is
-- closed and doesn't collect ducks.
--
-- Built to stay light: the ducks inside are one yellow fill that rises, plus
-- a few ducks on top. The duck you see flying into the jar after a bonk is
-- drawn by each client (client/DuckFx). Each server has its own jar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DuckBoss = require(script.Parent.DuckBoss)
local ModelLibrary = require(script.Parent.ModelLibrary)

local JAR_HEIGHT = 12
local JAR_WIDTH = 9
local FILL_WIDTH = 8.2
local BASE_HEIGHT = 1.2
local TOP_DUCKS = 5
local TOP_DUCK_SCALE = 0.13 -- about 1.2 studs tall
local DUCK_YELLOW = Color3.fromRGB(255, 215, 40)

local DuckJar = {}

local count = 0
local jar: Model
local fill: BasePart
local topDucks: { PVInstance } = {}
local label: TextLabel
local subLabel: TextLabel
local floorY = 0

local function commas(n: number): string
	local text = tostring(math.floor(n))
	while true do
		local replaced, found = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if found == 0 then
			return text
		end
	end
end

local function cylinder(name: string, height: number, width: number, center: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, width, width)
	p.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)) -- stand it up
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = jar
	return p
end

local function smallDuck(): PVInstance
	local duck = ModelLibrary.spawn("RubberDuck", CFrame.new(), jar, TOP_DUCK_SCALE)
	if duck then
		for _, item in duck:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanQuery = false
				item.CastShadow = false
			end
		end
		return duck
	end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 1.2
	ball.Color = DUCK_YELLOW
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Parent = jar
	return ball
end

local function findFloor(spot: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local result = workspace:Raycast(spot + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
	return if result then result.Position.Y else spot.Y
end

local function build()
	local spot = Config.DuckJar.Spot
	floorY = findFloor(spot)

	jar = Instance.new("Model")
	jar.Name = "DuckJar"

	cylinder(
		"Base",
		BASE_HEIGHT,
		JAR_WIDTH + 1.4,
		Vector3.new(spot.X, floorY + BASE_HEIGHT / 2, spot.Z),
		Color3.fromRGB(150, 100, 60)
	).Material =
		Enum.Material.Wood

	local glass = cylinder(
		"Glass",
		JAR_HEIGHT,
		JAR_WIDTH,
		Vector3.new(spot.X, floorY + BASE_HEIGHT + JAR_HEIGHT / 2, spot.Z),
		Color3.fromRGB(200, 235, 255)
	)
	glass.Material = Enum.Material.Glass
	glass.Transparency = 0.6
	glass.CastShadow = false

	local lid = cylinder(
		"Lid",
		1,
		JAR_WIDTH + 0.6,
		Vector3.new(spot.X, floorY + BASE_HEIGHT + JAR_HEIGHT + 0.5, spot.Z),
		Color3.fromRGB(230, 60, 70)
	)

	fill = cylinder("Fill", 0.05, FILL_WIDTH, Vector3.new(spot.X, floorY + BASE_HEIGHT, spot.Z), DUCK_YELLOW)
	fill.CanCollide = false
	fill.CanQuery = false
	fill.CastShadow = false

	for i = 1, TOP_DUCKS do
		topDucks[i] = smallDuck()
	end

	-- Counter over the lid
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 80)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.Parent = lid

	label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = DUCK_YELLOW
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label

	subLabel = Instance.new("TextLabel")
	subLabel.Position = UDim2.fromScale(0, 0.6)
	subLabel.Size = UDim2.new(1, 0, 0.4, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamBold
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.new(1, 1, 1)
	subLabel.Parent = billboard
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 2
	subStroke.Parent = subLabel

	jar.Parent = workspace
end

-- Moves the fill and the top ducks to match the count, and updates the counter.
local function refresh()
	local target = Config.DuckJar.Target
	local spot = Config.DuckJar.Spot
	local fraction = math.clamp(count / target, 0, 1)
	local height = math.max(0.05, (JAR_HEIGHT - 0.3) * fraction)
	local bottom = floorY + BASE_HEIGHT
	fill.Size = Vector3.new(height, FILL_WIDTH, FILL_WIDTH)
	fill.CFrame = CFrame.new(spot.X, bottom + height / 2, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
	fill.Transparency = if count > 0 then 0 else 1

	local top = bottom + height
	for i, duck in topDucks do
		local angle = (i / TOP_DUCKS) * math.pi * 2
		local radius = if i == 1 then 0 else 2.4
		local position = Vector3.new(spot.X + math.cos(angle) * radius, top, spot.Z + math.sin(angle) * radius)
		local cframe = CFrame.new(position) * CFrame.Angles(0, angle * 1.7, 0)
		local visible = count > 0
		if duck:IsA("Model") then
			duck:PivotTo(if visible then cframe else CFrame.new(position - Vector3.new(0, 50, 0)))
		elseif duck:IsA("BasePart") then
			duck.CFrame = cframe * CFrame.new(0, 0.6, 0)
			duck.Transparency = if visible then 0 else 1
		end
	end

	jar:SetAttribute("Count", count)
	jar:SetAttribute("Target", target)
	jar:SetAttribute("Closed", DuckBoss.isActive() or nil)
	if DuckBoss.isActive() then
		label.Text = "GIANT DUCK IS LOOSE!"
		subLabel.Text = "Bonk it into the pool!"
	else
		label.Text = `{commas(count)} / {commas(target)}`
		subLabel.Text = "ducks until the GIANT DUCK"
	end
end

-- Summons the boss if the jar is full (and no boss is out).
local function check()
	if count >= Config.DuckJar.Target and not DuckBoss.isActive() then
		count = 0
		DuckBoss.spawn()
	end
	refresh()
end

-- One duck per bonk. Ignored while the boss is out.
function DuckJar.add(amount: number)
	if DuckBoss.isActive() then
		return
	end
	count += amount
	check()
end

function DuckJar.getCount(): number
	return count
end

-- Admin: set this server's duck count. A full jar summons the boss.
function DuckJar.set(amount: number)
	count = math.max(0, math.floor(amount))
	check()
end

function DuckJar.start()
	build()
	DuckBoss.onGone(refresh)
	refresh()
end

return DuckJar
