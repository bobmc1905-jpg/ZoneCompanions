// =============================================================================
//  Zone Companions  -  csq_config
// -----------------------------------------------------------------------------
//  Every tunable value in the mod lives in this file. Nothing else in the mod
//  should contain a magic number: if a value might ever want changing, it gets
//  an entry in csq_config_spec() and an ini key, and is read back through
//  csq_cfg().
//
//  WHERE THE FILE LIVES
//  GameMaker sandboxes relative file I/O into the game's save area, so the
//  filename below resolves to:
//      %LOCALAPPDATA%\ZERO_Sievert\csq_config.ini
//  (the same folder that already holds installed_mods.json, mods_enabled.json
//  and the numeric save slots). That is a better home than the game folder: it
//  survives both GMLoader re-patching and game updates.
//
//  WHY A HAND-ROLLED PARSER INSTEAD OF ini_open/ini_read_*
//  GameMaker's ini_close() always rewrites the file from its parsed contents,
//  which silently strips every comment. Since the whole point of shipping a
//  generated, commented ini is that the user can read what the keys mean, the
//  mod writes the file once with comments and thereafter only ever reads it.
//  A missing key falls back to its default and logs a warning rather than
//  rewriting the user's file.
//
//  NOTE ON STRUCTURE
//  Section headers are cosmetic and exist purely to group the file for humans.
//  Key names are globally unique, so a key is found regardless of which section
//  it is under.
//
//  This file declares functions only. It deliberately contains no top-level
//  executable code -- all initialisation is driven from real object events by
//  csq_init, because a newly created global script's top-level body is not
//  guaranteed to be run at game start by the patcher.
// =============================================================================


