// =============================================================================
//  Zone Companions  -  csq_idle
// -----------------------------------------------------------------------------
//  Smoking, drinking and eating. The only thing in the mod that exists purely to
//  be looked at.
//
//  WHY THE VANILLA IDLE STATES CANNOT BE USED
//  Vanilla already has human_fuma_sigaretta, human_eat, human_drink and
//  human_play_guitar (obj_npc_parent_Step_0:411-422), each a one-liner calling
//  scr_npc_state_arms. They are exactly this feature, and they are unusable here,
//  because scr_npc_state_arms hands `state` back to vanilla:
//      * it calls scr_find_target_for_human() itself and overwrites target
//      * hostile target  -> state = "human_shoot"
//      * neutral target  -> state = "human_aim_neutral_target"
//      * animation ending-> state = is_in_hub() ? "human_hub_general" : "human_patrol"
//  Companions are raid-only, so that last branch is ALWAYS "human_patrol" -- a state
//  this mod does not drive and where leash_to_spawn does not apply. A companion that
//  finished a cigarette would wander off and never come back. The two gentler exits
//  are both inside is_in_hub() and unreachable. So the vanilla states do not
//  misbehave occasionally; they reliably break the squad.
//
//  WHAT IS USED INSTEAD
//  scr_npc_arms' body (five lines) without its `state = ss`, which is the only line
//  that causes the problem:
//      state           = "human_no_move"   the mod's own idle state
//      human_state_now = 2 | 3 | 4         eat | drink | smoke
//      draw_weapon     = false
//      instance_create_depth -> obj_arms_eat | obj_arms_drink | obj_arms_smoke
//  with linked_id and image_xscale copied across, exactly as vanilla does it.
//
//  BOTH WRITES ARE LOAD-BEARING
//  Each obj_arms_* Step is four lines long and destroys itself unless
//  linked_id.human_state_now equals its own number (obj_arms_smoke_Step_0:9 tests 4,
//  _eat tests 2, _drink tests 3) -- and when it does destroy itself it also does
//  linked_id.draw_weapon = true. So the prop is self-cleaning: every exit in this
//  file only has to put human_state_now back, and the weapon comes back for free.
//  draw_weapon is restored anyway, defensively, in case the prop was already gone.
//
//  WRITING human_state_now IS SAFE ONLY BECAUSE OF THE HOST STATE
//  human_state_now is the human_general utility selector's chosen action. While
//  `state` is "human_no_move" that selector is not running -- the switch never
//  reaches it -- so the field is unread by vanilla and free for the props to use.
//  -1 is vanilla's own initial value (obj_npc_parent_Create_0:254), which is why
//  that is what every exit path here restores.
//
//  THE ANIMATION NEEDS NO TICKING
//  obj_arms_smoke_Create_0 sets image_speed = 0.2 + random(0.3) and GameMaker
//  animates it. Vanilla read image_index only for its own per-frame exit roll, which
//  this module replaces with a timer.
//
//  NOTHING IN HERE SCANS THE HUB
//  Companions never spawn in the hub, so obj_arms_guitar is dropped rather than
//  gated: gating it on is_in_hub() would make it unreachable code, and a companion
//  playing guitar in the zone is comedy. Its weight is redistributed into the other
//  three, and there is no idle_life_guitar_weight key.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_idle_state_off()
/// @desc   The two-state machine. There is no "starting" or "stopping" state: the
///         prop appears on the frame the animation begins and destroys itself on the
///         frame it ends, so there is nothing to hold in between.
function csq_idle_state_off()    { return "off"; }
function csq_idle_state_living() { return "living"; }


/// @func   csq_idle_kind_eat()
/// @desc   The three usable props, by the human_state_now value each one demands.
///         Named rather than inlined because the number and the object have to agree
///         and a mismatch is a prop that destroys itself on its first Step.
function csq_idle_kind_eat()   { return 2; }
function csq_idle_kind_drink() { return 3; }
function csq_idle_kind_smoke() { return 4; }


