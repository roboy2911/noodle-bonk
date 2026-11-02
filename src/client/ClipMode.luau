--!strict
-- Clip mode, for recording videos (admins only). Press K, or the button in
-- the admin panel's Testing tab, to switch it on and off.
--
-- While it's on:
--   * all screen UI is hidden (world effects like BONK! text, splashes and
--     the Soak % over heads stay)
--   * the camera view is pulled back, lowered and smoothed for nicer footage.
--     Only the picture changes: the real camera (which aims your swings) still
--     turns instantly, so fighting feels the same.
--   * big moments are logged with the time since clip mode started.
--
-- Clip mode starts with a short white flash, so the log can be lined up with
-- the recording. Start recording first, then press K. When you switch it off,
-- the highlight list pops up to copy (it's also printed in the F9 console).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer

local TOGGLE_ACTION = "ToggleClipMode"
local GUI_NAME = "ClipMode"

-- Camera look
local CAMERA_OFFSET = CFrame.new(0.6, -1.3, 5) * CFrame.Angles(math.rad(7), 0, 0) -- back, lower, tilted up
local CAMERA_SMOOTHING = 7 -- higher = follows tighter
local CLIP_FOV = 62

-- Highlights
local BIG_LAUNCH_SPEED = 75 -- studs/s; a hit that sends someone faster than this is a "big launch"
local NEARBY = 60 -- abilities further than this from you aren't logged
local REPEAT_GAP = 1.5 -- same moment within this many seconds is logged once

local ABILITY_NAMES: { [string]: string } = {
	Tentacle = "Kraken throw",
	Slam = "Pogo slam",
	Magnet = "Magnet pull",
	Tornado = "Tornado spin",
	Vanish = "Vanished",
}

type Highlight = { time: number, stars: number, text: string }

local ClipMode = {}

local enabled = false
local startedAt = 0
local highlights: { Highlight } = {}
local lastLogged: { [string]: number } = {}
local hiddenGuis: { [ScreenGui]: boolean } = {}
local normalFov = 70
local trueCFrame: CFrame? = nil
local smoothCFrame: CFrame? = nil

local gui: ScreenGui
local flash: Frame
local results: Frame
local resultsBox: TextBox

-- Highlight log ----------------------------------------------------------------

local function stamp(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%04.1f", minutes, seconds - minutes * 60)
end

local function log(stars: number, text: string)
	if not enabled then
		return
	end
	local now = os.clock()
	if now - (lastLogged[text] or -math.huge) < REPEAT_GAP then
		return
	end
	lastLogged[text] = now
	table.insert(highlights, { time = now - startedAt, stars = stars, text = text })
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The character (player or dummy) whose root is closest to `position`.
local function characterNear(position: Vector3): (Model?, BasePart?)
	local best, bestRoot, bestDistance = nil, nil, 8
	local candidates: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(candidates, other.Character)
		end
	end
	for _, dummy in game:GetService("CollectionService"):GetTagged(Config.DummyTag) do
		table.insert(candidates, dummy)
	end
	for _, model in candidates do
		local root = model:FindFirstChild("HumanoidRootPart")
		if model:IsA("Model") and root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestRoot, bestDistance = model, root, distance
			end
		end
	end
	return best, bestRoot
end

local function nameOf(model: Model): string
	local other = Players:GetPlayerFromCharacter(model)
	return if other then other.DisplayName else model.Name
end

local function onHit(position: Vector3, _noodleId: string, attacker: Player?)
	if not enabled or attacker ~= player then
		return
	end
	local target, root = characterNear(position)
	if not target or not root then
		return
	end
	-- Give the launch a moment to start, then see how fast they're flying
	task.delay(0.15, function()
		if root.Parent and root.AssemblyLinearVelocity.Magnitude >= BIG_LAUNCH_SPEED then
			log(2, `Big launch on {nameOf(target)}`)
		end
	end)
end

local function onBonked(info: { [string]: any })
	local attacker: Player? = info.attacker
	local victim: Player? = info.victim
	local byName: string? = if attacker then attacker.DisplayName else info.attackerName
	if attacker == player then
		log(2, `You bonked {info.victimName} into the pool`)
		if info.milestoneTitle and info.attackerStreak then
			log(3, `{info.milestoneTitle}! {info.attackerStreak} streak`)
		end
		if info.endedStreak then
			log(3, `Ended {info.victimName}'s {info.endedStreak} streak`)
		end
	elseif victim == player then
		log(2, if byName then `{byName} bonked you into the pool` else "You fell in the pool")
	end
end

local function onKnockback(knockback: Remotes.KnockbackInfo)
	if knockback.velocity.Magnitude >= BIG_LAUNCH_SPEED then
		log(2, "You got launched")
	end
end

local function onAbilityFx(kind: string, a: any, b: any)
	if kind ~= "Sound" or type(a) ~= "string" or not ABILITY_NAMES[a] then
		return
	end
	local root = myRoot()
	if typeof(b) == "Vector3" and root and (b - root.Position).Magnitude > NEARBY then
		return
	end
	log(1, ABILITY_NAMES[a])
end

local function highlightText(): string
	if #highlights == 0 then
		return "No highlights logged. Bonk someone while clip mode is on!"
	end
	local lines = { `Clip mode highlights (time since the white flash, {#highlights} moments):` }
	for _, item in highlights do
		table.insert(lines, `{stamp(item.time)}  {string.rep("*", item.stars)}  {item.text}`)
	end
	return table.concat(lines, "\n")
end

-- Hiding UI ----------------------------------------------------------------------

local function setCoreUi(on: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, on)
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", on)
	end)
end

-- Runs every frame while on, so UI that appears later (respawns) is hidden too.
local function hideScreenGuis()
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child.Name ~= GUI_NAME and child.Enabled then
			child.Enabled = false
			hiddenGuis[child] = true
		end
	end
end

local function showScreenGuis()
	for screenGui in hiddenGuis do
		if screenGui.Parent then
			screenGui.Enabled = true
		end
	end
	table.clear(hiddenGuis)
end

-- Camera ---------------------------------------------------------------------------

-- Before Roblox's camera runs: put back the real camera, so it keeps turning
-- from where it really is (not from our smoothed view).
local function restoreCamera()
	local camera = workspace.CurrentCamera
	if camera and trueCFrame then
		camera.CFrame = trueCFrame
	end
end

-- After everything else: remember the real camera, then show the cinematic view.
local function cinematicCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	trueCFrame = camera.CFrame
	local target = camera.CFrame * CAMERA_OFFSET
	if smoothCFrame then
		smoothCFrame = smoothCFrame:Lerp(target, 1 - math.exp(-CAMERA_SMOOTHING * dt))
	else
		smoothCFrame = target
	end
	camera.CFrame = smoothCFrame :: CFrame
	hideScreenGuis()
end

-- On and off --------------------------------------------------------------------------

local function showResults()
	resultsBox.Text = highlightText()
	results.Visible = true
	CameraController.setCursorFree("ClipResults", true)
end

local function hideResults()
	results.Visible = false
	CameraController.setCursorFree("ClipResults", false)
end

function ClipMode.isOn(): boolean
	return enabled
end

function ClipMode.setEnabled(on: boolean)
	if on == enabled or not player:GetAttribute("IsAdmin") then
		return
	end
	enabled = on
	local camera = workspace.CurrentCamera

	if on then
		hideResults()
		table.clear(highlights)
		table.clear(lastLogged)
		startedAt = os.clock()
		setCoreUi(false)
		hideScreenGuis()
		if camera then
			normalFov = camera.FieldOfView
			camera.FieldOfView = CLIP_FOV
		end
		trueCFrame, smoothCFrame = nil, nil
		RunService:BindToRenderStep("ClipModeRestore", Enum.RenderPriority.Camera.Value - 1, restoreCamera)
		RunService:BindToRenderStep("ClipModeCamera", Enum.RenderPriority.Last.Value, cinematicCamera)

		-- White flash: lines the highlight times up with the recording
		flash.BackgroundTransparency = 0
		flash.Visible = true
		task.delay(0.12, function()
			local fade = TweenService:Create(flash, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
			fade.Completed:Once(function()
				flash.Visible = false
			end)
			fade:Play()
		end)
	else
		RunService:UnbindFromRenderStep("ClipModeRestore")
		RunService:UnbindFromRenderStep("ClipModeCamera")
		restoreCamera()
		trueCFrame, smoothCFrame = nil, nil
		if camera then
			camera.FieldOfView = normalFov
		end
		showScreenGuis()
		setCoreUi(true)
		print(`[Noodle Bonk] {highlightText()}`)
		showResults()
	end
end

-- Setup ---------------------------------------------------------------------------------

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100

	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BorderSizePixel = 0
	flash.Visible = false
	flash.Parent = gui

	results = Instance.new("Frame")
	results.AnchorPoint = Vector2.new(0.5, 0.5)
	results.Position = UDim2.fromScale(0.5, 0.5)
	results.Size = UDim2.new(0, 560, 0.7, 0)
	results.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	results.BackgroundTransparency = 0.05
	results.Visible = false
	results.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = results

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Clip highlights: select all (Ctrl+A), copy (Ctrl+C)"
	title.Parent = results

	resultsBox = Instance.new("TextBox")
	resultsBox.Position = UDim2.fromOffset(16, 46)
	resultsBox.Size = UDim2.new(1, -32, 1, -104)
	resultsBox.BackgroundColor3 = Color3.fromRGB(12, 15, 22)
	resultsBox.Font = Enum.Font.Code
	resultsBox.TextSize = 15
	resultsBox.TextColor3 = Color3.fromRGB(230, 235, 245)
	resultsBox.TextXAlignment = Enum.TextXAlignment.Left
	resultsBox.TextYAlignment = Enum.TextYAlignment.Top
	resultsBox.TextWrapped = true
	resultsBox.MultiLine = true
	resultsBox.ClearTextOnFocus = false
	resultsBox.TextEditable = false
	resultsBox.Text = ""
	resultsBox.Parent = results

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -16, 1, -12)
	close.Size = UDim2.fromOffset(110, 36)
	close.BackgroundColor3 = Color3.fromRGB(70, 80, 100)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "Close"
	close.Parent = results
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = close
	close.Activated:Connect(hideResults)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function ClipMode.start()
	build()
	Remotes.HitConfirm.OnClientEvent:Connect(onHit)
	Remotes.Bonked.OnClientEvent:Connect(onBonked)
	Remotes.Knockback.OnClientEvent:Connect(onKnockback)
	Remotes.AbilityFx.OnClientEvent:Connect(onAbilityFx)
	Remotes.PoolParty.OnClientEvent:Connect(function()
		log(1, "Pool Party started")
	end)

	ContextActionService:BindAction(TOGGLE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin and player:GetAttribute("IsAdmin") then
			ClipMode.setEnabled(not enabled)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K)
end

return ClipMode
