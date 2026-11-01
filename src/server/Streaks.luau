--!strict
-- Bonk streaks: how many people you've bonked in a row without falling in
-- yourself. Hitting a milestone (Config.StreakTiers) makes you glow and gets
-- announced to everyone. Ending someone's big streak earns bonus Bonks.
--
-- Your current streak also shows in the leaderboard. Streaks aren't saved;
-- they reset whenever your character respawns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DataService = require(script.Parent.DataService)

export type StreakTier = { At: number, Title: string, Color: Color3 }

export type StreakResult = {
	streak: number, -- attacker's streak after this bonk
	milestone: StreakTier?, -- set if this bonk hit a milestone
	ended: number?, -- the victim's streak this bonk ended, if it was big enough to matter
	bonus: number?, -- bonus Bonks the attacker got for ending it
}

local Streaks = {}

local streaks: { [Player]: number } = {}

-- The highest tier reached at `streak`, or nil below the first one.
local function tierFor(streak: number): StreakTier?
	local best: StreakTier? = nil
	for _, tier in Config.StreakTiers do
		if streak >= tier.At then
			best = tier
		end
	end
	return best
end

-- Tiers announce when first reached; past the top tier, every Config.StreakRepeatEvery.
local function milestoneAt(streak: number): StreakTier?
	local tiers = Config.StreakTiers
	for _, tier in tiers do
		if streak == tier.At then
			return tier
		end
	end
	local top = tiers[#tiers]
	if top and streak > top.At and (streak - top.At) % Config.StreakRepeatEvery == 0 then
		return top
	end
	return nil
end

local function setLeaderboard(player: Player, streak: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Streak")
	if value and value:IsA("IntValue") then
		value.Value = streak
	end
end

-- Glow in the color of the player's current tier.
local function updateGlow(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local tier = tierFor(streaks[player] or 0)
	local glow = character:FindFirstChild("StreakGlow")
	if not tier then
		if glow then
			glow:Destroy()
		end
		return
	end
	local highlight: Highlight
	if glow and glow:IsA("Highlight") then
		highlight = glow
	else
		highlight = Instance.new("Highlight")
		highlight.Name = "StreakGlow"
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = character
	end
	highlight.FillColor = tier.Color
	highlight.OutlineColor = tier.Color
end

local function setStreak(player: Player, streak: number)
	streaks[player] = streak
	player:SetAttribute("Streak", streak)
	setLeaderboard(player, streak)
	updateGlow(player)
end

-- Call on every bonk. `counts` is false for bonks that shouldn't add to
-- stats (dummies outside Studio). Returns what happened to streaks, or nil
-- if there's no attacker to credit.
function Streaks.onBonk(attacker: Player?, victim: Player?, counts: boolean): StreakResult?
	local ended: number? = nil
	if victim then
		local victimStreak = streaks[victim] or 0
		if victimStreak >= Config.StreakEndMinimum then
			ended = victimStreak
		end
		setStreak(victim, 0)
	end

	if not attacker or not counts then
		return nil
	end

	local streak = (streaks[attacker] or 0) + 1
	setStreak(attacker, streak)

	local bonus: number? = nil
	if ended then
		bonus = Config.StreakEndBonus
		DataService.increment(attacker, "Bonks", Config.StreakEndBonus)
	end

	return {
		streak = streak,
		milestone = milestoneAt(streak),
		ended = ended,
		bonus = bonus,
	}
end

local function onPlayerAdded(player: Player)
	streaks[player] = 0
	-- Respawning for any reason (bonked, reset, admin) ends the streak
	player.CharacterAdded:Connect(function()
		setStreak(player, 0)
	end)

	-- DataService creates leaderstats once their data loads; add the column then
	local leaderstats = player:WaitForChild("leaderstats", 30)
	if leaderstats and not leaderstats:FindFirstChild("Streak") then
		local value = Instance.new("IntValue")
		value.Name = "Streak"
		value.Value = streaks[player] or 0
		value.Parent = leaderstats
	end
end

function Streaks.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
	end)
end

return Streaks
