--!strict
-- Noodle picker. A button on the left side of the screen (or the N key)
-- opens a grid of every noodle with its stats. Locked noodles show what it
-- takes to unlock them and how close you are. Clicking an unlocked card asks
-- the server to switch. A banner pops up whenever you unlock something new.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local BonkUI = require(script.Parent.BonkUI)
local Effects = require(script.Parent.Effects)
local CameraController = require(script.Parent.CameraController)

type NoodleDef = Noodles.NoodleDef

local TOGGLE_ACTION = "ToggleNoodleMenu"

local PANEL_COLOR = Color3.fromRGB(22, 28, 44)
local CARD_COLOR = Color3.fromRGB(36, 44, 66)
local LOCKED_CARD_COLOR = Color3.fromRGB(28, 32, 44)
local TRACK_COLOR = Color3.fromRGB(16, 20, 32)
local TEXT_COLOR = Color3.new(1, 1, 1)
local SUBTEXT_COLOR = Color3.fromRGB(180, 190, 210)
local LOCKED_TEXT_COLOR = Color3.fromRGB(150, 155, 170)
local EQUIPPED_COLOR = Color3.fromRGB(90, 230, 130)
local BUTTON_COLOR = Color3.fromRGB(255, 105, 180)

local player = Players.LocalPlayer

local NoodleMenu = {}

type Card = {
	def: NoodleDef,
	button: TextButton,
	stroke: UIStroke,
	status: TextLabel,
	progressTrack: Frame,
	progressFill: Frame,
	locked: boolean,
}

local panel: Frame
local panelScale: UIScale
local cards: { [string]: Card } = {}
local isOpen = false
local knownUnlocked: { [string]: boolean }? = nil -- nil until saved data has loaded

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

local function bar(parent: Instance, color: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 4)
	return track, fill
end

-- Free noodles first, then by how hard they are to unlock.
local function sortedNoodles(): { NoodleDef }
	local list = {}
	for _, def in Noodles do
		table.insert(list, def)
	end
	local function rank(def: NoodleDef): number
		if def.Id == Config.DefaultNoodle then
			return -1
		end
		return if def.Unlock then def.Unlock.Amount else 0
	end
	table.sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

type StatRanges = { maxPower: number, maxReach: number, minStiffness: number }

local function statRanges(): StatRanges
	local ranges = { maxPower = 0, maxReach = 0, minStiffness = math.huge }
	for _, def in Noodles do
		ranges.maxPower = math.max(ranges.maxPower, def.Knockback)
		ranges.maxReach = math.max(ranges.maxReach, def.Length)
		ranges.minStiffness = math.min(ranges.minStiffness, def.Stiffness)
	end
	return ranges
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

	local track, fill = bar(row, color)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 56, 0.5, 0)
	track.Size = UDim2.new(1, -56, 0, 8)
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0.08, 1), 1)
end

local function buildCard(parent: Instance, def: NoodleDef, order: number, ranges: StatRanges)
	local button = Instance.new("TextButton")
	button.Name = def.Id
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = CARD_COLOR
	button.LayoutOrder = order
	button.Parent = parent
	corner(button, 12)

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = EQUIPPED_COLOR
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = button

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = button

	-- A stripe in the noodle's color stands in for a preview
	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(1, 0, 0, 12)
	swatch.BackgroundColor3 = def.Color
	swatch.BorderSizePixel = 0
	swatch.LayoutOrder = 1
	swatch.Parent = button
	corner(swatch, 6)

	label(button, def.DisplayName, Enum.Font.LuckiestGuy, 20, TEXT_COLOR).LayoutOrder = 2

	local desc = label(button, def.Description, Enum.Font.Gotham, 12, SUBTEXT_COLOR)
	desc.Size = UDim2.new(1, 0, 0, 30)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.LayoutOrder = 3

	statBar(button, "Power", def.Knockback / ranges.maxPower, Color3.fromRGB(255, 110, 110), 4)
	statBar(button, "Reach", def.Length / ranges.maxReach, Color3.fromRGB(110, 190, 255), 5)
	statBar(button, "Flop", ranges.minStiffness / def.Stiffness, Color3.fromRGB(255, 220, 90), 6)

	local status = label(button, "", Enum.Font.GothamBold, 12, SUBTEXT_COLOR)
	status.TextWrapped = true
	status.Size = UDim2.new(1, 0, 0, 28)
	status.LayoutOrder = 7

	local progressTrack, progressFill = bar(button, def.Color)
	progressTrack.Size = UDim2.new(1, 0, 0, 6)
	progressTrack.LayoutOrder = 8

	local card: Card = {
		def = def,
		button = button,
		stroke = stroke,
		status = status,
		progressTrack = progressTrack,
		progressFill = progressFill,
		locked = false,
	}
	cards[def.Id] = card

	button.MouseEnter:Connect(function()
		local base = if card.locked then LOCKED_CARD_COLOR else CARD_COLOR
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = base:Lerp(def.Color, 0.15) }):Play()
	end)
	button.MouseLeave:Connect(function()
		local base = if card.locked then LOCKED_CARD_COLOR else CARD_COLOR
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = base }):Play()
	end)
	button.Activated:Connect(function()
		if card.locked then
			-- Little wiggle to say "not yet"
			button.Rotation = 3
			TweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
			return
		end
		Effects.playSound("Click")
		Remotes.SelectNoodle:FireServer(def.Id)
		NoodleMenu.setOpen(false)
	end)
