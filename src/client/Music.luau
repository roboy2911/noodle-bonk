--!strict
-- Background music: shuffles through the tracks in Config.Music, one after
-- another. The MUSIC button in the bottom-right corner (or the M key) turns
-- it on and off.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Effects = require(script.Parent.Effects)

local TOGGLE_ACTION = "ToggleMusic"
local ON_COLOR = Color3.fromRGB(80, 200, 255)
local OFF_COLOR = Color3.fromRGB(70, 76, 96)

local player = Players.LocalPlayer

local Music = {}

local sound: Sound
local button: TextButton
local enabled = true
local playlist: { number } = {}
local position = 0

local function shuffled(): { number }
	local list = table.clone(Config.Music.Ids)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function playNext()
	if #Config.Music.Ids == 0 then
		return
	end
	if position >= #playlist then
		playlist = shuffled()
		position = 0
	end
	position += 1
	sound.SoundId = `rbxassetid://{playlist[position]}`
	sound.TimePosition = 0
	if enabled then
		sound:Play()
	end
end

function Music.setEnabled(on: boolean)
	enabled = on
	if on then
		if sound.TimePosition > 0 then
			sound:Resume()
		else
			sound:Play()
		end
	else
		sound:Pause()
	end
	button.Text = if on then "MUSIC: ON" else "MUSIC: OFF"
	button.BackgroundColor3 = if on then ON_COLOR else OFF_COLOR
end

function Music.start()
	sound = Instance.new("Sound")
	sound.Name = "NoodleMusic"
	sound.Volume = Config.Music.Volume
	sound.Parent = SoundService
	sound.Ended:Connect(playNext)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MusicButton"
	gui.ResetOnSpawn = false

	button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -16, 1, -16)
	button.Size = UDim2.fromOffset(120, 32)
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 16
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	button.Activated:Connect(function()
		Effects.playSound("Click")
		Music.setEnabled(not enabled)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Music.setEnabled(not enabled)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M)

	Music.setEnabled(true)
	playNext()
end

return Music