/// @func   csq_idle_kind_object(_kind)
/// @desc   Which obj_arms_* goes with a kind.
/// @return {Id.Instance|Real} the object index, or noone for an unknown kind
function csq_idle_kind_object(_kind)
{
    if (_kind == csq_idle_kind_eat())   return obj_arms_eat;
    if (_kind == csq_idle_kind_drink()) return obj_arms_drink;
    if (_kind == csq_idle_kind_smoke()) return obj_arms_smoke;
    return noone;
}


/// @func   csq_idle_kind_name(_kind)
/// @desc   For the log only.
/// @return {String}
function csq_idle_kind_name(_kind)
{
    if (_kind == csq_idle_kind_eat())   return "eat";
    if (_kind == csq_idle_kind_drink()) return "drink";
    if (_kind == csq_idle_kind_smoke()) return "smoke";
    return "none";
}


/// @func   csq_idle_init_instance()
/// @desc   Per-companion state, set up from csq_ai_init_instance.
///
///         csq_idle_calm, csq_idle_still and csq_idle_pstill are all frame counters
///         rather than timestamps because each belongs to one instance and is reset
///         by that instance's own step.
function csq_idle_init_instance()
{
    csq_idle_state = csq_idle_state_off();
    csq_idle_kind  = -1;
    csq_idle_timer = 0;

    csq_idle_calm   = 0;
    csq_idle_still  = 0;
    csq_idle_pstill = 0;

    csq_idle_last_x  = x;
    csq_idle_last_y  = y;
    csq_idle_last_px = 0;
    csq_idle_last_py = 0;
}


/// @func   csq_idle_track(_player)
/// @desc   Advance the three counters the entry gate reads. Called every frame the
///         module runs, before anything else, so the gate below is pure reading.
///
///         MOVEMENT IS MEASURED, NOT ASKED FOR
///         There is no "have I arrived" flag to read: csq_ai_drive_follow simply
///         calls path_end() when it is within arrive_distance and returns. So
///         standing still IS the arrival test, and it is a better one -- a companion
///         that has not arrived is by definition still walking. 2 px of tolerance
///         covers the sub-pixel drift a finished path leaves behind.
/// @param  {Id.Instance} _player
function csq_idle_track(_player)
{
    if (csq_ai_hostile_target_exists()) csq_idle_calm = 0;
    else                                csq_idle_calm++;

    if (point_distance(x, y, csq_idle_last_x, csq_idle_last_y) > 2)
    {
        csq_idle_still  = 0;
        csq_idle_last_x = x;
        csq_idle_last_y = y;
    }
    else
    {
        csq_idle_still++;
    }

    if (_player == noone)
    {
        csq_idle_pstill = 0;
        return;
    }

    if (point_distance(_player.x, _player.y, csq_idle_last_px, csq_idle_last_py) > 2)
    {
        csq_idle_pstill  = 0;
        csq_idle_last_px = _player.x;
        csq_idle_last_py = _player.y;
    }
    else
    {
        csq_idle_pstill++;
    }
}


/// @func   csq_idle_concurrent()
/// @desc   How many companions are animating right now, this one included.
/// @return {Real}
function csq_idle_concurrent()
{
    var _n     = 0;
    var _count = csq_squad_count();

    for (var _i = 0; _i < _count; _i++)
    {
        var _entry = csq_squad_entry(_i);
        if (is_undefined(_entry)) continue;

        var _inst = _entry.inst;
        if (!csq_alive(_inst)) continue;

        // Guarded rather than assumed: a companion spawned while idle life was off
        // has never run csq_idle_init_instance.
        if (!variable_instance_exists(_inst, "csq_idle_state")) continue;

        if (_inst.csq_idle_state == csq_idle_state_living()) _n++;
    }

    return _n;
}


/// @func   csq_idle_danger()
/// @desc   Is there a bullet in the air near this companion.
///
///         WHY THIS IS NOT scr_bullet_near()
///         Two reasons. It writes `target`, which this mod does not do outside
///         csq_ai_scan_for_targets. And vanilla is not running it for us anyway:
///         obj_npc_parent_Step_0 calls it inside the human_general case (:676), and a
///         companion animating here is in human_no_move, so that case never runs.
///         This is the same instance_nearest read, read-only, with a wider radius
///         than vanilla's 32 -- being shot at from across a clearing should still put
///         the cigarette out.
/// @return {Bool}
function csq_idle_danger()
{
    var _b = instance_nearest(x, y, obj_bullet_parent);

    if (!instance_exists(_b)) return false;

    return (point_distance(x, y, _b.x, _b.y) < 96);
}


