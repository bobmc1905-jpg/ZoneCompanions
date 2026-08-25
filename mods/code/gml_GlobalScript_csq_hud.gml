// =============================================================================
//  Zone Companions  -  csq_hud
// -----------------------------------------------------------------------------
//  Draws the squad list and the optional debug overlay. csq_hud_draw is also the
//  mod's single Draw GUI entry point, so it calls csq_recruit_draw and
//  csq_reveal_draw on the way through -- see the note on it below.
//
//  COORDINATE SPACE IS 480x270
//  obj_controller_Draw_64 opens with display_set_gui_size(480, 270). It briefly
//  switches to 1920x1080 for the UI library at line 595 and switches straight
//  back at line 597, and every later draw in the event is in 480x270 space. This
//  module is appended at the very end of that event, so 480x270 is what it gets.
//
//  WHY VANILLA'S TEXT HELPERS AND NOT draw_text
//  language_set_font(0) selects the game's own small UI font -- the same call
//  vanilla's debug readout and minimap markers use. Picking a font asset by name
//  would be a guess, and would break for any language that swaps its font.
//  scr_draw_text_outlined then gives text a dark outline so it stays readable
//  over grass, snow and the existing HUD alike.
//
//  The reference mod built its own bitmap font from a sprite sheet and blitted
//  glyph by glyph. That works, but it cannot render non-Latin characters and
//  duplicates something the engine already does, so it is not repeated here.
//
//  DRAW STATE IS SAVED AND RESTORED
//  Other objects' Draw GUI events run after obj_controller's, and they inherit
//  whatever alignment, colour and font this module leaves behind. So every piece
//  of state this module touches is captured first and put back afterwards.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_hud_colour_ok()
/// @desc   Row colours. Plain BGR literals, matching vanilla's own draw calls
///         (obj_controller_Draw_64 passes 16777215 for white).
function csq_hud_colour_ok()      { return 16777215; }   // white
function csq_hud_colour_hurt()    { return 8454143;  }   // pale red
function csq_hud_colour_absent()  { return 8421504;  }   // grey
function csq_hud_colour_outline() { return 0;        }   // black

/// @func   csq_hud_colour_interact()
/// @desc   The colour vanilla uses for the interaction prompt you are actually
///         about to trigger. obj_controller_Draw_64 line 519 starts every entry in
///         global.list_interact at 16777215 and line 523 recolours the selected one
///         to this, which is also the tint of the s_hud_selector arrow beside it
///         (#FFF291). BGR 9564927 is RGB(255, 234, 145) -- a warm cream.
function csq_hud_colour_interact() { return 9564927; }   // pale gold

/// @func   csq_hud_colour_reveal()
/// @desc   The colour of the optional companion position pins.
///
///         White, the same as vanilla's own NPC markers at
///         obj_controller_Draw_64 line 822 onward. An earlier build tinted these
///         green to mark them as "mine"; the squad's vision is now shown by
///         clearing the fog rather than by painting coloured shapes over it, so
///         there is no longer any coloured overlay for a pin to match, and a pin
///         that looks like the game's own pins is the least intrusive option.
function csq_hud_colour_reveal()
{
    return 16777215;   // white
}


/// @func   csq_hud_max_hp(_inst)
/// @desc   A companion's maximum HP. NPCs have no hp_max variable -- that is a
///         player-only field -- so the mod remembers its own, in csq_hp_max.
///
///         Not npc_get_hp(npc_id): that returns the raw preset figure, which is
///         neither the hp_multiplier boost nor the difficulty scaling
///         obj_npc_human_parent_Alarm_9 applies. Using it made a full-health
///         companion read as 90/60. csq_ai_init_instance computes the real maximum
///         and csq_ai_step keeps it honest.
///
///         Falls back to the preset value for an instance that somehow has no
///         csq_hp_max -- better a slightly wrong denominator than no bar at all.
function csq_hud_max_hp(_inst)
{
    try
    {
        if (variable_instance_exists(_inst, "csq_hp_max") && _inst.csq_hp_max > 0)
        {
            return _inst.csq_hp_max;
        }

        return npc_get_hp(_inst.npc_id);
    }
    catch (_err)
    {
        return 0;
    }
}


/// @func   csq_hud_mode_label(_mode)
/// @desc   Player-facing name for an internal mode string.
function csq_hud_mode_label(_mode)
{
    if (_mode == csq_ai_mode_engage()) return "Fighting";
    if (_mode == csq_ai_mode_hold())   return "Holding";
    if (_mode == csq_ai_mode_medic())  return "Healing";
    return "Following";
}


