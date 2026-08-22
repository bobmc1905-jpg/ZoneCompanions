// =============================================================================
//  Zone Companions  -  csq_squad
// -----------------------------------------------------------------------------
//  Owns the roster: which companions exist, their presets and carried HP, and
//  spawning/despawning them as raids start and end.
//
//  ROSTER vs INSTANCES
//  The roster (global.csq_squad) is durable data that outlives any raid. A live
//  instance id is only ever a cached, disposable pointer, because vanilla's NPC
//  step event calls instance_destroy() the moment hp <= 0 -- entirely outside
//  this mod's control. So every read of .inst goes through csq_alive(), and
//  csq_squad_prune() reconciles the roster with reality once per tick.
//
//  HOW THE PRESET AND NAME REACH THE CREATE EVENT
//  npc_setup honours an `npc_override` instance variable, but
//  obj_npc_parent_Create_0 sets `npc_override = undefined` and our Create event
//  calls event_inherited() before npc_setup, so the override is always cleared
//  by then. Instead the preset is handed over in global.csq_pending_preset,
//  written immediately before instance_create_depth. GML is single-threaded and
//  Create runs synchronously inside that call, so this is deterministic.
//
//  global.csq_pending_name rides along the same way, and exists because npc_setup
//  line 8 does its own name draw:
//      npc_name = npc_generate_name(npc_id);
//  csq_squad_make_entry called the very same generator when the roster entry was
//  created, so the two results are independent random draws and never agree. The
//  roster is the authority: it is the durable record, whereas the instance is
//  destroyed and recreated -- with a fresh name -- on every raid. Passing the
//  roster name in makes the HUD, the log, the medic message, the game's own
//  killfeed and the corpse container all show one name.
//
//  WHY RECRUITING SPAWNS RATHER THAN CONVERTS
//  Converting an existing world NPC into a companion was considered and
//  rejected. A vanilla NPC is not our object, so it has no event of ours to
//  drive it -- steering it would mean patching the 3978-line
//  obj_npc_parent_Step_0, and destroying-and-replacing it risks deleting a quest
//  giver or a scripted spawn. Recruiting therefore creates a fresh companion
//  beside the player. Safe, predictable, and it cannot corrupt a save.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_squad_init()
/// @desc   Ensure the roster exists. Safe to call repeatedly; never clears an
///         existing roster, so a mid-session map load cannot wipe the squad.
function csq_squad_init()
{
    if (!variable_global_exists("csq_squad") || !is_array(global.csq_squad))
    {
        global.csq_squad = [];
        csq_log_debug("squad: roster initialised");
    }

    if (!variable_global_exists("csq_pending_preset"))
    {
        global.csq_pending_preset = undefined;
    }

    if (!variable_global_exists("csq_pending_name"))
    {
        global.csq_pending_name = undefined;
    }

    if (!variable_global_exists("csq_squad_hold"))
    {
        global.csq_squad_hold = false;
    }
}


/// @func   csq_squad_count()
/// @desc   Roster size, including companions not currently spawned.
function csq_squad_count()
{
    csq_squad_init();
    return array_length(global.csq_squad);
}


/// @func   csq_squad_entry(_index)
/// @return {Struct} roster entry, or undefined
function csq_squad_entry(_index)
{
    csq_squad_init();

    if (_index < 0 || _index >= array_length(global.csq_squad)) return undefined;

    return global.csq_squad[_index];
}


/// @func   csq_squad_active_count()
/// @desc   How many roster entries currently have a live instance in the room.
function csq_squad_active_count()
{
    csq_squad_init();

    var _n = 0;
    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        if (csq_alive(global.csq_squad[_i].inst)) _n++;
    }

    return _n;
}


/// @func   csq_squad_max()
/// @desc   Configured cap, clamped to something the HUD and formation code can
///         actually cope with.
function csq_squad_max()
{
    return csq_clamp_int(csq_cfg("max_companions"), 0, 8);
}


