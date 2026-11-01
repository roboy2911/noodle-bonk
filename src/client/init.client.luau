--!strict
-- Client entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

if Config.BuildThumbnailScene then
	-- Screenshot mode: just look through the thumbnail camera with no UI
	require(script.ThumbnailView).start()
	return
end

local CameraController = require(script.CameraController)
local KnockbackController = require(script.KnockbackController)
local Effects = require(script.Effects)
local BonkUI = require(script.BonkUI)
local NoodleVisuals = require(script.NoodleVisuals)
local NoodleController = require(script.NoodleController)
local Hud = require(script.Hud)
local NoodleMenu = require(script.NoodleMenu)
local AdminMovement = require(script.AdminMovement)
local AdminPanel = require(script.AdminPanel)
local Music = require(script.Music)

CameraController.start()
KnockbackController.start()
Effects.start()
BonkUI.start()
NoodleVisuals.start()
NoodleController.start()
Hud.start()
NoodleMenu.start()
AdminMovement.start()
AdminPanel.start()
Music.start()
