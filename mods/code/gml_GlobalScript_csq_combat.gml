// =============================================================================
//  Zone Companions  -  csq_combat
// -----------------------------------------------------------------------------
//  Footwork during a firefight. The mod moves the feet; vanilla keeps the
//  trigger.
//
//  THE BUG THIS FIXES
//  A companion with an enemy in range stopped dead and became a turret. That is
//  not a mod bug -- it is what vanilla's human_general selector does -- and it is
//  worth spelling out, because every number below is chosen against it.
//
//  obj_npc_parent_Step_0 builds a ds_priority of candidate actions whenever
//  human_tick runs out, then takes ds_priority_find_max. Two of those actions
//  matter here:
//      29  Advance   weight 17, offered only when range_type != 0
//      11  Shoot     weight 18, offered only when range_type == 0
//  range_type == 0 means "the target is inside this weapon's effective band", so
//  the two are mutually exclusive by construction: the moment an enemy is close
//  enough to shoot at, the only action that closes distance stops being offered.
//  Action 11 also outweighs it, and state changes are a ratchet -- a new action
//  needs sub_ai_peso[human_state_now] < sub_ai_peso[_next_state] unless
//  state_finito is set -- so nothing lighter gets a look in either.
//
//  All of action 11's footwork is this (Step_0:1816-1831), and only on the frames
//  where a burst begins:
//      path_end();
//      if (scr_chance(75)) { var _xx = irandom_range(-8, 8);
//                            scr_enemy_choose_move_pos(x + _xx, y + _xx, 16); }
//      else                { move_point_x = x; move_point_y = y; }
//  A sixteen-pixel shuffle, three times out of four. That is the whole of a
//  vanilla NPC's movement while shooting.
//
//  AND IT WOULD STILL BARELY MOVE
//  Two further details defeat the naive fix of simply handing it a goal:
//
//  1.  Nothing repaths while shooting. Every other moving action in the selector
//      calls scr_enemy_path() itself, every frame; case 11 never does -- it only
//      calls path_end() at the start of each burst. A goal given to a shooting
//      companion is a goal nothing ever walks to.
//
//  2.  scr_enemy_path derives its own speed, and for state == "human_general" it
//      raises that to spd_alerted only for human_state_now in
//      {12,13,14,15,16,17,18,26,28,29,30,33,38}. 11 is absent. A shooting NPC
//      therefore walks at spd_not_alerted, a quarter of a pixel per step, so
//      path_speed has to be re-set AFTER scr_enemy_path returns -- every frame.
//
//  WHY COMMITTED MOVES
//  The fix is not "walk toward the enemy while shooting" -- that reads as a
//  conveyor belt. It is: pick a spot, walk to it, then stand and fight from it
//  for a while. The commit window is the humanity. A companion that re-decides
//  its destination every frame twitches; one that holds a decision for three
//  quarters of a second looks like it meant it.
//
//  THREE KINDS OF MOVE, ONE MACHINE
//  All three share csq_combat_commit and csq_combat_walk; they differ only in what
//  provokes them and where they aim.
//      push        the target is far enough away to be worth closing on. Aims along
//                  the line to it, angled off by this companion's side of the arc.
//      spread      a squadmate is standing too close. Aims across that line, on
//                  whichever side ends further from them. Own cooldown, so a stack
//                  can be broken up during the pause between advances.
//      reposition  nothing above has fired for four seconds and the companion has
//                  not moved. Aims across the line, side at random. This is the only
//                  one that runs when the target is already closer than
//                  push_stop_distance, which is precisely the case push cannot help
//                  with and the case vanilla is worst at.
//  Neither sidestep gives up ground: csq_combat_stop_distance never lets a clamp
//  push a companion outward, only stop it coming further in.
//
//  WHERE VANILLA STILL WINS
//  Every frame of a push re-checks that vanilla is still shooting. The instant it
//  wants to do something else -- take cover, reload, advance on a target that has
//  moved out of range -- the push is abandoned and the feet go straight back. The
//  mod fills the one gap in the selector; it does not argue with the rest of it.
//
//  WHAT IT NEVER TOUCHES
//  target, shoot_time, riflessi, riflessi_max, state_finito, must_take_cover,
//  have_to_reload. Aiming, reaction time and rate of fire stay exactly vanilla.
//  This file writes move_point_x, move_point_y, path_speed and path_timer, and
//  nothing else.
//
//  path_timer IS A DELIBERATE ADDITION TO THAT LIST
//  The design document's list of writable vanilla variables did not include it,
//  because it was drawn up before the "nothing repaths while shooting" detail
//  above was found. Without it a push is a goal with no route: scr_enemy_path
//  rebuilds only when its own path_timer reaches path_timer_reset (30), so up to
//  29 frames out of every 30 the companion would stand still. Assigning
//  path_timer = path_timer_reset to mean "rebuild now" is vanilla's own idiom for
//  it, used at Step_0:637, :2871, :3054 and :3120.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_combat_action_shoot()
/// @desc   The human_general sub-state number for "shoot at the target", so no
///         function below compares against a bare 11. Verified as the case at
///         obj_npc_parent_Step_0:1816 and as the ds_priority_add at :1481.
function csq_combat_action_shoot() { return 11; }