/// @func   csq_squad_is_full()
function csq_squad_is_full()
{
    return csq_squad_count() >= csq_squad_max();
}


/// @func   csq_squad_find_by_inst(_inst)
/// @return {Real} roster index, or -1
function csq_squad_find_by_inst(_inst)
{
    csq_squad_init();

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        if (global.csq_squad[_i].inst == _inst) return _i;
    }

    return -1;
}


/// @func   csq_squad_make_entry(_preset, _name, _hp)
/// @desc   A roster record. hp of -1 means "undamaged", resolved at spawn time
///         from the preset's own max HP.
function csq_squad_make_entry(_preset, _name, _hp)
{
    if (is_undefined(_preset) || string(_preset) == "") _preset = csq_cfg("default_preset");
    if (is_undefined(_hp))                              _hp     = -1;

    if (is_undefined(_name) || string(_name) == "")
    {
        _name = "Companion";

        // npc_generate_name is what vanilla uses for NPC display names; if it
        // is unavailable for any reason the generic label above is fine.
        try { _name = npc_generate_name(_preset); } catch (_err) {}
    }

    return {
        preset: string(_preset),
        name:   string(_name),
        hp:     _hp,
        inst:   noone,

        // Set only by csq_squad_notify_cleanup, and only on a confirmed death.
        // csq_squad_prune acts on this rather than on instance_exists -- see the
        // deactivation note in its header.
        dead:   false,

        // Rate-limits the "is deactivated" DEBUG line to one per transition.
        deact_logged: false,

        // Medic charges left this raid. Lives on the roster rather than on the
        // instance because an instance is destroyed at raid exit and *reported
        // missing* while the game has it deactivated -- so an instance variable
        // would silently reset the count every time a companion fell behind and
        // got culled. Refilled by csq_squad_refill_heal_charges at raid start.
        heal_charges: csq_squad_heal_charges_max()
    };
}


/// @func   csq_squad_heal_charges_max()
/// @desc   Configured charges per companion per raid, floored at 0 so a negative
///         value in the ini disables healing rather than making it infinite.
function csq_squad_heal_charges_max()
{
    return max(0, floor(csq_cfg("heal_charges")));
}


/// @func   csq_squad_heal_charges(_entry)
/// @desc   Charges remaining for a roster entry. Defaults to the configured
///         maximum, so an entry loaded from a save written before this field
///         existed starts the raid with a full complement rather than none.
function csq_squad_heal_charges(_entry)
{
    if (is_undefined(_entry)) return 0;

    return csq_struct_get(_entry, "heal_charges", csq_squad_heal_charges_max());
}


/// @func   csq_squad_refill_heal_charges()
/// @desc   Give every companion its heals back.
///
///         CALLED AT RAID *START*, NOT RAID EXIT.
///         Both give the player the same thing -- a full complement every raid --
///         but refilling on entry is the one that cannot be skipped. The raid exit
///         event does not run if the game crashes, is closed from the task manager,
///         or the player dies in a way that bypasses the exit screen; refilling
///         there would leave the squad permanently dry in exactly those cases.
/// @return {Real} how many entries were refilled
function csq_squad_refill_heal_charges()
{
    csq_squad_init();

    var _max = csq_squad_heal_charges_max();
    var _n   = 0;

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        global.csq_squad[_i].heal_charges = _max;
        _n++;
    }

    if (_n > 0)
    {
        csq_log_debug("squad: refilled " + string(_n) + " companion(s) to " +
                      string(_max) + " heal charge(s)");
    }

    return _n;
}


/// @func   csq_squad_consume_heal_charge(_inst)
/// @desc   Spend one charge for the companion instance _inst.
/// @return {Bool} whether a charge was actually available and spent
function csq_squad_consume_heal_charge(_inst)
{
    var _index = csq_squad_find_by_inst(_inst);
    if (_index < 0) return false;

    var _entry = global.csq_squad[_index];
    var _left  = csq_squad_heal_charges(_entry);

    if (_left <= 0) return false;

    _entry.heal_charges = _left - 1;
    return true;
}


