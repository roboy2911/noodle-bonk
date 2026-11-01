--!strict
-- Global tuning. Per-noodle numbers live in Noodles.luau.

local Config = {
	-- Arena
	KillY = -20, -- falling below this height counts as getting bonked
	WaterLevel = -30, -- top of the pool water (splash effects appear here)
	AutoBuildArena = true, -- builds the pool deck arena if Workspace has no model named "Arena"
	ArenaDiameter = 330, -- width of the round deck in studs
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

	-- Bonk streaks (bonks in a row without falling in). Reaching a tier makes
	-- you glow and is announced to everyone. Past the last tier, it's announced
	-- again every StreakRepeatEvery bonks.
	StreakTiers = {
		{ At = 3, Title = "ON FIRE", Color = Color3.fromRGB(255, 150, 40) },
		{ At = 5, Title = "UNSTOPPABLE", Color = Color3.fromRGB(255, 60, 60) },
		{ At = 10, Title = "LEGENDARY", Color = Color3.fromRGB(190, 90, 255) },
	},
	StreakRepeatEvery = 5,
	StreakEndMinimum = 3, -- ending a streak at least this long is announced
	StreakEndBonus = 2, -- extra Bonks for ending one

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

	-- Admins: the game's owner (or group owner) always counts, and everyone
	-- does in Studio. Add more people's UserIds here.
	AdminUserIds = {} :: { number },
	RescuePosition = Vector3.new(0, 6, 0), -- where god-mode players land instead of getting bonked

	-- Sound effects from Roblox's licensed ProSoundEffects library (free to use
	-- in any game). Each sound picks one of its Ids at random so repeats don't
	-- sound identical. Play them by name with Effects.playSound("Hit").
	Sounds = {
		Swing = { Ids = { 9120972444, 9120972457, 9120972323, 9120972321, 9120972724 }, Volume = 0.45 }, -- Wood Whoosh Quick Swings
		Hit = { Ids = { 9114183180, 9114183700, 9114183696, 9114183750, 9114183827 }, Volume = 0.9 }, -- Drips Pillow Hits Wet
		HitBoink = { Ids = { 9113854234, 9113854411, 9113854388, 9113854393, 9113854527 }, Volume = 0.5 }, -- Comic Boinks
		Splash = { Ids = { 9120589380, 9120589559 }, Volume = 0.8 }, -- Water Splash Jumping In Pool
		Launched = { Ids = { 9119197896, 9119197913 }, Volume = 0.6 }, -- Slide Whistle
		Boing = { Ids = { 9113854528 }, Volume = 0.8 }, -- Comic Boinks 6
		Slam = { Ids = { 9113524242 }, Volume = 0.9 }, -- Body Impact 3
		BubbleTrap = { Ids = { 9125409840 }, Volume = 0.8 }, -- Bubbles Small Underwater
		BubblePop = { Ids = { 9113263454 }, Volume = 0.8 }, -- Balloon Pop 1
		Tentacle = { Ids = { 9119990452 }, Volume = 0.9 }, -- Tentacle Slime 1
		Lash = { Ids = { 9113612888 }, Volume = 0.8 }, -- Buggy Whip Quick Swish Crack
		Inflate = { Ids = { 9120286427 }, Volume = 0.6 }, -- Tubular Whoosh Rise
		Streak = { Ids = { 9116394545 }, Volume = 0.8 }, -- Magic Glows Chiming Hits
		StreakEnded = { Ids = { 9120974378 }, Volume = 0.6 }, -- Wrestling Crowd 3
		Unlock = { Ids = { 9126073001 }, Volume = 0.8 }, -- Synth Sparkle Bell Ding
		Click = { Ids = { 9119717529 }, Volume = 0.5 }, -- Switch Click Toggle
		Announcement = { Ids = { 9114402205 }, Volume = 0.6 }, -- Dual Air Horns
	} :: { [string]: { Ids: { number }, Volume: number } },

	-- Background music from Roblox's licensed APM library. Plays in a shuffled loop.
	Music = {
		Ids = { 1837779005, 1840735251, 9043828544 }, -- Beach Party, Pool Party, Maui Beach
		Volume = 0.2,
	},
}

return Config
