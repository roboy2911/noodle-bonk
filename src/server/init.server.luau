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
local DummySpawner = require(script.DummySpawner)
local DummyFight = require(script.DummyFight)
local GlobalEvents = require(script.GlobalEvents)
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
Streaks.start()
CombatService.start()
BonkTracker.start(CombatService)
NoodleTools.start()
AdminService.start()
GlobalEvents.start()
DummyFight.start()
MonetizationService.start()
if Config.BuildThumbnailScene then
	-- Screenshot mode: no player characters or dummies, just the posed scene
	Players.CharacterAutoLoads = false
	task.spawn(require(script.ThumbnailScene).build)
else
	task.spawn(DummySpawner.spawn) -- building rigs can yield
end
