--!strict
-- Client entry point.

local KnockbackController = require(script.KnockbackController)
local NoodleController = require(script.NoodleController)
local Effects = require(script.Effects)
local BonkUI = require(script.BonkUI)
local NoodleMenu = require(script.NoodleMenu)

KnockbackController.start()
Effects.start()
BonkUI.start()
NoodleMenu.start()
NoodleController.start()
