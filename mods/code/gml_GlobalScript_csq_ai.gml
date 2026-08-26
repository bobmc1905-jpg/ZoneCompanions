// =============================================================================
//  Zone Companions  -  csq_ai
// -----------------------------------------------------------------------------
//  Decides what a companion is doing, and hands combat to the vanilla AI.
//
//  THE MOD CONTAINS NO COMBAT CODE. That is deliberate. obj_csq_companion
//  descends from obj_npc_human_parent, so it already owns the game's entire NPC
//  brain. This module only chooses which vanilla behaviour is in charge:
//
//      MODE      state              who drives movement
//      follow    "human_no_move"    this module (move_point_x/y + path_speed)
//      engage    "human_general"    vanilla utility AI -- cover, fire, reload
//      hold      "human_no_move"    nobody; the companion stands still
//      medic     "human_no_move"    this module, straight at the player
//
//  WHY state MUST ALWAYS BE A REAL VANILLA VALUE
//  obj_npc_parent_Step_0's switch ends with
//      default: trace_error("State \"", state, "\" unhandled");
//  and trace_error finishes with show_error(..., true) -- which is *fatal*. A
//  custom state string would therefore hard-crash the game every single frame.
//  So the companion's own mode lives in `csq_mode`, and `state` only ever holds
//  a string the vanilla machine already understands.
//
//  WHY "human_no_move" IS THE FOLLOW HOST STATE
//  Its entire case body is:
//      if (player_exists_local()) target_for_image_scale = _player.x;
//  No targeting, no pathing, no movement. That makes it a genuinely inert
//  host: this module owns movement completely while `state` stays legitimate.
//
//  WHY "human_general" IS THE COMBAT HOST STATE
//  It is the modern AI vanilla humans actually use -- gamedata/npc.json gives
//  loner_regular state_patrol AND state_alert of "human_general". It is a
//  ds_priority utility selector re-evaluated every human_tick_max ticks, which
//  picks between cover, shooting, flanking, reloading and grenades. Handing off
//  gives companions the best AI in the game for free. Entering it is safe: the
//  nested switch (human_state_now) has no default case, and
//  obj_npc_parent_Create_0 initialises human_state_now = -1, so a stale value
//  falls through harmlessly until the selector assigns a real sub-state.
//
//  THE LEASH IS A VANILLA FEATURE, NOT A CUSTOM SCAN
//  scr_find_target_for_human discards any target further than `leash_radius`
//  from `original_x/original_y` when `leash_to_spawn` is true. Repointing
//  original_x/y at the player every frame turns that into exactly "do not chase
//  enemies far from the player", with no custom scanning at all. It also makes
//  vanilla's own idle wandering recentre on the player, because human_general
//  sub-state Value_9 is scr_enemy_choose_move_pos(original_x, original_y, 0).
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_ai_mode_follow()
/// @desc   Mode name constants, so no module compares raw strings.
function csq_ai_mode_follow() { return "follow"; }
function csq_ai_mode_engage() { return "engage"; }
function csq_ai_mode_hold()   { return "hold"; }
function csq_ai_mode_medic()  { return "medic"; }


/// @func   csq_ai_state_idle()
/// @desc   The vanilla state strings this module parks the companion in.
///         Both are verified members of obj_npc_parent_Step_0's switch.
function csq_ai_state_idle()   { return "human_no_move"; }
function csq_ai_state_combat() { return "human_general"; }


/// @func   csq_ai_init_instance()
/// @desc   Set up the companion-specific instance variables. Runs in the
///         companion's Create event, after event_inherited() and npc_setup so
///         nothing here is clobbered by vanilla initialisation.
function csq_ai_init_instance()
{
    csq_mode          = csq_ai_mode_follow();
    csq_slot          = 0;
    csq_face          = 0;      // last known player facing, for the formation
    csq_scan_timer    = 0;
    csq_no_target     = 0;      // frames with no hostile target
    csq_path_fail     = 0;      // consecutive frames of failed pathing

    // Current wander offset from the formation slot, and the countdown to the
    // next re-roll. Zero means "stand exactly on the slot", which is also what
    // roaming collapses to whenever the player is moving.
    csq_roam_x        = 0;
    csq_roam_y        = 0;
    csq_roam_timer    = 0;

    // Smoothed aim heading, used to slide the formation toward the cursor. Seeded
    // from the live aim so the first frame does not drag the squad round from 0
    // degrees; falls back to 0 if the player cannot be read yet.
    csq_aim_dir       = 0;

    try
    {
        var _p = csq_player();
        if (_p != noone) csq_aim_dir = point_direction(_p.x, _p.y, _p.aim_point_x, _p.aim_point_y);
    }
    catch (_ignored) {}

    // Frames until this companion may heal again. Note that the *charges* live on
    // the roster entry instead (see csq_squad_make_entry): a cooldown is allowed
    // to reset when an instance is culled and respawned, a charge count is not.
    csq_heal_cd       = 0;

    // Countdown to the next flashlight-presence check. Zero means the very first
    // Step verifies the light, which is what you want for a companion respawned
    // mid-raid -- see csq_ai_torch_ensure for why it needs verifying at all.
    csq_torch_timer   = 0;

    // ---- identity ----------------------------------------------------------
    // Per-companion timing, reaction and disposition. Called here rather than from
    // the Create event so that every companion variable is set in one place, and
    // early enough that anything below could read the values if it ever needs to.
    //
    // It is the only thing in this file that adjusts human_tick_max_ref, and it does
    // so exactly once. See csq_human for why the seed comes from
    // global.csq_pending_slot and not from csq_slot.
    csq_human_init_instance();

    // ---- self-care ---------------------------------------------------------
    // The bandage machine's own state. Bandages themselves live on the roster, not
    // here -- see the note at the top of csq_care.
    csq_care_init_instance();

    // ---- idle chatter ------------------------------------------------------
    // Rolls this companion's first wait, so a squad that spawns together does not
    // all speak on the frame it lands.
    csq_voice_init_instance();

    // ---- idle life ---------------------------------------------------------
    // Counters for the smoke/drink/eat gate. All zero, so a companion has to earn a
    // full calm stretch after spawning before it can sit down.
    csq_idle_init_instance();

    // ---- combat footwork ---------------------------------------------------
    // Push state. csq_push_timer counts down the frames left in a committed move;
    // csq_push_cd covers the move plus the pause after it, so pushes cannot chain.
    // The goal is stored rather than recomputed because recomputing it every frame
    // is precisely what a commit is meant to prevent -- see csq_combat.
    csq_push_timer  = 0;
    csq_push_cd     = 0;
    csq_push_goal_x = x;
    csq_push_goal_y = y;

    // Where the companion stood on the previous frame of a push, and the minimum
    // gap between forced route rebuilds. Together they answer "is anything actually
    // walking this path" without asking GameMaker directly -- see
    // csq_combat_stalled for why that question is not asked.
    csq_push_last_x    = x;
    csq_push_last_y    = y;
    csq_push_repath_cd = 0;

    // Spread runs on its own cooldown rather than sharing csq_push_cd: standing on
    // top of a squadmate is worth fixing during the pause between advances instead
    // of waiting for it to end -- see csq_combat_spread.
    csq_spread_cd = 0;

    // Anti-root watch: where this companion has been standing, and for how long.
    // Read by csq_combat_reposition, which is the one piece of footwork allowed to
    // run when the companion is already close enough to the target.
    csq_root_x      = x;
    csq_root_y      = y;
    csq_root_frames = 0;

    // ---- toughness ---------------------------------------------------------
    // npc_setup has just set hp from the preset -- 60 for loner_regular, the same
    // as the enemies you kill three at a time. A companion that fights alongside
    // you takes far more incoming fire than a patrolling mook ever does, so scale
    // it up before anything reads the value.
    //
    // Applied here rather than in the Create event because csq_hp_max below has to
    // be computed from the final figure, and because csq_squad_spawn_entry restores
    // carried damage with min(carried, inst.hp) immediately after Create -- so the
    // boost has to be in place by the time that clamp runs, or a returning
    // companion would be capped at the unboosted maximum.
    //
    // A paid tier recruit carries its own multiplier in csq_hp_mult (set from
    // global.csq_pending_hp_mult in the Create event). A positive value there wins
    // over the global hp_multiplier, so a Veteran ends up tougher than a Rookie even
    // when they share a preset; -1 (a debug-spawn recruit or a legacy roster) uses
    // the configured default instead.
    var _mult = max(0.1, csq_cfg("hp_multiplier"));
    if (variable_instance_exists(id, "csq_hp_mult") && is_real(csq_hp_mult) && csq_hp_mult > 0)
    {
        _mult = csq_hp_mult;
    }
    hp = max(1, hp * _mult);

    // Maximum health, for the HUD bar and nothing else. NPCs have no hp_max of
    // their own -- that is a player field -- so the mod has to remember it.
    //
    // WHY THIS IS NOT JUST npc_get_hp(npc_id)
    // obj_npc_human_parent_Alarm_9 fires one frame after Create and does
    //     if (hp_set == false) { hp *= difficulty_get("enemy_human_hp"); ... }
    // so on any difficulty that scales human health the preset value is not what
    // the companion ends up with. Mirroring that multiply here gets the figure
    // right from the first frame; csq_ai_step then keeps a high-water mark, which
    // self-corrects if the game ever raises health by some route not modelled here.
    csq_hp_max = hp;

    try   { csq_hp_max = hp * difficulty_get("enemy_human_hp"); }
    catch (_ignored) {}

    csq_hp_max = max(1, csq_hp_max);

    // Enable the vanilla aggro leash. obj_prologue_npc sets these same two
    // variables; scr_find_target_for_human tests for their presence.
    leash_to_spawn = true;
    leash_radius   = csq_cfg("engage_radius");

    // Park in the inert host state. npc_setup will have set state from the
    // preset's state_patrol ("human_general" for loner_regular), which would
    // otherwise make the companion wander off on its own.
    state = csq_ai_state_idle();
}


