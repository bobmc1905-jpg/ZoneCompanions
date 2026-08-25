// =============================================================================
//  Zone Companions  -  csq_persist
// -----------------------------------------------------------------------------
//  Saves and restores the roster using the game's own save database, so a squad
//  belongs to a character and travels with that character's save slot.
//
//  WHY THE "general" DATABASE
//  Vanilla faction_save() is exactly this pattern:
//      db_open("general");
//      db_write("factions", "struct", SnapDeepCopy(global.struct_faction));
//      db_close();
//  "general" is the per-save-slot database. Writing there means the roster is
//  bound to the character, survives quitting to menu, and is deleted with the
//  save -- all of which are what a player would expect. A separate side file
//  would instead leak one character's companions into another's game.
//
//  "general" IS AN ALIAS, NOT A DATABASE OF ITS OWN
//  scr_setup_save_databases() calls
//      db_group_setup("shared", ["general", "pre_raid", "chest", "ftue"])
//  which registers the *same struct reference* under every one of those aliases.
//  So global.database_struct.general IS global.database_struct.shared, and its
//  loaded / allow_save / filename fields are the shared database's. db_open then
//  narrows the write target to shared.data.general, so this mod's section lands at
//      shared.data.general.mycompanions
//  alongside vanilla's own "factions" section, with no possibility of collision.
//  Two consequences the code below relies on: probing the "general" alias yields
//  valid state even though nothing ever db_create()d it, and .filename identifies
//  the save slot ("save_shared_<n>.dat").

//
//  ================  THE CRITICAL SAFETY CONSTRAINT  ========================
//  Every db_* precondition failure calls __db_error(), which ends in
//      show_error(_string + "\n ", true)
//  That aborts the game. It is NOT a catchable GML exception, so try/catch
//  offers no protection whatsoever. Every precondition must therefore be
//  checked by this module *before* the call:
//
//    db_open   fatal if a database is already open  (global.database_alias != undefined)
//    db_open   fatal if the alias was never db_create()d
//    db_read   fatal if the database is not loaded and allow_load is set
//    db_*      fatal if called with nothing open
//
//  Hence csq_persist_probe(), which inspects global.database_struct directly
//  rather than calling db_is_loaded() -- that helper is itself fatal for an
//  unknown alias. Nothing in this module calls a db_* function until the probe
//  has confirmed it is safe.
//  ==========================================================================
//
//  WHY WRITING IS GATED ON THE DATABASE BEING LOADED
//  db_write happily creates a section in an unloaded database, and db_close then
//  flushes it to disk. On an unloaded save that would write out a file
//  containing this mod's section and nothing else -- destroying the save. So
//  saving requires loaded == true, every time, with no fallback.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_persist_alias()
/// @desc   Database, section and schema version. The version number lets a later
///         release migrate old data instead of guessing at its shape.
///
///         The section name is "mycompanions" rather than the mod's current
///         display name: it is the key rosters are already stored under, and
///         renaming it would silently orphan every existing squad rather than
///         load it. It is never shown to the player, so it stays as it is. If it
///         ever does change, bump csq_persist_version() and migrate on read.
function csq_persist_alias()   { return "general"; }
function csq_persist_section() { return "mycompanions"; }
function csq_persist_version() { return 1; }