/// @func   csq_config_spec()
/// @desc   The single source of truth for every setting: its section, name,
///         type, default and documentation. Load, default-file generation and
///         validation are all driven from this one array, so a new setting is
///         added in exactly one place.
/// @return {Array} array of {section, key, type, def, comment}
function csq_config_spec()
{
    return [
        // ---- debug -------------------------------------------------------
        { section: "debug", key: "debug_enabled", type: "bool", def: false,
          comment: "Master switch for DEBUG-level logging and on-screen debug text." },
        { section: "debug", key: "log_level", type: "real", def: 2,
          comment: "0=ERROR only, 1=+WARNING, 2=+INFO (default), 3=+DEBUG." },
        { section: "debug", key: "log_to_file", type: "bool", def: true,
          comment: "Write the log to logs/csq_log.txt in the save folder." },
        { section: "debug", key: "log_to_trace", type: "bool", def: true,
          comment: "Also send every log line to the game's own trace() output." },
        { section: "debug", key: "draw_debug_overlay", type: "bool", def: false,
          comment: "Draw per-companion mode/state/target text. Needs debug_enabled." },

        // ---- squad -------------------------------------------------------
        { section: "squad", key: "max_companions", type: "real", def: 3,
          comment: "How many companions may be active at once (1-8 is sane)." },
        { section: "squad", key: "default_preset", type: "string", def: "loner_regular",
          comment: "NPC preset companions are built from. Must exist in gamedata/npc.json." },
        { section: "squad", key: "auto_spawn_in_raid", type: "bool", def: true,
          comment: "Respawn the saved roster automatically when a raid map loads." },
        { section: "squad", key: "spawn_offset", type: "real", def: 24,
          comment: "Pixels from the player to look for a free spawn cell." },
        { section: "squad", key: "spawn_delay_frames", type: "real", def: 30,
          comment: "Frames to wait after a map loads before spawning, so the map has finished generating." },
        { section: "squad", key: "respawn_on_death", type: "bool", def: false,
          comment: "false = a fallen companion is gone for good. true = they return next raid." },
        { section: "squad", key: "recover_deactivated", type: "bool", def: true,
          comment: "Reactivate and pull back companions the game culls for being too far away. Turn off only if it fights another mod." },
        // Companions fight at the player's pace and take the hits that go with it,
        // but they are built from an ordinary enemy preset -- loner_regular has 60
        // HP, the same as the mooks you kill three of at a time. 1 is vanilla-fair
        // and dies fast.
        { section: "squad", key: "hp_multiplier", type: "real", def: 1.5,
          comment: "Multiplies a companion's starting health. loner_regular has 60 HP, so 1.5 gives 90. The game's own difficulty scaling still applies on top." },

        // ---- follow ------------------------------------------------------
        { section: "follow", key: "follow_distance", type: "real", def: 32,
          comment: "Desired standoff distance from the player, in pixels." },
        { section: "follow", key: "formation_spread", type: "real", def: 26,
          comment: "How far apart companions fan out around the follow point." },
        { section: "follow", key: "catchup_distance", type: "real", def: 40,
          comment: "Distance from its formation slot at which a companion switches to catch-up speed." },
        { section: "follow", key: "arrive_distance", type: "real", def: 10,
          comment: "Inside this distance OF ITS SLOT a companion stops and holds position." },
        // Follow speed is the greater of two terms, checked every frame:
        //   * the preset's own spd_alerted scaled by speed_walk_mult / speed_run_mult
        //   * the player's ACTUAL current speed scaled by speed_match_mult /
        //     speed_catchup_mult
        // The second term is what keeps them with the player: reference numbers are
        // player walk 0.75 and player run 1.2 px/step (scr_player_movement:108-109),
        // but backpacks, hunter skills and the hub's 1.5x run bonus all raise that,
        // so it is read off the live player rather than assumed. loner_regular's
        // spd_alerted is 0.75 px/step.
        { section: "follow", key: "speed_walk_mult", type: "real", def: 1.05,
          comment: "Multiplier on the preset's alerted speed, used as the cruising floor." },
        { section: "follow", key: "speed_run_mult", type: "real", def: 2.6,
          comment: "Multiplier on the preset's alerted speed, used as the catch-up floor." },
        { section: "follow", key: "speed_match_mult", type: "real", def: 1.15,
          comment: "Cruising speed as a multiple of the player's CURRENT speed. Must be >1 or gaps never close." },
        { section: "follow", key: "speed_catchup_mult", type: "real", def: 1.75,
          comment: "Catch-up speed as a multiple of the player's CURRENT speed. Raise if they still lag behind." },
        { section: "follow", key: "speed_max", type: "real", def: 3.0,
          comment: "Hard ceiling on follow speed in pixels per step, so nothing looks like it is teleporting." },
        { section: "follow", key: "goal_move_threshold", type: "real", def: 8,
          comment: "Player must move this far before the formation slot is retargeted." },
        { section: "follow", key: "teleport_distance", type: "real", def: 400,
          comment: "Only consider teleporting past this distance. 0 disables teleporting." },
        { section: "follow", key: "teleport_fail_frames", type: "real", def: 90,
          comment: "Frames of continuous pathing failure required before teleporting." },
        // The formation sits BEHIND the player's heading, which is what keeps
        // companions out of your line of fire -- but it also means they hang back
        // by your shoulders and never screen the direction you are actually
        // watching. This slides the whole formation toward the cursor.
        { section: "follow", key: "aim_lead", type: "real", def: 26,
          comment: "Pixels the formation slides toward where you are aiming. 0 is off: companions sit purely behind you. Around follow_distance puts them level with you on the side you are covering; much higher pushes them out in front as a screen." },
        { section: "follow", key: "aim_lead_smooth", type: "real", def: 0.08,
          comment: "How quickly companions follow the cursor, per frame, 0.01 slow to 1 instant. Low values stop a flicked mouse making them jitter." },

        // ---- roam --------------------------------------------------------
        // Companions drift around their formation slot instead of standing on it.
        //
        // ROAMING IS SUPPRESSED WHILE THE PLAYER IS MOVING, on purpose. The follow
        // loop above was retuned specifically to stop companions trailing behind;
        // adding a random offset on top of a target that is already moving away
        // would hand that bug straight back. See roam_max_player_speed.
        { section: "roam", key: "roam_enabled", type: "bool", def: true,
          comment: "Let companions wander around their formation slot while the player is still." },
        { section: "roam", key: "roam_radius", type: "real", def: 40,
          comment: "How far from its formation slot a companion may drift, in pixels." },
        { section: "roam", key: "roam_interval", type: "real", def: 90,
          comment: "Frames between new wander destinations. 90 is about 1.5 seconds." },
        { section: "roam", key: "roam_max_player_speed", type: "real", def: 0.3,
          comment: "Roaming stops once the player moves faster than this, in pixels per step. Player walk is about 0.75, so 0.3 means 'only while standing still'. Raise it to keep roaming while on the move, at the cost of a looser formation." },

        // ---- combat ------------------------------------------------------
        { section: "combat", key: "engage_radius", type: "real", def: 420,
          comment: "Companions ignore enemies further than this from the player. Roughly a screen width; the game deactivates NPCs past ~480px anyway." },
        { section: "combat", key: "engage_advance", type: "real", def: 96,
          comment: "How far toward the enemy a companion may push while fighting, in pixels. 0 makes them hug the player. Raise for a more aggressive push, lower to keep them close." },
        { section: "combat", key: "disengage_frames", type: "real", def: 150,
          comment: "Frames without a target before a companion returns to following. Higher = stays in a fight through brief losses of line of sight." },
        { section: "combat", key: "scan_interval", type: "real", def: 4,
          comment: "Frames between target scans while following. Lower = faster reactions, more CPU." },
        { section: "combat", key: "mirror_player_relations", type: "bool", def: true,
          comment: "Copy the player's faction standings, so companions fight whoever you fight." },
        { section: "combat", key: "rep_ally", type: "real", def: 1000,
          comment: "Reputation written for allies. >600 counts as ally in-game." },
        { section: "combat", key: "rep_hostile", type: "real", def: 0,
          comment: "Reputation written for enemies. <250 counts as hostile in-game." },

        // ---- ff ----------------------------------------------------------
        // Friendly fire. The two bullet settings are enforced inside vanilla's own
        // collision predicates, so a blocked round is not consumed -- it passes
        // through and can still hit the enemy behind. See csq_ff.
        { section: "ff", key: "ff_protect_player", type: "bool", def: true,
          comment: "Companion bullets pass harmlessly through you." },
        { section: "ff", key: "ff_protect_companions", type: "bool", def: true,
          comment: "Your bullets pass harmlessly through companions. Turn this off if you want to be able to shoot your own squad." },
        { section: "ff", key: "ff_no_grenades", type: "bool", def: true,
          comment: "Stop companions throwing grenades at all. The preset carries live RGD grenades and flashbangs, and grenade damage has no faction check of any kind." },

        // ---- medic -------------------------------------------------------
        // Thresholds are fractions of the player's CURRENT maximum HP, which
        // vanilla recomputes every frame as
        //     hp_max = hp_max_total - wound
        // (player_step_personal_stats lines 44-45). So a wounded player sitting at
        // full effective health counts as full and is not healed -- closing a wound
        // takes medication, not a field dressing, and nothing here touches `wound`.
        { section: "medic", key: "heal_enabled", type: "bool", def: true,
          comment: "Let companions heal you when you are hurt." },
        { section: "medic", key: "heal_threshold", type: "real", def: 0.85,
          comment: "Heal once your health drops below this fraction of maximum. 1 = heal any damage at all." },
        { section: "medic", key: "heal_emergency_threshold", type: "real", def: 0.35,
          comment: "Below this fraction a companion abandons a firefight to reach you. Above it, it finishes the fight first." },
        { section: "medic", key: "heal_amount", type: "real", def: 25,
          comment: "HP restored per heal. Never takes you above your current maximum." },
        { section: "medic", key: "heal_charges", type: "real", def: 2,
          comment: "Heals each companion carries. Refilled at the start of every raid." },
        { section: "medic", key: "heal_cooldown_frames", type: "real", def: 600,
          comment: "Frames a companion waits between heals. 600 is 10 seconds at 60fps." },
        { section: "medic", key: "heal_range", type: "real", def: 24,
          comment: "How close a companion must get before it can heal you, in pixels." },
        { section: "medic", key: "heal_stop_bleed", type: "bool", def: true,
          comment: "Also stop bleeding, the way an NPC medic's dialogue heal does." },
        { section: "medic", key: "heal_message", type: "bool", def: true,
          comment: "Show an on-screen message when a companion patches you up." },

        // ---- hud ---------------------------------------------------------
        { section: "hud", key: "hud_enabled", type: "bool", def: true,
          comment: "Show the squad list. Coordinates below are in 480x270 GUI space." },
        { section: "hud", key: "hud_x", type: "real", def: 6,
          comment: "Left edge of the squad list, in GUI pixels (0-480)." },
        { section: "hud", key: "hud_y", type: "real", def: 40,
          comment: "Top edge of the squad list, in GUI pixels (0-270)." },
        { section: "hud", key: "hud_line_height", type: "real", def: 10,
          comment: "Vertical spacing per companion row." },
        // Row spacing is multiplied by this too, so shrinking the text does not
        // leave the panel spread over the same height it was before.
        { section: "hud", key: "hud_scale", type: "real", def: 1,
          comment: "Text size for the whole squad panel. 1 is the game's own smallest UI font at native size. 0.75 fits more on screen but looks ragged, because that font is a bitmap generated with antialiasing switched off." },
        { section: "hud", key: "hud_show_hp", type: "bool", def: true,
          comment: "Append current/max HP to each row." },

        // ---- input -------------------------------------------------------
        // Defaults are function keys so they cannot collide with the game's
        // movement/inventory bindings. Values are GameMaker virtual key codes:
        // F1=112 ... F12=123, A=65 ... Z=90, 0=48 ... 9=57.
        { section: "input", key: "key_recruit", type: "real", def: 117,
          comment: "Add a new companion built from default_preset. In a raid they appear beside you; in the hub they join the roster and turn up at the start of the next raid. Does nothing once the roster holds max_companions. Default F6." },
        { section: "input", key: "key_dismiss", type: "real", def: 118,
          comment: "Dismiss the nearest companion. Default F7." },
        { section: "input", key: "key_toggle_hold", type: "real", def: 119,
          comment: "Toggle the squad between Follow and Hold. Default F8." },
        { section: "input", key: "key_toggle_hud", type: "real", def: 116,
          comment: "Show or hide the squad panel. Default F5. Resets to shown every launch." },
        { section: "input", key: "key_debug_dump", type: "real", def: 120,
          comment: "Dump full squad state to the log. Default F9." }
    ];
}


