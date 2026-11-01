--!strict
-- The shop: a SHOP button on the left opens four cards (Skins Pack, VIP,
-- 2x Bonks, Pool Party) with their icons, perks and a buy button. Owned
-- passes show OWNED; passes whose ID isn't set in Config yet show COMING SOON.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local ImageIds = require(Shared.ImageIds)
local CameraController = require(script.Parent.CameraController)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer

local PANEL_COLOR = Color3.fromRGB(22, 28, 44)
local CARD_COLOR = Color3.fromRGB(36, 44, 66)
local BUY_COLOR = Color3.fromRGB(60, 200, 110)
local OWNED_COLOR = Color3.fromRGB(70, 80, 105)
local SHOP_COLOR = Color3.fromRGB(255, 200, 40)

type Item = {
	key: string, -- "Skins" | "Vip" | "DoubleBonks" | "PoolParty"
	title: string,
	perks: string,
	image: number,
	id: number,
	isProduct: boolean,
}

local ITEMS: { Item } = {
	{
		key = "Skins",
		title = "NOODLE SKINS",
		perks = "Gold, Rainbow, Galaxy, Neon and Lava skins for every noodle!",
		image = ImageIds.pass_skins_512,
		id = Config.Monetization.SkinsPassId,
		isProduct = false,
	},
	{
		key = "Vip",
		title = "VIP",
		perks = "Gold VIP tag, [VIP] in chat, and the exclusive Diamond skin.",
		image = ImageIds.pass_vip_512,
		id = Config.Monetization.VipPassId,
		isProduct = false,
	},
	{
		key = "DoubleBonks",
		title = "2X BONKS",
		perks = "Every bonk counts double. Unlock noodles twice as fast!",
		image = ImageIds.pass_2x_bonks_512,
		id = Config.Monetization.DoubleBonksPassId,
		isProduct = false,
	},
	{
		key = "PoolParty",
		title = "POOL PARTY",
		perks = "60s party for the WHOLE server: floaty jumps, confetti, 2x Bonks for everyone!",
		image = ImageIds.product_pool_party_512,
		id = Config.Monetization.PoolPartyProductId,
		isProduct = true,
	},
}

local Shop = {}

local panel: Frame
local panelScale: UIScale
local isOpen = false
local buyButtons: { [string]: TextButton } = {}
local prices: { [string]: number } = {}

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function owns(key: string): boolean
	return player:GetAttribute(`Owns_{key}`) == true
end

-- Opens Roblox's purchase prompt for a shop item ("Skins", "Vip", ...).
function Shop.prompt(key: string)
	for _, item in ITEMS do
		if item.key == key and item.id ~= 0 then
			if item.isProduct then
				MarketplaceService:PromptProductPurchase(player, item.id)
			elseif not owns(key) then
				MarketplaceService:PromptGamePassPurchase(player, item.id)
			end
			return
		end
	end
	Shop.setOpen(true) -- not set up yet: just show the shop
end

local function refreshButtons()
	for _, item in ITEMS do
		local button = buyButtons[item.key]
		if not button then
			continue
		end
		if item.id == 0 and not (owns(item.key) and not item.isProduct) then
			button.Text = "COMING SOON"
			button.BackgroundColor3 = OWNED_COLOR
		elseif not item.isProduct and owns(item.key) then
			button.Text = "OWNED ✓"
			button.BackgroundColor3 = OWNED_COLOR
		else
			local price = prices[item.key]
			button.Text = if price then `BUY  R$ {price}` else "BUY"
			button.BackgroundColor3 = BUY_COLOR
		end
	end
end

-- Real prices come from Roblox, so changing them on Creator Hub just works
local function loadPrices()
	for _, item in ITEMS do
		if item.id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(
						item.id,
						if item.isProduct then Enum.InfoType.Product else Enum.InfoType.GamePass
					)
				end)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					prices[item.key] = info.PriceInRobux
					refreshButtons()
				end
			end)
		end
	end
end

local function buildCard(parent: Instance, item: Item, order: number)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD_COLOR
	card.LayoutOrder = order
	card.Parent = parent
	corner(card, 14)

	local icon = Instance.new("ImageLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 10)
	icon.Size = UDim2.fromOffset(110, 110)
	icon.BackgroundTransparency = 1
	icon.Image = `rbxassetid://{item.image}`
	icon.Parent = card
	corner(icon, 55)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(10, 124)
	title.Size = UDim2.new(1, -20, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextSize = 24
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = item.title
	title.Parent = card

	local perks = Instance.new("TextLabel")
	perks.Position = UDim2.fromOffset(12, 152)
	perks.Size = UDim2.new(1, -24, 0, 46)
	perks.BackgroundTransparency = 1
	perks.Font = Enum.Font.GothamMedium
	perks.TextSize = 13
	perks.TextWrapped = true
	perks.TextColor3 = Color3.fromRGB(190, 200, 220)
	perks.Text = item.perks
	perks.Parent = card

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -24, 0, 36)
	buy.Font = Enum.Font.LuckiestGuy
	buy.TextSize = 20
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Parent = card
	corner(buy, 10)
	buy.Activated:Connect(function()
		Effects.playSound("Click")
		Shop.prompt(item.key)
	end)
	buyButtons[item.key] = buy
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6

	local open = Instance.new("TextButton")
	open.AnchorPoint = Vector2.new(0, 0.5)
	open.Position = UDim2.new(0, 16, 0.5, -54)
	open.Size = UDim2.fromOffset(130, 46)
	open.BackgroundColor3 = SHOP_COLOR
	open.Font = Enum.Font.LuckiestGuy
	open.TextSize = 22
	open.TextColor3 = Color3.fromRGB(60, 30, 0)
	open.Text = "SHOP"
	open.Parent = gui
	corner(open, 12)
	local openStroke = Instance.new("UIStroke")
	openStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	openStroke.Thickness = 3
	openStroke.Color = Color3.new(1, 1, 1)
	openStroke.Parent = open
	open.Activated:Connect(function()
		Shop.setOpen(not isOpen)
	end)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 640)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	local function fit()
		local camera = workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			panelScale:SetAttribute("Fit", math.min(1, (view.X - 20) / 620, (view.Y - 20) / 640))
			panelScale.Scale = panelScale:GetAttribute("Fit") :: number
		end
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -80, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextSize = 34
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = SHOP_COLOR
	title.Text = "SHOP"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Color3.fromRGB(230, 70, 80)
	close.Font = Enum.Font.LuckiestGuy
	close.TextSize = 22
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = panel
	corner(close, 10)
	close.Activated:Connect(function()
		Shop.setOpen(false)
	end)

	local grid = Instance.new("Frame")
	grid.Position = UDim2.fromOffset(16, 64)
	grid.Size = UDim2.new(1, -32, 1, -80)
	grid.BackgroundTransparency = 1
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(286, 270)
	layout.CellPadding = UDim2.fromOffset(16, 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, item in ITEMS do
		buildCard(grid, item, i)
	end
	refreshButtons()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function Shop.setOpen(open: boolean)
	if open ~= isOpen then
		Effects.playSound("Click")
	end
	isOpen = open
	CameraController.setCursorFree("Shop", open)
	if open then
		refreshButtons()
		panel.Visible = true
		local fitScale = panelScale:GetAttribute("Fit")
		local target = if type(fitScale) == "number" then fitScale else 1
		panelScale.Scale = target * 0.88
		TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = target,
		}):Play()
	else
		panel.Visible = false
	end
end

function Shop.start()
	build()
	loadPrices()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Owns_" then
			refreshButtons()
		end
	end)
end

return Shop
