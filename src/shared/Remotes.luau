--!strict
-- All RemoteEvents in one place. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Sent to a victim's client through Remotes.Knockback
export type KnockbackInfo = {
	velocity: Vector3,
	ragdollTime: number, -- 0 = launch without flopping
	stunTime: number?,
	float: { velocity: Vector3, time: number }?, -- hold this velocity for a while (bubble)
	shake: number?, -- camera shake strength
}

local FOLDER_NAME = "NoodleRemotes"
local EVENT_NAMES = {
	"NoodleHit",
	"UseAbility",
	"Knockback",
	"HitConfirm",
	"Bonked",
	"SelectNoodle",
	"AbilityFx",
	"Announcement",
	"SelectSkin",
	"PoolParty",
	"LuckyNoodle",
	"DuckBoss",
}
local FUNCTION_NAMES = { "AdminRequest" }

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
	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local func = Instance.new("RemoteFunction")
			func.Name = name
			func.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

local function getFunction(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return {
	-- client -> server: (target: Model, hitPosition: Vector3, direction: Vector3, speed: number)
	-- the attacker's noodle touched someone
	NoodleHit = get("NoodleHit"),
	-- client -> server: ()
	UseAbility = get("UseAbility"),
	-- server -> victim's client: (info: KnockbackInfo)
	Knockback = get("Knockback"),
	-- server -> all clients: (position: Vector3, noodleId: string, attacker: Player?) for hit effects
	HitConfirm = get("HitConfirm"),
	-- server -> all clients: (info: BonkInfo) see BonkTracker
	Bonked = get("Bonked"),
	-- client -> server: (noodleId: string) picked from the noodle menu
	SelectNoodle = get("SelectNoodle"),
	-- server -> all clients: (kind: string, ...) ability visuals, see client/Effects
	AbilityFx = get("AbilityFx"),
	-- server -> all clients: (text: string, from: string) filtered admin announcement
	Announcement = get("Announcement"),
	-- client -> server: (skinId: string?) pick a noodle skin, nil for none
	SelectSkin = get("SelectSkin"),
	-- server -> all clients: (starterName: string, duration: number) a Pool Party started
	PoolParty = get("PoolParty"),
	-- server -> all clients: (finder: Player) someone just found the Lucky noodle
	LuckyNoodle = get("LuckyNoodle"),
	-- server -> all clients: (event: "Spawned" | "Defeated" | "Left", names: { string }?) duck boss news
	DuckBoss = get("DuckBoss"),
	-- client -> server: (command: string, args: { [string]: any }) -> (success: boolean, message: string)
	AdminRequest = getFunction("AdminRequest"),
}
