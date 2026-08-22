// =============================================================================
//  Zone Companions  -  csq_input
// -----------------------------------------------------------------------------
//  Keyboard commands. Deliberately the thinnest module in the mod: it reads keys
//  and calls into csq_squad. No game logic lives here.
//
//  WHY FUNCTION KEYS BY DEFAULT
//  ZERO Sievert has no public keybinding registry a mod can politely add to, and
//  it does not expose its own bindings in a form this mod can safely read. So
//  rather than guess at a free letter key and risk stealing one the player uses
//  for a weapon slot or a consumable, the defaults are F5-F9 -- keys the base
//  game does not bind. All five are configurable as virtual key codes.
//
//  F5 IS FREE, CHECKED RATHER THAN ASSUMED
//  Vanilla does reference F5 and F6, but never on their own: player_step_debug_keys
//  line 36 needs Ctrl+F5 and line 49 Ctrl+F6, obj_main_menu_Step_0 line 52 needs
//  Ctrl+F5, and obj_map_generator_Step_0 line 25 needs F6 and F5 together. Every
//  other vk_f* in the decompile is an entry in a Catspeak constant table, not a
//  binding. So a bare F5 press reaches nothing in the base game -- the same reason
//  F6-F9 were already safe.
//
//  WHY keyboard_check_pressed AND NOT keyboard_check
//  Every command here is a discrete action, not a held state. keyboard_check
//  would fire once per frame, so a single tap of F6 would try to recruit sixty
//  companions a second.
//
//  WHERE THIS IS CALLED FROM
//  obj_player_Step_0, which the GMLoader ZERO Sievert guide documents as running
//  every tick in both hub and raid. That means commands work in both places --
//  recruiting in the hub adds to the roster and the companion appears at the
//  start of the next raid.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_input_key(_setting)
/// @desc   Read a keybind from config as a virtual key code. A key code of 0 (or
///         anything out of range) disables that command, which is how a player
///         turns off a binding they do not want.
/// @return {Real} virtual key code, or 0 for "disabled"
function csq_input_key(_setting)
{
    var _code = csq_cfg(_setting);

    if (is_undefined(_code) || !is_numeric(_code)) return 0;

    _code = floor(_code);
    if (_code <= 0 || _code > 255) return 0;

    return _code;
}


/// @func   csq_input_pressed(_setting)
/// @desc   Whether the key bound to _setting was pressed this frame.
function csq_input_pressed(_setting)
{
    var _code = csq_input_key(_setting);
    if (_code == 0) return false;

    try
    {
        return keyboard_check_pressed(_code);
    }
    catch (_err)
    {
        // A bad key code should disable the binding, not break the step event.
        csq_log_exception("csq_input_pressed(" + string(_setting) + ")", _err);
        return false;
    }
}


/// @func   csq_input_ui_states()
/// @desc   The player states in which the player is not walking the world under
///         keyboard control, so a mod command must not fire. Built once and
///         cached, because csq_input_blocked runs every frame and rebuilding an
///         array of structs per frame is pure garbage.
///
///         player_execute_state() runs script_execute(state) in
///         obj_player_Step_0, and UI flows set it through
///         player_set_local_state(), so `state` is the game's own record of
///         whether the player is in control or sitting in a menu.
/// @return {Array} array of {name, ref}
function csq_input_ui_states()
{
    if (variable_global_exists("csq_input_ui_state_list") &&
        is_array(global.csq_input_ui_state_list))
    {
        return global.csq_input_ui_state_list;
    }

    var _list = [];

    try
    {
        _list = [
            { name: "inventory",   ref: scr_player_state_inventory   },
            { name: "pda",         ref: scr_player_state_pda         },
            { name: "talk",        ref: scr_player_state_talk        },
            { name: "craft",       ref: scr_player_state_craft       },
            { name: "item_spawn",  ref: scr_player_state_item_spawn  },
            { name: "sleep",       ref: scr_player_state_sleep       },
            { name: "dead",        ref: scr_player_state_dead        },
            { name: "start",       ref: scr_player_state_start       },
            { name: "dummy",       ref: scr_player_state_dummy       },
            { name: "free_camera", ref: scr_player_state_free_camera },
            { name: "teleport",    ref: scr_player_state_teleport    }
        ];
    }
    catch (_err)
    {
        // If any of those scripts is missing, an empty list means "never
        // blocked", which is the safe direction -- see the fail-open note below.
        _list = [];
    }

    global.csq_input_ui_state_list = _list;
    return _list;
}