/// @func   csq_ai_set_mode(_mode)
/// @desc   Switch mode and apply the matching vanilla state. Logs only on an
///         actual change, so DEBUG output stays readable.
function csq_ai_set_mode(_mode)
{
    if (csq_mode == _mode) return false;

    var _from = csq_mode;
    csq_mode  = _mode;

    if (_mode == csq_ai_mode_engage())
    {
        state = csq_ai_state_combat();
    }
    else
    {
        state = csq_ai_state_idle();

        // Drop any path the vanilla AI started, so a leftover route does not
        // keep dragging the companion along after combat ends.
        try { path_end(); } catch (_err) {}
    }

    csq_log_debug("ai: slot " + string(csq_slot) + " " + _from + " -> " + _mode +
                  " (state=" + string(state) + ")");

    return true;
}


/// @func   csq_ai_target_is_protected(_target)
/// @desc   Whether _target is a permanent friendly/service NPC that companions
///         must never attack, even when another mod changes its faction.
///
///         Faction is normally enough: vanilla labels these people "All Friend"
///         or "Player". It is not a safety boundary, though. Data overhauls can
///         reclassify a trader as a Bandit while retaining the same trader role;
///         EFZ does exactly that to Mr. Junk. A companion mirrors the player's
///         relation to Bandits, so faction-only targeting would then kill a
///         quest-critical NPC.
///
///         The positive trader_id test is deliberately broad, covering both
///         vanilla and added traders. The short npc/object list is only for
///         service and story NPCs that have no trader_id. It deliberately does
///         NOT match generic `quest_*` ids: several of those are intended kill
///         targets, and protecting them would break their quests.
/// @return {Bool}
function csq_ai_target_is_protected(_target)
{
    try
    {
        if (_target == noone || _target == -4) return false;
        if (!instance_exists(_target))         return false;

        // Preserve vanilla's broad, inexpensive guarantee first.
        if (variable_instance_exists(_target, "faction"))
        {
            if (_target.faction == "Player" || _target.faction == "All Friend")
            {
                return true;
            }
        }

        // A real trader must never become a squad target. "no_trader" is the
        // sentinel vanilla writes into ordinary NPC records.
        if (variable_instance_exists(_target, "trader_id"))
        {
            var _trader = string(_target.trader_id);
            if (_trader != "" && _trader != "no_trader" && _trader != "undefined")
            {
                return true;
            }
        }

        // Vanilla's two traders that have save-impacting death branches. Test
        // object identity as well as npc_id so an external data override cannot
        // remove this protection by changing a record field.
        if (_target.object_index == obj_junk_trader)   return true;
        if (_target.object_index == obj_forest_trader) return true;

        if (!variable_instance_exists(_target, "npc_id")) return false;

        // Named service and story NPCs with no trader_id. These are permanent
        // friendly roles, unlike the intentionally hostile quest_kill_target_*.
        switch (string(_target.npc_id))
        {
            case "capotreno":
            case "daily_quest_giver":
            case "engineer":
            case "forest_trader":
            case "guide_npc":
            case "junk_trader":
            case "quest_dealer":
            case "green_army_prologue":
            case "green_army_prologue_2":
            case "green_army_quest_swamp":
            case "green_army_quest_swamp_leader":
            case "tutorial_npc":
                return true;
        }
    }
    catch (_err)
    {
        // Fail closed. A bad data field must make the squad leave that NPC
        // alone, never turn an unknown quest giver into a valid target.
        return true;
    }

    return false;
}


