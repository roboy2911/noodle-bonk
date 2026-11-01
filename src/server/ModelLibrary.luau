--!strict
-- Loads the Blender models at server start and keeps ready-to-clone templates
-- in ReplicatedStorage.ModelLibrary, so both server and client code can use them.
--
-- The models are Model assets owned by the game's creator (uploaded by
-- tools/upload_models.py). InsertService can only load them in a place owned
-- by that same account, so in an unsaved Studio place they won't load and the
-- game falls back to its simple built-in parts. Save the place to Roblox (or
-- publish it) and they appear.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ModelAssets = require(Shared.ModelAssets)
local ModelIds = require(Shared.ModelIds)

local LOAD_TIMEOUT = 20

local ModelLibrary = {}

local templates: { [string]: Model } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	local existing = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local found: Folder
	if existing and existing:IsA("Folder") then
		found = existing
	else
		found = Instance.new("Folder")
		found.Name = "ModelLibrary"
		found.Parent = ReplicatedStorage
	end
	folder = found
	return found
end

local function colorPart(part: BasePart)
	local token = ModelAssets.tokenOf(part.Name)
	local swatch = token and ModelAssets.Palette[token]
	if swatch then
		part.Color = swatch.Color
		part.Material = swatch.Material
	end
	if part:IsA("MeshPart") then
		part.TextureID = ""
	end
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
end

-- Turns the model so it stands the way its spec says (Tall / Flat).
local function fitOrientation(model: Model, fit: string?)
	if not fit then
		return
	end
	local _, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local turn: CFrame? = nil
	if fit == "Tall" and not (size.Y >= size.X and size.Y >= size.Z) then
		turn = if size.Z >= size.X then CFrame.Angles(math.rad(-90), 0, 0) else CFrame.Angles(0, 0, math.rad(90))
	elseif fit == "Flat" and not (size.Y <= size.X and size.Y <= size.Z) then
		turn = if size.Z <= size.X then CFrame.Angles(math.rad(-90), 0, 0) else CFrame.Angles(0, 0, math.rad(90))
	end
	if turn then
		model:PivotTo(CFrame.new(pivot.Position) * turn * pivot.Rotation)
	end
end

-- Puts the model's pivot at the bottom-center of its bounding box, at the origin.
local function normalize(model: Model)
	local box, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position - Vector3.new(0, size.Y / 2, 0))
	model:PivotTo(CFrame.new())
end

local function scaleToSpec(model: Model, spec: ModelAssets.Spec)
	local _, size = model:GetBoundingBox()
	local current = if spec.Measure == "Height" then size.Y else math.max(size.X, size.Z)
	if current > 0.001 then
		model:ScaleTo(model:GetScale() * spec.Size / current)
	end
end

local function prepare(name: string, loaded: Instance): Model?
	local model = Instance.new("Model")
	model.Name = name
	local count = 0
	for _, descendant in loaded:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Parent = model
			count += 1
		end
	end
	loaded:Destroy()
	if count == 0 then
		return nil
	end

	local spec = ModelAssets.Specs[name]
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			colorPart(part)
			part.Anchored = true
			part.CanCollide = if spec then spec.CanCollide else true
			part.CanTouch = false
			part.CanQuery = part.CanCollide
		end
	end
	if spec then
		fitOrientation(model, spec.Fit)
		normalize(model)
		scaleToSpec(model, spec)
		normalize(model)
	end
	return model
end

local function loadOne(name: string, assetId: number)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		warn(`[Noodle Bonk] Model {name} ({assetId}) didn't load: {result}`)
		return
	end
	local model = prepare(name, result)
	if model then
		model.Parent = getFolder()
		templates[name] = model
	end
end

-- Loads every model in ModelIds. Waits until all have loaded or failed (or
-- the timeout passes). Returns how many loaded.
function ModelLibrary.load(): number
	local pending = 0
	for name, assetId in ModelIds do
		pending += 1
		task.spawn(function()
			loadOne(name, assetId)
			pending -= 1
		end)
	end
	local deadline = os.clock() + LOAD_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end

	local loaded = 0
	for _ in templates do
		loaded += 1
	end
	getFolder():SetAttribute("Ready", true)
	getFolder():SetAttribute("Loaded", loaded)
	if loaded == 0 then
		warn("[Noodle Bonk] No Blender models loaded, using simple parts. Save the place to Roblox under the account that owns the models to see them.")
	else
		print(`[Noodle Bonk] Loaded {loaded} Blender models`)
	end
	return loaded
end

function ModelLibrary.has(name: string): boolean
	if templates[name] then
		return true
	end
	return false
end

-- A copy of the model, bottom-center at `cframe`. `scale` multiplies its spec size.
-- `colors` fills the ColorA / ColorB placeholders. Returns nil if it isn't loaded.
function ModelLibrary.spawn(
	name: string,
	cframe: CFrame,
	parent: Instance,
	scale: number?,
	colors: { ColorA: Color3?, ColorB: Color3? }?
): Model?
	local template = templates[name]
	if not template then
		return nil
	end
	local model = template:Clone()
	if scale and scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
	end
	if colors then
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				local token = ModelAssets.tokenOf(part.Name)
				if token == "ColorA" and colors.ColorA then
					part.Color = colors.ColorA
				elseif token == "ColorB" and colors.ColorB then
					part.Color = colors.ColorB
				end
			end
		end
	end
	model:PivotTo(cframe)
	model.Parent = parent
	return model
end

return ModelLibrary
