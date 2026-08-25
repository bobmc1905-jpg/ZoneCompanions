// =============================================================================
//  Zone Companions  -  csq_reveal
// -----------------------------------------------------------------------------
//  The squad's contribution to what the player can see. The game hides things in
//  two unrelated ways, so this module has two halves.
//
//  HALF ONE: SPRITES ARE FADED OUT, NOT MERELY DARKENED
//  obj_npc_parent_Step_0 line 3873 runs, for every NPC in a raid, every frame:
//      var _visibility = player_line_of_sight(x, y);
//  and walks image_alpha down to 0 when that is false. obj_chest_general_Step_0
//  line 39 does the same for containers. So a companion behind the player is not
//  dim, they are drawn at alpha 0 -- and their torch goes dark with them, because
//  obj_light_enemy_torch_Step_0 swaps its sprite for s_vuoto and scales by
//  lerp(0, scale_start, id_linked.image_alpha).
//
//  csq_reveal_squad_sees is prepended to player_line_of_sight itself, so a point
//  any companion can see counts as a point the player's side can see. One patch
//  covers companions, enemies, containers and flashlights, because it answers the
//  question rather than fixing up each caller's answer.
//
//  HALF TWO: VISION IN THIS GAME IS A HOLE IN A BLACK SURFACE
//  obj_fog_setup_Draw_0 clears surface_shadow to opaque black, switches to
//  bm_subtract, and punches the player's view out of it: a triangle fan of
//  global.angle_fow degrees aimed at the cursor, plus s_glow_fow around their
//  feet for close-range awareness. It then runs shd_fog_new over the level
//  geometry to paint wall shadows back in, and blits the whole surface over the
//  world at the player's "fog of war alpha" setting.
//
//  So a companion's field of view is not something to draw on top of the fog --
//  drawing on top is what a coloured overlay does, and it looks like an overlay.
//  It is another hole in the same surface, punched in the same subtract pass,
//  from the same triangle the companion's AI actually searches. Because it goes
//  in before shd_fog_new runs, wall shadows still apply to it: a companion
//  cannot reveal ground through a solid wall.
//
//  csq_reveal_fog_subtract is called from a one-line patch inside that event, so
//  it inherits the surface target, the subtract blend mode and the event's own
//  camera offsets. It must not be called from anywhere else.
//
//  KNOWN LIMITATION OF HALF TWO
//  shd_fog_new is handed one light position, the player's
//  (shader_set_uniform_f(light_pos, _player_x - _camx, ...)). Wall shadows inside
//  ground a companion cleared are therefore cast player-relative, so revealed
//  ground around a corner can look oddly lit. Fixing it would mean a second
//  shader pass per companion, which is not worth the frame cost.
//
//  BOTH HALVES READ ONE CACHE
//  csq_reveal_sight_cache builds the triangles once per frame in csq_tick. The
//  hole punched in the fog and the sprites allowed to render therefore come from
//  the same geometry in the same frame, and cannot disagree.
//
//  THE CONE IS THE REAL ONE
//  scr_find_target_for_human builds a triangle -- apex at the NPC, two far
//  corners at weapon_pointing_direction +/- alert_radius/2, at
//  alert_visual_distance -- and calls point_in_triangle on every candidate. Not
//  a circle, not an arc: that literal triangle is the search region, so clearing
//  the same three points clears exactly the ground the companion is watching.
//  csq_reveal_cone reproduces its arithmetic, including the day/night penalty
//  and scr_npc_oval_view's sideways squash, from the same vanilla getters.
//
//  The position pins are a separate, optional thing -- see csq_reveal_draw.
//  Those do draw over the fog, from obj_controller_Draw_64, because their whole
//  purpose is to be visible when the companion is not.
//
//  This file declares functions only -- see the note in csq_config.
// =============================================================================