/// @func   csq_ai_hostile_target_exists()
/// @desc   Whether `target` is a live instance this companion should shoot.
///         Protected quest/service NPCs are rejected before the faction test.
///         Hostility is otherwise derived from reputation rather than the
///         relation enum, so it does not depend on decompiled enum numbering.
function csq_ai_hostile_target_exists()
{
    try
    {
        if (target == -4)            return false;
        if (!instance_exists(target)) return false;
        if (csq_ai_target_is_protected(target)) return false;

        if (!variable_instance_exists(target, "faction")) return false;

        return csq_faction_is_hostile(faction, target.faction);
    }
    catch (_err)
    {
        return false;
    }
}


/// @func   csq_ai_scan_for_targets()
/// @desc   In follow/hold mode the vanilla machine never scans, because
///         "human_no_move" does not call scr_find_target_for_human. So this
///         module calls it on a timer -- it walks a collision list and does
///         line-of-sight checks, so it is not something to run every frame.
function csq_ai_scan_for_targets()
{
    var _interval = max(1, csq_cfg("scan_interval"));

    csq_scan_timer++;
    if (csq_scan_timer < _interval) return;

    csq_scan_timer = 0;

    try
    {
        // The leash (set in csq_ai_update_leash) makes this only ever return
        // enemies near the player. Its faction result still has to pass the
        // service/quest safety gate: data mods are allowed to alter faction
        // values, but must not turn a vendor into a squad target.
        target = scr_find_target_for_human();
        if (csq_ai_target_is_protected(target)) target = -4;
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_scan_for_targets", _err);
        target = -4;
    }
}


/// @func   csq_ai_update_leash(_player)
/// @desc   Repoint the vanilla leash. Re-read from config every frame so edits
///         take effect without a restart once reloaded.
///
///         WHY THE ANCHOR MOVES TOWARD THE ENEMY IN A FIGHT
///         original_x/original_y is not only the leash centre. obj_npc_parent_Step_0
///         line 732, inside the human_general utility selector, reads:
///             if (point_distance(x, y, original_x, original_y) > 20)
///                 ds_priority_add(_list_action, Value_9, global.sub_ai_peso[p]);
///         and Value_9 is scr_enemy_choose_move_pos(original_x, original_y, 0) --
///         "go back to the anchor". With the anchor pinned to the player, a
///         companion more than 20px out was handed a "walk back to the player"
///         candidate, which is what made them hover at the player's feet instead of
///         holding ground where they were useful.
///
///         Biasing the anchor at the target turns that same vanilla action into an
///         advance, with no combat code and without touching global.sub_ai_peso --
///         those weights are shared by every NPC in the game.
///
///         BUT IT DOES NOTHING WHILE THE COMPANION IS ACTUALLY SHOOTING
///         Corrected after reading the selector properly. That ds_priority_add is
///         nested inside
///             if (_no_target_or_ally == true)      // line 702
///         which opens 30 lines above it, so action 9 is only ever offered when the
///         NPC has no hostile target at all. It never competes with shooting (11),
///         cover (26) or advancing (29) -- the earlier version of this comment said
///         it did, and that was wrong.
///
///         Worse, it cannot fire even between bursts: the bias below is applied only
///         while csq_ai_hostile_target_exists(), and the moment that stops being
///         true the anchor snaps back to the player, which is also the moment
///         action 9 becomes available. The two conditions are mutually exclusive by
///         construction.
///
///         So engage_advance has exactly one live effect, and it is the one
///         documented at the leash_radius line below: it moves the point that
///         scr_find_target_for_human measures target distance from, extending
///         acquisition reach toward the enemy. It does not move anyone's feet.
///         Closing distance in a firefight is csq_combat's job -- see
///         csq_combat_push, and the note there about action 29 being gated on
///         range_type != 0.
///
///         The offset is clamped to engage_advance, so a companion still cannot
///         wander off after something: worst case they end up engage_advance px
///         from the player, on the enemy's side.
function csq_ai_update_leash(_player)
{
    var _ax = _player.x;
    var _ay = _player.y;

    if (csq_mode == csq_ai_mode_engage())
    {
        var _adv = csq_cfg("engage_advance");

        if (_adv > 0 && csq_ai_hostile_target_exists())
        {
            var _dir = point_direction(_player.x, _player.y, target.x, target.y);
            var _gap = point_distance(_player.x, _player.y, target.x, target.y);
            var _d   = min(_adv, _gap);

            _ax = _player.x + lengthdir_x(_d, _dir);
            _ay = _player.y + lengthdir_y(_d, _dir);
        }
    }

    original_x     = _ax;
    original_y     = _ay;
    leash_to_spawn = true;

    // Measured from the anchor above (scr_find_target_for_human line 165 discards
    // any target further than this from original_x/original_y), so an advanced
    // anchor extends reach toward the enemy without widening it behind the player.
    leash_radius   = csq_cfg("engage_radius");
}


/// @func   csq_ai_update_facing(_player)
/// @desc   Track the player's heading so the formation sits behind them.
///         xprevious/yprevious are built-in on every instance, which avoids
///         depending on any particular player-facing variable. A stationary
///         player keeps the last known heading.
function csq_ai_update_facing(_player)
{
    if (_player.x != _player.xprevious || _player.y != _player.yprevious)
    {
        csq_face = point_direction(_player.xprevious, _player.yprevious, _player.x, _player.y);
    }

    return csq_face;
}


/// @func   csq_ai_follow_speed(_error, _player)
/// @desc   Path speed for the current gap to the formation slot.
///
///         scr_enemy_path derives its own speed from `state`, and
///         "human_no_move" falls through to spd_not_alerted (0.25 px/step for a
///         loner) -- far too slow to keep up with a moving player. Verified that
///         *nothing* in vanilla ever writes path_speed, so overriding it here
///         conflicts with nothing.
///
///         WHY THIS TRACKS THE PLAYER'S LIVE SPEED INSTEAD OF FIXED MULTIPLIERS
///         The first version cruised on spd_not_alerted * 1.0 and caught up on
///         spd_alerted * 1.6. For a loner_regular that is 0.25 and 1.20 px/step
///         against a player who walks at 0.75 and runs at 1.20 (scr_player_movement
///         lines 108-109). So cruising lost ground even to a walking player, and
///         catch-up exactly TIED a running one -- arithmetically able to hold a gap
///         but never to close it, and losing outright as soon as the player had any
///         speed bonus at all. Hence: read what the player is actually doing and
///         beat it by a margin.
function csq_ai_follow_speed(_error, _player)
{
    try
    {
        // The preset's ALERTED speed is the floor. spd_not_alerted is the
        // idle-shuffle speed and has no business in a follow loop.
        var _base = npc_get_spd_alerted(npc_id);

        // What the player is actually doing this frame, in px/step. Read off the
        // live instance rather than assuming 0.75/1.2, because backpack
        // movement_speed, global.sk_k[5], the hub's 1.5x run bonus and the hunter
        // skills (jogger, marathonrunner, nudist, adrenalinerush, rolling_start,
        // emergency_sprint) all scale it. Chasing a hardcoded number would fall
        // behind again the moment the player put a better pack on.
        var _player_spd = 0;
        try   { _player_spd = point_distance(0, 0, _player.hspd, _player.vspd); }
        catch (_ignored) { _player_spd = 0; }

        // Cruising in formation: keep pace, plus a margin so the slot is actually
        // reached rather than merely held at a constant distance.
        var _speed = max(_base * csq_cfg("speed_walk_mult"),
                         _player_spd * csq_cfg("speed_match_mult"));

        // Lagging: open up. Both terms matter -- the preset term covers a
        // stationary player the companion still has to walk in to, the player term
        // covers a sprinting one.
        if (_error > csq_cfg("catchup_distance"))
        {
            _speed = max(_speed,
                         _base * csq_cfg("speed_run_mult"),
                         _player_spd * csq_cfg("speed_catchup_mult"));
        }

        // Capped so a teleport or a one-frame position spike cannot fling anyone
        // across the map at path speed.
        return clamp(_speed, 0.1, csq_cfg("speed_max"));
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_follow_speed", _err);
        return 1;
    }
}


