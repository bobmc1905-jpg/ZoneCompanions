// =============================================================================
//  Zone Companions  -  csq_care
// -----------------------------------------------------------------------------
//  A wounded companion patching itself up. First aid only: no looting, no
//  containers, no corpses, and nothing is ever taken from the player's inventory.
//
//  WHY THIS HAS TO BE MOD CODE
//  NPCs in this game have no bleed state and no self-heal. There is no vanilla
//  behaviour to trigger, gate or borrow -- obj_npc_parent's health only ever goes
//  down. The one precedent is this mod's own medic behaviour, whose player-facing
//  line is
//      scr_draw_text_with_box(_name + " patched you up", false);
//  and self-care is the inward-facing twin of it.
//
//  THE MACHINE
//      idle      -> nothing. Watches hp against selfcare_hp_threshold.
//      breaking  -> walk back toward the player first, using the follow driver.
//      binding   -> stand still, weapon down, for selfcare_bind_seconds.
//      healing   -> one frame: restore hp, spend a bandage, start the cooldown.
//  Held in csq_care_state and driven from csq_ai_step BEFORE the mode dispatch,
//  because a companion binding a wound must not simultaneously be pushing. While
//  the machine is past idle, csq_care_step returns true and csq_ai_step hands the
//  whole frame over -- no engage, no follow, no combat footwork.
//
//  IT ADDS NO MODE
//  csq_mode is left exactly as the last frame left it, and restored to the matching
//  vanilla state on every exit path. That matters because csq_ai_set_mode returns
//  early when the mode has not changed: if this module dropped state to
//  "human_no_move" and walked away, nothing downstream would ever put it back and
//  the companion would stand in a firefight doing nothing at all.
//
//  WHAT IT TOUCHES
//  hp, clamped to csq_hp_max and never above it. draw_weapon, which is purely
//  cosmetic -- obj_npc_weapon_Draw_0:5 is the only thing in the game that reads it.
//  state, through the accessors. path_timer on abort, for the reason spelled out in
//  csq_combat_push_abort. Nothing else.
//
//  CHARGES LIVE ON THE ROSTER, NOT ON THE INSTANCE
//  Same reason as the medic charges next to them: a companion instance is destroyed
//  at raid exit and *reported missing* while the game has it deactivated, so an
//  instance variable would silently refill the count every time a companion fell
//  behind and got culled. Refilled at raid start by csq_care_refill_charges, and
//  carried through a mid-raid quit by csq_persist.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_care_state_idle()
/// @desc   The four states of the machine, as functions rather than bare strings so
///         that a typo is a missing-function error at check time instead of a state
///         nothing ever matches at runtime.
function csq_care_state_idle()     { return "idle"; }
function csq_care_state_breaking() { return "breaking"; }
function csq_care_state_binding()  { return "binding"; }
function csq_care_state_healing()  { return "healing"; }


/// @func   csq_care_init_instance()
/// @desc   Per-companion self-care state. Called from csq_ai_init_instance.
function csq_care_init_instance()
{
    // Which state of the machine above this companion is in.
    csq_care_state = csq_care_state_idle();

    // Counts down the bind, and up while breaking contact. One variable for both
    // because the two never overlap and a second one would only ever be stale.
    csq_care_timer = 0;

    // Frames until this companion may bandage again. Ages in every state.
    csq_care_cd = 0;

    // hp at the moment binding started. The interrupt is "hp is lower than it was
    // when I knelt down", which needs a remembered value: there is no vanilla
    // damage flag on an NPC to read, only the number itself.
    csq_care_hp_mark = 0;
}


/// @func   csq_care_charges_max()
/// @desc   Bandages per companion per raid, floored at 0 so a negative value in the
///         ini disables healing rather than making it endless.
function csq_care_charges_max()
{
    return max(0, floor(csq_cfg("selfcare_charges")));
}


/// @func   csq_care_charges_entry(_entry)
/// @desc   Bandages left for a roster entry. Defaults to a full complement, so an
///         entry loaded from a save written before self-care existed starts the raid
///         supplied rather than empty -- the same forgiving direction the medic
///         charges take.
/// @param  {Struct} _entry
/// @return {Real}
function csq_care_charges_entry(_entry)
{
    if (is_undefined(_entry)) return 0;

    return csq_struct_get(_entry, "care_charges", csq_care_charges_max());
}


