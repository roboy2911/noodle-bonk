--!strict
-- Keeps the time-based unlock stats up to date:
--   PlayTime         seconds played in total
--   LongestSurvival  longest time (seconds) a character stayed out of the pool
--   DaysPlayed       how many different days you've played (with LastDay)
-- (Hits, TimesHit, MaxSoaks, AbilitiesUsed, BestStreak, StreaksEnded and
-- DuckHits are counted where they happen.)

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local STEP = 5 -- seconds between updates

local StatsTracker = {}

local aliveSince: { [Player]: number } = {}

local function today(): number
	return os.time() // 86400
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		aliveSince[player] = os.clock()
	end)
	if player.Character then
		aliveSince[player] = os.clock()
	end
	task.spawn(function()
		if DataService.waitForData(player) and player.Parent then
			local day = today()
			if DataService.getStat(player, "LastDay") ~= day then
				DataService.setStat(player, "LastDay", day)
				DataService.increment(player, "DaysPlayed", 1)
			end
		end
	end)
end

function StatsTracker.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		aliveSince[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(STEP)
			for _, player in Players:GetPlayers() do
				DataService.increment(player, "PlayTime", STEP)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local since = aliveSince[player]
				if since and humanoid and humanoid.Health > 0 and not character:GetAttribute("Bonked") then
					local alive = math.floor(os.clock() - since)
					if alive > DataService.getStat(player, "LongestSurvival") then
						DataService.setStat(player, "LongestSurvival", alive)
					end
				end
			end
		end
	end)
end

return StatsTracker