/// @func   csq_ai_try_teleport(_player, _distance)
/// @desc   Last-resort recovery for a companion that is both far away and
///         genuinely unable to path -- across a chasm, or sealed in geometry.
///         Deliberately conservative: distance alone is never enough, because
///         a long walk is not a failure. `path_is_valid` is set by
///         scr_enemy_path from mp_grid_path.
/// @return {Bool} whether a teleport happened
function csq_ai_try_teleport(_player, _distance)
{
    var _threshold = csq_cfg("teleport_distance");
    if (_threshold <= 0) return false;                  // feature disabled

    // Track sustained pathing failure.
    var _valid = true;
    if (variable_instance_exists(id, "path_is_valid")) _valid = path_is_valid;

    if (_valid) csq_path_fail = 0;
    else        csq_path_fail++;

    if (_distance < _threshold)                             return false;
    if (csq_path_fail < csq_cfg("teleport_fail_frames"))    return false;

    var _pos = csq_find_free_pos(_player.x, _player.y, max(16, csq_cfg("spawn_offset") * 3), 60);
    if (!_pos.ok)
    {
        csq_log_warn("ai: slot " + string(csq_slot) + " stuck at " + string(floor(_distance)) +
                     "px but found no free cell near the player");
        return false;
    }

    csq_log_warn("ai: slot " + string(csq_slot) + " teleported to the player " +
                 "(stuck " + string(csq_path_fail) + " frames at " +
                 string(floor(_distance)) + "px)");

    try { path_end(); } catch (_err) {}

    x = _pos.x;
    y = _pos.y;

    csq_path_fail = 0;
    return true;
}


/// @func   csq_ai_roam_point(_player, _slot_x, _slot_y)
/// @desc   The point a following companion should actually walk to: its formation
///         slot, plus a wander offset that is re-rolled on a timer.
///
///         WHY THE OFFSET LIVES HERE AND NOT IN csq_formation_point
///         csq_formation_point is pure geometry -- same inputs, same answer -- and
///         is also called by the spawn placement code, which wants the exact slot
///         and nothing else. Roaming is per-companion state that changes over
///         time, so it belongs on the instance driving the movement.
///
///         WHY ROAMING STOPS WHEN THE PLAYER MOVES
///         This is the whole safety argument for the feature. The follow loop was
///         just retuned to fix companions trailing behind, and that fix works by
///         beating the player's live speed by a margin while heading to a slot
///         that is itself running away. Adding a random 40px offset on top of a
///         receding target hands that bug straight back: the companion would spend
///         its speed margin on sideways drift instead of on closing the gap.
///
///         So above roam_max_player_speed (0.3 px/step, against a player walk of
///         about 0.75) the offset is forced to zero and the behaviour is identical
///         to the tuned follow. The timer is zeroed too, so a companion starts
///         drifting immediately when the player stops rather than waiting out the
///         remainder of an interval.
///
///         WHY THE OFFSET IS ONLY VALIDATED AT RE-ROLL TIME
///         The slot rotates as the player turns, so a destination that was clear
///         can become blocked without a re-roll. That is safe to ignore, because
///         scr_enemy_path snaps an unreachable goal to the nearest walkable cell
///         -- the same reason the plain formation slot needs no validation. The
///         check at re-roll time is there to avoid *choosing* a silly destination
///         inside a rock, not to guarantee one stays valid.
/// @return {Struct} {x, y} in room coordinates
function csq_ai_roam_point(_player, _slot_x, _slot_y)
{
    var _radius = csq_cfg("roam_radius");

    if (!csq_cfg("roam_enabled") || _radius <= 0)
    {
        csq_roam_x = 0;
        csq_roam_y = 0;
        return { x: _slot_x, y: _slot_y };
    }

    // Read the player's live speed the same way csq_ai_follow_speed does, rather
    // than assuming the 0.75/1.2 base values -- backpacks and skills scale both.
    var _player_spd = 0;
    try   { _player_spd = point_distance(0, 0, _player.hspd, _player.vspd); }
    catch (_ignored) { _player_spd = 0; }

    if (_player_spd > csq_cfg("roam_max_player_speed"))
    {
        csq_roam_x     = 0;
        csq_roam_y     = 0;
        csq_roam_timer = 0;
        return { x: _slot_x, y: _slot_y };
    }

    csq_roam_timer--;

    if (csq_roam_timer <= 0)
    {
        csq_roam_timer = max(1, csq_cfg("roam_interval"));

        // Vanilla's own wander idiom, lifted from scr_enemy_choose_move_pos:
        //     var range = irandom_range(arg2 div 2, arg2);
        //     var _dir  = irandom(360);
        // Using the same distribution means companions drift like the game's own
        // idling NPCs rather than in a way that reads as scripted.
        var _range = irandom_range(_radius div 2, _radius);
        var _dir   = irandom(360);

        var _ox = lengthdir_x(_range, _dir);
        var _oy = lengthdir_y(_range, _dir);

        if (csq_pos_walkable(_slot_x + _ox, _slot_y + _oy))
        {
            csq_roam_x = _ox;
            csq_roam_y = _oy;
        }
        else
        {
            // Blocked: fall back to the plain slot until the next roll.
            csq_roam_x = 0;
            csq_roam_y = 0;
        }
    }

    return { x: _slot_x + csq_roam_x, y: _slot_y + csq_roam_y };
}