/// @func   csq_care_charges_get()
/// @desc   Bandages left for this companion instance.
/// @return {Real}
function csq_care_charges_get()
{
    var _index = csq_squad_find_by_inst(id);
    if (_index < 0) return 0;

    return csq_care_charges_entry(global.csq_squad[_index]);
}


/// @func   csq_care_charges_set(_n)
/// @desc   Write this companion's remaining bandages back to the roster.
/// @param  {Real} _n
/// @return {Bool} whether a roster entry was found to write to
function csq_care_charges_set(_n)
{
    var _index = csq_squad_find_by_inst(id);
    if (_index < 0) return false;

    global.csq_squad[_index].care_charges = max(0, floor(_n));
    return true;
}


/// @func   csq_care_refill_charges()
/// @desc   Give every companion its bandages back.
///
///         CALLED AT RAID *START*, NOT RAID EXIT, for the reason written out in full
///         above csq_squad_refill_heal_charges: the exit event does not run if the
///         game crashes or the player dies past the exit screen, and refilling there
///         would leave the squad permanently dry in exactly those cases.
/// @return {Real} how many entries were refilled
function csq_care_refill_charges()
{
    csq_squad_init();

    var _max = csq_care_charges_max();
    var _n   = 0;

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        global.csq_squad[_i].care_charges = _max;
        _n++;
    }

    if (_n > 0)
    {
        csq_log_debug("care: refilled " + string(_n) + " companion(s) to " +
                      string(_max) + " bandage(s)");
    }

    return _n;
}


/// @func   csq_care_restore_state()
/// @desc   Put the vanilla state back to whatever this companion's mode implies.
///
///         Written as an if/else over the two accessors rather than as one ternary
///         so that every assignment to `state` in this mod stays a plain accessor
///         call -- which is the form the repo checker validates.
function csq_care_restore_state()
{
    if (csq_mode == csq_ai_mode_engage())
    {
        state = csq_ai_state_combat();
    }
    else
    {
        state = csq_ai_state_idle();
    }
}


/// @func   csq_care_abort()
/// @desc   Give up on the current attempt and hand the frame back to normal AI. No
///         bandage is spent and no cooldown starts, so a companion interrupted twice
///         will still try a third time.
function csq_care_abort()
{
    if (!variable_instance_exists(id, "csq_care_state")) return;
    if (csq_care_state == csq_care_state_idle()) return;

    csq_care_state = csq_care_state_idle();
    csq_care_timer = 0;

    draw_weapon = true;
    csq_care_restore_state();

    // Force a route rebuild rather than ending the path, for the reason set out in
    // csq_combat_push_abort: whichever vanilla action takes over next calls
    // scr_enemy_path itself, and that call only does anything when its own timer has
    // expired. Ending the path here would freeze the companion until it did.
    try { path_timer = path_timer_reset; } catch (_err) {}
}


/// @func   csq_care_wants_care()
/// @desc   Whether this companion should be trying to bandage itself right now.
///
///         Re-tested on every frame of an attempt, not just its first, so that a
///         companion whose situation changes -- a new contact, a lost roster entry --
///         goes straight back to fighting instead of finishing a heal it should never
///         have started.
/// @return {Bool}
function csq_care_wants_care()
{
    if (!csq_cfg("selfcare_enabled")) return false;
    if (csq_care_cd > 0) return false;
    if (csq_care_charges_get() <= 0) return false;

    // csq_hp_max is computed in csq_ai_init_instance from the same difficulty
    // multiply obj_npc_human_parent_Alarm_9 applies, so the fraction below is
    // meaningful and scales with difficulty. Guarded because dividing by it is not.
    if (csq_hp_max <= 0) return false;
    if ((hp / csq_hp_max) >= csq_cfg("selfcare_hp_threshold")) return false;

    // A live enemy of its own. On by default, and it is what makes selfcare_break_
    // contact mostly invisible: with this on there is rarely anything to break from.
    if (csq_cfg("selfcare_require_no_target") && csq_ai_hostile_target_exists())
    {
        return false;
    }

    // The player's life outranks the companion's own. csq_ai_wants_medic already
    // refuses to leave a fight for a scratch, so a companion holding the medic role
    // here is one on its way to something genuinely urgent.
    if (csq_mode == csq_ai_mode_medic()) return false;

    return true;
}


