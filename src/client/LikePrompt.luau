--!strict
-- After a few minutes of play, asks once per session for a Like and a
-- Favorite. Roblox doesn't let games like themselves, so this is only a
-- friendly reminder, but likes and favorites are a big part of how Roblox
-- decides which games to recommend.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Effects = require(script.Parent.Effects)
local Tutorial = require(script.Parent.Tutorial)

local player = Players.LocalPlayer

local SHOW_AFTER = 5 * 60 -- seconds of play this session
local GOLD = Color3.fromRGB(255, 215, 40)

local LikePrompt = {}

local function show()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LikePrompt"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, 200) -- slides up from below
	panel.Size = UDim2.new(0.9, 0, 0, 130)
	panel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(460, 130)
	sizeLimit.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.TextColor3 = GOLD
	title.Text = "HAVING FUN? 👍 ⭐"
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Position = UDim2.fromOffset(16, 46)
	body.Size = UDim2.new(1, -32, 0, 40)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 16
	body.TextWrapped = true
	body.TextColor3 = Color3.new(1, 1, 1)
	body.Text = "Like and Favorite Noodle Bonk on the game page to get new noodles and bosses sooner!"
	body.Parent = panel

	local ok = Instance.new("TextButton")
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -10)
	ok.Size = UDim2.fromOffset(140, 30)
	ok.BackgroundColor3 = Color3.fromRGB(60, 170, 100)
	ok.Font = Enum.Font.GothamBold
	ok.TextSize = 16
	ok.TextColor3 = Color3.new(1, 1, 1)
	ok.Text = "Will do! 👍"
	ok.Parent = panel
	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 8)
	okCorner.Parent = ok

	gui.Parent = player:WaitForChild("PlayerGui")
	Effects.playSound("Unlock")
	TweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 1, -24),
	}):Play()

	local function close()
		if gui.Parent then
			gui:Destroy()
		end
	end
	ok.Activated:Connect(close)
	task.delay(20, close) -- goes away by itself too
end

function LikePrompt.start()
	task.spawn(function()
		task.wait(SHOW_AFTER)
		-- Don't stack on top of the tutorial
		while Tutorial.isActive() do
			task.wait(5)
		end
		show()
	end)
end

return LikePrompt
