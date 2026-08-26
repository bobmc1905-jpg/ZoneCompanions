// =============================================================================
//  Zone Companions  -  csq_voice
// -----------------------------------------------------------------------------
//  Idle chatter, and the squad-wide brake that stops four companions talking over
//  each other.
//
//  WHAT ALREADY WORKS AND IS LEFT ALONE
//  Combat barks are vanilla and companions already inherit them: the selector's
//  entry switch fires text 1 on action 12 at 50% (Step_0:1539), text 10 on action 13
//  at 80% (:1552) and text 16 on action 30 at 50% (:1560). None of that is touched
//  or duplicated. This module adds the one category vanilla has no equivalent for --
//  a companion saying something when nothing is happening -- and lends its squad
//  cooldown to the push callout in csq_combat.
//
//  WHY NEW IDS ARE NEEDED AT ALL
//  lista_npc_text registers 295 ids in 0..321 and the only believable ambient lines
//  in the whole catalogue are 3 and 22, both of which are greetings aimed at the
//  player ("hey hunter", "good luck hunter"). A companion walking beside you for an
//  hour cannot only ever greet you. So this registers its own.
//
//  THE REGISTRATION CONTRACT
//  scr_draw_npc_text performs NO bounds check -- it indexes five global arrays
//  directly -- and obj_npc_draw_text's two alarms index four more. For a new id every
//  one of the nine has to be written:
//      t_npc_text[n][i]         Alarm_1, via array_length_2d. Fatal if missing.
//      t_npc_text_speed[n]      scr_draw_npc_text. Fatal.
//      t_npc_text_timer[n]      scr_draw_npc_text. Fatal.
//      t_npc_suppress_prompts[n] scr_draw_npc_text. Fatal.
//      t_npc_draw_offset_y[n]   scr_draw_npc_text. Fatal.
//      t_npc_needs_sight[n]     Step_0, every frame. Bark visible through walls.
//      t_npc_text_next[n]       Alarm_0. MUST be literally false -- the alarm tests
//                               `!= false`, and in GML `undefined != false` is true,
//                               so a missing entry makes a bark that times out call
//                               scr_draw_npc_text(undefined, undefined) and crash.
//      t_npc_text_next_id[n]    Alarm_0, alongside the above.
//      t_npc_id[n]              not read by this path; set for consistency.
//
//  REGISTERED ON EVERY MAP LOAD, NOT AT BOOT
//  lista_npc_text() re-creates five of those nine arrays from scratch with
//  array_create(324, ...) every time obj_controller is created, which throws away
//  anything written before it. So registration hangs off csq_on_map_load, after
//  vanilla has had its turn.
//
//  AND UNCONDITIONALLY, EVEN WITH CALLOUTS TURNED OFF
//  The alternative is a crash: a player who enables idle_callouts_enabled in the ini
//  mid-session would otherwise have companions ask for ids that were never written.
//  Five unused entries in a global array are invisible; an unbounded array read is
//  not. Only speaking is gated by the switch.
//
//  CONTENT IS PLAIN ENGLISH, ON PURPOSE
//  language_get_string returns its argument verbatim when the key is unknown
//  (scr_languages:344-350), so a literal sentence renders as itself and a loc-key
//  build is available later at no cost. Full sentences only -- the same function also
//  probes global.language_alias with case variants, and that map holds short UI
//  labels like "New Game" and "Skilled" which a one-word line could collide with.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_voice_lines()
/// @desc   The catalogue this mod registers. One entry per id, each a list of
///         variants that Alarm_1 shuffles between, so the same id said twice is
///         rarely the same sentence.
///
///         Deliberately unremarkable. These are people walking a long way with
///         someone they work for, not characters with arcs.
/// @return {Array<Array<String>>}
function csq_voice_lines()
{
    return [
        [
            "Quiet out here.",
            "I do not like it this quiet.",
            "Keep your eyes open.",
            "Something out there is watching us. I can feel it."
        ],
        [
            "Rain is coming. I can smell it.",
            "Air tastes like metal today.",
            "Fog is rolling in again.",
            "Sun goes down early this time of year."
        ],
        [
            "I am getting low on ammunition.",
            "These boots are finished after this run.",
            "I could use a smoke and somewhere to sit.",
            "Water ran out an hour ago."
        ],
        [
            "Where are we heading, hunter?",
            "Lead on. I am right behind you.",
            "You know these woods better than I do.",
            "Say the word and I will go first."
        ],
        [
            "My brother went into the zone for money. He came out as a story.",
            "Do not step anywhere I have not stepped.",
            "If I stop moving, do not wait for me.",
            "Everyone out here is somebody who thought it would be quick."
        ]
    ];
}


