# Zone Companions — Configuration Reference

Every tunable value in the mod, with its default and what it actually does.

**Where the file lives**

```
%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini
```

It is generated on first launch and is **never rewritten afterwards**, so your
edits are safe. Delete the file to regenerate it with defaults.

**How to change a setting**

1. Edit the value
2. Save
3. **Restart the game** — the file is read once at boot

**If a key is missing or misspelled** the mod falls back to that setting's default
and logs a warning naming how many keys were absent. Nothing breaks and your file
is not modified.

**Types.** `bool` accepts `true`/`false`, `yes`/`no`, `on`/`off` or `1`/`0` in any
casing. `real` is a number; a non-numeric value is rejected in favour of the
default rather than being fed into the mod as `NaN`. Section headers are cosmetic
— key names are globally unique, so a key is found whichever section it sits under.

---

## `[debug]` — 5 settings

Everything here is off or quiet by default. You only need this section when
something has gone wrong.

| Setting | Default | What it does |
|---|---|---|
| `debug_enabled` | `false` | Master switch for DEBUG-level logging and the on-screen debug text. Required for either; raising `log_level` alone will not produce DEBUG output. |
| `log_level` | `2` | `0` = ERROR only, `1` = + WARNING, `2` = + INFO, `3` = + DEBUG. |
| `log_to_file` | `true` | Write the log to `logs/csq_log.txt` in the save folder. Truncated fresh every launch. |
| `log_to_trace` | `true` | Also send every line to the game's own `trace()` output. |
| `draw_debug_overlay` | `false` | Draw a per-companion diagnostic line under each panel row. Also needs `debug_enabled`. |

### Reading the debug overlay

Each companion gets one extra line, kept deliberately narrow because the panel
lives in 480×270 GUI space:

```
no_move/no_move t- d34 s1.75 h0 r12,-8
```

| Field | Meaning |
|---|---|
| `no_move/no_move` | vanilla `state` / `human_state_now`, with the `human_` prefix stripped |
| `t` | `Y` if the companion has a target, `-` if not |
| `d` | distance to the player, in pixels |
| `s` | current `path_speed` |
| `h` | frames left on the heal cooldown |
| `r` | current roam offset from the formation slot |

Target is shown as a flag rather than the raw instance id, which says nothing
once you know a target exists. **F9** logs the real ids.

### Reporting a bug

Set `log_level = 3` and `debug_enabled = true`, restart, reproduce, press **F9**,
and attach `csq_log.txt`. F9 works regardless of these settings, on purpose — the
tool you reach for when something is broken must not require a config edit first.

---

## `[squad]` — 8 settings

| Setting | Default | What it does |
|---|---|---|
| `max_companions` | `3` | How many companions may be active at once. 1–8 is sane. |
| `default_preset` | `loner_regular` | The NPC preset companions are built from. Must exist in the game's `gamedata/npc.json`. |
| `auto_spawn_in_raid` | `true` | Respawn the saved roster automatically when a raid map loads. Off means you spawn them by hand with F6. |
| `spawn_offset` | `24` | Pixels from the player to start looking for a free spawn cell. |
| `spawn_delay_frames` | `30` | Frames to wait after a map loads before spawning. Only a floor — the mod additionally waits for the navigation grid and for you to be out of the raid intro, so a slow machine is handled regardless. |
| `respawn_on_death` | `false` | `false` = a fallen companion is gone for good. `true` = they return at the start of the next raid. |
| `recover_deactivated` | `true` | Reactivate and pull back companions the game culls for being too far away. Only turn this off if it conflicts with another mod. |
| `hp_multiplier` | `1.5` | Multiplies starting health. `loner_regular` has 60 HP, so `1.5` gives 90. The game's own difficulty scaling still applies on top. `1` is vanilla-fair, and dies fast — a companion fighting at your side takes far more incoming fire than a patrolling mook ever does. |

---

## `[follow]` — 14 settings

### Formation geometry

| Setting | Default | What it does |
|---|---|---|
| `follow_distance` | `32` | Desired standoff distance from the player, in pixels. |
| `formation_spread` | `26` | How far apart companions fan out around the follow point. |
| `catchup_distance` | `40` | Distance from its own slot at which a companion switches to catch-up speed. |
| `arrive_distance` | `10` | Inside this distance **of its slot**, a companion stops and holds position. |
| `goal_move_threshold` | `8` | You must move this far before the formation slot is retargeted. Stops slot jitter while you shuffle on the spot. |

### Aim lead

The formation sits *behind* your heading, which is what keeps companions out of
your line of fire — but on its own it also means they hang back by your shoulders
and never screen the direction you are actually watching. These slide the whole
formation toward your cursor.

| Setting | Default | What it does |
|---|---|---|
| `aim_lead` | `26` | Pixels the formation slides toward where you are aiming. `0` is off — companions sit purely behind you. Around `follow_distance` puts them level with you on the side you are covering. Much higher pushes them out in front as a screen. |
| `aim_lead_smooth` | `0.08` | How quickly they follow the cursor, per frame. `0.01` slow, `1` instant. Low values stop a flicked mouse making the squad jitter. |