/// @func   csq_care_enter_breaking()
/// @desc   Start walking back toward the player before going helpless.
function csq_care_enter_breaking()
{
    csq_care_state = csq_care_state_breaking();
    csq_care_timer = 0;

    csq_log_debug("care: slot " + string(csq_slot) + " breaking contact at " +
                  string(floor(hp)) + "/" + string(floor(csq_hp_max)) + " hp");
}


/// @func   csq_care_break_limit()
/// @desc   How long breaking contact may take before the attempt is abandoned.
///
///         DERIVED RATHER THAN CONFIGURED
///         A bound is needed: a companion that cannot reach the player -- blocked
///         geometry, a player who keeps running -- would otherwise walk instead of
///         shooting for the rest of the raid. Rather than invent a key nobody asked
///         for, the bound is three times the bind itself, on the principle that if
///         getting clear costs more than the treatment, the treatment is not worth
///         having.
/// @return {Real} frames
function csq_care_break_limit()
{
    return csq_seconds_to_frames(max(0.1, csq_cfg("selfcare_bind_seconds")) * 3);
}


/// @func   csq_care_do_breaking()
/// @desc   One frame of walking back toward the player.
/// @return {Bool} whether this companion is still held by self-care
function csq_care_do_breaking()
{
    var _player = csq_player();

    if (_player == noone || !csq_care_wants_care())
    {
        csq_care_abort();
        return false;
    }

    csq_care_timer++;

    // Clear enough. Either it is back in formation, or there is nothing left to be
    // clear OF -- which is the condition selfcare_require_no_target guarantees up
    // front, and the reason breaking is usually a single frame.
    var _near = (point_distance(x, y, _player.x, _player.y) <=
                 max(csq_cfg("follow_distance"), csq_cfg("arrive_distance")));

    if (_near || !csq_ai_hostile_target_exists())
    {
        csq_care_enter_binding();
        return true;
    }

    if (csq_care_timer > csq_care_break_limit())
    {
        csq_log_debug("care: slot " + string(csq_slot) +
                      " gave up breaking contact after " + string(csq_care_timer) + "f");
        csq_care_abort();
        return false;
    }

    // The formation driver, unchanged. It already walks to this companion's own slot
    // behind the player, which is the direction "away from the fight" means here.
    csq_ai_drive_follow(_player);
    return true;
}


/// @func   csq_care_enter_binding()
/// @desc   Kneel down. Weapon away, path dropped, and the one vanilla line that fits.
function csq_care_enter_binding()
{
    csq_care_state   = csq_care_state_binding();
    csq_care_timer   = csq_seconds_to_frames(max(0.1, csq_cfg("selfcare_bind_seconds")));
    csq_care_hp_mark = hp;

    state = csq_ai_state_idle();

    try { path_end(); } catch (_err) {}

    draw_weapon = false;

    // Vanilla bark 2 -- the "ahh, I'm hurt" line. Defined by lista_npc_text and,
    // being well under 324, needs no registration of any kind: the mod only has to
    // ask for it. A voice the player has already heard in the zone, used for the one
    // thing it was written for.
    if (csq_cfg("selfcare_callout_enabled"))
    {
        try { scr_draw_npc_text(id, 2); } catch (_err) {}
    }

    csq_log_debug("care: slot " + string(csq_slot) + " binding for " +
                  string(csq_care_timer) + "f at " + string(floor(hp)) + " hp");
}