/// @func   csq_reveal_npc_id(_inst)
/// @desc   The preset key vanilla's npc_get_* getters expect. Read from the
///         instance rather than the roster entry so it follows whatever the spawn
///         actually became, and validated against global.npc_data because those
///         getters call trace_error on an id they do not recognise.
/// @return {String|Undefined} undefined when it cannot be trusted
function csq_reveal_npc_id(_inst)
{
    if (!instance_exists(_inst))                              return undefined;
    if (!variable_instance_exists(_inst, "npc_id"))            return undefined;

    var _id = _inst.npc_id;
    if (is_undefined(_id) || string(_id) == "")                return undefined;
    if (!is_struct(global.npc_data))                           return undefined;
    if (!variable_struct_exists(global.npc_data, string(_id))) return undefined;

    return string(_id);
}


/// @func   csq_reveal_daylight_factor()
/// @desc   The multiplier vanilla applies to both the cone's length and its angle
///         for the time of day, from the top of scr_find_target_for_human.
///
///         The decompiled source compares obj_light_controller.ciclo_now against
///         UnknownEnum.Value_0/2/3, which are plain integers in the shipped code:
///         0 sunrise, 1 day, 2 sunset, 3 night, with ciclo_time[] holding the hour
///         each phase begins. Vanilla divides by 1.25 at night and lerps across
///         sunrise and sunset. Anything unrecognised means full daylight.
///
///         A future build that renumbers those phases would rescale the drawn cone
///         by at most 20%, never break it -- which is why this is worth doing
///         rather than pretending the cone is the same size at midnight.
function csq_reveal_daylight_factor()
{
    var _k = 1.25;

    try
    {
        if (!instance_exists(obj_light_controller)) return 1;

        var _lc = instance_find(obj_light_controller, 0);
        if (!instance_exists(_lc)) return 1;

        var _now = _lc.ciclo_now;
        var _t   = time_get_hours_fraction();

        // Night: the full penalty.
        if (_now == 3) return 1 / _k;

        // Sunrise: penalised at the start of the phase, clear by the end of it.
        if (_now == 0)
        {
            var _span = _lc.ciclo_time[1] - _lc.ciclo_time[0];
            if (_span == 0) return 1;

            return lerp(1 / _k, 1, clamp((_t - _lc.ciclo_time[0]) / _span, 0, 1));
        }

        // Sunset: the same run backwards.
        if (_now == 2)
        {
            var _span2 = _lc.ciclo_time[3] - _lc.ciclo_time[2];
            if (_span2 == 0) return 1;

            return lerp(1, 1 / _k, clamp((_t - _lc.ciclo_time[2]) / _span2, 0, 1));
        }
    }
    catch (_err)
    {
        // Cosmetic. Full daylight is the honest default -- it draws the largest
        // cone the companion could ever have, so it never claims sight it lacks
        // in a direction, only possibly a little too much range at dusk.
        return 1;
    }

    return 1;
}


/// @func   csq_reveal_cone(_inst)
/// @desc   The companion's sight triangle, in world coordinates: the same three
///         points scr_find_target_for_human feeds to point_in_triangle.
/// @return {Struct} {ok, x1,y1, x2,y2, x3,y3}
function csq_reveal_cone(_inst)
{
    var _fail = { ok: false, x1: 0, y1: 0, x2: 0, y2: 0, x3: 0, y3: 0 };

    try
    {
        // Vanilla wraps its whole scan in this test, so with no light controller
        // the companion is not scanning at all and has no cone to show.
        if (!instance_exists(obj_light_controller)) return _fail;

        var _npc = csq_reveal_npc_id(_inst);
        if (is_undefined(_npc)) return _fail;

        var _f     = csq_reveal_daylight_factor();
        var _dist  = npc_get_alert_visual_distance(_npc) * _f;
        var _angle = npc_get_alert_radius(_npc) * _f;

        if (_dist <= 0 || _angle <= 0) return _fail;

        // weapon_pointing_direction is what vanilla aims the cone along, not
        // image_angle or direction. csq_aim_dir is this mod's own smoothed aim and
        // is the closest stand-in if the vanilla variable is ever absent.
        var _dir = 0;

        if (variable_instance_exists(_inst, "weapon_pointing_direction"))
        {
            _dir = _inst.weapon_pointing_direction;
        }
        else if (variable_instance_exists(_inst, "csq_aim_dir"))
        {
            _dir = _inst.csq_aim_dir;
        }

        // The squash that makes sight shorter to the sides than straight ahead.
        // Called rather than reimplemented: it reads a general preset field that
        // is not this mod's to duplicate.
        try { _dist = scr_npc_oval_view(_dist, _dir); } catch (_e) {}

        if (_dist <= 0) return _fail;

        var _half = _angle / 2;

        return {
            ok: true,
            x1: _inst.x,
            y1: _inst.y,
            x2: _inst.x + lengthdir_x(_dist, _dir + _half),
            y2: _inst.y + lengthdir_y(_dist, _dir + _half),
            x3: _inst.x + lengthdir_x(_dist, _dir - _half),
            y3: _inst.y + lengthdir_y(_dist, _dir - _half)
        };
    }
    catch (_err)
    {
        csq_log_exception("csq_reveal_cone", _err);
        return _fail;
    }
}


