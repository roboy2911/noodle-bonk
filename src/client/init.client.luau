--!strict
-- Client entry point.

local CameraController = require(script.CameraController)
local KnockbackController = require(script.KnockbackController)
local Effects = require(script.Effects)
local BonkUI = require(script.BonkUI)
local NoodleVisuals = require(script.NoodleVisuals)
local NoodleController = require(script.NoodleController)
local Hud = require(script.Hud)
local NoodleMenu = require(script.NoodleMenu)

CameraController.start()
KnockbackController.start()
Effects.start()
BonkUI.start()
NoodleVisuals.start()
NoodleController.start()
Hud.start()
NoodleMenu.start()
