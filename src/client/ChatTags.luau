--!strict
-- Adds a gold [VIP] tag in front of chat messages from VIP players
-- (TextChatService, the default chat).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTags = {}

function ChatTags.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("Owns_Vip") then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = `<font color="#FFD23C">[VIP]</font> {message.PrefixText}`
			return properties
		end
		return nil :: any -- leave everyone else's messages as they are
	end
end

return ChatTags