/// @func   csq_voice_id_base()
/// @desc   Where this mod's ids start. Vanilla's highest is 321 and its arrays are
///         allocated to 323, so 800 is clear of both today and of a future patch
///         filling the holes at 116, 155, 186, 250, 263-279, 285-289, 322 and 323.
///         GML arrays grow on write, so an index past the allocation is fine provided
///         all nine arrays get it -- which is the whole point of csq_voice_register.
/// @return {Real}
function csq_voice_id_base()
{
    return max(0, floor(csq_cfg("callout_id_base")));
}


/// @func   csq_voice_register()
/// @desc   Write this mod's lines into vanilla's text tables. Called from
///         csq_on_map_load, after lista_npc_text has rebuilt them.
/// @return {Real} how many ids were registered
function csq_voice_register()
{
    // lista_npc_text has not run yet -- nothing to append to, and creating the arrays
    // here would only have them thrown away when it does.
    if (!variable_global_exists("t_npc_text")) return 0;

    try
    {
        var _lines = csq_voice_lines();
        var _base  = csq_voice_id_base();
        var _sight = csq_cfg("callout_needs_sight");
        var _timer = max(1, floor(csq_cfg("callout_text_timer")));

        for (var _i = 0; _i < array_length(_lines); _i++)
        {
            var _id       = _base + _i;
            var _variants = _lines[_i];

            for (var _v = 0; _v < array_length(_variants); _v++)
            {
                global.t_npc_text[_id][_v] = _variants[_v];
            }

            global.t_npc_id[_id] = _id;

            // false, not 0 and not undefined. See the contract in the file header.
            global.t_npc_text_next[_id]    = false;
            global.t_npc_text_next_id[_id] = noone;

            global.t_npc_needs_sight[_id]      = _sight;
            global.t_npc_text_speed[_id]       = 0.5;
            global.t_npc_text_timer[_id]       = _timer;
            global.t_npc_suppress_prompts[_id] = true;
            global.t_npc_draw_offset_y[_id]    = -24;
        }

        csq_log_debug("voice: registered " + string(array_length(_lines)) +
                      " callout id(s) from " + string(_base));

        return array_length(_lines);
    }
    catch (_err)
    {
        csq_log_exception("csq_voice_register", _err);
        return 0;
    }
}


// -----------------------------------------------------------------------------
//  THE SQUAD BRAKE
//
//  scr_draw_npc_text destroys any existing obj_npc_draw_text whose id_npc matches,
//  so one companion can never talk over itself. Four of them talking over each
//  other is the actual problem, and it is not a problem vanilla has ever had to
//  solve: a loner is alone. So the brake is one global timestamp that every callout
//  in the mod -- idle chatter here, the push callout in csq_combat -- has to pass.
//
//  Measured in current_time (milliseconds since the process started) rather than
//  frames, because it is shared and nothing owns it. A frame counter would need
//  somewhere to be decremented, and no single instance is guaranteed to exist for
//  the whole raid.
// -----------------------------------------------------------------------------

/// @func   csq_voice_can_speak()
/// @desc   Whether the squad's shared cooldown has expired. Cheap, and safe to call
///         before rolling a chance.
/// @return {Bool}
function csq_voice_can_speak()
{
    if (!variable_global_exists("csq_last_callout_time")) return true;

    var _gap = max(0, csq_cfg("callout_squad_cooldown_seconds")) * 1000;

    return ((current_time - global.csq_last_callout_time) >= _gap);
}


/// @func   csq_voice_mark_spoken()
/// @desc   Start the shared cooldown. Called by every path that actually says
///         something, including the push callout in csq_combat.
function csq_voice_mark_spoken()
{
    global.csq_last_callout_time = current_time;
}


