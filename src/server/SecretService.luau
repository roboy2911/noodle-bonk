--!strict
-- Unlocks the secret noodles. Players only ever see a vague hint; the real
-- rules are here:
--
--   Quack      stand on the giant rubber duck decoration for 30 seconds
--   Coconut    touch the coconut at the top of one palm tree
--   Clown      get bonked by someone using the Tornado noodle 10 times
--   Lifeguard  play 5 minutes in a server with others without landing a hit
--   Snail      stand completely still for 2 minutes
--   Moon       get launched higher than 150 studs
--   ???        "Infection": get bonked by someone holding ???. The game's owner
--              starts with it, and it spreads from there. Each new infection is
--              announced with a count across all servers.
--
-- Finding one awards its badge (Config.SecretBadges, 0 = no badge yet) and
-- tells the server.

local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local DataService = require(script.Parent.DataService)

local STEP = 0.25
local QUACK_TIME = 30
local SNAIL_TIME = 120
local LIFEGUARD_TIME = 300
local MOON_HEIGHT = 150
local COCONUT_REACH = 6
local INFECTION_NOODLE = "Mystery"

local SecretService = {}

type Progress = { duck: number, still: number, calm: number, lastPosition: Vector3? }
local progress: { [Player]: Progress } = {}
local foundAlready: { [Player]: { [string]: boolean } } = {}

local secretDefs = {}
for _, def in Noodles do
	if def.Secret then
		table.insert(secretDefs, def)
	end
end

local function unlock(player: Player, stat: string)
	if DataService.getStat(player, stat) < 1 then
		DataService.setStat(player, stat, 1)
	end
end

-- Award the badge and tell the server when a secret is newly found.
local function checkFound(player: Player)
	local found = foundAlready[player]
	if not found then
		return
	end
	local stats = Unlocks.readStats(player)
	for _, def in secretDefs do
		if not found[def.Id] and Unlocks.isUnlocked(def, stats) then
			found[def.Id] = true
			local badgeId = Config.SecretBadges[def.Id]
			if badgeId and badgeId > 0 then
				task.spawn(pcall, function()
					BadgeService:AwardBadge(player.UserId, badgeId)
				end)
			end
			if def.Id ~= INFECTION_NOODLE then -- infections have their own news
				Remotes.SecretNews:FireAllClients("Found", player.DisplayName)
			end
		end
	end
end

-- ??? infection ---------------------------------------------------------------

local function infect(player: Player)
	if DataService.getStat(player, "Infected") >= 1 then
		return
	end
	DataService.setStat(player, "Infected", 1)
	task.spawn(function()
		local count: number? = nil
		pcall(function()
			count = DataStoreService:GetDataStore("NoodleBonkSecrets"):IncrementAsync("InfectedCount", 1)
		end)
		Remotes.SecretNews:FireAllClients("Infected", player.DisplayName, count)
		print(`[Noodle Bonk] ??? spread to {player.Name} (#{count or "?"})`)
	end)
end

-- Called by BonkTracker for every bonk. `noodleId` is the noodle that hit them.
function SecretService.onBonk(attacker: Player?, victim: Player?, noodleId: string?)
	if not victim then
		return
	end
	if noodleId == "Tornado" and attacker then
		DataService.increment(victim, "TornadoBonked", 1) -- Clown
	end
	if noodleId == INFECTION_NOODLE and attacker then
		infect(victim)
	end
end

-- Map secrets ---------------------------------------------------------------------

local function standingOn(root: BasePart, model: Instance): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	return workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params) ~= nil
end

local function update(dt: number)
	local duck = workspace:FindFirstChild("SecretDuck", true)
	local coconut = workspace:FindFirstChild("SecretCoconut", true)
	local crowded = #Players:GetPlayers() >= 2

	for _, player in Players:GetPlayers() do
		local state = progress[player]
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if state and character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			-- Moon: launched really high
			if root.Position.Y > MOON_HEIGHT then
				unlock(player, "SecretMoon")
			end
			-- Coconut: reached the top of the palm
			if
				coconut
				and coconut:IsA("BasePart")
				and (root.Position - coconut.Position).Magnitude <= COCONUT_REACH
			then
				unlock(player, "SecretCoconut")
			end
			-- Quack: standing on the giant duck
			if duck and standingOn(root, duck) then
				state.duck += dt
				if state.duck >= QUACK_TIME then
					unlock(player, "SecretQuack")
				end
			else
				state.duck = 0
			end
			-- Snail: not moving at all
			local last = state.lastPosition
			state.lastPosition = root.Position
			if last and (root.Position - last).Magnitude < 0.05 and root.AssemblyLinearVelocity.Magnitude < 0.5 then
				state.still += dt
				if state.still >= SNAIL_TIME then
					unlock(player, "SecretSnail")
				end
			else
				state.still = 0
			end
			-- Lifeguard: peaceful time with other people around (hits reset it)
			if crowded then
				state.calm += dt
				if state.calm >= LIFEGUARD_TIME then
					unlock(player, "SecretLifeguard")
				end
			end
		end
	end
end

-- Setup --------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	progress[player] = { duck = 0, still = 0, calm = 0 }
	player.CharacterAdded:Connect(function()
		local state = progress[player]
		if state then
			state.duck, state.still, state.lastPosition = 0, 0, nil
		end
	end)
	task.spawn(function()
		if not DataService.waitForData(player) or not player.Parent then
			return
		end
		-- Remember what they'd already found, so only new finds are announced
		local found = {}
		local stats = Unlocks.readStats(player)
		for _, def in secretDefs do
			found[def.Id] = Unlocks.isUnlocked(def, stats)
		end
		foundAlready[player] = found
		for _, def in secretDefs do
			local stat = def.Unlock and def.Unlock.Stat
			if stat then
				player:GetAttributeChangedSignal(Unlocks.statAttribute(stat)):Connect(function()
					checkFound(player)
				end)
			end
		end
		-- Patient zero: the game's owner starts out infected
		if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
			unlock(player, "Infected")
		end
	end)
end

function SecretService.start(combat: any)
	-- Landing any hit resets the Lifeguard timer
	combat.onHit(function(_, attacker: Player?)
		local state = attacker and progress[attacker]
		if state then
			state.calm = 0
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		foundAlready[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= STEP then
			update(elapsed)
			elapsed = 0
		end
	end)
end

return SecretService
