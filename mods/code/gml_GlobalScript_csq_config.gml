// =============================================================================
//  Zone Companions  -  csq_config
// -----------------------------------------------------------------------------
//  Every tunable value in the mod lives in this file. Nothing else in the mod
//  should contain a magic number: if a value might ever want changing, it gets
//  an entry in csq_config_spec() and an ini key, and is read back through
//  csq_cfg().
//
//  WHERE THE FILES LIVE
//  GameMaker sandboxes relative file I/O into the game's save area, so the
//  filenames below resolve to:
//      %LOCALAPPDATA%\ZERO_Sievert\csq_config.ini
//      %LOCALAPPDATA%\ZERO_Sievert\csq_config_user.ini
//  (the same folder that already holds installed_mods.json, mods_enabled.json
//  and the numeric save slots). That is a better home than the game folder: it
//  survives both GMLoader re-patching and game updates.
//
//  THERE ARE TWO FILES, AND ONLY ONE OF THEM IS THE PLAYER'S
//      csq_config.ini        generated. Every setting, its current default and a
//                            comment saying what it does. Rewritten from the spec
//                            on every launch; no value is ever read out of it.
//      csq_config_user.ini   the player's. Only the lines they want to change.
//                            The only file overrides come from, and the only file
//                            the mod will not overwrite.
//
//  A single file cannot be both. Written-once-if-missing is the only safe way to
//  treat a file holding the player's edits, but it also means a mod update can
//  never reach it: settings added later are simply absent, and defaults changed
//  later are still documented wrongly. 1.0.0 shipped 61 settings, 1.1.0 had 97 and
//  1.2.0 has 146, so a player upgrading from 1.0.0 would have seen none of the 85
//  added since. Splitting them makes the reference disposable -- always regenerated,
//  therefore always correct -- and the override file tiny, hand-written and
//  update-proof.
//
//  The transition is automatic in both directions. On the first launch after an
//  update there is no user file, so the old single config's non-default values are
//  adopted into a new one wholesale; and thereafter anything typed into the
//  generated file by habit is moved across rather than reverted. See
//  csq_config_adopt_strays.
//
//  WHY A HAND-ROLLED PARSER INSTEAD OF ini_open/ini_read_*
//  GameMaker's ini_close() always rewrites the file from its parsed contents,
//  which silently strips every comment. Both of these files are mostly comments,
//  so that is fatal to the format: the reference is unreadable without them and
//  the user file's instructions would vanish the first time it was touched.
//
//  NOTE ON STRUCTURE
//  Section headers are cosmetic and exist purely to group the file for humans.
//  Key names are globally unique, so a key is found regardless of which section
//  it is under -- which is what lets the user file be a flat list.
//
//  This file declares functions only. It deliberately contains no top-level
//  executable code -- all initialisation is driven from real object events by
//  csq_init, because a newly created global script's top-level body is not
//  guaranteed to be run at game start by the patcher.
// =============================================================================


