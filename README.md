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
| P / ADMIN button | Admin panel (admins only) |
| M / MUSIC button | Music on/off |

## 3D models (Blender)

Every model is made in Blender by a script, uploaded to Roblox with Open
Cloud, and loaded by the game at startup:

| Model | Used for |
|---|---|
| NoodleSegment, NoodleTip | every noodle: ridged foam tube with a hollow core, rounded tip |
| PoolDeck | the arena floor look: deck slab, cyan coping lip, tile bands |
| SpawnPad | the spawn platform with a pink star |
| Umbrella | 8-panel scalloped beach umbrellas (2 colors per copy) |
| LoungeChair | pairs of loungers near the middle |
| LifeguardTower | lifeguard tower with a striped roof |
| Crate | wooden crate piles |
| PalmTree | palm trees around the edge |
| BeachBall, SwimRing, RubberDuck | scattered pool toys and a giant duck |

**How it fits together**

- `tools/blender/build_models.py` builds them all and exports FBX files to
  `assets/models/`. Part names start with a color token (`Wood_Leg`), and the
  game colors parts from the palette in `src/shared/ModelAssets.luau`.
- `tools/upload_models.py` uploads changed FBX files as Model assets owned by
  your account and writes their IDs to `src/shared/ModelIds.luau`.
- `src/server/ModelLibrary.luau` loads them with InsertService at startup,
  colors, sizes and stands them up, and puts templates in
  `ReplicatedStorage.ModelLibrary` so clients can use them too.
- If a model can't load, the game uses the old simple parts instead.

**Models only load in a place owned by the account that owns them**
(roboy2911). In a fresh unsaved Studio place you'll see the simple parts. Use
**File > Save to Roblox** (or publish) and run again to see the models.

To change a model: edit `build_models.py`, then rebuild and re-upload:

```bash
blender --background --factory-startup --python tools/blender/build_models.py -- assets/models
```
```bash
python3 tools/upload_models.py
```

The upload needs `ROBLOX_API_KEY` (Open Cloud key with asset read + write)
and `ROBLOX_USER_ID` in the environment. To preview models without Studio:
`blender --background --factory-startup --python tools/blender/render_previews.py -- assets/models previews`.

## Layout