/// @func   csq_ai_aim_offset(_player)
/// @desc   How far, and in which direction, to slide this companion's formation
///         slot toward where the player is aiming.
///
///         WHY THIS EXISTS
///         csq_formation_point puts every slot at follow_distance BEHIND the
///         player's movement heading. That is deliberate -- it keeps companions out
///         of your line of fire -- but the side effect is that they only ever hang
///         off your shoulders, and they hang off the shoulders of the direction you
///         last *walked*, which after you stop is whatever it happened to be.
///         Sliding the whole formation toward the cursor makes them cover the
///         direction you are actually watching: at aim_lead == follow_distance they
///         end up roughly level with you on that side, and higher values push them
///         out ahead as a screen.
///
///         WHERE THE AIM POINT COMES FROM
///         player_step_set_aim_point (called first thing in obj_player's Step) does
///             aim_point_x = obj_cursor.aa_x;
///             aim_point_y = obj_cursor.aa_y;
///         in room coordinates, aim assist already applied. The direction is then
///         the same point_direction call the game's own shooting code makes in
///         player_action_shoot line 269 and player_step_weapon_direction line 7, so
///         this tracks the real weapon heading rather than a guess at it.
///
///         WHY THE HEADING IS SMOOTHED
///         A mouse can cross the screen in three frames. Feeding that straight into
///         the pathing goal would move it further than goal_move_threshold every
///         frame, and scr_enemy_path rebuilds the entire route each time it
///         retargets -- the companion would spend its whole life recomputing a path
///         it never walks. So the heading eases toward the cursor at
///         aim_lead_smooth per frame using angle_difference, which takes the short
///         way round and so does not spin the long way through 359 -> 0.
///
///         Fails closed, to a zero offset: no aim lead is the current, known-good
///         behaviour, so an unreadable aim point costs nothing.
/// @return {Struct} {x, y} offset in room coordinates
function csq_ai_aim_offset(_player)
{
    var _lead = csq_cfg("aim_lead");

    if (_lead <= 0) return { x: 0, y: 0 };

    try
    {
        // Ignore a cursor sitting on top of the player: point_direction of a
        // zero-length vector is meaningless, and at that range there is no
        // meaningful side to cover anyway. Keeping the previous smoothed heading
        // means the formation holds still instead of snapping somewhere arbitrary.
        if (point_distance(_player.x, _player.y, _player.aim_point_x, _player.aim_point_y) > 8)
        {
            var _target = point_direction(_player.x, _player.y,
                                          _player.aim_point_x, _player.aim_point_y);

            var _smooth = clamp(csq_cfg("aim_lead_smooth"), 0.01, 1);

            csq_aim_dir += angle_difference(_target, csq_aim_dir) * _smooth;
        }

        // Not validated against the collision grid, for the same reason the plain
        // formation slot is not: scr_enemy_path snaps an unreachable goal to the
        // nearest walkable cell. Only the roam offset is validated, because that
        // one is *chosen* at random and could pick a silly spot inside a rock.
        return {
            x: lengthdir_x(_lead, csq_aim_dir),
            y: lengthdir_y(_lead, csq_aim_dir)
        };
    }
    catch (_err)
    {
        return { x: 0, y: 0 };
    }
}


/// @func   csq_ai_drive_follow(_player)
/// @desc   Move the companion toward its formation slot using the same A*
///         routine every vanilla NPC uses.
///
///         Takes no distance argument on purpose. The only distance that matters
///         here is the one to the slot, which is computed below; passing in the
///         distance to the player is what produced the bug described inline.
///         (csq_ai_try_teleport still takes distance-to-player, because "am I
///         stranded far from the player" genuinely is measured from the player.)
function csq_ai_drive_follow(_player)
{
    var _facing = csq_ai_update_facing(_player);
    var _total  = max(1, csq_squad_count());
    var _slot   = csq_formation_point(csq_slot, _total, _player.x, _player.y, _facing);

    // Personal formation radius. csq_follow_bias is this companion's own +/- pixel
    // offset (csq_human), pushed along the line from the player to its slot so the
    // arc geometry is untouched and only this one companion's distance changes.
    //
    // Without it every companion sits on the same circle, which is what makes four
    // of them read as one object with four sprites: they arrive together, stop
    // together, and turn together. A handful of pixels is enough to break that up
    // without loosening the formation in any way a player would call sloppy.
    //
    // Zero when de-sync is off, so this whole block collapses to the old behaviour.
    if (variable_instance_exists(id, "csq_follow_bias") && csq_follow_bias != 0)
    {
        var _bias_dir = point_direction(_player.x, _player.y, _slot.x, _slot.y);
        _slot.x += lengthdir_x(csq_follow_bias, _bias_dir);
        _slot.y += lengthdir_y(csq_follow_bias, _bias_dir);
    }

    // Slide the whole formation toward the cursor. Applied to the slot rather than
    // to the anchor handed to csq_formation_point, so the fan-out geometry -- the
    // arc, the spread, the one-behind/three-in-a-V shape -- is untouched and only
    // its centre moves. aim_lead = 0 leaves the slot exactly where it was.
    var _aim = csq_ai_aim_offset(_player);
    _slot.x += _aim.x;
    _slot.y += _aim.y;

    // The roam offset is applied HERE, before anything below reads the goal.
    // Every threshold in this function -- arrive_distance, goal_move_threshold,
    // and the catchup_distance inside csq_ai_follow_speed -- has to measure
    // against the point actually being walked to. Measuring against the bare slot
    // while pathing somewhere else is precisely the class of bug that made
    // companions repath every frame to a cell they were already standing on.
    var _point = csq_ai_roam_point(_player, _slot.x, _slot.y);

    // Error is measured against the GOAL, not against the player.
    //
    // The original code compared arrive_distance (18) to the distance to the
    // player, while the pathing goal was follow_distance (40) behind them. A
    // companion standing perfectly in formation was therefore 40px from the player
    // and "not arrived", so it never stopped: it repathed to a cell it was already
    // standing on, every frame, forever. Same reason the speed selector kept
    // reading 40+ as a lag that needed correcting.
    var _error = point_distance(x, y, _point.x, _point.y);

    // Close enough: stop cleanly rather than jittering around the slot.
    if (_error <= csq_cfg("arrive_distance"))
    {
        try { path_end(); } catch (_err) {}
        return;
    }

    // Only retarget once the slot has meaningfully moved. scr_enemy_path
    // rebuilds the whole route when it fires, so thrashing the goal every frame
    // would waste work and make movement stutter.
    if (point_distance(move_point_x, move_point_y, _point.x, _point.y) >
        csq_cfg("goal_move_threshold"))
    {
        move_point_x = _point.x;
        move_point_y = _point.y;
    }

    try
    {
        // Vanilla A*: repaths on its own timer, snaps an unreachable goal to the
        // nearest walkable cell, then mp_grid_path over global.grid_move.
        scr_enemy_path();

        // Own the speed (see csq_ai_follow_speed).
        path_speed = csq_ai_follow_speed(_error, _player);
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_drive_follow", _err);
    }
}