/// @func   csq_config_spec()
/// @desc   The single source of truth for every setting: its section, name,
///         type, default and documentation. Loading, reference-file generation,
///         stray adoption and validation are all driven from this one array, so a
///         new setting is added in exactly one place and appears in the player's
///         reference file the first time the new build runs.
/// @return {Array} array of {section, key, type, def, comment}
function csq_config_spec()
{
    return [
        // ---- debug -------------------------------------------------------
        { section: "debug", key: "debug_enabled", type: "bool", def: false,
          comment: "Master switch for DEBUG-level logging and on-screen debug text." },
        { section: "debug", key: "log_level", type: "real", def: 2,
          comment: "0=ERROR only, 1=+WARNING, 2=+INFO (default), 3=+DEBUG." },
        { section: "debug", key: "log_to_file", type: "bool", def: true,
          comment: "Write the log to logs/csq_log.txt in the save folder." },
        { section: "debug", key: "log_to_trace", type: "bool", def: true,
          comment: "Also send every log line to the game's own trace() output." },
        { section: "debug", key: "draw_debug_overlay", type: "bool", def: false,
          comment: "Draw per-companion mode/state/target text. Needs debug_enabled." },

        // ---- squad -------------------------------------------------------
        { section: "squad", key: "max_companions", type: "real", def: 3,
          comment: "How many companions may be active at once (1-8 is sane)." },
        { section: "squad", key: "default_preset", type: "string", def: "loner_regular",
          comment: "NPC preset companions are built from. Must exist in gamedata/npc.json." },
        { section: "squad", key: "auto_spawn_in_raid", type: "bool", def: true,
          comment: "Respawn the saved roster automatically when a raid map loads." },
        { section: "squad", key: "spawn_offset", type: "real", def: 24,
          comment: "Pixels from the player to look for a free spawn cell." },
        { section: "squad", key: "spawn_delay_frames", type: "real", def: 30,
          comment: "Frames to wait after a map loads before spawning, so the map has finished generating." },
        { section: "squad", key: "respawn_on_death", type: "bool", def: false,
          comment: "false = a fallen companion is gone for good. true = they return next raid." },
        { section: "squad", key: "recover_deactivated", type: "bool", def: true,
          comment: "Reactivate and pull back companions the game culls for being too far away. Turn off only if it fights another mod." },
        // Companions fight at the player's pace and take the hits that go with it,
        // but they are built from an ordinary enemy preset -- loner_regular has 60
        // HP, the same as the mooks you kill three of at a time. 1 is vanilla-fair
        // and dies fast.
        { section: "squad", key: "hp_multiplier", type: "real", def: 1.5,
          comment: "Multiplies a companion's starting health. loner_regular has 60 HP, so 1.5 gives 90. The game's own difficulty scaling still applies on top." },

        // ---- follow ------------------------------------------------------
        { section: "follow", key: "follow_distance", type: "real", def: 32,
          comment: "Desired standoff distance from the player, in pixels." },
        { section: "follow", key: "formation_spread", type: "real", def: 26,
          comment: "How far apart companions fan out around the follow point." },
        { section: "follow", key: "catchup_distance", type: "real", def: 40,
          comment: "Distance from its formation slot at which a companion switches to catch-up speed." },
        { section: "follow", key: "arrive_distance", type: "real", def: 10,
          comment: "Inside this distance OF ITS SLOT a companion stops and holds position." },
        // Follow speed is the greater of two terms, checked every frame:
        //   * the preset's own spd_alerted scaled by speed_walk_mult / speed_run_mult
        //   * the player's ACTUAL current speed scaled by speed_match_mult /
        //     speed_catchup_mult
        // The second term is what keeps them with the player: reference numbers are
        // player walk 0.75 and player run 1.2 px/step (scr_player_movement:108-109),
        // but backpacks, hunter skills and the hub's 1.5x run bonus all raise that,
        // so it is read off the live player rather than assumed. loner_regular's
        // spd_alerted is 0.75 px/step.
        { section: "follow", key: "speed_walk_mult", type: "real", def: 1.05,
          comment: "Multiplier on the preset's alerted speed, used as the cruising floor." },
        { section: "follow", key: "speed_run_mult", type: "real", def: 2.6,
          comment: "Multiplier on the preset's alerted speed, used as the catch-up floor." },
        { section: "follow", key: "speed_match_mult", type: "real", def: 1.15,
          comment: "Cruising speed as a multiple of the player's CURRENT speed. Must be >1 or gaps never close." },
        { section: "follow", key: "speed_catchup_mult", type: "real", def: 1.75,
          comment: "Catch-up speed as a multiple of the player's CURRENT speed. Raise if they still lag behind." },
        { section: "follow", key: "speed_max", type: "real", def: 3.0,
          comment: "Hard ceiling on follow speed in pixels per step, so nothing looks like it is teleporting." },
        { section: "follow", key: "goal_move_threshold", type: "real", def: 8,
          comment: "Player must move this far before the formation slot is retargeted." },
        { section: "follow", key: "teleport_distance", type: "real", def: 400,
          comment: "Only consider teleporting past this distance. 0 disables teleporting." },
        { section: "follow", key: "teleport_fail_frames", type: "real", def: 90,
          comment: "Frames of continuous pathing failure required before teleporting." },
        // The formation sits BEHIND the player's heading, which is what keeps
        // companions out of your line of fire -- but it also means they hang back
        // by your shoulders and never screen the direction you are actually
        // watching. This slides the whole formation toward the cursor.
        { section: "follow", key: "aim_lead", type: "real", def: 26,
          comment: "Pixels the formation slides toward where you are aiming. 0 is off: companions sit purely behind you. Around follow_distance puts them level with you on the side you are covering; much higher pushes them out in front as a screen." },
        { section: "follow", key: "aim_lead_smooth", type: "real", def: 0.08,
          comment: "How quickly companions follow the cursor, per frame, 0.01 slow to 1 instant. Low values stop a flicked mouse making them jitter." },

        // ---- roam --------------------------------------------------------
        // Companions drift around their formation slot instead of standing on it.
        //
        // ROAMING IS SUPPRESSED WHILE THE PLAYER IS MOVING, on purpose. The follow
        // loop above was retuned specifically to stop companions trailing behind;
        // adding a random offset on top of a target that is already moving away
        // would hand that bug straight back. See roam_max_player_speed.
        { section: "roam", key: "roam_enabled", type: "bool", def: true,
          comment: "Let companions wander around their formation slot while the player is still." },
        { section: "roam", key: "roam_radius", type: "real", def: 40,
          comment: "How far from its formation slot a companion may drift, in pixels." },
        { section: "roam", key: "roam_interval", type: "real", def: 90,
          comment: "Frames between new wander destinations. 90 is about 1.5 seconds." },
        { section: "roam", key: "roam_max_player_speed", type: "real", def: 0.3,
          comment: "Roaming stops once the player moves faster than this, in pixels per step. Player walk is about 0.75, so 0.3 means 'only while standing still'. Raise it to keep roaming while on the move, at the cost of a looser formation." },

        // ---- combat ------------------------------------------------------
        { section: "combat", key: "engage_radius", type: "real", def: 420,
          comment: "Companions ignore enemies further than this from the player. Roughly a screen width; the game deactivates NPCs past ~480px anyway." },
        { section: "combat", key: "engage_advance", type: "real", def: 96,
          comment: "How far toward the enemy a companion may push while fighting, in pixels. 0 makes them hug the player. Raise for a more aggressive push, lower to keep them close." },
        { section: "combat", key: "disengage_frames", type: "real", def: 150,
          comment: "Frames without a target before a companion returns to following. Higher = stays in a fight through brief losses of line of sight." },
        { section: "combat", key: "scan_interval", type: "real", def: 4,
          comment: "Frames between target scans while following. Lower = faster reactions, more CPU." },
        { section: "combat", key: "mirror_player_relations", type: "bool", def: true,
          comment: "Copy the player's faction standings, so companions fight whoever you fight." },
        { section: "combat", key: "rep_ally", type: "real", def: 1000,
          comment: "Reputation written for allies. >600 counts as ally in-game." },
        { section: "combat", key: "rep_hostile", type: "real", def: 0,
          comment: "Reputation written for enemies. <250 counts as hostile in-game." },

        // Combat craft. Vanilla's NPC brain has no action that closes distance once
        // the target is already inside the weapon's effective band: action 29
        // (Advance) is gated on range_type != 0 and action 11 (Shoot) on
        // range_type == 0, and 11 wins the priority queue. So an NPC in range stops
        // dead and shuffles inside a 16px box. Everything below is the mod moving
        // the feet while vanilla keeps the trigger.
        { section: "combat", key: "push_enabled", type: "bool", def: true,
          comment: "Companions advance on a target in committed moves while they shoot, instead of rooting to the spot the moment it comes into range. Turn off for exactly vanilla footwork." },
        { section: "combat", key: "push_min_distance", type: "real", def: 220,
          comment: "A companion only pushes when the target is at least this far away, in pixels. Below it they are already close enough and vanilla's own shuffle is fine. An aggressive companion closes from a little further out, a cautious one waits until the gap is larger." },
        { section: "combat", key: "push_stop_distance", type: "real", def: 90,
          comment: "A push never aims closer than this to the target, in pixels. This is the line between 'advancing' and 'walking into a shotgun'." },
        { section: "combat", key: "push_step", type: "real", def: 48,
          comment: "How far one committed move carries the companion, in pixels. Small steps read as bounding from cover to cover; large ones read as a charge." },
        { section: "combat", key: "push_commit_frames", type: "real", def: 45,
          comment: "How long a companion sticks to a move once it has started it, in frames (60 = 1 second). This is the setting that makes pushing look human: an NPC that re-decides every frame twitches, one that commits looks like it meant it. Lower it for jumpier footwork, raise it for a more determined advance." },
        { section: "combat", key: "push_cooldown_frames", type: "real", def: 90,
          comment: "Frames of standing and shooting after a push finishes, before another may start. Pushes back to back would be a sprint; this is what turns them into advance, fire, advance." },
        { section: "combat", key: "push_speed_mult", type: "real", def: 1.35,
          comment: "Movement speed during a push, as a multiple of the preset's alerted speed. Vanilla walks a shooting NPC at its idle speed, which is why an advance without this looks like a stroll." },
        { section: "combat", key: "push_max_from_player", type: "real", def: 260,
          comment: "A companion never pushes to a spot further than this from you, in pixels. The leash that stops an advance turning into a solo assault across the map." },
        { section: "combat", key: "push_require_los", type: "bool", def: true,
          comment: "Only push when the companion can actually see the target. Off means they will also close on a target they have lost behind cover." },
        { section: "combat", key: "flank_bias_degrees", type: "real", def: 35,
          comment: "How far off the straight line to the target each companion angles its advance, in degrees. Alternating slots lean opposite ways, so a squad spreads into an arc instead of queueing up single file. 0 makes everyone charge straight in." },
        { section: "combat", key: "spread_enabled", type: "bool", def: true,
          comment: "Companions standing on top of each other in a firefight sidestep apart. Two of them in one spot is one grenade, and it is the single clearest tell that a squad is running one brain. Sits under push_enabled: turning that off turns off all combat footwork." },
        { section: "combat", key: "spread_min_distance", type: "real", def: 40,
          comment: "How close another companion has to be before this one moves aside, in pixels. Roughly two body widths." },
        { section: "combat", key: "spread_step", type: "real", def: 36,
          comment: "How far a companion sidesteps to break up a stack, in pixels. Always across the line to the target, never along it, so nobody gives up ground or walks into the open to do it." },
        { section: "combat", key: "reposition_after_frames", type: "real", def: 240,
          comment: "Frames of shooting from the same spot before a companion shifts position anyway, at 60 a second. This is the anti-turret backstop: it fires even when the target is already close enough that no advance is wanted, so a firefight never has anyone standing perfectly still for ten seconds. 0 switches it off." },
        { section: "combat", key: "reposition_step", type: "real", def: 56,
          comment: "How far that shift carries, in pixels. Side chosen at random each time, so a blocked direction fixes itself on the next attempt." },

        // ---- ff ----------------------------------------------------------
        // Friendly fire. The two bullet settings are enforced inside vanilla's own
        // collision predicates, so a blocked round is not consumed -- it passes
        // through and can still hit the enemy behind. See csq_ff.
        { section: "ff", key: "ff_protect_player", type: "bool", def: true,
          comment: "Companion bullets pass harmlessly through you." },
        { section: "ff", key: "ff_protect_companions", type: "bool", def: true,
          comment: "Your bullets pass harmlessly through companions. Turn this off if you want to be able to shoot your own squad." },
        { section: "ff", key: "ff_no_grenades", type: "bool", def: true,
          comment: "Stop companions throwing grenades at all. The preset carries live RGD grenades and flashbangs, and grenade damage has no faction check of any kind." },

        // ---- medic -------------------------------------------------------
        // Thresholds are fractions of the player's CURRENT maximum HP, which
        // vanilla recomputes every frame as
        //     hp_max = hp_max_total - wound
        // (player_step_personal_stats lines 44-45). So a wounded player sitting at
        // full effective health counts as full and is not healed -- closing a wound
        // takes medication, not a field dressing, and nothing here touches `wound`.
        { section: "medic", key: "heal_enabled", type: "bool", def: true,
          comment: "Let companions heal you when you are hurt." },
        { section: "medic", key: "heal_threshold", type: "real", def: 0.85,
          comment: "Heal once your health drops below this fraction of maximum. 1 = heal any damage at all." },
        { section: "medic", key: "heal_emergency_threshold", type: "real", def: 0.35,
          comment: "Below this fraction a companion abandons a firefight to reach you. Above it, it finishes the fight first." },
        { section: "medic", key: "heal_amount", type: "real", def: 25,
          comment: "HP restored per heal. Never takes you above your current maximum." },
        { section: "medic", key: "heal_charges", type: "real", def: 2,
          comment: "Heals each companion carries. Refilled at the start of every raid." },
        { section: "medic", key: "heal_cooldown_frames", type: "real", def: 600,
          comment: "Frames a companion waits between heals. 600 is 10 seconds at 60fps." },
        { section: "medic", key: "heal_range", type: "real", def: 24,
          comment: "How close a companion must get before it can heal you, in pixels." },
        { section: "medic", key: "heal_stop_bleed", type: "bool", def: true,
          comment: "Also stop bleeding, the way an NPC medic's dialogue heal does." },
        { section: "medic", key: "heal_message", type: "bool", def: true,
          comment: "Show an on-screen message when a companion patches you up." },

        // ---- hud ---------------------------------------------------------
        { section: "hud", key: "hud_enabled", type: "bool", def: true,
          comment: "Show the squad list. Coordinates below are in 480x270 GUI space." },
        { section: "hud", key: "hud_x", type: "real", def: 6,
          comment: "Left edge of the squad list, in GUI pixels (0-480)." },
        { section: "hud", key: "hud_y", type: "real", def: 40,
          comment: "Top edge of the squad list, in GUI pixels (0-270)." },
        { section: "hud", key: "hud_line_height", type: "real", def: 10,
          comment: "Vertical spacing per companion row." },
        // Row spacing is multiplied by this too, so shrinking the text does not
        // leave the panel spread over the same height it was before.
        { section: "hud", key: "hud_scale", type: "real", def: 1,
          comment: "Text size for the whole squad panel. 1 is the game's own smallest UI font at native size. 0.75 fits more on screen but looks ragged, because that font is a bitmap generated with antialiasing switched off." },
        { section: "hud", key: "hud_show_hp", type: "bool", def: true,
          comment: "Append current/max HP to each row." },

        // ---- reveal ------------------------------------------------------
        // The squad's contribution to what the player can see. There are two
        // separate mechanisms here, because the game hides things in two ways.
        //
        // 1. SPRITES ARE FADED OUT, NOT JUST DARKENED
        // obj_npc_parent_Step_0 line 3873 runs, for every NPC in a raid, every
        // frame: var _visibility = player_line_of_sight(x, y), and walks image_alpha
        // down to 0 when that is false. player_line_of_sight is false for anything
        // outside the player's own 90-degree wedge that is further away than
        // global.fow_minimun_dis (35px). obj_chest_general_Step_0 line 39 does the
        // same for containers.
        //
        // So a companion standing behind the player is not dim, they are drawn at
        // alpha 0 -- and their torch goes with them, because
        // obj_light_enemy_torch_Step_0 swaps its sprite for s_vuoto and scales by
        // lerp(0, scale_start, id_linked.image_alpha). That is reveal_squad_sight.
        //
        // 2. THE GROUND IS PAINTED BLACK
        // obj_fog_setup_Draw_0 clears a screen-sized surface to opaque black, then
        // switches to bm_subtract and punches the player's view wedge out of it with
        // a triangle fan (global.angle_fow degrees, aimed at the cursor) plus
        // s_glow_fow for close-range awareness. shd_fog_new then paints wall shadows
        // back in, and the surface is blitted over the world at the player's
        // "fog of war alpha" setting. That is reveal_view_cone.
        //
        // Both use the same triangle the companion's AI actually searches, built
        // once per frame by csq_reveal_sight_cache, so what they light and what they
        // let you see can never disagree.
        { section: "reveal", key: "reveal_squad_sight", type: "bool", def: true,
          comment: "Let what your companions can see count as something you can see: the companion themselves, their flashlight, and anyone standing in their field of view. This is the setting that stops a companion behind you from being invisible." },
        { section: "reveal", key: "reveal_view_cone", type: "bool", def: true,
          comment: "Let each companion's field of view clear the fog of war, the same way the player's does." },
        // The cone used is the literal triangle scr_find_target_for_human tests
        // against, not an approximation: apex at the companion, edges at
        // weapon_pointing_direction +/- alert_radius/2, length alert_visual_distance
        // after the day/night penalty and scr_npc_oval_view's sideways squash. If it
        // is not in the triangle, the companion cannot see it -- so the cleared area
        // is exactly the ground they are actually watching.
        { section: "reveal", key: "reveal_cone_strength", type: "real", def: 1,
          comment: "How completely a companion clears the fog, 0-1, applied to both the cone and the glow. 1 matches the player's own vision; lower leaves what they reveal dimmer than what you do." },
        // This is the setting that answers "why can I not see my own companion
        // standing right there": their sprite IS drawn every frame --
        // obj_npc_human_parent_Draw_0 has no visibility test at all -- it is the fog
        // surface painted over the world afterwards that hides them. So they are
        // given the same s_glow_fow halo the player gets, subtracted at their feet,
        // which makes them visible whether or not the player is looking their way.
        // Independent of reveal_view_cone on purpose: seeing your squad and seeing
        // what your squad is watching are two different wishes.
        { section: "reveal", key: "reveal_companion_glow", type: "bool", def: true,
          comment: "Clear the fog in a small circle around each companion, the way the game does around the player, so a companion outside your own field of view is still visible." },
        // Position pins are off by default now that companions clear the fog around
        // themselves: a companion standing in their own cleared ground is visible as
        // themselves, and a pin on top of that is just clutter. Still here for
        // finding someone who has fallen behind off screen.
        { section: "reveal", key: "reveal_companions", type: "bool", def: false,
          comment: "Mark each companion's position with the game's own NPC pin, drawn over the fog so it shows through walls and darkness." },
        { section: "reveal", key: "reveal_names", type: "bool", def: true,
          comment: "Print the companion's name next to their pin. Ignored unless reveal_companions is on." },
        { section: "reveal", key: "reveal_offscreen", type: "bool", def: true,
          comment: "When a companion is off screen, pin their marker to the screen edge as an arrow pointing at them, the way the game marks hub NPCs. Ignored unless reveal_companions is on." },

        // ---- recruit -----------------------------------------------------
        // The paid recruiter NPC by the bar in the bunker. Walk up to them and
        // press the recruit key (see [input]) to hire companions for roubles.
        //
        // WHY TIERS ARE CONFIG, NOT A GAME DIFFICULTY
        // The game's own difficulty (rookie/standard/survivor/hunter) is a single
        // global, not a per-NPC value, so it cannot make one companion tougher than
        // another. Instead each tier maps to a real NPC preset plus an HP multiplier
        // and a price: a better preset genuinely fights better (npc_setup pulls
        // reflexes, hp and weapon from it), and the multiplier separates tiers that
        // share a preset. Only two loner presets exist (loner_novice, loner_regular),
        // which is why the top tiers reuse loner_regular and pull ahead on HP. Point
        // a tier's preset at the bandit ladder (bandit_veteran ... bandit_master) for
        // a genuinely smarter -- if bandit-looking -- companion.
        { section: "recruit", key: "recruiter_enabled", type: "bool", def: true,
          comment: "Place a recruiter NPC by the bar in the bunker. Off removes the NPC and the paid menu entirely." },
        { section: "recruit", key: "recruiter_preset", type: "string", def: "hub_loner_regular",
          comment: "NPC preset the recruiter LOOKS like (appearance only; they never move or fight). Must exist in gamedata/npc.json; falls back to default_preset if not." },
        { section: "recruit", key: "recruiter_offset_x", type: "real", def: -32,
          comment: "Recruiter position as a pixel offset from the barman. Negative x is to the LEFT of the barman." },
        { section: "recruit", key: "recruiter_offset_y", type: "real", def: 48,
          comment: "Vertical pixel offset from the barman. Positive y moves DOWN, in front of the bar counter where the player walks, so the recruiter is not hidden behind it." },
        { section: "recruit", key: "recruiter_range", type: "real", def: 32,
          comment: "How close you must stand for the recruit prompt to show and the key to open the menu, in pixels." },
        { section: "recruit", key: "recruiter_depth_bias", type: "real", def: 0,
          comment: "Draw-order nudge for the recruiter, in pixels. Raise it (try 32 or 64) if he ends up hidden behind the bar counter or a shelf; 0 keeps the vanilla NPC draw order." },
        { section: "recruit", key: "recruiter_avoid_furniture", type: "bool", def: true,
          comment: "If the offset lands the recruiter inside the counter, a wall or a shelf, step him out to the nearest clear floor tile (preferring in front of the bar). Off places him exactly on the offset." },
        { section: "recruit", key: "recruiter_prompt_over_npc", type: "bool", def: true,
          comment: "Draw the hire prompt above the recruiter's head instead of at a fixed spot low on the screen." },
        // THE NAME LABEL IS VANILLA'S OWN, NOT A SECOND HAND-DRAWN OVERLAY
        // obj_controller_Draw_64 walks an obj_controller array called arr_npc_marker
        // and, for every entry, draws the s_minimap_marker pin plus the entry's text
        // above it -- that is exactly where "Barman", "Doctor" and "Networker" come
        // from (see init_npc_marker). Registering one entry there gives the recruiter
        // a label identical to theirs for free, including the off-screen edge arrow,
        // the hide-while-outside-the-bunker rule and the player's own
        // "display_npc_marker" setting. See csq_recruit_marker_sync.
        { section: "recruit", key: "recruiter_marker_enabled", type: "bool", def: true,
          comment: "Give the recruiter a floating name label in the bunker, drawn exactly like the Barman's and the Doctor's." },
        { section: "recruit", key: "recruiter_marker_text", type: "string", def: "Labour Contracts",
          comment: "Text of the recruiter's name label." },
        { section: "recruit", key: "recruiter_marker_offset_y", type: "real", def: -8,
          comment: "Vertical pixel offset of the name label from the recruiter. Negative moves it UP, positive DOWN. -8 sits the pin at his shins and the label over his head; 0 drops it to his chest, and vanilla's own labels use -24, which on a real NPC sprite floats well clear above him." },
        { section: "recruit", key: "recruit_tier_count", type: "real", def: 3,
          comment: "How many difficulty tiers the menu offers, 1 to 3." },
        { section: "recruit", key: "recruit_tier1_name", type: "string", def: "Rookie",
          comment: "Tier 1 label shown in the menu." },
        { section: "recruit", key: "recruit_tier1_preset", type: "string", def: "loner_novice",
          comment: "Tier 1 NPC preset. Must exist in gamedata/npc.json; falls back to default_preset if not." },
        { section: "recruit", key: "recruit_tier1_hp_mult", type: "real", def: 1.0,
          comment: "Tier 1 health multiplier, overriding hp_multiplier for this companion." },
        { section: "recruit", key: "recruit_tier1_price", type: "real", def: 2500,
          comment: "Tier 1 price per companion, in roubles." },
        { section: "recruit", key: "recruit_tier2_name", type: "string", def: "Veteran",
          comment: "Tier 2 label shown in the menu." },
        { section: "recruit", key: "recruit_tier2_preset", type: "string", def: "loner_regular",
          comment: "Tier 2 NPC preset. Must exist in gamedata/npc.json; falls back to default_preset if not." },
        { section: "recruit", key: "recruit_tier2_hp_mult", type: "real", def: 1.75,
          comment: "Tier 2 health multiplier, overriding hp_multiplier for this companion." },
        { section: "recruit", key: "recruit_tier2_price", type: "real", def: 6000,
          comment: "Tier 2 price per companion, in roubles." },
        { section: "recruit", key: "recruit_tier3_name", type: "string", def: "Elite",
          comment: "Tier 3 label shown in the menu." },
        { section: "recruit", key: "recruit_tier3_preset", type: "string", def: "loner_regular",
          comment: "Tier 3 NPC preset. Must exist in gamedata/npc.json; falls back to default_preset if not. Try bandit_veteran or bandit_master for smarter AI." },
        { section: "recruit", key: "recruit_tier3_hp_mult", type: "real", def: 3.0,
          comment: "Tier 3 health multiplier, overriding hp_multiplier for this companion." },
        { section: "recruit", key: "recruit_tier3_price", type: "real", def: 12000,
          comment: "Tier 3 price per companion, in roubles." },
        // Hire-menu navigation. Separate from the [input] binds because these only
        // ever fire while the menu is open (the player is frozen in the talk state),
        // so they cannot collide with world controls. Values are GameMaker virtual
        // key codes: W=87, S=83, vk_enter=13, vk_backspace=8. The up and down arrows
        // always work too, as fixed aliases. Set one to 0 to disable that action.
        { section: "recruit", key: "recruit_key_up", type: "real", def: 87,
          comment: "Menu: raise the value / move the highlight up. Default W (87)." },
        { section: "recruit", key: "recruit_key_down", type: "real", def: 83,
          comment: "Menu: lower the value / move the highlight down. Default S (83)." },
        { section: "recruit", key: "recruit_key_confirm", type: "real", def: 13,
          comment: "Menu: advance a step, and BUY on the final summary. Default Enter (13)." },
        { section: "recruit", key: "recruit_key_back", type: "real", def: 8,
          comment: "Menu: step back, and close from the first step. Default Backspace (8)." },

        // ---- callouts ----------------------------------------------------
        // Spoken lines, drawn by vanilla's own obj_npc_draw_text through
        // global.t_npc_text. Registration happens on every map load, not at boot,
        // because vanilla's lista_npc_text() re-creates five of the nine parallel
        // arrays from scratch each time obj_controller is created.
        { section: "callouts", key: "idle_callouts_enabled", type: "bool", def: true,
          comment: "Companions occasionally say something out loud when nothing is happening. Uses the game's own NPC speech bubbles." },
        { section: "callouts", key: "push_callout_chance", type: "real", def: 35,
          comment: "Percent chance a companion calls out as it starts a push. Uses the game's existing 'I'm pushing' lines, so nothing has to be registered for it. 0 turns push callouts off; the rest of pushing is unaffected." },
        { section: "callouts", key: "selfcare_callout_enabled", type: "bool", def: true,
          comment: "A companion says something as it starts bandaging itself. Uses the game's existing 'I'm hurt' line, so it is a voice you have already heard in the zone." },
        { section: "callouts", key: "idle_callout_min_seconds", type: "real", def: 40,
          comment: "Shortest wait between one companion's idle lines, in seconds. The actual wait is rolled between this and the maximum, per companion, so two of them never speak on a schedule." },
        { section: "callouts", key: "idle_callout_max_seconds", type: "real", def: 110,
          comment: "Longest wait between one companion's idle lines, in seconds. Raise both numbers if the squad talks more than you want; lower them if the walk between towns feels empty." },
        { section: "callouts", key: "idle_callout_radius", type: "real", def: 220,
          comment: "How close to you a companion has to be to bother saying anything, in pixels. A line from someone off screen is noise, not atmosphere." },
        { section: "callouts", key: "idle_callout_needs_calm_seconds", type: "real", def: 12,
          comment: "Seconds of no enemy contact before idle chatter starts again. This is what stops a companion making small talk over the sound of the last body hitting the ground." },
        { section: "callouts", key: "callout_squad_cooldown_seconds", type: "real", def: 8,
          comment: "Seconds after any companion speaks before another may. Squad-wide, so four of them cannot talk over each other." },
        { section: "callouts", key: "callout_id_base", type: "real", def: 800,
          comment: "Where this mod's own speech lines are registered in the game's text table. The game's own lines stop at 321. Only worth changing if another mod happens to use the same range." },
        { section: "callouts", key: "callout_needs_sight", type: "bool", def: true,
          comment: "Hide a speech bubble when a wall is between you and the speaker, the way the game's own NPC lines behave. Off makes companions audible through walls." },
        { section: "callouts", key: "callout_text_timer", type: "real", def: 130,
          comment: "How long one of this mod's lines stays on screen, in frames. 130 is what the game uses for its own NPC speech." },

        // ---- selfcare ----------------------------------------------------
        // A wounded companion patching itself up. This is first aid only: it never
        // loots, never opens a container and never touches your inventory.
        { section: "selfcare", key: "selfcare_enabled", type: "bool", def: true,
          comment: "Badly hurt companions break contact and bandage themselves, using their own limited supplies." },
        { section: "selfcare", key: "selfcare_hp_threshold", type: "real", def: 0.45,
          comment: "How badly hurt is badly hurt, as a fraction of the companion's own maximum health. 0.45 means it starts thinking about bandages below 45 percent. Scales with difficulty, because the maximum does." },
        { section: "selfcare", key: "selfcare_heal_fraction", type: "real", def: 0.25,
          comment: "How much of that maximum one bandage gives back. Deliberately less than the threshold: first aid buys a companion the rest of the fight, it does not reset it." },
        { section: "selfcare", key: "selfcare_bind_seconds", type: "real", def: 3.0,
          comment: "Seconds spent standing still with the weapon down. This is the cost of the heal, and it is meant to be felt -- a companion caught bandaging is a companion not shooting." },
        { section: "selfcare", key: "selfcare_cooldown_seconds", type: "real", def: 60,
          comment: "Seconds before the same companion will bandage again, even with supplies left." },
        { section: "selfcare", key: "selfcare_charges", type: "real", def: 2,
          comment: "Bandages each companion carries per raid. Nothing is taken from your inventory and nothing is looted; this is what they brought with them. 0 turns the healing off while leaving everything else about the behaviour intact." },
        { section: "selfcare", key: "selfcare_require_no_target", type: "bool", def: true,
          comment: "Never bandage while it still has a live enemy of its own. On is the sane setting; off lets a companion try first aid mid-firefight, which is as bad an idea for them as it is for you." },
        { section: "selfcare", key: "selfcare_break_contact", type: "bool", def: true,
          comment: "Walk back toward you before starting. Only does visible work when there is something to walk away from -- see selfcare_require_no_target." },
        { section: "selfcare", key: "selfcare_interrupt_on_hit", type: "bool", def: true,
          comment: "Taking any damage while bandaging aborts it. No bandage is spent and no cooldown starts, so a companion interrupted twice will still try a third time." },

        // ---- idle_life ---------------------------------------------------
        // Eating, drinking and smoking, driven through the vanilla obj_arms_* props.
        // Each prop's own Step event destroys it as soon as the companion leaves the
        // matching human_state_now, so nothing here can leak an object.
        { section: "idle_life", key: "idle_life_enabled", type: "bool", def: true,
          comment: "During long quiet stretches a companion may sit down for a smoke, a drink or a bite. Interrupted instantly by contact." },
        { section: "idle_life", key: "idle_life_min_seconds", type: "real", def: 25,
          comment: "Shortest an idle animation lasts, in seconds." },
        { section: "idle_life", key: "idle_life_max_seconds", type: "real", def: 90,
          comment: "Longest an idle animation lasts, in seconds. A companion has to earn another calm stretch before it can start a second one." },
        { section: "idle_life", key: "idle_life_calm_seconds", type: "real", def: 25,
          comment: "How long a companion must have had nothing to shoot at before it will start. Deliberately longer than idle_callout_needs_calm_seconds: lighting a cigarette in the zone claims more safety than saying something does." },
        { section: "idle_life", key: "idle_life_max_concurrent", type: "real", def: 1,
          comment: "How many companions may be animating at once, across the whole squad. 1 means you see one of them take a break, not all of them." },
        { section: "idle_life", key: "idle_life_smoke_weight", type: "real", def: 40,
          comment: "Relative chance of a cigarette. The three weights are compared against each other, so any scale works." },
        { section: "idle_life", key: "idle_life_drink_weight", type: "real", def: 30,
          comment: "Relative chance of a drink." },
        { section: "idle_life", key: "idle_life_eat_weight", type: "real", def: 30,
          comment: "Relative chance of a bite to eat. Set all three to 0 to leave the feature on but silent." },

        // ---- desync ------------------------------------------------------
        // Everything that stops a squad looking like one object. Without it, four
        // companions run the same code on the same frame with the same numbers and
        // move as a single rigid body.
        { section: "desync", key: "desync_enabled", type: "bool", def: true,
          comment: "Give each companion its own timing, reaction delay and follow distance, so a squad stops moving in lockstep." },
        { section: "desync", key: "desync_seed_from_slot", type: "bool", def: true,
          comment: "Derive each companion's personal numbers from its squad slot instead of at random, so the same slot behaves the same way every raid. Off = fresh random every spawn." },
        { section: "desync", key: "desync_tick_jitter", type: "real", def: 3,
          comment: "Frames of spread in when companions take their decisions. Do not raise above 3: vanilla's own think interval is short, and more than this shows up as visible hesitation." },
        { section: "desync", key: "desync_reaction_jitter_frames", type: "real", def: 6,
          comment: "Extra frames, up to this many, that one companion holds a committed move longer than another. Pure variation; it does not slow anyone's shooting." },
        { section: "desync", key: "desync_follow_distance_jitter", type: "real", def: 8,
          comment: "Pixels of personal offset added to a companion's formation distance, so they do not all sit at the same radius." },
        { section: "desync", key: "temperament_enabled", type: "bool", def: true,
          comment: "Each companion gets a fixed personality score that nudges how eagerly it pushes and how often it talks. Off = every companion behaves identically." },

        // ---- input -------------------------------------------------------
        // Defaults are function keys so they cannot collide with the game's
        // movement/inventory bindings. Values are GameMaker virtual key codes:
        // F1=112 ... F12=123, A=65 ... Z=90, 0=48 ... 9=57.
        //
        // key_recruit is the deliberate exception: it is F, the same key vanilla
        // binds to Interact (scr_load_key_bindings line 53), because talking to the
        // recruiter should feel like talking to any other NPC. Both actions do fire
        // on one press -- this mod cannot consume a key press on vanilla's behalf --
        // but vanilla's Interact only does anything when the player is inside an
        // interactable's own range, which the recruiter's corner of the bar is not.
        // Move it to a function key if a future room change puts him next to one.
        { section: "input", key: "key_recruit", type: "real", def: 70,
          comment: "Near the recruiter NPC, opens the paid recruitment menu. Does nothing anywhere else. Set to 0 to disable. Default F, matching the game's own Interact key." },
        { section: "input", key: "key_debug_spawn", type: "real", def: 117,
          comment: "Instantly adds one free companion from default_preset, anywhere, ignoring price and the recruiter. Only works when debug_enabled is on. Default F6." },
        { section: "input", key: "key_dismiss", type: "real", def: 118,
          comment: "Dismiss the nearest companion. Default F7." },
        { section: "input", key: "key_toggle_hold", type: "real", def: 119,
          comment: "Toggle the squad between Follow and Hold. Default F8." },
        { section: "input", key: "key_toggle_hud", type: "real", def: 116,
          comment: "Show or hide the squad panel. Default F5. Resets to shown every launch." },
        { section: "input", key: "key_debug_dump", type: "real", def: 120,
          comment: "Dump full squad state to the log. Default F9." }
    ];
}


