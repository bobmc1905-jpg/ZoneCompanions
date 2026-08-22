# Changelog

All notable changes to Zone Companions are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/bobmc1905-jpg/zone-companions/releases/tag/v1.0.0
