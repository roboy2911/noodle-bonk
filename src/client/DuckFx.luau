--!strict
-- Duck visuals, drawn on each client so the server stays light:
--   * after every bonk, a little rubber duck flies from the splash into the jar
--   * the Giant Duck boss waddles side to side as it walks
--   * the Duck noodle's stampede: a row of ducks charging forward

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local FLY_TIME = 1.1
local MAX_FLYING = 12 -- more bonks than this at once just skip the flying duck
local DUCK_YELLOW = Color3.fromRGB(255, 215, 40)

local DuckFx = {}

local flying = 0
local folder: Folder

-- A small anchored rubber duck (the Blender model if loaded, else a ball).
function DuckFx.makeDuck(height: number): PVInstance
	local library = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local template = library and library:FindFirstChild("RubberDuck")
	if template and template:IsA("Model") then
		local duck = template:Clone()
		duck:ScaleTo(duck:GetScale() * height / 9)
		for _, item in duck:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanQuery = false
				item.CanTouch = false
				item.CastShadow = false
			end
		end
		duck.Parent = folder
		return duck
	end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * height
	ball.Color = DUCK_YELLOW
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Parent = folder
	return ball
end

local function place(duck: PVInstance, cframe: CFrame)
	if duck:IsA("Model") then
		duck:PivotTo(cframe)
	elseif duck:IsA("BasePart") then
		duck.CFrame = cframe
	end
end

-- Flying duck: from where someone fell in, in an arc, into the top of the jar.
local function flyToJar(from: Vector3)
	local jar = workspace:FindFirstChild("DuckJar")
	local lid = jar and jar:FindFirstChild("Lid")
	if not lid or not lid:IsA("BasePart") or jar:GetAttribute("Closed") or flying >= MAX_FLYING then
		return
	end
	flying += 1
	local start = Vector3.new(from.X, Config.WaterLevel + 2, from.Z)
	local finish = lid.Position
	local peak = math.max(start.Y, finish.Y) + 30
	local duck = DuckFx.makeDuck(1.6)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / FLY_TIME, 1)
		local flat = start:Lerp(finish, t)
		-- Up and over: a parabola through `peak`
		local y = (1 - t) * (1 - t) * start.Y
			+ 2 * (1 - t) * t * (2 * peak - (start.Y + finish.Y) / 2)
			+ t * t * finish.Y
		place(duck, CFrame.new(flat.X, y, flat.Z) * CFrame.Angles(0, t * 12, t * 2))
		if t >= 1 then
			connection:Disconnect()
			duck:Destroy()
			flying -= 1
		end
	end)
end

-- Stampede: a row of ducks runs forward along `direction`.
function DuckFx.stampede(origin: Vector3, direction: Vector3)
	local ducks: { PVInstance } = {}
	local offsets = { -6, -3, 0, 3, 6 }
	local right = direction:Cross(Vector3.yAxis)
	for i, offset in offsets do
		ducks[i] = DuckFx.makeDuck(2.6)
	end
	local ground = origin.Y - 3
	local started = os.clock()
	local duration = 1.2
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / duration, 1)
		for i, duck in ducks do
			local hop = math.abs(math.sin((t * 10 + i) * math.pi)) * 1.2
			local position = origin + direction * (Config.StampedeLength * t) + right * offsets[i]
			position = Vector3.new(position.X, ground + hop, position.Z)
			place(duck, CFrame.lookAt(position, position + direction))
		end
		if t >= 1 then
			connection:Disconnect()
			for _, duck in ducks do
				duck:Destroy()
			end
		end
	end)
end

-- The boss's waddle: rock side to side while it moves.
local function waddle()
	local now = os.clock()
	for _, boss in CollectionService:GetTagged("DuckBoss") do
		local body = boss:FindFirstChild("HumanoidRootPart")
		local motor = body and body:FindFirstChild("Waddle")
		if body and body:IsA("BasePart") and motor and motor:IsA("Motor6D") then
			local speed = Vector3.new(body.AssemblyLinearVelocity.X, 0, body.AssemblyLinearVelocity.Z).Magnitude
			local amount = math.clamp(speed / 8, 0.15, 1)
			motor.Transform = CFrame.new(0, math.abs(math.sin(now * 7)) * 0.6 * amount, 0)
				* CFrame.Angles(0, 0, math.sin(now * 7) * 0.14 * amount)
		end
	end
end

function DuckFx.start()
	folder = Instance.new("Folder")
	folder.Name = "DuckFx"
	folder.Parent = workspace

	Remotes.Bonked.OnClientEvent:Connect(function(info: { [string]: any })
		if (info.attacker or info.attackerName) and typeof(info.position) == "Vector3" then
			flyToJar(info.position)
		end
	end)
	RunService.RenderStepped:Connect(waddle)
end

return DuckFx