/// @func   csq_config_filename()
/// @desc   The GENERATED reference file. Rewritten from csq_config_spec() on every
///         launch, so it always describes the version that is actually running.
///         No value is ever read back out of it -- see csq_config_user_filename.
///
///         Relative, so it resolves inside the save area
///         (%LOCALAPPDATA%\ZERO_Sievert).
function csq_config_filename()
{
    return "csq_config.ini";
}


/// @func   csq_config_user_filename()
/// @desc   The USER file: the only file overrides are read from, and the only file
///         the mod will not overwrite. Created once as an all-commented template.
///
///         WHY THE CONFIG IS TWO FILES
///         There used to be one, written only when it did not already exist. That
///         is the only safe way to treat a single file -- rewriting it would eat the
///         player's edits -- but it means a mod update can never reach it. Every
///         setting added after the file was created is missing from it, every
///         default changed since is still described wrongly, and the player has no
///         way to find out except by reading CONFIGURATION.md. 1.0.0 shipped 61
///         settings, 1.1.0 had 97 and 1.2.0 has 146; a player upgrading from 1.0.0
///         would have seen none of the 85 added since.
///
///         Splitting the file makes both halves easy: the reference is disposable,
///         so it can be regenerated unconditionally and is always correct, and the
///         user file only ever holds the handful of lines the player typed, so it
///         survives every update untouched and can never drift out of date. It is
///         also far smaller, which makes "what have I actually changed?" answerable
///         at a glance.
function csq_config_user_filename()
{
    return "csq_config_user.ini";
}


