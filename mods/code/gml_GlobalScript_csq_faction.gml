// =============================================================================
//  Zone Companions  -  csq_faction
// -----------------------------------------------------------------------------
//  Registers a dedicated "Companion" faction so companions are allies of the
//  player and enemies of whoever the player fights.
//
//  This is a supported extension, not a hack: vanilla faction_load() ends with
//  exactly this pattern --
//      faction_create("Horizon");
//      faction_set_rep("Horizon", "Horizon", 1000);
//      faction_set_rep("All Friend", "Horizon", 1000);
//  -- and global.faction_rel is resized from the struct's key count, so extra
//  factions are anticipated by the game's own code.
//
//  THERE ARE TWO REGISTRIES AND COMBAT ONLY READS ONE
//      global.struct_faction       base;  faction_get_rep       (obj_controller)
//      global.struct_faction_temp  live;  faction_get_rep_temp  (everyone else)
//  scr_get_relation picks between them by object_index, and every NPC therefore
//  resolves relations through the *temp* registry. Registering in the base
//  registry alone would leave companions hostile to everything, because
//  faction_get_rep_temp returns 0 -- maximally hostile -- for an unknown
//  faction. So both are written.
//
//  TWO VANILLA GAPS THIS MODULE WORKS AROUND
//  1. faction_create's second loop tests `_names[_r] == arg0`, but `_names` was
//     captured *before* arg0 was inserted, so the condition is never true. The
//     loop is dead code, and the new faction's key is therefore never added to
//     any *other* faction's relationship struct. Left alone, a Loner scanning
//     for targets would evaluate faction_get_rep_temp("Loners", "Companion")
//     and get `undefined`, which then flows into `relation <= r` inside
//     scr_find_target_for_human. faction_set_rep / faction_set_rep_temp write
//     both directions with variable_struct_set, which creates missing keys, so
//     looping over every faction closes the gap.
//  2. faction_load() runs hotfix_convert_factions_to_structs() -- which rebuilds
//     temp from base -- *before* faction_create("Horizon"), so vanilla's own
//     Horizon never reaches the temp registry. For any faction in that state we
//     write only our own side of the relationship. Making Horizon fully live in
//     temp would change vanilla behaviour, which is out of scope for this mod.
//
//  WHEN THIS RUNS
//  Appended to obj_controller_Create_0, which runs after faction_load() (line
//  25) and re-runs on every hub/map load. Every operation here is idempotent.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_faction_name()
/// @desc   Single definition of the faction id. Deliberately not configurable:
///         it is written into save data, so changing it would orphan a roster.
function csq_faction_name()
{
    return "Companion";
}


/// @func   csq_faction_desired_rep(_other)
/// @desc   Reputation this mod wants between "Companion" and _other.
///         Mirroring the player's own standing (the default) means companions
///         automatically fight whoever the player is currently hostile to, and
///         keep up as reputation shifts during play.
/// @return {Real} 0..1000  (<250 hostile, 250-600 neutral, >600 ally)
function csq_faction_desired_rep(_other)
{
    var _ally    = csq_cfg("rep_ally");
    var _hostile = csq_cfg("rep_hostile");
    var _me      = csq_faction_name();

    // Always allied: ourselves (so companions never shoot each other), the
    // player, and the catch-all friendly faction.
    if (_other == _me)           return _ally;
    if (_other == "Player")      return _ally;
    if (_other == "All Friend")  return _ally;

    if (csq_cfg("mirror_player_relations"))
    {
        try
        {
            var _p = faction_get_rep_temp("Player", _other);
            if (!is_undefined(_p) && is_numeric(_p)) return _p;
        }
        catch (_err)
        {
            // Fall through to the explicit table below.
        }
    }

    // Explicit fallback, used when mirroring is disabled or unavailable.
    if (_other == "All Enemy" || _other == "Bandits" || _other == "Mutants")
    {
        return _hostile;
    }

    return 500;   // neutral: will not start a fight, will defend itself
}


/// @func   csq_faction_set_temp_one_way(_from, _to, _value)
/// @desc   Write a single direction of the temp registry. Used only for
///         factions absent from temp, where faction_set_rep_temp would throw
///         because it dereferences both entries.
function csq_faction_set_temp_one_way(_from, _to, _value)
{
    try
    {
        if (!variable_struct_exists(global.struct_faction_temp, _from)) return false;

        var _entry = variable_struct_get(global.struct_faction_temp, _from);
        var _rel   = variable_struct_get(_entry, "relationship");

        if (!is_struct(_rel)) return false;

        variable_struct_set(_rel, _to, _value);
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_faction_set_temp_one_way", _err);
        return false;
    }
}


/// @func   csq_faction_ensure_temp_entry(_name)
/// @desc   Guarantee _name exists in the temp registry, deep-copying its base
///         entry if necessary. SnapDeepCopy is the game's own cloning helper.
function csq_faction_ensure_temp_entry(_name)
{
    try
    {
        if (!variable_global_exists("struct_faction_temp"))          return false;
        if (variable_struct_exists(global.struct_faction_temp, _name)) return true;
        if (!variable_struct_exists(global.struct_faction, _name))    return false;

        var _base = variable_struct_get(global.struct_faction, _name);
        variable_struct_set(global.struct_faction_temp, _name, SnapDeepCopy(_base));

        csq_log_debug("faction: created temp registry entry for '" + string(_name) + "'");
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_faction_ensure_temp_entry", _err);
        return false;
    }
}