/// @func   csq_combat_flank_sign()
/// @desc   Which side of the straight line to the target this companion leans on.
///
///         Taken from the formation slot rather than rolled, so a squad fans into
///         an arc instead of forming a queue behind whoever got there first -- and
///         so two companions can never happen to pick the same side and stack up
///         anyway.
/// @return {Real} +1 or -1
function csq_combat_flank_sign()
{
    var _slot = 0;
    if (variable_instance_exists(id, "csq_slot") && is_real(csq_slot))
    {
        _slot = abs(floor(csq_slot));
    }

    return ((_slot mod 2) == 0) ? 1 : -1;
}

/// @func   csq_combat_temper_scale(_span)
/// @desc   This companion's temperament expressed as a multiplier around 1.
///
///         _span is how far the aggressive end may stretch the result: 0.25 gives
///         0.75 at temperament 0 and 1.25 at temperament 99. Pass a NEGATIVE span
///         for a quantity where being aggressive means wanting less of it -- the
///         distance a companion waits for before closing, or the pause between
///         advances.
///
///         Returns exactly 1 when temperament is off, because csq_human_temperament
///         hands back a flat 50 in that case. That is what lets every number below
///         collapse to its configured value for the regression gate, without any
///         caller having to test the switch.
/// @param  {Real} _span  how far temperament may stretch the value, 0..1
/// @return {Real} a multiplier
function csq_combat_temper_scale(_span)
{
    var _t = 50;
    if (variable_instance_exists(id, "csq_temperament") && is_real(csq_temperament))
    {
        _t = clamp(csq_temperament, 0, 99);
    }

    return 1 + (((_t - 50) / 50) * _span);
}


/// @func   csq_combat_commit_frames()
/// @desc   How long this companion holds a move once it has started it.
///
///         csq_react_frames is this companion's own slice of decision latency
///         (csq_human), so two companions pushing on the same frame do not finish
///         on the same frame either. It lengthens the commit and nothing else --
///         no part of this file delays a trigger pull.
/// @return {Real} frames, at least 1
function csq_combat_commit_frames()
{
    var _base  = max(1, floor(csq_cfg("push_commit_frames")));
    var _extra = 0;

    if (variable_instance_exists(id, "csq_react_frames") && is_real(csq_react_frames))
    {
        _extra = max(0, floor(csq_react_frames));
    }

    return _base + _extra;
}

/// @func   csq_combat_push_speed()
/// @desc   Movement speed for a push, in pixels per step.
///
///         Built from the preset's ALERTED speed, because scr_enemy_path would
///         otherwise hand a shooting NPC its idle shuffle speed -- see point 2 in
///         the file header. npc_get_spd_alerted already folds in
///         current_move_speed_multiplier, so anything the game does to slow the
///         world down still applies.
///
///         Capped by the same speed_max the follow loop uses. It is a sanity limit
///         on a configured multiplier, not a follow-specific number.
/// @return {Real}
function csq_combat_push_speed()
{
    try
    {
        var _base = npc_get_spd_alerted(npc_id);
        var _spd  = _base * max(0.1, csq_cfg("push_speed_mult"));

        return clamp(_spd, 0.1, csq_cfg("speed_max"));
    }
    catch (_err)
    {
        csq_log_exception("csq_combat_push_speed", _err);
        return 1;
    }
}


