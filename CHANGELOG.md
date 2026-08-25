# Changelog

All notable changes to Zone Companions are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This is the only changelog. The Nexus Mods release notes are generated from the
section below that matches the version being published — unwrapped, with the
Markdown stripped — so each entry is written to read as prose on a mod page, not
just as a diff summary.

---

## [1.1.1] — 2026-08-25

Two fixes to things the base game only ever set up once, at NPC spawn, and never
checked again.

### Fixed

- **A companion's flashlight went out when you walked into or out of a building,
  and never came back on.** A doorway teleports *you* to the paired interior marker
  somewhere else in the room, so the companion is left standing outside the 960×540
  region `obj_controller` keeps activated and is deactivated within 20 frames. Its
  light either destroys itself — `obj_light_enemy_torch` runs `instance_destroy()`
  when `instance_exists(id_linked)` fails, and a deactivated instance reports as
  non-existent — or is culled in the same sweep and stranded at the doorway. The
  companion is recovered and teleported to you; the light was not, and the base game
  creates a torch in exactly one place, at NPC creation. Companions now check every
  30 frames that they still own a light and re-create it if not, mirroring the
  presence check the base game already runs on an NPC's weapon. A stranded torch
  that wakes up later and re-attaches is destroyed as a duplicate, so a companion
  cannot end up lit twice over.
- **Companions had to reload before they could return fire on first contact.** Every
  NPC is created with `have_to_reload = true`, which the state machine turns into a
  reload action — `path_end()` and 1.3 to 3 seconds of standing still — the moment it
  acquires a target. The magazine was already full: `npc_setup_weapon` fills it at
  spawn. The flag is now cleared right after the weapon is set up, so a companion you
  hired and walked into the zone with shoots back immediately. Reloads from a
  genuinely empty magazine are untouched.
- **Companions offered a "press F to talk" prompt in raid.** `npc_setup` copies the
  preset's `speaker_id` onto the instance, and `loner_regular` carries `"guy"` — the
  generic wandering-loner speaker, with real dialogue behind it. That is all
  `player_collect_nearby_interactables` needs, so standing next to your own companion
  put a talk prompt on screen, served up a stranger's small talk, and competed with
  the loot container you were actually trying to open. Companions now keep the
  `"no_speaker"` value the base game gives every NPC before setup overwrites it, which
  also stops a companion ever being wired up as a quest giver. The recruiter pins the
  same value, so a `recruiter_preset` pointed at a talking preset cannot end up with
  two prompts on one key.

---

## [1.1.0] — 2026-08-25

Companions are now hired from an NPC for money instead of appearing on a key press,
the squad's vision genuinely reveals the world the way yours does, and the config
file is split in two so that mod updates can actually reach it.

### Added

- **A paid recruiter NPC.** A hireable-labour contact stands in the hub bar with a
  floating name tag, drawn in the same pale gold the base game uses for the
  interaction prompt you are about to trigger. Walk up, press **F** — the game's
  own Interact key — and a hire menu opens.
- **Three companion tiers, bought with roubles.** Rookie (2 500), Veteran
  (6 000) and Elite (12 000). Each tier maps to a real vanilla NPC preset and an
  HP multiplier, so a more expensive companion is measurably tougher rather than
  cosmetically different. Prices, presets, multipliers and tier names are all
  configurable.
- **The menu is navigated with the keyboard** — W/S to move, Enter to buy,
  Backspace to close — and refuses the purchase with a reason when you cannot
  afford a tier or the squad is already full. Money is taken through the game's
  own trader transfer, so the transaction shows up in your rouble count exactly
  like any other purchase.
- **Squad vision reveal, in both halves.** Companions now see for you:
  - Anything inside a companion's real vision cone is *drawn* — enemies,
    containers, and the companions themselves — instead of being faded to
    invisible. The base game walks every raid NPC's `image_alpha` down to zero
    outside your own line of sight, so a companion twenty metres ahead was
    literally not rendered. A single guard prepended to the game's
    `player_line_of_sight` predicate now answers "yes" when any companion can see
    the point, which fixes enemies, loot containers, the companions' sprites and
    their flashlights in one place.
  - Each companion's cone is also **subtracted from the fog of war**, inside the
    base game's own subtract pass, so it clears the black exactly the way your own
    cone does. No coloured overlays, no boxes — the map just opens up where your
    squad is looking.
  - The cone used is the **real one**: the same triangle
    `scr_find_target_for_human` builds from the NPC's weapon direction, alert
    radius and visual distance, including the day/night factor. What is revealed
    is precisely what that companion could actually shoot at.
- **Optional position pins** for companions who are off-screen or behind fog, in
  the same white the base game uses for its own NPC markers. Off by default.
- **A sixth key binding.** `key_recruit` (**F**) opens the recruiter menu;
  debug spawning moved to its own `key_debug_spawn` (**F6**), which remains gated
  behind `debug_enabled`.
- **36 new configurable settings**, taking the total from 61 to **97** across
  **eleven** sections — the new `[reveal]` (7) and `[recruit]` (28) sections, plus
  one more key in `[input]`.
- **The config is now two files, and updates reach it.**
  - `csq_config.ini` is a generated reference: every setting the running version
    has, its current default and a description, **rewritten from scratch on every
    launch**. So a mod update's new settings appear in it immediately and its
    defaults are never described wrongly.
  - `csq_config_user.ini` is yours: created once as an all-commented template,
    never overwritten, and holding only the lines you actually want to change.
  - **Nothing to do when you update.** Your 1.0.0 config is moved into the new user
    file automatically on the first launch. And if you edit the generated file out
    of habit, the mod moves those lines into your user file for you, applies them
    that same launch, and says so in the log — nothing is silently reverted.
  - A misspelled key is now reported by name in the log. The old "N keys absent"
    warning is gone, because an absent key is the normal case in a file that is
    meant to be short.