/// @func   csq_ai_player_hp_ratio(_player)
/// @desc   The player's health as a fraction of their CURRENT maximum.
///
///         hp_max is the right denominator, not hp_max_total. Vanilla recomputes
///         it every frame in player_step_personal_stats lines 44-45 as
///             hp_max = hp_max_total - wound
///         and uses it as the clamp on natural regeneration, so it is the game's
///         own definition of "full". A player with 40 points of wound is at full
///         health when hp == hp_max, and no field dressing is going to change
///         that -- wound is what medication treats.
///
///         Returns 1 (full, never heal) if the maximum cannot be read at all.
///         That is the safe direction: a companion that fails to heal is a
///         disappointment, one that heals forever off a divide-by-zero is a bug.
/// @return {Real} 0..1
function csq_ai_player_hp_ratio(_player)
{
    try
    {
        var _max = _player.hp_max;

        // Fall back only if hp_max is missing or nonsensical, never silently.
        if (!is_real(_max) || _max <= 0) _max = _player.hp_max_total;
        if (!is_real(_max) || _max <= 0) return 1;

        return clamp(_player.hp / _max, 0, 1);
    }
    catch (_err)
    {
        return 1;
    }
}


/// @func   csq_ai_heal_charges_left()
/// @desc   Medic charges remaining for this companion, read off its roster entry.
///         Returns 0 for an instance that is not on the roster, which cannot
///         normally happen but must not throw if it does.
function csq_ai_heal_charges_left()
{
    var _index = csq_squad_find_by_inst(id);
    if (_index < 0) return 0;

    return csq_squad_heal_charges(global.csq_squad[_index]);
}


/// @func   csq_ai_medic_claim_holder()
/// @desc   The companion currently claiming the medic job, or noone.
///
///         Self-healing on purpose. A claim is dropped automatically when its
///         holder stops existing, which covers a companion dying mid-approach AND
///         one that walked out of obj_controller_Alarm_4's 960x540 activation box
///         and got deactivated -- GameMaker reports deactivated instances as
///         non-existent, and they run no events, so a culled medic could never
///         release its own claim. Without this the squad would refuse to heal for
///         the rest of the raid.
function csq_ai_medic_claim_holder()
{
    if (!variable_global_exists("csq_medic_id")) return noone;

    var _holder = global.csq_medic_id;

    if (_holder == noone || _holder == -4) return noone;

    if (!instance_exists(_holder))
    {
        global.csq_medic_id = noone;
        return noone;
    }

    return _holder;
}


/// @func   csq_ai_medic_try_claim()
/// @desc   Take the medic job, or confirm this companion already holds it.
///
///         WHY THE JOB IS EXCLUSIVE
///         Without a claim, every companion in the squad sees the same wound and
///         every one of them breaks formation for it -- three companions abandoning
///         a firefight to converge on one player, and three charges spent on a
///         single heal. One goes, the rest keep fighting.
/// @return {Bool} whether this companion holds the claim
function csq_ai_medic_try_claim()
{
    var _holder = csq_ai_medic_claim_holder();

    if (_holder == id)    return true;
    if (_holder != noone) return false;

    global.csq_medic_id = id;
    return true;
}


/// @func   csq_ai_medic_release()
/// @desc   Give up the medic job, but only if this companion is the one holding
///         it -- otherwise a companion leaving follow mode would cancel someone
///         else's run.
function csq_ai_medic_release()
{
    if (!variable_global_exists("csq_medic_id")) return false;
    if (global.csq_medic_id != id)               return false;

    global.csq_medic_id = noone;
    return true;
}


/// @func   csq_ai_wants_medic(_player)
/// @desc   Whether this companion should be heading over to patch the player up.
///         Does not consider the claim -- csq_ai_step pairs this with
///         csq_ai_medic_try_claim so that only one companion acts on a yes.
///
///         WHY THE THRESHOLD IS STRICTER MID-FIGHT
///         The user's decision was "only when critically low": a scratch is not
///         worth walking out of cover for while there are enemies up, but bleeding
///         out is. So while engaged the bar is heal_emergency_threshold (35%), and
///         otherwise it is heal_threshold (85%).
///
///         WHY THAT DOES NOT OSCILLATE
///         Once the companion switches to medic, csq_mode is no longer engage, so
///         the next frame evaluates against the *lenient* threshold and it stays
///         committed. A companion that broke off at 34% therefore finishes the job
///         instead of flipping back to engage the instant regeneration nudges the
///         player to 36% -- which would leave it stuck alternating between the two
///         modes, walking nowhere.
function csq_ai_wants_medic(_player)
{
    if (!csq_cfg("heal_enabled")) return false;

    // A dead player, or one still riding the raid intro, is not a patient.
    // csq_player_in_world also covers scr_player_state_start, where x/y are pinned
    // to obj_train and walking to them is meaningless.
    if (!csq_player_in_world(_player)) return false;

    if (csq_heal_cd > 0)                return false;
    if (csq_ai_heal_charges_left() <= 0) return false;

    var _ratio = csq_ai_player_hp_ratio(_player);

    if (_ratio >= csq_cfg("heal_threshold")) return false;

    if (csq_mode == csq_ai_mode_engage() &&
        _ratio >= csq_cfg("heal_emergency_threshold"))
    {
        return false;
    }

    return true;
}


/// @func   csq_ai_do_heal(_player)
/// @desc   Apply one heal. Charge is spent first, so a failure to spend one can
///         never result in a free heal.
///
///         The arithmetic mirrors vanilla exactly. npc_dialogue_heal_hp does
///             _player.hp = _player.hp_max;
///             _player.bleed = 0;
///         and player_step_personal_stats clamps natural regen to hp_max, so
///         clamping to hp_max here means a companion's medkit obeys the same
///         ceiling as everything else in the game. wound is deliberately not
///         touched -- see csq_ai_player_hp_ratio.
/// @return {Bool} whether a heal happened
function csq_ai_do_heal(_player)
{
    try
    {
        if (!csq_squad_consume_heal_charge(id))
        {
            // Out of charges. Sit on a short cooldown rather than retesting every
            // frame, and hand the job back so nothing is left holding the claim.
            csq_heal_cd = 60;
            csq_ai_medic_release();
            return false;
        }

        var _before = _player.hp;

        _player.hp = clamp(_player.hp + csq_cfg("heal_amount"), 0, _player.hp_max);

        if (csq_cfg("heal_stop_bleed")) _player.bleed = 0;

        csq_heal_cd = max(1, csq_cfg("heal_cooldown_frames"));

        var _name    = csq_ai_display_name();
        var _healed  = _player.hp - _before;
        var _left    = csq_ai_heal_charges_left();

        if (csq_cfg("heal_message"))
        {
            try
            {
                // The `false` is required. scr_draw_text_with_box's default
                // arg1 = true runs language_get_string(arg0), which for a literal
                // that is not a localisation key returns nothing and draws an
                // empty box.
                scr_draw_text_with_box(_name + " patched you up", false);
            }
            catch (_ignored) {}

            try
            {
                // snd_medikit_1 is NOT a confirmed asset -- it appears only as a
                // string default parameter in scr_mods_users line 183, so it may
                // not exist in a stock build. Resolved by name and checked, with
                // the sound npc_dialogue_heal_hp itself uses as the fallback.
                var _snd = asset_get_index("snd_medikit_1");

                if (_snd < 0 || !audio_exists(_snd)) _snd = snd_ui_click_text_npc;

                audio_play_sound(_snd, 9, false);
            }
            catch (_ignored) {}
        }

        csq_log_info("medic: " + _name + " healed the player for " +
                     string(floor(_healed)) + " (" + string(_left) + " charge(s) left)");

        // Job done -- let the next wound be claimed by whoever is closest.
        csq_ai_medic_release();

        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_do_heal", _err);

        // Do not leave the squad deadlocked on a claim nobody is acting on.
        csq_heal_cd = 60;
        csq_ai_medic_release();
        return false;
    }
}