/// @func   csq_config_parse_bool(_raw, _def)
/// @desc   Accepts true/false, yes/no, on/off and 1/0 in any casing.
function csq_config_parse_bool(_raw, _def)
{
    var _v = string_lower(string_trim(_raw));
    if (_v == "true" || _v == "1" || _v == "yes" || _v == "on")   return true;
    if (_v == "false" || _v == "0" || _v == "no" || _v == "off")  return false;
    return _def;
}


/// @func   csq_config_format_value(_type, _value)
/// @desc   Render a value the way the ini should contain it.
function csq_config_format_value(_type, _value)
{
    if (_type == "bool") return _value ? "true" : "false";
    return string(_value);
}


/// @func   csq_config_find_entry(_spec, _key)
/// @desc   The spec entry for a key, or undefined if the running version has no
///         such setting.
function csq_config_find_entry(_spec, _key)
{
    for (var _i = 0; _i < array_length(_spec); _i++)
    {
        if (_spec[_i].key == _key) return _spec[_i];
    }

    return undefined;
}


/// @func   csq_config_parse_typed(_entry, _text)
/// @desc   One raw ini string to a typed value, falling back to the entry's own
///         default. The single place a line's type is interpreted, so the loader
///         and the stray-value diff below can never disagree about what a line
///         means.
function csq_config_parse_typed(_entry, _text)
{
    switch (_entry.type)
    {
        case "bool":
            return csq_config_parse_bool(_text, _entry.def);

        case "real":
            // Reject non-numeric text rather than feeding NaN downstream.
            if (string_trim(_text) != "" && is_numeric(real(_text))) return real(_text);
            return _entry.def;

        default:
            return string_trim(_text);
    }
}