/// @func   csq_squad_spawn_entry(_entry, _slot)
/// @desc   Create the live instance for one roster entry beside the player.
/// @return {Id.Instance} the new instance, or noone
function csq_squad_spawn_entry(_entry, _slot)
{
    try
    {
        if (is_undefined(_entry)) return noone;

        var _player = csq_player();
        if (_player == noone)
        {
            csq_log_warn("squad: cannot spawn '" + _entry.name + "', no local player");
            return noone;
        }

        // Look for somewhere walkable near the player. Searching a few times the
        // configured offset gives the spiral search room to work in tight cover.
        // The separation argument stops a batch spawn stacking the whole squad on
        // one cell -- without it every member of the roster got the player's own
        // tile, because that tile is walkable by definition.
        var _sep    = max(0, csq_cfg("spawn_offset"));
        var _radius = max(16, _sep * 3);
        var _pos    = csq_find_free_pos(_player.x, _player.y, _radius, 60, _sep);

        if (!_pos.ok)
        {
            // Not fatal: the player's own tile is walkable by definition, and
            // pathing will separate them on the next frame.
            csq_log_warn("squad: no free cell near player for '" + _entry.name +
                         "', spawning on the player");
        }

        // Hand the preset and the roster's name to the Create event (see header).
        global.csq_pending_preset = _entry.preset;
        global.csq_pending_name   = _entry.name;

        var _inst = instance_create_depth(_pos.x, _pos.y, 0, obj_csq_companion);

        global.csq_pending_preset = undefined;
        global.csq_pending_name   = undefined;

        if (!instance_exists(_inst))
        {
            csq_log_error("squad: instance_create_depth returned no instance for '" +
                          _entry.name + "'");
            return noone;
        }

        _entry.inst = _inst;
        _inst.csq_slot = _slot;

        // Restore carried damage. Clamped so a stale save cannot exceed the
        // preset's current max HP.
        if (_entry.hp > 0)
        {
            _inst.hp = min(_entry.hp, _inst.hp);
        }

        csq_log_info("squad: spawned '" + _entry.name + "' (" + _entry.preset +
                     ") slot " + string(_slot) +
                     " at " + string(floor(_pos.x)) + "," + string(floor(_pos.y)) +
                     " hp " + string(_inst.hp));

        return _inst;
    }
    catch (_err)
    {
        global.csq_pending_preset = undefined;
        global.csq_pending_name   = undefined;
        csq_log_exception("csq_squad_spawn_entry", _err);
        return noone;
    }
}


/// @func   csq_squad_recruit(_preset)
/// @desc   Add a companion to the roster and spawn it if we are in a raid.
/// @return {Bool} success
function csq_squad_recruit(_preset)
{
    csq_squad_init();

    if (csq_squad_is_full())
    {
        csq_log_info("squad: roster full (" + string(csq_squad_max()) + "), recruit ignored");
        return false;
    }

    var _entry = csq_squad_make_entry(_preset, undefined, -1);
    array_push(global.csq_squad, _entry);

    var _slot = array_length(global.csq_squad) - 1;

    csq_log_info("squad: recruited '" + _entry.name + "' (" + _entry.preset +
                 "), roster now " + string(csq_squad_count()));

    // Only spawn where NPCs belong. In the hub, companions stay on the roster
    // and appear at the start of the next raid.
    if (csq_in_raid())
    {
        csq_squad_spawn_entry(_entry, _slot);
    }
    else
    {
        csq_log_debug("squad: not in a raid, '" + _entry.name + "' will spawn on the next one");
    }

    return true;
}