/// @func   csq_combat_stop_distance(_allow_inside)
/// @desc   The closest a piece of footwork may aim to the target.
///
///         push_stop_distance for an advance. For sidesteps -- spread and
///         reposition -- the same number would be a retreat order rather than a
///         limit: a companion that vanilla has already walked to 60 px would be
///         clamped out to 90 and would give up ground it was told to hold. So for
///         those the limit becomes whichever is smaller, the configured distance or
///         the gap the companion is already standing at. It can never be used to
///         push a companion outward, only to stop it coming further in.
/// @param  {Bool} _allow_inside  true for footwork that only moves sideways
/// @return {Real}
function csq_combat_stop_distance(_allow_inside)
{
    var _stop = max(0, csq_cfg("push_stop_distance"));

    if (_allow_inside && csq_ai_hostile_target_exists())
    {
        _stop = min(_stop, point_distance(x, y, target.x, target.y));
    }

    return _stop;
}


/// @func   csq_combat_goal_clamp(_gx, _gy, _player, _stop)
/// @desc   Pull a proposed destination inside the two limits footwork must respect,
///         and report whether a legal destination survived at all.
///
///         The limits are deliberately different in kind. The stop distance is
///         about the companion: do not walk into a shotgun. push_max_from_player is
///         about the squad: an advance is not a solo assault across the map.
///
///         They can contradict each other -- the player standing inside
///         push_stop_distance of the enemy is enough to do it. Rather than pick a
///         winner and return a point that breaks the other, this reports failure
///         and the caller declines to move. Vanilla's own footwork then applies,
///         which is the right answer when the player is already in the enemy's
///         face: the companion holds and shoots rather than crowding in.
/// @param  {Real} _gx      proposed goal x
/// @param  {Real} _gy      proposed goal y
/// @param  {Id.Instance} _player
/// @param  {Real} _stop    from csq_combat_stop_distance
/// @return {Struct} { x, y, ok }
function csq_combat_goal_clamp(_gx, _gy, _player, _stop)
{
    var _x2   = _gx;
    var _y2   = _gy;
    var _has  = csq_ai_hostile_target_exists();

    // 1. Never aim closer to the target than the stop distance.
    if (_has)
    {
        var _d = point_distance(_x2, _y2, target.x, target.y);

        if (_d < _stop)
        {
            // Back off along the line from the target out to the goal. If the goal
            // landed exactly on the target there is no such line, so use the one
            // out to the companion instead.
            var _out = (_d <= 0.001) ? point_direction(target.x, target.y, x, y)
                                     : point_direction(target.x, target.y, _x2, _y2);

            _x2 = target.x + lengthdir_x(_stop, _out);
            _y2 = target.y + lengthdir_y(_stop, _out);
        }
    }

    // 2. Never aim further from the player than push_max_from_player.
    var _leash = max(0, csq_cfg("push_max_from_player"));

    if (point_distance(_x2, _y2, _player.x, _player.y) > _leash)
    {
        var _in = point_direction(_player.x, _player.y, _x2, _y2);

        _x2 = _player.x + lengthdir_x(_leash, _in);
        _y2 = _player.y + lengthdir_y(_leash, _in);
    }

    // Step 2 can undo step 1, so the stop distance -- the limit that matters for
    // the companion's own survival -- is the one that gets the final word.
    // A pixel of tolerance, because both clamps land on a radius exactly.
    var _ok = true;

    if (_has && point_distance(_x2, _y2, target.x, target.y) < (_stop - 1))
    {
        _ok = false;
    }

    return { x: _x2, y: _y2, ok: _ok };
}

/// @func   csq_combat_stalled()
/// @desc   Whether the companion failed to move at all since the last frame of
///         this push, i.e. whether it currently has no path to walk.
///
///         WHY IT IS MEASURED RATHER THAN ASKED
///         The direct question is `path_index == -1`. It is avoided on purpose:
///         path_index appears nowhere in the vanilla game, and the mod's GML is
///         compiled by GMLoader rather than by the GameMaker IDE. A built-in the
///         compiler does not recognise becomes a plain instance-variable lookup,
///         which reads as undefined at runtime -- a crash in a Step event, on every
///         frame, for a check that only exists to save a little work. Position is
///         something both compilers agree about.
///
///         A blocked companion also reads as stalled, which is why the caller rate
///         limits how often a stall may force a rebuild.
/// @return {Bool}
function csq_combat_stalled()
{
    var _moved = point_distance(x, y, csq_push_last_x, csq_push_last_y);

    csq_push_last_x = x;
    csq_push_last_y = y;

    return (_moved < 0.05);
}


