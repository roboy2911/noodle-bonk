--!strict
-- Every noodle in the game. To add one: copy an entry, give it a new Id,
-- and (optionally) point Ability at a function in server/NoodleAbilities.
-- New noodles show up in the noodle menu automatically.

export type UnlockRequirement = {
	Stat: string, -- a stat from Unlocks.STATS, e.g. "Bonks"
	Amount: number,
}

export type NoodleDef = {
	Id: string,
	DisplayName: string,
	Description: string, -- shown in the noodle menu
	Color: Color3,
	Length: number,
	Thickness: number,
	Stiffness: number, -- how hard it springs back straight. Lower = floppier

	Knockback: number, -- launch speed (studs/sec) of a full-power hit, before Soak
	Upward: number?, -- upward lift as a fraction of Knockback (defaults to Config.BaseUpward)
	Cooldown: number, -- seconds before you can hit the same target again
	SoakGain: number, -- Soak added to the victim per hit

	RagdollTime: number?, -- seconds the victim flops around (defaults to Config.RagdollTime)
	StunTime: number?, -- seconds the victim can't move or swing
	WalkSpeed: number?, -- your walk speed while holding it
	Invisible: boolean?, -- other players can't see this noodle (you see it faintly)

	Ability: string?, -- name of an active ability (E / ButtonY / mobile button)
	AbilityCooldown: number?,

	Unlock: UnlockRequirement?, -- nil = free from the start
}

-- Unlocks go up with how strong the noodle is, and all come from Bonks.
local Noodles: { [string]: NoodleDef } = {
	Classic = {
		Id = "Classic",
		DisplayName = "Classic Noodle",
		Description = "The trusty pink noodle. Good at everything.",
		Color = Color3.fromRGB(255, 105, 180),
		Length = 7,
		Thickness = 0.8,
		Stiffness = 260,
		Knockback = 55,
		Cooldown = 0.5,
		SoakGain = 12,
	},

	Pogo = {
		Id = "Pogo",
		DisplayName = "Pogo Noodle",
		Description = "Press E to pogo up and slam down with a shockwave.",
		Color = Color3.fromRGB(255, 140, 50),
		Length = 6,
		Thickness = 0.9,
		Stiffness = 350,
		Knockback = 45,
		Upward = 0.9,
		Cooldown = 0.6,
		SoakGain = 10,
		Ability = "PogoSlam",
		AbilityCooldown = 8,
		Unlock = { Stat = "Bonks", Amount = 25 },
	},

	Invisible = {
		Id = "Invisible",
		DisplayName = "Invisible Noodle",
		Description = "Nobody else can see it. Press E to vanish completely for a few seconds.",
		Color = Color3.fromRGB(210, 220, 255),
		Length = 7,
		Thickness = 0.75,
		Stiffness = 260,
		Knockback = 55,
		Cooldown = 0.5,
		SoakGain = 12,
		Invisible = true,
		Ability = "Vanish",
		AbilityCooldown = 12,
		Unlock = { Stat = "Bonks", Amount = 75 },
	},

	Magnet = {
		Id = "Magnet",
		DisplayName = "Magnet Noodle",
		Description = "Heavy metal. Press E to pull everyone nearby right to you.",
		Color = Color3.fromRGB(225, 55, 55),
		Length = 6.5,
		Thickness = 1.0,
		Stiffness = 450,
		Knockback = 62,
		Cooldown = 0.7,
		SoakGain = 14,
		WalkSpeed = 15,
		Ability = "Magnet",
		AbilityCooldown = 10,
		Unlock = { Stat = "Bonks", Amount = 150 },
	},

	Kraken = {
		Id = "Kraken",
		DisplayName = "Kraken Noodle",
		Description = "Press E to grab someone with a tentacle and throw them over your head.",
		Color = Color3.fromRGB(120, 60, 160),
		Length = 9,
		Thickness = 1.0,
		Stiffness = 180,
		Knockback = 60,
		Cooldown = 0.8,
		SoakGain = 14,
		RagdollTime = 1.4,
		Ability = "Tentacle",
		AbilityCooldown = 10,
		Unlock = { Stat = "Bonks", Amount = 250 },
	},

	Tornado = {
		Id = "Tornado",
		DisplayName = "Tornado Noodle",
		Description = "The strongest noodle. Press E to spin like a tornado and bonk everyone around you.",
		Color = Color3.fromRGB(150, 215, 235),
		Length = 8,
		Thickness = 0.8,
		Stiffness = 420,
		Knockback = 66,
		Cooldown = 0.45,
		SoakGain = 14,
		Ability = "Tornado",
		AbilityCooldown = 14,
		Unlock = { Stat = "Bonks", Amount = 400 },
	},
}

return Noodles
