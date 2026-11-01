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

Players.RespawnTime = Config.RespawnTime

ArenaBuilder.build()
DataService.start()
CombatService.start()
BonkTracker.start(CombatService)
NoodleTools.start()
AdminService.start()
task.spawn(DummySpawner.spawn) -- building rigs can yield