### Changed

- `key_recruit` was **117** (F6) and created a free companion from
  `default_preset`. It is now **70** (F) and opens the paid hire menu. F6 still
  free-spawns, under the new `key_debug_spawn` name, when `debug_enabled` is on.
- The squad panel's companion rows are unchanged, but the mod's single Draw GUI
  entry point now also drives the recruiter prompt, the hire menu and the position
  pins, all of which draw with the panel hidden or the roster empty.
- The mod now touches base-game code in **nine** places, up from seven: the two
  new patches are the `player_line_of_sight` guard and the fog-subtract hook
  part-way through `obj_fog_setup_Draw_0`. Both are prepends inside existing code
  rather than replacements, and nothing else in the game is modified.

### Fixed

- **Companions were invisible outside your own view cone.** Root cause was the
  base game's per-frame alpha fade on every raid NPC, not the fog surface;
  darkening was never the problem, the sprites were at alpha 0.
- **Companion flashlights emitted nothing when out of your sight.** The torch
  object scales its light by its owner's `image_alpha`, so an alpha-0 companion's
  light was scaled to zero. Fixed by the same `player_line_of_sight` guard.
- **Loot containers a companion was standing next to stayed hidden**, for the same
  reason and with the same fix.

### Known limitation

- Wall shadows inside ground a companion has cleared are still cast relative to
  *your* position. The base game's fog shader is handed exactly one light
  position, the player's, and fixing it would mean a second shader pass per
  companion — not worth the frame cost. The ground is revealed correctly; only the
  direction the shadows fall is wrong.

### Upgrading from 1.0.0

Nothing to do. No setting was removed or renamed, and on the first launch the mod
moves your existing `csq_config.ini` values into the new `csq_config_user.ini` for
you, then regenerates `csq_config.ini` as a reference listing all 97 settings. Your
saves and existing rosters are unaffected.

---

## [1.0.0] — 2026-08-22

Initial public release.

### Added

- **A persistent companion squad.** Up to `max_companions` (default 3) NPC
  companions spawn beside you at the start of every raid. The roster is saved
  into the character's own save slot, so a squad belongs to a character, travels
  with that save, and is deleted with it.
- **Real combat AI, not a scripted approximation.** Companions descend from the
  game's own `obj_npc_human_parent`, so when a hostile comes into range the mod
  hands control to vanilla's `human_general` utility AI — the same selector that
  makes bandits take cover, flank, shoot and reload. The mod contains no combat
  code at all.
- **Real pathfinding.** Following uses the game's own `mp_grid` A\* navigation
  grid, so companions route around buildings and terrain instead of walking into
  walls.
- **Formation following.** Companions hold a slot behind your heading, offset
  toward where you are aiming so they screen the direction you are covering
  rather than only your back. Speeds are derived from your *live* current speed,
  so backpacks, hunter skills and the hub's run bonus cannot leave them behind.
- **Idle roaming.** While you stand still, companions drift within `roam_radius`
  of their slot instead of standing to attention. Suppressed the moment you start
  moving, so it can never loosen the formation on the move.
- **Teleport rescue.** A companion that has genuinely failed to path for
  `teleport_fail_frames` and is beyond `teleport_distance` is moved to a free cell
  near you, rather than being lost behind geometry.
- **Field medic.** A companion will break off to heal you below
  `heal_threshold`, and will abandon a firefight to reach you below
  `heal_emergency_threshold`. Exactly one companion claims each wound, so the
  whole squad does not break formation for the same injury. Charges refill at the
  start of every raid. Healing restores HP and optionally stops bleeding — the
  same as an NPC medic's dialogue heal.
- **Two-way friendly fire protection.** Companion bullets pass through you and
  your bullets pass through companions, both enforced inside vanilla's own
  collision predicates — so a blocked round is not consumed and can still hit the
  enemy behind. Grenades are disarmed instead of filtered, because grenade damage
  in this game has no faction check of any kind.
- **A dedicated "Companion" faction**, registered into both of the game's faction
  registries on every map load. It mirrors your own standings by default, so
  companions fight whoever you are fighting.
- **Squad panel** (top-left) showing each companion's name, current/max HP,
  remaining field dressings and mode. Movable, resizable and toggleable, drawn
  with the game's own outlined-text helper so it stays readable over snow and
  grass.
- **Injury persistence.** Companions carry damage out of one raid and into the
  next, and survive the game culling off-screen instances.
- **Five rebindable keys** — F5 panel, F6 add companion, F7 dismiss nearest, F8
  Follow/Hold, F9 state dump. Suppressed while the Steam overlay is up or the
  player is in any menu, dialogue or non-walking state.
- **61 configurable settings** across nine sections, written out as a fully
  commented `csq_config.ini` on first launch and documented in
  [CONFIGURATION.md](CONFIGURATION.md).
- **Levelled logging** to `logs/csq_log.txt` and the game's own `trace()`, with a
  debug overlay and an F9 state dump for bug reports.

### Notes on this release

- The mod touches base-game code in exactly **seven places** — five appended
  calls into object events, and two guards prepended to the bullet-collision
  predicates. Nothing else in the game is modified.

[1.1.1]: https://github.com/bobmc1905-jpg/ZoneCompanions/releases/tag/v1.1.1
[1.1.0]: https://github.com/bobmc1905-jpg/ZoneCompanions/releases/tag/v1.1.0
[1.0.0]: https://github.com/bobmc1905-jpg/ZoneCompanions/releases/tag/v1.0