/// @func   csq_faction_register()
/// @desc   Create the companion faction and write a complete, total set of
///         relationships into both registries. Idempotent; called on every map
///         load.
/// @return {Bool} success
function csq_faction_register()
{
    try
    {
        if (!variable_global_exists("struct_faction"))
        {
            csq_log_error("faction: global.struct_faction missing -- " +
                          "registration skipped (is the load order correct?)");
            return false;
        }

        var _me     = csq_faction_name();
        var _is_new = !variable_struct_exists(global.struct_faction, _me);

        faction_create(_me);                  // no-ops when already present
        csq_faction_ensure_temp_entry(_me);

        var _names     = variable_struct_get_names(global.struct_faction);
        var _temp_gaps = 0;

        for (var _i = 0; _i < array_length(_names); _i++)
        {
            var _other = _names[_i];
            var _rep   = csq_faction_desired_rep(_other);

            // Base registry. Writes both directions and creates absent keys,
            // which is what closes vanilla gap 1 described above.
            faction_set_rep(_me, _other, _rep);

            // Temp registry -- the one combat actually reads.
            if (variable_struct_exists(global.struct_faction_temp, _other))
            {
                faction_set_rep_temp(_me, _other, _rep);
            }
            else
            {
                // vanilla gap 2: write our side only.
                csq_faction_set_temp_one_way(_me, _other, _rep);
                _temp_gaps++;
            }
        }

        if (_is_new)
        {
            csq_log_info("faction: registered '" + _me + "' across " +
                         string(array_length(_names)) + " faction(s)");
        }
        else
        {
            csq_log_debug("faction: refreshed '" + _me + "' relations");
        }

        if (_temp_gaps > 0)
        {
            csq_log_debug("faction: " + string(_temp_gaps) + " faction(s) absent from " +
                          "the temp registry, wrote one-way relations for them");
        }

        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_faction_register", _err);
        return false;
    }
}


/// @func   csq_faction_rep_hostile_max()
/// @desc   The reputation thresholds vanilla scr_get_relation uses:
///             rep <  250   hostile
///             rep 250..600 neutral
///             rep >  600   ally
///         Named here so the rest of the mod can classify a relationship without
///         either a bare magic number or a dependency on the decompiled
///         UnknownEnum values, whose numbering is an artefact of decompilation.
function csq_faction_rep_hostile_max() { return 250; }
function csq_faction_rep_ally_min()    { return 600; }


/// @func   csq_faction_validate_config()
/// @desc   Check the configured reputation values against the thresholds vanilla
///         actually classifies on, and warn when they disagree.
///
///         Worth checking because both values are player-editable and the failure
///         mode is silent rather than loud. rep_ally set to 400 leaves companions
///         merely *neutral* to the player, so they never adopt the player's
///         enemies; rep_hostile set to 300 leaves them unwilling to open fire on
///         bandits at all. Neither raises an error -- the squad just stands around
///         looking broken, with nothing in the log to explain why.
///
///         This only warns. Clamping would silently override a deliberate choice,
///         and deliberately neutral companions are a legitimate thing to want; the
///         log line is enough to account for the behaviour.
/// @return {Bool} whether both values sit on the expected side of the thresholds
function csq_faction_validate_config()
{
    var _ok = true;

    try
    {
        var _ally    = csq_cfg("rep_ally");
        var _hostile = csq_cfg("rep_hostile");

        if (_ally <= csq_faction_rep_ally_min())
        {
            csq_log_warn("config: rep_ally is " + string(_ally) + ", not above the " +
                         string(csq_faction_rep_ally_min()) + " the game requires for an " +
                         "ally -- companions will be treated as neutral and will not " +
                         "adopt the player's enemies");
            _ok = false;
        }

        if (_hostile >= csq_faction_rep_hostile_max())
        {
            csq_log_warn("config: rep_hostile is " + string(_hostile) + ", not below the " +
                         string(csq_faction_rep_hostile_max()) + " the game requires for " +
                         "hostility -- companions will not open fire on factions they are " +
                         "meant to fight");
            _ok = false;
        }
    }
    catch (_err)
    {
        csq_log_exception("csq_faction_validate_config", _err);
        return false;
    }

    return _ok;
}


/// @func   csq_faction_is_hostile(_mine, _other)
/// @desc   Whether faction _mine should shoot faction _other, read from the temp
///         registry -- the same one combat itself consults.
///
///         An absent counterpart key yields `undefined` (see vanilla gap 1 in the
///         header). That is treated as NOT hostile: refusing to shoot something
///         the game cannot classify is the safe failure mode, since the
///         alternative is companions opening fire on quest givers and traders.
function csq_faction_is_hostile(_mine, _other)
{
    try
    {
        if (is_undefined(_mine) || is_undefined(_other)) return false;

        // "All Enemy" is vanilla's catch-all for things that fight everyone.
        if (_other == "All Enemy") return true;

        var _rep = faction_get_rep_temp(_mine, _other);

        if (is_undefined(_rep) || !is_numeric(_rep)) return false;

        return _rep < csq_faction_rep_hostile_max();
    }
    catch (_err)
    {
        return false;
    }
}


/// @func   csq_faction_apply(_inst)
/// @desc   Put an instance into the companion faction. Called from the
///         companion's Create event *after* npc_setup, which would otherwise
///         leave the preset's own faction (Loners) in place.
function csq_faction_apply(_inst)
{
    try
    {
        if (!instance_exists(_inst)) return false;

        _inst.faction = csq_faction_name();
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_faction_apply", _err);
        return false;
    }
}