/// @func   csq_combat_drive(_gx, _gy, _repath)
/// @desc   Walk toward a goal using the same A* routine every vanilla NPC uses.
///
///         The goal is written unconditionally rather than behind the
///         goal_move_threshold guard csq_ai_drive_follow uses. That guard exists
///         because a formation slot moves every frame; a commit goal does not move
///         at all, and vanilla overwrites move_point_x/y from underneath us at the
///         start of every burst (Step_0:1824), so declining to rewrite it would
///         simply lose the goal.
/// @param  {Real} _gx
/// @param  {Real} _gy
/// @param  {Bool} _repath  true on the frame the goal changes
function csq_combat_drive(_gx, _gy, _repath)
{
    move_point_x = _gx;
    move_point_y = _gy;

    try
    {
        if (csq_push_repath_cd > 0) csq_push_repath_cd--;

        // Vanilla calls path_end() at the start of every burst (Step_0:1820) and
        // never starts another while shooting, so a push spends most of its frames
        // with no path at all. Rebuilding is the only way back: scr_enemy_path is
        // the only thing in the game that calls path_start for a human, and it does
        // so only when its own 30-frame timer expires. Forcing that timer is
        // vanilla's own idiom for "repath now" (Step_0:637, :2871, :3054, :3120).
        //
        // Rate limited, because a companion wedged against geometry looks exactly
        // like one whose path was just cancelled, and rebuilding an A* route every
        // frame for four companions is not free.
        //
        // The stall test runs unconditionally rather than inside the || below: it
        // is also what keeps csq_push_last_x/y current, and GML short-circuits.
        var _stalled = csq_combat_stalled();
        var _force   = _repath || (_stalled && csq_push_repath_cd <= 0);

        if (_force)
        {
            path_timer         = path_timer_reset;
            csq_push_repath_cd = 8;
        }

        // Vanilla A*: snaps an unreachable goal to the nearest walkable cell
        // (overwriting move_point_x/y as it does so), then mp_grid_path over
        // global.grid_move, then path_start.
        scr_enemy_path();

        // Own the speed, last. scr_enemy_path sets it too, and for a shooting NPC
        // it sets it to the idle shuffle speed -- see point 2 in the file header.
        path_speed = csq_combat_push_speed();
    }
    catch (_err)
    {
        csq_log_exception("csq_combat_drive", _err);
    }
}


/// @func   csq_combat_push_abort()
/// @desc   Give the feet back to vanilla, mid-move, no argument.
///
///         Called the moment vanilla stops shooting -- it wants cover, or a reload,
///         or the target left the weapon's band and action 29 is available again --
///         and whenever the companion leaves engage mode entirely.
///
///         Deliberately does NOT call path_end(). Vanilla has already chosen its own
///         move_point for whichever action just took over, and every one of those
///         actions calls scr_enemy_path itself on every frame. Ending the path would
///         leave the companion standing still until that call's timer next came
///         round; forcing the rebuild instead means vanilla's intention takes effect
///         on the very next frame. Costs nothing when no push was running.
function csq_combat_push_abort()
{
    if (!variable_instance_exists(id, "csq_push_timer")) return;
    if (csq_push_timer <= 0) return;

    csq_push_timer = 0;

    try { path_timer = path_timer_reset; } catch (_err) {}
}


/// @func   csq_combat_fighting()
/// @desc   Whether footwork is allowed to touch the feet at all this frame.
///
///         Re-tested on every frame of a move, not just its first. Vanilla deciding
///         it would rather take cover, or reload, or that the target has left the
///         weapon's band and action 29 is available again, ends the move at once:
///         this module fills the one gap in the selector, it does not overrule the
///         rest of it.
/// @return {Bool}
function csq_combat_fighting()
{
    if (state != csq_ai_state_combat()) return false;
    if (human_state_now != csq_combat_action_shoot()) return false;

    return csq_ai_hostile_target_exists();
}


