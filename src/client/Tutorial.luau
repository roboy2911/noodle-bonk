--!strict
-- A short first-time tutorial: swing → hit someone → bonk them into the pool.
-- It shows once per player (saved as the "Tutorial" stat); there's a Skip
-- button. Each step finishes when the player actually does it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local Effects = require(script.Parent.Effects)
local NoodleController = require(script.Parent.NoodleController)

local player = Players.LocalPlayer

local BONK_STEP_TIMEOUT = 90 -- move on even if they haven't bonked anyone yet
local LAST_STEP_TIME = 6
local GOLD = Color3.fromRGB(255, 215, 40)

local Tutorial = {}

local gui: ScreenGui
local panel: Frame
local stepLabel: TextLabel
local titleLabel: TextLabel
local hintLabel: TextLabel
local finished = false
local highlight: Highlight? = nil

local function swingHint(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Drag your finger across the screen FAST to whip your noodle around"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Flick the right stick FAST to whip your noodle around"
	end
	return "There's no attack button: move your mouse left and right FAST"
end

local function noodleBot(): Model?
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") and dummy:GetAttribute("SoloDummy") then
			return dummy
		end
	end
	return nil
end

-- Outlines Noodle Bot (only on this screen) so new players know who to hit.
local function pointAtBot(on: boolean)
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	local bot = if on then noodleBot() else nil
	if bot then
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = GOLD
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = bot
		h.Parent = gui
		highlight = h
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 70)
	panel.Size = UDim2.new(0.9, 0, 0, 120)
	panel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(620, 140)
	sizeLimit.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = panel

	stepLabel = Instance.new("TextLabel")
	stepLabel.Position = UDim2.fromOffset(16, 8)
	stepLabel.Size = UDim2.new(1, -120, 0, 18)
	stepLabel.BackgroundTransparency = 1
	stepLabel.Font = Enum.Font.GothamBold
	stepLabel.TextSize = 14
	stepLabel.TextColor3 = Color3.fromRGB(170, 190, 220)
	stepLabel.TextXAlignment = Enum.TextXAlignment.Left
	stepLabel.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Position = UDim2.fromOffset(16, 26)
	titleLabel.Size = UDim2.new(1, -32, 0, 44)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = GOLD
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	hintLabel = Instance.new("TextLabel")
	hintLabel.Position = UDim2.fromOffset(16, 72)
	hintLabel.Size = UDim2.new(1, -32, 0, 40)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 17
	hintLabel.TextWrapped = true
	hintLabel.TextColor3 = Color3.new(1, 1, 1)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextYAlignment = Enum.TextYAlignment.Top
	hintLabel.Parent = panel

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -10, 0, 8)
	skip.Size = UDim2.fromOffset(90, 26)
	skip.BackgroundColor3 = Color3.fromRGB(60, 70, 95)
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 14
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Text = "Skip tutorial"
	skip.Parent = panel
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip
	skip.Activated:Connect(function()
		finished = true
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function show(step: number, title: string, hint: string)
	stepLabel.Text = `TUTORIAL  {step}/4`
	titleLabel.Text = title
	hintLabel.Text = hint
	-- Little pop so the change is noticed
	local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = panel
	scale.Scale = 1.08
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- Waits until `done()` is true (or the tutorial is skipped / times out).
local function waitFor(done: () -> boolean, timeout: number?)
	local started = os.clock()
	while not finished and not done() do
		if timeout and os.clock() - started > timeout then
			return
		end
		task.wait(0.1)
	end
	if not finished then
		Effects.playSound("Click")
	end
end

local function run()
	build()
	local hitSomeone, bonkedSomeone = false, false
	local hitConnection = Remotes.HitConfirm.OnClientEvent:Connect(function(_, _, attacker: Player?)
		if attacker == player then
			hitSomeone = true
		end
	end)
	local bonkConnection = Remotes.Bonked.OnClientEvent:Connect(function(info: { [string]: any })
		if info.attacker == player then
			bonkedSomeone = true
		end
	end)

	-- 1: swing
	local stepStart = os.clock()
	show(1, "SWING YOUR NOODLE!", swingHint())
	waitFor(function()
		return NoodleController.lastFastSwingTime() > stepStart
	end)

	-- 2: hit someone
	if not finished then
		local bot = noodleBot()
		show(
			2,
			if bot then "HIT NOODLE BOT!" else "HIT SOMEONE!",
			if bot
				then "Walk up to the glowing dummy and whip your noodle into it"
				else "Walk up to another player and whip your noodle into them"
		)
		pointAtBot(true)
		waitFor(function()
			return hitSomeone
		end)
	end

	-- 3: bonk them into the pool
	if not finished then
		show(
			3,
			"BONK THEM INTO THE POOL!",
			"Every hit makes them soggier, so they fly further. Knock them off the edge!"
		)
		waitFor(function()
			return bonkedSomeone
		end, BONK_STEP_TIMEOUT)
	end
	pointAtBot(false)

	-- 4: what's next
	if not finished then
		Effects.playSound("Streak")
		show(
			4,
			"YOU'RE A NOODLE BONKER!",
			"Bonk more people to unlock new noodles (press N). Press E to use a noodle's ability."
		)
		waitFor(function()
			return false
		end, LAST_STEP_TIME)
	end

	hitConnection:Disconnect()
	bonkConnection:Disconnect()
	Remotes.TutorialDone:FireServer()
	local fade = TweenService:Create(panel, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	gui:Destroy()
end

function Tutorial.isActive(): boolean
	return gui ~= nil and gui.Parent ~= nil
end

function Tutorial.start()
	task.spawn(function()
		-- Wait for saved stats to arrive (they're copied onto the Player)
		local attribute = Unlocks.statAttribute("Tutorial")
		local deadline = os.clock() + 20
		while player:GetAttribute(attribute) == nil and os.clock() < deadline do
			task.wait(0.25)
		end
		local done = player:GetAttribute(attribute)
		if type(done) == "number" and done >= 1 then
			return
		end
		task.wait(2) -- let the loading screen go away first
		run()
	end)
end

return Tutorial