/// @func   csq_care_do_binding()
/// @desc   One frame of standing still with the weapon down.
/// @return {Bool} whether this companion is still held by self-care
function csq_care_do_binding()
{
    // Took a hit. There is no damage flag on a vanilla NPC to read, so this is the
    // comparison against the remembered value that stands in for one.
    if (csq_cfg("selfcare_interrupt_on_hit") && hp < csq_care_hp_mark)
    {
        csq_log_debug("care: slot " + string(csq_slot) + " interrupted, " +
                      string(floor(csq_care_hp_mark - hp)) + " damage taken while binding");
        csq_care_abort();
        return false;
    }

    if (!csq_care_wants_care())
    {
        csq_care_abort();
        return false;
    }

    // Re-asserted every frame rather than set once at entry. Vanilla's Step runs
    // first -- obj_csq_companion calls event_inherited() before csq_ai_step -- and it
    // is entitled to change state and start a path from underneath us. Holding still
    // means holding still against that, every frame, for the whole bind.
    state = csq_ai_state_idle();
    draw_weapon = false;

    try { path_end(); } catch (_err) {}

    csq_care_timer--;

    if (csq_care_timer <= 0)
    {
        csq_care_state = csq_care_state_healing();
    }

    return true;
}


/// @func   csq_care_do_healing()
/// @desc   The single frame the bandage actually lands on.
///
///         Separate from binding rather than folded into its last frame so that the
///         cost and the payment are not the same event: an interrupt on the final
///         frame of a bind still costs nothing, and the DEBUG log has one line per
///         bandage spent.
/// @return {Bool} always true -- this frame belongs to self-care
function csq_care_do_healing()
{
    var _before = hp;

    // Never above the remembered maximum. csq_ai_step keeps that honest on every
    // frame, so this cannot be used to inflate a companion past what the difficulty
    // setting says it should have.
    hp = min(csq_hp_max, hp + (csq_hp_max * max(0, csq_cfg("selfcare_heal_fraction"))));

    var _left = csq_care_charges_get() - 1;
    csq_care_charges_set(_left);

    csq_care_cd = csq_seconds_to_frames(max(0, csq_cfg("selfcare_cooldown_seconds")));

    draw_weapon = true;
    csq_care_restore_state();

    csq_care_state = csq_care_state_idle();
    csq_care_timer = 0;

    csq_log_info("care: " + csq_ai_display_name() + " patched itself up, " +
                 string(floor(_before)) + " -> " + string(floor(hp)) + " hp, " +
                 string(max(0, _left)) + " bandage(s) left");

    return true;
}


/// @func   csq_care_step()
/// @desc   One frame of self-care. Called from csq_ai_step BEFORE the mode dispatch.
/// @return {Bool} true if self-care has taken the frame, and the caller must not run
///                its own dispatch or combat footwork
function csq_care_step()
{
    try
    {
        // The cooldown ages in every state, fighting included, exactly as csq_heal_cd
        // does: time spent doing something else still counts toward the next bandage.
        if (csq_care_cd > 0) csq_care_cd--;

        // Switched off mid-raid. Anything in flight is dropped without cost.
        if (!csq_cfg("selfcare_enabled"))
        {
            csq_care_abort();
            return false;
        }

        // An if/else chain rather than a switch, so every comparison goes through the
        // accessors. GML does allow expressions as case labels, but a state machine
        // whose transitions use the accessors and whose dispatch uses bare strings is
        // one rename away from a companion stuck in a state nothing matches.
        if (csq_care_state == csq_care_state_breaking()) return csq_care_do_breaking();
        if (csq_care_state == csq_care_state_binding())  return csq_care_do_binding();
        if (csq_care_state == csq_care_state_healing())  return csq_care_do_healing();

        // Idle. The only question left is whether to start.
        if (!csq_care_wants_care()) return false;
        if (csq_player() == noone)  return false;

        // Drop any committed advance before taking the frame. csq_combat_step will not
        // be reached again until self-care finishes, so an in-flight push left set
        // would resume against a goal chosen for a situation that has since passed.
        csq_combat_push_abort();

        // And put down the cigarette. csq_idle_step runs after this function and
        // returns false while care holds the instance, so it will never see the
        // transition itself -- the prop would keep animating over a companion kneeling
        // with a bandage. Safe on an instance that was not animating.
        csq_idle_exit("self-care");

        if (csq_cfg("selfcare_break_contact"))
        {
            csq_care_enter_breaking();
            return true;
        }

        csq_care_enter_binding();
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_care_step", _err);

        // A companion must never be left kneeling because of an error in the code
        // that was meant to stand it back up.
        try { csq_care_abort(); } catch (_err2) {}

        return false;
    }
}