/// @func   csq_combat_commit(_gx, _gy, _pause)
/// @desc   Start a committed move. Shared by all three kinds of footwork, which
///         differ only in where they aim and what provoked them.
///
///         The root counter is cleared here rather than left to the distance test in
///         csq_combat_step: the companion has not moved yet, and reposition must not
///         be able to fire again on the frame after something else already did.
/// @param  {Real} _gx
/// @param  {Real} _gy
/// @param  {Real} _pause  frames to stand still for after arriving
function csq_combat_commit(_gx, _gy, _pause)
{
    csq_push_goal_x = _gx;
    csq_push_goal_y = _gy;
    csq_push_timer  = csq_combat_commit_frames();

    // The cooldown spans the move as well as the pause after it, so the configured
    // pause reads as "how long it stands and shoots between moves" rather than as an
    // offset from the start of the last one.
    csq_push_cd = csq_push_timer + max(0, floor(_pause));

    csq_root_x      = x;
    csq_root_y      = y;
    csq_root_frames = 0;

    csq_combat_drive(_gx, _gy, true);
}


/// @func   csq_combat_walk()
/// @desc   One frame of a move already in flight: walk it out and do not re-decide.
///         This is the whole behaviour -- the three producers below only choose where
///         to go.
function csq_combat_walk()
{
    csq_push_timer--;

    // Arrived. push_commit_frames is how long a move may take, not how long it must:
    // standing on the goal and repathing to the cell already occupied is the rooting
    // this file exists to remove.
    if (point_distance(x, y, csq_push_goal_x, csq_push_goal_y) <= 8)
    {
        csq_push_timer = 0;
    }

    if (csq_push_timer <= 0)
    {
        // Plant and let vanilla fight from here. The cooldown set at commit time is
        // what keeps it standing for a while; it ages on its own.
        try { path_end(); } catch (_err) {}
        return;
    }

    csq_combat_drive(csq_push_goal_x, csq_push_goal_y, false);
}


/// @func   csq_combat_crowd_mate()
/// @desc   The nearest live squadmate standing inside spread_min_distance, or noone.
///
///         Walks the roster rather than using a collision circle because the roster
///         is short, already to hand, and cannot accidentally match the player, a
///         corpse, or an enemy human.
/// @return {Id.Instance}
function csq_combat_crowd_mate()
{
    var _near  = noone;
    var _best  = max(0, csq_cfg("spread_min_distance"));
    var _count = csq_squad_count();

    for (var _i = 0; _i < _count; _i++)
    {
        var _entry = csq_squad_entry(_i);

        if (is_undefined(_entry)) continue;

        var _inst = _entry.inst;

        if (_inst == id) continue;
        if (!csq_alive(_inst)) continue;

        var _d = point_distance(x, y, _inst.x, _inst.y);

        if (_d <= _best)
        {
            _best = _d;
            _near = _inst;
        }
    }

    return _near;
}


/// @func   csq_combat_spread(_player)
/// @desc   Sidestep out of a stack.
///
///         Always across the line to the target, never along it, so breaking up a
///         stack never costs ground and never walks anyone into the open to do it.
///         Of the two perpendiculars, the one that ends further from the crowding
///         squadmate wins, which is what makes two companions in one spot separate
///         instead of both drifting the same way.
///
///         Has its own cooldown so that it can interrupt the pause between pushes.
///         Two companions in one spot is one grenade; it is worth reacting to before
///         the next advance would have come round anyway.
/// @param  {Id.Instance} _player
/// @return {Bool} true if a move was committed
function csq_combat_spread(_player)
{
    if (!csq_cfg("spread_enabled")) return false;
    if (csq_spread_cd > 0) return false;

    var _mate = csq_combat_crowd_mate();

    if (_mate == noone) return false;

    var _line = point_direction(x, y, target.x, target.y);
    var _step = max(4, csq_cfg("spread_step"));
    var _stop = csq_combat_stop_distance(true);

    var _ax = x + lengthdir_x(_step, _line + 90);
    var _ay = y + lengthdir_y(_step, _line + 90);
    var _bx = x + lengthdir_x(_step, _line - 90);
    var _by = y + lengthdir_y(_step, _line - 90);

    var _pick_a = (point_distance(_ax, _ay, _mate.x, _mate.y) >=
                   point_distance(_bx, _by, _mate.x, _mate.y));

    var _goal = csq_combat_goal_clamp(_pick_a ? _ax : _bx,
                                      _pick_a ? _ay : _by,
                                      _player, _stop);

    if (!_goal.ok)
    {
        csq_spread_cd = 30;
        return false;
    }

    csq_spread_cd = csq_combat_commit_frames() +
                    max(0, floor(csq_cfg("push_cooldown_frames") * 0.5));

    csq_combat_commit(_goal.x, _goal.y,
                      max(0, floor(csq_cfg("push_cooldown_frames") *
                                   csq_combat_temper_scale(-0.33))));

    csq_log_debug("combat: slot " + string(csq_slot) +
                  " spread " + string(floor(_goal.x)) + "," + string(floor(_goal.y)) +
                  " off mate at " + string(floor(point_distance(x, y, _mate.x, _mate.y))) + "px" +
                  " for " + string(csq_push_timer) + "f");

    return true;
}


