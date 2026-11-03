--!strict
-- Server entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ModelLibrary = require(script.ModelLibrary)
local ArenaBuilder = require(script.ArenaBuilder)
local Environment = require(script.Environment)
local DataService = require(script.DataService)
local CombatService = require(script.CombatService)
local BonkTracker = require(script.BonkTracker)
local NoodleTools = require(script.NoodleTools)
local DummyFight = require(script.DummyFight)
local GlobalEvents = require(script.GlobalEvents)
local SoloDummy = require(script.SoloDummy)
local Friends = require(script.Friends)
local PoolParty = require(script.PoolParty)
local DuckBoss = require(script.DuckBoss)
local DuckJar = require(script.DuckJar)
local AdminService = require(script.AdminService)
local Streaks = require(script.Streaks)
local MonetizationService = require(script.MonetizationService)

Players.RespawnTime = Config.RespawnTime

ModelLibrary.load() -- the Blender models; waits up to ~20s, falls back to simple parts
ArenaBuilder.build()
if not Config.BuildThumbnailScene then
	Environment.setup()
end
DataService.start()
-- Remember (saved) that the player finished the tutorial, so it only shows once
require(ReplicatedStorage.Shared.Remotes).TutorialDone.OnServerEvent:Connect(function(player)
	if DataService.getStat(player, "Tutorial") < 1 then
		DataService.setStat(player, "Tutorial", 1)
	end
end)
Streaks.start()
CombatService.start()
BonkTracker.start(CombatService)
NoodleTools.start()
AdminService.start()
GlobalEvents.start()
DummyFight.start()
Friends.start()
PoolParty.init()
DuckBoss.start(CombatService)
if not Config.BuildThumbnailScene then
	DuckJar.start()
end
MonetizationService.start()
if Config.BuildThumbnailScene then
	-- Screenshot mode: no player characters or dummies, just the posed scene
	Players.CharacterAutoLoads = false
	task.spawn(require(script.ThumbnailScene).build)
else
	SoloDummy.start() -- one dummy that fights you when you're alone
end
