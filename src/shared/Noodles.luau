--!strict
-- Every noodle in the game. To add one: copy an entry, give it a new Id,
-- and (optionally) point Ability at a function in server/NoodleAbilities.

export type NoodleDef = {
	Id: string,
	DisplayName: string,
	Description: string, -- shown in the noodle menu
	Color: Color3,
	Length: number,
	Thickness: number,

	Knockback: number, -- base launch speed (studs/sec) before Soak
	Upward: number?, -- upward lift as a fraction of Knockback (defaults to Config.BaseUpward)
	Cooldown: number, -- seconds between swings
	Range: number, -- studs from your root to theirs
	ArcDeg: number, -- width of the swing in front of you
	MaxTargets: number, -- how many players one swing can hit
	SoakGain: number, -- Soak added to the victim per hit

	RagdollTime: number?, -- seconds the victim tumbles (defaults to Config.RagdollTime)
	StunTime: number?, -- seconds the victim can't move or swing
	WalkSpeed: number?, -- your walk speed while holding it

	Ability: string?, -- name of an active ability (E / ButtonY / mobile button)
	AbilityCooldown: number?,
}

local Noodles: { [string]: NoodleDef } = {
	Classic = {
		Id = "Classic",
		DisplayName = "Classic Noodle",
		Description = "The trusty pink noodle. Good at everything.",
		Color = Color3.fromRGB(255, 105, 180),
		Length = 7,
		Thickness = 0.8,
		Knockback = 55,
		Cooldown = 0.7,
		Range = 8,
		ArcDeg = 80,
		MaxTargets = 1,
		SoakGain = 12,
	},

	-- Slow and heavy. Hits like a frozen fish.
	Frozen = {
		Id = "Frozen",
		DisplayName = "Frozen Noodle",
		Description = "Slow and heavy. Hits like a frozen fish.",
		Color = Color3.fromRGB(170, 230, 255),
		Length = 7,
		Thickness = 0.9,
		Knockback = 80,
		Cooldown = 1.2,
		Range = 7,
		ArcDeg = 70,
		MaxTargets = 1,
		SoakGain = 20,
		WalkSpeed = 13,
	},

	-- Sends people straight up. Ability: bounce yourself into the air.
	Spring = {
		Id = "Spring",
		DisplayName = "Spring Noodle",
		Description = "Sends people sky-high. Press E to bounce yourself up.",
		Color = Color3.fromRGB(255, 225, 60),
		Length = 7,
		Thickness = 0.8,
		Knockback = 40,
		Upward = 1.4,
		Cooldown = 0.9,
		Range = 8,
		ArcDeg = 80,
		MaxTargets = 1,
		SoakGain = 10,
		Ability = "Boing",
		AbilityCooldown = 6,
	},

	-- Weak push, but leaves the victim stunned and wide open.
	Jellyfish = {
		Id = "Jellyfish",
		DisplayName = "Jellyfish Noodle",
		Description = "Weak push, but leaves them stunned and wide open.",
		Color = Color3.fromRGB(190, 120, 255),
		Length = 7,
		Thickness = 0.8,
		Knockback = 25,
		Cooldown = 1.0,
		Range = 8,
		ArcDeg = 80,
		MaxTargets = 1,
		SoakGain = 8,
		RagdollTime = 0.4,
		StunTime = 1.2,
	},

	-- Wide, fast and weak. Hits up to 4 people at once.
	Spaghetti = {
		Id = "Spaghetti",
		DisplayName = "Spaghetti Noodle",
		Description = "Fast, wide and weak. Bonks up to 4 people at once.",
		Color = Color3.fromRGB(255, 215, 130),
		Length = 7,
		Thickness = 0.6,
		Knockback = 30,
		Cooldown = 0.55,
		Range = 9,
		ArcDeg = 140,
		MaxTargets = 4,
		SoakGain = 6,
	},

	-- Long reach. Ability: lash someone and yank them toward you.
	Whip = {
		Id = "Whip",
		DisplayName = "Noodle Whip",
		Description = "Longest reach. Press E to yank someone toward you.",
		Color = Color3.fromRGB(90, 220, 120),
		Length = 10,
		Thickness = 0.6,
		Knockback = 45,
		Cooldown = 0.8,
		Range = 11,
		ArcDeg = 50,
		MaxTargets = 1,
		SoakGain = 10,
		Ability = "Lash",
		AbilityCooldown = 7,
	},
}

return Noodles