/// @func   csq_reveal_sight_cache()
/// @desc   Rebuild the squad's sight geometry for this frame. Called once from
///         csq_tick, so it costs one pass over the roster per frame no matter how
///         many things ask about it afterwards.
///
///         WHY A CACHE AND NOT A LIVE QUERY
///         csq_reveal_squad_sees is called once per NPC and once per chest, every
///         frame, from inside vanilla's own visibility fade. Recomputing a cone
///         there would mean npc_get_* lookups and a scr_npc_oval_view call per
///         asker per companion. Building the triangles once and testing against
///         them is the same answer for a fraction of the work.
///
///         It also makes the two halves of the feature agree by construction: the
///         hole punched in the fog and the sprites allowed to render come from the
///         same triangles in the same frame, so a companion can never light ground
///         where its cone does not reach, or the reverse.
function csq_reveal_sight_cache()
{
    try
    {
        // Read once and stored, because csq_reveal_squad_sees runs in the hot path
        // and should not be doing config lookups per NPC.
        global.csq_reveal_sight_on = csq_cfg("reveal_squad_sight");

        var _out   = [];
        var _count = csq_squad_count();

        for (var _i = 0; _i < _count; _i++)
        {
            var _e = csq_squad_entry(_i);
            if (is_undefined(_e)) continue;
            if (!instance_exists(_e.inst)) continue;

            var _inst = _e.inst;
            var _t    = csq_reveal_cone(_inst);

            // x/y are kept separately from the triangle's apex because they are
            // still wanted when the cone itself failed to build -- a companion with
            // no usable cone is still a companion the player should be able to see.
            array_push(_out, {
                x:  _inst.x, y:  _inst.y,
                ok: _t.ok,
                x1: _t.x1,   y1: _t.y1,
                x2: _t.x2,   y2: _t.y2,
                x3: _t.x3,   y3: _t.y3
            });
        }

        global.csq_reveal_cones = _out;
    }
    catch (_err)
    {
        global.csq_reveal_cones = [];
        csq_log_exception("csq_reveal_sight_cache", _err);
    }
}


