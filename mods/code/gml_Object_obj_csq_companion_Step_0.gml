// =============================================================================
//  obj_csq_companion : Step
// -----------------------------------------------------------------------------
//  event_inherited() runs the entire vanilla NPC brain:
//      obj_npc_human_parent_Step_0   (weapon presence check)
//        -> obj_npc_parent_Step_0    (the 3978-line state machine)
//
//  It runs FIRST, deliberately. In "human_general" that is what aims, shoots,
//  takes cover and sets `target`, so csq_ai_step() gets to react to a target
//  computed this frame rather than last. In "human_no_move" the vanilla machine
//  does nothing at all, so nothing is lost either way.
//
//  THE hp GUARD IS NOT OPTIONAL
//  obj_npc_parent_Step_0 ends with:
//      if (hp <= 0) { hp = -100; ... instance_destroy(); }
//  GameMaker keeps executing the event after instance_destroy(), so without this
//  check csq_ai_step() would run every death frame against an instance that is
//  already being torn down -- reading a deleted path and writing to a destroyed
//  instance. Testing hp > 0 catches it precisely, because the vanilla code has
//  just stamped -100 over it.
// =============================================================================

event_inherited();

if (hp > 0)
{
    csq_ai_step();
}
