--!strict
-- Server entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ArenaBuilder = require(script.ArenaBuilder)
local CombatService = require(script.CombatService)
local BonkTracker = require(script.BonkTracker)
local NoodleTools = require(script.NoodleTools)

Players.RespawnTime = Config.RespawnTime

ArenaBuilder.build()
CombatService.start()
BonkTracker.start(CombatService)
NoodleTools.start()