/// @func   csq_reveal_squad_sees(_x, _y)
/// @desc   True when any companion has an unobstructed view of a world point.
///
///         THIS IS THE FUNCTION THAT MAKES THINGS ACTUALLY RENDER
///         Clearing fog was only ever half the job. obj_npc_parent_Step_0 line 3873
///         runs, for every NPC in a raid, every frame:
///             var _visibility = player_line_of_sight(x, y);
///         and fades image_alpha to 0 when that is false. obj_chest_general_Step_0
///         line 39 does the same. And player_line_of_sight is false for anything
///         outside the player's own 90-degree wedge and further than
///         global.fow_minimun_dis away.
///
///         So a companion standing behind the player is not dim -- their sprite is
///         drawn at alpha 0, which is why no amount of fog clearing revealed them.
///         Their flashlight goes with them: obj_light_enemy_torch_Step_0 sets its
///         sprite to s_vuoto and scales by lerp(0, scale_start, id_linked
///         .image_alpha), so an alpha-0 owner carries a light that emits nothing.
///
///         The patch on player_line_of_sight consults this first. A point any
///         companion can see is treated as a point the player's side can see, which
///         is what "reveal the world the way the player does" has to mean: the
///         companion, their torchlight, and any enemy standing in their cone.
///
///         Mirrors player_line_of_sight's own structure deliberately -- the close
///         range exemption, the triangle test, then the wall test -- so the rule is
///         the same rule, applied from a different pair of eyes.
function csq_reveal_squad_sees(_x, _y)
{
    // Set by csq_reveal_sight_cache, which only runs inside csq_tick, which only
    // runs after csq_boot. Testing it is therefore also the proof that the config
    // and the roster are up before anything below touches them.
    if (!variable_global_exists("csq_reveal_cones")) return false;
    if (!global.csq_reveal_sight_on)                return false;

    var _cones = global.csq_reveal_cones;
    var _n     = array_length(_cones);

    if (_n == 0) return false;

    // Proof of life, once per session, same reasoning as in csq_reveal_fog_subtract:
    // it separates "the patch on player_line_of_sight never applied" from "it applied
    // and the answer was no".
    if (!variable_global_exists("csq_sight_patch_proved"))
    {
        global.csq_sight_patch_proved = true;
        csq_log_info("reveal: squad sight live, " + string(_n) + " cone(s)");
    }

    // Vanilla's own "close enough that the cone does not matter" radius, 35px, set
    // in obj_fog_setup_Create_0 line 15. Read rather than copied so it tracks.
    var _near = variable_global_exists("fow_minimun_dis") ? global.fow_minimun_dis : 35;

    for (var _i = 0; _i < _n; _i++)
    {
        var _c = _cones[_i];

        // Close range, no cone test and no wall test -- exactly vanilla's exemption.
        // This is also what guarantees a companion is visible to the player at all:
        // they are zero pixels from themselves, so they always pass here.
        if (point_distance(_x, _y, _c.x, _c.y) <= _near) return true;

        if (!_c.ok) continue;

        if (!point_in_triangle(_x, _y, _c.x1, _c.y1, _c.x2, _c.y2, _c.x3, _c.y3)) continue;

        // The wall test last, because it is the only expensive one. Cast from the
        // companion, so they cannot see through a solid any more than the player can.
        if (collision_line(_x, _y, _c.x, _c.y, obj_solid, true, true)) continue;

        return true;
    }

    return false;
}


/// @func   csq_reveal_edge_point(_gx, _gy, _ox, _oy, _margin)
/// @desc   Where the line from (_ox,_oy) toward an off-screen (_gx,_gy) leaves the
///         480x270 GUI rectangle, inset by _margin. The same projection vanilla's
///         clip_to_view_edge does for hub markers, but in GUI space rather than
///         world space with a hardcoded 480x270 camera, so it stays correct if the
///         view size ever changes.
/// @return {Struct} {x, y}
function csq_reveal_edge_point(_gx, _gy, _ox, _oy, _margin)
{
    var _dx = _gx - _ox;
    var _dy = _gy - _oy;

    // A zero component has no crossing on that axis, so it gets a parameter big
    // enough to lose the min() below rather than an epsilon: perturbing the delta
    // instead would have to guess a sign, and a literal small enough not to move
    // the result is also small enough for the compiler to flatten to zero -- which
    // is what it did to the tolerance in csq_config_is_default.
    var _big = 999999;

    var _tx = _big;
    var _ty = _big;

    if (_dx != 0) _tx = (_dx > 0) ? ((480 - _margin - _ox) / _dx) : ((_margin - _ox) / _dx);
    if (_dy != 0) _ty = (_dy > 0) ? ((270 - _margin - _oy) / _dy) : ((_margin - _oy) / _dy);

    // The nearer of the two crossings is the one actually on the rectangle.
    var _t = min(_tx, _ty);

    return {
        x: clamp(_ox + (_dx * _t), _margin, 480 - _margin),
        y: clamp(_oy + (_dy * _t), _margin, 270 - _margin)
    };
}


