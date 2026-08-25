# Zone Companions

*Don't walk the Zone alone.*

---

<!--
  README-NEXUS.txt is this file's twin: the same sections, claims and numbers, in
  BBCode for the Nexus Mods description box. The only content it leaves out is the
  AI note and the referral link immediately below. Change one, change the other.
-->

> [!NOTE]
> **🤖 Fully vibe-coded.** This mod was built entirely with Claude Opus 5, using
> API credits from [Agent Router](https://agentrouter.org/register?aff=C3yz).
> Total cost to code it: **~$160**. If this mod is useful to you and you want to
> support future work, signing up through [my referral link](https://agentrouter.org/register?aff=C3yz)
> gets you **$50 in free API credits** — no obligation, just an option if you were
> going to sign up anyway.

---

**A squad of NPC companions for ZERO Sievert.** Hire them from a contact in the
hub bar, and they spawn beside you at the start of every raid, follow you in
formation, fight what you fight, patch you up when you are hurt, scout ahead with
their own working eyes, and carry their injuries between raids.

Because this is a GMLoader mod, companions run the game's *own* NPC brain — the
same utility AI that makes bandits take cover, flank and reload, and the same
`mp_grid` A\* pathfinding the base game uses. Nothing about their combat is
re-implemented or faked.

Version **1.1.1** · MIT licensed · Source and full docs:
<https://github.com/bobmc1905-jpg/ZoneCompanions>

---

## What your squad does

- **Fights with the game's real AI** — cover, flanking, reloading, target
  selection. Not approximated. This mod contains no combat code at all.
- **Paths properly** — they route around buildings and terrain on the game's own
  A\* navigation grid instead of grinding into walls.
- **Sees for you** — enemies, loot containers and the companions themselves are
  drawn when a companion can see them, even when you cannot, and each companion's
  view cone clears the fog of war exactly like your own.
- **Holds a formation that covers where you are looking** — they sit behind your
  heading, out of your line of fire, but slide toward your cursor so they screen
  the direction you are actually watching.
- **Keeps up with you** — follow speed is derived from your *live* current speed,
  so backpacks, hunter skills and the hub's run bonus cannot leave them trailing.
- **Patches you up** — a companion breaks off to heal you when you are hurt, and
  abandons a firefight to reach you when you are critical. Exactly one claims each
  wound, so the whole squad does not drop formation for the same injury. Charges
  refill every raid.
- **Will not shoot you, and you will not shoot them** — protection runs both ways,
  enforced inside the game's own bullet-collision checks, so a blocked round is
  not wasted and can still hit the enemy behind it.
- **Belongs to your character** — the roster is saved in that character's save
  slot, carries injuries between raids, and is deleted with the save.
- **Behaves naturally when idle** — they drift around their position while you
  stand still, and snap back into formation the moment you move.
- **Tells you what is going on** — a squad panel shows each companion's name,
  health, remaining field dressings and current mode.

---

## Requirements

| | |
|---|---|
| **ZERO Sievert** | tested against **1.2.92** |
| **GMLoader** | tested against **build 34** |
| **Other mods** | none required |
| **Backup** | GMLoader makes a `backup.win` for you — keep your own copy of `data.win` too |

> **This is not a Steam Workshop mod.** GMLoader patches `data.win` directly,
> which is what makes real companion AI possible, and is also why the mod cannot
> be distributed through the Workshop. See [Known issues](#known-issues).

---

## Installation

1. **Install GMLoader** into your ZERO Sievert game folder, next to `data.win`,
   following GMLoader's own instructions. You should end up with `GMLoader.exe`,
   `GMLoader.ini` and a `mods/` folder sitting alongside the game.

   > **Patch the install your launcher actually starts.** On Steam that is
   > usually `…\Steam\steamapps\common\ZERO Sievert\` — not a copy of the game
   > folder kept somewhere else. Patching a copy looks like a complete success in
   > GMLoader's log while the game you actually launch stays vanilla, and because
   > both installs share one save folder it is easy to misdiagnose.

2. **Merge this mod's `mods/` folder into GMLoader's `mods/` folder.** GMLoader
   uses one shared, flat tree — mods do *not* get their own subfolder — so you
   are merging, not replacing:

   ```
   <game folder>/mods/code/gml_GlobalScript_csq_*.gml           (13 files)
   <game folder>/mods/code/gml_Object_obj_csq_companion_*.gml   (3 files)
   <game folder>/mods/code/gml_Object_obj_csq_recruiter_*.gml   (2 files)
   <game folder>/mods/config/new_object/obj_csq_companion.json
   <game folder>/mods/config/new_object/obj_csq_recruiter.json
   <game folder>/mods/config/code_patch/10_zone_companions.yaml
   ```

   Those three destinations are `GMLCodeDirectory`, `NewObjectDirectory` and
   `GMLCodePatchDirectory` in `GMLoader.ini`. 21 files in total.

3. **Run GMLoader** from the game folder. It wants a real console window, so if
   you launch it from a script rather than by double-clicking:

   ```bash
   powershell -NoProfile -Command "Start-Process -FilePath 'GMLoader.exe' -WorkingDirectory (Get-Location).Path"
   ```

4. **Check `GMLoader.log`** for a successful save and no errors. If it stopped on
   a hash mismatch, see [below](#if-gmloader-refuses-on-a-hash-check).

5. **Launch the game.** On first run the mod writes a fully commented reference of
   every setting to `%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini`, and an empty
   `csq_config_user.ini` next to it for your own changes.

### Re-patching after a game update

GMLoader always recompiles from `backup.win`, and a game update replaces
`data.win`. After any update: delete the stale `backup.win`, let GMLoader make a
fresh one, and re-run it.

### If GMLoader refuses on a hash check

GMLoader ships with the hash of the `data.win` it was built against. Different
builds of the same game version can hash differently, which is not corruption.
Fix it by **updating the expected hash**, not by disabling the check:

1. Get your own hash with the bundled `GMLoader - Utility/GMLoader - xxHash.exe`
2. Put that value into `GMLoader.ini` as `SupportedDataHash`
3. Leave `CheckHash=true`, and set `AutoDeleteBackup=false`

> **Do not just set `CheckHash=false`.** With the check off GMLoader never
> creates `backup.win`, so it has nothing pristine to recompile from and no way
> to undo a patch.

---

## Controls

| Default key | Action |
|---|---|
| **F** | Standing next to the recruiter, open the hire menu. Does nothing anywhere else |
| **F5** | Show or hide the squad panel |
| **F7** | Dismiss the companion nearest you, permanently |
| **F8** | Toggle the whole squad between Follow and Hold |
| **F9** | Dump full squad state to the log — use this when reporting a bug |
| **F6** | *Debug only:* add one free companion from `default_preset`. Requires `debug_enabled` |

In the hire menu: **W**/**S** to choose, **Enter** to buy, **Backspace** to close.

All six are rebindable under `[input]` in the config, as GameMaker virtual key
codes. Function keys are the defaults specifically because they cannot collide
with the game's movement and inventory bindings; a bare F5–F9 press reaches
nothing in vanilla.

**F is the deliberate exception.** It is the game's own Interact key, because
talking to the recruiter should feel like talking to any other NPC. Both actions do
fire on one press — a mod cannot consume a key press on the base game's behalf — but
vanilla's Interact only does anything inside an interactable's own range, and the
recruiter's corner of the bar is not one. And because F is a key you press
constantly, the recruit action is a no-op away from the recruiter.

Commands are ignored while the Steam overlay is up, and while you are in a menu,
dialogue, the inventory, the PDA, crafting, sleeping, dead, or riding the intro
train — so nothing fires behind a UI.

### Hiring companions

Companions are **bought**, from a hireable-labour contact who stands in the hub bar
under a floating *Labour Contracts* label. Walk up, press **F**, and pick a tier:

| Tier | Price | What you get |
|---|---|---|
| **Rookie** | 2 500 ₽ | The `loner_novice` preset at baseline health |
| **Veteran** | 6 000 ₽ | `loner_regular`, 1.75× health |
| **Elite** | 12 000 ₽ | `loner_regular`, 3× health |

The tier is not cosmetic: the preset is where the game gets an NPC's reflexes,
health and weapon setup, so a more expensive companion genuinely fights better.
Names, prices, presets and multipliers are all configurable, and you can point a
tier at the bandit ladder (`bandit_veteran`, `bandit_master`) for smarter AI at the
cost of looking like a bandit.

Money is taken through the game's own trader transfer, so a hire shows up in your
rouble count exactly like any other purchase. The menu refuses with a reason when
you cannot afford a tier or the roster is already at `max_companions`. In a raid a
new companion appears beside you; in the hub they join the roster for your next
raid.

`key_debug_spawn` (**F6**) still creates a free companion from `default_preset`,
ignoring price and the recruiter entirely — but only while `debug_enabled` is on. It
is a testing tool, not the intended way to build a squad.

### What your companions can see

Companions have working eyes, and what they see counts as something you can see:

- **Anything inside a companion's vision cone is drawn** — enemies, loot containers,
  and the companions themselves. This is not cosmetic: the base game walks every
  raid NPC's alpha down to zero outside *your* line of sight, so before this a
  companion twenty metres ahead was literally not rendered, and neither was their
  flashlight.
- **Each cone also clears the fog of war**, inside the game's own subtract pass, so
  it opens the map up exactly the way your own cone does. No coloured overlays.
- **The cone is the real one** — the same triangle the companion's AI searches for
  targets, built from its weapon direction, alert radius and visual distance,
  including the day/night penalty. What gets revealed is precisely what that
  companion could actually shoot at.

Optional white position pins (`reveal_companions`) mark companions through fog and
walls, with an edge arrow when they are off screen. Off by default, because a
companion standing in fog it cleared itself is already visible. All of it is
switchable in `[reveal]`.

### Companion modes

| Mode | Behaviour |
|---|---|
| **Following** | Paths to a formation slot around you, drifting within `roam_radius` of it while you stand still |
| **Fighting** | A hostile is within `engage_radius` of you — the vanilla combat AI takes over completely |
| **Healing** | On its way to patch you up, or doing it |
| **Holding** | Stays put, but still returns fire |

Priority is **Healing → Fighting → Holding → Following**. Fighting outranks
Holding, so a companion told to hold position will still defend itself. Healing
outranks Fighting only for a *critical* wound (`heal_emergency_threshold`);
otherwise it finishes the firefight first.

The panel in the top-left shows each companion's name, HP, remaining field
dressings (`+2`) and current mode. Companions carry their damage out of a raid
and back into the next one, and the roster travels with the character's save
slot.

---

## Configuration

There are two files, both beside your saves:

```
%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini        generated — do not edit
%LOCALAPPDATA%\ZERO_Sievert\csq_config_user.ini   yours
```

`csq_config.ini` is a **generated reference**: all **97 settings**, each with its
current default and a comment explaining it. It is rewritten from scratch every
launch, so it always matches the version you are running — which means a mod update
can never leave you with a config file that quietly lacks its new settings.

`csq_config_user.ini` is **yours**. Put in it only the lines you want to change:

```ini
max_companions = 4
hp_multiplier = 2
recruit_tier1_price = 1500
```

Save, then **restart the game** — config is read once at boot. The mod never
overwrites this file.

**Nothing to do when you update.** Coming from 1.0.0, your old settings are moved
into the new user file automatically on the first launch. And if you edit the
generated file out of habit, the mod moves those lines into your user file for you,
applies them that same launch, and says so in the log.

For the full reference — grouped, with defaults and tuning recipes — see
**[CONFIGURATION.md](CONFIGURATION.md)**.

The eleven sections at a glance:

| Section | Controls |
|---|---|
| `[debug]` | Logging verbosity, the debug overlay. **Off by default.** |
| `[squad]` | Squad size, the NPC preset used, spawning, toughness |
| `[follow]` | Formation shape, follow distances and speeds, teleport rescue |
| `[roam]` | Idle drift around the formation slot |
| `[combat]` | Engagement range, aggression, faction standings |
| `[ff]` | Friendly fire in both directions, grenade disarming |
| `[medic]` | Whether and when companions heal you, and how much |
| `[hud]` | Squad panel position, size and contents |
| `[reveal]` | What your companions' vision reveals, and how strongly |
| `[recruit]` | The recruiter NPC, the three tiers, their prices, menu keys |
| `[input]` | The six keybinds |

> `csq_` is the mod's internal namespace prefix. It shows up in the config
> filename, the log filename and the log lines. It is kept short deliberately:
> GMLoader loads every mod into one shared flat folder, so a short unique prefix
> is what stops two mods colliding.

---

## Logging

The mod writes a fresh log every launch to:

```
%LOCALAPPDATA%\ZERO_Sievert\logs\csq_log.txt
```

Four levels — `0` ERROR, `1` WARNING, `2` INFO (default), `3` DEBUG. DEBUG also
requires `debug_enabled = true`, so raising `log_level` alone will not flood the
file.

**Reporting a problem?** Set `log_level = 3` and `debug_enabled = true`, restart,
reproduce the issue, press **F9**, and attach `csq_log.txt`. F9 works regardless
of the debug settings, precisely so it is available without editing the config
first.

---

## Compatibility

- **Saves:** safe to add to an existing character, and safe to remove. Roster data
  lives in its own section of the save that the base game never reads, so leftovers
  after uninstalling are harmless.
- **Other GMLoader mods:** should coexist. Everything the mod adds lives in its own
  uniquely-prefixed scripts and its own new objects, and it touches base-game code
  in only nine places. The two worth knowing about are the bullet-collision
  predicates `bullet_can_collide_with_player` and `bullet_can_collide_with_npc` —
  another mod that rewrites those specific functions could conflict. Each patch is
  applied independently, so a clash disables that one patch and logs a warning
  rather than breaking the build.
- **Steam Workshop mods:** the Workshop mod system and GMLoader work differently
  and do not know about each other. Running both is generally fine, but a Workshop
  companion or follower mod alongside this one is asking for trouble.
- **Not compatible with:** any mod that also replaces those two bullet-collision
  predicates.

---

## Known issues

- **Not Steam Workshop distributable.** GMLoader rewrites `data.win`. That is
  inherent to the approach, and was the accepted trade-off for getting real AI
  and real pathfinding.
- **Must be re-applied after every game update**, because the update replaces the
  file GMLoader patched.
- **All companions of a tier use one NPC preset.** Per-companion presets are stored
  in the roster and honoured on load, so a mixed squad works, but the choice is per
  *tier* rather than per hire.
- **Wall shadows are cast from your position, not your companion's.** Inside ground
  a companion has revealed, the fog shader still draws shadows relative to you. The
  base game hands that shader exactly one light position and giving each companion
  its own would mean an extra shader pass per companion. The ground is revealed
  correctly; only the direction the shadows fall is wrong.
- **Companions carry no inventory** and cannot be given gear. They spawn with
  whatever their preset's weapon setup gives them. Medic charges are an abstract
  per-raid count, not an item — healing consumes nothing from anyone's bag.
- **Companions cannot throw grenades** while `ff_no_grenades` is on (the
  default). This is blunt on purpose: grenade damage in this game has no faction
  check of any kind, so there is no way to let them throw *and* keep you safe.
- **The medic does not treat wounds.** It restores HP and stops bleeding, exactly
  like an NPC medic's dialogue heal. The `wound` stat needs medication, and the
  mod deliberately never touches it.

---

## Uninstalling

1. Delete this mod's 21 files from the `mods/` tree.
2. Re-run GMLoader to rebuild a clean `data.win` from `backup.win`.

Optionally also delete `%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini`,
`csq_config_user.ini` and `logs\csq_log.txt`.

Leftover roster data in a save is harmless — it lives in its own section that the
base game never reads.

---

## Permissions

Released under the **MIT Licence** — see [LICENSE](LICENSE). The list below simply
restates it in the terms mod sites ask for. In short: do what you like with it,
just credit the original and link back.

- **Use it in your own mods:** yes. Take the code, the approach, whole modules,
  whatever is useful.
- **Modify and re-upload:** yes, anywhere, including Nexus Mods — credit the
  original and link back to this repository or the Nexus page.
- **Fix it or update it for a newer game version:** yes, and you do not need to ask
  first. If I have gone quiet and the mod is broken, please do.
- **Translate it:** yes, with credit.
- **Include it in a modpack or compilation:** yes, with credit.
- **Convert it to another game or another loader:** yes, with credit.
- **Credit required:** yes, in all of the above. Name the original mod and link
  back — that is the only condition.

Only ask that you do not present it as your own original work, and that if you fork
it publicly you keep the MIT licence notice with it.

---

## Credits

- **Bobby** — mod author
- **Senjay-id** — [GMLoader](https://github.com/Senjay-id/GMLoader), without which
  this mod could not exist
- **The Underminers team** —
  [UndertaleModTool](https://github.com/UnderminersTeam/UndertaleModTool), which
  GMLoader uses to recompile the game
- **The ZERO Sievert modding community** — for mapping out the game's internals
- **CABO Studio** — for ZERO Sievert itself, published by Modern Wolf

Changes in each release are listed in [CHANGELOG.md](CHANGELOG.md).

*Released under the MIT Licence — © 2026 Bobby*
