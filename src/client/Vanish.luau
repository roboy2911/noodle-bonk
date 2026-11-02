--!strict
-- Hides characters that used the Invisible noodle's Vanish ability (a
-- "VanishedUntil" server time on the character). Other players see nothing;
-- you see yourself faintly so you know where you are. Their noodle, name,
-- Soak % and other tags over their head are hidden too.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local SELF_TRANSPARENCY = 0.65 -- how see-through you look to yourself

local Vanish = {}

type Hidden = { nameDisplay: Enum.HumanoidDisplayDistanceType?, guis: { BillboardGui } }
local hidden: { [Model]: Hidden } = {}

-- Is this character vanished right now?
function Vanish.isVanished(character: Model): boolean
	local untilTime = character:GetAttribute("VanishedUntil")
	return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

-- How see-through things on this character should be for this client: 0 = normal.
function Vanish.transparencyFor(character: Model): number
	if not Vanish.isVanished(character) then
		return 0
	end
	return if character == player.Character then SELF_TRANSPARENCY else 1
end

local function setLook(character: Model, amount: number)
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = amount
		end
	end
end

local function hide(character: Model)
	local state = hidden[character]
	if not state then
		state = { guis = {} }
		hidden[character] = state
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			state.nameDisplay = humanoid.DisplayDistanceType
		end
	end
	-- Every frame, so new parts and tags (and Roblox's own camera fading) can't undo it
	setLook(character, Vanish.transparencyFor(character))
	if character ~= player.Character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		for _, item in character:GetDescendants() do
			if item:IsA("BillboardGui") and item.Enabled then
				item.Enabled = false
				table.insert(state.guis, item)
			end
		end
	end
end

local function show(character: Model)
	local state = hidden[character]
	if not state then
		return
	end
	hidden[character] = nil
	setLook(character, 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and state.nameDisplay then
		humanoid.DisplayDistanceType = state.nameDisplay
	end
	for _, gui in state.guis do
		if gui.Parent then
			gui.Enabled = true
		end
	end
end

local function step()
	local characters: { Model } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(characters, other.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(Config.DummyTag) do
		if dummy:IsA("Model") then
			table.insert(characters, dummy)
		end
	end
	local seen: { [Model]: boolean } = {}
	for _, character in characters do
		if Vanish.isVanished(character) then
			seen[character] = true
			hide(character)
		end
	end
	for character in hidden do
		if not seen[character] then
			show(character)
		end
	end
end

function Vanish.start()
	RunService:BindToRenderStep("NoodleVanish", Enum.RenderPriority.Character.Value + 1, step)
end

return Vanish
