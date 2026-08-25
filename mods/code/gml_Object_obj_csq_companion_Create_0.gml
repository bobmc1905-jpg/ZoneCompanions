// =============================================================================
//  obj_csq_companion : Create
// -----------------------------------------------------------------------------
//  Mirrors the vanilla concrete-NPC pattern exactly. obj_loner_regular's Create
//  event is, in full:
//
//      event_inherited();
//      npc_setup("loner_regular");
//      npc_setup_weapon();
//
//  This event is that, with the preset supplied at runtime and two mod-specific
//  lines appended. Note the absence of init_bt_ai_human(): obj_loner_regular does
//  not call it either, because loner_regular's states are "human_general" rather
//  than the behaviour tree. Adding it would initialise a tree nothing runs.
//
//  ORDER IS LOAD-BEARING
//    event_inherited()     builds the NPC: obj_npc_human_parent (torch light,
//                          alarm[9] weapon spawn, weapon timers) then
//                          obj_npc_parent (the ~340 lines of NPC state).
//    npc_setup()           fills in faction, hp, sprites, state and NPCrecoil
//                          from the preset -- so it must come before anything
//                          that overrides those.
//    npc_setup_weapon()    gives the companion a gun to actually fight with.
//    npc_name = roster name
//                          overwrites the random name npc_setup drew at its line 8,
//                          so the panel and the game agree on who this is. After
//                          npc_setup for the same reason as everything below.
//    csq_faction_apply()   replaces the preset's faction (Loners) with
//                          "Companion". After npc_setup, which would undo it.
//    csq_ff_disarm_grenades()
//                          zeroes grenade_amount_max. After npc_setup, which sets
//                          it from the preset -- loner_regular carries live RGD
//                          grenades and flashbangs, and grenade damage has no
//                          faction check at all. See csq_ff.
//    csq_ai_init_instance()sets csq_* variables, scales hp by hp_multiplier and
//                          parks state in "human_no_move". After npc_setup, which
//                          sets both hp and state from the preset. Note the hp
//                          scaling has to land before csq_squad_spawn_entry's
//                          min(carried_hp, inst.hp) clamp, which runs as soon as
//                          instance_create_depth returns -- so it cannot be
//                          deferred to the first step.
// =============================================================================

event_inherited();

// The preset and the display name are handed over in globals rather than as
// arguments, because instance_create_depth cannot pass any and npc_override is
// cleared by obj_npc_parent's own Create -- which event_inherited() has just run.
var _csq_preset = undefined;
var _csq_name   = undefined;

// -1 = no per-companion override; csq_ai_init_instance falls back to the
// configured hp_multiplier. A tier recruit passes its own value through here.
csq_hp_mult = -1;
if (variable_global_exists("csq_pending_hp_mult"))
{
    csq_hp_mult = global.csq_pending_hp_mult;
}

if (variable_global_exists("csq_pending_preset"))
{
    _csq_preset = global.csq_pending_preset;
}

if (variable_global_exists("csq_pending_name"))
{
    _csq_name = global.csq_pending_name;
}

if (is_undefined(_csq_preset) || string(_csq_preset) == "")
{
    // Reached only if something other than csq_squad_spawn_entry created this
    // instance. Falling back to the configured preset keeps it functional.
    _csq_preset = csq_cfg("default_preset");
    csq_log_debug("companion: no pending preset, falling back to '" + string(_csq_preset) + "'");
}

npc_setup(_csq_preset);
npc_setup_weapon();

// npc_setup line 8 has just overwritten npc_name with a fresh draw of its own:
//     npc_name = npc_generate_name(npc_id);
// The roster made an independent draw from that same generator back when the entry
// was created, so the two never match. Take the roster's, because the roster is
// the durable record -- this instance is destroyed and rebuilt every raid, drawing
// a new name each time, while the roster name is what the HUD, the log and the
// medic message have always shown.
//
// npc_name is display-only, so this is safe. Its readers are the killfeed
// (scr_shoot sets bull.shooter_npc_name from it), the death screen
// (who_killed_player.npc_name), the loot container left behind on death
// (obj_npc_human_parent_Destroy_0 sets drop.name_chest) and trader/dialogue
// lookups that a companion never reaches. Nothing keys behaviour off it.
if (!is_undefined(_csq_name) && string(_csq_name) != "")
{
    npc_name = string(_csq_name);
}

csq_faction_apply(id);
csq_ff_disarm_grenades();
csq_ai_init_instance();

csq_log_debug("companion: created '" + string(npc_name) + "' preset=" + string(_csq_preset) +
              " faction=" + string(faction) + " hp=" + string(hp));
