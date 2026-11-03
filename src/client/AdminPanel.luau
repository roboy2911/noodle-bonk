--!strict
-- Admin panel. Open it with the ADMIN button or the P key. It only appears
-- for admins (the server sets the IsAdmin attribute), and the server checks
-- every command again, so hiding it is just tidiness, not security.
--
-- Pick a player on the left (you're selected by default), then use the tabs:
--   Player:  give noodles, edit stats, moderation, teleports, fun
--   Testing: unlock all, god mode, fly, noclip, no cooldown, walk speed, clip mode
--   Server:  dummies, announcements, events, shutdown

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local CameraController = require(script.Parent.CameraController)
local ClipMode = require(script.Parent.ClipMode)
local Effects = require(script.Parent.Effects)

local TOGGLE_ACTION = "ToggleAdminPanel"
local PANEL_SIZE = Vector2.new(660, 500)
local LIST_WIDTH = 170
local BUTTON_WIDTH = 140
local CONFIRM_TIME = 3

local PANEL_COLOR = Color3.fromRGB(22, 26, 38)
local SECTION_COLOR = Color3.fromRGB(30, 36, 52)
local BUTTON_COLOR = Color3.fromRGB(56, 66, 96)
local DANGER_COLOR = Color3.fromRGB(200, 60, 70)
local GOOD_COLOR = Color3.fromRGB(60, 170, 100)
local TOGGLE_ON_COLOR = Color3.fromRGB(60, 170, 100)
local SELECTED_COLOR = Color3.fromRGB(255, 105, 180)
local TEXT_COLOR = Color3.new(1, 1, 1)
local SUBTEXT_COLOR = Color3.fromRGB(170, 180, 200)
local STATUS_OK = Color3.fromRGB(120, 230, 150)
local STATUS_BAD = Color3.fromRGB(255, 120, 120)

local player = Players.LocalPlayer

local AdminPanel = {}

type Toggle = {
	button: TextButton,
	label: string,
	isOn: () -> boolean,
}

local panel: Frame
local panelScale: UIScale
local statusLabel: TextLabel
local targetLabel: TextLabel
local playerList: ScrollingFrame
local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local toggles: { Toggle } = {}
local selected: Player = player
local isOpen = false
local built = false

-- Small UI helpers --------------------------------------------------------------

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function setStatus(text: string, color: Color3)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
end

local function makeButton(parent: Instance, text: string, color: Color3?, width: number?): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width or BUTTON_WIDTH, 32)
	button.BackgroundColor3 = color or BUTTON_COLOR
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = TEXT_COLOR
	button.TextWrapped = true
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	corner(button, 8)
	button.Activated:Connect(function()
		Effects.playSound("Click")
	end)
	return button
end

local function makeBox(parent: Instance, placeholder: string, width: number?): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(width or BUTTON_WIDTH, 32)
	box.BackgroundColor3 = Color3.fromRGB(14, 17, 26)
	box.Font = Enum.Font.Gotham
	box.TextSize = 13
	box.TextColor3 = TEXT_COLOR
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = SUBTEXT_COLOR
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = parent
	corner(box, 8)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = box
	return box
end

local function header(page: ScrollingFrame, text: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -8, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextSize = 17
	label.TextColor3 = SELECTED_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = #page:GetChildren()
	label.Parent = page
end

local function note(page: ScrollingFrame, text: string)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -8, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextColor3 = SUBTEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = #page:GetChildren()
	label.Parent = page
end

-- A horizontal row that wraps its buttons onto new lines.
local function row(page: ScrollingFrame): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -8, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = #page:GetChildren()
	frame.Parent = page

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Wraps = true
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- Sends a command to the server and shows the result in the status line.
local function send(command: string, args: { [string]: any }?)
	local payload: { [string]: any } = args or {}
	if payload.target == nil then
		payload.target = selected
	end
	setStatus("Working...", SUBTEXT_COLOR)
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Remotes.AdminRequest:InvokeServer(command, payload)
		end)
		if not ok then
			setStatus(`Request failed: {success}`, STATUS_BAD)
		else
			setStatus(tostring(message), if success then STATUS_OK else STATUS_BAD)
		end
	end)
end

-- A button that needs a second click within a few seconds, for risky actions.
local function confirmButton(parent: Instance, text: string, onConfirm: () -> (), color: Color3?)
	local button = makeButton(parent, text, color or DANGER_COLOR)
	local armedUntil = 0
	button.Activated:Connect(function()
		if os.clock() < armedUntil then
			armedUntil = 0
			button.Text = text
			onConfirm()
			return
		end
		armedUntil = os.clock() + CONFIRM_TIME
		button.Text = "Sure? Click again"
		task.delay(CONFIRM_TIME, function()
			if os.clock() >= armedUntil then
				button.Text = text
			end
		end)
	end)
