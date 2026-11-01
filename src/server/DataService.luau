--!strict
-- Saves each player's stats and chosen noodle with DataStores.
--
-- Stats are copied onto the Player as attributes ("Stat_Bonks", ...) so the
-- client can show unlock progress, and "DataLoaded" is set once they're in.
--
-- To test saving in Studio, turn on Game Settings > Security >
-- "Enable Studio Access to API Services". Without it, the game still runs
-- but nothing is saved.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Unlocks = require(Shared.Unlocks)
local Skins = require(Shared.Skins)

local STORE_NAME = "NoodleBonk_v1"

export type PlayerData = {
	Stats: { [string]: number },
	Selected: string,
	Skin: string?, -- chosen noodle skin (still needs the pass to use it)
}

type Profile = {
	data: PlayerData,
	canSave: boolean, -- false if loading failed, so we never overwrite real data with blanks
}

local DataService = {}

local profiles: { [Player]: Profile } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[Noodle Bonk] DataStores unavailable, progress won't save: {result}`)
	end
end

local function defaultData(): PlayerData
	local stats = {}
	for _, stat in Unlocks.STATS do
		stats[stat] = 0
	end
	return { Stats = stats, Selected = Config.DefaultNoodle }
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function load(player: Player): (PlayerData, boolean)
	local data = defaultData()
	local dataStore = store
	if not dataStore then
		return data, false
	end

	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			if type(result) == "table" then
				local savedStats = result.Stats
				if type(savedStats) == "table" then
					for _, stat in Unlocks.STATS do
						local value = savedStats[stat]
						if type(value) == "number" then
							data.Stats[stat] = value
						end
					end
				end
				if type(result.Selected) == "string" and Noodles[result.Selected] then
					data.Selected = result.Selected
				end
				if type(result.Skin) == "string" and Skins.ById[result.Skin] then
					data.Skin = result.Skin
				end
			end
			return data, true
		end

		warn(`[Noodle Bonk] Loading data for {player.Name} failed (try {attempt}): {result}`)
		-- No point retrying if Studio just isn't allowed to use DataStores
		if string.find(tostring(result), "StudioAccessToApisNotAllowed") then
			break
		end
		task.wait(attempt)
	end
	return data, false
end

local function save(player: Player)
	local profile = profiles[player]
	local dataStore = store
	if not profile or not profile.canSave or not dataStore then
		return
	end
	local ok, err = pcall(function()
		dataStore:UpdateAsync(keyFor(player), function()
			return profile.data
		end)
	end)
	if not ok then
		warn(`[Noodle Bonk] Saving data for {player.Name} failed: {err}`)
	end
end

local function setupLeaderstats(player: Player, data: PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local bonks = Instance.new("IntValue")
	bonks.Name = "Bonks"
	bonks.Value = data.Stats.Bonks or 0
	bonks.Parent = leaderstats

	leaderstats.Parent = player
end

local function onPlayerAdded(player: Player)
	local data, canSave = load(player)
	if not player.Parent then
		return -- left while loading
	end
	profiles[player] = { data = data, canSave = canSave }

	setupLeaderstats(player, data)
	for _, stat in Unlocks.STATS do
		player:SetAttribute(Unlocks.statAttribute(stat), data.Stats[stat] or 0)
	end
	player:SetAttribute("DataLoaded", true)
end

local function onPlayerRemoving(player: Player)
	save(player)
	profiles[player] = nil
end

-- Waits (up to 15s) for the player's data to load. nil if they left or it timed out.
function DataService.waitForData(player: Player): PlayerData?
	local deadline = os.clock() + 15
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	local profile = profiles[player]
	return if profile then profile.data else nil
end

function DataService.increment(player: Player, stat: string, amount: number)
	local profile = profiles[player]
	if profile then
		DataService.setStat(player, stat, (profile.data.Stats[stat] or 0) + amount)
	end
end

function DataService.getStat(player: Player, stat: string): number
	local profile = profiles[player]
	return if profile then profile.data.Stats[stat] or 0 else 0
end

function DataService.setStat(player: Player, stat: string, value: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.data.Stats[stat] = value
	player:SetAttribute(Unlocks.statAttribute(stat), value)

	if stat == "Bonks" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local bonks = leaderstats and leaderstats:FindFirstChild("Bonks")
		if bonks and bonks:IsA("IntValue") then
			bonks.Value = value
		end
	end
end

-- Wipes the player's progress back to a fresh start (saved on next save).
function DataService.reset(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local fresh = defaultData()
	profile.data.Selected = fresh.Selected
	for stat, value in fresh.Stats do
		DataService.setStat(player, stat, value)
	end
end

-- Whether this player's data can be saved (false in Studio without API access).
function DataService.canSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.canSave
end

function DataService.setSkin(player: Player, skinId: string?)
	local profile = profiles[player]
	if profile then
		profile.data.Skin = skinId
	end
end

function DataService.setSelected(player: Player, noodleId: string)
	local profile = profiles[player]
	if profile then
		profile.data.Selected = noodleId
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)

	-- Save everyone when the server shuts down
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