/// @func   csq_squad_despawn_entry(_entry)
/// @desc   Remove the live instance but keep the roster record, storing current
///         HP so damage carries between raids.
function csq_squad_despawn_entry(_entry)
{
    try
    {
        if (is_undefined(_entry)) return false;

        if (csq_alive(_entry.inst))
        {
            _entry.hp = _entry.inst.hp;

            // The companion's CleanUp event handles its own bookkeeping.
            with (_entry.inst) instance_destroy();

            csq_log_debug("squad: despawned '" + _entry.name + "', carried hp " + string(_entry.hp));
        }

        _entry.inst = noone;
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_squad_despawn_entry", _err);
        return false;
    }
}


/// @func   csq_squad_remove_at(_index)
/// @desc   Permanently drop a roster entry, despawning it first.
function csq_squad_remove_at(_index)
{
    csq_squad_init();

    var _entry = csq_squad_entry(_index);
    if (is_undefined(_entry)) return false;

    var _name = _entry.name;

    csq_squad_despawn_entry(_entry);
    csq_array_remove_at(global.csq_squad, _index);
    csq_squad_reassign_slots();

    csq_log_info("squad: dismissed '" + _name + "', roster now " + string(csq_squad_count()));
    return true;
}


/// @func   csq_squad_reassign_slots()
/// @desc   Keep formation slots contiguous after a removal, so the fan-out in
///         csq_formation_point has no gaps.
function csq_squad_reassign_slots()
{
    csq_squad_init();

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _entry = global.csq_squad[_i];
        if (csq_alive(_entry.inst)) _entry.inst.csq_slot = _i;
    }
}


/// @func   csq_squad_spawn_all()
/// @desc   Bring the whole roster into the current raid. Entries that already
///         have a live instance are skipped, so this is safe to call more than
///         once per raid.
function csq_squad_spawn_all()
{
    csq_squad_init();

    if (!csq_in_raid())
    {
        csq_log_debug("squad: spawn_all skipped, not in a raid");
        return 0;
    }

    var _spawned = 0;
    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _entry = global.csq_squad[_i];

        if (csq_alive(_entry.inst)) continue;

        if (csq_squad_spawn_entry(_entry, _i) != noone) _spawned++;
    }

    if (_spawned > 0)
    {
        csq_log_info("squad: spawned " + string(_spawned) + " companion(s) into the raid");
    }

    return _spawned;
}


/// @func   csq_squad_despawn_all()
/// @desc   Clear every live instance, preserving the roster. Called at raid exit.
function csq_squad_despawn_all()
{
    csq_squad_init();

    var _n = 0;
    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        if (csq_alive(global.csq_squad[_i].inst))
        {
            csq_squad_despawn_entry(global.csq_squad[_i]);
            _n++;
        }
        else
        {
            global.csq_squad[_i].inst = noone;
        }
    }

    if (_n > 0) csq_log_info("squad: despawned " + string(_n) + " companion(s)");
    return _n;
}


