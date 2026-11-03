--!strict
-- Unlock rules, shared by the server (which enforces them) and the client
-- (which shows progress in the noodle menu). Stats are saved by DataService
-- and copied onto the Player as attributes named "Stat_<name>".

local Noodles = require(script.Parent.Noodles)

type NoodleDef = Noodles.NoodleDef
export type Stats = { [string]: number }

local Unlocks = {}

-- Every saved stat. Add a name here to start tracking a new one.
-- "Tutorial" isn't an unlock: it's 1 once the player has finished (or skipped) the tutorial.
Unlocks.STATS = { "Bonks", "Splashes", "PoolParties", "FriendSessions", "Lucky", "DuckBosses", "Tutorial" }

local DESCRIPTIONS: { [string]: (number) -> string } = {
	Bonks = function(amount)
		return `Bonk {amount} people`
	end,
	Splashes = function(amount)
		return `Fall in the pool {amount} times`
	end,
	PoolParties = function()
		return "Be in a server during a Pool Party"
	end,
	FriendSessions = function()
		return "Play in a server with a friend"
	end,
	Lucky = function()
		return "1 in 2,500 chance on every bonk"
	end,
	DuckBosses = function()
		return "Help defeat the Giant Rubber Duck"
	end,
}

function Unlocks.statAttribute(stat: string): string
	return `Stat_{stat}`
end

function Unlocks.readStats(player: Player): Stats
	local stats: Stats = {}
	for _, stat in Unlocks.STATS do
		local value = player:GetAttribute(Unlocks.statAttribute(stat))
		stats[stat] = if type(value) == "number" then value else 0
	end
	return stats
end

function Unlocks.isUnlocked(def: NoodleDef, stats: Stats): boolean
	local requirement = def.Unlock
	if not requirement then
		return true
	end
	return (stats[requirement.Stat] or 0) >= requirement.Amount
end

-- Whether this player may use the noodle right now: earned it, or an admin
-- unlocked it for them this session (AllUnlocked / Granted_<Id> attributes).
function Unlocks.isAvailable(player: Player, def: NoodleDef): boolean
	if player:GetAttribute("AllUnlocked") or player:GetAttribute(`Granted_{def.Id}`) then
		return true
	end
	return Unlocks.isUnlocked(def, Unlocks.readStats(player))
end

-- 0 to 1 progress toward unlocking.
function Unlocks.progress(def: NoodleDef, stats: Stats): number
	local requirement = def.Unlock
	if not requirement then
		return 1
	end
	return math.clamp((stats[requirement.Stat] or 0) / requirement.Amount, 0, 1)
end

-- e.g. "Bonk 50 people (12/50)"
function Unlocks.describe(def: NoodleDef, stats: Stats): string
	local requirement = def.Unlock
	if not requirement then
		return "Free"
	end
	local describe = DESCRIPTIONS[requirement.Stat]
	local text = if describe then describe(requirement.Amount) else `{requirement.Stat}: {requirement.Amount}`
	if requirement.Amount <= 1 then
		return text -- a one-time thing, no progress to show
	end
	local have = math.min(stats[requirement.Stat] or 0, requirement.Amount)
	return `{text} ({have}/{requirement.Amount})`
end

return Unlocks
