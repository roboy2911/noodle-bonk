--!strict
-- On-screen info: the ability cooldown bar, Soak % over everyone's heads,
-- and a short controls hint.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local NoodleController = require(script.Parent.NoodleController)
local Vanish = require(script.Parent.Vanish)

local READY_COLOR = Color3.fromRGB(90, 230, 130)
local CHARGING_COLOR = Color3.fromRGB(110, 140, 190)
local DRY_COLOR = Color3.new(1, 1, 1)
local SOAKED_COLOR = Color3.fromRGB(40, 110, 255)
local SOAK_REFRESH = 0.15

local player = Players.LocalPlayer

local Hud = {}

type SoakTag = { gui: BillboardGui, label: TextLabel }

local abilityFrame: Frame
local abilityFill: Frame
local abilityLabel: TextLabel
local soakFolder: Folder
local soakTags: { [Model]: SoakTag } = {}
local sinceSoakRefresh = 0

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false

	-- Ability cooldown bar, bottom center
	abilityFrame = Instance.new("Frame")
	abilityFrame.AnchorPoint = Vector2.new(0.5, 1)
	abilityFrame.Position = UDim2.new(0.5, 0, 1, -24)
	abilityFrame.Size = UDim2.fromOffset(240, 34)
	abilityFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
	abilityFrame.BackgroundTransparency = 0.25
	abilityFrame.Visible = false
	abilityFrame.Parent = gui
	corner(abilityFrame, 10)

	abilityFill = Instance.new("Frame")
	abilityFill.BorderSizePixel = 0
	abilityFill.Size = UDim2.fromScale(0, 1)
	abilityFill.Parent = abilityFrame
	corner(abilityFill, 10)

	abilityLabel = Instance.new("TextLabel")
	abilityLabel.Size = UDim2.fromScale(1, 1)
	abilityLabel.BackgroundTransparency = 1
	abilityLabel.Font = Enum.Font.LuckiestGuy
	abilityLabel.TextSize = 18
	abilityLabel.TextColor3 = Color3.new(1, 1, 1)
	abilityLabel.ZIndex = 2
	abilityLabel.Parent = abilityFrame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = abilityLabel

	-- Controls hint, bottom left
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 16, 1, -16)
	hint.Size = UDim2.fromOffset(480, 20)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 14
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextTransparency = 0.2
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = if touchOnly
		then "Drag to turn and swing your noodle"
		else "Turn fast to swing  •  Ctrl: free mouse  •  N: noodles  •  M: music"
	hint.Parent = gui
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 1.5
	hintStroke.Transparency = 0.3
	hintStroke.Parent = hint

	gui.Parent = player:WaitForChild("PlayerGui")

	soakFolder = Instance.new("Folder")
	soakFolder.Name = "SoakTags"
	soakFolder.Parent = player:WaitForChild("PlayerGui")
end

local function updateAbility()
	local name, ready = NoodleController.getAbilityState()
	abilityFrame.Visible = name ~= nil
	if not name then
		return
	end
	abilityFill.Size = UDim2.fromScale(ready, 1)
	abilityFill.BackgroundColor3 = if ready >= 1 then READY_COLOR else CHARGING_COLOR
	abilityLabel.Text = if ready >= 1 then `{string.upper(name)} READY [E]` else string.upper(name)
end

local function makeSoakTag(head: BasePart): SoakTag
	local gui = Instance.new("BillboardGui")
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(80, 30)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = soakFolder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label

	return { gui = gui, label = label }
end

-- Shows each soaked character's Soak % over their head, bluer the wetter they are.
local function updateSoakTags()
	local characters: { Model } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(characters, other.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") then
			table.insert(characters, dummy)
		end
	end

	local seen: { [Model]: boolean } = {}
	for _, character in characters do
		local soak = character:GetAttribute("Soak")
		local head = character:FindFirstChild("Head")
		local vanished = character ~= player.Character and Vanish.isVanished(character)
		if type(soak) == "number" and soak >= 1 and head and head:IsA("BasePart") and not vanished then
			seen[character] = true
			local tag = soakTags[character]
			if not tag then
				tag = makeSoakTag(head)
				soakTags[character] = tag
			end
			tag.gui.Adornee = head
			tag.label.Text = `{math.floor(soak)}%`
			tag.label.TextColor3 = DRY_COLOR:Lerp(SOAKED_COLOR, math.clamp(soak / Config.MaxSoak, 0, 1))
		end
	end

	for character, tag in soakTags do
		if not seen[character] then
			tag.gui:Destroy()
			soakTags[character] = nil
		end
	end
end

function Hud.start()
	build()
	RunService.RenderStepped:Connect(function(dt)
		updateAbility()
		sinceSoakRefresh += dt
		if sinceSoakRefresh >= SOAK_REFRESH then
			sinceSoakRefresh = 0
			updateSoakTags()
		end
	end)
end

return Hud
