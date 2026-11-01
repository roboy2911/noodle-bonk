--!strict
-- How the Blender models (tools/blender/build_models.py) look and fit in game.
--
-- Every MeshPart in a model is named "<Token>_<anything>". The token picks its
-- color and material from Palette below, so the models don't need textures.
-- ColorA / ColorB are placeholders the arena recolors per copy (e.g. umbrella
-- stripes). Asset IDs come from the generated ModelIds.luau.

local Config = require(script.Parent.Config)

export type Swatch = { Color: Color3, Material: Enum.Material }

export type Spec = {
	-- How to measure the model when sizing it, and the size it should be in studs
	Measure: "Height" | "Width",
	Size: number,
	-- Orientation sanity check after import: "Tall" models should be tallest
	-- along Y, "Flat" ones thinnest along Y. nil = trust the file. Only use it
	-- for shapes that are clearly taller than wide (or flatter than wide):
	-- an umbrella is wider than it is tall, so "Tall" would tip it over.
	Fit: ("Tall" | "Flat")?,
	-- Whether players bump into it
	CanCollide: boolean,
}

local ModelAssets = {}

ModelAssets.Palette = {
	Foam = { Color = Color3.fromRGB(255, 105, 180), Material = Enum.Material.SmoothPlastic },
	Sand = { Color = Color3.fromRGB(238, 228, 205), Material = Enum.Material.Concrete },
	Cyan = { Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.SmoothPlastic },
	White = { Color = Color3.fromRGB(246, 246, 246), Material = Enum.Material.SmoothPlastic },
	Wood = { Color = Color3.fromRGB(176, 124, 78), Material = Enum.Material.Wood },
	WoodDark = { Color = Color3.fromRGB(122, 82, 48), Material = Enum.Material.Wood },
	Red = { Color = Color3.fromRGB(235, 64, 64), Material = Enum.Material.SmoothPlastic },
	Yellow = { Color = Color3.fromRGB(255, 214, 50), Material = Enum.Material.SmoothPlastic },
	Orange = { Color = Color3.fromRGB(255, 140, 30), Material = Enum.Material.SmoothPlastic },
	Black = { Color = Color3.fromRGB(25, 25, 25), Material = Enum.Material.SmoothPlastic },
	Blue = { Color = Color3.fromRGB(60, 140, 255), Material = Enum.Material.SmoothPlastic },
	Green = { Color = Color3.fromRGB(90, 200, 90), Material = Enum.Material.SmoothPlastic },
	Leaf = { Color = Color3.fromRGB(72, 178, 72), Material = Enum.Material.SmoothPlastic },
	Bark = { Color = Color3.fromRGB(152, 112, 72), Material = Enum.Material.Wood },
	Brown = { Color = Color3.fromRGB(112, 72, 42), Material = Enum.Material.SmoothPlastic },
	Pink = { Color = Color3.fromRGB(255, 105, 180), Material = Enum.Material.SmoothPlastic },
	Accent = { Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.SmoothPlastic },
	ColorA = { Color = Color3.fromRGB(255, 105, 180), Material = Enum.Material.SmoothPlastic },
	ColorB = { Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic },
} :: { [string]: Swatch }

ModelAssets.Specs = {
	-- Noodle pieces are sized every frame by NoodleVisuals, so only colors matter here
	NoodleSegment = { Measure = "Width", Size = 1, CanCollide = false },
	NoodleTip = { Measure = "Width", Size = 1, CanCollide = false },

	PoolDeck = { Measure = "Width", Size = Config.ArenaDiameter + 3, Fit = "Flat", CanCollide = false },
	SpawnPad = { Measure = "Width", Size = 14, Fit = "Flat", CanCollide = true },
	Umbrella = { Measure = "Height", Size = 11.5, CanCollide = true },
	LoungeChair = { Measure = "Width", Size = 7, CanCollide = true },
	LifeguardTower = { Measure = "Height", Size = 15, Fit = "Tall", CanCollide = true },
	BeachBall = { Measure = "Height", Size = 4, CanCollide = true },
	SwimRing = { Measure = "Width", Size = 5.5, Fit = "Flat", CanCollide = true },
	RubberDuck = { Measure = "Height", Size = 9, CanCollide = true },
	PalmTree = { Measure = "Height", Size = 21, CanCollide = true },
	Crate = { Measure = "Height", Size = 5, CanCollide = true },
} :: { [string]: Spec }

-- The palette token at the start of a part name ("Wood_Leg" -> "Wood").
function ModelAssets.tokenOf(partName: string): string?
	return string.match(partName, "^(%a+)_")
end

return ModelAssets