/// @func   csq_combat_push(_player)
/// @desc   Advance on the target in committed moves while vanilla shoots.
/// @param  {Id.Instance} _player
/// @return {Bool} true if a move was committed
function csq_combat_push(_player)
{
    if (csq_push_cd > 0) return false;

    // ---- entry conditions ---------------------------------------------------
    // An aggressive companion closes from a shorter gap than a cautious one, which
    // is the same thing as saying it needs less provocation to move.
    var _min = max(0, csq_cfg("push_min_distance") * csq_combat_temper_scale(-0.25));

    if (point_distance(x, y, target.x, target.y) < _min) return false;

    if (point_distance(x, y, _player.x, _player.y) > max(0, csq_cfg("push_max_from_player")))
    {
        return false;
    }

    // instance_line_of_sight is vanilla's own one-liner:
    // !collision_line(x, y, target.x, target.y, obj_solid, true, true).
    if (csq_cfg("push_require_los") && !instance_line_of_sight(x, y, target)) return false;

    // ---- where to -----------------------------------------------------------
    // push_step pixels along the line to the target, angled off it by this
    // companion's own side of the arc.
    var _dir  = point_direction(x, y, target.x, target.y) +
                (csq_combat_flank_sign() * csq_cfg("flank_bias_degrees"));
    var _step = max(4, csq_cfg("push_step"));

    var _goal = csq_combat_goal_clamp(x + lengthdir_x(_step, _dir),
                                      y + lengthdir_y(_step, _dir),
                                      _player,
                                      csq_combat_stop_distance(false));
    if (!_goal.ok)
    {
        // The two limits contradicted each other (see csq_combat_goal_clamp).
        // Wait half a second rather than recomputing the same impossible sum on
        // every frame for as long as the player stands there.
        csq_push_cd = 30;
        return false;
    }

    // ---- commit -------------------------------------------------------------
    csq_combat_commit(_goal.x, _goal.y,
                      max(0, floor(csq_cfg("push_cooldown_frames") *
                                   csq_combat_temper_scale(-0.33))));

    // Vanilla bark 8: "I'm pushing", "go go go", "yeah, keep running". Defined by
    // lista_npc_text at line 347 and, being under 324, needs no registration of
    // any kind -- the mod only has to ask for it. BT_traverse is the only vanilla
    // caller, and loner_regular never runs the behaviour tree, so a companion
    // saying this is a line the game has always had and never used here.
    var _chance = csq_cfg("push_callout_chance");

    // Through the squad brake, not straight to the bubble: three companions pushing
    // the same target in the same second is exactly the case that reads as noise.
    // Cooldown first, chance second -- csq_voice_can_speak is the cheaper test and
    // rolling a die we are going to throw away only burns the RNG.
    if (_chance > 0 && csq_voice_can_speak() && scr_chance(_chance))
    {
        try { scr_draw_npc_text(id, 8); } catch (_err) {}
        csq_voice_mark_spoken();
    }

    csq_log_debug("combat: slot " + string(csq_slot) +
                  " push " + string(floor(csq_push_goal_x)) + "," + string(floor(csq_push_goal_y)) +
                  " from " + string(floor(point_distance(x, y, target.x, target.y))) + "px" +
                  " for " + string(csq_push_timer) + "f" +
                  " cd " + string(csq_push_cd) +
                  " temperament " + string(csq_temperament));

    return true;
}


