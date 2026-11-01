--!strict
-- Global tuning. Per-noodle numbers live in Noodles.luau.

local Config = {
	-- Arena
	KillY = -20, -- falling below this height counts as getting bonked
	WaterLevel = -30, -- top of the pool water (splash effects appear here)
	AutoBuildArena = true, -- builds a test pool island if Workspace has no model named "Arena"
	RespawnTime = 2,
	SpawnProtection = 3, -- seconds of ForceField after spawning (bonking someone ends it early)
	DefaultWalkSpeed = 16,

	-- Practice dummies spawned in a ring around the arena when the server starts
	DummyCount = 3, -- set to 0 to turn them off
	DummyRingCenter = Vector3.new(0, 0, 0),
	DummyRingRadius = 25,
	DummyTag = "NoodleDummy", -- tag any Humanoid model with this to make your own dummy
	DummyColor = Color3.fromRGB(120, 200, 255),
	DummyBonksCountInStudio = true, -- bonking dummies counts toward unlocks, but only in Studio

	-- Swinging. You swing by turning your camera; a hit counts when the noodle
	-- actually touches someone while moving fast enough.
	MinHitSpeed = 22, -- noodle speed (studs/sec) needed for a hit
	FullPowerSpeed = 90, -- noodle speed for full knockback
	MinPowerScale = 0.35, -- fraction of knockback a minimum-speed hit gets
	MaxHitSpeed = 200, -- faster claims are clamped
	HitPadding = 0.6, -- extra hit radius around the noodle
	ArmReach = 2.5, -- distance from your root to where the noodle starts
	WhooshSpeed = 60, -- noodle speed that plays the whoosh sound

	-- Bendy noodle simulation (visual and hits)
	NoodleSegments = 6,
	NoodleDamping = 6, -- higher = settles faster, less wobble
	NoodleSag = 18, -- how much gravity droops the noodle

	-- A hit still earns the bonk if the victim falls within this many seconds
	CreditWindow = 8,

	-- Server-side validation. These allow for network lag between what the
	-- attacker saw and where the server thinks everyone is.
	RangeTolerance = 5,
	CooldownTolerance = 0.85, -- server accepts hits/abilities at 85% of the cooldown

	-- Soak: every hit you take makes you wetter, and wetter players fly further.
	-- Knockback is multiplied by (1 + Soak / 100).
	MaxSoak = 200,
	SoakDecayPerSecond = 2,

	-- Knockback defaults (a noodle can override these)
	BaseUpward = 0.35, -- upward lift as a fraction of knockback power
	RagdollTime = 1.2,
	BodyRadius = 2, -- added to range checks so you can hit the edge of a body

	-- Inflatable noodle ability
	InflateScale = 2.2,
	InflateTime = 6,
	InflateKnockbackBonus = 1.4,

	-- Noodle tool
	DefaultNoodle = "Classic",
	SelectCooldown = 0.5, -- seconds between noodle switches from the menu
	GripSign = 1, -- set to -1 if noodles point backwards out of the hand

	-- Saving
	AutosaveInterval = 120,

	-- Placeholder sounds from Roblox's built-in content. Swap in real foam / squeak sounds.
	Sounds = {
		Swing = "rbxasset://sounds/swordslash.wav",
		Bonk = "rbxasset://sounds/swordlunge.wav",
		Splash = "rbxasset://sounds/impact_water.mp3",
	},
}

return Config