/// @func   csq_reveal_fog_subtract(_camx, _camy)
/// @desc   Punch the squad's vision out of vanilla's fog surface.
///
///         CALLED FROM INSIDE obj_fog_setup_Draw_0 AND NOWHERE ELSE.
///         The patch inserts the call just before that event's
///         gpu_set_blendmode(bm_normal), which means on entry:
///           - surface_shadow is the render target, cleared to opaque black;
///           - the blend mode is still bm_subtract, so anything drawn white
///             removes fog instead of adding paint;
///           - the player's own wedge and glow have already been subtracted;
///           - shd_fog_new has NOT run yet, so wall shadows are still painted in
///             afterwards and a companion cannot reveal ground through a solid;
///           - _camx/_camy are the event's rounded camera origin, which is what
///             turns a world coordinate into a surface coordinate.
///         Every one of those is a precondition, not a convenience.
///
///         Coordinates are world-minus-camera exactly as vanilla computes _px/_py
///         on line 17, so the cone lands on the same pixels the companion's AI is
///         actually searching.
///
///         draw_vertex takes the ambient colour and alpha rather than its own, so
///         both are set here and put back: the shader pass that follows must not
///         inherit a change.
function csq_reveal_fog_subtract(_camx, _camy)
{
    try
    {
        var _cone = csq_cfg("reveal_view_cone");
        var _glow = csq_cfg("reveal_companion_glow");

        if (!_cone && !_glow) return;

        // The same triangles csq_reveal_squad_sees is testing against this frame.
        // Draw events run after every Step event, so csq_tick has already refreshed
        // this -- there is no staleness here, unlike on the NPC side.
        if (!variable_global_exists("csq_reveal_cones")) return;

        var _cones = global.csq_reveal_cones;
        var _n     = array_length(_cones);

        if (_n == 0) return;

        // Subtracting alpha 0 is a no-op, so skip the whole pass rather than
        // emitting primitives that cannot change a pixel.
        var _strength = clamp(csq_cfg("reveal_cone_strength"), 0, 1);
        if (_strength <= 0) return;

        // Proof of life, once per session. If this line is absent from the log the
        // patch on obj_fog_setup_Draw_0 never fired, which is a different bug from
        // "the cones are there but you cannot see them". One INFO, not one a frame.
        if (!variable_global_exists("csq_fog_patch_proved"))
        {
            global.csq_fog_patch_proved = true;
            csq_log_info("reveal: fog subtract live, " + string(_n) + " cone(s)");
        }

        var _old_colour = draw_get_color();
        var _old_alpha  = draw_get_alpha();

        draw_set_color(c_white);
        draw_set_alpha(_strength);

        for (var _i = 0; _i < _n; _i++)
        {
            var _t = _cones[_i];

            if (_cone && _t.ok)
            {
                // pr_trianglelist rather than vanilla's pr_trianglefan: a fan is
                // only worth it for a shared apex across several triangles, and
                // there is exactly one triangle per companion here.
                draw_primitive_begin(pr_trianglelist);
                draw_vertex(_t.x1 - _camx, _t.y1 - _camy);
                draw_vertex(_t.x2 - _camx, _t.y2 - _camy);
                draw_vertex(_t.x3 - _camx, _t.y3 - _camy);
                draw_primitive_end();
            }

            if (_glow)
            {
                // The same sprite vanilla subtracts at the player's feet, so a
                // companion is lit exactly the way the player is and nothing about
                // the look has to be invented.
                draw_sprite_ext(s_glow_fow, 0, _t.x - _camx, _t.y - _camy,
                                1, 1, 0, c_white, _strength);
            }
        }

        draw_set_alpha(_old_alpha);
        draw_set_color(_old_colour);
    }
    catch (_err)
    {
        // Leaving a non-white colour or a partial alpha behind would tint the wall
        // shadow pass and the surface blit, so the reset happens even on failure.
        draw_set_alpha(1);
        draw_set_color(c_white);
        csq_log_exception("csq_reveal_fog_subtract", _err);
    }
}