/// @func   csq_idle_stagger_frames()
/// @desc   This companion's own addition to the calm requirement, 0..5 seconds,
///         fixed for the raid. Without it four companions who went quiet on the same
///         frame become eligible on the same frame, and idle_life_max_concurrent
///         decides which one wins by array order -- so it would always be slot 0.
/// @return {Real} frames
function csq_idle_stagger_frames()
{
    return csq_seconds_to_frames(1) * (csq_human_mix(csq_human_seed(), 8) mod 6);
}


/// @func   csq_idle_pick()
/// @desc   Choose a kind, weighted, with a per-companion favourite.
///
///         The favourite is why the seed is involved at all: 40/30/30 is 40/30/30 for
///         everybody, so a squad sharing one weight table mostly smokes. Doubling one
///         weight per companion, chosen once from its seed, means the drinker is
///         always the drinker.
/// @return {Real} a kind, or -1 if every weight is zero
function csq_idle_pick()
{
    var _smoke = max(0, csq_cfg("idle_life_smoke_weight"));
    var _drink = max(0, csq_cfg("idle_life_drink_weight"));
    var _eat   = max(0, csq_cfg("idle_life_eat_weight"));

    var _fav = csq_human_mix(csq_human_seed(), 7) mod 3;

    if (_fav == 0) _smoke *= 2;
    if (_fav == 1) _drink *= 2;
    if (_fav == 2) _eat   *= 2;

    var _total = _smoke + _drink + _eat;
    if (_total <= 0) return -1;

    var _roll = random(_total);

    if (_roll < _smoke)            return csq_idle_kind_smoke();
    if (_roll < (_smoke + _drink)) return csq_idle_kind_drink();

    return csq_idle_kind_eat();
}


/// @func   csq_idle_care_busy()
/// @desc   Whether the bandage machine owns this instance. Guarded, because a
///         companion spawned before self-care existed in the config has no state.
/// @return {Bool}
function csq_idle_care_busy()
{
    if (!variable_instance_exists(id, "csq_care_state")) return false;
    return (csq_care_state != csq_care_state_idle());
}


/// @func   csq_idle_wants(_player)
/// @desc   Every entry condition, in ascending order of cost.
///
///         csq_mode IS LAST FRAME'S, AND THAT IS CORRECT
///         csq_idle_step runs above the dispatch that sets the mode, so the value read
///         here was decided on the previous frame. Idle life is a claim that nothing
///         has happened for twenty-five seconds; a mode that is one frame stale is not
///         the weak link in that claim, and the target and bullet tests below are both
///         current.
/// @param  {Id.Instance} _player
/// @return {Bool}
function csq_idle_wants(_player)
{
    if (_player == noone) return false;

    // follow and hold only. engage has a fight and medic has a patient.
    if (csq_mode != csq_ai_mode_follow() && csq_mode != csq_ai_mode_hold()) return false;

    if (csq_idle_care_busy()) return false;

    if (csq_ai_hostile_target_exists()) return false;

    var _calm = csq_seconds_to_frames(max(0, csq_cfg("idle_life_calm_seconds"))) +
                csq_idle_stagger_frames();

    if (csq_idle_calm < _calm) return false;

    // Standing still for a second, which doubles as "has arrived" -- see the note in
    // csq_idle_track.
    var _second = csq_seconds_to_frames(1);

    if (csq_idle_still < _second) return false;

    // In follow mode the player has to have stopped too, or the companion sits down
    // and is immediately left behind. In hold mode it does not: a companion smoking
    // at its held position while you scout ahead is the intended picture.
    if (csq_mode == csq_ai_mode_follow() && csq_idle_pstill < _second) return false;

    var _leash = max(0, csq_cfg("follow_distance")) + max(0, csq_cfg("catchup_distance"));
    if (point_distance(x, y, _player.x, _player.y) > _leash) return false;

    if (csq_idle_concurrent() >= max(0, floor(csq_cfg("idle_life_max_concurrent")))) return false;

    // Last, because it is the only test that touches the instance list of another
    // object entirely.
    if (csq_idle_danger()) return false;

    return true;
}