/// @func   csq_hud_charge_text(_entry)
/// @desc   The remaining-heals marker for a roster row, or "" when the medic
///         ability is switched off.
///
///         Read from the roster entry rather than the instance, because that is
///         where the count lives -- an instance is destroyed at raid exit and
///         reported missing while the game has it deactivated, so an instance
///         variable would appear to reset itself. See csq_squad_make_entry.
///
///         Zero is shown as "+0" rather than hidden. When a companion stops
///         coming to patch you up, the reason should be visible on the panel
///         instead of looking like the feature broke.
function csq_hud_charge_text(_entry)
{
    if (!csq_cfg("heal_enabled")) return "";

    return "  +" + string(csq_squad_heal_charges(_entry));
}


/// @func   csq_hud_row_text(_index, _entry)
/// @desc   Build one roster line.
/// @return {Struct} {text, colour}
function csq_hud_row_text(_index, _entry)
{
    var _label  = string(_index + 1) + ". " + _entry.name;
    var _colour = csq_hud_colour_absent();

    if (!csq_alive(_entry.inst))
    {
        // On the roster but not in the world -- normal in the hub.
        return { text: _label + "  (waiting)", colour: _colour };
    }

    var _inst = _entry.inst;
    _colour   = csq_hud_colour_ok();

    if (csq_cfg("hud_show_hp"))
    {
        var _max = csq_hud_max_hp(_inst);
        var _hp  = floor(_inst.hp);

        if (_max > 0)
        {
            _label += "  " + string(_hp) + "/" + string(floor(_max));
            if (_hp < _max) _colour = csq_hud_colour_hurt();
        }
        else
        {
            _label += "  " + string(_hp);
        }
    }

    var _mode = "";
    try { _mode = string(_inst.csq_mode); } catch (_err) {}

    _label += csq_hud_charge_text(_entry);
    _label += "  [" + csq_hud_mode_label(_mode) + "]";

    return { text: _label, colour: _colour };
}


/// @func   csq_hud_short_state(_state)
/// @desc   A vanilla NPC state name with its "human_" prefix removed.
///
///         Every state a companion can be in is prefixed that way --
///         human_no_move, human_general, human_shoot -- so on the debug overlay the
///         prefix is six identical characters repeated on every line, twice per
///         line. Stripping it is the single biggest saving available, and nothing
///         is lost: the remainder is still unique.
function csq_hud_short_state(_state)
{
    var _s = string(_state);

    if (string_copy(_s, 1, 6) == "human_") _s = string_delete(_s, 1, 6);

    return _s;
}


/// @func   csq_hud_debug_text(_entry)
/// @desc   The extra diagnostic line drawn when draw_debug_overlay is on. Shows
///         the vanilla state alongside the mod's mode, which is the single most
///         useful thing when working out why a companion is misbehaving.
///
///         KEPT DELIBERATELY NARROW
///         The panel lives in 480x270 GUI space, so an 80-character line covers
///         most of the screen width. Labels are therefore single letters and the
///         state prefix is stripped:
///             no_move/no_move t- d34 s1.75 h0 r12,-8
///                 t  has a target (Y) or not (-)
///                 d  distance to the player, pixels
///                 s  path_speed
///                 h  frames left on the heal cooldown
///                 r  current roam offset from the formation slot
///         `target` is reported as a flag rather than the raw value because it is
///         an instance id -- six or seven digits that say nothing once presence is
///         known. csq_squad_dump (F9) still logs the real id.
function csq_hud_debug_text(_entry)
{
    if (!csq_alive(_entry.inst)) return "";

    var _inst = _entry.inst;
    var _text = "";

    try
    {
        var _player = csq_player();
        var _dist   = (_player == noone) ? -1
                    : floor(point_distance(_inst.x, _inst.y, _player.x, _player.y));

        var _tgt = (_inst.target == noone || _inst.target == -4) ? "-" : "Y";

        _text = "  " + csq_hud_short_state(_inst.state) +
                "/"  + csq_hud_short_state(_inst.human_state_now) +
                " t"  + _tgt +
                " d"  + string(_dist) +
                " s"  + string(_inst.path_speed) +
                " h"  + string(_inst.csq_heal_cd) +
                " r"  + string(floor(_inst.csq_roam_x)) + "," +
                        string(floor(_inst.csq_roam_y));
    }
    catch (_err)
    {
        _text = "  <debug read failed>";
    }

    return _text;
}


/// @func   csq_hud_visible()
/// @desc   Whether the panel should be drawn right now.
///
///         Two switches, deliberately separate:
///           hud_enabled        the config master switch. Off means the player
///                              never wants the panel, and the toggle key does
///                              nothing.
///           global.csq_hud_shown  the runtime toggle, flipped by the key.
///
///         The runtime flag is defaulted lazily here rather than in csq_boot, so
///         there is no boot-order dependency -- the same idiom csq_squad_init
///         uses. It is deliberately NOT persisted: it is a runtime toggle, not a
///         setting, and the mod never writes to csq_config_user.ini, so saving it
///         would mean editing the player's own file behind their back. The panel is
///         therefore shown again on every launch.
function csq_hud_visible()
{
    if (!variable_global_exists("csq_hud_shown"))
    {
        global.csq_hud_shown = true;
    }

    return csq_cfg("hud_enabled") && global.csq_hud_shown;
}