/// @func   csq_voice_init_instance()
/// @desc   Per-companion scheduling state, set up from csq_ai_init_instance.
///
///         csq_voice_calm counts frames since this companion last had anything to
///         shoot at. It is a frame counter and not a timestamp because it belongs to
///         one instance and is reset by that instance's own step.
function csq_voice_init_instance()
{
    csq_voice_calm  = 0;
    csq_voice_timer = 0;

    // A full wait, not zero, so a squad that has just spawned does not all speak on
    // the same frame it lands.
    csq_voice_reschedule();
}


/// @func   csq_voice_reschedule()
/// @desc   Roll the next wait. Temperament shortens it: the same trait that makes a
///         companion close distance faster makes it the one who fills a silence.
/// @return {Real} the wait, in frames
function csq_voice_reschedule()
{
    var _min = max(1, floor(csq_cfg("idle_callout_min_seconds")));
    var _max = max(_min, floor(csq_cfg("idle_callout_max_seconds")));

    var _wait = irandom_range(_min, _max) * csq_combat_temper_scale(-0.25);

    csq_voice_timer = csq_seconds_to_frames(max(1, _wait));

    return csq_voice_timer;
}


/// @func   csq_voice_say_idle()
/// @desc   Pick one of this mod's ids and say it. Which id is uniform -- the five
///         are peers, not a priority order.
/// @return {Bool} whether anything was said
function csq_voice_say_idle()
{
    var _count = array_length(csq_voice_lines());
    if (_count <= 0) return false;

    var _id = csq_voice_id_base() + irandom(_count - 1);

    // Wrapped, like every other scr_draw_npc_text call in the mod: the id is
    // registered by csq_voice_register, and if that ever failed this must not take
    // the frame with it.
    try
    {
        scr_draw_npc_text(id, _id);
    }
    catch (_err)
    {
        csq_log_exception("csq_voice_say_idle", _err);
        return false;
    }

    csq_voice_mark_spoken();

    csq_log_debug("voice: " + csq_ai_display_name() + " said " + string(_id) +
                  " after " + string(csq_voice_calm) + "f calm");

    return true;
}


/// @func   csq_voice_step()
/// @desc   Called LAST from csq_ai_step, so it reacts to what the frame actually
///         decided rather than to what it was about to decide. It writes no vanilla
///         variable and never touches state, path or mode -- the worst it can do is
///         put a speech bubble over a companion's head.
///
///         FOUR CONDITIONS, AND WHY THE CLOCK IS ONLY ONE OF THEM
///         The timer says when a companion is *willing* to speak. The other three --
///         not engaged, calm for long enough, player close enough -- say whether now
///         is a moment worth speaking into. So an expired timer is held expired
///         instead of being re-rolled: a companion that has been silent through two
///         minutes of shooting should say something when the shooting stops, not
///         start counting again from there.
/// @return {Bool} whether it spoke this frame
function csq_voice_step()
{
    try
    {
        // With the switch off this writes nothing whatsoever, not even its own
        // scheduling state -- see the regression gate in the dev prompt.
        if (!csq_cfg("idle_callouts_enabled")) return false;

        // Self-healing, so enabling callouts mid-raid works on companions that were
        // spawned while the feature was off.
        if (!variable_instance_exists(id, "csq_voice_timer")) csq_voice_init_instance();

        var _busy = (csq_mode == csq_ai_mode_engage()) || csq_ai_hostile_target_exists();

        if (_busy) csq_voice_calm = 0;
        else       csq_voice_calm++;

        if (csq_voice_timer > 0)
        {
            csq_voice_timer--;
            return false;
        }

        if (_busy) return false;

        var _calm = csq_seconds_to_frames(max(0, csq_cfg("idle_callout_needs_calm_seconds")));
        if (csq_voice_calm < _calm) return false;

        // Nobody to say it to. Companions are raid-only, so the player being absent
        // means the raid is ending, not that this is the hub.
        var _player = csq_player();
        if (_player == noone) return false;

        var _radius = max(0, csq_cfg("idle_callout_radius"));
        if (point_distance(x, y, _player.x, _player.y) > _radius) return false;

        if (!csq_voice_can_speak()) return false;
        if (!csq_voice_say_idle())  return false;

        csq_voice_reschedule();

        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_voice_step", _err);
        return false;
    }
}
