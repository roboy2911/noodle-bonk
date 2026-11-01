# Noodle Bonk 🏊

A Roblox arena brawler. Bonk people off a floating pool deck with bendy pool
noodles. There's no attack button: shift lock is always on, so you swing by
turning fast, and the noodle has to actually touch someone. Every hit makes the
victim **soggier**, so they fly further on the next one.

## Setup

The project uses [Rojo](https://rojo.space). Tool versions are pinned in `rokit.toml`.

```bash
rokit install
```

```bash
rojo serve
```

Then open a place in Studio (the default Baseplate template is fine) and,
**in Edit mode (not while playing)**, connect with the Rojo plugin. Check that
`ReplicatedStorage > Shared` has its modules, then press Play. With
`Config.AutoBuildArena` on, the server replaces the Baseplate with a test pool
deck over water and spawns practice dummies.

To test saving in Studio, turn on **Game Settings > Security > Enable Studio
Access to API Services**. Without it the game runs, but progress resets each session.

## Controls

| Input | Does |
|---|---|
| Move the mouse / drag (mobile) / right stick | Turn. Turn fast to swing your noodle |
| E / ButtonY / on-screen button | Noodle ability |
| N / NOODLES button | Noodle menu |
| Ctrl | Free the mouse cursor (also freed automatically in menus and chat) |

## Layout

```
src/
  shared/               ReplicatedStorage.Shared
    Config.luau         global tuning (swing speeds, Soak, sim, sounds...)
    Noodles.luau        every noodle: stats, ability, unlock requirement
    Unlocks.luau        unlock rules shared by server and client
    HitQuery.luau       cone/range checks (used by abilities)
    Remotes.luau        RemoteEvents + the KnockbackInfo type
  server/               ServerScriptService.Server
    init.server.luau    entry point
    DataService         DataStore saving: stats, chosen noodle, leaderstats
    CombatService       validates hits and abilities, knockback, Soak
    NoodleAbilities     active abilities, keyed by name
    Ragdoll             floppy ragdoll (Motor6D <-> BallSocket)
    NoodleTools         gives out noodle Tools, handles menu picks
    BonkTracker         detects falls, credits bonks, updates stats
    ArenaBuilder        test arena for empty places
    DummySpawner        practice dummies on server start
  client/               StarterPlayerScripts.Client
    init.client.luau    entry point
    CameraController    always-on shift lock, Ctrl to free cursor, camera shake
    NoodleSim           bendy noodle physics (springy point chain)
    NoodleVisuals       draws every noodle from the sim
    NoodleController    hit detection from the sim + ability button
    KnockbackController applies launches, floats and stuns to your character
    Effects             sounds, BONK! text, splashes, ability visuals
    BonkUI              "BONKED!" banner and kill feed
    Hud                 ability cooldown bar, Soak % over heads, controls hint
    NoodleMenu          noodle picker with unlock progress
```

## How a hit works

1. `CameraController` keeps your character facing the camera, so turning the
   camera turns you and your noodle.
2. Every client simulates every noodle as a chain of springy points
   (`NoodleSim`). Points near the hand are stiff, the tip lags, so fast turns
   bend the noodle and it wobbles when you stop.
3. On your client, `NoodleController` checks the path each point swept this
   frame. If a point moving faster than `Config.MinHitSpeed` touches someone,
   it sends `Remotes.NoodleHit` with where, which way, and how fast.
4. The server checks the claim: per-target cooldown, reach (noodle length),
   hit position near the target, and that the speed matches how fast it saw
   you turning recently. Faster swings hit harder, up to `FullPowerSpeed`.
5. The target is launched mostly in the direction the noodle was moving,
   scaled by Soak. Their client applies the push (it owns their physics), and
   the server makes their joints floppy for the ragdoll.
6. When anyone falls below `Config.KillY`, `BonkTracker` gives the bonk to the
   last person who hit them within `Config.CreditWindow` seconds.

## Noodles and unlocks

| Noodle | Unlock | Ability (E) |
|---|---|---|
| Classic | Free | none |
| Spaghetti | Bonk 10 | none (super floppy, fast re-hits) |
| Jellyfish | Fall in 15 times | none (stuns on hit) |
| Spring | Bonk 50 | Boing: bounce yourself up |
| Pogo | Bonk 75 | PogoSlam: bounce up, shockwave on landing |
| Frozen | Bonk 100 | none (stiff and heavy) |
| Inflatable | Bonk 150 | Inflate: giant noodle for 6 s |
| Bubble | Fall in 40 times | BubbleTrap: float someone away in a bubble |
| Whip | Bonk 200 | Lash: yank someone toward you |
| Kraken | Bonk 300 | Tentacle: grab and throw someone over your head |

Bonks on practice dummies count toward unlocks **only in Studio**
(`Config.DummyBonksCountInStudio`), so nobody can farm them in a live game.

### Adding a noodle

1. Add an entry to `src/shared/Noodles.luau`. `Stiffness` controls how
   floppy it is (lower = floppier), `Unlock` what it takes to earn it.
2. Optional: set `Ability = "MyAbility"` and add
   `Abilities.MyAbility = function(ctx) ... end` in `src/server/NoodleAbilities.luau`.
3. It shows up in the noodle menu automatically.

To track a new stat for unlocks, add its name to `Unlocks.STATS`, give it a
description in `Unlocks.luau`, and call `DataService.increment(player, "Name", 1)`.

## Tuning tips

- **Hits feel too hard to land:** lower `MinHitSpeed` or raise `HitPadding`.
- **Swings feel weak:** lower `FullPowerSpeed`.
- **Noodles too wobbly / too stiff:** change `NoodleDamping`, or a noodle's `Stiffness`.
- **Noodle points backwards out of the hand:** set `Config.GripSign = -1`.

## Known gaps / next steps

- **Placeholder sounds** in `Config.Sounds`. Swap in squeaky foam and splash sounds.
- **Client-applied knockback.** The victim's client applies its own launch, so
  an exploiter could ignore it. Server-side position checks can come later.
- **Jump bonks.** Jumping moves your noodle fast enough to hit people
  standing right next to you. This is physical and can be fun, but if it
  feels cheap, ignore vertical speed in `NoodleController`.
- **Not built yet:** shop, gamepasses, 3D noodle previews in the menu.