/// @func   csq_input_blocked()
/// @desc   Suppress commands while the player is not in control, so a keybind
///         cannot fire behind a menu, a dialogue, or the Steam overlay.
///
///         WHAT THIS DELIBERATELY DOES NOT USE
///         An earlier version tested `keyboard_string != ""` as an "a text field
///         has focus" signal. That was wrong, and it silently disabled every
///         keybind in the mod. GameMaker's keyboard_string is a *persistent*
///         buffer holding the last 1024 printable characters typed; it is cleared
///         only by assigning "" to it, and ZERO Sievert never assigns to it (the
///         sole vanilla reference is a Catspeak binding). So the first time the
///         player pressed W, A, S or D to walk, keyboard_string became non-empty
///         and stayed non-empty for the rest of the session, and csq_input_step
///         returned early on every frame from then on.
///
///         WHAT IT USES INSTEAD
///          * steam_is_overlay_activated(), which is exactly the signal vanilla's
///            own update_keyboard_input() uses to drop input.
///          * The player's `state` script -- see csq_input_ui_states().
///
///         Unknown or unrecognised states fail OPEN, i.e. commands are allowed.
///         The failure this replaces was "keys silently never work", which is far
///         worse than a command firing during a state nobody classified.
/// @return {Bool} whether commands should be suppressed this frame
function csq_input_blocked()
{
    var _reason = "";

    try
    {
        // Vanilla drops all input while the Steam overlay is up; match that.
        if (steam_is_overlay_activated()) _reason = "steam overlay";
    }
    catch (_err)
    {
        // Unavailable outside a Steam build. Not a reason to block.
    }

    if (_reason == "")
    {
        try
        {
            var _p = csq_player();

            if (_p == noone)
            {
                _reason = "no local player";
            }
            else
            {
                var _states = csq_input_ui_states();

                for (var _i = 0; _i < array_length(_states); _i++)
                {
                    if (_p.state == _states[_i].ref)
                    {
                        _reason = "player state " + _states[_i].name;
                        break;
                    }
                }
            }
        }
        catch (_err)
        {
            // Fail open.
            _reason = "";
        }
    }

    // Report only when the answer changes. csq_log opens the log file on every
    // call, so an unconditional DEBUG line here would mean a file open per frame.
    // Logging the transition is what makes a silent block diagnosable at all --
    // the absence of exactly this line is why the keyboard_string bug above
    // needed a play session and a decompile to find.
    if (!variable_global_exists("csq_input_block_reason"))
    {
        global.csq_input_block_reason = "";
    }

    if (_reason != global.csq_input_block_reason)
    {
        global.csq_input_block_reason = _reason;

        if (_reason == "") csq_log_debug("input: commands enabled");
        else               csq_log_debug("input: commands suppressed (" + _reason + ")");
    }

    return (_reason != "");
}


/// @func   csq_input_recruit()
/// @desc   Add a companion built from the configured preset.
function csq_input_recruit()
{
    csq_log_debug("input: recruit key pressed");

    if (!csq_squad_recruit(csq_cfg("default_preset")))
    {
        csq_log_debug("input: recruit declined (roster full?)");
    }
}


/// @func   csq_input_dismiss()
/// @desc   Remove the companion nearest the player, permanently.
function csq_input_dismiss()
{
    csq_log_debug("input: dismiss key pressed");

    var _index = csq_squad_nearest_index();

    if (_index < 0)
    {
        csq_log_info("squad: nothing to dismiss, roster is empty");
        return;
    }

    csq_squad_remove_at(_index);
}


/// @func   csq_input_step()
/// @desc   Poll every binding once per frame. Called from csq_tick, which is
///         appended to obj_player_Step_0.
function csq_input_step()
{
    if (csq_input_blocked()) return;

    if (csq_input_pressed("key_recruit"))     csq_input_recruit();
    if (csq_input_pressed("key_dismiss"))     csq_input_dismiss();
    if (csq_input_pressed("key_toggle_hold")) csq_squad_toggle_hold();
    if (csq_input_pressed("key_toggle_hud"))  csq_hud_toggle();

    // The debug dump works regardless of debug_enabled -- it is the tool a player
    // reaches for when reporting a problem, so it must not need a config edit
    // first. csq_squad_dump logs at INFO for the same reason.
    if (csq_input_pressed("key_debug_dump"))  csq_squad_dump();
}
