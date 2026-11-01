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

	Ability: string?, -- name of an active ability (E / ButtonY / mobile button)
	AbilityCooldown: number?,

	Unlock: UnlockRequirement?, -- nil = free from the start
}

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

	Spaghetti = {
		Id = "Spaghetti",
		DisplayName = "Spaghetti Noodle",
		Description = "Super floppy. Whips around wildly and bonks fast.",
		Color = Color3.fromRGB(255, 215, 130),
		Length = 8,
		Thickness = 0.55,
		Stiffness = 90,
		Knockback = 32,
		Cooldown = 0.25,
		SoakGain = 7,
		Unlock = { Stat = "Bonks", Amount = 10 },
	},

	Jellyfish = {
		Id = "Jellyfish",
		DisplayName = "Jellyfish Noodle",
		Description = "Weak push, but leaves them stunned and wide open.",
		Color = Color3.fromRGB(190, 120, 255),
		Length = 7,
		Thickness = 0.8,
		Stiffness = 200,
		Knockback = 25,
		Cooldown = 0.8,
		SoakGain = 8,
		RagdollTime = 0.4,
		StunTime = 1.2,
		Unlock = { Stat = "Splashes", Amount = 15 },
	},

	Spring = {
		Id = "Spring",
		DisplayName = "Spring Noodle",
		Description = "Sends people sky-high. Press E to bounce yourself up.",
		Color = Color3.fromRGB(255, 225, 60),
		Length = 7,
		Thickness = 0.8,
		Stiffness = 320,
		Knockback = 40,
		Upward = 1.4,
		Cooldown = 0.6,
		SoakGain = 10,
		Ability = "Boing",
		AbilityCooldown = 6,
		Unlock = { Stat = "Bonks", Amount = 50 },
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
		Unlock = { Stat = "Bonks", Amount = 75 },
	},

	Frozen = {
		Id = "Frozen",
		DisplayName = "Frozen Noodle",
		Description = "Frozen stiff. Slow, but hits like a frozen fish.",
		Color = Color3.fromRGB(170, 230, 255),
		Length = 7,
		Thickness = 0.9,
		Stiffness = 600,
		Knockback = 80,
		Cooldown = 1.0,
		SoakGain = 20,
		WalkSpeed = 13,
		Unlock = { Stat = "Bonks", Amount = 100 },
	},

	Inflatable = {
		Id = "Inflatable",
		DisplayName = "Inflatable Noodle",
		Description = "Press E to blow it up to giant size for a few seconds.",
		Color = Color3.fromRGB(80, 230, 200),
		Length = 7,
		Thickness = 1.0,
		Stiffness = 220,
		Knockback = 50,
		Cooldown = 0.5,
		SoakGain = 12,
		Ability = "Inflate",
		AbilityCooldown = 15,
		Unlock = { Stat = "Bonks", Amount = 150 },
	},

	Bubble = {
		Id = "Bubble",
		DisplayName = "Bubble Noodle",
		Description = "Press E to trap someone in a bubble and float them away.",
		Color = Color3.fromRGB(140, 210, 255),
		Length = 7,
		Thickness = 0.8,
		Stiffness = 240,
		Knockback = 35,
		Cooldown = 0.6,
		SoakGain = 10,
		Ability = "BubbleTrap",
		AbilityCooldown = 10,
		Unlock = { Stat = "Splashes", Amount = 40 },
	},

	Whip = {
		Id = "Whip",
		DisplayName = "Noodle Whip",
		Description = "Longest reach. Press E to yank someone toward you.",
		Color = Color3.fromRGB(90, 220, 120),
		Length = 10,
		Thickness = 0.6,
		Stiffness = 150,
		Knockback = 45,
		Cooldown = 0.5,
		SoakGain = 10,
		Ability = "Lash",
		AbilityCooldown = 7,
		Unlock = { Stat = "Bonks", Amount = 200 },
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
		Unlock = { Stat = "Bonks", Amount = 300 },
	},
}

return Noodles
