--!strict
-- Sends admin announcements and admin-started Pool Parties to every running
-- server, using MessagingService. The server that sends one shows it right
-- away; the others show it when the message arrives (usually under a second).
--
-- Pool Parties bought from the shop are not sent here: they stay in the
-- buyer's server.
--
-- MessagingService needs a published game. In an unpublished Studio place
-- the events still show in your own server.

local MessagingService = game:GetService("MessagingService")

local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
local PoolParty = require(script.Parent.PoolParty)

local TOPIC = "NoodleBonkAdmin"

local GlobalEvents = {}

type Message = { kind: string, text: string?, from: string?, server: string }

local function show(message: Message)
	if message.kind == "Announce" and type(message.text) == "string" and type(message.from) == "string" then
		Remotes.Announcement:FireAllClients(message.text, message.from)
	elseif message.kind == "PoolParty" and type(message.from) == "string" then
		PoolParty.start(message.from)
	end
end

-- Shows it here, then tries to send it to every other server.
-- Returns whether the other servers were reached.
local function broadcast(message: Message): boolean
	show(message)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, message)
	end)
	if not ok then
		warn(`[Noodle Bonk] Couldn't send {message.kind} to other servers: {err}`)
	end
	return ok
end

-- `text` must already be filtered.
function GlobalEvents.announce(text: string, from: string): boolean
	return broadcast({ kind = "Announce", text = text, from = from, server = game.JobId })
end

function GlobalEvents.poolParty(from: string): boolean
	return broadcast({ kind = "PoolParty", from = from, server = game.JobId })
end

function GlobalEvents.start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(packet)
				local message = packet.Data
				if type(message) ~= "table" or type(message.kind) ~= "string" then
					return
				end
				if message.server == game.JobId then
					return -- we sent it and already showed it
				end
				show(message :: Message)
			end)
		end)
		if not ok then
			warn(`[Noodle Bonk] Not listening for events from other servers: {err}`)
		end
	end)
end

return GlobalEvents
