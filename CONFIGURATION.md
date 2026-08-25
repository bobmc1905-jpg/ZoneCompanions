# Zone Companions — Configuration Reference

Every tunable value in the mod, with its default and what it actually does.

## The two config files

Both live beside your saves:

```
%LOCALAPPDATA%\ZERO_Sievert\csq_config.ini        generated — do not edit
%LOCALAPPDATA%\ZERO_Sievert\csq_config_user.ini   yours
```

**`csq_config.ini` is a generated reference.** It lists every setting the running
version has, with its current default and a one-line description, and it is
**rewritten from scratch every time the game starts**. Read it, copy from it, but do
not edit it — your changes there will not stick.

**`csq_config_user.ini` is yours.** It is created once, as a template with
everything commented out, and the mod never overwrites it. Put in it *only* the
lines you want to change:

```ini
max_companions = 4
hp_multiplier = 2
recruit_tier1_price = 1500
```

Anything you do not list uses the default. Section headers are optional — key names
are globally unique, so a key works wherever you put it.

### Why two files

A single file cannot be both up to date and safe to keep your edits in. The old
one-file version was only written when it was missing, which is the only way to
avoid clobbering your settings — but it also meant a mod update could never reach
it. Every setting added after your file was created was simply absent from it, and
every default changed since was still described wrongly. 1.0.0 had 61 settings and
1.1.0 has 97, so an upgrading player would have seen none of the 36 new ones.

Split in two, the reference is disposable and therefore always correct, and your
overrides are a short list you wrote yourself that no update touches.

### Nothing to do when you update

- **Coming from 1.0.0:** your old `csq_config.ini` settings are moved into a new
  `csq_config_user.ini` automatically on the first launch. Nothing to re-type.
- **If you edit `csq_config.ini` out of habit:** the mod notices, moves those lines
  into your user file for you, applies them immediately, and says so in
  `logs/csq_log.txt`. Nothing is lost.

**How to change a setting**

1. Add or edit the line in `csq_config_user.ini`
2. Save
3. **Restart the game** — config is read once at boot

**If a key is misspelled** the mod ignores it and logs a warning naming it. Nothing
breaks and your file is not modified.

**Types.** `bool` accepts `true`/`false`, `yes`/`no`, `on`/`off` or `1`/`0` in any
casing. `real` is a number; a non-numeric value is rejected in favour of the
default rather than being fed into the mod as `NaN`.

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
| `auto_spawn_in_raid` | `true` | Respawn the saved roster automatically when a raid map loads. Off means they stay on the roster until you spawn them by hand with the debug spawn key. |
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

> The F5 visibility state is **not saved**. It is a runtime toggle, not a setting —
> the mod never writes to your `csq_config_user.ini`, so persisting it would mean
> editing your file behind your back. The panel is therefore visible again on every
> launch.

---

## `[reveal]` — 7 settings

What your companions can see, and how much of it you get to see. There are two
independent mechanisms here, because the base game hides things in two different
ways.

**1. Sprites are faded out, not merely darkened.** For every NPC in a raid, every
frame, the base game asks `player_line_of_sight(x, y)` and walks that instance's
`image_alpha` down to `0` when the answer is no. Containers get the same treatment.
So a companion behind you is not dim, it is not drawn at all — and its flashlight
goes with it, because the torch object scales its light by its owner's alpha. That
is `reveal_squad_sight`, which makes a companion's line of sight count as yours.

**2. The ground is painted black.** Fog of war is an opaque black surface with your
view wedge *subtracted* out of it. That is `reveal_view_cone`, which subtracts each
companion's wedge from the same surface, in the same pass.

Both use the same triangle the companion's own AI searches for targets — apex at
the companion, edges at its weapon direction ± half its alert radius, length its
visual distance after the day/night penalty. If it is not in that triangle, the
companion genuinely cannot see it, so what is revealed is exactly the ground they
are watching.

| Setting | Default | What it does |
|---|---|---|
| `reveal_squad_sight` | `true` | Let what your companions can see count as something you can see: the companion itself, its flashlight, and anyone standing in its field of view. **This is the setting that stops a companion behind you being invisible.** |
| `reveal_view_cone` | `true` | Let each companion's field of view clear the fog of war, the same way yours does. |
| `reveal_cone_strength` | `1` | How completely a companion clears the fog, `0`–`1`, applied to both the cone and the glow. `1` matches your own vision; lower leaves what they reveal dimmer than what you do. |
| `reveal_companion_glow` | `true` | Clear the fog in a small circle around each companion, the way the game does around you, so a companion outside your own field of view is still visible. Independent of `reveal_view_cone` on purpose — seeing your squad and seeing what your squad is watching are two different wishes. |
| `reveal_companions` | `false` | Mark each companion's position with the game's own white NPC pin, drawn over the fog so it shows through walls and darkness. |
| `reveal_names` | `true` | Print the companion's name next to its pin. Ignored unless `reveal_companions` is on. |
| `reveal_offscreen` | `true` | When a companion is off screen, pin its marker to the screen edge as an arrow pointing at it, the way the game marks hub NPCs. Ignored unless `reveal_companions` is on. |

