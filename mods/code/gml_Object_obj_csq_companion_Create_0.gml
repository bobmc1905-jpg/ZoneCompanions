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
//    have_to_reload = false
//                          cancels the one forced reload vanilla schedules for every
//                          freshly created NPC. Directly after npc_setup_weapon,
//                          which is what filled the magazine the flag claims is
//                          empty.
//    npc_speaker_id = "no_speaker"
//                          takes the talk prompt off the companion. After npc_setup,
//                          which is what put a real speaker on it.
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

// The companion walks out of the hub with a round already chambered.
//
// obj_npc_parent_Create_0 line 279 sets have_to_reload = true for every NPC in the
// game, and obj_npc_parent_Step_0 turns that flag into a reload *action* the moment
// the NPC acquires a target (lines 1463 and 1647): reloading = true, path_end(),
// alarm[0] = irandom(100) + 80. That is 1.3 to 3 seconds of standing still and not
// firing, spent at the exact moment first contact happens -- which is what "their
// weapons are not reloaded after spawn, so entering combat they need to reload
// first" is.
//
// Nothing is actually empty. npc_setup_weapon, one line above, has just filled the
// magazine (ammo_now = the weapon's magazine size, modded size included). The flag
// is vanilla's way of making an ambient enemy rack the bolt the first time it sees
// you; a companion you hired, armed and walked into the zone with has had all the
// time in the world to do that already.
//
// Only the *initial* flag is cleared. scr_enemy_shoot line 42 still sets it when the
// magazine genuinely runs dry, so mid-fight reloads behave exactly as vanilla.
have_to_reload = false;

// A companion is not someone you strike up a conversation with.
//
// npc_setup line 9 does
//     npc_speaker_id = npc_get_speaker_id(npc_id, true);
// and loner_regular's gamedata entry carries "speaker_id" : "guy" -- the generic
// wandering-loner speaker, with real dialogue content behind it. That is all
// player_collect_nearby_interactables needs to offer the talk interaction:
//     if (npc_speaker_id != "no_speaker" && npc_dialogue_has_content(id))
//         if (faction_get_rep_temp(_faction, faction) >= 0)
// Both tests pass for a companion -- the rep test passes for practically anyone,
// since 0 is already the floor -- so standing within 16px of your own companion put
// a "press F to talk" prompt on screen and offered up a stranger's small talk, plus
// whatever heal and repair prompts that speaker has.
//
// Restoring the value obj_npc_parent_Create_0 line 27 sets for every NPC in the
// game is the cleanest way out: the first test short-circuits, no dialogue lookup
// happens at all, and the companion stops competing with the chest you were
// actually trying to open. "no_speaker" is speaker index 0 in speaker.json, so
// alarm[10]'s is_a_quest_giver lookup three frames from now reads exactly what a
// bandit's does -- and cannot hand a companion a quest line.
npc_speaker_id = "no_speaker";

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