/// @func   csq_combat_reposition(_player)
/// @desc   The anti-turret backstop: shift position after standing in one spot for
///         too long, whatever the range says.
///
///         This is the only footwork that runs when the target is already closer than
///         push_stop_distance, which is exactly the case push cannot help with and
///         the case vanilla is worst at -- action 11 shuffling inside a 16 px box for
///         as long as the fight lasts. It moves sideways only, so it neither charges
///         nor retreats, and it picks its side at random so that a direction blocked
///         by geometry sorts itself out on the next attempt rather than wedging the
///         companion against the same wall forever.
/// @param  {Id.Instance} _player
/// @return {Bool} true if a move was committed
function csq_combat_reposition(_player)
{
    var _after = csq_cfg("reposition_after_frames");

    if (_after <= 0) return false;
    if (csq_root_frames < _after) return false;
    if (csq_push_cd > 0) return false;

    var _line = point_direction(x, y, target.x, target.y);
    var _step = max(4, csq_cfg("reposition_step"));
    var _dir  = _line + (90 * choose(-1, 1));

    var _goal = csq_combat_goal_clamp(x + lengthdir_x(_step, _dir),
                                      y + lengthdir_y(_step, _dir),
                                      _player,
                                      csq_combat_stop_distance(true));
    if (!_goal.ok)
    {
        csq_push_cd = 30;
        return false;
    }

    var _stood = csq_root_frames;

    csq_combat_commit(_goal.x, _goal.y,
                      max(0, floor(csq_cfg("push_cooldown_frames") *
                                   csq_combat_temper_scale(-0.33))));

    csq_log_debug("combat: slot " + string(csq_slot) +
                  " reposition " + string(floor(_goal.x)) + "," + string(floor(_goal.y)) +
                  " after " + string(_stood) + "f rooted" +
                  " at " + string(floor(point_distance(x, y, target.x, target.y))) + "px");

    return true;
}


/// @func   csq_combat_step()
/// @desc   One frame of combat footwork.
///
///         Called from csq_ai_step AFTER the mode dispatch has run, so
///         human_state_now is the sub-state vanilla settled on for this frame
///         rather than the one from the last. Everything in here is a no-op unless
///         the companion is actually in a fight.
///
///         PRODUCER ORDER
///         spread, then push, then reposition.
///         Spread first because it is a reflex rather than a plan: standing on a
///         squadmate is worth fixing before deciding whether to advance, and it is
///         the one that can interrupt the pause between pushes. Reposition last
///         because its trigger -- four seconds in the same place -- cannot be true if
///         either of the others has just fired, so it costs nothing to ask it last
///         and asking it first would let a boredom sidestep pre-empt a real advance.
///
///         push_enabled is the master switch for all three. spread_enabled and
///         reposition_after_frames only choose which of them run underneath it, so
///         that turning combat footwork off restores baseline behaviour exactly --
///         one switch, not three.
function csq_combat_step()
{
    try
    {
        // The cooldowns age in every mode, engage included, for the same reason
        // csq_heal_cd does: time spent doing something else still counts toward the
        // next move being allowed.
        if (csq_push_cd   > 0) csq_push_cd--;
        if (csq_spread_cd > 0) csq_spread_cd--;

        var _player = csq_player();

        if (!csq_cfg("push_enabled") ||
            csq_mode != csq_ai_mode_engage() ||
            _player == noone ||
            !csq_combat_fighting())
        {
            csq_combat_push_abort();

            // Not fighting, so "how long has it stood here" is not a question about
            // rooting any more. Re-anchoring keeps a companion from arriving at a
            // firefight with the counter already expired and sidestepping instantly.
            csq_root_x      = x;
            csq_root_y      = y;
            csq_root_frames = 0;
            return;
        }

        // How long this companion has held one spot, in frames. 24 px of slack so
        // that vanilla's own +/-8 px shuffle inside action 11 does not read as movement.
        if (point_distance(x, y, csq_root_x, csq_root_y) > 24)
        {
            csq_root_x      = x;
            csq_root_y      = y;
            csq_root_frames = 0;
        }
        else
        {
            csq_root_frames++;
        }

        if (csq_push_timer > 0)
        {
            csq_combat_walk();
            return;
        }

        if (csq_combat_spread(_player)) return;
        if (csq_combat_push(_player))   return;

        csq_combat_reposition(_player);
    }
    catch (_err)
    {
        csq_log_exception("csq_combat_step", _err);
    }
}