/// @func   csq_ai_display_name()
/// @desc   The companion's name for player-facing text. Prefers the roster name,
///         and falls back to the instance's own npc_name.
///
///         The two now agree: the companion's Create event assigns npc_name from
///         global.csq_pending_name after npc_setup, overwriting the independent
///         random draw npc_setup makes at its line 8. The roster is still read
///         first, because it is the record that survives the instance -- the
///         fallback only matters for an instance created by something other than
///         csq_squad_spawn_entry.
function csq_ai_display_name()
{
    try
    {
        var _index = csq_squad_find_by_inst(id);

        if (_index >= 0)
        {
            var _name = global.csq_squad[_index].name;
            if (is_string(_name) && _name != "") return _name;
        }

        if (variable_instance_exists(id, "npc_name")) return string(npc_name);
    }
    catch (_err) {}

    return "Your companion";
}


/// @func   csq_ai_drive_medic(_player)
/// @desc   Walk to the player and heal once in range.
///
///         Straight at the player, not at a formation slot: the goal is contact,
///         and the slot sits follow_distance behind them by design, which is
///         further than heal_range. Speed is borrowed from csq_ai_follow_speed
///         because closing a gap to the player is exactly what that function is
///         tuned for -- past catchup_distance it picks the run speed, so an
///         emergency heal is delivered at a run rather than a stroll.
function csq_ai_drive_medic(_player)
{
    var _distance = point_distance(x, y, _player.x, _player.y);

    if (_distance <= csq_cfg("heal_range"))
    {
        try { path_end(); } catch (_err) {}

        csq_ai_do_heal(_player);
        return;
    }

    // Keep facing tracked while converging, so the formation does not snap to a
    // stale heading the moment the companion returns to follow mode.
    csq_ai_update_facing(_player);

    move_point_x = _player.x;
    move_point_y = _player.y;

    try
    {
        scr_enemy_path();
        path_speed = csq_ai_follow_speed(_distance, _player);
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_drive_medic", _err);
    }
}


/// @func   csq_ai_torch_ensure()
/// @desc   Verify this companion still owns a flashlight, and re-light it if not.
///         Called from the companion's Step event with `self` bound to the
///         companion instance.
///
///         WHY A COMPANION'S FLASHLIGHT GOES OUT
///         obj_npc_human_parent_Create_0 hands every human NPC its light exactly
///         once, and nothing in the game ever gives one back:
///             if (!is_in_hub())
///             {
///                 var ll = instance_create_depth(x, y, 0, obj_light_enemy_torch);
///                 ll.id_linked = id;
///             }
///         That instance_create_depth is the only reference to obj_light_enemy_torch
///         in the entire decompiled codebase.
///
///         Walking through a doorway teleports the *player* clear across the room
///         (player_action_interact: x = indoor_id.tele_x, y = indoor_id.tele_y),
///         which leaves the companion standing at the old position, outside the
///         960x540 box obj_controller_Alarm_4 keeps activated. Within 20 frames the
///         companion is deactivated, and its light dies one of two ways:
///           - the torch is still active, evaluates instance_exists(id_linked) as
///             false -- a deactivated instance reports as non-existent -- and runs
///             the instance_destroy() in its own Step; or
///           - the torch is culled in the same sweep and is stranded at the
///             doorway, where instance_activate_region will not reach it again.
///         csq_squad_recover_deactivated reactivates the companion and drops it
///         next to the player either way, so the companion comes back but the light
///         does not. Hence "the flashlight goes out going in or out of a building
///         and never comes back on".
///
///         Vanilla hits the identical problem with the NPC's *weapon* and fixes it
///         with a periodic presence check: obj_npc_human_parent_Step_0 counts to
///         check_weapon_timer_max and re-fires alarm[9] whenever no obj_npc_weapon
///         claims it. This is that pattern, applied to the light.
/// @return {Bool} whether a replacement light was created
function csq_ai_torch_ensure()
{
    // Vanilla creates no torch inside the hub, so neither does this. is_in_hub is
    // also what gates the original line.
    if (csq_in_hub()) return false;

    // Defensive: an instance that somehow skipped csq_ai_init_instance still gets a
    // working timer rather than a "variable not set" crash on the increment.
    if (!variable_instance_exists(id, "csq_torch_timer")) csq_torch_timer = 0;

    // Half a second. Vanilla's equivalent weapon check uses 120 frames, but a
    // missing gun is invisible until the NPC shoots whereas a missing light is
    // obvious the moment you look at the companion, so this one is four times
    // keener. The work below is a single pass over the handful of active lights.
    csq_torch_timer--;
    if (csq_torch_timer > 0) return false;
    csq_torch_timer = 30;

    // Find the light that belongs to this companion. with() only walks *active*
    // instances, which is exactly the test wanted: a stranded deactivated torch is
    // frozen at a doorway and can never follow this companion again, so for the
    // purposes of "does this companion have a light" it does not count.
    //
    // The duplicate branch is the other half of that. If the player later walks
    // back past the doorway, instance_activate_region wakes the stranded torch, it
    // sees its owner exists again and snaps onto the companion -- which by then
    // already has a replacement, so the companion would glow at double brightness
    // for the rest of the raid. Keeping the first and destroying the rest collapses
    // that back to one light within half a second of it happening.
    var _my_id = id;
    var _mine  = noone;

    with (obj_light_enemy_torch)
    {
        if (id_linked == _my_id)
        {
            if (_mine == noone) _mine = id;
            else                instance_destroy();
        }
    }

    if (_mine != noone) return false;

    // Same two lines as obj_npc_human_parent_Create_0. The torch's own Create sets
    // alarm[10] = 1, which flips start_checking on a frame later and caches
    // light_standard, so a light built this way behaves identically to one built at
    // NPC spawn -- there is no extra state to restore.
    try
    {
        var _ll = instance_create_depth(x, y, 0, obj_light_enemy_torch);
        _ll.id_linked = _my_id;
    }
    catch (_err)
    {
        csq_log_exception("csq_ai_torch_ensure", _err);
        return false;
    }

    csq_log_debug("companion: relit flashlight for '" + string(npc_name) + "'");
    return true;
}


