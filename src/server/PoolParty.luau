--!strict
-- Pool Party: a server-wide event someone buys from the shop (or an admin
-- starts). For Config.PoolParty.Duration seconds: lower gravity, everyone's
-- Bonks count double, confetti, and a countdown for everyone. Buying another
-- while one is running adds more time.
--
-- State lives on Workspace attributes so clients can show it:
--   PoolPartyUntil (server time it ends), PoolPartyBy (who started it)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

local PoolParty = {}

local normalGravity = workspace.Gravity
local token = 0

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function PoolParty.isActive(): boolean
	local untilTime = workspace:GetAttribute("PoolPartyUntil")
	return type(untilTime) == "number" and untilTime > serverNow()
end

local function finish(myToken: number)
	if myToken ~= token then
		return
	end
	workspace:SetAttribute("PoolPartyUntil", nil)
	workspace:SetAttribute("PoolPartyBy", nil)
	workspace.Gravity = normalGravity
end

-- Starts a party (or extends the current one). `starterName` is shown to everyone.
function PoolParty.start(starterName: string)
	local duration = Config.PoolParty.Duration
	local current = workspace:GetAttribute("PoolPartyUntil")
	local base = if type(current) == "number" and current > serverNow() then current else serverNow()
	if not PoolParty.isActive() then
		normalGravity = workspace.Gravity
	end
	workspace:SetAttribute("PoolPartyUntil", base + duration)
	workspace:SetAttribute("PoolPartyBy", starterName)
	workspace.Gravity = Config.PoolParty.Gravity

	token += 1
	local myToken = token
	task.delay(base + duration - serverNow(), finish, myToken)

	-- Being here for a party unlocks the Party noodle
	for _, player in Players:GetPlayers() do
		DataService.increment(player, "PoolParties", 1)
	end

	Remotes.PoolParty:FireAllClients(starterName, duration)
	print(`[Noodle Bonk] Pool Party started by {starterName} ({#Players:GetPlayers()} players)`)
end

-- Players who join while a party is on get credit for it too.
function PoolParty.init()
	Players.PlayerAdded:Connect(function(player)
		if PoolParty.isActive() and DataService.waitForData(player) and player.Parent then
			DataService.increment(player, "PoolParties", 1)
		end
	end)
end

return PoolParty
