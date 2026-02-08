# Case Study: Improved Enemy Search Behavior (Issue #650)

## Problem Statement

The issue requests two improvements to enemy search behavior:
1. **Realistic looking behavior**: Enemies should look around more realistically when searching (sometimes looking in directions other than directly at the player's last known position)
2. **Coordinated group search**: When multiple enemies search for a player, each enemy should cover their own unique zone without duplicating areas for optimal search speed

## Current Implementation Analysis

### Search State (SEARCHING - Issue #322)
- Enemies use a **square spiral pattern** from the last known player position
- Each enemy generates waypoints independently using `_generate_search_waypoints()`
- At each waypoint, enemies scan by rotating at constant angular speed (`rotation += delta * 1.5`)
- **Problem**: Scanning is uniform and mechanical - always rotates at the same speed
- **Problem**: During SEARCHING state, enemies still face toward the player's actual position (Priority 2 in `_update_enemy_model_rotation()`) rather than scanning realistically

### Individual Zone Tracking
- Each enemy has `_search_visited_zones: Dictionary` to track visited 50px grid cells
- But there is **no coordination between enemies** - each enemy tracks only its own visits
- Multiple enemies searching the same area will overlap completely

### Intel Sharing
- Enemies share intel via `_share_intel_with_nearby_enemies()` every 0.5s
- Shares memory (suspected position + confidence) and prediction hypotheses
- But this does **NOT** share visited search zones

## Solution Design

### 1. Realistic Scanning Behavior
Instead of always facing the player during SEARCHING:
- Remove SEARCHING from Priority 2 rotation (currently forces facing toward actual player position)
- Add natural head/body scanning at each waypoint:
  - Random scan target angles (not just constant rotation)
  - Occasional pauses during scan
  - Sometimes look "wrong" direction before checking correct direction
  - Vary scan speed per waypoint

### 2. Coordinated Group Search (Voronoi-based Zone Assignment)
New `GroupSearchCoordinator` component (RefCounted, no scene needed):
- When multiple enemies enter SEARCHING with similar centers, they coordinate
- Uses **angle-sector division**: divides 360 degrees around search center by number of searching enemies
- Each enemy gets assigned a unique sector to search
- Enemies generate spiral waypoints only within their assigned sector
- When enemy finishes sector, takes unclaimed sectors or adjusts

### Key Algorithms
- **Voronoi-inspired zone division**: For N enemies searching around a center point, divide the area into N angular sectors. Each enemy's spiral pattern is constrained to their sector.
- **Realistic scanning**: Use randomized scan targets from a distribution weighted toward the search direction, with random "look-away" moments

## References

- [Voronoi Diagrams in Game Development](https://www.gamegeniuslab.com/tutorial-post/voronoi-diagrams-in-game-development-procedural-maps-ai-territories-stylish-effects/)
- [How to Use Voronoi Diagrams to Control AI](https://gamedevelopment.tutsplus.com/tutorials/how-to-use-voronoi-diagrams-to-control-ai--gamedev-11778)
- [Dynamic Guard Patrol in Stealth Games (AAAI)](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903)
- [Patrolling AI Systems in Video Games](https://www.researchgate.net/publication/364090728_Patrolling_AI_Systems_in_Video_Games)

## Implementation Files

| File | Changes |
|------|---------|
| `scripts/ai/group_search_coordinator.gd` | **NEW** - Coordinates zone assignment for group search |
| `scripts/objects/enemy.gd` | Modified - Integrate coordinator, fix scan rotation, add realistic scanning |
| `scripts/ai/enemy_actions.gd` | Modified - Add CoordinatedSearchAction |
| `tests/unit/test_group_search_coordinator.gd` | **NEW** - Unit tests |

## Post-Implementation Crash Fix

### Symptoms
After the initial implementation, the game crashed when enemies entered SEARCHING state.
Three crash logs were provided by the repo owner (see `crash-logs/` directory).

### Root Cause Analysis

**Problem:** The `_unregister_from_group_search()` function was only called in 2 of 10 non-SEARCHING state transition functions (`_transition_to_idle` and `_transition_to_combat`). The remaining 8 transitions were missing cleanup:
- `_transition_to_seeking_cover()`
- `_transition_to_in_cover()`
- `_transition_to_flanking()`
- `_transition_to_suppressed()`
- `_transition_to_pursuing()`
- `_transition_to_assault()`
- `_transition_to_evading_grenade()`
- `_transition_to_retreating()`

Additionally, `_on_death()` did not unregister from the coordinator, leaving stale references when enemies died while searching.

**Crash Sequence:**
1. Multiple enemies enter SEARCHING state (e.g., after LastChance effect resets memory)
2. Each enemy registers with `GroupSearchCoordinator` via `get_or_create()`
3. An enemy transitions out of SEARCHING to another state (e.g., spots player -> COMBAT -> RETREATING)
4. The coordinator is NOT cleaned up - stale reference remains
5. The coordinator's `_enemy_order` and `_enemy_sectors` grow with entries for enemies no longer searching
6. When enemies re-enter SEARCHING or the coordinator tries to access stale enemy data, the game crashes

**Evidence from crash logs:**
- All 3 logs show crashes occurring during SEARCHING state processing
- Logs end abruptly without error messages (indicating native-level crash, not GDScript error)
- Crash occurs within 1-2 seconds of enemies entering SEARCHING state
- No "sector" or "coordinator" debug messages visible (coordinator logging was off by default)

### Fix Applied (First Pass)
1. Added `_unregister_from_group_search()` to all 8 missing state transition functions
2. Added `_unregister_from_group_search()` to `_on_death()` for cleanup when enemy dies while searching
3. Added division-by-zero guard in `get_sector_angles()` for edge case with empty coordinator
4. Added 3 new edge case unit tests (empty coordinator, nonexistent enemy unregister, double unregister)

## Second Crash Report (Native Crash on Bulk SEARCHING Transition)

### Symptoms
After the first fix, the repo owner reported the game still crashes when search begins.
A new crash log was provided (`crash-logs/game_log_20260208_173955.txt`).

### Root Cause Analysis

**Crash pattern:** Log shows 6 enemies entering SEARCHING simultaneously at 17:40:17
after LastChance effect ends. The log ends abruptly at line 1088 with no error messages,
indicating a native crash (segfault) rather than a GDScript error.

**Contributing factors identified:**

1. **Double `move_and_slide()` call** — `_process_searching_state()` called `move_and_slide()`
   inline (line 2253), and then `_physics_process()` called it again (line 899). With 6 enemies
   simultaneously starting navigation, this meant 12 collision processing calls per frame in
   the first physics tick, overwhelming the physics engine.

2. **No navigation deferral** — Enemies started requesting navigation paths immediately
   in the same physics frame they transitioned. When `_reset_all_enemy_memory()` is called
   from `_process()` (via LastChance manager), enemies transition to SEARCHING before
   `_physics_process()` runs. The first `_physics_process()` call then hits NavigationServer2D
   for 6 enemies simultaneously with potentially stale navigation maps.

3. **Stale coordinators across scene reloads** — `GroupSearchCoordinator._active_coordinators`
   is a static Dictionary that persists across scene loads. If enemies are freed without proper
   cleanup, stale coordinators with invalid enemy references accumulate.

4. **Missing `_exit_tree()` cleanup** — When enemies are removed from the scene tree
   (e.g., level reload), they weren't unregistered from the coordinator.

**Same pattern in `_process_evading_grenade_state()`** — Also had inline `move_and_slide()`
calls duplicating the `_physics_process()` call.

### Fix Applied (Second Pass)
1. **Removed double `move_and_slide()`** from `_process_searching_state()` and
   `_process_evading_grenade_state()` — velocity is set, but `move_and_slide()` is only
   called once per frame in `_physics_process()` (line 899)
2. **Added 2-frame navigation deferral** via `_search_init_frames` counter — enemies wait
   2 physics frames after transition before starting navigation, allowing nav map to sync
3. **Stale coordinator cleanup** in `get_or_create()` — validates enemy references and
   removes coordinators where all registered enemies are invalid
4. **Added `_exit_tree()`** to enemy.gd — calls `_unregister_from_group_search()` when
   enemy is removed from scene tree
5. **Added null/validity checks** in `register_enemy()` and `unregister_enemy()`

## Third Crash Report (Single Enemy SEARCHING Transition)

### Symptoms
After the second fix, the repo owner reported the game still crashes when search begins.
A new crash log was provided (`crash-logs/game_log_20260208_191327.txt`).

### Root Cause Analysis

**Crash pattern:** Unlike the previous crashes (bulk 6-enemy transitions), this crash occurs
with a **single enemy** (Enemy4) transitioning from PURSUING to SEARCHING via the global stuck
detection mechanism. The log shows:
1. Enemy4 stuck at (780.9, 901.8) for 4.0 seconds, triggering `GLOBAL STUCK` detection
2. `_transition_to_searching()` completes successfully (log: "SEARCHING started, waypoints=5")
3. One more physics frame processes (ROT_CHANGE logged for Enemy4)
4. Enemy1 transitions COMBAT → PURSUING (normal state change)
5. Log ends abruptly — native crash (segfault)

**Key difference from previous crashes:** Only 1 enemy transitions to SEARCHING, so the bulk
transition theory (double `move_and_slide`, nav map sync) does not apply here.

**Identified root causes:**

1. **`instance_from_id()` usage in `get_or_create()`** — Called during `_physics_process` to
   validate enemy references in the static coordinator dictionary. Godot 4.3 has known issues
   with `instance_from_id()` (see [godotengine/godot#108246](https://github.com/godotengine/godot/issues/108246),
   [godotengine/godot#32383](https://github.com/godotengine/godot/issues/32383)):
   - Instance IDs can be reused after an object is freed, causing `instance_from_id()` to
     return an unrelated object
   - In release builds, accessing freed object memory can cause segfaults without GDScript
     error messages

2. **Static Dictionary access during `_physics_process`** — `GroupSearchCoordinator.get_or_create()`
   iterates `_active_coordinators` (a static Dictionary) and calls methods on RefCounted objects
   during `_physics_process`. If a coordinator's internal state is inconsistent (e.g., from a
   previous frame's partial cleanup), this could cause engine-level corruption.

3. **Synchronous coordinator registration during physics frame** — The coordinator setup
   (`get_or_create`, `register_enemy`, `_generate_search_waypoints`) was all done inline
   in `_transition_to_searching()` which runs inside `_physics_process`. This heavy operation
   during physics processing could interact poorly with the engine's internal state.

### Fix Applied (Third Pass)

1. **Deferred coordinator registration** — `_transition_to_searching()` now only sets up basic
   state and generates waypoints using the original solo spiral pattern. Coordinator registration
   is deferred to the next idle frame via `call_deferred("_deferred_coordinator_setup")`. This
   completely isolates coordinator code from `_physics_process` execution.

2. **Replaced `instance_from_id()` with WeakRef pattern** — `get_or_create()` now uses
   `WeakRef.get_ref()` to check enemy validity instead of `instance_from_id()`. WeakRef is
   the recommended Godot pattern for safely tracking object lifecycle without the risks of
   instance ID reuse or freed object access.

3. **Safety guards in deferred setup** — `_deferred_coordinator_setup()` checks:
   - `is_instance_valid(self)` — enemy hasn't been freed
   - `_is_alive` — enemy hasn't died
   - `_current_state == AIState.SEARCHING` — enemy hasn't already left SEARCHING

4. **Coordinator only regenerates waypoints when needed** — If the coordinator determines
   that coordination is active (≥2 enemies), it regenerates waypoints with sector constraints.
   Otherwise, the original solo waypoints are used as-is.
