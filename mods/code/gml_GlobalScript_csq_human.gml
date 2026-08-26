// =============================================================================
//  Zone Companions  -  csq_human
// -----------------------------------------------------------------------------
//  Per-companion identity: the small set of numbers that make one companion not
//  quite the same as the one standing next to it.
//
//  THE PROBLEM THIS SOLVES
//  Four companions run identical code, on the same frame, against the same
//  configuration. Vanilla's own NPC brain re-decides every human_tick_max frames
//  (obj_npc_parent_Step_0:678, human_tick_max_ref = 7 plus irandom_range(-1, 1)),
//  and every companion inherits the same 7. So a squad takes its decisions in
//  lockstep, arrives at the same conclusion at the same instant, and moves like one
//  rigid body with four sprites. Nothing about the individual behaviours is wrong;
//  the synchronisation is what reads as mechanical.
//
//  WHAT LIVES HERE
//  Five instance variables, all written exactly once, at spawn:
//      csq_seed          the companion's identity number; everything else derives
//                        from it, so behaviour is reproducible
//      csq_phase         0..desync_tick_jitter-1, added to human_tick_max_ref so
//                        each companion thinks on its own cadence
//      csq_react_frames  extra frames this companion holds a committed move
//      csq_follow_bias   +/- pixels on its formation distance
//      csq_temperament   0..99, a fixed disposition read by the push and voice code
//
//  WHY DERIVED RATHER THAN RANDOM
//  irandom() would work and would be one line shorter, but it makes a bug
//  unreproducible: "slot 2 keeps walking into the fire" cannot be investigated if
//  slot 2 is different every time the raid loads. With desync_seed_from_slot on,
//  slot 2 is the same companion every raid, and turning the setting off restores
//  per-spawn randomness for anyone who prefers it.
//
//  WHY THE SEED CANNOT COME FROM csq_slot
//  csq_slot is assigned by csq_squad_spawn_entry AFTER instance_create_depth
//  returns (csq_squad:322), and this file runs inside the Create event, before that
//  line executes -- so csq_slot is still its initial 0 for every companion. The
//  slot is therefore handed over in global.csq_pending_slot, exactly as the preset,
//  name and hp multiplier already are, and for exactly the same reason:
//  instance_create_depth cannot pass arguments.
//
//  WHY THE SEED IS NOT REFRESHED WHEN THE SLOT CHANGES
//  csq_squad compacts the roster when a companion dies (csq_squad:449), so slots
//  shift under the survivors. Re-deriving here would silently swap two companions'
//  personalities mid-raid. The seed is spawn-time identity and is never rewritten.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_human_mix(_seed, _salt)
/// @desc   A tiny reproducible integer hash.
///
///         Not cryptography, and it does not need to be. The only requirement is
///         that two quantities derived from the same seed do not move together --
///         seed+1 must not mean "one more of everything" -- because otherwise
///         slot 0 would be the timid, close-following, quiet companion on every
///         axis at once and the squad would be sorted rather than varied.
///
///         Multiplying by a large odd constant and folding back into 31 bits is
///         enough for that. Every value stays well inside the 2^53 a GML real
///         represents exactly, so the result is identical on every machine.
/// @param  {Real} _seed  the companion's csq_seed
/// @param  {Real} _salt  which derived quantity is being asked for
/// @return {Real} a non-negative integer
function csq_human_mix(_seed, _salt)
{
    var _v = (abs(floor(_seed)) + 1) * (2654435761 + _salt * 40503);
    return abs(floor(_v mod 2147483647));
}


/// @func   csq_human_seed()
/// @desc   This instance's identity number, or 0 if it has not been initialised.
///         Read rather than recomputed, so it cannot drift.
/// @return {Real}
function csq_human_seed()
{
    if (!variable_instance_exists(id, "csq_seed")) return 0;
    if (!is_real(csq_seed))                        return 0;
    return csq_seed;
}


/// @func   csq_human_phase()
/// @desc   How many frames longer than vanilla's 7 this companion waits between
///         decisions. Added to human_tick_max_ref once, at spawn.
///
///         CAPPED AT 3 ON PURPOSE
///         obj_npc_parent_Step_0:678 rebuilds human_tick_max as
///             human_tick_max_ref + irandom_range(-1, 1)
///         so vanilla already runs at 6..8 frames. Pushing the reference to 10 is
///         a 43% longer reaction loop, which stops reading as personality and
///         starts reading as lag. desync_tick_jitter's own comment says the same;
///         this clamp is what makes the comment true.
/// @return {Real} 0..2
function csq_human_phase()
{
    if (!csq_cfg("desync_enabled")) return 0;

    var _j = floor(clamp(csq_cfg("desync_tick_jitter"), 0, 3));
    if (_j <= 0) return 0;

    return csq_human_mix(csq_human_seed(), 0) mod _j;
}


