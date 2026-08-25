// =============================================================================
//  Zone Companions  -  csq_init
// -----------------------------------------------------------------------------
//  The mod's lifecycle entry points. Five of the mod's nine code patches append a
//  single call to a vanilla object event, and each of those five calls exactly one
//  function in this file and nothing else -- so the mod's whole lifecycle is the
//  five functions below.
//
//  LIFECYCLE
//    csq_boot()          obj_cursor_Create_0        once, on the logo screen
//    csq_on_map_load()   obj_controller_Create_0    every hub or raid load
//    csq_tick()          obj_player_Step_0          every frame, hub and raid
//    csq_hud_draw()      obj_controller_Draw_64     every frame (see csq_hud)
//    csq_on_raid_exit()  obj_exit_screen_Create_0   when a raid ends
//
//  Those five events are the ones the GMLoader ZERO Sievert guide documents as
//  mod entry points, which is why they were chosen over any others.
//
//  THE OTHER FOUR PATCHES ARE NOT LIFECYCLE AND ARE NOT ROUTED THROUGH HERE
//  They are guards and hooks prepended inside a specific vanilla function, where
//  the only sensible caller is that function: two in the bullet-collision
//  predicates (csq_ff), one in player_line_of_sight and one part-way through
//  obj_fog_setup_Draw_0 (both csq_reveal). Each documents its own preconditions at
//  the definition. See mods/config/code_patch/10_zone_companions.yaml for the
//  complete list.
//
//  WHY SPAWNING IS DEFERRED OUT OF THE MAP-LOAD EVENT
//  obj_controller_Create_0 fires before the map generator has finished, so
//  global.grid_move and obj_controller.grid_motion are not usable yet and the
//  player instance may not exist. Spawning there would put companions inside
//  walls or fail outright. So map load only records the *intent* to spawn, and
//  csq_tick performs it once the player exists and the settle delay has passed --
//  obj_player_Step_0 cannot run before there is a player, which makes it the
//  natural place for work that needs a live world.
//
//  WHY EVERY ENTRY POINT CALLS csq_boot FIRST
//  A global script's top-level body is not guaranteed to run at game start, so
//  there is no reliable "module load" moment to hook. Instead each entry point
//  self-heals: csq_boot is idempotent and cheap after the first call, so
//  whichever event fires first performs the initialisation. That also means the
//  mod recovers if the boot patch itself ever fails to apply.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_mod_name()
/// @desc   Identity, reported in the log header and on error.
function csq_mod_name()    { return "Zone Companions"; }
function csq_mod_version() { return "1.1.1"; }


/// @func   csq_boot()
/// @desc   One-time initialisation: logging, configuration, globals. Idempotent
///         and safe to call from any event, at any time.
/// @return {Bool} whether this call performed the initialisation
function csq_boot()
{
    if (variable_global_exists("csq_booted") && global.csq_booted) return false;

    // Set the flag first. If anything below throws, a later entry point will not
    // loop trying to boot again every single frame.
    global.csq_booted = true;

    try
    {
        // Order matters exactly once, here: logging comes up before anything
        // else so that config problems are reportable. csq_log falls back to
        // spec defaults until csq_config_load has run, so this is safe.
        csq_log_init();

        csq_log_info("==== " + csq_mod_name() + " v" + csq_mod_version() + " starting ====");

        csq_config_load();

        // Re-apply the level now that real config is available; csq_log_init ran
        // against defaults.
        csq_log_info("boot: log level " + csq_log_level_name(csq_cfg("log_level")) +
                     ", debug " + (csq_cfg("debug_enabled") ? "on" : "off"));

        // Sanity-check the player-editable reputation values against the
        // thresholds the game classifies on. Done here rather than at faction
        // registration so it reports once per session instead of on every map
        // load, and so a bad value is visible in the log before anything spawns.
        csq_faction_validate_config();

        csq_squad_init();

        global.csq_want_spawn      = false;
        global.csq_spawn_countdown = 0;
        global.csq_persist_loaded  = false;
        global.csq_persist_source  = "";
        global.csq_grid_wait_logged = false;
        global.csq_intro_wait_logged = false;

        // Medic bookkeeping. csq_medic_id is the "one companion is on its way to
        // heal you" claim -- without it every companion in the squad would break
        // formation for the same wound. noone means the job is unclaimed.
        global.csq_medic_id       = noone;
        global.csq_heal_refilled  = false;

        csq_log_info("boot: initialised, max " + string(csq_squad_max()) + " companion(s)");
        csq_log_info("boot: keys - recruit " + string(csq_input_key("key_recruit")) +
                     ", dismiss " + string(csq_input_key("key_dismiss")) +
                     ", hold "    + string(csq_input_key("key_toggle_hold")) +
                     ", panel "   + string(csq_input_key("key_toggle_hud")) +
                     ", dump "    + string(csq_input_key("key_debug_dump")) +
                     ", debug spawn " + string(csq_input_key("key_debug_spawn")));

        return true;
    }
    catch (_err)
    {
        // Boot failing must not take the game with it. The mod simply does
        // nothing, and says so as loudly as it can.
        csq_log_exception("csq_boot", _err);
        return false;
    }
}


