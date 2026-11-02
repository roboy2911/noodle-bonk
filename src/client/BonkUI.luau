--!strict
-- The big "BONKED!" banner and the kill feed in the top-right corner.
--
-- The feed stays quiet: it only lists bonks you were part of, plus big
-- moments everyone should see (streak milestones, streaks being ended, and
-- admin announcements).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer

local MAX_FEED_ENTRIES = 5
local FEED_LIFETIME = 5
local BANNER_TIME = 1.6

local GOT_BONKED_COLOR = Color3.fromRGB(255, 90, 90)
local DID_BONK_COLOR = Color3.fromRGB(255, 225, 60)
local ANNOUNCEMENT_COLOR = Color3.fromRGB(120, 220, 255)
local STREAK_END_COLOR = Color3.fromRGB(255, 200, 80)

local BonkUI = {}

local banner: TextLabel
local bannerStroke: UIStroke
local bannerScale: UIScale
local feed: Frame
local bannerToken = 0
local feedOrder = 0

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BonkUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Size = UDim2.fromScale(0.8, 0.12)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.LuckiestGuy
	banner.TextScaled = true
	banner.Visible = false
	banner.Parent = gui

	bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 4
	bannerStroke.Parent = banner

	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	feed = Instance.new("Frame")
	feed.AnchorPoint = Vector2.new(1, 0)
	feed.Position = UDim2.new(1, -16, 0, 60)
	feed.Size = UDim2.fromOffset(340, 200)
	feed.BackgroundTransparency = 1
	feed.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 4)
	layout.Parent = feed

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Big centered text that slams in, then fades. Other UI uses it too (unlocks).
function BonkUI.showBanner(text: string, color: Color3, duration: number?)
	bannerToken += 1
	local token = bannerToken

	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	bannerStroke.Transparency = 0
	banner.Visible = true

	-- Slam in big, then settle
	bannerScale.Scale = 1.8
	TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	task.delay(duration or BANNER_TIME, function()
		if token ~= bannerToken then
			return
		end
		local fade = TweenInfo.new(0.3)
		TweenService:Create(banner, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerStroke, fade, { Transparency = 1 }):Play()
	end)
end

local function addFeedEntry(text: string, color: Color3?)
	feedOrder += 1

	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.fromOffset(340, 26)
	entry.AutomaticSize = Enum.AutomaticSize.None
	entry.BackgroundColor3 = Color3.new(0, 0, 0)
	entry.BackgroundTransparency = 0.45
	entry.Font = Enum.Font.GothamBold
	entry.TextSize = 16
	entry.TextColor3 = color or Color3.new(1, 1, 1)
	entry.TextXAlignment = Enum.TextXAlignment.Right
	entry.TextTruncate = Enum.TextTruncate.AtEnd
	entry.Text = text .. "  "
	entry.LayoutOrder = -feedOrder -- newest on top
	entry.Parent = feed

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = entry

	-- Trim the oldest entries
	local entries = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = MAX_FEED_ENTRIES + 1, #entries do
		entries[i]:Destroy()
	end

	task.delay(FEED_LIFETIME, function()
		if not entry.Parent then
			return
		end
		local tween = TweenService:Create(entry, TweenInfo.new(0.4), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		tween.Completed:Once(function()
			entry:Destroy()
		end)
		tween:Play()
	end)
end

local function onBonked(info: { [string]: any })
	local attacker: Player? = info.attacker
	local dummyName: string? = info.attackerName -- a dummy bonked them
	local byName: string? = if attacker then attacker.DisplayName else dummyName
	local victim: Player? = info.victim
	local victimName: string = info.victimName
	local position: Vector3 = info.position
	local streak: number? = info.attackerStreak
	local milestoneTitle: string? = info.milestoneTitle
	local milestoneColor: Color3 = info.milestoneColor or DID_BONK_COLOR
	local endedStreak: number? = info.endedStreak
	local bonus: number? = info.bonus

	-- Feed: your own bonks only
	if attacker == player then
		addFeedEntry(`You bonked {victimName} into the deep end`, DID_BONK_COLOR)
	elseif victim == player then
		addFeedEntry(if byName then `{byName} bonked you` else "You fell in the pool", GOT_BONKED_COLOR)
	end

	-- Feed: big moments, for everyone
	if attacker and endedStreak then
		local attackerName = if attacker == player then "You" else attacker.DisplayName
		local victimLabel = if victim == player then "your" else `{victimName}'s`
		addFeedEntry(`{attackerName} ended {victimLabel} {endedStreak} bonk streak!`, STREAK_END_COLOR)
	end
	if attacker and milestoneTitle and streak then
		local name = if attacker == player then "You are" else `{attacker.DisplayName} is`
		addFeedEntry(`{name} {milestoneTitle}! {streak} bonks in a row`, milestoneColor)
	end

	Effects.playSound("Splash", Vector3.new(position.X, Config.WaterLevel, position.Z))
	Effects.splash(Vector3.new(position.X, Config.WaterLevel, position.Z))

	if victim == player then
		Effects.playSound("Launched")
		BonkUI.showBanner(if byName then `BONKED by {byName}!` else "SPLASH! You fell in.", GOT_BONKED_COLOR)
	elseif attacker == player then
		if milestoneTitle and streak then
			Effects.playSound("Streak")
			BonkUI.showBanner(`{milestoneTitle}! {streak} STREAK`, milestoneColor, 2.5)
		elseif endedStreak and bonus then
			Effects.playSound("StreakEnded")
			BonkUI.showBanner(`STREAK ENDED! +{bonus} BONKS`, STREAK_END_COLOR, 2.5)
		else
			BonkUI.showBanner(`BONKED {victimName}!`, DID_BONK_COLOR)
		end
	end
end

function BonkUI.start()
	build()
	Remotes.Bonked.OnClientEvent:Connect(onBonked)
	Remotes.Announcement.OnClientEvent:Connect(function(text: string, from: string)
		Effects.playSound("Announcement")
		BonkUI.showBanner(text, ANNOUNCEMENT_COLOR, 5)
		addFeedEntry(`[ADMIN] {from}: {text}`)
	end)
end

return BonkUI
