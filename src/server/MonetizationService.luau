--!strict
-- The shop: game pass ownership, purchases, and their perks.
--
--   Noodle Skins Pack (pass) - skins for any noodle (Gold, Rainbow, Galaxy, Neon, Lava)
--   VIP (pass)               - gold VIP tag over your head, [VIP] in chat, Diamond skin
--   2x Bonks (pass)          - every bonk counts double (leaderboard and unlocks)
--   Pool Party (product)     - 60s server event, see PoolParty.luau
--
-- Ownership is copied onto the Player as attributes (Owns_Skins, Owns_Vip,
-- Owns_DoubleBonks) so the client shop and menus can show it. IDs live in
-- Config.Monetization; a pass with ID 0 is "coming soon" and nobody owns it
-- (except in Studio when StudioOwnsEverything is on).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Skins = require(Shared.Skins)
local DataService = require(script.Parent.DataService)
local PoolParty = require(script.Parent.PoolParty)

export type PassKey = "Skins" | "Vip" | "DoubleBonks"

local PASS_IDS: { [string]: number } = {
	Skins = Config.Monetization.SkinsPassId,
	Vip = Config.Monetization.VipPassId,
	DoubleBonks = Config.Monetization.DoubleBonksPassId,
}

local VIP_GOLD = Color3.fromRGB(255, 210, 60)

local MonetizationService = {}

local grantedReceipts: { [string]: boolean } = {}

local function studioFreebies(): boolean
	return RunService:IsStudio() and Config.Monetization.StudioOwnsEverything
end

function MonetizationService.owns(player: Player, pass: PassKey): boolean
	return player:GetAttribute(`Owns_{pass}`) == true
end

-- Skins need their pass; no skin (nil) is always allowed.
function MonetizationService.canUseSkin(player: Player, skinId: string?): boolean
	if skinId == nil then
		return true
	end
	local skin = Skins.ById[skinId]
	return skin ~= nil and MonetizationService.owns(player, skin.Requires)
end

-- How many Bonks one bonk is worth for this player right now.
function MonetizationService.bonkValue(player: Player): number
	local value = if MonetizationService.owns(player, "DoubleBonks") then 2 else 1
	if PoolParty.isActive() then
		value *= Config.PoolParty.BonkMultiplier
	end
	return value
end

-- VIP perks -------------------------------------------------------------------------

local function addVipTag(character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or head:FindFirstChild("VipTag") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Size = UDim2.fromOffset(90, 34)
	tag.StudsOffset = Vector3.new(0, 3.4, 0)
	tag.MaxDistance = 90
	tag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.Text = "⭐ VIP"
	label.TextColor3 = VIP_GOLD
	label.Parent = tag
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(90, 50, 0)
	stroke.Parent = label
end

local function applyPerks(player: Player)
	if MonetizationService.owns(player, "Vip") and player.Character then
		task.spawn(addVipTag, player.Character)
	end
end

-- Ownership ----------------------------------------------------------------------------

local function grantPass(player: Player, pass: string)
	player:SetAttribute(`Owns_{pass}`, true)
	applyPerks(player)
end

local function checkOwnership(player: Player)
	for pass, id in PASS_IDS do
		if studioFreebies() then
			grantPass(player, pass)
		elseif id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				grantPass(player, pass)
			end
		end
	end
end

-- Skins ----------------------------------------------------------------------------------

local function applySkin(player: Player, skinId: string?)
	player:SetAttribute("Skin", skinId)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("NoodleId") then
		tool:SetAttribute("Skin", skinId)
	end
end

local function onSelectSkin(player: Player, skinId: unknown)
	local id: string? = if type(skinId) == "string" then skinId else nil
	if not MonetizationService.canUseSkin(player, id) then
		return
	end
	DataService.setSkin(player, id)
	applySkin(player, id)
end

-- Purchases --------------------------------------------------------------------------------

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	-- Roblox can resend a receipt; only act on each purchase once per server
	if grantedReceipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if receipt.ProductId == Config.Monetization.PoolPartyProductId then
		PoolParty.start(player.DisplayName)
		grantedReceipts[receipt.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function onPassPurchased(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for pass, id in PASS_IDS do
		if id == passId and id ~= 0 then
			grantPass(player, pass)
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		applyPerks(player)
	end)
	checkOwnership(player)

	-- Restore their saved skin once data loads (if they still own it)
	local data = DataService.waitForData(player)
	if data and data.Skin and MonetizationService.canUseSkin(player, data.Skin) then
		applySkin(player, data.Skin)
	end
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)
	Remotes.SelectSkin.OnServerEvent:Connect(onSelectSkin)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MonetizationService