/// @func   csq_persist_probe()
/// @desc   Decide what is safe to do with the save database right now, without
///         calling any db_* function. See the safety note in the header.
/// @return {Struct} {exists, loaded, can_open, can_read, can_write, source, why}
function csq_persist_probe()
{
    var _result = {
        exists:    false,
        loaded:    false,
        can_open:  false,
        can_read:  false,
        can_write: false,
        source:    "",
        why:       ""
    };

    if (!variable_global_exists("database_struct") || !is_struct(global.database_struct))
    {
        _result.why = "database subsystem not initialised";
        return _result;
    }

    if (!variable_struct_exists(global.database_struct, csq_persist_alias()))
    {
        _result.why = "database '" + csq_persist_alias() + "' does not exist yet";
        return _result;
    }

    var _db = variable_struct_get(global.database_struct, csq_persist_alias());
    if (!is_struct(_db))
    {
        _result.why = "database '" + csq_persist_alias() + "' is not a struct";
        return _result;
    }

    _result.exists = true;
    _result.loaded = csq_struct_get(_db, "loaded", false);

    // Which file this database is currently bound to. "general" is a group member
    // of "shared" (db_group_setup), so this is the shared database's own filename:
    // "save_shared_<slot>.dat". That makes it a reliable identity for which save
    // slot is in play -- see the slot-change check in csq_persist_load.
    _result.source = string(csq_struct_get(_db, "filename", ""));

    // db_open is fatal if anything is already open.
    var _busy = variable_global_exists("database_alias") &&
                !is_undefined(global.database_alias);

    if (_busy)
    {
        _result.why = "database '" + string(global.database_alias) + "' is already open";
        return _result;
    }

    _result.can_open = true;

    // db_read is fatal unless loaded, or unless loading is disabled entirely.
    var _allow_load = csq_struct_get(_db, "allow_load", true);
    _result.can_read = _result.loaded || !_allow_load;

    // Writing additionally requires that saving is permitted at all.
    _result.can_write = _result.loaded && csq_struct_get(_db, "allow_save", true);

    if (!_result.loaded) _result.why = "no save is loaded";

    return _result;
}


/// @func   csq_persist_serialise()
/// @desc   Reduce the roster to plain data. Live instance ids are deliberately
///         dropped -- they are meaningless in the next session, and JSON cannot
///         represent them anyway.
/// @return {Array} array of {preset, name, hp, hp_mult}
function csq_persist_serialise()
{
    csq_squad_init();

    var _out = [];

    for (var _i = 0; _i < array_length(global.csq_squad); _i++)
    {
        var _entry = global.csq_squad[_i];

        // Prefer the live HP over the stored value, so quitting mid-raid keeps
        // whatever damage the companion has actually taken.
        var _hp = _entry.hp;
        if (csq_alive(_entry.inst)) _hp = _entry.inst.hp;

        array_push(_out, {
            preset:  string(_entry.preset),
            name:    string(_entry.name),
            hp:      _hp,

            // Carry the tier toughness so a Veteran reloaded from a save is still a
            // Veteran. -1 for a legacy entry that predates tiers, which loads back
            // to the configured hp_multiplier.
            hp_mult: csq_struct_get(_entry, "hp_mult", -1)
        });
    }

    return _out;
}


/// @func   csq_persist_deserialise(_data)
/// @desc   Rebuild the roster from saved data, validating every field. Bad or
///         partial records are skipped rather than trusted, because save data
///         may have been written by an older version of the mod.
/// @return {Real} how many entries were restored
function csq_persist_deserialise(_data)
{
    csq_squad_init();

    if (!is_array(_data))
    {
        csq_log_debug("persist: no roster array in save data");
        return 0;
    }

    var _restored = [];
    var _skipped  = 0;
    var _max      = csq_squad_max();

    for (var _i = 0; _i < array_length(_data); _i++)
    {
        var _record = _data[_i];

        if (!is_struct(_record))
        {
            _skipped++;
            continue;
        }

        var _preset = csq_struct_get(_record, "preset", "");
        if (!is_string(_preset) || _preset == "")
        {
            _skipped++;
            continue;
        }

        // Honour a max_companions that the player has since lowered.
        if (array_length(_restored) >= _max)
        {
            _skipped++;
            continue;
        }

        var _name = csq_struct_get(_record, "name", "");
        var _hp   = csq_struct_get(_record, "hp", -1);

        if (!is_numeric(_hp)) _hp = -1;

        // hp_mult is absent from saves written before tiers existed; -1 restores
        // those to the configured hp_multiplier, exactly as they behaved before.
        var _hp_mult = csq_struct_get(_record, "hp_mult", -1);
        if (!is_numeric(_hp_mult)) _hp_mult = -1;

        array_push(_restored, csq_squad_make_entry(_preset, _name, _hp, _hp_mult));
    }

    global.csq_squad = _restored;

    if (_skipped > 0)
    {
        csq_log_warn("persist: skipped " + string(_skipped) +
                     " unusable roster record(s) in save data");
    }

    return array_length(_restored);
}


