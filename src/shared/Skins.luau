--!strict
-- Noodle skins. They work on any noodle and only change how it looks.
-- "Skins" ones come with the Noodle Skins Pack game pass, "Vip" ones with VIP.

export type SkinDef = {
	Id: string,
	DisplayName: string,
	Color: Color3, -- shown in the menu swatch; Rainbow ignores it on the noodle
	Material: Enum.Material,
	Rainbow: boolean?, -- colors cycle along the noodle
	Requires: "Skins" | "Vip",
}

local Skins = {}

Skins.List = {
	{ Id = "Gold", DisplayName = "Gold", Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil, Requires = "Skins" },
	{ Id = "Rainbow", DisplayName = "Rainbow", Color = Color3.fromRGB(255, 80, 120), Material = Enum.Material.SmoothPlastic, Rainbow = true, Requires = "Skins" },
	{ Id = "Galaxy", DisplayName = "Galaxy", Color = Color3.fromRGB(150, 90, 255), Material = Enum.Material.ForceField, Requires = "Skins" },
	{ Id = "Neon", DisplayName = "Neon", Color = Color3.fromRGB(0, 255, 200), Material = Enum.Material.Neon, Requires = "Skins" },
	{ Id = "Lava", DisplayName = "Lava", Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.CrackedLava, Requires = "Skins" },
	{ Id = "Diamond", DisplayName = "Diamond (VIP)", Color = Color3.fromRGB(160, 235, 255), Material = Enum.Material.Glass, Requires = "Vip" },
} :: { SkinDef }

Skins.ById = {} :: { [string]: SkinDef }
for _, skin in Skins.List do
	Skins.ById[skin.Id] = skin
end

-- Rainbow color for a point along the noodle (0-1) at time `t`.
function Skins.rainbowAt(along: number, t: number): Color3
	return Color3.fromHSV((t * 0.35 + along * 0.6) % 1, 0.75, 1)
end

return Skins