```
src/
  first/                ReplicatedFirst
    LoadingScreen       logo + tips loading screen, waits for the models
  shared/               ReplicatedStorage.Shared
    Config.luau         global tuning (swing speeds, Soak, sim, sounds...)
    Noodles.luau        every noodle: stats, ability, unlock requirement
    Unlocks.luau        unlock rules shared by server and client
    HitQuery.luau       cone/range checks (used by abilities)
    Remotes.luau        RemoteEvents + the KnockbackInfo type
    ModelAssets.luau    model palette, sizes and fit rules
    ModelIds.luau       uploaded model asset IDs (generated)
    NoodleMesh.luau     noodle pieces from the foam mesh
  server/               ServerScriptService.Server
    init.server.luau    entry point
    DataService         DataStore saving: stats, chosen noodle, leaderstats
    CombatService       validates hits and abilities, knockback, Soak
    NoodleAbilities     active abilities, keyed by name
    Ragdoll             floppy ragdoll (Motor6D <-> BallSocket)
    NoodleTools         gives out noodle Tools, handles menu picks
    BonkTracker         detects falls, credits bonks, updates stats
    ModelLibrary        loads the Blender models and makes templates
    ArenaBuilder        the arena: pool deck dressed with the models
    Environment         sunny gameplay lighting
    Streaks             bonk streaks: glow, announcements, bonus for ending one
    DummySpawner        practice dummies (on start, and from the admin panel)
    AdminService        admin access checks and every admin command
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
    AdminPanel          admin panel UI
    AdminMovement       fly and noclip for admins
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

## Arena

`ArenaBuilder` makes a round pool deck `Config.ArenaDiameter` studs wide
(330 by default) floating over water. From the middle out: the spawn pad, 4
benches, 6 beach umbrellas (their tops are solid, so you can land on them),
8 crate piles, then an open edge with a blue stripe. To use your own map,
put a model named `Arena` in Workspace and the builder skips itself.

## Streaks and the kill feed

Bonk people in a row without falling in yourself to build a streak (shown on
the leaderboard). At 3 you're **ON FIRE**, at 5 **UNSTOPPABLE**, at 10
**LEGENDARY**, and every 5 after that it's announced again. Each tier gives
you a glow in its color. Ending someone's streak of 3+ gets announced and
gives you +2 Bonks. Tune it all with `StreakTiers`, `StreakRepeatEvery`,
`StreakEndMinimum` and `StreakEndBonus` in `Config.luau`.

The kill feed stays quiet: it only shows bonks you were part of, plus streak
milestones, ended streaks and admin announcements for everyone.

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

## Admin panel

Press **P** or click **ADMIN** (left side of the screen). Admins are:

- the game's owner (or the owner of the group that owns it),
- anyone whose UserId is in `Config.AdminUserIds`,
- everyone, when playing in Studio.

The server checks admin status on every command, so the panel can't be
abused by someone who isn't an admin. Every command is printed in the server
output.

Pick a player in the list on the left (you're selected by default), then:

| Tab | What's there |
|---|---|
| **Player** | Give any noodle (even locked, for this session) · set or add Bonks/Splashes (saved) · reset all their data · kick · ban 1 day / forever · unban by name or UserId · go to them · bring them · reset their character · launch · max Soak · dry off |
| **Testing** | Toggles for the selected player: unlock all, god mode (can't be hit, falls put you back on the deck), fly (Space up, Q down), noclip, no ability cooldown · set walk speed |
| **Server** | Spawn/clear dummies · announcement banner for everyone (goes through Roblox's text filter) · soak storm · dry everyone · low gravity · launch everyone · respawn everyone · shut down the server |

Risky buttons (kick, ban, reset data, respawn everyone, shut down) need a
second click within 3 seconds. Bans use Roblox's ban API, which only works in
a live game, not in Studio.

## Sounds and music

All audio comes from Roblox's own licensed libraries, which are free to use
in any game: **ProSoundEffects** for effects and **APM** for music. Everything
is listed by name in `Config.Sounds` and `Config.Music`. To swap a sound,
change its Ids (each sound picks one of its Ids at random) or its Volume. Play
one from client code with `Effects.playSound("Name", position?)`.

| Sound | Plays when |
|---|---|
| Swing | your noodle whooshes fast |
| Hit + HitBoink | a noodle lands a hit (wet foam thwack + cartoon boink) |
| Splash | someone falls in the pool |
| Launched | you get bonked (slide whistle) |
| Boing / Slam | Spring and Pogo bounce, Pogo landing |
| BubbleTrap / BubblePop | Bubble ability starts / pops |
| Tentacle / Lash / Inflate | Kraken, Whip and Inflatable abilities |
| Streak / StreakEnded | you hit a streak tier / end someone's streak |
| Unlock | you unlock a noodle |
| Click | menu and panel buttons |
| Announcement | admin announcement (air horn) |

Music shuffles through Beach Party, Pool Party and Maui Beach at low volume.

## Thumbnail scene (Studio only)

`server/ThumbnailScene.luau` builds a frozen, ready-to-screenshot action shot
on the arena: an attacker mid-swing with a bent pink noodle, a shocked victim
flying off the edge toward the camera with a "BONK!" impact star, two players
fighting in the background, one floating in a bubble, one launched into the
sky, and cartoon splashes. It also sets bright saturated lighting and a low
16:9 camera with the top-left left open for your logo. It's **off by default**.

**Take the screenshot**

1. In `src/shared/Config.luau`, set `BuildThumbnailScene = true` and save
   (Rojo syncs it).
2. In Studio, use **Run (F8)**, not Play. Run has no player, so there's no game
   UI at all. The camera jumps to the shot after a second or two.
3. Close or collapse the Explorer, Properties and Output panels and maximize
   Studio so the viewport is as big as possible. For best quality, set
   **File > Studio Settings > Rendering > Editor Quality Level** to the max.
4. Capture the viewport: **Win+Shift+S** (Windows) or **Cmd+Shift+4** (Mac).
   Crop to 16:9 (1920x1080 is what Roblox uses for thumbnails).
5. If you moved the camera by accident, paste this in the Command Bar:
   `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable workspace.CurrentCamera.CFrame = workspace.ThumbnailScene.ThumbnailCamera.CFrame workspace.CurrentCamera.FieldOfView = 55`
6. Press **Stop**, and set `BuildThumbnailScene = false` again before publishing.

Play (F5) works too: the client locks the camera and hides all UI.

**Game icon (square)**

The scene also has an `IconCamera`: a close-up of the grinning attacker with
the noodle and the hit, framed for a square crop.

1. In `Config.luau`, set `ThumbnailShot = "Icon"` (set it back to
   `"Thumbnail"` for the 16:9 shot).
2. **Run (F8)**, hide the panels, and screenshot the middle of the viewport
   as a square (Win+Shift+S / Cmd+Shift+4).
3. Resize it to **512x512** and upload it under Game Settings > Basic Info >
   Game Icon. Roblox rounds the corners, so keep the face away from the edges.
4. To flip cameras while it's running, paste this in the Command Bar
   (swap `IconCamera` for `ThumbnailCamera` to go back):
   `local c = workspace.ThumbnailScene.IconCamera workspace.CurrentCamera.CFrame = c.CFrame workspace.CurrentCamera.FieldOfView = c.FieldOfView`

**Export to Blender for a nicer render**

1. While it's running, select `Workspace > ThumbnailScene` in the Explorer and
   press **Ctrl+C**.
2. Press **Stop**, select **Workspace**, and press **Ctrl+V**. The scene is
   now saved in your place (it disappears from a Run session when you stop).
3. Right-click the pasted `ThumbnailScene` > **Export Selection...** and save
   the `.obj`. Studio writes the `.mtl` and texture images (faces) next to it.
4. In Blender: **File > Import > Wavefront (.obj)**. Then add a sun lamp and
   camera, and render with Cycles or Eevee at any resolution.
5. The water and the "BONK!" text don't export (terrain and GUI). Add a water
   plane in Blender, and put the text on in your image editor.

To move things around, edit the `at(forward, sideways, height)` positions in
`ThumbnailScene.build()`. They're measured from the camera.

## Tuning tips

- **Hits feel too hard to land:** lower `MinHitSpeed` or raise `HitPadding`.
- **Swings feel weak:** lower `FullPowerSpeed`.
- **Noodles too wobbly / too stiff:** change `NoodleDamping`, or a noodle's `Stiffness`.
- **Noodle points backwards out of the hand:** set `Config.GripSign = -1`.

## Publishing checklist

1. Open (or create) a place for Noodle Bonk only, connect Rojo in **Edit
   mode**, and check `Config.luau`: `BuildThumbnailScene = false`.
2. **File > Publish to Roblox** under **roboy2911** (the account that owns the
   models). Run a test server: the Output should say `Loaded 12 Blender models`.
3. **Game Settings**:
   - Security: turn on **Enable Studio Access to API Services** (saving).
   - Avatar: **R15**.
   - Basic Info: name **Noodle Bonk 🏊 Battles**, the description from
     `marketing/description.txt`, icon `marketing/icon_A_512.png`,
     thumbnail `marketing/thumbnail_1920x1080.png`.
   - Permissions: set the game to **Public** when you're ready.
4. Fill in the **Experience Questionnaire** (content maturity) on the Creator
   Hub. Noodle Bonk is cartoon slapstick with no blood.
5. Play a real server with a friend (Test > Clients and Servers, or publish
   and join) to check hits, saving and unlocks.

## Known gaps / next steps

- **Client-applied knockback.** The victim's client applies its own launch, so
  an exploiter could ignore it. Server-side position checks can come later.
- **Jump bonks.** Jumping moves your noodle fast enough to hit people
  standing right next to you. This is physical and can be fun, but if it
  feels cheap, ignore vertical speed in `NoodleController`.
- **Not built yet:** shop, gamepasses, 3D noodle previews in the menu.
