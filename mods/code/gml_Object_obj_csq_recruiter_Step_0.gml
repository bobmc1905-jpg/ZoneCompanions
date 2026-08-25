// =============================================================================
//  obj_csq_recruiter : Step
// -----------------------------------------------------------------------------
//  event_inherited() runs the vanilla NPC brain, exactly as the companion's Step
//  does. In "human_no_move" that machine does nothing but face the player, so
//  this event exists only to guarantee the recruiter is actually SEEN.
//
//  WHY VISIBILITY HAS TO BE PINNED HERE
//  obj_npc_parent_Step_0 ramps image_alpha up and down from the player's line of
//  sight -- but the whole block is wrapped in `if (!is_in_hub())`. In the hub it
//  never runs, so an NPC's alpha is whatever it happened to be, and nothing ever
//  restores it. Every vanilla hub NPC is placed by the room editor and never
//  touched, so vanilla never notices; a runtime-created one has no such luck.
//  Forcing alpha and visible here costs two assignments a frame and removes the
//  entire class of "the recruiter is there but you cannot see him" failure.
//
//  DEPTH IS RE-DERIVED, NOT LEFT TO THE CREATE CALL
//  obj_npc_parent_Step_0 line 2 sets depth = -y - sprite_height/2 every frame, so
//  the depth passed to instance_create_depth is irrelevant. The bar counter and
//  shelves are obj_solid children, drawn from
//      depth = -y - sprite_height + sprite_yoffset
//  which can land in front of an NPC standing at the same y. recruiter_depth_bias
//  is subtracted here so a player who ends up with a recruiter hidden behind bar
//  furniture can pull him forward from the ini without a rebuild. Applied AFTER
//  event_inherited(), because that is what wrote depth this frame.
//
//  THE hp GUARD MIRRORS THE COMPANION'S STEP
//  obj_npc_parent_Step_0 ends in `if (hp <= 0) { hp = -100; ... instance_destroy(); }`
//  and GameMaker keeps running the event afterwards, so nothing below should touch
//  an instance that is already being torn down. The recruiter cannot be shot in the
//  hub, but the guard costs one comparison and removes the question.
// =============================================================================

event_inherited();

if (hp > 0)
{
    image_alpha = 1;
    visible     = true;

    if (sprite_exists(sprite_index))
    {
        depth = -y - (sprite_get_height(sprite_index) / 2) - csq_cfg("recruiter_depth_bias");
    }
}