/// @func   csq_idle_enter(_kind)
/// @desc   Start animating. This is scr_npc_arms' body minus the one line that would
///         hand `state` back to vanilla -- see the header.
/// @param  {Real} _kind  2 eat, 3 drink, 4 smoke
/// @return {Bool} whether it started
function csq_idle_enter(_kind)
{
    var _object = csq_idle_kind_object(_kind);
    if (_object == noone) return false;

    var _min = max(1, floor(csq_cfg("idle_life_min_seconds")));
    var _max = max(_min, floor(csq_cfg("idle_life_max_seconds")));

    csq_idle_state = csq_idle_state_living();
    csq_idle_kind  = _kind;
    csq_idle_timer = csq_seconds_to_frames(irandom_range(_min, _max));

    state           = csq_ai_state_idle();
    human_state_now = _kind;
    draw_weapon     = false;

    try { path_end(); } catch (_err) {}

    var _prop = instance_create_depth(x, y, 0, _object);

    // Both fields are what the prop's Step reads. depth it sets itself, from
    // linked_id.depth, so the 0 above is only a starting value.
    _prop.linked_id    = id;
    _prop.image_xscale = image_xscale;

    csq_log_debug("idle: " + csq_ai_display_name() + " settles in for a " +
                  csq_idle_kind_name(_kind) + ", " + string(csq_idle_timer) + "f");

    return true;
}


/// @func   csq_idle_exit(_why)
/// @desc   Stop animating and hand the companion back. Safe to call at any time from
///         anywhere, including on an instance that was never animating -- csq_care
///         calls it unconditionally.
/// @param  {String} _why  for the log
/// @return {Bool} whether anything was actually stopped
function csq_idle_exit(_why)
{
    if (!variable_instance_exists(id, "csq_idle_state")) return false;
    if (csq_idle_state == csq_idle_state_off())          return false;

    var _kind = csq_idle_kind;

    csq_idle_state = csq_idle_state_off();
    csq_idle_kind  = -1;
    csq_idle_timer = 0;

    // The calm clock restarts. That is the whole cooldown mechanism, and it is why
    // there is no idle_life_cooldown key: a companion has to earn another full
    // idle_life_calm_seconds of quiet before it can sit down again.
    csq_idle_calm = 0;

    // -1 is vanilla's own initial value (obj_npc_parent_Create_0:254). The prop sees
    // the mismatch on its next Step, destroys itself and restores draw_weapon; this
    // sets draw_weapon anyway, in case the prop had already gone for another reason.
    human_state_now = -1;
    draw_weapon     = true;

    // `state` is deliberately NOT restored here. Every caller's next act sets it:
    // csq_ai_step falls through to the dispatch, and csq_care restores it itself. The
    // one thing this must not do is write "human_no_move" back over a mode that has
    // already moved on.
    csq_log_debug("idle: " + csq_ai_display_name() + " puts the " +
                  csq_idle_kind_name(_kind) + " away (" + string(_why) + ")");

    return true;
}


