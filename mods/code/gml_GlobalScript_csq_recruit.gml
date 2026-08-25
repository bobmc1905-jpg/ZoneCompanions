// =============================================================================
//  Zone Companions  -  csq_recruit
// -----------------------------------------------------------------------------
//  The paid recruitment feature: an NPC by the bar in the bunker, and the hire
//  menu the player drives to buy companions at a chosen difficulty tier.
//
//  WHY THE MENU IS THE MOD'S OWN, NOT THE GAME'S DIALOGUE UI
//  ZERO Sievert's dialogue windows are laid out by external Catspeak .ui files
//  (ui/npc.ui and friends) that are not part of the decompiled export, and the
//  vanilla renderer only understands the dia_type values those files declare. A
//  custom purchase flow cannot be expressed through them without shipping and
//  loading a .ui the mod does not have. So the menu is drawn with the mod's own
//  csq_hud text helpers, in the same 480x270 GUI space, and navigated with the
//  mod's own keyboard handling -- exactly the systems the squad panel already uses.
//
//  HOW THE PLAYER IS FROZEN WHILE THE MENU IS OPEN
//  Opening the menu puts the player in scr_player_state_talk, which is already in
//  csq_input's blocked-state list -- so every other mod keybind is suppressed and
//  the player stops walking. That state's whole body is "stop aiming, show the
//  mouse" (verified), so it is safe to sit in with no speaker and renders nothing
//  on its own. Closing restores scr_player_state_move.
//
//  MONEY IS DEDUCTED DIRECTLY, NOT VIA trader_transfer_money
//  trader_transfer_money(undefined, ...) reassigns arg0 = global.speaker_nearest
//  and then dereferences arg0.npc_id for a reputation gain. The recruiter is not a
//  registered speaker, so global.speaker_nearest is -4 here and that deref would be
//  fatal. Instead this subtracts global.player_money directly and persists it with
//  the game's own scr_save_player_status(), gated behind csq_persist_probe() so no
//  db_* call can fire against an unloaded save (see csq_persist's safety note).
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_recruit_step_size()
/// @desc   Menu step ids. Kept as functions so no caller compares raw numbers.
function csq_recruit_step_size()    { return 1; }   // choose how many
function csq_recruit_step_tier()    { return 2; }   // choose difficulty
function csq_recruit_step_confirm() { return 3; }   // review and buy


/// @func   csq_recruit_init()
/// @desc   Lazily create the menu-state globals. Same idiom as csq_squad_init:
///         safe to call every frame, never resets an open menu.
function csq_recruit_init()
{
    if (!variable_global_exists("csq_recruit_open"))      global.csq_recruit_open      = false;
    if (!variable_global_exists("csq_recruit_step"))      global.csq_recruit_step      = csq_recruit_step_size();
    if (!variable_global_exists("csq_recruit_sel_count")) global.csq_recruit_sel_count = 1;
    if (!variable_global_exists("csq_recruit_sel_tier"))  global.csq_recruit_sel_tier  = 0;
    if (!variable_global_exists("csq_recruit_near"))       global.csq_recruit_near      = false;
    if (!variable_global_exists("csq_recruit_preset_warned")) global.csq_recruit_preset_warned = {};
}

/// @func   csq_recruit_enabled()
function csq_recruit_enabled()
{
    return csq_cfg("recruiter_enabled");
}


/// @func   csq_recruit_tier_count()
/// @desc   How many tiers the menu offers, clamped to the three the config defines.
function csq_recruit_tier_count()
{
    return csq_clamp_int(csq_cfg("recruit_tier_count"), 1, 3);
}


/// @func   csq_recruit_tier(_i)
/// @desc   One tier's definition, read straight from config. _i is 0-based.
/// @return {Struct} {name, preset, hp_mult, price}
function csq_recruit_tier(_i)
{
    var _n = string(_i + 1);   // config keys are 1-based: recruit_tier1_*

    return {
        name:    string(csq_cfg("recruit_tier" + _n + "_name")),
        preset:  string(csq_cfg("recruit_tier" + _n + "_preset")),
        hp_mult: max(0.1, csq_cfg("recruit_tier" + _n + "_hp_mult")),
        price:   max(0, floor(csq_cfg("recruit_tier" + _n + "_price")))
    };
}


/// @func   csq_recruit_preset_exists(_preset)
/// @desc   Whether a preset id is a real entry in global.npc_data. Checked BEFORE
///         any use, because npc_get_hp (and everything that calls it) ends in a
///         fatal, uncatchable trace_error for an unknown id -- see npc_get_hp.
function csq_recruit_preset_exists(_preset)
{
    try
    {
        if (!variable_global_exists("npc_data") || !is_struct(global.npc_data)) return false;
        return is_struct(variable_struct_get(global.npc_data, string(_preset)));
    }
    catch (_err)
    {
        return false;
    }
}