/// @func   csq_config_is_default(_entry, _text)
/// @desc   Whether a raw ini line carries this setting's default value.
///
///         Compared after parsing rather than as text, so "TRUE", "on" and "1" all
///         count as equal to `true`, and "3" as equal to `3.0`.
///
///         REALS ARE COMPARED AS SCALED INTEGERS, NOT AGAINST A TOLERANCE
///         This was `abs(_v - _entry.def) < 0.0000001`, which reported every single
///         real-valued setting as different from its default -- 45 keys "edited" in a
///         file where 3 were. Whatever the compiler does with a literal that small,
///         it is not a positive number by the time the comparison runs, and
///         `abs(0) < 0` is false for every key that matches. Scaling both sides and
///         rounding needs no epsilon at all, and four decimals is more precision
///         than the reference file can even express: it is written with string(),
///         which renders a real to two.
function csq_config_is_default(_entry, _text)
{
    var _v = csq_config_parse_typed(_entry, _text);

    if (_entry.type == "real") return (round(_v * 10000) == round(_entry.def * 10000));

    return (_v == _entry.def);
}


/// @func   csq_config_write_reference_file()
/// @desc   Generate the fully commented reference ini from csq_config_spec().
///
///         WHY THIS IS REWRITTEN EVERY LAUNCH
///         It is a generated document, not state: every line in it is derived from
///         the spec, so throwing it away and remaking it loses nothing and
///         guarantees it matches the code. New settings appear the first time an
///         updated build runs, changed defaults are described correctly, and a
///         setting a future version drops disappears instead of lingering as a line
///         that no longer does anything.
///
///         That is only safe because overrides live in csq_config_user_filename()
///         and nothing here is ever read back for its value. A player who edits
///         this file anyway is rescued by csq_config_adopt_strays rather than
///         quietly reverted.
/// @return {Bool} whether the file was written
function csq_config_write_reference_file()
{
    var _spec = csq_config_spec();
    var _f = -1;

    try
    {
        _f = file_text_open_write(csq_config_filename());

        var _bar = "; ==========================================================";

        file_text_write_string(_f, _bar); file_text_writeln(_f);
        // Stamped with the mod identity rather than a literal, so a config file
        // attached to a bug report says which version generated it. Safe to call
        // across modules here for the same reason csq_config_load can call
        // csq_log_info: every csq_* global script is registered by the time any
        // object event runs.
        file_text_write_string(_f, ";  " + csq_mod_name() + " v" + csq_mod_version() +
                                   " -- generated reference");                              file_text_writeln(_f);
        file_text_write_string(_f, ";");                                                    file_text_writeln(_f);
        file_text_write_string(_f, ";  DO NOT EDIT THIS FILE. It is rewritten from scratch"); file_text_writeln(_f);
        file_text_write_string(_f, ";  every time the game starts.");                        file_text_writeln(_f);
        file_text_write_string(_f, ";");                                                    file_text_writeln(_f);
        file_text_write_string(_f, ";  Put your own settings in:");                          file_text_writeln(_f);
        file_text_write_string(_f, ";      " + csq_config_user_filename());                  file_text_writeln(_f);
        file_text_write_string(_f, ";  Only the lines you want to change -- everything else"); file_text_writeln(_f);
        file_text_write_string(_f, ";  uses the default listed below.");                     file_text_writeln(_f);
        file_text_write_string(_f, ";");                                                    file_text_writeln(_f);
        file_text_write_string(_f, ";  If you do edit this file by mistake, the mod moves");  file_text_writeln(_f);
        file_text_write_string(_f, ";  your changes into the user file for you and says so"); file_text_writeln(_f);
        file_text_write_string(_f, ";  in logs/csq_log.txt. Nothing is lost.");              file_text_writeln(_f);
        file_text_write_string(_f, ";");                                                    file_text_writeln(_f);
        file_text_write_string(_f, ";  Full reference: CONFIGURATION.md in the mod download.");file_text_writeln(_f);
        file_text_write_string(_f, _bar); file_text_writeln(_f);

        var _current_section = "";
        for (var _i = 0; _i < array_length(_spec); _i++)
        {
            var _e = _spec[_i];

            if (_e.section != _current_section)
            {
                _current_section = _e.section;
                file_text_writeln(_f);
                file_text_write_string(_f, "[" + _current_section + "]");
                file_text_writeln(_f);
            }

            file_text_write_string(_f, "; " + _e.comment);
            file_text_writeln(_f);
            file_text_write_string(_f, _e.key + " = " + csq_config_format_value(_e.type, _e.def));
            file_text_writeln(_f);
        }

        file_text_close(_f);
        return true;
    }
    catch (_err)
    {
        // Never let a config problem stop the mod loading -- defaults are fine.
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
        return false;
    }
}


