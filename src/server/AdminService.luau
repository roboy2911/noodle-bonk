--!strict
-- Admin commands, run from the admin panel through Remotes.AdminRequest.
--
-- Who counts as an admin (checked again on every single request):
--   * the game's owner, or the owner of the group that owns it
--   * anyone whose UserId is in Config.AdminUserIds
--   * everyone, when testing in Studio
--
-- Each command takes (admin, args) and returns (success, message). Commands
-- that act on a player read the Player from args.target.

local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Noodles = require(Shared.Noodles)
local Remotes = require(Shared.Remotes)
local Unlocks = require(Shared.Unlocks)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local DummySpawner = require(script.Parent.DummySpawner)
local NoodleTools = require(script.Parent.NoodleTools)
local PoolParty = require(script.Parent.PoolParty)

type Args = { [string]: any }
type Command = (admin: Player, args: Args) -> (boolean, string)

local LOW_GRAVITY = 50
local MAX_ANNOUNCEMENT_LENGTH = 120
local MAX_DUMMIES_PER_SPAWN = 20

local AdminService = {}

local commands: { [string]: Command } = {}
local normalGravity = workspace.Gravity

-- Access ---------------------------------------------------------------------

function AdminService.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	-- Group-owned game: the group's owner is an admin
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	return ok and type(info) == "table" and type(info.Owner) == "table" and info.Owner.Id == player.UserId
end

-- Helpers --------------------------------------------------------------------

local function targetOf(args: Args): Player?
	local target = args.target
	if typeof(target) == "Instance" and target:IsA("Player") and target.Parent == Players then
		return target
	end
	return nil
end

local function numberOf(value: any): number?
	local n = tonumber(value)
	if n and n == n and n ~= math.huge and n ~= -math.huge then
		return n
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Every living-or-not character in the game: players and dummies.
local function allCharacters(): { Model }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") then
			table.insert(list, dummy)
		end
	end
	return list
end

local function toggleAttribute(player: Player, name: string): boolean
	local on = not player:GetAttribute(name)
	player:SetAttribute(name, on or nil)
	return on
end

local function onOff(on: boolean): string
	return if on then "ON" else "OFF"
end

local function launch(character: Model)
	local angle = math.random() * math.pi * 2
	CombatService.applyKnockback(character, {
		velocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 70 + Vector3.yAxis * 90,
		ragdollTime = 1.5,
		shake = 0.6,
	})
end

-- Wraps a command that needs a selected player.
local function withTarget(handler: (admin: Player, target: Player, args: Args) -> (boolean, string)): Command
	return function(admin, args)
		local target = targetOf(args)
		if not target then
			return false, "Pick a player first"
		end
		return handler(admin, target, args)
	end
end

-- Player tools ---------------------------------------------------------------

commands.GiveNoodle = withTarget(function(_, target, args)
	local id = args.noodleId
	if type(id) ~= "string" or not Noodles[id] then
		return false, "Unknown noodle"
	end
	NoodleTools.grant(target, id)
	return true, `Gave {target.DisplayName} the {Noodles[id].DisplayName}`
end)

local function statCommand(add: boolean): Command
	return withTarget(function(_, target, args)
		local stat = args.stat
		local value = numberOf(args.value)
		if type(stat) ~= "string" or not table.find(Unlocks.STATS, stat) then
			return false, "Unknown stat"
		end
		if not value then
			return false, "Type a number first"
		end
		local newValue = math.max(0, math.floor(if add then DataService.getStat(target, stat) + value else value))
		DataService.setStat(target, stat, newValue)
		return true, `{target.DisplayName}'s {stat} is now {newValue}`
	end)
end
commands.SetStat = statCommand(false)
commands.AddStat = statCommand(true)

commands.ResetData = withTarget(function(_, target)
	DataService.reset(target)
	for name in target:GetAttributes() do
		if string.sub(name, 1, 8) == "Granted_" then
			target:SetAttribute(name, nil)
		end
	end
	target:SetAttribute("AllUnlocked", nil)
	target:SetAttribute("Noodle", Config.DefaultNoodle)
	NoodleTools.give(target)
	return true, `Reset all of {target.DisplayName}'s progress`
end)