/// @func   csq_recruit_resolve_preset(_preset)
/// @desc   Return _preset if the game knows it, otherwise fall back to
///         default_preset. Warns once per bad id so a typo in the ini is visible
///         without spamming the log every spawn.
function csq_recruit_resolve_preset(_preset)
{
    _preset = string(_preset);

    if (csq_recruit_preset_exists(_preset)) return _preset;

    var _fallback = string(csq_cfg("default_preset"));

    csq_recruit_init();
    if (!variable_struct_exists(global.csq_recruit_preset_warned, _preset))
    {
        global.csq_recruit_preset_warned[$ _preset] = true;
        csq_log_warn("recruit: preset '" + _preset + "' is not in gamedata, " +
                     "falling back to '" + _fallback + "'");
    }

    // If even the configured default is unknown, hand back the raw value and let
    // the caller's own guard deal with it -- there is nothing safer left to try.
    if (csq_recruit_preset_exists(_fallback)) return _fallback;

    return _preset;
}


/// @func   csq_recruit_available_slots()
/// @desc   How many more companions the roster can hold right now.
function csq_recruit_available_slots()
{
    return max(0, csq_squad_max() - csq_squad_count());
}

/// @func   csq_recruit_spawn_npc()
/// @desc   Place the recruiter in the hub, once.
///
///         THE ANCHOR IS THE BAR'S TRADE MARKER, NOT A VISIBLE BARMAN
///         There is no barman sprite to stand beside: the bar's speaker entry sets
///         speaker_sprite_idle = s_vuoto and obj_trader_Draw_0 skips drawing
///         entirely for that sprite, so the barman the player sees is part of the
///         room art. obj_tradr_bar -- IsVisible false, an 8x8 mask running
///         npc_setup("barman") -- is the only live instance that marks the bar, and
///         it sits back at the counter. So the offset has to carry the recruiter
///         OUT from the counter into the floor space the player walks in, which is
///         why recruiter_offset_y defaults positive (down, toward the camera).
///
///         Idempotent: instance_number gates re-creation, and the instance is
///         destroyed automatically by the room change when the player leaves the
///         hub, so the next hub visit recreates it.
function csq_recruit_spawn_npc()
{
    if (!csq_recruit_enabled()) return;
    if (!csq_in_hub())          return;

    // Already placed this visit.
    if (instance_number(obj_csq_recruiter) > 0) return;

    // Wait until the barman exists, so the anchor is available.
    if (!instance_exists(obj_tradr_bar))
    {
        return;
    }

    try
    {
        var _barman = instance_find(obj_tradr_bar, 0);
        if (!instance_exists(_barman)) return;

        var _tx = _barman.x + csq_cfg("recruiter_offset_x");
        var _ty = _barman.y + csq_cfg("recruiter_offset_y");

        // The recruiter is not solid, so an imperfect spot costs nothing
        // mechanically -- but standing inside the counter or a shelf means the
        // furniture draws over him and the player sees nobody. csq_recruit_clear_spot
        // steps him out to open floor.
        var _inst = instance_create_depth(_tx, _ty, 0, obj_csq_recruiter);

        if (instance_exists(_inst))
        {
            if (csq_cfg("recruiter_avoid_furniture")) csq_recruit_clear_spot(_inst);

            // After clear_spot, so the label sits over where he actually ended up.
            csq_recruit_marker_sync(_inst);

            csq_log_info("recruit: recruiter placed at " +
                         string(floor(_inst.x)) + "," + string(floor(_inst.y)) +
                         " (bar marker " + string(floor(_barman.x)) + "," +
                         string(floor(_barman.y)) + ", offset " +
                         string(floor(_tx)) + "," + string(floor(_ty)) + ")");

            // Everything a "he is not there" report needs, in one line.
            csq_log_debug("recruit: recruiter sprite=" + string(sprite_get_name(_inst.sprite_index)) +
                          " alpha=" + string(_inst.image_alpha) +
                          " visible=" + string(_inst.visible) +
                          " depth=" + string(_inst.depth) +
                          " state=" + string(_inst.state));
        }
        else
        {
            csq_log_warn("recruit: instance_create_depth returned no recruiter");
        }
    }
    catch (_err)
    {
        csq_log_exception("csq_recruit_spawn_npc", _err);
    }
}