/// @func   csq_config_read_file(_file)
/// @desc   Parse "key = value" lines out of one ini, ignoring blanks, [sections]
///         and ; or # comments. Section headers are cosmetic; keys are unique.
///
///         A later line wins over an earlier one with the same key, which is what
///         makes csq_config_adopt_strays able to append rather than rewrite.
/// @param  {String} _file  which ini to read; a missing file is not an error
/// @return {Struct} raw string values keyed by setting name
function csq_config_read_file(_file)
{
    var _raw = {};
    var _f = -1;

    try
    {
        if (!file_exists(_file)) return _raw;

        _f = file_text_open_read(_file);

        while (!file_text_eof(_f))
        {
            var _line = string_trim(file_text_read_string(_f));
            file_text_readln(_f);

            if (_line == "") continue;

            var _first = string_char_at(_line, 1);
            if (_first == ";" || _first == "#" || _first == "[") continue;

            var _eq = string_pos("=", _line);
            if (_eq <= 1) continue;

            var _key = string_trim(string_copy(_line, 1, _eq - 1));
            var _val = string_trim(string_delete(_line, 1, _eq));

            if (_key != "") variable_struct_set(_raw, _key, _val);
        }

        file_text_close(_f);
    }
    catch (_err)
    {
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
    }

    return _raw;
}


