--!strict
-- Client entry point.

local KnockbackController = require(script.KnockbackController)
local NoodleController = require(script.NoodleController)
local Effects = require(script.Effects)
local BonkUI = require(script.BonkUI)

KnockbackController.start()
Effects.start()
BonkUI.start()
NoodleController.start()
