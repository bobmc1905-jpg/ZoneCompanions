// =============================================================================
//  Zone Companions  -  csq_ff
// -----------------------------------------------------------------------------
//  Friendly fire. Keeps companion rounds out of the player, player rounds out of
//  companions, and grenades out of the fight entirely.
//
//  WHY THIS BLOCKS AT THE COLLISION STAGE, NOT THE DAMAGE STAGE
//  The obvious alternative was to zero the damage in player_damage. That is worse
//  in two ways. A bullet that "hits" for zero is still consumed on impact, so a
//  companion firing past the player would have its round eaten by the player's
//  hitbox instead of reaching the enemy behind. And player_damage is called from
//  nine unrelated places (anomalies, emissions, mutant collisions, grenades, a
//  quest explosion), so a guard there would have to distinguish bullets from
//  everything else after the fact.
//
//  Vanilla already has exactly the right hook: two small boolean predicates that
//  decide whether a bullet is allowed to collide at all.
//
//      bullet_can_collide_with_player(bullet, player)
//      bullet_can_collide_with_npc(bullet, npc)
//
//  Returning false there means the round passes straight through and carries on
//  to whatever is behind. That is both cheaper and better behaviour.
//
//  WHY EVERY PREDICATE HERE FAILS OPEN
//  These run once per bullet per frame, inside the game's own combat path. If one
//  of them ever throws, the correct answer is "do not block" -- because blocking
//  by accident would make the player invulnerable to something, or make an enemy
//  unkillable. So each returns false on any error, which restores exactly stock
//  behaviour. A mod bug must not be able to break vanilla combat.
//
//  WHY THE ORDER OF CHECKS MATTERS
//  Both predicates test the cheap discriminating integer first -- "is this even
//  about a companion?" -- before reading config or touching instances. In a
//  firefight the overwhelming majority of bullets have nothing to do with the
//  squad, and those exit on a single object_index comparison.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_ff_is_companion(_inst)
/// @desc   Whether _inst is a live companion. object_index is compared rather
///         than faction, so this keeps working regardless of what the faction
///         config is set to.
///
///         obj_csq_companion is safe to name directly: GMLoader's
///         3_NewObjectManipulation step creates it before 5_ImportGML compiles
///         this file, so the identifier resolves at compile time.
function csq_ff_is_companion(_inst)
{
    if (_inst == noone || _inst == -4)  return false;
    if (!instance_exists(_inst))        return false;

    return (_inst.object_index == obj_csq_companion);
}


/// @func   csq_ff_bullet_shooter(_bullet)
/// @desc   The instance that fired _bullet, or noone.
///
///         obj_bullet_parent_Create_0 line 7 initialises shooter_id = -4, and
///         every firing site sets it together with shooter_faction:
///             bull.shooter_faction = faction;
///             bull.shooter_id      = id;
///         (scr_shoot lines 112-113, 137-138, 199-200 and obj_npc_parent_Step_0
///         lines 3434-3435, 3478-3479, 3602-3603). So an unset shooter is -4,
///         and anything else is a real instance id that may since have died.
function csq_ff_bullet_shooter(_bullet)
{
    if (!variable_instance_exists(_bullet, "shooter_id")) return noone;

    var _s = _bullet.shooter_id;

    if (_s == -4 || _s == noone)  return noone;
    if (!instance_exists(_s))     return noone;

    return _s;
}


/// @func   csq_ff_block_bullet_on_player(_bullet, _player)
/// @desc   Should this bullet be stopped from hitting the player?
///         Injected into bullet_can_collide_with_player immediately after its
///         own instance_exists(arg1) guard, so _player is known to exist.
/// @return {Bool} true to block the collision
function csq_ff_block_bullet_on_player(_bullet, _player)
{
    try
    {
        // Cheapest discriminating test first: almost every bullet in a firefight
        // was fired by something that is not a companion.
        var _shooter = csq_ff_bullet_shooter(_bullet);
        if (!csq_ff_is_companion(_shooter)) return false;

        return csq_cfg("ff_protect_player");
    }
    catch (_err)
    {
        // Fail open -- see the header. Deliberately not logged: this runs per
        // bullet per frame, and csq_log opens the log file on every call, so a
        // recurring failure here would be a per-frame file write.
        return false;
    }
}


