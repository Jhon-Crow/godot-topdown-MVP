# Issue #1446: Shieldbearer as Dynamic Cover for Allied Enemies

## Problem Statement

The shieldbearer enemy has a formation system (`EnemyShieldComponent._update_formation`) that positions nearby allies behind it via `set_formation_follow_target`. However, allies following behind the shieldbearer never enter the `IN_COVER` AI state. The cover system (`CoverComponent`) only detects static obstacles on `collision_mask=4` via raycasts, so the shieldbearer's body/shield is invisible to cover detection. Allies walk behind the shield but gain none of the AI benefits of being in cover (reduced exposure, suppressive fire responses, GOAP `in_cover` world state).

## How Similar Games Solve This

**SWAT 4 / Ready or Not:** Shield operators serve as mobile cover. Teammates stack behind the shield in a column formation. The AI uses a "cover provider" abstraction where the shield itself is treated as a directional cover source, not a static obstacle. Line-of-sight checks from the threat to the follower pass through the shield's blocking arc.

**Rainbow Six (Vegas/Siege):** Mobile shield operators provide a "cover cone" to teammates behind them. The game checks whether allies are within the shield's shadow relative to the threat direction, rather than requiring a physical raycast hit on a static obstacle.

**XCOM 2:** Cover is tile-based. The "mobile cover" concept is handled by giving adjacent allies a cover bonus when near a shieldbearer. This is a stat modifier approach rather than a spatial raycast approach.

**General pattern in tactical AI:** The dominant approach is a **virtual cover provider** -- the shieldbearer registers itself as a dynamic cover source. Allies check whether they are within the shieldbearer's "shadow cone" (the angular region behind the shield relative to the threat). If yes, they receive cover state benefits without needing a raycast to hit a physical obstacle.

## Proposed Solution for This Codebase

**Approach: Shadow-cone virtual cover.** Two changes are needed:

1. **Shieldbearer advertises cover:** `EnemyShieldComponent` already calls `set_formation_follow_target` on nearby allies. Extend this to also call a new method `set_dynamic_cover_provider(shielder)` on the ally, passing the shieldbearer reference.

2. **Allies recognize dynamic cover:** In `enemy.gd`, when an ally has a valid `_formation_shielder` and is positioned behind it (within the shield's shadow cone relative to the player/threat), treat the ally as being in cover. Specifically:
   - Add a `_is_behind_shield() -> bool` function that checks if the ally is within ~60 degrees behind the shieldbearer relative to the threat direction.
   - In the AI state processing, allow transition to `IN_COVER` when `_is_behind_shield()` returns true, even without `CoverComponent` finding a static obstacle.
   - Set `_goap_world_state["in_cover"] = true` when behind the shield.

3. **Cover validity tracking:** When the shield breaks (`_shield_up = false`) or the shielder dies, allies must immediately lose cover status. The existing cleanup at line 1275 of `enemy.gd` already nullifies `_formation_shielder` when the shield drops -- extend this to also clear the dynamic cover state.

This approach requires no changes to `CoverComponent` or its `collision_mask=4` raycast system. The static cover system remains untouched; dynamic shield cover is a parallel path.

## Relevant Libraries and Components

- **No external Godot plugins needed.** The shadow-cone check is simple vector math (dot product of normalized direction vectors).
- The existing `EnemyShieldComponent.FORMATION_RADIUS` (350px) and `FORMATION_OFFSET` (80px) constants already define the spatial relationship.
- The GOAP action system (`scripts/ai/enemy_actions.gd`) already uses `in_cover` as a world state key, so no planner changes are needed -- only the world state update logic.
- `CoverRaycastMonitor` debug overlay could optionally be extended to visualize the shield shadow cone for debugging.