/// @func   csq_recruit_clear_spot(_inst)
/// @desc   Move _inst off any bar furniture it was placed inside. Everything solid
///         in the bunker -- counter, shelves, walls, tables -- descends from
///         obj_solid, and place_meeting against a parent object tests all its
///         children, so one check covers the lot.
///
///         Candidates are tried straight down first (out from behind the counter,
///         toward the player's side of the bar), then down-and-sideways, then the
///         rest of the ring, so the recruiter ends up where a customer would stand
///         rather than tucked behind the bar. Gives up quietly after the last ring:
///         a cosmetically poor spot is much better than no recruiter.
function csq_recruit_clear_spot(_inst)
{
    with (_inst)
    {
        if (!place_meeting(x, y, obj_solid)) return;

        var _sx = x, _sy = y;

        // dx, dy pairs in preference order, scaled by the ring radius.
        var _dirs = [[0, 1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [-1, -1], [1, -1]];

        for (var _r = 16; _r <= 96; _r += 16)
        {
            for (var _d = 0; _d < array_length(_dirs); _d++)
            {
                var _cx = _sx + (_dirs[_d][0] * _r);
                var _cy = _sy + (_dirs[_d][1] * _r);

                if (!place_meeting(_cx, _cy, obj_solid))
                {
                    x = _cx;
                    y = _cy;
                    csq_log_debug("recruit: offset spot was inside furniture, moved " +
                                  string(_r) + "px to " + string(floor(x)) + "," + string(floor(y)));
                    return;
                }
            }
        }

        csq_log_warn("recruit: no clear floor within 96px of the offset; leaving the " +
                     "recruiter at " + string(floor(x)) + "," + string(floor(y)) +
                     " (raise recruiter_depth_bias if he is hidden)");
    }
}


/// @func   csq_recruit_marker_sync(_inst)
/// @desc   Give the recruiter the same floating name label the Barman, the Doctor
///         and the Networker have.
///
///         HOW VANILLA DRAWS THOSE LABELS
///         init_npc_marker fills an obj_controller array, arr_npc_marker, with
///         {x, y, text, draw_x, draw_y} structs -- literally
///         `new npc_marker(590, 872, "Barman")` and five more. Near the end of
///         obj_controller_Draw_64, for every entry that passes
///         teleport_allowed(text), the event draws the s_minimap_marker pin at the
///         entry's world position and the text 15px above it; entries off the edge
///         of the view get a rotated arrow instead, eased with a lerp on draw_x and
///         draw_y. All of that comes for free by appending one entry, along with
///         three gates worth having: the whole block is wrapped in the player's own
///         settings_get("display_npc_marker"), it only runs in
///         scr_player_state_move (so the label vanishes while the hire menu is up),
///         and an entry with y < 1146 is skipped while the player is outside the
///         bunker. Nothing else reads arr_npc_marker -- the fast-travel menu is
///         driven by ui/modal_teleport.ui, which does not touch it -- so a new
///         entry adds a label and nothing more.
///
///         A PLAIN STRUCT, NOT new npc_marker()
///         The draw code only ever reads .text, .x, .y, .draw_x and .draw_y and
///         tests is_struct(), and npc_marker's constructor body is exactly those
///         five fields. A literal struct is field-identical and does not depend on
///         a vanilla constructor name resolving from mod scope.
///
///         teleport_allowed() ends in `return true`, so an unrecognised label like
///         "Labour Contracts" is allowed by its default arm; language_get_string()
///         likewise hands back an unknown string unchanged, so the label renders as
///         typed in every language.
///
///         Called once per hub visit, straight after placement. Existing entries are
///         matched by text and updated in place rather than appended, because
///         obj_controller survives the room change on some paths and duplicates
///         would stack one label on top of another.
function csq_recruit_marker_sync(_inst)
{
    if (!csq_cfg("recruiter_marker_enabled")) return;

    try
    {
        if (!instance_exists(_inst))       return;
        if (!instance_exists(obj_controller)) return;

        var _ctrl = instance_find(obj_controller, 0);
        if (!instance_exists(_ctrl)) return;

        // Vanilla creates this in obj_controller's Create event. If a future patch
        // renames or removes it, do nothing rather than inventing the variable --
        // an array only this mod writes to would never be drawn.
        if (!variable_instance_exists(_ctrl, "arr_npc_marker")) return;
        if (!is_array(_ctrl.arr_npc_marker))                    return;

        var _text = string(csq_cfg("recruiter_marker_text"));
        if (_text == "") return;

        var _mx = _inst.x;
        var _my = _inst.y + csq_cfg("recruiter_marker_offset_y");

        var _arr = _ctrl.arr_npc_marker;

        for (var _i = 0; _i < array_length(_arr); _i++)
        {
            var _m = _arr[_i];

            if (!is_struct(_m)) continue;
            if (!variable_struct_exists(_m, "text")) continue;
            if (string(_m.text) != _text) continue;

            // Already registered this session -- move it, do not add a second one.
            _m.x = _mx;
            _m.y = _my;

            // draw_x/draw_y cache the eased off-screen arrow position. Left at a
            // stale value the arrow slides across the screen from the old spot.
            _m.draw_x = _mx;
            _m.draw_y = _my;

            csq_log_debug("recruit: name label '" + _text + "' moved to " +
                          string(floor(_mx)) + "," + string(floor(_my)));
            return;
        }

        array_push(_ctrl.arr_npc_marker, {
            x:      _mx,
            y:      _my,
            text:   _text,
            draw_x: _mx,
            draw_y: _my
        });

        csq_log_info("recruit: name label '" + _text + "' registered at " +
                     string(floor(_mx)) + "," + string(floor(_my)) +
                     " (" + string(array_length(_ctrl.arr_npc_marker)) + " marker(s) total)");
    }
    catch (_err)
    {
        // A missing label is cosmetic. Never let it stop the recruiter appearing.
        csq_log_exception("csq_recruit_marker_sync", _err);
    }
}


/// @func   csq_recruit_instance()
/// @desc   The live recruiter, or noone. Used by the prompt to anchor itself.
function csq_recruit_instance()
{
    if (instance_number(obj_csq_recruiter) <= 0) return noone;

    var _inst = instance_find(obj_csq_recruiter, 0);
    if (!instance_exists(_inst)) return noone;

    return _inst;
}


/// @func   csq_recruit_player_near()
/// @desc   Whether the player is close enough to the recruiter to interact.
function csq_recruit_player_near()
{
    if (!csq_recruit_enabled()) return false;
    if (!csq_in_hub())          return false;

    var _p = csq_player();
    if (_p == noone) return false;

    if (instance_number(obj_csq_recruiter) <= 0) return false;

    try
    {
        var _rec = instance_nearest(_p.x, _p.y, obj_csq_recruiter);
        if (!instance_exists(_rec)) return false;

        var _range = max(8, csq_cfg("recruiter_range"));
        return point_distance(_p.x, _p.y, _rec.x, _rec.y) <= _range;
    }
    catch (_err)
    {
        return false;
    }
}


/// @func   csq_recruit_toast(_msg)
/// @desc   A short on-screen message via the game's own text box, with a log
///         fallback if that routine is unavailable.
function csq_recruit_toast(_msg)
{
    try   { scr_draw_text_with_box(_msg, false); }
    catch (_err) { csq_log_debug("recruit toast: " + string(_msg)); }
}


/// @func   csq_recruit_open_menu()
/// @desc   Open the hire menu at the first step and freeze the player. Declines
///         with a message when the roster is already full.
function csq_recruit_open_menu()
{
    csq_recruit_init();
    if (!csq_recruit_enabled()) return;

    var _avail = csq_recruit_available_slots();
    if (_avail <= 0)
    {
        csq_recruit_toast("Your squad is already full (" + string(csq_squad_max()) + ").");
        csq_log_info("recruit: menu not opened, roster full");
        return;
    }

    global.csq_recruit_open      = true;
    global.csq_recruit_step      = csq_recruit_step_size();
    global.csq_recruit_sel_count = 1;
    global.csq_recruit_sel_tier  = clamp(global.csq_recruit_sel_tier, 0, csq_recruit_tier_count() - 1);

    // Freeze the player. talk is already in csq_input's blocked-state list, so this
    // also suppresses every other mod keybind while the menu is up.
    try { player_set_local_state(scr_player_state_talk); }
    catch (_err) { csq_log_exception("csq_recruit_open_menu(freeze)", _err); }

    csq_log_debug("recruit: menu opened, " + string(_avail) + " slot(s) free");
}


/// @func   csq_recruit_close_menu()
/// @desc   Close the menu and hand control back, but only if the player is still
///         in the talk state this mod put them in -- never stomp another state.
function csq_recruit_close_menu()
{
    csq_recruit_init();
    if (!global.csq_recruit_open) return;

    global.csq_recruit_open = false;

    try
    {
        var _p = csq_player();
        if (_p != noone && _p.state == scr_player_state_talk)
        {
            player_set_local_state(scr_player_state_move);
        }
    }
    catch (_err) { csq_log_exception("csq_recruit_close_menu(restore)", _err); }

    csq_log_debug("recruit: menu closed");
}


/// @func   csq_recruit_tick()
/// @desc   Per-frame driver, called from csq_tick. Places the recruiter in the
///         hub, tracks proximity for the prompt, and runs the menu when open.
///         A no-op outside the hub or when the feature is disabled.
function csq_recruit_tick()
{
    csq_recruit_init();

    try
    {
        if (!csq_recruit_enabled() || !csq_in_hub())
        {
            if (global.csq_recruit_open) csq_recruit_close_menu();
            global.csq_recruit_near = false;
            return;
        }

        csq_recruit_spawn_npc();

        global.csq_recruit_near = csq_recruit_player_near();

        if (global.csq_recruit_open) csq_recruit_menu_input();
    }
    catch (_err)
    {
        csq_log_exception("csq_recruit_tick", _err);
    }
}


/// @func   csq_recruit_menu_input()
/// @desc   Keyboard handling while the menu is open. The four actions -- up, down,
///         confirm, back -- are configurable virtual key codes (see the [recruit]
///         section), read through csq_input_pressed exactly like the world binds.
///         The up/down arrows are kept as fixed aliases for the configured keys, so
///         a player who reaches for the arrows is not stuck. These are read here
///         rather than in csq_input_step because the player is frozen in the talk
///         state while the menu is up -- that state is on csq_input's blocked list,
///         so the world binds are suppressed and these keys reach nothing else.
///         Confirm advances,
///         back steps back (and closes from the first step), so a purchase always
///         takes a deliberate second confirm on the summary -- no buying by accident.
function csq_recruit_menu_input()
{
    var _up    = csq_input_pressed("recruit_key_up")   || keyboard_check_pressed(vk_up);
    var _down  = csq_input_pressed("recruit_key_down") || keyboard_check_pressed(vk_down);
    var _enter = csq_input_pressed("recruit_key_confirm");
    var _back  = csq_input_pressed("recruit_key_back");

    var _step = global.csq_recruit_step;

    if (_step == csq_recruit_step_size())
    {
        var _avail = csq_recruit_available_slots();
        if (_avail < 1) { csq_recruit_close_menu(); return; }

        if (_up)   global.csq_recruit_sel_count = min(_avail, global.csq_recruit_sel_count + 1);
        if (_down) global.csq_recruit_sel_count = max(1,      global.csq_recruit_sel_count - 1);
        global.csq_recruit_sel_count = clamp(global.csq_recruit_sel_count, 1, _avail);

        if (_enter)
        {
            global.csq_recruit_step = csq_recruit_step_tier();
            csq_log_debug("recruit: step -> tier, count=" + string(global.csq_recruit_sel_count));
        }
        else if (_back) csq_recruit_close_menu();
    }
    else if (_step == csq_recruit_step_tier())
    {
        var _tc = csq_recruit_tier_count();

        // The tiers are drawn as a top-to-bottom list, cheapest first, so "up" has
        // to move the highlight toward the TOP of that list -- which is a lower
        // index. Incrementing on up (the obvious reading of "up means more") made
        // W walk down the list and S walk up it.
        if (_up)   global.csq_recruit_sel_tier = max(0,       global.csq_recruit_sel_tier - 1);
        if (_down) global.csq_recruit_sel_tier = min(_tc - 1, global.csq_recruit_sel_tier + 1);

        if (_enter)
        {
            global.csq_recruit_step = csq_recruit_step_confirm();
            csq_log_debug("recruit: step -> confirm, tier=" + string(global.csq_recruit_sel_tier));
        }
        else if (_back) global.csq_recruit_step = csq_recruit_step_size();
    }
    else if (_step == csq_recruit_step_confirm())
    {
        if (_enter)     csq_recruit_confirm();
        else if (_back) global.csq_recruit_step = csq_recruit_step_tier();
    }
}


/// @func   csq_recruit_total_cost()
/// @desc   Price for the current selection: tier price times count.
function csq_recruit_total_cost()
{
    var _tier  = csq_recruit_tier(global.csq_recruit_sel_tier);
    var _count = max(1, global.csq_recruit_sel_count);
    return _tier.price * _count;
}


/// @func   csq_recruit_player_money()
/// @desc   Current roubles, guarded.
function csq_recruit_player_money()
{
    try { return global.player_money; } catch (_err) { return 0; }
}


/// @func   csq_recruit_persist_money()
/// @desc   Commit the player's money (and current status) to the save, using the
///         game's own routine. Gated behind csq_persist_probe so no db_* call can
///         fire against an unloaded save -- the same fatal-precondition rule the
///         whole persist module lives by. If it cannot save now, the change stays
///         in RAM and the game writes it at its next ordinary save point.
function csq_recruit_persist_money()
{
    var _probe = csq_persist_probe();

    if (!_probe.can_open || !_probe.can_write)
    {
        csq_log_debug("recruit: money change not saved now (" + _probe.why +
                      "); the game will persist it at its next save");
        return;
    }

    try
    {
        scr_save_player_status();
        csq_log_debug("recruit: player status saved");
    }
    catch (_err)
    {
        csq_log_exception("csq_recruit_persist_money", _err);
        try { db_close(true); } catch (_ignored) {}
    }
}


/// @func   csq_recruit_confirm()
/// @desc   The purchase. Re-checks room and funds at the moment of buying, deducts
///         the total, spawns/registers the companions at the chosen tier, and logs
///         the whole transaction. Refunds the shortfall if fewer than requested
///         could be added, so the player is never charged for a companion that did
///         not join.
function csq_recruit_confirm()
{
    csq_recruit_init();

    var _tier  = csq_recruit_tier(global.csq_recruit_sel_tier);
    var _avail = csq_recruit_available_slots();
    var _count = clamp(global.csq_recruit_sel_count, 1, max(1, _avail));
    var _total = _tier.price * _count;
    var _money = csq_recruit_player_money();

    csq_log_info("recruit: confirm attempt count=" + string(_count) +
                 " tier='" + _tier.name + "' preset='" + _tier.preset + "'" +
                 " hp_mult=" + string(_tier.hp_mult) +
                 " total=" + string(_total) + " money=" + string(_money));

    if (_avail < _count)
    {
        csq_recruit_toast("Not enough room in your squad.");
        csq_log_info("recruit: blocked, only " + string(_avail) + " slot(s) free");
        return;
    }

    if (_money < _total)
    {
        csq_recruit_toast("Not enough roubles - need " + string(_total) + ".");
        csq_log_info("recruit: blocked, insufficient funds (need " + string(_total) +
                     ", have " + string(_money) + ")");
        return;
    }

    // Charge first, then persist, then spawn.
    global.player_money = _money - _total;
    csq_recruit_persist_money();

    var _preset = csq_recruit_resolve_preset(_tier.preset);

    var _ok = 0;
    for (var _i = 0; _i < _count; _i++)
    {
        if (csq_squad_recruit(_preset, _tier.hp_mult)) _ok++;
        else break;
    }

    // Refund any companion that could not be added (should not happen after the
    // room check above, but a refund is the safe response if it ever does).
    if (_ok < _count)
    {
        var _refund = (_count - _ok) * _tier.price;
        global.player_money += _refund;
        csq_recruit_persist_money();
        csq_log_warn("recruit: only " + string(_ok) + " of " + string(_count) +
                     " added, refunded " + string(_refund));
    }

    csq_log_info("recruit: purchased " + string(_ok) + "/" + string(_count) + " '" +
                 _tier.name + "' companion(s), money now " + string(global.player_money));

    if (_ok > 0) csq_recruit_toast("Recruited " + string(_ok) + " " + _tier.name + " companion(s).");
    else         csq_recruit_toast("Recruitment failed.");

    csq_recruit_close_menu();
}


/// @func   csq_recruit_key_label(_setting)
/// @desc   A short human label for the key bound to _setting, for the prompt and
///         the menu footer. Covers the common codes; falls back to "key N".
function csq_recruit_key_label(_setting)
{
    var _code = csq_input_key(_setting);

    if (_code == 0)                   return "?";
    if (_code == 13)                  return "Enter";
    if (_code == 8)                   return "Backspace";
    if (_code == 38)                  return "Up";
    if (_code == 40)                  return "Down";
    if (_code == 37)                  return "Left";
    if (_code == 39)                  return "Right";
    if (_code == 32)                  return "Space";
    if (_code >= 112 && _code <= 123) return "F" + string(_code - 111);   // F1-F12
    if (_code >= 48  && _code <= 57)  return string(_code - 48);          // 0-9
    if (_code >= 65  && _code <= 90)  return chr(_code);                  // A-Z

    return "key " + string(_code);
}


/// @func   csq_recruit_draw()
/// @desc   Draw the prompt or the menu. Called first thing in csq_hud_draw, before
///         the squad panel's own early-outs, so it shows with an empty roster and
///         while the panel is toggled off. Never throws.
function csq_recruit_draw()
{
    csq_recruit_init();

    try
    {
        if (!csq_recruit_enabled()) return;
        if (!csq_in_hub())          return;
        if (!global.csq_recruit_open && !global.csq_recruit_near) return;

        var _of = draw_get_font();
        var _oc = draw_get_color();
        var _oa = draw_get_alpha();
        var _oh = draw_get_halign();
        var _ov = draw_get_valign();

        try { language_set_font(0); } catch (_e) {}
        draw_set_alpha(1);

        if (global.csq_recruit_open) csq_recruit_draw_menu();
        else                         csq_recruit_draw_prompt();

        draw_set_alpha(_oa);
        draw_set_color(_oc);
        draw_set_font(_of);
        draw_set_halign(_oh);
        draw_set_valign(_ov);
    }
    catch (_err)
    {
        csq_log_exception("csq_recruit_draw", _err);
    }
}


/// @func   csq_recruit_world_to_gui(_wx, _wy)
/// @desc   A world point in the mod's 480x270 GUI space. Kept as a named wrapper
///         because the recruiter code reads better for it; the arithmetic lives in
///         csq_world_to_gui now that the reveal overlays need it too.
/// @return {Struct} {ok, x, y}
function csq_recruit_world_to_gui(_wx, _wy)
{
    return csq_world_to_gui(_wx, _wy);
}


/// @func   csq_recruit_prompt_text()
/// @desc   The hire hint, in the exact shape vanilla uses for every other NPC.
///
///         draw_text_outlined_with_control cannot be reused directly: its keyboard
///         branch is literally
///             arg2 = "[" + scr_key_map(global.kb_now[arg3]) + "] " + arg2;
///         where arg3 is an index into vanilla's own action table. This mod's key is
///         not a vanilla action, so there is no index to hand it -- but the format is
///         one line, so it is reproduced here instead of faked with a lookalike.
///
///         The word comes from the same descriptor vanilla's talk prompt uses
///         ("faction.inter.talk" -> "Talk" in english.csv), so it follows the player's
///         language rather than pinning English into the UI. Both lookups are guarded:
///         scr_key_map returns "Error" for codes it does not know, and
///         language_get_string returns its argument unchanged for a missing key.
function csq_recruit_prompt_text()
{
    var _key = csq_recruit_key_label("key_recruit");

    try
    {
        var _mapped = scr_key_map(csq_input_key("key_recruit"));

        // "Error" is scr_key_map's own miss value, not an exception.
        if (is_string(_mapped) && _mapped != "" && _mapped != "Error") _key = _mapped;
    }
    catch (_err) { /* keep the local label */ }

    var _verb = "Talk";

    try
    {
        var _loc = language_get_string("faction.inter.talk");

        // An untranslated descriptor comes back verbatim -- do not show the raw key.
        if (is_string(_loc) && _loc != "" && _loc != "faction.inter.talk") _verb = _loc;
    }
    catch (_err) { /* keep "Talk" */ }

    return "[" + _key + "] " + _verb;
}


/// @func   csq_recruit_draw_prompt()
/// @desc   The "walk up and press a key" hint. Drawn over the recruiter's head so
///         the hint and the man it belongs to read as one thing -- a fixed screen
///         position left the player hunting for which part of the bar was live.
///         Clamped inside the GUI so it cannot slide off an edge, and it falls back
///         to the old low-centre spot if the camera or the instance is unavailable.
function csq_recruit_draw_prompt()
{
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    var _text = csq_recruit_prompt_text();

    var _px = 240, _py = 210;

    if (csq_cfg("recruiter_prompt_over_npc"))
    {
        var _rec = csq_recruit_instance();

        if (_rec != noone)
        {
            // Both the prompt and the name label are on screen at once -- the label
            // only hides during dialogue, and the player is in the move state while
            // standing in range. Vanilla draws its label 15px above the marker pin,
            // so keep the prompt a line clear above wherever that lands instead of
            // trusting a fixed -28 that collides as soon as the offset is retuned.
            var _off = -28;

            if (csq_cfg("recruiter_marker_enabled"))
            {
                _off = min(_off, csq_cfg("recruiter_marker_offset_y") - 15 - 14);
            }

            var _gui = csq_recruit_world_to_gui(_rec.x, _rec.y + _off);

            if (_gui.ok)
            {
                _px = clamp(_gui.x, 70, 410);
                _py = clamp(_gui.y, 12, 258);
            }
        }
    }

    // Vanilla's colour for the interaction it is about to run, not plain white --
    // see csq_hud_colour_interact. Ours is always the selected one by definition.
    scr_draw_text_outlined(_px, _py, _text,
        csq_hud_colour_interact(), csq_hud_colour_outline(), 1, 1);
}


/// @func   csq_recruit_lore_lines()
/// @desc   The flavour text under the squad-size step. Returned as one line per
///         array entry rather than a single "\n" string, because scr_draw_text_outlined
///         hands its text to draw_text_transformed_color, which honours newlines but
///         not the mod's own line spacing -- drawing each line explicitly keeps the
///         block aligned with the rest of the panel.
///
///         Hardcoded rather than exposed in the ini: an ini value cannot hold a line
///         break, so three keys would be needed to say one thing, and this is
///         narrative rather than a setting a player would want to tune.
function csq_recruit_lore_lines()
{
    return [
        "Everyone here signs on for a rotation.",
        "Some rotations end at the extraction point.",
        "The Artel prices the difference."
    ];
}


/// @func   csq_recruit_draw_menu()
/// @desc   The panel: a translucent box with a title, a step indicator, the
///         step body, and a controls footer. Drawn in 480x270 GUI space, using
///         the same csq_hud text helpers and colours as the squad panel.
///
///         The box is 312px wide, centred on 240. It was 264 before the flavour text
///         went in: at roughly 5.6px per character in the small UI font, the longest
///         lore line runs about 241px and would have overhung the old inner width.
///         Everything inside is either centred on 240 or left-aligned from the left
///         edge, so widening it only ever gives the contents more room.
function csq_recruit_draw_menu()
{
    var _x1 = 84, _y1 = 48, _x2 = 396, _y2 = 222;

    // Backdrop, then a one-pixel border.
    draw_set_color(csq_hud_colour_outline());
    draw_set_alpha(0.82);
    draw_rectangle(_x1, _y1, _x2, _y2, false);

    draw_set_alpha(1);
    draw_set_color(csq_hud_colour_ok());
    draw_rectangle(_x1, _y1, _x2, _y2, true);

    draw_set_halign(fa_center);
    draw_set_valign(fa_top);

    // The contact's own trade name, not a verb: this reads as the sign over his
    // corner of the bar rather than an instruction to the player.
    scr_draw_text_outlined(240, _y1 + 6, "Artel Labour Recruitment",
                           csq_hud_colour_ok(), csq_hud_colour_outline(), 1, 1);

    var _label = "Step 3 of 3  -  Confirm";
    if      (global.csq_recruit_step == csq_recruit_step_size()) _label = "Step 1 of 3  -  Squad size";
    else if (global.csq_recruit_step == csq_recruit_step_tier()) _label = "Step 2 of 3  -  Difficulty";

    scr_draw_text_outlined(240, _y1 + 20, _label,
                           csq_hud_colour_absent(), csq_hud_colour_outline(), 1, 1);

    draw_set_halign(fa_left);

    // _y2 - 14 is the footer's own y, and valign is fa_top for the body, so that is
    // the first pixel the footer claims. The body treats it as a hard ceiling and
    // stacks the flavour text upward from just above it.
    csq_recruit_draw_menu_body(_x1 + 14, _y1 + 42, 14, _y2 - 14);

    draw_set_halign(fa_center);

    var _kup   = csq_recruit_key_label("recruit_key_up");
    var _kdn   = csq_recruit_key_label("recruit_key_down");
    var _kok   = csq_recruit_key_label("recruit_key_confirm");
    var _kback = csq_recruit_key_label("recruit_key_back");

    var _foot = _kup + "/" + _kdn + ": change     " + _kok + ": next     " + _kback + ": back";
    if (global.csq_recruit_step == csq_recruit_step_confirm())
    {
        _foot = _kok + ": BUY     " + _kback + ": back";
    }

    scr_draw_text_outlined(240, _y2 - 14, _foot,
                           csq_hud_colour_absent(), csq_hud_colour_outline(), 1, 1);
}


/// @func   csq_recruit_draw_menu_body(_x, _y, _lh, _ybottom)
/// @desc   The step-specific lines of the menu. Left-aligned from (_x, _y), one
///         line every _lh pixels. The confirm step recomputes the total from the
///         same helpers the purchase uses, so the figure shown is the figure charged.
///
///         _ybottom is the lowest y the body may draw on -- the top of the footer's
///         space. The squad-size step hangs its flavour text up from there rather
///         than flowing down from _y, so the block stays pinned to the bottom of the
///         box whatever the step above it does.
function csq_recruit_draw_menu_body(_x, _y, _lh, _ybottom)
{
    var _white = csq_hud_colour_ok();
    var _grey  = csq_hud_colour_absent();
    var _red   = csq_hud_colour_hurt();
    var _out   = csq_hud_colour_outline();

    var _step = global.csq_recruit_step;

    if (_step == csq_recruit_step_size())
    {
        var _avail = csq_recruit_available_slots();

        scr_draw_text_outlined(_x, _y,
            "Squad: " + string(csq_squad_count()) + "/" + string(csq_squad_max()) +
            "     Free slots: " + string(_avail), _grey, _out, 1, 1);

        _y += _lh * 2;
        scr_draw_text_outlined(_x, _y,
            "How many to hire:    < " + string(global.csq_recruit_sel_count) + " >",
            _white, _out, 1, 1);

        // Flavour text, bottom-anchored. 12px spacing rather than the body's 14 so
        // the three lines read as one block set apart from the controls above.
        //
        // valign is fa_top here, so a line drawn at y occupies roughly y..y+12. The
        // LAST line therefore has to start a full line-height plus a gap above the
        // footer, not on it -- anchoring the last line's y to _ybottom itself is what
        // made the block run down into the controls hint.
        var _lore = csq_recruit_lore_lines();
        var _lore_lh = 12;
        var _ly = _ybottom - 6 - (array_length(_lore) * _lore_lh);

        for (var _i = 0; _i < array_length(_lore); _i++)
        {
            scr_draw_text_outlined(_x, _ly + (_i * _lore_lh), _lore[_i], _grey, _out, 1, 1);
        }
    }
    else if (_step == csq_recruit_step_tier())
    {
        var _tc = csq_recruit_tier_count();

        for (var _i = 0; _i < _tc; _i++)
        {
            var _t   = csq_recruit_tier(_i);
            var _sel = (_i == global.csq_recruit_sel_tier);

            scr_draw_text_outlined(_x, _y,
                (_sel ? "> " : "   ") + _t.name + "     " + string(_t.price) + " ea",
                _sel ? _white : _grey, _out, 1, 1);

            _y += _lh;
        }
    }
    else
    {
        var _t     = csq_recruit_tier(global.csq_recruit_sel_tier);
        var _count = clamp(global.csq_recruit_sel_count, 1, max(1, csq_recruit_available_slots()));
        var _total = _t.price * _count;
        var _money = csq_recruit_player_money();

        scr_draw_text_outlined(_x, _y, "Companions:   " + string(_count),      _white, _out, 1, 1); _y += _lh;
        scr_draw_text_outlined(_x, _y, "Difficulty:   " + _t.name,             _white, _out, 1, 1); _y += _lh;
        scr_draw_text_outlined(_x, _y, "Price each:   " + string(_t.price),    _white, _out, 1, 1); _y += _lh;
        scr_draw_text_outlined(_x, _y, "Total:        " + string(_total),      _white, _out, 1, 1); _y += _lh;
        scr_draw_text_outlined(_x, _y, "Your money:   " + string(_money),
                               (_money < _total) ? _red : _grey, _out, 1, 1);
        _y += _lh * 2;

        if (_money < _total) scr_draw_text_outlined(_x, _y, "Not enough roubles.", _red,   _out, 1, 1);
        else                 scr_draw_text_outlined(_x, _y, "Press " + csq_recruit_key_label("recruit_key_confirm") + " to buy.", _white, _out, 1, 1);
    }
}