/// @func   csq_on_map_load()
/// @desc   A hub or raid map has started loading. Registers the faction, pulls
///         the roster out of the save, and arms a deferred spawn.
function csq_on_map_load()
{
    csq_boot();

    try
    {
        csq_log_debug("map load: raid=" + string(csq_in_raid()) + " hub=" + string(csq_in_hub()));

        // Runs after vanilla faction_load(), which rebuilds both faction
        // registries from the save -- so the companion faction has to be
        // re-registered on every load, not just once.
        csq_faction_register();

        // The save database is only reliably loaded by this point if a character
        // is actually in play; csq_persist handles that itself and no-ops
        // otherwise, so this can be called unconditionally.
        csq_persist_load();

        // Any instances from the previous map are gone. Clear the cached ids so
        // the roster does not hold pointers into a destroyed room.
        csq_squad_forget_instances();

        // Arm the per-raid medic refill and drop any stale claim. Deliberately
        // *armed* here rather than performed here -- see csq_tick_refill_heal_charges.
        global.csq_heal_refilled = false;
        global.csq_medic_id      = noone;

        // Arm the deferred spawn (see the header note).
        if (csq_cfg("auto_spawn_in_raid"))
        {
            global.csq_want_spawn        = true;
            global.csq_spawn_countdown   = max(0, csq_cfg("spawn_delay_frames"));
            global.csq_grid_wait_logged  = false;
            global.csq_intro_wait_logged = false;

            csq_log_debug("map load: spawn armed, " +
                          string(global.csq_spawn_countdown) + " frame delay");
        }
    }
    catch (_err)
    {
        csq_log_exception("csq_on_map_load", _err);
    }
}


/// @func   csq_squad_forget_instances()
/// @desc   Drop every cached instance id without touching the roster. Lives here
///         rather than in csq_squad because it is purely a lifecycle concern:
///         a room change invalidates ids, and nothing died.
function csq_squad_forget_instances()
{
    csq_squad_init();

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        global.csq_squad[_i].inst = noone;
    }
}


