// =============================================================================
//  obj_csq_companion : Clean Up
// -----------------------------------------------------------------------------
//  event_inherited() IS MANDATORY HERE.
//
//  obj_npc_parent_CleanUp_0 releases everything an NPC owns:
//      audio_emitter_free(emitter_shoot / emitter_walk / emitter_talk);
//      path_delete(path_to_target);
//      ds_list_destroy(lista_path_x / lista_path_y);
//      ds_grid_destroy(grid_faction_my);
//
//  A child object that defines CleanUp *replaces* its parent's unless it calls
//  event_inherited(). Omitting it would leak three audio emitters, a path, two
//  ds_lists and a ds_grid for every companion ever spawned -- a slow, cumulative
//  memory leak across a long session.
//
//  It runs first so those resources are freed even if the mod's own bookkeeping
//  fails. CleanUp also fires at room end and game end, when globals may already
//  have been torn down, which is why csq_squad_notify_cleanup swallows its own
//  errors instead of reporting them.
//
//  THE obj_arms_* TEARDOWN IS BELT AND BRACES
//  Each prop's own Step already begins `if (!instance_exists(linked_id))
//  instance_destroy();`, so an orphan cleans itself up on its next frame regardless.
//  This closes the one-frame window in between, during which the prop would still be
//  drawn at a dead companion's last position -- and it costs one loop over a family
//  of objects that almost never has any members.
// =============================================================================

event_inherited();

csq_squad_notify_cleanup(id);

csq_idle_destroy_props(id);