commands.Kick = withTarget(function(admin, target, args)
	if target == admin then
		return false, "You can't kick yourself"
	end
	local reason = if type(args.reason) == "string" and args.reason ~= "" then args.reason else "Kicked by an admin"
	target:Kick(string.sub(reason, 1, 200))
	return true, `Kicked {target.DisplayName}`
end)

commands.Ban = withTarget(function(admin, target, args)
	if target == admin then
		return false, "You can't ban yourself"
	end
	local hours = numberOf(args.hours) or 0
	local reason = if type(args.reason) == "string" and args.reason ~= "" then args.reason else "Banned by an admin"
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { target.UserId },
			ApplyToUniverse = true,
			Duration = if hours > 0 then math.floor(hours * 3600) else -1,
			DisplayReason = string.sub(reason, 1, 400),
			PrivateReason = `Banned by {admin.Name} ({admin.UserId})`,
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		return false, `Ban failed (bans don't work in Studio): {err}`
	end
	return true, `Banned {target.DisplayName} ` .. (if hours > 0 then `for {hours} hours` else "forever")
end)

commands.Unban = function(_, args)
	local user = args.user
	if type(user) ~= "string" or user == "" then
		return false, "Type a username or UserId to unban"
	end
	local userId = tonumber(user)
	if not userId then
		local ok, result = pcall(function()
			return Players:GetUserIdFromNameAsync(user)
		end)
		if not ok then
			return false, `No player named {user}`
		end
		userId = result
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { userId :: number }, ApplyToUniverse = true })
	end)
	if not ok then
		return false, `Unban failed: {err}`
	end
	return true, `Unbanned {user}`
end

commands.GoTo = withTarget(function(admin, target)
	local targetRoot = rootOf(target)
	if not targetRoot or not admin.Character then
		return false, "One of you has no character right now"
	end
	admin.Character:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 4))
	return true, `Teleported to {target.DisplayName}`
end)

commands.Bring = withTarget(function(admin, target)
	local adminRoot = rootOf(admin)
	if not adminRoot or not target.Character then
		return false, "One of you has no character right now"
	end
	target.Character:PivotTo(adminRoot.CFrame * CFrame.new(0, 0, -5))
	return true, `Brought {target.DisplayName} to you`
end)

commands.Kill = withTarget(function(_, target)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "They have no character right now"
	end
	humanoid.Health = 0
	return true, `Reset {target.DisplayName}`
end)

commands.Launch = withTarget(function(_, target)
	if not target.Character then
		return false, "They have no character right now"
	end
	launch(target.Character)
	return true, `Launched {target.DisplayName}`
end)

commands.MaxSoak = withTarget(function(_, target)
	if not target.Character then
		return false, "They have no character right now"
	end
	CombatService.addSoak(target.Character, Config.MaxSoak)
	return true, `{target.DisplayName} is fully soaked`
end)

commands.Dry = withTarget(function(_, target)
	if not target.Character then
		return false, "They have no character right now"
	end
	target.Character:SetAttribute("Soak", 0)
	return true, `Dried off {target.DisplayName}`
end)

-- Testing toggles (on the selected player) ------------------------------------

local function toggleCommand(attribute: string, label: string, afterToggle: ((Player, boolean) -> ())?): Command
	return withTarget(function(_, target)
		local on = toggleAttribute(target, attribute)
		if afterToggle then
			afterToggle(target, on)
		end
		return true, `{label} {onOff(on)} for {target.DisplayName}`
	end)
end

commands.ToggleUnlockAll = toggleCommand("AllUnlocked", "Unlock all", function(target, on)
	if not on then
		NoodleTools.give(target) -- drops back to an earned noodle if needed
	end
end)
commands.ToggleGod = toggleCommand("AdminGod", "God mode")
commands.ToggleFly = toggleCommand("AdminFly", "Fly")
commands.ToggleNoclip = toggleCommand("AdminNoclip", "Noclip")
commands.ToggleNoCooldown = toggleCommand("AdminNoCooldown", "No ability cooldown")

