# Case Study: Issue #1249 — Tactical Enemy Movement in Narrow Passages

## Problem Statement

After collisions were added between enemies (so they cannot pass through each other), enemies
misbehave when multiple of them try to move toward the player through narrow passages:

- They push and jostle each other instead of moving tactically
- They do not queue single-file through narrow passages
- If one enemy blocks the path, others should take tactical positions rather than stand still
  pushing

## Current Implementation (Pre-fix)

### Avoidance Systems Already in Place

1. **ORCA (Optimal Reciprocal Collision Avoidance)** via `NavigationAgent2D`
   - `avoidance_enabled = true`, `radius = 24px`, `neighbor_distance = 100px`, `max_neighbors = 10`
   - Each enemy feeds intended velocity to `_nav_agent.set_velocity()`, gets back a safe velocity via
     `_on_avoidance_velocity_computed(safe_velocity)` callback
   - Asynchronous: avoidance velocity is applied the next frame

2. **Separation Force** (`_apply_separation_force`, Issue #1146)
   - Applied every physics frame to all alive enemies
   - `SEPARATION_RADIUS = 60px`, `SEPARATION_STRENGTH = 280 px/s²`
   - Pushes enemy away from all allies within 60px, weighted by proximity

3. **Navigation**: All movement uses `_move_to_target_nav()` which routes via `NavigationAgent2D`
   for pathfinding

### Root Cause of the Problem

The issue manifests in two related but distinct scenarios:

**Scenario A — Many enemies in same narrow passage:**
ORCA avoidance computes safe velocities, but when a corridor is narrower than `2 * radius = 48px`,
ORCA has no valid perpendicular escape direction. Multiple enemies all compute "ZERO" as the
safe velocity, resulting in deadlock — they block each other at the entrance. The separation force
then "jostles" them, causing visible chaos.

**Scenario B — Follower enemies in PURSUING/COMBAT states:**
Multiple enemies in the same pursuit group all set the same nav target (player position or nearby
cover). They all compute an identical path, so N enemies funnel into the same narrow passage at
the same time. There is no "turn-based" or "priority" mechanism to let one enemy go first while
others wait or find alternate positions.

**Key missing behaviors:**
1. **Path-blocked-by-ally detection**: No mechanism detects that the path is blocked by a friendly
   rather than a wall. Enemies use stuck detection (`GLOBAL_STUCK_MAX_TIME = 4s`) which is too
   slow and transitions to SEARCHING rather than to tactical waiting/positioning.
2. **Tactical yielding**: No priority system to let the closest enemy pass while others hold
   position.
3. **No alternate position seeking**: When an ally blocks the forward path, the enemy should look
   for cover nearby to wait, rather than pushing.

## Related Issues & Prior Art in Codebase

| Issue | What was done |
|-------|--------------|
| #1146 | Added ORCA avoidance + separation force to prevent enemy overlap |
| #1119 | Switched patrol to NavigationAgent2D (wall-rubbing fix) |
| #1107 | Machete enemy wall-stuck corner escape |
| #367  | Global stuck detection: PURSUING/FLANKING → SEARCHING after 4s |
| #604  | Grenadier coordination: allies wait for grenade via `_waiting_for_grenadier` flag |

The grenadier coordination pattern (Issue #604) is the most relevant precedent: an enemy can set
`_waiting_for_grenadier = true` and zero its velocity while another enemy acts. We can use a
similar yielding pattern.

## Algorithm Design

### 1. Narrow Passage Detection

To detect whether the path ahead passes through a narrow corridor, we cast two perpendicular
raycasts from the next waypoint (perpendicular to the movement direction). If both sides hit walls
within `NARROW_PASSAGE_HALF_WIDTH = 40px`, the passage is narrow.

```
movement direction →
         |===WALL===|
         |          |
  enemy  → waypoint →
         |          |
         |===WALL===|
         ↑ both sides < 40px → narrow passage
```

### 2. Ally-in-Path Detection

Before entering the narrow passage, cast a raycast along the movement direction (collision_mask
for enemies only, layer 2). If an ally enemy body is within `ALLY_BLOCK_DETECTION_RANGE = 100px`,
the path is considered blocked by an ally.

### 3. Priority Assignment

Priority is based on proximity to player: the enemy closest to the player has the highest priority
and passes first. Others yield.

```gdscript
# Pseudo-code priority check
var my_dist = global_position.distance_to(player_pos)
var ally_dist = blocking_ally.global_position.distance_to(player_pos)
if my_dist > ally_dist:
    # I am farther → I should yield
    yield_to_ally()
```

### 4. Tactical Waiting Behavior

When yielding, an enemy:
1. Stops moving (velocity = Vector2.ZERO)
2. Searches for nearby cover off to the side
3. If cover found → moves to that cover position (takes a tactical waiting position)
4. If no cover → waits in place for `YIELD_MAX_WAIT_TIME = 2.5s`, then forces through

### 5. Integration Point

The detection and yielding logic runs in `_apply_separation_force()` (already called every frame)
or as a new check before `_move_to_target_nav()`. The TacticalMovementComponent is a `RefCounted`
node like `PacifistComponent`.

## Solution Components

### New File: `scripts/components/tactical_movement_component.gd`

`TacticalMovementComponent` (extends RefCounted):

- `is_yielding: bool` — whether this enemy is currently yielding to another
- `yield_timer: float` — how long has been yielding
- `yield_cover_position: Vector2` — alternate cover position while yielding

Methods:
- `check_and_yield(enemy, target_pos, delta) -> bool` — returns true if enemy should yield
- `reset_yield()` — clears yield state

### Modified: `scripts/objects/enemy.gd`

- Add `var _tactical_movement: TacticalMovementComponent` variable
- Initialize in `_ready()`
- Call `_tactical_movement.check_and_yield()` in `_move_to_target_nav()` before applying velocity

### New Test: `tests/unit/test_tactical_movement.gd`

Tests for:
- Ally-in-path detection logic
- Narrow passage detection logic
- Priority assignment (closer enemy has priority)
- Yield timer expiry forces passage

## Known Godot 4 Constraints

- ORCA avoidance callback is async (1-frame delay): `_avoidance_velocity` from callback is used
  the *next* frame. This is fine for yielding since we zero velocity before the callback.
- `get_tree().get_nodes_in_group("enemies")` is called at most once per frame for separation, so
  we can reuse this call for ally detection without extra cost.
- NavigationAgent2D physics layers: enemy bodies are on collision layer 2, obstacles on layer 3.
  To detect enemies (not walls), use `collision_mask = 2` in raycasts.

## Performance Considerations

- Narrow passage check: 2 raycasts per frame when PURSUING/COMBAT moving → negligible
- Ally-in-path check: 1 raycast per frame → negligible
- Group iteration for priority: O(n) over all enemies, same as existing `_apply_separation_force`

## References

- RVO2 paper: van den Berg et al. 2011 — ORCA in narrow corridors requires priority
- Godot NavigationAgent2D avoidance docs
- Issue #604 (grenadier wait pattern) — closest in-codebase precedent
- Issue #1146 (ORCA + separation) — the original separation work

---

## Session 2 — Bug Report 2026-03-21 (post-initial-fix)

### Game Log
`game_log_20260321_080731.txt` — LabyrinthLevel, 5+5 enemies, Hard difficulty.

### Bug 1: Enemies stop moving while PURSUING

**Symptom:** Owner reported enemies stop moving during PURSUING.

**Root cause (confirmed by code review):**
`_should_yield_to_closer_ally()` in `TacticalMovementComponent` iterated **all** enemies in the
`"enemies"` group — including enemies in other rooms. In a level with 10+ enemies, most pursuing
enemies had at least one other enemy that happened to be closer to the player, so 4-5 enemies
would simultaneously yield (velocity = 0). Only the single closest enemy ever moved.

**Fix:** Added `YIELD_NEARBY_RADIUS = 200 px` check. Only enemies within 200 px of the yielding
enemy can trigger a yield. Enemies in other rooms are ignored.

### Bug 2: Enemies collide while SEARCHING

**Symptom:** Owner reported enemies collide while searching. Log shows repeated
`SEARCHING: Stuck at wp N, skipping` entries for all searching enemies simultaneously,
indicating they bumped into each other and triggered stuck detection.

**Root cause (confirmed by code review):**
`_process_searching_state()` computed velocity directly (`velocity = dir * move_speed * 0.7`)
and called `move_and_slide()` directly without feeding the velocity to `NavigationAgent2D.set_velocity()`.
This meant the ORCA avoidance callback (`_on_avoidance_velocity_computed`) was never triggered
during SEARCHING — enemies could not steer around each other. Separation force was applied afterwards
but couldn't overcome direct collisions when multiple enemies converged on the same search waypoints.

**Fix:** Before `move_and_slide()`, call `_nav_agent.set_velocity(intended_search_vel)` and use
`_avoidance_velocity` if ORCA has already computed a safe velocity. This is identical to how
`_move_to_target_nav()` handles it for PURSUING/COMBAT states.

### Timeline
- `08:07:54` — Player becomes invisible (used invisibility suit), enemies lose target
- `08:07:55` — All 4 active enemies enter SEARCHING simultaneously at nearly the same position
- `08:07:57` — All enemies immediately start reporting "Stuck at wp 0, skipping"
- Enemies skip through all search waypoints rapidly, never making progress
- Pattern repeats with expanding search rings — enemies are gridlocked together

---

## Session 3 — Bug Report 2026-03-21 08:48 (post-session-2-fix)

### Game Logs
- `game_log_20260321_084500.txt` — LabyrinthLevel, 5 enemies, Hard difficulty (short run ~15s)
- `game_log_20260321_084548.txt` — LabyrinthLevel, 10 enemies + Grenadier, Hard difficulty (long run ~2m)

### Screenshot

Owner reported enemies still collide and get stuck in corners. Screenshot shows multiple enemies
with "(SEARCHING)" labels piled up at a corner/corridor mouth.

### Root Cause 1: Narrow-Passage Detection Too Narrow

**Symptom:** Enemies in PURSUING state pile up at corridor mouths and corners.

**Root cause:** `NARROW_PASSAGE_HALF_WIDTH = 44px` required corridors narrower than 88px total to
trigger tactical yielding. The LabyrinthLevel corridors near the Office 2 area appear to be
90–120px wide — just outside the detection threshold. Enemies would pack in without yielding.

**Fix:** Increased `NARROW_PASSAGE_HALF_WIDTH` from 44→64px. Now corridors up to 128px wide
trigger tactical yielding when an ally is blocking ahead.

**Fix:** Increased `ALLY_BLOCK_DETECTION_RANGE` from 80→100px. Blockers slightly farther ahead
are now detected, giving yielding enemies more time to step aside.

### Root Cause 2: SEARCHING Enemies Not Subject to Tactical Yielding

**Symptom:** Searching enemies pile up in corridor mouths (visible in screenshot with SEARCHING
labels clustered together).

**Root cause:** `TacticalMovementComponent.check_and_yield()` was only called from
`_move_to_target_nav()`, which handles PURSUING/COMBAT/FLANKING. The `_process_searching_state()`
movement path had no yielding — searching enemies would all try to navigate the same corridor
mouth simultaneously, colliding.

**Fix:** Added `check_and_yield()` call in `_process_searching_state()` before the movement
section. Searching enemies now yield in narrow passages just like pursuing enemies. The yielding
frame also resets `_search_stuck_timer` so the stuck-skip doesn't fire while yielding.

**Fix:** Added `reset_yield()` call in `_transition_to_searching()` so any lingering yield state
from a prior PURSUING phase is cleared on transition.

### Root Cause 3: Slow Stuck-Skip in SEARCHING Causes Long Collision Windows

**Symptom:** Log shows `SEARCHING: Stuck at wp 3, skipping` — Enemy2 stuck for 2s at each
blocked corner waypoint. Multiple searching enemies simultaneously occupy the same corner.

**Root cause:** `SEARCH_STUCK_MAX_TIME = 2.0s` — enemies waited 2 seconds at each blocked
waypoint before skipping to the next. When ORCA partially reduces velocity (e.g. 0.5 px/frame
instead of 0), progress check (`< 10px`) fires but the timer runs for 2 full seconds. Multiple
enemies stuck at the same corner for 2s each × multiple waypoints = long collision windows.

**Fix:** Reduced `SEARCH_STUCK_MAX_TIME` from 2.0→0.8s. Searching enemies now skip unreachable
waypoints ~2.5× faster, reducing the time window during which they pile up in corners.

### Timeline (game_log_20260321_084548.txt)

- `08:45:49` — 10 enemies spawned (Enemy1-10) + Grenadier
- `08:45:52` — Scene transition to larger level with 10 enemies
- `08:46:07` — Enemy7, Enemy10 (PATROL) start reporting PATROL STUCK repeatedly at same positions
  (Enemy7 at ~(1610,897), Enemy10 at ~(1170,1600)) — patrol routes in tight corners
- `08:46:44` — Enemy2 GLOBAL STUCK for 20s while PURSUING → enters SEARCHING at (885,698)
- `08:46:44` — Enemy4 GLOBAL STUCK for 20s while PURSUING → enters SEARCHING at (548,976)
- `08:46:45`–`08:47:13` — Enemy2 SEARCHING: stuck at wp3 (2s), then wp4 → expand outer ring,
  stuck again at wp2 (2s) → expand again → eventually spots player at 08:47:33
- `08:47:35` — Enemy3 enters SEARCHING at (548,975) — same location as Enemy4

### Verification

The new fixes address all three root causes:
1. Wider detection (64px) catches LabyrinthLevel corridor widths
2. SEARCHING now respects tactical yielding, so searching enemies don't pile up in corridor mouths
3. Faster waypoint skip (0.8s) reduces collision window at corners