/// @func   csq_hud_toggle()
/// @desc   Flip the panel on or off. Bound to key_toggle_hud.
/// @return {Bool} the new visibility
function csq_hud_toggle()
{
    // Reads through csq_hud_visible first so the global is created if this is the
    // first time anything has asked.
    csq_hud_visible();

    if (!csq_cfg("hud_enabled"))
    {
        // A key that does nothing is indistinguishable from a broken mod, so say
        // why. INFO rather than DEBUG: the player pressed a key and deserves an
        // answer without first editing the config.
        csq_log_info("hud: toggle ignored, hud_enabled is off in the config");
        return false;
    }

    global.csq_hud_shown = !global.csq_hud_shown;
    csq_log_info("hud: panel " + (global.csq_hud_shown ? "shown" : "hidden"));

    return global.csq_hud_shown;
}


/// @func   csq_hud_draw()
/// @desc   The mod's only Draw GUI entry point, appended to the end of
///         obj_controller_Draw_64. Renders the squad panel, and first hands over to
///         csq_recruit_draw and csq_reveal_draw, both of which have to work when the
///         panel itself is hidden or the roster is empty.
///
///         Never throws: a HUD problem must not take the whole draw event down,
///         because obj_controller draws the real UI.
function csq_hud_draw()
{
    try
    {
        // The recruiter prompt and hire menu draw independently of the squad panel
        // -- they must show even with an empty roster, and while the panel is
        // toggled off -- so they run before the panel's own early-outs below.
        // csq_recruit_draw guards itself and never throws.
        csq_recruit_draw();

        // Same reasoning: "where is my companion" has to answer itself with the
        // panel hidden, and it is the one overlay that must survive fog of war.
        csq_reveal_draw();

        if (!csq_hud_visible())      return;
        if (csq_squad_count() == 0)  return;

        // Suppress in menus and on the map screen, where the panel would sit on
        // top of real UI. Companions only matter in the world.
        if (!csq_in_raid() && !csq_in_hub()) return;

        // ---- capture draw state -----------------------------------------
        var _old_font   = draw_get_font();
        var _old_colour = draw_get_color();
        var _old_alpha  = draw_get_alpha();

        // ---- set our own -------------------------------------------------
        // Index 0 is the small UI font vanilla uses for its own debug readout.
        try { language_set_font(0); } catch (_err) {}

        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
        draw_set_alpha(1);

        var _x      = csq_cfg("hud_x");
        var _y      = csq_cfg("hud_y");

        // arg5 of scr_draw_text_outlined is a scale, handed straight to
        // draw_text_transformed_color. Clamped so a typo in the ini cannot make the
        // panel invisible or fill the screen.
        var _scale  = clamp(csq_cfg("hud_scale"), 0.25, 4);

        // Row spacing follows the scale, or shrinking the text would leave the rows
        // as far apart as before and save nothing.
        var _line   = max(4, round(csq_cfg("hud_line_height") * _scale));

        // The outline is a pixel offset, not a scale, so it grows with the text but
        // never drops below one -- a sub-pixel outline just disappears. Vanilla
        // follows the same rule, passing (1, 1), (2, 2) and (3, 3).
        var _out    = max(1, round(_scale));

        var _debug  = csq_cfg("debug_enabled") && csq_cfg("draw_debug_overlay");
        var _count  = csq_squad_count();

        // Header. Only mentions Hold when it is on, so the normal case is quiet.
        var _header = "Squad " + string(csq_squad_active_count()) + "/" + string(_count);
        if (global.csq_squad_hold) _header += "  - HOLD";

        scr_draw_text_outlined(_x, _y, _header,
                               csq_hud_colour_ok(), csq_hud_colour_outline(), _scale, _out);

        _y += _line;

        for (var _i = 0; _i < _count; _i++)
        {
            var _entry = csq_squad_entry(_i);
            if (is_undefined(_entry)) continue;

            var _row = csq_hud_row_text(_i, _entry);

            scr_draw_text_outlined(_x, _y, _row.text,
                                   _row.colour, csq_hud_colour_outline(), _scale, _out);
            _y += _line;

            if (_debug)
            {
                var _dbg = csq_hud_debug_text(_entry);
                if (_dbg != "")
                {
                    scr_draw_text_outlined(_x, _y, _dbg,
                                           csq_hud_colour_absent(), csq_hud_colour_outline(), _scale, _out);
                    _y += _line;
                }
            }
        }

        // ---- restore draw state ------------------------------------------
        draw_set_alpha(_old_alpha);
        draw_set_color(_old_colour);
        draw_set_font(_old_font);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }
    catch (_err)
    {
        csq_log_exception("csq_hud_draw", _err);
    }
}
