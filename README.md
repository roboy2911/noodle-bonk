# Noodle Bonk 🏊

A Roblox arena brawler. Bonk people off a floating pool deck with pool noodles.
Every noodle has its own power, and every hit makes the victim **soggier**, so
they fly further on the next one.

## Setup

The project uses [Rojo](https://rojo.space). Tool versions are pinned in `rokit.toml`.

```bash
rokit install
```

```bash
rojo serve
```

Then open a place in Studio (the default Baseplate template is fine), connect
with the Rojo plugin, and press Play. With `Config.AutoBuildArena` on, the
server replaces the Baseplate with a test pool deck over water.

## Layout

```
src/
  shared/              ReplicatedStorage.Shared
    Config.luau        global tuning (kill height, lag tolerance, Soak, sounds)
    Noodles.luau       every noodle and its stats
    HitQuery.luau      shared cone/range hit checks
    Remotes.luau       RemoteEvents (server creates, client waits)
  server/              ServerScriptService.Server
    init.server.luau   entry point
    CombatService      validates swings/abilities, applies knockback, Soak
    NoodleAbilities    active abilities (E key), keyed by name
    NoodleTools        builds noodle Tools and gives them out on spawn
    BonkTracker        detects falls, credits bonks, leaderstats
    ArenaBuilder       test arena for empty places
  client/              StarterPlayerScripts.Client
    init.client.luau   entry point
    NoodleController   swing input + ability button
    KnockbackController applies pushes, tumble and stun to your character
    Effects            hit sounds and "BONK!" pop-up text
    BonkUI             "BONKED!" banner and kill feed
```

## How a hit works

1. The client swings (`Tool.Activated`), plays the slash animation, and uses
   `HitQuery.findTargets` to pick who's in front of it.
2. It sends those targets to the server in `Remotes.Swing`.
3. The server re-checks the cooldown, range and arc, with extra tolerance for
   lag (`Config.RangeTolerance`, `ArcToleranceDeg`, `CooldownTolerance`), and
   ignores anyone in a ForceField.
4. For each valid target it adds Soak, works out the launch velocity
   (`Knockback × (1 + Soak/100)`), and remembers who hit them.
5. Player characters are physically owned by their own client, so the server
   sends the velocity to the **victim's** client in `Remotes.Knockback`, and the
   victim applies it. Dummies and NPCs are pushed directly on the server.
6. When anyone falls below `Config.KillY`, `BonkTracker` gives the bonk to the
   last person who hit them within `Config.CreditWindow` seconds.

## Adding a noodle

1. Add an entry to `src/shared/Noodles.luau`.
2. Optional: give it an active ability by setting `Ability = "MyAbility"` and
   adding `Abilities.MyAbility = function(ctx) ... end` in
   `src/server/NoodleAbilities.luau`.
3. Optional: put a custom Tool model in `ServerStorage/NoodleModels/<Id>`.
   Without one, a foam cylinder in the noodle's color is built.

To switch noodles while testing, change the `Noodle` attribute on your Player
(server view, Properties panel) to a noodle Id. You get the new noodle right away.

## Testing with dummies

Make a rig (Avatar tab, Rig Builder), unanchor its parts, and add the tag
`NoodleDummy`. Dummies get knocked around like players and reset to their
starting spot after a bonk.

## Known gaps / next steps

- **Placeholder sounds** in `Config.Sounds`. Swap in squeaky foam and splash sounds.
- **Tumble, not limp ragdoll.** Knockback uses the Humanoid `Physics` state, so
  the body tumbles stiffly. A Motor6D-to-BallSocket ragdoll would be floppier.
- **Grip direction.** If noodles stick out backwards, set `Config.GripSign = -1`.
- **Knockback trust.** The victim's client applies its own knockback, so an
  exploiter could ignore it. Server-side position checks can come later.
- **Not built yet:** saving data, unlocking noodles, a shop, ability cooldown UI.