/// @func   csq_persist_save()
/// @desc   Write the roster to the current save slot.
/// @return {Bool} whether anything was written
function csq_persist_save()
{
    var _probe = csq_persist_probe();

    if (!_probe.can_open || !_probe.can_write)
    {
        csq_log_debug("persist: save skipped (" + _probe.why + ")");
        return false;
    }

    // Past this point every precondition is satisfied, so no db_* call can abort.
    try
    {
        db_open(csq_persist_alias());

        db_write(csq_persist_section(), "version", csq_persist_version());
        db_write(csq_persist_section(), "roster",  csq_persist_serialise());

        // db_close flushes when the database is marked changed, which db_write
        // does automatically via autoscan_for_changes.
        db_close();

        csq_log_info("persist: saved " + string(csq_squad_count()) + " companion(s)");
        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_persist_save", _err);

        // Leave the database closed whatever happened, or the next db_open in
        // the *game's* own code would abort.
        try { db_close(true); } catch (_ignored) {}
        return false;
    }
}


/// @func   csq_persist_load()
/// @desc   Restore the roster from the current save slot. Safe to call on every
///         map load; global.csq_persist_loaded stops it re-reading and discarding
///         a roster that has changed since the save, while the save-slot check
///         below makes sure that guard cannot outlive the character it applies to.
/// @return {Bool} whether data was read
function csq_persist_load()
{
    if (!variable_global_exists("csq_persist_loaded"))
    {
        global.csq_persist_loaded = false;
    }

    if (!variable_global_exists("csq_persist_source"))
    {
        global.csq_persist_source = "";
    }

    var _probe = csq_persist_probe();

    if (!_probe.can_open || !_probe.can_read)
    {
        csq_log_debug("persist: load skipped (" + _probe.why + ")");
        return false;
    }

    // Re-read when the save slot itself has changed, even though a roster was
    // already loaded this session.
    //
    // Quitting to the menu and starting or loading a different character calls
    // db_set_filename("shared", "save_shared_<slot>.dat"), which changes .filename
    // and clears .loaded. Comparing the filename is therefore an exact answer to
    // "is this the same save I read from?" -- and it needs no extra patch to a
    // main-menu event, which is why this replaced an explicit session-reset hook.
    //
    // Without it, the flag would stay true for the lifetime of the process and the
    // first character's squad would follow the player into every character loaded
    // afterwards, until the game was restarted.
    var _same_save = (_probe.source == global.csq_persist_source);

    if (global.csq_persist_loaded && _same_save)
    {
        csq_log_debug("persist: roster already loaded this session");
        return false;
    }

    if (global.csq_persist_loaded && !_same_save)
    {
        csq_log_info("persist: save slot changed ('" + global.csq_persist_source +
                     "' -> '" + _probe.source + "'), re-reading the roster");
    }

    try
    {
        db_open(csq_persist_alias());

        var _version = db_read(csq_persist_section(), "version", 0);
        var _roster  = db_read(csq_persist_section(), "roster",  []);

        // Pass true so closing cannot write anything -- loading must never
        // modify the save.
        db_close(true);

        if (_version > csq_persist_version())
        {
            csq_log_warn("persist: save data is version " + string(_version) +
                         " but this mod understands " + string(csq_persist_version()) +
                         "; loading anyway");
        }

        var _n = csq_persist_deserialise(_roster);

        global.csq_persist_loaded = true;
        global.csq_persist_source = _probe.source;

        if (_n > 0) csq_log_info("persist: restored " + string(_n) + " companion(s) from the save");
        else        csq_log_debug("persist: no saved companions for this character");

        return true;
    }
    catch (_err)
    {
        csq_log_exception("csq_persist_load", _err);
        try { db_close(true); } catch (_ignored) {}
        return false;
    }
}
