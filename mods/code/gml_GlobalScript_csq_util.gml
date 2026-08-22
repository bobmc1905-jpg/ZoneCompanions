// =============================================================================
//  Zone Companions  -  csq_util
// -----------------------------------------------------------------------------
//  Shared helpers used by more than one module. Anything that would otherwise
//  be copy-pasted between csq_squad, csq_ai, csq_hud or csq_persist belongs
//  here.
//
//  These wrappers exist for one reason: several vanilla routines reach straight
//  into singletons (scr_check_position_free reads obj_controller.grid_motion
//  with no instance_exists guard, for example) and will throw if called at the
//  wrong moment -- during a room transition, on the main menu, or in the hub.
//  Wrapping them once here means the rest of the mod can call them freely
//  without repeating the same defensive checks.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


// -----------------------------------------------------------------------------
//  Player and world state
// -----------------------------------------------------------------------------

/// @func   csq_player()
/// @desc   The local player instance, or noone. player_get_local() alone is not
///         enough: it can return a stale or non-existent id between rooms.
/// @return {Id.Instance} player instance or noone
function csq_player()
{
    try
    {
        if (!player_exists_local()) return noone;

        var _p = player_get_local();
        if (!instance_exists(_p)) return noone;

        return _p;
    }
    catch (_err)
    {
        return noone;
    }
}


/// @func   csq_player_in_world(_player)
/// @desc   Whether the player is standing at a real, usable map position under
///         their own control -- as opposed to mid-intro or dead.
///
///         THIS EXISTS BECAUSE OF THE TRAIN.
///         scr_player_state_start() is the raid intro state, and it does two
///         things every frame: sets visible = false, and pins x/y to obj_train's
///         position. So while it is running, "the player's position" is a moving
///         train, not a place anything can be spawned. Spawning there put the
///         whole squad down at the boarding point; the train then carried the
///         player off without them, and they were culled out of existence a few
///         seconds later.
/// @return {Bool}
function csq_player_in_world(_player)
{
    if (is_undefined(_player)) _player = csq_player();
    if (_player == noone)      return false;

    try
    {
        if (_player.state == scr_player_state_start) return false;
        if (_player.state == scr_player_state_dead)  return false;
    }
    catch (_err)
    {
        // Unreadable state: assume in-world rather than never acting at all.
        return true;
    }

    return true;
}


/// @func   csq_in_raid()
/// @desc   True while in a raid map. Vanilla is_in_raid() is "room == room1".
function csq_in_raid()
{
    try { return is_in_raid(); } catch (_err) { return false; }
}


/// @func   csq_in_hub()
/// @desc   True while in the hub. Companions do not fight here -- vanilla
///         scr_find_target_for_human forces no target when is_in_hub().
function csq_in_hub()
{
    try { return is_in_hub(); } catch (_err) { return false; }
}


/// @func   csq_alive(_inst)
/// @desc   One check for "this id is a live instance with hp left". Companion
///         records hold ids that vanilla may destroy at any time (the NPC step
///         event calls instance_destroy() when hp <= 0), so every access to a
///         roster instance goes through this.
function csq_alive(_inst)
{
    if (is_undefined(_inst)) return false;
    if (_inst == noone)      return false;

    try
    {
        if (!instance_exists(_inst)) return false;
        if (variable_instance_exists(_inst, "hp") && _inst.hp <= 0) return false;
        return true;
    }
    catch (_err)
    {
        return false;
    }
}


// -----------------------------------------------------------------------------
//  Positions and navigation
// -----------------------------------------------------------------------------

/// @func   csq_pos_walkable(_x, _y)
/// @desc   Guarded wrapper around vanilla scr_check_position_free, which tests
///         obj_controller.grid_motion (0 = walkable, -1 = blocked) plus the
///         map generator's tile bounds. Reused rather than reimplemented so the
///         mod always agrees with the game about what is walkable.
function csq_pos_walkable(_x, _y)
{
    try
    {
        // Outside a raid the vanilla routine returns true unconditionally, but
        // it also dereferences obj_controller, so guard that first.
        if (!instance_exists(obj_controller)) return false;

        // And it indexes obj_controller.grid_motion with no validity check of its
        // own. During a map load that grid does not exist yet, and a bad
        // ds_grid_get is not reliably catchable, so it is checked explicitly.
        if (!variable_instance_exists(obj_controller, "grid_motion"))          return false;
        if (!ds_exists(obj_controller.grid_motion, ds_type_grid))              return false;

        return scr_check_position_free(_x, _y);
    }
    catch (_err)
    {
        return false;
    }
}


