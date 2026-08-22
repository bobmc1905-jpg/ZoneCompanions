# Zone Companions

**A squad of NPC companions for ZERO Sievert.** They spawn beside you at the
start of every raid, follow you in formation, fight what you fight, patch you up
when you are hurt, and carry their injuries between raids.

Because this is a GMLoader mod, companions run the game's *own* NPC brain — the
same utility AI that makes bandits take cover, flank and reload, and the same
`mp_grid` A\* pathfinding the base game uses. Nothing about their combat is
re-implemented or faked.

Version **1.0.0** · MIT licensed · Source and full docs:
<https://github.com/bobmc1905-jpg/zone-companions>

---

## Requirements

| | |
|---|---|
| **ZERO Sievert** | tested against **1.2.92** |
| **GMLoader** | tested against **build 34** |
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
   <game folder>/mods/code/gml_GlobalScript_csq_*.gml          (11 files)
   <game folder>/mods/code/gml_Object_obj_csq_companion_*.gml  (3 files)
   <game folder>/mods/config/new_object/obj_csq_companion.json
   <game folder>/mods/config/code_patch/10_zone_companions.yaml
   ```

   Those three destinations are `GMLCodeDirectory`, `NewObjectDirectory` and
   `GMLCodePatchDirectory` in `GMLoader.ini`. 16 files in total.

3. **Run GMLoader** from the game folder. It wants a real console window, so if
   you launch it from a script rather than by double-clicking:

   ```bash
   powershell -NoProfile -Command "Start-Process -FilePath 'GMLoader.exe' -WorkingDirectory (Get-Location).Path"
   ```

4. **Check `GMLoader.log`** for a successful save and no errors. If it stopped on
   a hash mismatch, see [below](#if-gmloader-refuses-on-a-hash-check).

5. **Launch the game.** On first run the mod writes a fully commented config file
   to `%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini`.

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
| **F5** | Show or hide the squad panel |
| **F6** | Add a companion (built from `default_preset`) |
| **F7** | Dismiss the companion nearest you, permanently |
| **F8** | Toggle the whole squad between Follow and Hold |
| **F9** | Dump full squad state to the log — use this when reporting a bug |

All five are rebindable under `[input]` in the config, as GameMaker virtual key
codes. Function keys are the defaults specifically because they cannot collide
with the game's movement and inventory bindings; a bare F5–F9 press reaches
nothing in vanilla.

Commands are ignored while the Steam overlay is up, and while you are in a menu,
dialogue, the inventory, the PDA, crafting, sleeping, dead, or riding the intro
train — so nothing fires behind a UI.

### What F6 actually does

F6 **creates a new companion** from the `default_preset` setting. It does *not*
convert a friendly NPC standing near you — there is no proximity check and no
existing NPC is involved. In a raid the new companion appears beside you; in the
hub they join the roster and turn up at the start of your next raid. Once the
roster holds `max_companions`, F6 does nothing (and says so in the log).

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

The config file is generated on first launch at:

```
%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini
```

Edit a value, save, and **restart the game** — the file is read once at boot.
Delete the file to regenerate it with defaults.

Every one of the **61 settings** carries its own explanatory comment inside that
generated file, so the ini is self-documenting. For the full reference —
grouped, with defaults and tuning advice — see **[CONFIGURATION.md](CONFIGURATION.md)**.

The nine sections at a glance:

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
| `[input]` | The five keybinds |

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

## Known issues

- **Not Steam Workshop distributable.** GMLoader rewrites `data.win`. That is
  inherent to the approach, and was the accepted trade-off for getting real AI
  and real pathfinding.
- **Must be re-applied after every game update**, because the update replaces the
  file GMLoader patched.
- **All companions use one NPC preset.** Per-companion presets are stored in the
  roster and honoured on load, but F6 always creates the configured default.
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

1. Delete this mod's 16 files from the `mods/` tree.
2. Re-run GMLoader to rebuild a clean `data.win` from `backup.win`.

Optionally also delete `%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini` and
`logs\csq_log.txt`.

Leftover roster data in a save is harmless — it lives in its own section that the
base game never reads.

---

## Credits and licence

Made by **Bobby**.

Built on [GMLoader](https://github.com/Senjay-id/GMLoader) by Senjay-id, without
which none of this would be possible. GMLoader in turn recompiles `data.win`
using [UndertaleModTool](https://github.com/UnderminersTeam/UndertaleModTool) by
the Underminers team. Thanks to the ZERO Sievert modding community for mapping
out the game's internals.

Released under the **MIT Licence** — see [LICENSE](LICENSE). You may reuse, fork
and redistribute this, including in your own mods, as long as you credit the
original and link back.

Changes in each release are listed in [CHANGELOG.md](CHANGELOG.md).