end

local function toggleButton(parent: Instance, label: string, command: string, isOn: () -> boolean)
	local button = makeButton(parent, label)
	button.Activated:Connect(function()
		send(command)
	end)
	table.insert(toggles, { button = button, label = label, isOn = isOn })
end

local function refreshToggles()
	for _, toggle in toggles do
		local on = toggle.isOn()
		toggle.button.Text = `{toggle.label}: {if on then "ON" else "OFF"}`
		toggle.button.BackgroundColor3 = if on then TOGGLE_ON_COLOR else BUTTON_COLOR
	end
end

local function attributeOn(name: string): () -> boolean
	return function()
		return selected.Parent ~= nil and selected:GetAttribute(name) == true
	end
end

-- Player list ---------------------------------------------------------------

local function refreshPlayerList()
	for _, child in playerList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	if not selected.Parent then
		selected = player
	end

	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		if a == player then
			return true
		elseif b == player then
			return false
		end
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)

	for i, other in list do
		local text = if other == player then `{other.DisplayName} (you)` else other.DisplayName
		local button = makeButton(playerList, text, if other == selected then SELECTED_COLOR else BUTTON_COLOR, LIST_WIDTH - 20)
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.LayoutOrder = i
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.Parent = button
		button.Activated:Connect(function()
			selected = other
			refreshPlayerList()
		end)
	end

	targetLabel.Text = `Target: {selected.DisplayName} (@{selected.Name})`
	refreshToggles()
end

-- Pages ------------------------------------------------------------------------

local function makePage(parent: Instance, name: string): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = name
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	pages[name] = page
	return page
end

