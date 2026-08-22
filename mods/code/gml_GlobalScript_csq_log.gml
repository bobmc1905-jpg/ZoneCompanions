// =============================================================================
//  Zone Companions  -  csq_log
// -----------------------------------------------------------------------------
//  Levelled, toggleable logging.
//
//      0  ERROR    something broke; always logged
//      1  WARNING   recoverable oddity
//      2  INFO      lifecycle milestones (default)
//      3  DEBUG     per-companion detail; also gated by debug_enabled
//
//  Output goes to logs/csq_log.txt and/or the game's own trace(). The file path
//  is relative, so GameMaker's sandbox resolves it inside the save area, which on
//  Windows is %LOCALAPPDATA%\ZERO_Sievert\logs\csq_log.txt. This mirrors the
//  game's own convention in gml_GlobalScript_ga_trace, which writes
//  "logs/ga_log.txt" via file_text_open_append.
//
//  Design rules:
//   * Logging must never be able to crash the game. Every file operation is
//     wrapped, and a failure permanently disables file output rather than
//     retrying (and failing) once per frame.
//   * Logging must work before csq_config_load() has run, because config load
//     itself logs. csq_cfg() falls back to spec defaults, so that is safe.
//   * Logging must work even if some other module failed to import. That is why
//     the "[ZoneCompanions]" line prefix below is a literal rather than a call to
//     csq_mod_name(): this module is the one thing that has to be able to report
//     a broken mod, so it depends on nothing but csq_cfg.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_log_filename()
function csq_log_filename()
{
    return "logs/csq_log.txt";
}


/// @func   csq_log_level_name(_level)
function csq_log_level_name(_level)
{
    switch (_level)
    {
        case 0:  return "ERROR";
        case 1:  return "WARN ";
        case 2:  return "INFO ";
        case 3:  return "DEBUG";
        default: return "?????";
    }
}


/// @func   csq_log_init()
/// @desc   Create logs/ if absent, truncate the log, and write a header. Called
///         once per game launch from csq_boot, before config is loaded.
/// @return {Bool} whether file logging is available
function csq_log_init()
{
    global.csq_log_ready       = true;
    global.csq_log_file_broken = false;

    var _f = -1;
    try
    {
        // The save area has no logs/ folder on a fresh install.
        if (!directory_exists("logs")) directory_create("logs");

        // Truncate: one log per launch keeps it readable.
        _f = file_text_open_write(csq_log_filename());
        file_text_write_string(_f, "=== Zone Companions log  |  " +
                                   date_datetime_string(date_current_datetime()) + " ===");
        file_text_writeln(_f);
        file_text_close(_f);
    }
    catch (_err)
    {
        global.csq_log_file_broken = true;
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
        // Fall back to trace() only; the mod carries on regardless.
        try { trace("[ZoneCompanions] WARN : could not open " + csq_log_filename() +
                    ", file logging disabled"); } catch (_ignored2) {}
        return false;
    }

    return true;
}


/// @func   csq_log(_level, _message)
/// @desc   Core log routine. Prefer the csq_log_error/warn/info/debug wrappers.
function csq_log(_level, _message)
{
    // Honour the configured verbosity. csq_cfg falls back to defaults when
    // config has not been loaded yet, so this is safe during early boot.
    if (_level > csq_cfg("log_level")) return;

    // DEBUG additionally requires the master debug switch.
    if (_level >= 3 && !csq_cfg("debug_enabled")) return;

    var _line = "[ZoneCompanions] " + csq_log_level_name(_level) + ": " + string(_message);

    if (csq_cfg("log_to_trace"))
    {
        try { trace(_line); } catch (_ignored) {}
    }

    if (!csq_cfg("log_to_file")) return;

    // A broken log file stays broken -- do not retry every frame.
    if (variable_global_exists("csq_log_file_broken") && global.csq_log_file_broken) return;

    var _f = -1;
    try
    {
        _f = file_text_open_append(csq_log_filename());
        file_text_write_string(_f, _line);
        file_text_writeln(_f);
        file_text_close(_f);
    }
    catch (_err)
    {
        global.csq_log_file_broken = true;
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
    }
}


function csq_log_error(_message) { csq_log(0, _message); }
function csq_log_warn(_message)  { csq_log(1, _message); }
function csq_log_info(_message)  { csq_log(2, _message); }
function csq_log_debug(_message) { csq_log(3, _message); }


/// @func   csq_log_exception(_where, _err)
/// @desc   Uniform reporting for a caught exception. GML exception structs carry
///         .message and .longMessage, but a thrown string or value has neither,
///         so both shapes are handled.
function csq_log_exception(_where, _err)
{
    var _detail = "";

    if (is_struct(_err))
    {
        if (variable_struct_exists(_err, "longMessage"))    _detail = string(_err.longMessage);
        else if (variable_struct_exists(_err, "message"))   _detail = string(_err.message);
        else                                                _detail = "unrecognised exception struct";
    }
    else
    {
        _detail = string(_err);
    }

    csq_log_error(string(_where) + ": " + _detail);
}