/// @func   csq_reveal_draw_marker(_inst, _name, _colour, _origin)
/// @desc   One companion's position marker. On screen: vanilla's own
///         s_minimap_marker pin at their feet, the name above it, exactly the
///         treatment the bunker NPCs get. Off screen: the same pin pushed to the
///         screen edge and rotated to point at them, which is what
///         obj_controller_Draw_64 does for a hub marker outside the view.
///
///         _origin is the GUI position the off-screen arrow points away from --
///         the player, so the arrow reads as "your companion is that way".
function csq_reveal_draw_marker(_inst, _name, _colour, _origin)
{
    if (!instance_exists(_inst)) return;

    var _g = csq_world_to_gui(_inst.x, _inst.y);
    if (!_g.ok) return;

    var _on_screen = (_g.x >= 0 && _g.x <= 480 && _g.y >= 0 && _g.y <= 270);

    if (!_on_screen && !csq_cfg("reveal_offscreen")) return;

    var _px = _g.x;
    var _py = _g.y;
    var _rot = 0;

    if (!_on_screen)
    {
        var _edge = csq_reveal_edge_point(_g.x, _g.y, _origin.x, _origin.y, 16);

        _px = _edge.x;
        _py = _edge.y;

        // +90 because s_minimap_marker is drawn as a downward teardrop, so its
        // own point is a quarter turn from the direction it is being aimed in.
        // Vanilla applies the same correction at obj_controller_Draw_64 line 856.
        _rot = point_direction(_origin.x, _origin.y, _g.x, _g.y) + 90;
    }

    draw_set_alpha(1);

    // Tinted, unlike vanilla's c_white pin, so the squad's markers are not
    // mistaken for the bunker's fast-travel NPCs.
    try { draw_sprite_ext(s_minimap_marker, 0, _px, _py, 1, 1, _rot, _colour, 1); }
    catch (_err) {}

    if (!csq_cfg("reveal_names")) return;
    if (string(_name) == "")      return;

    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    // 15px above the pin on screen, 16 when pinned to an edge: vanilla's two
    // offsets, kept so the labels line up with the game's own.
    var _ty = _on_screen ? (_py - 15) : (_py - 16);

    scr_draw_text_outlined(clamp(_px, 32, 448), clamp(_ty, 16, 238),
                           string(_name), _colour, csq_hud_colour_outline(), 1, 1);
}


/// @func   csq_reveal_draw()
/// @desc   Draw the squad's position pins. Called from csq_hud_draw before the squad
///         panel's own early-outs, because "where has my companion got to" has to
///         work with the panel toggled off. Never throws.
///
///         Nothing here touches the view cones -- those are holes in the fog
///         surface, punched much earlier in the frame by csq_reveal_fog_subtract.
///         This is the one part of the feature that genuinely does draw on top of
///         everything, because a pin exists precisely for the case where the
///         companion cannot be seen: off the edge of the screen, or behind a wall.
function csq_reveal_draw()
{
    try
    {
        if (!csq_cfg("reveal_companions")) return;
        if (csq_squad_count() == 0)        return;

        // Only meaningful in the world. In menus and on the map screen this would
        // paint over real UI.
        if (!csq_in_raid() && !csq_in_hub()) return;

        var _player = csq_player();
        if (_player == noone) return;

        var _origin = csq_world_to_gui(_player.x, _player.y);
        if (!_origin.ok) return;

        var _old_font   = draw_get_font();
        var _old_colour = draw_get_color();
        var _old_alpha  = draw_get_alpha();
        var _old_halign = draw_get_halign();
        var _old_valign = draw_get_valign();

        try { language_set_font(0); } catch (_err) {}

        var _colour = csq_hud_colour_reveal();
        var _count  = csq_squad_count();

        for (var _j = 0; _j < _count; _j++)
        {
            var _e = csq_squad_entry(_j);
            if (is_undefined(_e)) continue;
            if (!instance_exists(_e.inst)) continue;

            csq_reveal_draw_marker(_e.inst, _e.name, _colour, _origin);
        }

        draw_set_alpha(_old_alpha);
        draw_set_color(_old_colour);
        draw_set_halign(_old_halign);
        draw_set_valign(_old_valign);
        try { draw_set_font_language(_old_font); } catch (_err) { draw_set_font(_old_font); }
    }
    catch (_err)
    {
        // An overlay is cosmetic; obj_controller_Draw_64 still has the real UI to
        // paint after this returns.
        draw_set_alpha(1);
        csq_log_exception("csq_reveal_draw", _err);
    }
}
