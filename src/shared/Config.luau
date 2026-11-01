--!strict
-- Global combat tuning. Per-noodle numbers live in Noodles.luau.

local Config = {
	-- Arena
	KillY = -20, -- falling below this height counts as getting bonked
	AutoBuildArena = true, -- builds a test pool island if Workspace has no model named "Arena"
	RespawnTime = 2,
	SpawnProtection = 3, -- seconds of ForceField after spawning (swinging ends it early)
	DefaultWalkSpeed = 16,

	-- A hit still earns the bonk if the victim falls within this many seconds
	CreditWindow = 8,

	-- Server-side validation. These allow for network lag between what the
	-- attacker saw and where the server thinks everyone is.
	RangeTolerance = 5,
	ArcToleranceDeg = 25,
	CooldownTolerance = 0.85, -- server accepts swings at 85% of the cooldown
	MaxTargetsPerRequest = 8,

	-- Soak: every hit you take makes you wetter, and wetter players fly further.
	-- Knockback is multiplied by (1 + Soak / 100).
	MaxSoak = 200,
	SoakDecayPerSecond = 2,

	-- Knockback defaults (a noodle can override these)
	BaseUpward = 0.35, -- upward lift as a fraction of knockback power
	RagdollTime = 1.2,
	BodyRadius = 2, -- added to range checks so you can hit the edge of a body

	-- Noodle tool
	DefaultNoodle = "Classic",
	GripOffset = 0.6, -- how far from the noodle's end the hand holds it
	GripSign = 1, -- set to -1 if noodles point backwards out of the hand

	-- Placeholder sounds from Roblox's built-in content. Swap in real foam / squeak sounds.
	Sounds = {
		Swing = "rbxasset://sounds/swordslash.wav",
		Bonk = "rbxasset://sounds/swordlunge.wav",
		Splash = "rbxasset://sounds/impact_water.mp3",
	},
}

return Config