end

local function refresh()
	local stats = Unlocks.readStats(player)
	local current = player:GetAttribute("Noodle")
	for id, card in cards do
		local unlocked = Unlocks.isAvailable(player, card.def)
		local equipped = unlocked and id == current
		card.locked = not unlocked
		card.button.BackgroundColor3 = if unlocked then CARD_COLOR else LOCKED_CARD_COLOR
		card.stroke.Enabled = equipped
		card.progressTrack.Visible = not unlocked
		card.progressFill.Size = UDim2.fromScale(Unlocks.progress(card.def, stats), 1)

		if equipped then
			card.status.Text = "EQUIPPED"
			card.status.TextColor3 = EQUIPPED_COLOR
		elseif unlocked then
			card.status.Text = if card.def.Ability then `Ability: {card.def.Ability} [E]` else "Click to equip"
			card.status.TextColor3 = SUBTEXT_COLOR
		else
			card.status.Text = `LOCKED: {Unlocks.describe(card.def, stats)}`
			card.status.TextColor3 = LOCKED_TEXT_COLOR
		end
	end
end

-- Pops a banner for anything that just became unlocked.
local function checkNewUnlocks()
	if not player:GetAttribute("DataLoaded") then
		return
	end
	local stats = Unlocks.readStats(player)
	local nowUnlocked: { [string]: boolean } = {}
	for id, def in Noodles do
		nowUnlocked[id] = Unlocks.isUnlocked(def, stats)
	end

	local known = knownUnlocked
	if known then
		for id, unlocked in nowUnlocked do
			if unlocked and not known[id] then
				Effects.playSound("Unlock")
				BonkUI.showBanner(`UNLOCKED: {Noodles[id].DisplayName}!`, Noodles[id].Color)
			end
		end
	end
	-- The first check after loading just records what they already had
	knownUnlocked = nowUnlocked
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
	openButton.Font = Enum.Font.LuckiestGuy
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
	sizeLimit.MaxSize = Vector2.new(760, 600)
	sizeLimit.Parent = panel

	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local title = label(panel, "PICK YOUR NOODLE", Enum.Font.LuckiestGuy, 30, TEXT_COLOR)
	title.Position = UDim2.fromOffset(20, 14)
	title.Size = UDim2.new(1, -80, 0, 36)

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Color3.fromRGB(230, 70, 80)
	close.Font = Enum.Font.LuckiestGuy
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
	grid.CellSize = UDim2.fromOffset(220, 236)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = scroller

	local ranges = statRanges()
	for i, def in sortedNoodles() do
		buildCard(scroller, def, i, ranges)
	end

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Public -------------------------------------------------------------------

function NoodleMenu.setOpen(open: boolean)
	if open ~= isOpen then
		Effects.playSound("Click")
	end
	isOpen = open
	CameraController.setCursorFree("NoodleMenu", open)
	if open then
		refresh()
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
	refresh()
	checkNewUnlocks()

	-- Stats, admin grants, the equipped noodle and data loading all change attributes
	player.AttributeChanged:Connect(function(name)
		if name == "DataLoaded" or string.sub(name, 1, 5) == "Stat_" then
			checkNewUnlocks()
		end
		refresh()
	end)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			NoodleMenu.setOpen(not isOpen)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.N, Enum.KeyCode.ButtonSelect)
end

return NoodleMenu