local function buildPlayerPage(page: ScrollingFrame)
	header(page, "Give noodle")
	note(page, "Works even if it's locked. Lasts until they leave.")
	local noodleRow = row(page)
	local defs = {}
	for _, def in Noodles do
		table.insert(defs, def)
	end
	table.sort(defs, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	for _, def in defs do
		local button = makeButton(noodleRow, def.DisplayName, def.Color:Lerp(Color3.new(0, 0, 0), 0.35), 100)
		button.Activated:Connect(function()
			send("GiveNoodle", { noodleId = def.Id })
		end)
	end

	header(page, "Stats (saved)")
	local statRow = row(page)
	-- One button cycles through every stat; Set / Add use the one shown
	local statIndex = 1
	local statButton = makeButton(statRow, `Stat: {Unlocks.STATS[1]} ▸`, nil, 220)
	statButton.Activated:Connect(function()
		statIndex = statIndex % #Unlocks.STATS + 1
		statButton.Text = `Stat: {Unlocks.STATS[statIndex]} ▸`
	end)
	local amountBox = makeBox(statRow, "Amount", 90)
	makeButton(statRow, "Set", nil, 70).Activated:Connect(function()
		send("SetStat", { stat = Unlocks.STATS[statIndex], value = amountBox.Text })
	end)
	makeButton(statRow, "Add", nil, 70).Activated:Connect(function()
		send("AddStat", { stat = Unlocks.STATS[statIndex], value = amountBox.Text })
	end)
	note(page, "Click the stat button to pick which stat. Times are in seconds (PlayTime, LongestSurvival).")
	local resetRow = row(page)
	confirmButton(resetRow, "Reset ALL data", function()
		send("ResetData")
	end)

	header(page, "Moderation")
	local reasonRow = row(page)
	local reasonBox = makeBox(reasonRow, "Reason (shown to them)", 290)
	local modRow = row(page)
	confirmButton(modRow, "Kick", function()
		send("Kick", { reason = reasonBox.Text })
	end)
	confirmButton(modRow, "Ban 1 day", function()
		send("Ban", { reason = reasonBox.Text, hours = 24 })
	end)
	confirmButton(modRow, "Ban forever", function()
		send("Ban", { reason = reasonBox.Text, hours = 0 })
	end)
	local unbanRow = row(page)
	local unbanBox = makeBox(unbanRow, "Username or UserId", 200)
	makeButton(unbanRow, "Unban", GOOD_COLOR, 90).Activated:Connect(function()
		send("Unban", { user = unbanBox.Text })
	end)

	header(page, "Move & mess with them")
	local moveRow = row(page)
	for _, item in {
		{ "Go to them", "GoTo" },
		{ "Bring to me", "Bring" },
		{ "Reset character", "Kill" },
		{ "Launch", "Launch" },
		{ "Max Soak", "MaxSoak" },
		{ "Dry off", "Dry" },
	} do
		makeButton(moveRow, item[1]).Activated:Connect(function()
			send(item[2])
		end)
	end
end

local function buildTestingPage(page: ScrollingFrame)
	header(page, "Toggles")
	note(page, "These apply to the selected player. Pick yourself to test.")
	local toggleRow = row(page)
	toggleButton(toggleRow, "Unlock all", "ToggleUnlockAll", attributeOn("AllUnlocked"))
	toggleButton(toggleRow, "God mode", "ToggleGod", attributeOn("AdminGod"))
	toggleButton(toggleRow, "Fly", "ToggleFly", attributeOn("AdminFly"))
	toggleButton(toggleRow, "Noclip", "ToggleNoclip", attributeOn("AdminNoclip"))
	toggleButton(toggleRow, "No ability cooldown", "ToggleNoCooldown", attributeOn("AdminNoCooldown"))
	note(page, "God mode: can't be hit, and falling off puts you back on the deck. Fly: Space up, Q down.")

	header(page, "Walk speed")
	local speedRow = row(page)
	local speedBox = makeBox(speedRow, "Speed (0 = normal)", 150)
	makeButton(speedRow, "Set speed").Activated:Connect(function()
		send("SetWalkSpeed", { value = speedBox.Text })
	end)

	header(page, "Recording")
	note(
		page,
		"Clip mode: hides all UI, smooth cinematic camera, and logs big moments. Start recording first, then press K (or this button). Press K again to stop and see the highlight list."
	)
	local clipRow = row(page)
	makeButton(clipRow, "Start clip mode (K)", GOOD_COLOR, 190).Activated:Connect(function()
		AdminPanel.setOpen(false)
		ClipMode.setEnabled(true)
	end)
end

local function buildServerPage(page: ScrollingFrame)
	header(page, "Dummies")
	local dummyRow = row(page)
	local countBox = makeBox(dummyRow, "How many (1-20)", 130)
	makeButton(dummyRow, "Spawn dummies").Activated:Connect(function()
		send("SpawnDummies", { value = countBox.Text })
	end)
	makeButton(dummyRow, "Clear dummies").Activated:Connect(function()
		send("ClearDummies")
	end)
	toggleButton(dummyRow, "Dummies fight", "ToggleDummyFight", function()
		return workspace:GetAttribute("DummyFight") == true
	end)
	note(page, "Dummies fight: they grab noodles and chase the nearest player. Only this server.")

	header(page, "Duck jar (this server)")
	note(page, "Every bonk adds a duck. A full jar summons the Giant Duck boss.")
	local duckRow = row(page)
	local duckBox = makeBox(duckRow, "Ducks", 110)
	makeButton(duckRow, "Set ducks").Activated:Connect(function()
		send("SetDucks", { value = duckBox.Text })
	end)
	makeButton(duckRow, "Spawn Giant Duck", Color3.fromRGB(230, 180, 30), 160).Activated:Connect(function()
		send("SpawnDuckBoss")
	end)
	makeButton(duckRow, "Remove Giant Duck").Activated:Connect(function()
		send("RemoveDuckBoss")
	end)

	header(page, "Announcement")
	note(page, "Shows a big banner for everyone in every server. Goes through Roblox's text filter.")
	local announceRow = row(page)
	local messageBox = makeBox(announceRow, "Message", 300)
	makeButton(announceRow, "Send", GOOD_COLOR, 90).Activated:Connect(function()
		send("Announce", { text = messageBox.Text })
		messageBox.Text = ""
	end)

	header(page, "Events")
	local eventRow = row(page)
	makeButton(eventRow, "Soak storm").Activated:Connect(function()
		send("SoakStorm")
	end)
	makeButton(eventRow, "Dry everyone").Activated:Connect(function()
		send("DryAll")
	end)
	toggleButton(eventRow, "Low gravity", "ToggleLowGravity", function()
		return workspace:GetAttribute("LowGravity") == true
	end)
	makeButton(eventRow, "Launch everyone").Activated:Connect(function()
		send("LaunchAll")
	end)
	makeButton(eventRow, "Pool Party (all servers)", Color3.fromRGB(255, 105, 180)).Activated:Connect(function()
		send("StartPoolParty")
	end)
	confirmButton(eventRow, "Respawn everyone", function()
		send("ResetEveryone")
	end, BUTTON_COLOR)

	header(page, "Danger zone")
	local dangerRow = row(page)
	confirmButton(dangerRow, "Shut down server", function()
		send("Shutdown")
	end)
end

local function showTab(name: string)
	for pageName, page in pages do
		page.Visible = pageName == name
		tabButtons[pageName].BackgroundColor3 = if pageName == name then SELECTED_COLOR else BUTTON_COLOR
	end
end

-- Build ------------------------------------------------------------------------

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10

	local openButton = makeButton(gui, "ADMIN", DANGER_COLOR, 130)
	openButton.AnchorPoint = Vector2.new(0, 0.5)
	openButton.Position = UDim2.new(0, 16, 0.5, 46)
	openButton.Font = Enum.Font.LuckiestGuy
	openButton.TextSize = 18
	openButton.Activated:Connect(function()
		AdminPanel.setOpen(not isOpen)
	end)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)

	-- Shrink to fit small screens
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			panelScale.Scale = math.min(1, (view.X - 20) / PANEL_SIZE.X, (view.Y - 20) / PANEL_SIZE.Y)
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.fromOffset(200, 30)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextSize = 26
	title.TextColor3 = TEXT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ADMIN PANEL"
	title.Parent = panel

	local close = makeButton(panel, "X", DANGER_COLOR, 32)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Activated:Connect(function()
		AdminPanel.setOpen(false)
	end)

	-- Player list on the left
	local listSection = Instance.new("Frame")
	listSection.Position = UDim2.fromOffset(12, 50)
	listSection.Size = UDim2.new(0, LIST_WIDTH, 1, -92)
	listSection.BackgroundColor3 = SECTION_COLOR
	listSection.Parent = panel
	corner(listSection, 10)

	local listTitle = Instance.new("TextLabel")
	listTitle.Position = UDim2.fromOffset(10, 6)
	listTitle.Size = UDim2.new(1, -20, 0, 20)
	listTitle.BackgroundTransparency = 1
	listTitle.Font = Enum.Font.GothamBold
	listTitle.TextSize = 13
	listTitle.TextColor3 = SUBTEXT_COLOR
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.Text = "PLAYERS"
	listTitle.Parent = listSection

	playerList = Instance.new("ScrollingFrame")
	playerList.Position = UDim2.fromOffset(10, 30)
	playerList.Size = UDim2.new(1, -14, 1, -38)
	playerList.BackgroundTransparency = 1
	playerList.BorderSizePixel = 0
	playerList.ScrollBarThickness = 4
	playerList.CanvasSize = UDim2.new()
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.Parent = listSection
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = playerList

	-- Tabs + content on the right
	local rightX = LIST_WIDTH + 24
	targetLabel = Instance.new("TextLabel")
	targetLabel.Position = UDim2.fromOffset(rightX, 50)
	targetLabel.Size = UDim2.new(1, -rightX - 12, 0, 20)
	targetLabel.BackgroundTransparency = 1
	targetLabel.Font = Enum.Font.GothamBold
	targetLabel.TextSize = 14
	targetLabel.TextColor3 = TEXT_COLOR
	targetLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetLabel.Parent = panel

	local tabBar = Instance.new("Frame")
	tabBar.Position = UDim2.fromOffset(rightX, 74)
	tabBar.Size = UDim2.new(1, -rightX - 12, 0, 32)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	local content = Instance.new("Frame")
	content.Position = UDim2.fromOffset(rightX, 114)
	content.Size = UDim2.new(1, -rightX - 12, 1, -156)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local tabs: { { name: string, build: (ScrollingFrame) -> () } } = {
		{ name = "Player", build = buildPlayerPage },
		{ name = "Testing", build = buildTestingPage },
		{ name = "Server", build = buildServerPage },
	}
	for i, tab in tabs do
		local name = tab.name
		local button = makeButton(tabBar, name, nil, 110)
		button.LayoutOrder = i
		button.Activated:Connect(function()
			showTab(name)
		end)
		tabButtons[name] = button
		tab.build(makePage(content, name))
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.new(0, 16, 1, -10)
	statusLabel.Size = UDim2.new(1, -32, 0, 22)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 14
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Parent = panel
	setStatus("Pick a player, then a command.", SUBTEXT_COLOR)

	showTab("Player")
	gui.Parent = player:WaitForChild("PlayerGui")
	refreshPlayerList()

	Players.PlayerAdded:Connect(refreshPlayerList)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayerList)
	end)

	-- Keep toggle buttons in sync while the panel is open
	task.spawn(function()
		while true do
			task.wait(0.25)
			if isOpen then
				refreshToggles()
			end
		end
	end)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			AdminPanel.setOpen(not isOpen)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.P)

	built = true
end

-- Public -----------------------------------------------------------------------

function AdminPanel.setOpen(open: boolean)
	if not built then
		return
	end
	isOpen = open
	CameraController.setCursorFree("AdminPanel", open)
	if open then
		refreshPlayerList()
		panel.Visible = true
		local base = panelScale.Scale
		panelScale.Scale = base * 0.9
		TweenService:Create(panelScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = base,
		}):Play()
	else
		panel.Visible = false
	end
end

function AdminPanel.start()
	if player:GetAttribute("IsAdmin") then
		build()
		return
	end
	-- The server marks admins shortly after they join
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		if player:GetAttribute("IsAdmin") and not built then
			connection:Disconnect()
			build()
		end
	end)
end

return AdminPanel