commands.SetWalkSpeed = withTarget(function(_, target, args)
	local speed = numberOf(args.value)
	if not speed then
		return false, "Type a number first (0 = normal)"
	end
	speed = math.clamp(speed, 0, 200)
	target:SetAttribute("AdminWalkSpeed", if speed > 0 then speed else nil)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local def = NoodleTools.getNoodleDef(target)
		humanoid.WalkSpeed = NoodleTools.walkSpeedFor(target, def)
	end
	return true, if speed > 0
		then `{target.DisplayName}'s walk speed is {speed}`
		else `{target.DisplayName}'s walk speed is back to normal`
end)

-- Server tools -----------------------------------------------------------------

commands.SpawnDummies = function(_, args)
	local count = math.clamp(math.floor(numberOf(args.value) or 3), 1, MAX_DUMMIES_PER_SPAWN)
	local spawned = DummySpawner.spawn(count)
	return spawned > 0, `Spawned {spawned} dummies`
end

commands.ClearDummies = function()
	return true, `Removed {DummySpawner.clear()} dummies`
end

commands.Announce = function(admin, args)
	local text = args.text
	if type(text) ~= "string" or string.gsub(text, "%s", "") == "" then
		return false, "Type a message first"
	end
	text = string.sub(text, 1, MAX_ANNOUNCEMENT_LENGTH)
	-- Roblox requires text shown to other players to go through the filter
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, admin.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "Couldn't filter that message, try again"
	end
	Remotes.Announcement:FireAllClients(filtered, admin.DisplayName)
	return true, "Announcement sent"
end

commands.SoakStorm = function()
	for _, character in allCharacters() do
		CombatService.addSoak(character, Config.MaxSoak)
	end
	return true, "Everyone is fully soaked"
end

commands.DryAll = function()
	for _, character in allCharacters() do
		character:SetAttribute("Soak", 0)
	end
	return true, "Everyone is dry"
end

commands.ToggleLowGravity = function()
	local on = workspace.Gravity == normalGravity
	workspace.Gravity = if on then LOW_GRAVITY else normalGravity
	workspace:SetAttribute("LowGravity", on or nil)
	return true, `Low gravity {onOff(on)}`
end

commands.LaunchAll = function(admin)
	for _, character in allCharacters() do
		if character ~= admin.Character then
			launch(character)
		end
	end
	return true, "Launched everyone"
end

commands.ResetEveryone = function()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
	local removed = DummySpawner.clear()
	DummySpawner.spawn(math.max(removed, Config.DummyCount))
	workspace.Gravity = normalGravity
	workspace:SetAttribute("LowGravity", nil)
	return true, "Respawned everyone and reset the dummies"
end

commands.StartPoolParty = function(admin)
	PoolParty.start(admin.DisplayName)
	return true, `Pool Party on for {Config.PoolParty.Duration}s (buying another adds time)`
end

commands.Shutdown = function(admin)
	for _, player in Players:GetPlayers() do
		player:Kick(`The server was shut down by {admin.DisplayName}. Please rejoin!`)
	end
	return true, "Shutting down"
end

-- Wiring -----------------------------------------------------------------------

local function onRequest(player: Player, command: unknown, args: unknown): (boolean, string)
	if not AdminService.isAdmin(player) then
		warn(`[Noodle Bonk] Non-admin {player.Name} ({player.UserId}) tried an admin command`)
		return false, "You're not an admin"
	end
	if type(command) ~= "string" or not commands[command] then
		return false, "Unknown command"
	end
	local handler = commands[command]
	local commandArgs: Args = if type(args) == "table" then args :: any else {}
	local ok, success, message = pcall(handler, player, commandArgs)
	if not ok then
		warn(`[Noodle Bonk] Admin command {command} errored: {success}`)
		return false, "That command hit an error (see the server output)"
	end
	print(`[Noodle Bonk] Admin {player.Name}: {command} -> {message}`)
	return success, message
end

local function markAdmin(player: Player)
	if AdminService.isAdmin(player) then
		player:SetAttribute("IsAdmin", true)
	end
end

function AdminService.start()
	Remotes.AdminRequest.OnServerInvoke = onRequest
	Players.PlayerAdded:Connect(markAdmin)
	for _, player in Players:GetPlayers() do
		task.spawn(markAdmin, player)
	end
end

return AdminService
