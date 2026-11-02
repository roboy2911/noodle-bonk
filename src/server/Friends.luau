--!strict
-- Tracks which players in this server are Roblox friends. The first time a
-- player shares a server with a friend, their "FriendSessions" stat goes up
-- (unlocks the Squad noodle). The Squad noodle's ability uses nearestFriend.

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local Friends = {}

local friendsOf: { [Player]: { [Player]: boolean } } = {}
local counted: { [Player]: boolean } = {} -- already counted this session

local function setFor(player: Player): { [Player]: boolean }
	local set = friendsOf[player]
	if not set then
		set = {}
		friendsOf[player] = set
	end
	return set
end

local function countSession(player: Player)
	if counted[player] then
		return
	end
	counted[player] = true
	task.spawn(function()
		if DataService.waitForData(player) and player.Parent then
			DataService.increment(player, "FriendSessions", 1)
		end
	end)
end

local function onPlayerAdded(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend and player.Parent and other.Parent then
				setFor(player)[other] = true
				setFor(other)[player] = true
				countSession(player)
				countSession(other)
			end
		end
	end
end

-- The closest friend of `player` in this server who has a character, if any.
function Friends.nearestFriend(player: Player, from: Vector3): (Player?, BasePart?)
	local best, bestRoot, bestDistance = nil, nil, math.huge
	for friend in friendsOf[player] or {} do
		local character = friend.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if friend.Parent and root and root:IsA("BasePart") then
			local distance = (root.Position - from).Magnitude
			if distance < bestDistance then
				best, bestRoot, bestDistance = friend, root, distance
			end
		end
	end
	return best, bestRoot
end

function Friends.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, set in friendsOf do
			set[player] = nil
		end
		friendsOf[player] = nil
		counted[player] = nil
	end)
end

return Friends
