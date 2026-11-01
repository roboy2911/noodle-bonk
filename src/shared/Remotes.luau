--!strict
-- All RemoteEvents in one place. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "NoodleRemotes"
local EVENT_NAMES = { "Swing", "UseAbility", "Knockback", "HitConfirm", "Bonked", "SelectNoodle" }

local folder: Instance
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return {
	-- client -> server: (targets: { Model }) the characters the client thinks it hit
	Swing = get("Swing"),
	-- client -> server: ()
	UseAbility = get("UseAbility"),
	-- server -> victim's client: (velocity: Vector3, ragdollTime: number, stunTime: number?)
	Knockback = get("Knockback"),
	-- server -> all clients: (position: Vector3, noodleId: string) for hit effects
	HitConfirm = get("HitConfirm"),
	-- server -> all clients: (info: BonkInfo) see BonkTracker
	Bonked = get("Bonked"),
	-- client -> server: (noodleId: string) picked from the noodle menu
	SelectNoodle = get("SelectNoodle"),
}