/// @func   csq_config_write_user_stub()
/// @desc   Create the user file if it is absent: a header explaining the split and
///         a handful of commented-out examples. Never called when the file already
///         exists, so a player's own file is never touched.
///
///         Examples are commented out rather than written live because an empty
///         override file has to mean "everything default". A stub that actually set
///         five values would silently change the game for a player who never opened
///         it.
/// @return {Bool} whether the file was created
function csq_config_write_user_stub()
{
    if (file_exists(csq_config_user_filename())) return false;

    var _f = -1;

    try
    {
        _f = file_text_open_write(csq_config_user_filename());

        var _bar = "; ==========================================================";
        var _lines = [
            _bar,
            ";  " + csq_mod_name() + " -- your settings",
            ";",
            ";  This file is yours. The mod creates it once and then only",
            ";  ever appends to it, to rescue a change you made in",
            ";  " + csq_config_filename() + " by mistake.",
            ";",
            ";  Put ONLY the lines you want to change here. Anything not",
            ";  listed uses the default from " + csq_config_filename() + ",",
            ";  which is regenerated every launch and lists every setting",
            ";  with a description of what it does.",
            ";",
            ";  Save, then restart the game -- config is read once at boot.",
            ";",
            ";  Section headers are cosmetic: key names are unique, so a",
            ";  key works wherever you put it in this file.",
            _bar,
            "",
            "; Examples. Delete the leading ; to switch one on.",
            "",
            "; max_companions = 4",
            "; hp_multiplier = 2",
            "; heal_charges = 4",
            "; recruit_tier1_price = 1500",
            "; reveal_cone_strength = 0.75",
            "; hud_scale = 1.5"
        ];

        for (var _i = 0; _i < array_length(_lines); _i++)
        {
            file_text_write_string(_f, _lines[_i]);
            file_text_writeln(_f);
        }

        file_text_close(_f);
        return true;
    }
    catch (_err)
    {
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
        return false;
    }
}


/// @func   csq_config_key_in(_array, _key)
/// @desc   Written out rather than using array_contains, which the base game never
///         calls -- and a built-in absent from data.win's function table is a
///         recompile risk that is not worth taking for a three-line loop.
function csq_config_key_in(_array, _key)
{
    for (var _i = 0; _i < array_length(_array); _i++)
    {
        if (_array[_i] == _key) return true;
    }

    return false;
}


/// @func   csq_config_repurposed_keys()
/// @desc   Keys that must NOT be carried forward by csq_config_adopt_strays, because
///         their meaning changed rather than merely their default.
///
///         Adoption works by asking "does this line differ from the current
///         default?", which cannot tell a value the player chose from a value that
///         was simply the default of an older release. For almost every setting that
///         does not matter -- being pinned to the old default is the conservative
///         reading, and it is what the player was running. For a key whose *job*
///         changed it is actively wrong.
///
///         key_recruit is the one case so far. In 1.0.0 it was 117 (F6) and spawned
///         a free companion; in 1.1.0 it is 70 (F) and opens the paid recruiter menu,
///         while 117 became key_debug_spawn. Adopting an old `key_recruit = 117`
///         would put two different commands on F6 and leave the recruiter menu
///         unreachable, so the new default wins and the log says why.
///
///         Keep this list short and delete from it once a release is old enough that
///         nobody is upgrading across the change.
function csq_config_repurposed_keys()
{
    return ["key_recruit"];
}


/// @func   csq_config_adopt_strays(_spec, _ref_raw, _user_raw)
/// @desc   Move any hand-edited value out of the generated reference file and into
///         the user file, and into this session's overrides.
///
///         WHY THIS EXISTS
///         csq_config.ini was the only config file for the first release, and it is
///         still the file named in every guide, screenshot and forum post. Now that
///         it is regenerated on every launch, a player editing it would have their
///         work reverted the next time they started the game -- a worse failure than
///         the staleness the split was introduced to fix, because it is silent.
///
///         So anything in the reference file that is not the current default is
///         treated as something the player meant, and is copied where it will
///         survive. Appended rather than rewritten, because a later line wins in
///         csq_config_read_file, and because appending cannot damage whatever else
///         the player has in there.
///
///         THIS ALSO PERFORMS THE UPGRADE FROM 1.0.0 WITH NO ACTION FROM THE PLAYER
///         On the first launch after updating there is no user file at all and the
///         old single config is a pile of strays, so the player's entire previous
///         configuration is adopted wholesale and nothing has to be re-typed.
///
///         Three things are deliberately not adopted. A key the running version does
///         not know is skipped, so a setting a future release drops does not get
///         copied forward forever. A key the user file already sets is skipped,
///         because the user file is the authority -- appending would silently
///         override the player's own line with an older stray. And a key whose
///         meaning changed between releases is skipped; see
///         csq_config_repurposed_keys.
/// @return {Struct} {adopted, unknown, shadowed, repurposed: Array<String>, persisted: Bool}
function csq_config_adopt_strays(_spec, _ref_raw, _user_raw)
{
    var _out  = { adopted: [], unknown: [], shadowed: [], repurposed: [], persisted: true };
    var _skip = csq_config_repurposed_keys();
    var _keys = variable_struct_get_names(_ref_raw);

    for (var _i = 0; _i < array_length(_keys); _i++)
    {
        var _key   = _keys[_i];
        var _text  = variable_struct_get(_ref_raw, _key);
        var _entry = csq_config_find_entry(_spec, _key);

        if (is_undefined(_entry))
        {
            array_push(_out.unknown, _key);
            continue;
        }

        if (csq_config_is_default(_entry, _text)) continue;

        if (csq_config_key_in(_skip, _key))
        {
            array_push(_out.repurposed, _key);
            continue;
        }

        if (variable_struct_exists(_user_raw, _key))
        {
            array_push(_out.shadowed, _key);
            continue;
        }

        // Honour it this launch as well as saving it, so the edit takes effect
        // immediately instead of only after another restart.
        variable_struct_set(_user_raw, _key, _text);
        array_push(_out.adopted, _key);
    }

    if (array_length(_out.adopted) == 0) return _out;

    var _f = -1;

    try
    {
        _f = file_text_open_append(csq_config_user_filename());

        file_text_writeln(_f);
        file_text_write_string(_f, "; ---- moved here from " + csq_config_filename() +
                                   " by v" + csq_mod_version() + " ----");
        file_text_writeln(_f);
        file_text_write_string(_f, "; That file is regenerated every launch, so these would");
        file_text_writeln(_f);
        file_text_write_string(_f, "; not have survived. Edit or delete them freely.");
        file_text_writeln(_f);

        for (var _j = 0; _j < array_length(_out.adopted); _j++)
        {
            var _k = _out.adopted[_j];
            file_text_write_string(_f, _k + " = " + variable_struct_get(_ref_raw, _k));
            file_text_writeln(_f);
        }

        file_text_close(_f);
    }
    catch (_err)
    {
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }

        // The values are live for this session either way -- they went into
        // _user_raw above. Only persistence failed, so report that distinctly
        // instead of claiming a save that did not happen.
        _out.persisted = false;
    }

    return _out;
}