### Speed

Follow speed is the **greater of two terms**, re-evaluated every frame:

- the preset's own alerted speed × `speed_walk_mult` / `speed_run_mult`
- **your actual current speed** × `speed_match_mult` / `speed_catchup_mult`

The second term is what keeps them with you. Player walk is about 0.75 px/step
and run about 1.2, but backpacks, hunter skills and the hub's run bonus all raise
that — so it is read off you live rather than assumed.

| Setting | Default | What it does |
|---|---|---|
| `speed_walk_mult` | `1.05` | Multiplier on the preset's alerted speed, used as the cruising floor. |
| `speed_run_mult` | `2.6` | Multiplier on the preset's alerted speed, used as the catch-up floor. |
| `speed_match_mult` | `1.15` | Cruising speed as a multiple of your **current** speed. Must be `> 1` or gaps never close. |
| `speed_catchup_mult` | `1.75` | Catch-up speed as a multiple of your current speed. **Raise this first if companions still lag behind.** |
| `speed_max` | `3.0` | Hard ceiling in pixels per step, so nothing ever looks like it is teleporting. |

### Teleport rescue

A last resort for a companion genuinely stuck behind geometry. Both conditions
must hold.

| Setting | Default | What it does |
|---|---|---|
| `teleport_distance` | `400` | Only consider teleporting beyond this distance. `0` disables teleporting entirely. |
| `teleport_fail_frames` | `90` | Frames of *continuous* pathing failure required first. 90 is about 1.5 seconds. |

---

## `[roam]` — 4 settings

Companions drift around their formation slot instead of standing to attention.

> **Roaming is suppressed while you are moving, on purpose.** The follow logic was
> tuned specifically to stop companions trailing behind; adding a random offset to
> a target that is already moving away would hand that problem straight back.

| Setting | Default | What it does |
|---|---|---|
| `roam_enabled` | `true` | Let companions wander around their slot while you are still. |
| `roam_radius` | `40` | How far from the slot a companion may drift, in pixels. |
| `roam_interval` | `90` | Frames between new wander destinations. 90 is about 1.5 seconds. |
| `roam_max_player_speed` | `0.3` | Roaming stops once you move faster than this, in px/step. Player walk is about 0.75, so `0.3` effectively means "only while standing still". Raise it to keep roaming on the move, at the cost of a looser formation. |

---

## `[combat]` — 7 settings

| Setting | Default | What it does |
|---|---|---|
| `engage_radius` | `420` | Companions ignore enemies further than this from **you**. Roughly a screen width; the game deactivates NPCs past about 480 px anyway. This doubles as the vanilla aggro leash radius. |
| `engage_advance` | `96` | How far toward an enemy a companion may push while fighting, in pixels. `0` makes them hug you. Raise for a more aggressive push, lower to keep them close. |
| `disengage_frames` | `150` | Frames without a target before a companion returns to following. Higher keeps them in a fight through brief losses of line of sight. |
| `scan_interval` | `4` | Frames between target scans while following. Lower = faster reactions, more CPU. |
| `mirror_player_relations` | `true` | Copy your own faction standings, so companions fight whoever you fight. Turn off to give the Companion faction fixed standings instead. |
| `rep_ally` | `1000` | Reputation written for allies. The game counts anything above 600 as an ally. |
| `rep_hostile` | `0` | Reputation written for enemies. The game counts anything below 250 as hostile. |

> `rep_ally` and `rep_hostile` are validated at boot against those thresholds. A
> value on the wrong side of them is reported in the log rather than silently
> producing companions that will not fight.

---

## `[ff]` — 3 settings

Friendly fire. The two bullet settings are enforced inside vanilla's **own**
collision predicates, which means a blocked round is not consumed — it passes
through and can still hit the enemy behind.

| Setting | Default | What it does |
|---|---|---|
| `ff_protect_player` | `true` | Companion bullets pass harmlessly through you. |
| `ff_protect_companions` | `true` | Your bullets pass harmlessly through companions. Turn off if you want to be able to shoot your own squad. |
| `ff_no_grenades` | `true` | Stop companions throwing grenades at all. |

> `ff_no_grenades` is blunt because it has to be: grenade damage in this game has
> **no faction check of any kind**, so there is no way to let companions throw and
> keep you safe. The preset carries live RGD grenades and flashbangs, so this is
> disarmed at spawn rather than filtered at the point of damage.

---

## `[medic]` — 9 settings

Thresholds are fractions of your **current** maximum HP, which the game
recomputes every frame as `hp_max_total - wound`. So a wounded player sitting at
full effective health counts as full and is not healed — closing a wound takes
medication, and the mod never touches `wound`.

