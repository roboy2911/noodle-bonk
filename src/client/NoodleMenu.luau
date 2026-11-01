--!strict
-- Noodle picker. A button on the left side of the screen (or the N key)
-- opens a grid of every noodle with its stats. Clicking a card asks the
-- server to switch, and the card for your current noodle is highlighted.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)

type NoodleDef = Noodles.NoodleDef

local TOGGLE_ACTION = "ToggleNoodleMenu"

local PANEL_COLOR = Color3.fromRGB(22, 28, 44)
local CARD_COLOR = Color3.fromRGB(36, 44, 66)
local TRACK_COLOR = Color3.fromRGB(16, 20, 32)
local TEXT_COLOR = Color3.new(1, 1, 1)
local SUBTEXT_COLOR = Color3.fromRGB(180, 190, 210)
local EQUIPPED_COLOR = Color3.fromRGB(90, 230, 130)
local BUTTON_COLOR = Color3.fromRGB(255, 105, 180)

local player = Players.LocalPlayer

local NoodleMenu = {}

type Card = { stroke: UIStroke, status: TextLabel }

local panel: Frame
local panelScale: UIScale
local cards: { [string]: Card } = {}
local isOpen = false

-- Helpers ----------------------------------------------------------------

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- Noodles sorted with the default first, then alphabetically.
local function sortedNoodles(): { NoodleDef }
	local list = {}
	for _, def in Noodles do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		if a.Id == Config.DefaultNoodle then
			return true
		elseif b.Id == Config.DefaultNoodle then
			return false
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

-- Stats are shown relative to the best noodle in each category.
local function statMaxes(): (number, number, number)
	local maxPower, fastestCooldown, maxReach = 0, math.huge, 0
	for _, def in Noodles do
		maxPower = math.max(maxPower, def.Knockback)
		fastestCooldown = math.min(fastestCooldown, def.Cooldown)
		maxReach = math.max(maxReach, def.Range)
	end
	return maxPower, fastestCooldown, maxReach
end

-- UI -----------------------------------------------------------------------

local function statBar(parent: Instance, name: string, fraction: number, color: Color3, order: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 14)
	row.LayoutOrder = order
	row.Parent = parent

	local text = label(row, name, Enum.Font.GothamBold, 12, SUBTEXT_COLOR)
	text.Size = UDim2.new(0, 52, 1, 0)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 56, 0.5, 0)
	track.Size = UDim2.new(1, -56, 0, 8)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0.08, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)
end

local function buildCard(parent: Instance, def: NoodleDef, order: number, maxes: { number })
	local card = Instance.new("TextButton")
	card.Name = def.Id
	card.Text = ""
	card.AutoButtonColor = false
	card.BackgroundColor3 = CARD_COLOR
	card.LayoutOrder = order
	card.Parent = parent
	corner(card, 12)

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = EQUIPPED_COLOR
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = card

	-- A stripe in the noodle's color stands in for a preview
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(1, 0, 0, 12)
	swatch.BackgroundColor3 = def.Color
	swatch.BorderSizePixel = 0
	swatch.LayoutOrder = 1
	swatch.Parent = card
	corner(swatch, 6)

	label(card, def.DisplayName, Enum.Font.FredokaOne, 20, TEXT_COLOR).LayoutOrder = 2

	local desc = label(card, def.Description, Enum.Font.Gotham, 12, SUBTEXT_COLOR)
	desc.Size = UDim2.new(1, 0, 0, 30)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.LayoutOrder = 3

	local maxPower, fastestCooldown, maxReach = maxes[1], maxes[2], maxes[3]
	statBar(card, "Power", def.Knockback / maxPower, Color3.fromRGB(255, 110, 110), 4)
	statBar(card, "Speed", fastestCooldown / def.Cooldown, Color3.fromRGB(255, 220, 90), 5)
	statBar(card, "Reach", def.Range / maxReach, Color3.fromRGB(110, 190, 255), 6)

	local abilityText = if def.Ability then `Ability: {def.Ability} [E]` else "No ability"
	local ability = label(card, abilityText, Enum.Font.GothamBold, 12, if def.Ability then def.Color else SUBTEXT_COLOR)
	ability.LayoutOrder = 7

	local status = label(card, "EQUIPPED", Enum.Font.FredokaOne, 16, EQUIPPED_COLOR)
	status.LayoutOrder = 8
	status.Visible = false

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = CARD_COLOR:Lerp(def.Color, 0.15) }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = CARD_COLOR }):Play()
	end)
	card.Activated:Connect(function()
		Remotes.SelectNoodle:FireServer(def.Id)
		NoodleMenu.setOpen(false)
	end)

	cards[def.Id] = { stroke = stroke, status = status }
end

local function refreshEquipped()
	local current = player:GetAttribute("Noodle")
	for id, card in cards do
		local equipped = id == current
		card.stroke.Enabled = equipped
		card.status.Visible = equipped
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NoodleMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	-- Open button on the left edge
	local openButton = Instance.new("TextButton")
	openButton.AnchorPoint = Vector2.new(0, 0.5)
	openButton.Position = UDim2.new(0, 16, 0.5, 0)
	openButton.Size = UDim2.fromOffset(130, 46)
	openButton.BackgroundColor3 = BUTTON_COLOR
	openButton.Font = Enum.Font.FredokaOne
	openButton.TextSize = 22
	openButton.TextColor3 = TEXT_COLOR
	openButton.Text = "NOODLES"
	openButton.Parent = gui
	corner(openButton, 12)
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Thickness = 3
	buttonStroke.Color = Color3.new(1, 1, 1)
	buttonStroke.Parent = openButton
	openButton.Activated:Connect(function()
		NoodleMenu.setOpen(not isOpen)
	end)

	-- Main panel
	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.9, 0.85)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)

	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(760, 580)
	sizeLimit.Parent = panel

	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = label(panel, "PICK YOUR NOODLE", Enum.Font.FredokaOne, 30, TEXT_COLOR)
	title.Position = UDim2.fromOffset(20, 14)
	title.Size = UDim2.new(1, -80, 0, 36)

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Color3.fromRGB(230, 70, 80)
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 22
	close.TextColor3 = TEXT_COLOR
	close.Text = "X"
	close.Parent = panel
	corner(close, 10)
	close.Activated:Connect(function()
		NoodleMenu.setOpen(false)
	end)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Position = UDim2.fromOffset(16, 64)
	scroller.Size = UDim2.new(1, -32, 1, -80)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(220, 210)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = scroller

	local maxPower, fastestCooldown, maxReach = statMaxes()
	for i, def in sortedNoodles() do
		buildCard(scroller, def, i, { maxPower, fastestCooldown, maxReach })
	end

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Public -------------------------------------------------------------------

function NoodleMenu.setOpen(open: boolean)
	isOpen = open
	if open then
		refreshEquipped()
		panel.Visible = true
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	else
		panel.Visible = false
	end
end

function NoodleMenu.start()
	build()
	refreshEquipped()
	player:GetAttributeChangedSignal("Noodle"):Connect(refreshEquipped)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			NoodleMenu.setOpen(not isOpen)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonSelect)
end

return NoodleMenu
