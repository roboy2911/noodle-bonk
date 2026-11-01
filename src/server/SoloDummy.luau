--!strict
-- Keeps exactly one dummy in the server while exactly one player is in it,
-- and none otherwise. That dummy always fights (see server/DummyFight), so a
-- player alone in a server still has someone to bonk.
--
-- Dummies an admin spawns from the panel aren't touched.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DummySpawner = require(script.Parent.DummySpawner)

local SoloDummy = {}

local updating = false
local again = false

local function soloDummies(): { Model }
	local list = {}
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") and dummy.Parent and dummy:GetAttribute("SoloDummy") then
			table.insert(list, dummy)
		end
	end
	return list
end

-- Adds or removes the solo dummy to match the player count.
function SoloDummy.update()
	if updating then
		again = true -- someone joined or left mid-update; check again after
		return
	end
	updating = true
	repeat
		again = false
		local wanted = if Config.SoloDummy and #Players:GetPlayers() == 1 then 1 else 0
		local existing = soloDummies()
		for i = wanted + 1, #existing do
			existing[i]:Destroy()
		end
		if #existing < wanted then
			DummySpawner.spawn(1, true) -- building the rig can yield
		end
	until not again
	updating = false
end

function SoloDummy.start()
	Players.PlayerAdded:Connect(SoloDummy.update)
	Players.PlayerRemoving:Connect(function()
		task.defer(SoloDummy.update) -- the leaving player is still in the list right now
	end)
	task.spawn(SoloDummy.update)
end

return SoloDummy