/// @func   csq_config_filename()
/// @desc   Config path, relative so it resolves inside the save area.
function csq_config_filename()
{
    return "csq_config.ini";
}


/// @func   csq_config_parse_bool(_raw, _def)
/// @desc   Accepts true/false, yes/no, on/off and 1/0 in any casing.
function csq_config_parse_bool(_raw, _def)
{
    var _v = string_lower(string_trim(_raw));
    if (_v == "true" || _v == "1" || _v == "yes" || _v == "on")   return true;
    if (_v == "false" || _v == "0" || _v == "no" || _v == "off")  return false;
    return _def;
}


/// @func   csq_config_format_value(_type, _value)
/// @desc   Render a value the way the ini should contain it.
function csq_config_format_value(_type, _value)
{
    if (_type == "bool") return _value ? "true" : "false";
    return string(_value);
}


/// @func   csq_config_write_default_file()
/// @desc   Generate a fully commented ini from csq_config_spec(). Called only
///         when the file does not exist, so a user's edits are never clobbered.
/// @return {Bool} whether the file was written
function csq_config_write_default_file()
{
    var _spec = csq_config_spec();
    var _f = -1;

    try
    {
        _f = file_text_open_write(csq_config_filename());

        file_text_write_string(_f, "; ==========================================================");   file_text_writeln(_f);
        // Stamped with the mod identity rather than a literal, so a config file
        // attached to a bug report says which version generated it. Safe to call
        // across modules here for the same reason csq_config_load can call
        // csq_log_info: every csq_* global script is registered by the time any
        // object event runs.
        file_text_write_string(_f, ";  " + csq_mod_name() + " v" + csq_mod_version() + " configuration"); file_text_writeln(_f);
        file_text_write_string(_f, ";  Edit values, save, then restart the game.");                    file_text_writeln(_f);
        file_text_write_string(_f, ";  Delete this file to regenerate it with defaults.");             file_text_writeln(_f);
        file_text_write_string(_f, ";  Full reference: CONFIGURATION.md in the mod download.");        file_text_writeln(_f);
        file_text_write_string(_f, "; ==========================================================");   file_text_writeln(_f);

        var _current_section = "";
        for (var _i = 0; _i < array_length(_spec); _i++)
        {
            var _e = _spec[_i];

            if (_e.section != _current_section)
            {
                _current_section = _e.section;
                file_text_writeln(_f);
                file_text_write_string(_f, "[" + _current_section + "]");
                file_text_writeln(_f);
            }

            file_text_write_string(_f, "; " + _e.comment);
            file_text_writeln(_f);
            file_text_write_string(_f, _e.key + " = " + csq_config_format_value(_e.type, _e.def));
            file_text_writeln(_f);
        }

        file_text_close(_f);
        return true;
    }
    catch (_err)
    {
        // Never let a config problem stop the mod loading -- defaults are fine.
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
        return false;
    }
}