/// @func   csq_squad_prune()
/// @desc   Reconcile the roster against the world once per tick.
///
///         WHY THIS NO LONGER TRUSTS instance_exists()
///         It used to remove any entry whose instance had stopped existing, on the
///         assumption that vanilla had destroyed it on death. That was wrong, and
///         it deleted healthy squads.
///
///         obj_controller_Alarm_4 reschedules itself every 20 frames (60 on low
///         spec) and runs:
///             instance_deactivate_region(x - 480, y - 270, 960, 540, false, true);
///             instance_activate_region (x - 480, y - 270, 960, 540, true);
///         i.e. it deactivates everything outside a 960x540 box around the
///         controller. GameMaker reports a *deactivated* instance as
///         instance_exists() == false, and fires no event when deactivating. So a
///         companion that merely fell behind looked exactly like a corpse, and the
///         roster entry was destroyed while the companion was still standing there
///         -- later reactivating, orphaned, and fighting on its own.
///
///         Death is now reported only by the companion's CleanUp event, which is
///         the one signal that genuinely means the instance is gone. See
///         csq_squad_notify_cleanup. Recovery of deactivated companions is
///         csq_squad_recover_deactivated's job.
function csq_squad_prune()
{
    csq_squad_init();

    // Walk backwards: removing an entry shifts everything after it.
    for (var _i = array_length(global.csq_squad) - 1; _i >= 0; _i--)
    {
        var _entry = global.csq_squad[_i];

        if (csq_struct_get(_entry, "dead", false))
        {
            _entry.inst = noone;

            if (csq_cfg("respawn_on_death"))
            {
                // Clear the flag and the carried damage so the next raid gets a
                // fresh companion rather than a permanently dead roster slot.
                _entry.dead = false;
                _entry.hp   = -1;
                csq_log_info("squad: '" + _entry.name + "' died, will return next raid");
            }
            else
            {
                csq_log_info("squad: '" + _entry.name + "' was lost, removing from roster");
                csq_array_remove_at(global.csq_squad, _i);
            }

            continue;
        }

        // Not dead. A missing instance here means deactivated, not destroyed.
        if (_entry.inst != noone && !instance_exists(_entry.inst))
        {
            if (!csq_struct_get(_entry, "deact_logged", false))
            {
                _entry.deact_logged = true;
                csq_log_debug("squad: '" + _entry.name +
                              "' is deactivated (outside the culling region)");
            }
        }
        else
        {
            _entry.deact_logged = false;
        }
    }

    csq_squad_reassign_slots();
}


/// @func   csq_squad_recover_deactivated()
/// @desc   Bring back companions the game has culled. Without this a companion
///         that fell outside the 960x540 activation box would stay frozen for the
///         rest of the raid, occupying a roster slot and never catching up --
///         because a deactivated instance does not run its own Step event, so the
///         mod's follow and teleport logic cannot help it from the inside.
/// @return {Real} how many were recovered
function csq_squad_recover_deactivated()
{
    if (!csq_cfg("recover_deactivated")) return 0;
    if (!csq_in_raid())                  return 0;

    csq_squad_init();

    var _player = csq_player();
    if (_player == noone)                    return 0;
    if (!csq_player_in_world(_player))       return 0;

    var _n = 0;

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _entry = global.csq_squad[_i];

        if (csq_struct_get(_entry, "dead", false)) continue;
        if (_entry.inst == noone)                  continue;
        if (instance_exists(_entry.inst))          continue;   // already active

        try
        {
            // Reactivate a single instance, the same call vanilla's own
            // game_unpause uses to bring specific objects back.
            instance_activate_object(_entry.inst);

            if (!instance_exists(_entry.inst))
            {
                // Not deactivated after all -- the id is simply stale.
                _entry.inst = noone;
                continue;
            }

            // Move it back inside the activation box, or Alarm_4 will deactivate
            // it again within 20 frames and nothing will have been achieved.
            var _sep = max(0, csq_cfg("spawn_offset"));
            var _pos = csq_find_free_pos(_player.x, _player.y,
                                         max(16, _sep * 3), 60, _sep);

            _entry.inst.x = _pos.x;
            _entry.inst.y = _pos.y;
            _entry.deact_logged = false;

            _n++;
            csq_log_info("squad: recovered '" + _entry.name +
                         "' from deactivation, moved to " +
                         string(floor(_pos.x)) + "," + string(floor(_pos.y)));
        }
        catch (_err)
        {
            csq_log_exception("csq_squad_recover_deactivated", _err);
            _entry.inst = noone;
        }
    }

    return _n;
}


