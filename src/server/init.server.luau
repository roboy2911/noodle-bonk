--!strict
-- Server entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ArenaBuilder = require(script.ArenaBuilder)
local DataService = require(script.DataService)
local CombatService = require(script.CombatService)
local BonkTracker = require(script.BonkTracker)
local NoodleTools = require(script.NoodleTools)
local DummySpawner = require(script.DummySpawner)
local AdminService = require(script.AdminService)
local Streaks = require(script.Streaks)

Players.RespawnTime = Config.RespawnTime

ArenaBuilder.build()
DataService.start()
Streaks.start()
CombatService.start()
BonkTracker.start(CombatService)
NoodleTools.start()
AdminService.start()
if Config.BuildThumbnailScene then
	-- Screenshot mode: no player characters or dummies, just the posed scene
	Players.CharacterAutoLoads = false
	task.spawn(require(script.ThumbnailScene).build)
else
	task.spawn(DummySpawner.spawn) -- building rigs can yield
end