| Setting | Default | What it does |
|---|---|---|
| `heal_enabled` | `true` | Let companions heal you when you are hurt. |
| `heal_threshold` | `0.85` | Heal once your health drops below this fraction of maximum. `1` = heal any damage at all. |
| `heal_emergency_threshold` | `0.35` | Below this fraction, a companion **abandons a firefight** to reach you. Above it, it finishes the fight first. |
| `heal_amount` | `25` | HP restored per heal. Never takes you above your current maximum. |
| `heal_charges` | `2` | Heals each companion carries. Refilled at the start of every raid. |
| `heal_cooldown_frames` | `600` | Frames a companion waits between heals. 600 is 10 seconds at 60 fps. |
| `heal_range` | `24` | How close a companion must get before it can heal, in pixels. |
| `heal_stop_bleed` | `true` | Also stop bleeding, the way an NPC medic's dialogue heal does. |
| `heal_message` | `true` | Show an on-screen message when a companion patches you up. |

> Exactly **one** companion claims each wound. Without that, every companion in
> the squad would break formation for the same injury. Charges live on the roster
> entry rather than the instance, so being culled and respawned cannot silently
> refill them. `+0` is shown on the panel rather than hidden, so a companion that
> has stopped healing you looks out of charges rather than broken.

---

## `[hud]` — 6 settings

Coordinates are in the game's 480×270 GUI space, not screen pixels.

| Setting | Default | What it does |
|---|---|---|
| `hud_enabled` | `true` | Show the squad panel at all. When `false`, the F5 toggle does nothing (and says so in the log). |
| `hud_x` | `6` | Left edge of the panel, 0–480. |
| `hud_y` | `40` | Top edge of the panel, 0–270. |
| `hud_line_height` | `10` | Vertical spacing per row. Scaled by `hud_scale` too. |
| `hud_scale` | `1` | Text size for the whole panel, clamped to 0.25–4. `1` is the game's smallest UI font at native size. `0.75` fits more on screen but looks ragged, because that font is a bitmap generated with antialiasing off. |
| `hud_show_hp` | `true` | Append current/max HP to each row. |

> The F5 visibility state is **not saved**. The config file is only ever written
> when it is missing, so persisting it would mean rewriting your own ini behind
> your back. The panel is therefore visible again on every launch.

---

## `[input]` — 5 settings

Values are **GameMaker virtual key codes**, not letters:

- `F1`–`F12` = `112`–`123`
- `A`–`Z` = `65`–`90`
- `0`–`9` = `48`–`57`

Set a binding to `0` (or anything outside 1–255) to disable that command.

| Setting | Default | Key | What it does |
|---|---|---|---|
| `key_toggle_hud` | `116` | F5 | Show or hide the squad panel. Resets to shown every launch. |
| `key_recruit` | `117` | F6 | Add a new companion built from `default_preset`. In a raid they appear beside you; in the hub they join the roster for your next raid. Does nothing once the roster holds `max_companions`. |
| `key_dismiss` | `118` | F7 | Dismiss the companion nearest you, permanently. |
| `key_toggle_hold` | `119` | F8 | Toggle the whole squad between Follow and Hold. |
| `key_debug_dump` | `120` | F9 | Dump full squad state to the log. Works regardless of the `[debug]` settings. |

> **F6 does not convert a nearby NPC.** There is no proximity check and no
> existing NPC is involved — it creates a fresh companion from the configured
> preset.

Function keys are the defaults because they cannot collide with the game's
movement and inventory bindings. This was checked rather than assumed: vanilla
only ever reads F5 and F6 *with* a modifier, so a bare F5–F9 press reaches nothing
in the base game.

Commands are suppressed while the Steam overlay is up, and while your player state
is any of inventory, PDA, talk, craft, item spawn, sleep, dead, raid start,
dummy, free camera or teleport. An unrecognised state **allows** commands — the
failure mode being avoided is "keys silently never work", which is far worse than
a command firing during a state nobody classified.

---

## Tuning recipes

**"They keep falling behind."**
Raise `speed_catchup_mult` (try `2.2`), then `speed_max` (try `4`). Those two
govern the term that tracks your live speed, which is the one that matters.

**"They get in my line of fire."**
Lower `aim_lead` toward `0` so they sit purely behind you, and raise
`follow_distance`. Keep `ff_protect_companions = true`.

**"They wander off and get killed."**
Lower `engage_advance` toward `0` and lower `engage_radius`. Both also tighten the
vanilla aggro leash.

**"They are too strong / too weak."**
`hp_multiplier` — `1` is vanilla-fair, `1.5` is the default, `3` makes them
genuinely tanky. Difficulty scaling applies on top either way.

**"I want a lone bodyguard, not a squad."**
`max_companions = 1`, `hp_multiplier = 2.5`, `heal_charges = 4`,
`follow_distance = 24`.

**"I want them to fight, not babysit me."**
`heal_enabled = false`, `engage_advance = 160`, `engage_radius = 480`,
`roam_max_player_speed = 1.5`.

**"I want a stealthier game with no HUD."**
`hud_enabled = false`. Companions still work; you just lose the readout.