/// @func   csq_pos_clear_of_companions(_x, _y, _min_sep)
/// @desc   Whether (_x, _y) is at least _min_sep from every live companion.
///         Used to stop a batch spawn stacking the whole squad on one cell.
function csq_pos_clear_of_companions(_x, _y, _min_sep)
{
    if (_min_sep <= 0) return true;

    try
    {
        with (obj_csq_companion)
        {
            if (point_distance(x, y, _x, _y) < _min_sep) return false;
        }
    }
    catch (_err)
    {
        // If the object cannot be enumerated, separation is simply not enforced.
        return true;
    }

    return true;
}


/// @func   csq_find_free_pos(_x, _y, _radius, _attempts, _min_sep)
/// @desc   Look for a walkable point within _radius of (_x, _y). Same
///         repeat-until-free idiom as vanilla npc_spawn_near_player, but at
///         close range -- that routine is hardcoded to 240-280px, which is far
///         too distant for a companion.
///
///         _min_sep (optional, default 0) rejects candidates within that
///         distance of an existing companion. Without it, spawning a squad in one
///         loop put every member on the identical cell: the origin shortcut below
///         returns the player's own tile, which is walkable by definition, so
///         every call in the batch got the same answer.
/// @return {Struct} {x, y, ok}
function csq_find_free_pos(_x, _y, _radius, _attempts, _min_sep)
{
    if (is_undefined(_attempts)) _attempts = 60;
    if (is_undefined(_min_sep))  _min_sep  = 0;

    // The origin itself is usually fine; try it before scattering. Skipped when a
    // separation is required, since the origin is shared by every caller in a batch.
    if (csq_pos_walkable(_x, _y) && csq_pos_clear_of_companions(_x, _y, _min_sep))
    {
        return { x: _x, y: _y, ok: true };
    }

    for (var _i = 0; _i < _attempts; _i++)
    {
        // Spiral outwards so the closest candidates are tried first.
        var _dist  = _radius * ((_i + 1) / _attempts);
        var _angle = irandom(360);
        var _cx    = _x + lengthdir_x(_dist, _angle);
        var _cy    = _y + lengthdir_y(_dist, _angle);

        if (csq_pos_walkable(_cx, _cy) &&
            csq_pos_clear_of_companions(_cx, _cy, _min_sep))
        {
            return { x: _cx, y: _cy, ok: true };
        }
    }

    // Fall back to a walkable cell without the separation requirement rather than
    // reporting failure -- overlapping is far better than not spawning.
    if (_min_sep > 0)
    {
        var _relaxed = csq_find_free_pos(_x, _y, _radius, _attempts, 0);
        if (_relaxed.ok) return _relaxed;
    }

    // Caller decides what to do; nothing in the mod treats this as fatal.
    return { x: _x, y: _y, ok: false };
}


/// @func   csq_formation_point(_slot, _total, _anchor_x, _anchor_y, _facing)
/// @desc   Where companion _slot should stand relative to the player. Slots are
///         fanned out behind the player across an arc so companions neither
///         stack on one another nor block the player's line of fire.
/// @return {Struct} {x, y}
function csq_formation_point(_slot, _total, _anchor_x, _anchor_y, _facing)
{
    var _dist   = csq_cfg("follow_distance");
    var _spread = csq_cfg("formation_spread");

    if (_total < 1) _total = 1;

    // Spread slots evenly over an arc centred behind the player. With one
    // companion that is directly behind; with three it is a shallow V.
    var _arc    = min(140, _spread * _total);
    var _step   = (_total > 1) ? (_arc / (_total - 1)) : 0;
    var _offset = (_total > 1) ? (-_arc * 0.5 + _step * _slot) : 0;

    var _dir = _facing + 180 + _offset;

    return {
        x: _anchor_x + lengthdir_x(_dist, _dir),
        y: _anchor_y + lengthdir_y(_dist, _dir)
    };
}


// -----------------------------------------------------------------------------
//  Small generic helpers
// -----------------------------------------------------------------------------

/// @func   csq_array_remove_at(_array, _index)
/// @desc   Delete one entry in place. array_delete exists in this runtime, but
///         routing it through here keeps bounds checking in one spot.
function csq_array_remove_at(_array, _index)
{
    if (_index < 0 || _index >= array_length(_array)) return false;

    array_delete(_array, _index, 1);
    return true;
}


/// @func   csq_struct_get(_struct, _key, _default)
/// @desc   Read a struct field with a fallback. Used heavily when loading saved
///         data, where an older save may simply not have a field.
function csq_struct_get(_struct, _key, _default)
{
    if (!is_struct(_struct))                        return _default;
    if (!variable_struct_exists(_struct, _key))     return _default;

    var _v = variable_struct_get(_struct, _key);
    if (is_undefined(_v))                           return _default;

    return _v;
}


/// @func   csq_clamp_int(_value, _min, _max)
/// @desc   Clamp and round to a whole number, for counts and indices read from
///         user-editable config.
function csq_clamp_int(_value, _min, _max)
{
    return floor(clamp(_value, _min, _max));
}