/// @func   csq_human_temperament()
/// @desc   This companion's fixed disposition, 0 (cautious) to 99 (aggressive).
///
///         Read by the push code to nudge how eagerly it closes, and by the voice
///         code to nudge how often it speaks. It is deliberately a single scalar
///         rather than a struct of traits: one number that several behaviours read
///         differently produces companions who feel coherent, whereas independent
///         traits produce companions who feel randomised.
///
///         Returns a flat 50 when temperament_enabled is off, so every caller can
///         use the value unconditionally and "off" means "everyone is average"
///         rather than "everyone is 0".
/// @return {Real} 0..99
function csq_human_temperament()
{
    if (!csq_cfg("desync_enabled"))     return 50;
    if (!csq_cfg("temperament_enabled")) return 50;

    return csq_human_mix(csq_human_seed(), 3) mod 100;
}


/// @func   csq_human_init_instance()
/// @desc   Give this companion its identity. Called once, from
///         csq_ai_init_instance, which runs inside obj_csq_companion's Create event
///         after npc_setup has finished -- so human_tick_max_ref is already the
///         vanilla 7 by the time it is adjusted here.
///
///         Every variable is written before the first csq_cfg call, so a
///         configuration failure leaves a companion with neutral values rather
///         than with no variables at all: the behaviour modules read these every
///         frame and an undefined read is a crash, not a fallback.
function csq_human_init_instance()
{
    // Neutral defaults first. These are exactly what desync_enabled = false
    // produces, which is what makes the regression gate meaningful.
    csq_seed         = 0;
    csq_phase        = 0;
    csq_react_frames = 0;
    csq_follow_bias  = 0;
    csq_temperament  = 50;

    try
    {
        // The slot arrives in a global because csq_slot is not set until after
        // instance_create_depth returns. See the file header.
        var _slot = 0;
        if (variable_global_exists("csq_pending_slot") && is_real(global.csq_pending_slot))
        {
            _slot = max(0, floor(global.csq_pending_slot));
        }

        csq_seed = csq_cfg("desync_seed_from_slot") ? (_slot + 1) : irandom(100000);

        if (!csq_cfg("desync_enabled"))
        {
            csq_log_debug("human: slot " + string(_slot) + " de-sync off, neutral identity");
            return;
        }

        csq_phase = csq_human_phase();

        // A companion that has just committed to a move holds it a few frames
        // longer than its neighbour. This is decision latency, never trigger
        // latency: nothing here touches riflessi, riflessi_max or rate of fire, and
        // the preset already carries 34-53 frames of reaction delay of its own
        // (hunter_skilled reflexes_*, resolved in scr_enemy_shoot:11).
        var _rj = max(0, floor(csq_cfg("desync_reaction_jitter_frames")));
        csq_react_frames = (_rj <= 0) ? 0 : (csq_human_mix(csq_seed, 1) mod (_rj + 1));

        // Personal formation radius, so four companions do not sit on one circle.
        var _fj = max(0, floor(csq_cfg("desync_follow_distance_jitter")));
        csq_follow_bias = (_fj <= 0) ? 0
                        : ((csq_human_mix(csq_seed, 2) mod (_fj * 2 + 1)) - _fj);

        csq_temperament = csq_human_temperament();

        // The one vanilla variable this file writes. human_tick_max_ref is the NPC's
        // own decision interval reference (obj_npc_parent_Create_0:253, value 7);
        // vanilla re-derives human_tick_max from it every cycle, so a one-off
        // adjustment here de-synchronises the squad permanently rather than for a
        // single tick. It is per-instance, so no other NPC in the game is affected.
        if (variable_instance_exists(id, "human_tick_max_ref") &&
            is_real(human_tick_max_ref))
        {
            human_tick_max_ref += csq_phase;
        }

        csq_log_debug("human: slot " + string(_slot) +
                      " seed "  + string(csq_seed) +
                      " phase " + string(csq_phase) +
                      " react " + string(csq_react_frames) +
                      " bias "  + string(csq_follow_bias) +
                      " temperament " + string(csq_temperament));
    }
    catch (_err)
    {
        csq_log_exception("csq_human_init_instance", _err);
    }
}