/// @func   csq_ai_step()
/// @desc   One frame of companion logic. Called from the companion's Step event
///         with `self` bound to the companion instance.
function csq_ai_step()
{
    var _player = csq_player();

    if (_player == noone)
    {
        // No player to follow -- between rooms, or on a menu. Stay put rather
        // than pathing to a stale coordinate. The medic claim goes back too: its
        // holder cannot act on it here and would block the rest of the squad.
        csq_ai_medic_release();

        try { path_end(); } catch (_err) {}
        return;
    }

    // 0. Age the heal cooldown. Ticks in every mode, engage included, so time
    //    spent fighting counts toward the next heal being available.
    if (csq_heal_cd > 0) csq_heal_cd--;

    //    Keep the remembered maximum honest. csq_ai_init_instance already predicts
    //    what obj_npc_human_parent_Alarm_9's difficulty multiply will produce, so
    //    this is a backstop rather than the main mechanism -- but it costs one
    //    comparison and means the HUD can never show a bar over 100%, whatever
    //    route health arrives by.
    if (hp > csq_hp_max) csq_hp_max = hp;

    // 1. Keep the vanilla leash pinned to the player.
    csq_ai_update_leash(_player);

    // 1a. event_inherited() ran before this function, so vanilla may have
    // re-acquired a target while the companion was in human_general. Remove a
    // protected NPC immediately and leave engage in this same frame. The bullet
    // collision guard in csq_ff covers the one inherited frame before this code
    // gets control, which closes both the AI and damage paths.
    if (csq_ai_target_is_protected(target))
    {
        target = -4;

        if (csq_mode == csq_ai_mode_engage())
        {
            csq_no_target = 0;
            csq_ai_set_mode(global.csq_squad_hold ? csq_ai_mode_hold() : csq_ai_mode_follow());
        }
    }

    // 1b. Self-care, before anything else can give this companion a job.
    //
    //     A wounded companion binds before it does anything else -- that is the whole
    //     point of the behaviour, and it is why this sits above the dispatch rather
    //     than inside it. When it returns true it has taken the frame: no medic, no
    //     engage, no follow, and no combat footwork. Vanilla's own Step has already
    //     run by here (event_inherited), so "hold still" is re-asserted against
    //     whatever that decided, every frame, rather than set once and hoped for.
    //
    //     It adds no mode. csq_mode is left exactly as it was and the matching vanilla
    //     state is restored on every exit path, because csq_ai_set_mode returns early
    //     when the mode has not changed and would not put it back.
    if (csq_care_step()) return;

    // 1c. Idle life, second, because a companion that is bleeding is not smoking.
    //
    //     Like self-care it adds no mode and takes the whole frame when it returns
    //     true -- and unlike self-care it does its own target scan while it holds the
    //     instance, because the dispatch below (which normally scans) never runs. See
    //     the note on csq_idle_step.
    if (csq_idle_step()) return;

    var _distance = point_distance(x, y, _player.x, _player.y);

    // 2. Decide who is in charge this frame.
    //
    //    Priority is medic > engage > hold > follow.
    //
    //    Medic sits on top, but that alone does not mean healing interrupts
    //    combat: csq_ai_wants_medic already refuses to leave a fight for anything
    //    above heal_emergency_threshold. The ranking is what lets a *critical*
    //    wound outrank shooting; the predicate is what stops a scratch doing the
    //    same. Hold is still below engage, because a companion told to hold
    //    position defends itself -- that is the point of holding a position.
    //
    //    The claim is taken in the same condition so a companion that loses the
    //    race falls straight through to normal behaviour on this frame instead of
    //    standing idle for one.
    if (csq_ai_wants_medic(_player) && csq_ai_medic_try_claim())
    {
        csq_ai_set_mode(csq_ai_mode_medic());
        csq_ai_drive_medic(_player);
    }
    else if (csq_mode == csq_ai_mode_engage())
    {
        // Vanilla owns movement and shooting. Only watch for the fight ending.
        if (csq_ai_hostile_target_exists())
        {
            csq_no_target = 0;
        }
        else
        {
            csq_no_target++;

            if (csq_no_target >= csq_cfg("disengage_frames"))
            {
                csq_no_target = 0;
                csq_ai_set_mode(global.csq_squad_hold ? csq_ai_mode_hold() : csq_ai_mode_follow());
            }
        }
    }
    else
    {
        // Reaching here means this companion is not the medic this frame, so any
        // claim it was holding is stale -- the heal has landed, the charges ran
        // out, or the player recovered. Released before anything else so the next
        // wound can be claimed immediately by whoever is closest.
        csq_ai_medic_release();

        // Follow or hold: this module scans, because "human_no_move" does not.
        csq_ai_scan_for_targets();

        if (csq_ai_hostile_target_exists())
        {
            csq_no_target = 0;
            csq_ai_set_mode(csq_ai_mode_engage());
        }
        else if (global.csq_squad_hold)
        {
            // csq_ai_set_mode calls path_end(), so nothing further is needed --
            // the companion simply stops where it stands.
            csq_ai_set_mode(csq_ai_mode_hold());
        }
        else
        {
            csq_ai_set_mode(csq_ai_mode_follow());

            if (!csq_ai_try_teleport(_player, _distance))
            {
                csq_ai_drive_follow(_player);
            }
        }
    }

    // 3. Combat footwork, after the dispatch above rather than inside it.
    //
    //    It has to read human_state_now, and the value that matters is the one
    //    vanilla settled on for THIS frame -- obj_csq_companion's Step calls
    //    event_inherited() before csq_ai_step, so by here the selector has already
    //    run, chosen its action and fired. Reading it from inside the engage branch
    //    would work equally well today, but keeping it out here makes the producer
    //    order explicit: footwork settles, then the callout at step 5 reacts to it.
    //
    //    Vanilla owns the trigger throughout. All this moves is the feet, and only
    //    while vanilla is shooting and standing still to do it.
    csq_combat_step();

    // 4. Belt and braces: while not fighting, stop the companion accumulating
    //    awareness of the player. With correct faction reputation the player
    //    resolves as an ally and would never be shot, but a maxed alert_player
    //    can still make the player win the target slot in
    //    scr_find_target_for_human, crowding out a real enemy.
    if (csq_mode != csq_ai_mode_engage())
    {
        alert_player = 0;
    }

    // 5. Idle chatter, last of everything.
    //
    //    It is the only step in this function that cannot change what a companion
    //    does -- it writes no vanilla variable and touches neither state nor mode --
    //    so it goes where it can see the outcome of every decision above. Note that
    //    the self-care early return at 1a means a companion binding a wound never
    //    reaches this: it has already said its line.
    csq_voice_step();
}