/// @func   csq_squad_notify_cleanup(_inst)
/// @desc   Called from the companion's CleanUp event. This is the mod's ONLY
///         authority on a companion dying, because it is the only signal that
///         genuinely distinguishes destruction from GameMaker's instance
///         deactivation -- CleanUp fires for the former and not the latter.
///
///         TELLING DEATH FROM A ROOM CHANGE
///         obj_npc_parent_Step_0 forces hp = -100 (line 3795-3797) well before it
///         reaches instance_destroy() (line 3856), so by CleanUp time a dead NPC
///         always has hp <= 0. A room ending destroys instances without running
///         another step, so hp is still whatever it was -- positive. That makes
///         hp the discriminator, and it is why this sets .dead rather than
///         leaving the decision to a caller that can no longer see the instance.
function csq_squad_notify_cleanup(_inst)
{
    try
    {
        if (!variable_global_exists("csq_squad") || !is_array(global.csq_squad)) return false;

        var _index = csq_squad_find_by_inst(_inst);
        if (_index < 0) return false;

        var _entry = global.csq_squad[_index];

        var _hp = 0;
        try
        {
            if (variable_instance_exists(_inst, "hp")) _hp = _inst.hp;
        }
        catch (_ignored) {}

        if (_hp > 0)
        {
            // Room change or an explicit despawn: keep the carried damage.
            _entry.hp = _hp;
            csq_log_debug("squad: '" + _entry.name + "' cleaned up (hp " + string(_hp) + ", not a death)");
        }
        else
        {
            _entry.dead = true;
            csq_log_debug("squad: '" + _entry.name + "' cleaned up dead (hp " + string(_hp) + ")");
        }

        _entry.inst         = noone;
        _entry.deact_logged = false;

        return true;
    }
    catch (_err)
    {
        // CleanUp can run during shutdown, when globals may already be gone.
        // Failing quietly is correct here; there is nothing left to protect.
        return false;
    }
}


/// @func   csq_squad_nearest_index()
/// @desc   Roster index of the live companion closest to the player, or -1.
function csq_squad_nearest_index()
{
    csq_squad_init();

    var _player = csq_player();
    if (_player == noone) return -1;

    var _best      = -1;
    var _best_dist = 1000000;

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _entry = global.csq_squad[_i];
        if (!csq_alive(_entry.inst)) continue;

        var _d = point_distance(_player.x, _player.y, _entry.inst.x, _entry.inst.y);
        if (_d < _best_dist)
        {
            _best_dist = _d;
            _best      = _i;
        }
    }

    // Nothing spawned: fall back to the last roster entry so dismissing still
    // works from the hub.
    if (_best == -1 && array_length(global.csq_squad) > 0)
    {
        _best = array_length(global.csq_squad) - 1;
    }

    return _best;
}


/// @func   csq_squad_toggle_hold()
/// @desc   Flip the whole squad between following and holding position.
function csq_squad_toggle_hold()
{
    csq_squad_init();

    global.csq_squad_hold = !global.csq_squad_hold;
    csq_log_info("squad: hold " + (global.csq_squad_hold ? "ON (holding position)" : "OFF (following)"));

    return global.csq_squad_hold;
}


/// @func   csq_squad_dump()
/// @desc   Write the full roster to the log. Bound to a debug key.
function csq_squad_dump()
{
    csq_squad_init();

    csq_log_info("---- squad dump: " + string(csq_squad_count()) + " entr(ies), " +
                 string(csq_squad_active_count()) + " live, hold=" +
                 string(global.csq_squad_hold) + " ----");

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _e    = global.csq_squad[_i];
        var _live = csq_alive(_e.inst);

        var _line = "  [" + string(_i) + "] " + _e.name + " (" + _e.preset + ")" +
                    " inst=" + string(_e.inst) + " live=" + string(_live);

        if (_live)
        {
            _line += " hp=" + string(_e.inst.hp) +
                     " pos=" + string(floor(_e.inst.x)) + "," + string(floor(_e.inst.y)) +
                     " mode=" + string(_e.inst.csq_mode) +
                     " state=" + string(_e.inst.state) +
                     " target=" + string(_e.inst.target);
        }
        else
        {
            _line += " carried_hp=" + string(_e.hp);
        }

        csq_log_info(_line);
    }

    csq_log_info("---- end squad dump ----");
}
