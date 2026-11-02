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

	-- Solo dummy: when exactly one player is in a server, one dummy spawns and
	-- fights them. It disappears as soon as a second player joins.
	SoloDummy = true,
	SoloDummyName = "Noodle Bot", -- shown in the kill feed: "BONKED by Noodle Bot!"

	-- Practice dummies (admin panel > Spawn dummies)
	DummyCount = 3, -- default number for "Respawn everyone" style resets
	DummyRingCenter = Vector3.new(0, 0, 0),
	DummyRingRadius = 25,
	DummyTag = "NoodleDummy", -- tag any Humanoid model with this to make your own dummy
	DummyColor = Color3.fromRGB(120, 200, 255),
	DummyBonksCountInStudio = true, -- bonking dummies counts toward unlocks, but only in Studio

	-- Dummy fight (admin panel > Server > Dummies fight: ON). Dummies grab a
	-- noodle, chase the nearest player and swing at them. Only in that server.
	DummyFight = {
		Noodle = "Classic", -- noodle the dummies hold
		WalkSpeed = 15, -- a bit slower than players (16), so you can still get away
		LungeSpeed = 26, -- speed of the short dash forward while swinging
		ExtraReach = 1.5, -- studs of hit range on top of the noodle's length
		ChaseRange = 400, -- studs; players further away are ignored (the whole deck)
		SwingCooldown = 1.2, -- seconds between a dummy's swings
		Power = 0.85, -- fraction of the noodle's normal knockback
	},

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

	-- Noodle abilities
	VanishTime = 4, -- Invisible noodle: seconds you stay invisible (hitting someone ends it)
	MagnetRadius = 32, -- Magnet noodle: studs it pulls from
	TornadoTime = 3, -- Tornado noodle: seconds you spin
	TornadoSpinSpeed = 22, -- radians per second (about 3.5 turns a second)
	SprayRange = 16, -- Splash noodle: studs the spray reaches
	SpraySoak = 40, -- Splash noodle: Soak added by the spray
	LuckyChance = 2500, -- Lucky noodle: 1 in this many bonks unlocks it

	-- Duck jar and Giant Rubber Duck boss (each server has its own). Every bonk
	-- drops a duck in the jar; a full jar spawns the boss. Bonk it into the
	-- pool, and everyone who hit it unlocks the Duck noodle.
	DuckJar = {
		Target = 2500, -- ducks needed to summon the boss
		Spot = Vector3.new(199, -12, 115), -- bottom of the jar: out in the pool, past the deck edge
		Scale = 4, -- 4x a normal jar (48 studs tall)
	},
	DuckBoss = {
		Scale = 1.6, -- size of the duck model (1 = the 9-stud decoration)
		BodySize = Vector3.new(11, 9, 13), -- its invisible hitbox
		MaxHP = 2000,
		DamagePerPower = 0.5, -- damage = hit power x this (a full Classic hit at 0% Soak is about 27)
		WalkSpeed = 7,
		BumpRange = 3, -- belly bump anyone this close to its body
		BumpCooldown = 4, -- per player
		BumpPower = 55,
		QuackEvery = 15, -- seconds between QUACK shockwaves
		QuackRadius = 22,
		QuackPower = 50,
		RestAfterAttack = 1.5, -- seconds it stands still after attacking
		Lifetime = 420, -- seconds before it gets bored and leaves
		StayInside = 20, -- it won't walk closer than this to the deck edge
	},
	StampedeLength = 60, -- Duck noodle: studs the duck stampede runs
	StampedePower = 75,

	-- Noodle tool
	DefaultNoodle = "Classic",
	SelectCooldown = 0.5, -- seconds between noodle switches from the menu
	GripSign = 1, -- set to -1 if noodles point backwards out of the hand

	-- Saving
	AutosaveInterval = 120,

	-- Shop. Create the game passes and developer product on Creator Hub, then
	-- paste their IDs here (see README "Shop setup"). 0 = not set up yet: the
	-- shop shows it as "Coming soon".
	Monetization = {
		SkinsPassId = 2064184318, -- game pass: Noodle Skins (79 R$)
		VipPassId = 2063685083, -- game pass: VIP (99 R$)
		DoubleBonksPassId = 2064176426, -- game pass: 2X Bonks (49 R$)
		PoolPartyProductId = 3726303546, -- developer product: Pool Party (25 R$, can buy again)
		-- In Studio, act as if you own every pass so you can test the perks
		StudioOwnsEverything = true,
	},

	-- Pool Party server event (bought from the shop, or started from the admin panel)
	PoolParty = {
		Duration = 60, -- seconds; buying another while one runs adds this much
		Gravity = 90, -- floatier jumps and launches during the party
		BonkMultiplier = 2, -- everyone's Bonks count double
	},

	-- Studio only: builds a frozen, ready-to-screenshot thumbnail scene on the
	-- arena instead of normal play (see server/ThumbnailScene and the README).
	BuildThumbnailScene = false,
	ThumbnailShot = "Thumbnail", -- "Thumbnail" (16:9 action shot) or "Icon" (square close-up)

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
		BubblePop = { Ids = { 9113263454 }, Volume = 0.8 }, -- Balloon Pop 1
		Tentacle = { Ids = { 9119990452 }, Volume = 0.9 }, -- Tentacle Slime 1
		Vanish = { Ids = { 9120286427 }, Volume = 0.6 }, -- Tubular Whoosh Rise
		Magnet = { Ids = { 9113524242 }, Volume = 0.7 }, -- Body Impact 3
		Tornado = { Ids = { 9120972444, 9120972457, 9120972323 }, Volume = 0.9 }, -- Wood Whoosh Quick Swings
		Quack = { Ids = { 9113854528, 9113854411 }, Volume = 1 }, -- Comic Boinks (swap in a real quack)
		Stampede = { Ids = { 9113854234, 9113854388, 9113854393 }, Volume = 0.9 }, -- Comic Boinks
		Streak = { Ids = { 9116394545 }, Volume = 0.8 }, -- Magic Glows Chiming Hits
		StreakEnded = { Ids = { 9120974378 }, Volume = 0.6 }, -- Wrestling Crowd 3
		Unlock = { Ids = { 9126073001 }, Volume = 0.8 }, -- Synth Sparkle Bell Ding
		Click = { Ids = { 9119717529 }, Volume = 0.5 }, -- Switch Click Toggle
		Announcement = { Ids = { 9114402205 }, Volume = 0.6 }, -- Dual Air Horns
	} :: { [string]: { Ids: { number }, Volume: number } },

	-- Ocean ambience under everything (ProSoundEffects), always on, quiet
	Ambience = {
		Waves = { Id = 9119677305, Volume = 0.22 }, -- Surf Ocean Wave Impact On Zuma Beach 4
		Seagulls = { Id = 9118858002, Volume = 0.08 }, -- Seagulls 1
	} :: { [string]: { Id: number, Volume: number } },

	-- Sunny gameplay lighting (server/Environment). Turn off to keep your place's own Lighting.
	SetupLighting = true,

	-- Background music from Roblox's licensed APM library. Plays in a shuffled loop.
	Music = {
		Ids = { 1837779005, 1840735251, 9043828544 }, -- Beach Party, Pool Party, Maui Beach
		Volume = 0.2,
	},
}

return Config