/// @func   csq_tick_deferred_spawn()
/// @desc   Run the armed spawn once the world is actually ready for it.
function csq_tick_deferred_spawn()
{
    if (!global.csq_want_spawn) return;

    // Only raids get companions. In the hub they stay on the roster.
    if (!csq_in_raid())
    {
        global.csq_want_spawn = false;
        csq_log_debug("spawn: disarmed, not in a raid");
        return;
    }

    if (global.csq_spawn_countdown > 0)
    {
        global.csq_spawn_countdown--;
        return;
    }

    // Wait until the player is actually standing in the world.
    //
    // On a train-spawn map the raid opens in scr_player_state_start, which pins
    // the player's x/y to obj_train every frame. Spawning against that position
    // drops the squad at the boarding point and the train then leaves without
    // them -- which is exactly what happened before this check existed. The
    // 30-frame countdown was never going to be enough, because the intro lasts
    // as long as the ride does, not a fixed number of frames.
    if (!csq_player_in_world(id))
    {
        if (!global.csq_intro_wait_logged)
        {
            global.csq_intro_wait_logged = true;
            csq_log_debug("spawn: waiting for the player to leave the raid intro");
        }
        return;
    }

    global.csq_intro_wait_logged = false;

    // Wait for the navigation grid rather than counting frames forever -- a slow
    // machine may still be generating the map when the countdown expires.
    if (!csq_pos_walkable(x, y))
    {
        // x/y here are the player's, since this runs inside obj_player_Step_0.
        //
        // Logged once, not once per frame: csq_log appends to the log file on
        // every call, so a per-frame DEBUG line would mean a file open per frame.
        if (!global.csq_grid_wait_logged)
        {
            global.csq_grid_wait_logged = true;
            csq_log_debug("spawn: waiting for the navigation grid");
        }
        return;
    }

    global.csq_grid_wait_logged = false;
    global.csq_want_spawn       = false;

    csq_squad_spawn_all();
}


/// @func   csq_tick_refill_heal_charges()
/// @desc   Refill every companion's medic charges once per raid entry.
///
///         WHY THIS IS NOT DONE IN csq_on_map_load
///         That event is obj_controller_Create_0, which fires while the map is
///         still coming up -- the same reason spawning is deferred out of it. The
///         spawn path already declines to trust csq_in_raid() at that moment and
///         re-tests it from the tick instead. Refilling has the identical problem:
///         a raid load that reported "not in a raid" would leave the squad with no
///         heals for the entire run.
///
///         So map load only *arms* the refill by clearing global.csq_heal_refilled,
///         and this runs it the first frame we are demonstrably in a raid with a
///         live player. Cost while idle is one boolean test per frame.
function csq_tick_refill_heal_charges()
{
    if (global.csq_heal_refilled) return;
    if (!csq_in_raid())           return;

    global.csq_heal_refilled = true;
    csq_squad_refill_heal_charges();
}


/// @func   csq_tick()
/// @desc   Per-frame work that is not a companion's own behaviour. Called from
///         obj_player_Step_0, so `self` is the player and a player is guaranteed
///         to exist.
function csq_tick()
{
    csq_boot();

    try
    {
        csq_input_step();
        csq_squad_prune();

        // After prune, so a confirmed death is off the roster before we try to
        // rescue anything, and before the deferred spawn counts live companions.
        csq_squad_recover_deactivated();

        csq_tick_refill_heal_charges();
        csq_tick_deferred_spawn();

        // Recruiter NPC: (re)place it in the hub, watch the player's distance to
        // it, and drive the hire menu. Self-contained in csq_recruit; a no-op when
        // the feature is disabled or we are not in the hub.
        csq_recruit_tick();

        // Last, and after prune, so the sight cache only ever holds companions that
        // were live this frame. Everything that asks "can my squad see this point"
        // -- vanilla's NPC and chest visibility fades, and the fog subtract in
        // obj_fog_setup's Draw event -- reads what this builds.
        csq_reveal_sight_cache();
    }
    catch (_err)
    {
        csq_log_exception("csq_tick", _err);
    }
}


/// @func   csq_on_raid_exit()
/// @desc   The raid is over. Take companions out of the world and commit the
///         roster to the save, so HP carried out of one raid is there at the
///         start of the next.
function csq_on_raid_exit()
{
    csq_boot();

    try
    {
        csq_log_info("raid exit: " + string(csq_squad_active_count()) +
                     " companion(s) came out with you");

        csq_squad_despawn_all();
        csq_persist_save();

        global.csq_want_spawn = false;
    }
    catch (_err)
    {
        csq_log_exception("csq_on_raid_exit", _err);
    }
}