/// @func   csq_ff_block_bullet_on_companion(_bullet, _npc)
/// @desc   Should this bullet be stopped from hitting a companion?
///         Injected into bullet_can_collide_with_npc immediately after its own
///         instance_exists(arg1) guard, so _npc is known to exist.
///
///         COMPANION-ON-COMPANION IS ALREADY HANDLED BY VANILLA
///         bullet_can_collide_with_npc only returns true when
///             arg0.shooter_faction != arg1.faction
///         and all companions share one faction, so a companion's round already
///         cannot hit another companion. It is still checked here so the
///         protection does not quietly depend on that -- if the faction setup
///         ever changes, this keeps holding.
/// @return {Bool} true to block the collision
function csq_ff_block_bullet_on_companion(_bullet, _npc)
{
    try
    {
        // Most NPCs shot at are not companions; this exits on one comparison.
        if (_npc.object_index != obj_csq_companion) return false;

        if (!csq_cfg("ff_protect_companions")) return false;

        var _shooter = csq_ff_bullet_shooter(_bullet);
        if (_shooter == noone) return false;

        // Another companion (belt and braces, see above).
        if (csq_ff_is_companion(_shooter)) return true;

        // The player. The faction string is the discriminator rather than the
        // object, because "Player" is a literal the game itself compares against
        // (obj_grenade_parent_Step_0 line 210) and it covers every player object
        // without this file having to know which one is in use.
        if (variable_instance_exists(_bullet, "shooter_faction"))
        {
            if (_bullet.shooter_faction == "Player") return true;
        }

        return false;
    }
    catch (_err)
    {
        return false;   // fail open
    }
}


/// @func   csq_ff_disarm_grenades()
/// @desc   Stop this companion ever throwing a grenade. Runs in the companion's
///         Create event with `self` bound to the companion, after npc_setup.
///
///         WHY THIS IS NEEDED AT ALL
///         Grenades bypass both bullet predicates above -- they are not bullets.
///         obj_grenade_parent_Step_0 lines 226-244 damage the player with no
///         faction check whatsoever; the only exemption is
///             if (thrown_by_player && skill_hunter_obtained("grenadeexpert"))
///         and thrown_by_player is initialised false (obj_grenade_parent_Create_0
///         line 31) and set true in exactly one place, class_player_arms line 213,
///         when the *player* throws. A companion's grenade therefore always
///         damages the player at full value.
///
///         Vanilla's own _same_faction_throw_grenade check does not help: it
///         protects NPCs of the thrower's faction, and the player is not the
///         companion's faction.
///
///         loner_regular is not a bluffer about this. Its npc.json entry carries
///         grenade_amount "{human_low}", prob_grenade_rgd 1 and
///         prob_grenade_flash 1 -- live fragmentation grenades and flashbangs.
///
///         WHY NO VANILLA PATCH IS REQUIRED
///         npc_setup line 19 sets grenade_amount_max as an *instance* variable:
///             grenade_amount_max = npc_get_grenade_amount(npc_id);
///         and obj_npc_parent_Step_0 line 1326 gates the entire grenade branch on
///             if (grenade_amount_thrown < grenade_amount_max)
///         Setting the maximum to 0 makes that 0 < 0, which is false forever, so
///         the branch is never entered for any grenade type. One assignment
///         replaces what would otherwise be a patch to a 3978-line event.
/// @return {Bool} whether grenades were disarmed
function csq_ff_disarm_grenades()
{
    try
    {
        if (!csq_cfg("ff_no_grenades")) return false;

        grenade_amount_max = 0;
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_ff_disarm_grenades", _err);
        return false;
    }
}
