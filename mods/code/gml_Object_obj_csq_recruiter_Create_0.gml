// =============================================================================
//  obj_csq_recruiter : Create
// -----------------------------------------------------------------------------
//  The merc-hire NPC that stands by the bar in the bunker. It is deliberately
//  built exactly like a companion (obj_csq_companion) -- same descent from
//  obj_npc_human_parent, same init order -- because that path is already proven
//  to spawn a stable, non-crashing NPC. The differences from a companion are all
//  subtractive: it never moves, never fights, and is never added to the roster.
//
//  It is not registered with csq_squad, so csq_squad_notify_cleanup ignores its
//  CleanUp, csq_squad_prune never sees it, and it occupies no formation slot. The
//  only mod code that touches it lives in csq_recruit (spawn, proximity, menu).
//
//  ORDER MIRRORS THE COMPANION CREATE EVENT
//    event_inherited()   builds the NPC (obj_npc_human_parent -> obj_npc_parent).
//    npc_setup(preset)   fills faction, hp, sprites and state from the preset. The
//                        preset is appearance only -- validated in csq_recruit so
//                        an unknown id cannot reach npc_get_hp's fatal trace_error.
//    npc_setup_weapon()  matches the companion's proven init exactly. Skipping it
//                        was considered, but obj_npc_human_parent's Alarm_9 spawns a
//                        linked weapon regardless and reads arma_now, so mirroring
//                        the companion path is the lower-risk choice. The recruiter
//                        never fires it: "human_no_move" runs no targeting code.
//    csq_faction_apply() puts it on the Companion faction so nothing ever targets
//                        it (there are no enemies in the hub regardless, but this
//                        also keeps it off the native talk-detection's hostile path).
//    csq_ff_disarm_grenades()
//                        it carries no live ordnance, for the same reason companions
//                        do not.
//    state="human_no_move"
//                        the inert vanilla host state (see csq_ai). With no Step
//                        event of its own this object inherits obj_npc_parent's Step,
//                        which in this state does nothing -- so the recruiter simply
//                        stands where it was placed.
//    csq_recruiter=true  a marker so any future squad scan can exclude it cheaply.
// =============================================================================

event_inherited();

var _preset = csq_recruit_resolve_preset(csq_cfg("recruiter_preset"));

npc_setup(_preset);
npc_setup_weapon();

csq_faction_apply(id);
csq_ff_disarm_grenades();

// Never wander. "human_no_move" is a verified member of obj_npc_parent_Step_0's
// state switch (see csq_ai); any non-vanilla string here would hard-crash.
state = "human_no_move";

// Identifies this instance as the recruiter rather than a companion.
csq_recruiter = true;

csq_log_debug("recruiter: created preset=" + string(_preset) +
              " at " + string(floor(x)) + "," + string(floor(y)));