> **Known limitation.** Wall shadows inside ground a companion has cleared are
> still cast relative to *your* position. The game's fog shader is handed exactly
> one light position, the player's, and giving each companion its own would mean a
> second shader pass per companion. The ground is revealed correctly; only the
> direction the shadows fall is wrong.

> Position pins are off by default because a companion standing in fog it has
> cleared itself is already visible as itself, and a pin on top of that is clutter.
> Turn them on to find someone who has fallen behind off screen.

---

## `[recruit]` — 28 settings

The paid recruiter NPC by the bar in the bunker. Walk up to him and press
`key_recruit` (**F** by default) to hire companions for roubles.

### The NPC — 8 settings

| Setting | Default | What it does |
|---|---|---|
| `recruiter_enabled` | `true` | Place the recruiter in the bunker at all. Off removes the NPC and the paid menu entirely. |
| `recruiter_preset` | `hub_loner_regular` | The NPC preset he *looks* like — appearance only; he never moves or fights. Must exist in `gamedata/npc.json`; falls back to `default_preset` if not. |
| `recruiter_offset_x` | `-32` | His position as a pixel offset from the barman. Negative x is to the **left** of the barman. |
| `recruiter_offset_y` | `48` | Vertical offset from the barman. Positive y moves **down**, in front of the bar counter where you walk, so he is not hidden behind it. |
| `recruiter_range` | `32` | How close you must stand for the prompt to show and the key to open the menu, in pixels. |
| `recruiter_depth_bias` | `0` | Draw-order nudge, in pixels. Raise it (try `32` or `64`) if he ends up hidden behind the counter or a shelf; `0` keeps the vanilla NPC draw order. |
| `recruiter_avoid_furniture` | `true` | If the offset lands him inside the counter, a wall or a shelf, step him out to the nearest clear floor tile, preferring the front of the bar. Off places him exactly on the offset. |
| `recruiter_prompt_over_npc` | `true` | Draw the hire prompt above his head instead of at a fixed spot low on the screen. |

### The name label — 3 settings

The floating label is the game's **own** NPC marker, not a second hand-drawn
overlay: registering one entry in the controller's marker array is exactly where
"Barman", "Doctor" and "Networker" come from, so the recruiter gets a label
identical to theirs for free — including the off-screen edge arrow, the
hide-while-outside-the-bunker rule and your own "display NPC marker" setting.

| Setting | Default | What it does |
|---|---|---|
| `recruiter_marker_enabled` | `true` | Give him a floating name label, drawn exactly like the Barman's. |
| `recruiter_marker_text` | `Labour Contracts` | The label's text. |
| `recruiter_marker_offset_y` | `-8` | Vertical offset of the label. Negative moves it **up**. `-8` sits the pin at his shins and the label over his head; `0` drops it to his chest; vanilla's own labels use `-24`, which floats well clear above him. |

### Tiers — 13 settings

| Setting | Default | What it does |
|---|---|---|
| `recruit_tier_count` | `3` | How many tiers the menu offers, `1`–`3`. |
| `recruit_tier1_name` | `Rookie` | Tier 1 label in the menu. |
| `recruit_tier1_preset` | `loner_novice` | Tier 1 NPC preset. Must exist in `gamedata/npc.json`. |
| `recruit_tier1_hp_mult` | `1.0` | Tier 1 health multiplier, overriding `hp_multiplier` for that companion. |
| `recruit_tier1_price` | `2500` | Tier 1 price, in roubles. |
| `recruit_tier2_name` | `Veteran` | Tier 2 label. |
| `recruit_tier2_preset` | `loner_regular` | Tier 2 NPC preset. |
| `recruit_tier2_hp_mult` | `1.75` | Tier 2 health multiplier. |
| `recruit_tier2_price` | `6000` | Tier 2 price. |
| `recruit_tier3_name` | `Elite` | Tier 3 label. |
| `recruit_tier3_preset` | `loner_regular` | Tier 3 NPC preset. Try `bandit_veteran` or `bandit_master` for smarter AI. |
| `recruit_tier3_hp_mult` | `3.0` | Tier 3 health multiplier. |
| `recruit_tier3_price` | `12000` | Tier 3 price. |

