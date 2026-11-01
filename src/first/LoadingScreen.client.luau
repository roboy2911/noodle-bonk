--!strict
-- Loading screen (runs from ReplicatedFirst, before anything else loads).
-- Shows the logo, a wobbling noodle loading bar and gameplay tips, and stays
-- up until the game and its 3D models are ready (or 15 seconds pass).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MAX_WAIT = 15
local TIPS = {
	"Turn your camera FAST to swing your noodle!",
	"Every hit soaks them. Soggy players fly further!",
	"Press E for your noodle's special ability.",
	"Bonk people in a row to go ON FIRE!",
	"Unlock new noodles by bonking and splashing.",
	"Umbrella tops are solid. Land on them!",
}

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.new(1, 1, 1)
background.Parent = gui
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(Color3.fromRGB(40, 150, 255), Color3.fromRGB(120, 215, 255))
gradient.Rotation = 90
gradient.Parent = background

local function label(text: string, size: UDim2, position: UDim2, color: Color3, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.LuckiestGuy
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.Parent = background
	local outline = Instance.new("UIStroke")
	outline.Thickness = stroke
	outline.Color = Color3.fromRGB(40, 20, 90)
	outline.Parent = l
	return l
end

local title = label("NOODLE", UDim2.fromScale(0.6, 0.13), UDim2.fromScale(0.5, 0.3), Color3.fromRGB(255, 226, 60), 5)
local bonk = label("BONK!", UDim2.fromScale(0.7, 0.2), UDim2.fromScale(0.5, 0.45), Color3.fromRGB(255, 110, 190), 6)
bonk.Rotation = -4
title.Rotation = -4

-- A pink "noodle" loading bar
local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, 0.65)
track.Size = UDim2.fromScale(0.42, 0.035)
track.BackgroundColor3 = Color3.fromRGB(20, 60, 120)
track.BackgroundTransparency = 0.4
track.Parent = background
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(255, 105, 180)
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local tip = Instance.new("TextLabel")
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, 0.75)
tip.Size = UDim2.fromScale(0.8, 0.045)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamBold
tip.TextScaled = true
tip.TextColor3 = Color3.new(1, 1, 1)
tip.Text = TIPS[math.random(#TIPS)]
tip.Parent = background

gui.Parent = player:WaitForChild("PlayerGui")

-- Animate: bouncing title, filling bar, rotating tips
local start = os.clock()
local tipIndex = math.random(#TIPS)
local lastTip = start
local connection = RunService.RenderStepped:Connect(function()
	local t = os.clock() - start
	bonk.Rotation = -4 + math.sin(t * 4) * 3
	bonk.Size = UDim2.fromScale(0.7 + math.sin(t * 6) * 0.01, 0.2)
	if os.clock() - lastTip > 3 then
		lastTip = os.clock()
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = TIPS[tipIndex]
	end
end)

local function setProgress(fraction: number)
	TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(fraction, 0.03, 1), 1) }):Play()
end

-- Step 1: the game itself
setProgress(0.15)
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setProgress(0.6)

-- Step 2: the 3D models (the server marks ModelLibrary "Ready" once it has tried)
local deadline = start + MAX_WAIT
local library = ReplicatedStorage:WaitForChild("ModelLibrary", math.max(0.1, deadline - os.clock()))
while library and not library:GetAttribute("Ready") and os.clock() < deadline do
	task.wait(0.1)
end
setProgress(1)
task.wait(0.4)

-- Fade out
connection:Disconnect()
local fade = TweenInfo.new(0.5)
TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
for _, child in background:GetDescendants() do
	if child:IsA("TextLabel") then
		TweenService:Create(child, fade, { TextTransparency = 1 }):Play()
	elseif child:IsA("UIStroke") then
		TweenService:Create(child, fade, { Transparency = 1 }):Play()
	elseif child:IsA("Frame") then
		TweenService:Create(child, fade, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.6)
gui:Destroy()