/// @func   csq_idle_step()
/// @desc   Called from csq_ai_step directly after csq_care_step, and above the mode
///         dispatch. Returns true when it has taken the frame.
///
///         WHY IT SCANS FOR TARGETS ITSELF
///         Taking the frame means the dispatch does not run, and the dispatch is where
///         csq_ai_scan_for_targets() lives -- "follow or hold: this module scans,
///         because human_no_move does not". Without the call below, `target` would be
///         frozen at whatever it was when the cigarette was lit, the target-acquired
///         exit could never fire, and a companion would animate through a firefight.
///         Vanilla will not do it for us: obj_npc_parent_Step_0 only calls
///         scr_find_target_for_human inside the human_general case.
/// @return {Bool} whether idle life owns this frame
function csq_idle_step()
{
    try
    {
        // With the switch off this writes nothing at all -- unless it is holding an
        // animation from before the switch was turned off, which has to be put down.
        if (!csq_cfg("idle_life_enabled"))
        {
            csq_idle_exit("switched off");
            return false;
        }

        // Self-healing, so enabling idle life mid-raid works on companions spawned
        // while it was off.
        if (!variable_instance_exists(id, "csq_idle_state")) csq_idle_init_instance();

        var _player = csq_player();

        csq_idle_track(_player);

        if (csq_idle_state == csq_idle_state_living())
        {
            // Keeps `target` current while the dispatch is skipped. Respects
            // scan_interval, the same as the dispatch's own call.
            csq_ai_scan_for_targets();

            // Immediate exits, all tested before the timer: a companion must not
            // finish its animation before reacting to being shot at.
            if (csq_ai_hostile_target_exists()) { csq_idle_exit("target");    return false; }
            if (csq_idle_danger())              { csq_idle_exit("gunfire");   return false; }
            if (csq_idle_care_busy())           { csq_idle_exit("wounded");   return false; }
            if (_player == noone)               { csq_idle_exit("no player"); return false; }

            if (csq_mode != csq_ai_mode_follow() && csq_mode != csq_ai_mode_hold())
            {
                csq_idle_exit("mode " + string(csq_mode));
                return false;
            }

            var _leash = max(0, csq_cfg("follow_distance")) + max(0, csq_cfg("catchup_distance"));

            if (point_distance(x, y, _player.x, _player.y) > _leash)
            {
                csq_idle_exit("player moved off");
                return false;
            }

            csq_idle_timer--;

            if (csq_idle_timer <= 0)
            {
                csq_idle_exit("finished");
                return false;
            }

            // Re-asserted every frame rather than set once. Vanilla's Step has already
            // run by here (event_inherited in obj_csq_companion_Step_0) and is
            // entitled to have changed any of the three -- and if human_state_now
            // drifts for even one frame the prop destroys itself.
            state           = csq_ai_state_idle();
            human_state_now = csq_idle_kind;
            draw_weapon     = false;

            // The same belt-and-braces line csq_ai_step runs at step 4, repeated here
            // because taking the frame skips it. Without it a companion accumulates
            // awareness of the player for as long as it animates, and the scan above
            // is what feeds that awareness -- a maxed alert_player can win the target
            // slot in scr_find_target_for_human and crowd out a real enemy.
            alert_player = 0;

            return true;
        }

        if (!csq_idle_wants(_player)) return false;

        var _kind = csq_idle_pick();
        if (_kind < 0) return false;

        return csq_idle_enter(_kind);
    }
    catch (_err)
    {
        csq_log_exception("csq_idle_step", _err);

        // Never leave a companion holding a cigarette it cannot put down.
        try { csq_idle_exit("error"); } catch (_err2) {}

        return false;
    }
}


/// @func   csq_idle_destroy_props_of(_object, _owner)
/// @desc   Destroy every instance of one obj_arms_* family that belongs to _owner.
/// @param  {Asset.GMObject} _object
/// @param  {Id.Instance} _owner
/// @return {Real} how many were destroyed
function csq_idle_destroy_props_of(_object, _owner)
{
    var _n = 0;

    with (_object)
    {
        if (linked_id == _owner)
        {
            instance_destroy();
            _n++;
        }
    }

    return _n;
}


/// @func   csq_idle_destroy_props(_owner)
/// @desc   Tear down a companion's props. Called from obj_csq_companion's CleanUp,
///         which also fires at room end and game end -- so it swallows everything,
///         the same way csq_squad_notify_cleanup does and for the same reason.
/// @param  {Id.Instance} _owner
/// @return {Real} how many were destroyed
function csq_idle_destroy_props(_owner)
{
    try
    {
        var _n = 0;

        _n += csq_idle_destroy_props_of(obj_arms_smoke, _owner);
        _n += csq_idle_destroy_props_of(obj_arms_drink, _owner);
        _n += csq_idle_destroy_props_of(obj_arms_eat,   _owner);

        return _n;
    }
    catch (_err)
    {
        return 0;
    }
}