> **Why tiers are config rather than a difficulty setting.** The game's own
> difficulty is a single global, not a per-NPC value, so it cannot make one
> companion tougher than another. Each tier instead maps to a real NPC preset plus
> an HP multiplier and a price: a better preset genuinely fights better — reflexes,
> health and weapon all come from it — and the multiplier separates tiers that share
> a preset. Only two loner presets exist, which is why the top tiers reuse
> `loner_regular` and pull ahead on HP.

### Menu navigation — 4 settings

Separate from `[input]` because these only ever fire while the menu is open, with
you frozen in the talk state, so they cannot collide with world controls. The up
and down arrow keys always work too, as fixed aliases. Set one to `0` to disable
that action.

| Setting | Default | Key | What it does |
|---|---|---|---|
| `recruit_key_up` | `87` | W | Move the highlight up. |
| `recruit_key_down` | `83` | S | Move the highlight down. |
| `recruit_key_confirm` | `13` | Enter | Advance a step, and **buy** on the final summary. |
| `recruit_key_back` | `8` | Backspace | Step back, and close the menu from the first step. |

> Money is taken through the game's own trader transfer, so a hire shows up in your
> rouble count exactly like any other purchase. The menu refuses with a reason when
> you cannot afford a tier or the roster already holds `max_companions`.

---

## `[input]` — 6 settings

Values are **GameMaker virtual key codes**, not letters:

- `F1`–`F12` = `112`–`123`
- `A`–`Z` = `65`–`90`
- `0`–`9` = `48`–`57`

Set a binding to `0` (or anything outside 1–255) to disable that command.

| Setting | Default | Key | What it does |
|---|---|---|---|
| `key_recruit` | `70` | F | Standing next to the recruiter, opens the paid hire menu. **Does nothing anywhere else.** |
| `key_toggle_hud` | `116` | F5 | Show or hide the squad panel. Resets to shown every launch. |
| `key_debug_spawn` | `117` | F6 | Instantly add one free companion from `default_preset`, anywhere, ignoring price and the recruiter. **Only works while `debug_enabled` is on.** |
| `key_dismiss` | `118` | F7 | Dismiss the companion nearest you, permanently. |
| `key_toggle_hold` | `119` | F8 | Toggle the whole squad between Follow and Hold. |
| `key_debug_dump` | `120` | F9 | Dump full squad state to the log. Works regardless of the `[debug]` settings. |

> **Why `key_recruit` is F and not a function key.** F is what the base game binds
> to Interact, and talking to the recruiter should feel like talking to any other
> NPC. Both actions do fire on one press — a mod cannot consume a key press on the
> base game's behalf — but vanilla's Interact only does anything while you are
> inside an interactable's own range, and the recruiter's corner of the bar is not
> one. And because F is a key you press constantly, the recruit action is a no-op
> away from the recruiter. Move it to a function key if a future game update puts
> an interactable next to him.

> **The debug spawn key does not convert a nearby NPC.** There is no proximity
> check and no existing NPC is involved — it creates a fresh companion from
> `default_preset`, free, at your side. It is a testing tool, which is why it is
> gated behind `debug_enabled`; the intended way to gain companions is to pay the
> recruiter.

Function keys are the defaults for everything else because they cannot collide with
the game's movement and inventory bindings. This was checked rather than assumed:
vanilla only ever reads F5 and F6 *with* a modifier, so a bare F5–F9 press reaches
nothing in the base game.

Commands are suppressed while the Steam overlay is up, and while your player state
is any of inventory, PDA, talk, craft, item spawn, sleep, dead, raid start,
dummy, free camera or teleport. An unrecognised state **allows** commands — the
failure mode being avoided is "keys silently never work", which is far worse than
a command firing during a state nobody classified.

---

## Tuning recipes

Put these in `csq_config_user.ini`.

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

**"Companions are too cheap / too expensive."**
`recruit_tier1_price`, `recruit_tier2_price`, `recruit_tier3_price`. For a run where
companions are a real investment, try `5000` / `15000` / `40000`.

**"I want smarter companions, not just tougher ones."**
Point the tiers at the bandit ladder: `recruit_tier2_preset = bandit_veteran`,
`recruit_tier3_preset = bandit_master`. They will look like bandits, but the preset
is where reflexes and weapon choice come from.

**"Squad vision feels like cheating."**
`reveal_view_cone = false` keeps them visible without opening the map up, or
`reveal_cone_strength = 0.5` leaves what they reveal dimmer than what you see. For
the 1.0.0 behaviour, set `reveal_squad_sight`, `reveal_view_cone` and
`reveal_companion_glow` all to `false`.

**"I keep losing a companion off screen."**
`reveal_companions = true` — pins them through fog and walls, with an edge arrow
when they are off screen.

**"I want no recruiter, just free companions."**
`recruiter_enabled = false`, plus `debug_enabled = true` to enable the F6 free
spawn.