/// @func   csq_config_load()
/// @desc   Populate global.csq_cfg_values from the spec defaults, then overlay the
///         user file. Always succeeds: a missing or malformed file just means
///         defaults. Safe to call more than once.
///
///         ORDER MATTERS HERE
///         The reference file is read BEFORE it is regenerated, because that read is
///         the only chance to notice a player has edited it. Regenerating first
///         would destroy the evidence along with their work.
/// @return {Struct} the populated config struct
function csq_config_load()
{
    var _spec = csq_config_spec();

    // 1. Read both files as they stand.
    var _ref_raw  = csq_config_read_file(csq_config_filename());
    var _user_raw = csq_config_read_file(csq_config_user_filename());

    // 2. Make sure there is somewhere for overrides to live before anything tries
    //    to append to it.
    var _stubbed = csq_config_write_user_stub();

    // 3. Rescue anything the player typed into the generated file.
    var _stray = csq_config_adopt_strays(_spec, _ref_raw, _user_raw);

    // 4. Regenerate the reference, now that nothing needs the old copy.
    var _wrote = csq_config_write_reference_file();

    // 5. Defaults, overlaid with the user file.
    var _values    = {};
    var _overrides = 0;

    for (var _i = 0; _i < array_length(_spec); _i++)
    {
        var _e     = _spec[_i];
        var _value = _e.def;

        if (variable_struct_exists(_user_raw, _e.key))
        {
            var _text = variable_struct_get(_user_raw, _e.key);
            _value    = csq_config_parse_typed(_e, _text);

            // A line that parses back to the default is either belt-and-braces or a
            // value the mod refused, so it is not counted as an override.
            if (!csq_config_is_default(_e, _text)) _overrides++;
        }

        variable_struct_set(_values, _e.key, _value);
    }

    global.csq_cfg_values = _values;

    // Logging is only available once csq_log has been initialised; csq_init orders
    // that before this call, so these lines are safe.
    if (_wrote)   csq_log_debug("config: regenerated " + csq_config_filename());
    if (_stubbed) csq_log_info("config: created " + csq_config_user_filename() +
                               " for your own settings");

    csq_log_info("config: " + string(_overrides) + " override(s) from " +
                 csq_config_user_filename() + ", " +
                 string(array_length(_spec) - _overrides) + " default(s)");

    if (array_length(_stray.adopted) > 0)
    {
        // INFO, not DEBUG: the player edited a file and the mod moved their edit
        // somewhere else. That is something they are entitled to be told about
        // without first turning on debug logging.
        csq_log_info("config: moved " + string(array_length(_stray.adopted)) +
                     " edited setting(s) out of " + csq_config_filename() + " into " +
                     csq_config_user_filename() + " (" +
                     csq_config_key_list(_stray.adopted) + ")");

        if (!_stray.persisted)
        {
            csq_log_warn("config: could not append to " + csq_config_user_filename() +
                         "; those settings work now but will be lost on restart");
        }
    }

    if (array_length(_stray.repurposed) > 0)
    {
        // WARN rather than INFO: the player had a value and is not getting it. They
        // are entitled to know which key and that the new default is in force.
        csq_log_warn("config: " + csq_config_key_list(_stray.repurposed) +
                     " changed meaning in v" + csq_mod_version() +
                     " and was not carried over; the new default is in use. See " +
                     "CONFIGURATION.md [input]");
    }

    if (array_length(_stray.shadowed) > 0)
    {
        csq_log_warn("config: ignored " + string(array_length(_stray.shadowed)) +
                     " edit(s) in " + csq_config_filename() + " already set in " +
                     csq_config_user_filename() + " (" +
                     csq_config_key_list(_stray.shadowed) + ")");
    }

    // Typos are the single most common config problem, and the old "N key(s) absent"
    // warning cannot detect them any more: an absent key is now the normal case.
    var _unknown = csq_config_unknown_keys(_spec, _user_raw);
    if (array_length(_unknown) > 0)
    {
        csq_log_warn("config: " + string(array_length(_unknown)) +
                     " unrecognised key(s) in " + csq_config_user_filename() +
                     ", ignored (" + csq_config_key_list(_unknown) + ")");
    }

    return _values;
}


/// @func   csq_config_unknown_keys(_spec, _raw)
/// @desc   Keys present in a parsed ini that the running version has no setting
///         for -- almost always a typo, occasionally a leftover from an older
///         release.
function csq_config_unknown_keys(_spec, _raw)
{
    var _out  = [];
    var _keys = variable_struct_get_names(_raw);

    for (var _i = 0; _i < array_length(_keys); _i++)
    {
        if (is_undefined(csq_config_find_entry(_spec, _keys[_i])))
        {
            array_push(_out, _keys[_i]);
        }
    }

    return _out;
}


/// @func   csq_config_key_list(_keys)
/// @desc   Key names for one log line, capped so a wholesale 1.0.0 adoption cannot
///         write a 60-name paragraph into the log.
function csq_config_key_list(_keys)
{
    var _max = 8;
    var _n   = array_length(_keys);
    var _s   = "";

    for (var _i = 0; _i < min(_n, _max); _i++)
    {
        if (_i > 0) _s += ", ";
        _s += _keys[_i];
    }

    if (_n > _max) _s += ", +" + string(_n - _max) + " more";

    return _s;
}


/// @func   csq_cfg(_key)
/// @desc   Read one setting. Falls back to the spec default if config has not
///         been loaded yet, so callers never have to null-check.
function csq_cfg(_key)
{
    if (variable_global_exists("csq_cfg_values"))
    {
        if (variable_struct_exists(global.csq_cfg_values, _key))
        {
            return variable_struct_get(global.csq_cfg_values, _key);
        }
    }

    // Fallback: linear scan of the spec. Only reached before load, or for a
    // typo'd key, so the cost does not matter.
    var _spec = csq_config_spec();
    for (var _i = 0; _i < array_length(_spec); _i++)
    {
        if (_spec[_i].key == _key) return _spec[_i].def;
    }

    return undefined;
}