/// @func   csq_config_read_file()
/// @desc   Parse "key = value" lines, ignoring blanks, [sections] and
///         ; or # comments. Section headers are cosmetic; keys are unique.
/// @return {Struct} raw string values keyed by setting name
function csq_config_read_file()
{
    var _raw = {};
    var _f = -1;

    try
    {
        if (!file_exists(csq_config_filename())) return _raw;

        _f = file_text_open_read(csq_config_filename());

        while (!file_text_eof(_f))
        {
            var _line = string_trim(file_text_read_string(_f));
            file_text_readln(_f);

            if (_line == "") continue;

            var _first = string_char_at(_line, 1);
            if (_first == ";" || _first == "#" || _first == "[") continue;

            var _eq = string_pos("=", _line);
            if (_eq <= 1) continue;

            var _key = string_trim(string_copy(_line, 1, _eq - 1));
            var _val = string_trim(string_delete(_line, 1, _eq));

            if (_key != "") variable_struct_set(_raw, _key, _val);
        }

        file_text_close(_f);
    }
    catch (_err)
    {
        if (_f != -1)
        {
            try { file_text_close(_f); } catch (_ignored) {}
        }
    }

    return _raw;
}


/// @func   csq_config_load()
/// @desc   Populate global.csq_cfg_values from defaults, then overlay whatever
///         the ini provides. Always succeeds: a missing or malformed file just
///         means defaults. Safe to call more than once.
/// @return {Struct} the populated config struct
function csq_config_load()
{
    var _spec = csq_config_spec();
    var _created = false;

    if (!file_exists(csq_config_filename()))
    {
        _created = csq_config_write_default_file();
    }

    var _raw    = csq_config_read_file();
    var _values = {};
    var _missing = 0;

    for (var _i = 0; _i < array_length(_spec); _i++)
    {
        var _e     = _spec[_i];
        var _value = _e.def;

        if (variable_struct_exists(_raw, _e.key))
        {
            var _text = variable_struct_get(_raw, _e.key);

            switch (_e.type)
            {
                case "bool":
                    _value = csq_config_parse_bool(_text, _e.def);
                    break;

                case "real":
                    // Reject non-numeric text rather than feeding NaN downstream.
                    if (string_trim(_text) != "" && is_numeric(real(_text)))
                    {
                        _value = real(_text);
                    }
                    break;

                default:
                    _value = string_trim(_text);
                    break;
            }
        }
        else
        {
            _missing++;
        }

        variable_struct_set(_values, _e.key, _value);
    }

    global.csq_cfg_values = _values;

    // Logging is only available once csq_log has been initialised; csq_init
    // orders that before this call, so these lines are safe.
    if (_created)
    {
        csq_log_info("config: wrote default " + csq_config_filename());
    }
    if (_missing > 0)
    {
        csq_log_warn("config: " + string(_missing) + " key(s) absent from " +
                     csq_config_filename() + ", using defaults");
    }

    return _values;
}


/// @func   csq_cfg(_key)
/// @desc   Read one setting. Falls back to the spec default if config has not
///         been loaded yet, so callers never have to null-check.
function csq_cfg(_key)
{
    if (variable_global_exists("csq_cfg_values"))
    {
        if (variable_struct_exists(global.csq_cfg_values, _key))
        {
            return variable_struct_get(global.csq_cfg_values, _key);
        }
    }

    // Fallback: linear scan of the spec. Only reached before load, or for a
    // typo'd key, so the cost does not matter.
    var _spec = csq_config_spec();
    for (var _i = 0; _i < array_length(_spec); _i++)
    {
        if (_spec[_i].key == _key) return _spec[_i].def;
    }

    return undefined;
}
