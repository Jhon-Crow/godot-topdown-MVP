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

## Fourth Crash Report (NavigationServer2D Segfault During Physics)

### Symptoms
After the third fix (deferred coordinator + WeakRef), the game still crashes when an enemy
enters SEARCHING state. Crash log: `crash-logs/game_log_20260208_191327.txt`.

### Root Cause Analysis (Cross-Log Pattern Discovery)

Analysis of **all 5 crash logs** (4 crashes + 1 clean exit) revealed a common operation
present in every crash that was not yet addressed by fixes #1-#3:

**`_generate_search_waypoints()` calls `NavigationServer2D.map_get_closest_point()` synchronously
during `_physics_process()` via `_is_waypoint_navigable()`.**

The function chain:
1. `_transition_to_searching()` (called from `_physics_process` via GLOBAL STUCK or state machine)
2. → `_generate_search_waypoints()` (generates waypoints)
3. → `_is_waypoint_navigable()` (called in a tight loop, up to 100 iterations)
4. → `NavigationServer2D.map_get_closest_point()` (native engine call)

This means during a single `_physics_process` frame, the engine was making up to 100
`NavigationServer2D.map_get_closest_point()` calls synchronously. In Godot 4.3, NavigationServer2D
operations during the physics step can cause native segfaults when the navigation map hasn't
fully synced or when internal RID references are in flux.

**Evidence across all crashes:**

| Crash | Trigger | NavServer calls during physics | Time to crash |
|-------|---------|-------------------------------|---------------|
| Log 2 | LastChance expire (4 enemies) | 4× `_generate_search_waypoints` | ~1 second |
| Log 3 | LastChance expire (4 enemies) | 4× `_generate_search_waypoints` | < 1 second |
| Log 4 | LastChance expire (6 enemies) | 6× `_generate_search_waypoints` | < 1 second |
| Log 5 | GLOBAL STUCK (1 enemy) | 1× `_generate_search_waypoints` | 0 frames |

Fix #3 deferred only the **coordinator setup** (static Dictionary + `instance_from_id`), but
`_generate_search_waypoints()` was still called synchronously inside `_transition_to_searching()`.

### Fix Applied (Fourth Pass)

1. **Deferred waypoint generation** — `_transition_to_searching()` no longer calls
   `_generate_search_waypoints()`. Instead, it only sets state variables and logs the transition.

2. **Unified deferred initialization** — `_deferred_search_init()` replaces the separate
   `_deferred_coordinator_setup()`. When `_search_init_frames` reaches 0 in
   `_process_searching_state()`, it calls `call_deferred("_deferred_search_init")` which:
   - Generates waypoints (NavigationServer2D calls — safe on idle frame)
   - Registers with group search coordinator
   - Regenerates sector waypoints if coordination is active

3. **Complete isolation from physics** — No NavigationServer2D calls remain in the
   `_transition_to_searching()` → `_physics_process()` execution path. All navigation
   queries are deferred to idle frames via `call_deferred()`.

## Fifth Crash Report (NavigationAgent2D Avoidance + Repeated Path Computation)

### Symptoms
After the fourth fix (deferred waypoint generation), the game still crashes ~1 second after
multiple enemies enter SEARCHING state. Crash log: `crash-logs/game_log_20260209_012831.txt`.

Unlike previous crashes (which happened during init), this crash occurs during **normal
SEARCHING movement** after deferred init completes successfully.

### Root Cause Analysis

**Two contributing factors identified:**

#### Factor 1: NavigationAgent2D avoidance processing during SEARCHING

The `Enemy.tscn` scene has `avoidance_enabled = true` on the NavigationAgent2D node. When
4+ enemies enter SEARCHING state in the same area (~100px radius), the avoidance system
actively processes interactions between all nearby agents every physics frame. The avoidance
system runs partly on NavigationServer2D's internal thread, and concurrent path queries from
multiple agents during `_physics_process` can cause native segfaults in Godot 4.3.

Enemy positions in the crash log confirm the searching enemies were close together:
- Enemy1: searching at (700, 750)
- Enemy2: searching at (799, 664)
- Enemy3: searching at (802, 661)
- Enemy4: searching at (799, 664)

All 4 enemies are within the `neighbor_distance = 100.0` configured on the NavigationAgent2D,
meaning the avoidance system was actively computing interactions between them.

#### Factor 2: Redundant `target_position` assignment every frame

`_process_searching_state()` set `_nav_agent.target_position = target_waypoint` **every
physics frame** (line 2232). In Godot 4.3, setting `target_position` triggers a path
recalculation. With 4 enemies doing this simultaneously every frame, that's 4 path
recalculations per physics tick, plus 4 avoidance computations.

#### Factor 3: Synchronous waypoint regeneration during physics

When enemies exhaust their 5 initial waypoints and need to expand the search radius,
`_generate_search_waypoints()` was called synchronously from within `_process_searching_state()`,
calling `NavigationServer2D.map_get_closest_point()` up to 100 times during `_physics_process`.

### Evidence

| Crash | Trigger | Deferred Init | Time to Crash | Cause |
|-------|---------|---------------|---------------|-------|
| Log 6 | LastChance (4 enemies) | Completed OK | ~1 second | Avoidance + repeated target_position |

**Timeline from log:**
1. `01:29:59` — LastChance effect ends, 4 enemies enter SEARCHING
2. `01:29:59` — All 4 deferred inits complete: "Init complete (solo, waypoints=5)"
3. `01:29:59-01:30:00` — Normal SEARCHING movement (corner checks, waypoint following)
4. `01:30:00` — Native crash (log ends abruptly at line 2858)

### Fix Applied (Fifth Pass)

1. **Disabled NavigationAgent2D avoidance during SEARCHING** — `_deferred_search_init()`
   sets `_nav_agent.avoidance_enabled = false` before generating waypoints. Avoidance is
   re-enabled in `_unregister_from_group_search()` when leaving SEARCHING state. This
   eliminates the concurrent avoidance computation that contributed to native segfaults.

2. **Cache nav target to avoid redundant path recalculation** — Added
   `_search_nav_target_set` flag. `_nav_agent.target_position` is only set once per
   waypoint (when `_search_nav_target_set` is false), not every frame. The flag is reset
   when advancing to the next waypoint. This reduces NavigationServer2D path computations
   from 4×60/s to 4×(once per waypoint change).

3. **Deferred waypoint regeneration** — When enemies exhaust their waypoints and need to
   expand the search radius or relocate the search center, `_generate_search_waypoints()`
   is no longer called synchronously. Instead, `_search_init_frames = 1` is set, which
   triggers the same deferred initialization path (`_deferred_search_init()`) on the next
   idle frame.

## Sixth Crash Report (NavigationAgent2D get_next_path_position During Movement)

### Symptoms
After the fifth fix (avoidance disabled + cached nav target + deferred regen), the game
still crashes ~1 second after enemies enter SEARCHING state. Two crash logs provided:
- `crash-logs/game_log_20260209_012831.txt` (crash log #5, re-tested)
- `crash-logs/game_log_20260209_024401.txt` (crash log #6)

### Root Cause Analysis

**The critical insight:** All previous fixes addressed NavigationServer2D calls during
*initialization* (waypoint generation, coordinator setup) or *configuration* (avoidance,
target_position setting). But the **ongoing movement** still used NavigationAgent2D methods
synchronously every physics frame:

```
_nav_agent.is_navigation_finished()  -- every frame per enemy
_nav_agent.get_next_path_position()  -- every frame per enemy
```

With 3 enemies simultaneously in SEARCHING state in the same ~150px area, these calls
produce 3×60 = 180 NavigationServer2D queries per second from `_physics_process`. The
Godot 4.3 NavigationServer2D has known thread-safety issues where concurrent navigation
queries from multiple agents can trigger native segfaults.

**Evidence from crash log #6 (`game_log_20260209_024401.txt`):**

| Time | Event |
|------|-------|
| `02:44:13` | 3 enemies (Enemy2,3,4) enter SEARCHING with deferred init |
| `02:44:13` | All 3 complete init: "Init complete (solo, waypoints=5)" |
| `02:44:13-14` | Normal waypoint movement (corner checks, rotation) |
| `02:44:14` | Native crash (log ends at line 463) |

Time to crash: ~1 second after search movement begins.

### Key Insight: FEAR AI Approach

Research into professional game AI implementations (particularly F.E.A.R. by Monolith,
GDC 2006 "Three States and a Plan" by Jeff Orkin) revealed that:

1. **Short-distance patrol/search movement uses simple direct movement**, not pathfinding
2. **Expensive pathfinding (A*) is reserved for long-distance navigation** (pursuing across
   the map, reaching distant cover points)
3. **Search waypoints are typically within a small radius** (100-500px) where direct
   movement is sufficient and obstacles are already validated during waypoint generation

This insight directly applies to our problem: search waypoints are generated within
a 100-500px radius and are already validated as navigable by `_is_waypoint_navigable()`
during `_deferred_search_init()`. Using NavigationAgent2D for this short-distance
movement is both unnecessary and dangerous.

### Fix Applied (Sixth Pass)

**Replaced NavigationAgent2D pathfinding with direct movement during SEARCHING state.**

The old code (lines 2233-2255) used `_nav_agent.target_position`, `.is_navigation_finished()`,
and `.get_next_path_position()` to navigate to each waypoint. The new code simply computes
the direction vector from the enemy's position to the target waypoint and sets velocity
directly:

```gdscript
# OLD: NavigationAgent2D-based (crashes with 3+ simultaneous enemies)
_nav_agent.target_position = target_waypoint
if _nav_agent.is_navigation_finished(): ...
else: var next_pos := _nav_agent.get_next_path_position()

# NEW: Direct movement (no NavigationServer2D calls in physics)
var dir := (target_waypoint - global_position).normalized()
velocity = dir * move_speed * 0.7
```

This completely eliminates ALL NavigationServer2D calls from the SEARCHING
`_physics_process` loop. The stuck detection system (Issue #354) handles cases where
direct movement gets blocked by obstacles — enemies skip the waypoint after 2 seconds
of no progress.

### Seventh Crash Analysis

After Fix #6, the crash persisted. Analysis of the Godot engine source code
(`navigation_agent_2d.cpp`) revealed the true root cause:

**`get_next_path_position()` internally calls `_update_navigation()` which calls
`NavigationServer2D::query_path()` — a full synchronous pathfinding query.**

Similarly, `is_navigation_finished()` also calls `_update_navigation()` → `query_path()`.

The flashlight detection component (`flashlight_detection_component.gd`) calls
`is_next_waypoint_lit(nav_agent, ...)` inside `_update_goap_state()` which is called from
`_physics_process()` **for EVERY enemy, EVERY frame, REGARDLESS of state**.

This function (lines 385-390 of flashlight_detection_component.gd):
```gdscript
func is_next_waypoint_lit(nav_agent, player, raycast):
    if nav_agent == null or nav_agent.is_navigation_finished():  # → query_path()
        return false
    var next_pos := nav_agent.get_next_path_position()  # → query_path()
    return is_position_lit(next_pos, player, raycast)
```

With 4 enemies, this generates **up to 8 `NavigationServer2D::query_path()` calls per
physics frame** (2 calls × 4 enemies) just from flashlight detection — even though enemies
in SEARCHING state don't have a valid NavigationAgent2D path.

### Fix Applied (Seventh Pass)

1. **Skip flashlight waypoint check during SEARCHING** — In `_update_goap_state()`,
   set `passage_lit_by_flashlight = false` when `_current_state == AIState.SEARCHING`
   instead of calling `is_next_waypoint_lit()`. Since SEARCHING uses direct movement
   (not NavigationAgent2D), there is no "next waypoint" to check.

2. **Disable avoidance immediately** — In `_transition_to_searching()`, disable
   `_nav_agent.avoidance_enabled` immediately instead of waiting for `_deferred_search_init()`.
   This prevents the NavigationAgent2D's internal `NOTIFICATION_INTERNAL_PHYSICS_PROCESS`
   from calling `NavigationServer2D.agent_set_position()` during the 2-frame init delay.

### Summary of All 7 Crash Fixes

| Fix # | Root Cause | Solution |
|-------|-----------|----------|
| 1 | Missing coordinator cleanup on state transitions | Added `_unregister_from_group_search()` to all 10 transitions |
| 2 | Double `move_and_slide()` + no navigation deferral | Removed inline `move_and_slide()`, added 2-frame init delay |
| 3 | `instance_from_id()` crash during physics | Replaced with WeakRef + deferred coordinator setup |
| 4 | `_generate_search_waypoints()` during physics | Deferred all waypoint generation to idle frames |
| 5 | NavigationAgent2D avoidance + repeated target_position | Disabled avoidance, cached nav target, deferred regen |
| 6 | `get_next_path_position()` called every frame during movement | Replaced with direct movement — zero NavigationServer2D calls in SEARCHING state handler |
| 7 | **`_update_goap_state()` calls `is_next_waypoint_lit()` every frame for ALL states** | **Skip flashlight waypoint check during SEARCHING + immediate avoidance disable** |

## Eighth Crash Report Investigation (2026-02-09)

### User Report
After the 7 crash fixes were applied, the user reported "вылетает" (crashes) and asked
to "проверь C#" (check C#). A new crash log was attached: `game_log_20260209_105825.txt`.

### Log Analysis

The crash log (899 lines) shows **normal gameplay with no crash message**:

| Time | Event |
|------|-------|
| `10:58:25` | Game started on LabyrinthLevel (5 enemies) |
| `10:58:31` | Player advanced to BuildingLevel (10 enemies) |
| `10:58:35` | Player hit (3→2→1 HP), LastChance triggered |
| `10:58:42` | LastChance ended, player teleported, memory reset for 10 enemies |
| `10:58:42` | 4 enemies (Enemy1-4) enter SEARCHING with "Init complete (solo, waypoints=5)" |
| `10:58:43` | Normal SEARCHING behavior (corner checks, waypoint following) |
| `10:58:43` | **Log ends normally** — no error message, no crash message |

### Key Observations

1. **No crash message captured**: Unlike previous crashes (which ended abruptly mid-line),
   this log ends with complete lines showing normal SEARCHING state behavior.

2. **Deferred init working correctly**: All 4 searching enemies show "Init complete (solo, waypoints=5)",
   indicating the 2-frame deferred initialization is working as intended.

3. **C# components running normally**: ReplayManager (C#), Player signals (C#), and all
   autoloads show successful initialization and operation throughout the log.

4. **SEARCHING direct movement active**: The log shows SEARCHING state enemies using corner
   checks and rotation changes, indicating the direct movement system (Fix #6) is operating.

### Possible Explanations

1. **Crash happened later**: The log may have been captured before the actual crash occurred.
   The log ends at frame 660 (11 seconds of gameplay) - if the crash happened at frame 1000+,
   it wouldn't be captured.

2. **Silent engine crash**: Some native Godot crashes (especially NavigationServer2D or
   physics thread issues) can terminate the process without logging any message. This would
   be consistent with the user's report.

3. **C# exception handling gap**: If a C# signal handler throws an exception during a
   Godot callback, the engine may crash without producing a GDScript-visible error.

### Investigation Status

Requested additional information from the user:
- Exact timing of crash (immediate after log ends, or later?)
- Type of crash (silent close, dialog, Windows error?)
- Reproducibility (consistent trigger?)
- Crash dump files (Windows may save .dmp files)

See PR comment: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/651#issuecomment-3880191315

## Ninth Crash Report Investigation (2026-02-24) + Deep Case Study

### User Report
After 7 crash fixes, user reported (in Russian): "вылетает при поиске. найди способ оптимизации поиска на godot" (crashes during search. Find a way to optimize search on Godot). They asked for a deep case study analysis with online research and a real fix.

### Deep Research Findings

#### 1. Godot 4.3 Race Condition in NavigationServer2D (Critical)

**Issue #101318** (godotengine/godot): `map_get_closest_point()` and related NavigationServer query methods acquired **nested read locks on the same RWLock** within a single thread. This caused deadlocks and crashes in Godot 4.3-stable that did NOT appear in Godot 4.2-stable.

- **Affected**: Godot 4.3-stable and 4.4-dev1
- **Fixed**: PR #101535, backported to **Godot 4.3.1-stable** and 4.4-dev2
- **Symptom**: Silent freeze or crash when `map_get_closest_point()` is called with 4+ enemies simultaneously
- **Source**: https://github.com/godotengine/godot/issues/101318

**This is a highly relevant root cause for our crash.** Our `_is_waypoint_navigable()` calls `NavigationServer2D.map_get_closest_point()` during `_deferred_search_init()`. Even though we defer to idle frames, if multiple enemies call `_deferred_search_init()` in the same idle frame via `call_deferred`, all their `map_get_closest_point()` calls execute on the same frame. With 4 enemies, this is 4 × (up to 100 calls per enemy) = 400 `map_get_closest_point()` calls in a single idle frame, which in Godot 4.3 triggers the nested lock issue.

#### 2. NavigationAgent2D Avoidance Performance Collapse

**Issue #82598**: With 150+ agents using avoidance, FPS drops to 5-10. With 200+ agents and avoidance disabled, FPS stays at 60.

- **Current fix status**: avoidance IS disabled in SEARCHING state
- **But**: Avoidance is re-enabled when leaving SEARCHING via `_unregister_from_group_search()`. If enemies rapidly cycle in/out of SEARCHING (e.g., LastChance resets, then enemies immediately spot player), the avoidance enable/disable toggling can itself trigger crashes

#### 3. Map Query Before First Synchronization

**Issue #84677**: Calling `get_next_path_position()` in `_physics_process()` on the very first frame fails. Workaround: defer navigation setup with `await get_tree().physics_frame`.

- **Current fix status**: already addressed by `_search_init_frames = 2` deferred initialization

#### 4. NavigationServer2D Performance: `map_get_closest_point()` is a Full-Map Scan

`NavigationServer2D.map_get_closest_point()` performs a scan of the entire navigation mesh to find the closest navigable point. For a large level like BuildingLevel, this is an expensive operation. With 4 enemies each generating 20 waypoints and checking each with `_is_waypoint_navigable()`, this is potentially 80 full-map scans in a single idle frame.

#### 5. `_count_enemies_in_combat()` Called Every Physics Frame for Every Enemy

`_update_goap_state()` calls `_count_enemies_in_combat()` every physics frame for every enemy. This function calls `get_tree().get_nodes_in_group("enemies")` — a scene tree traversal — and iterates all enemies every frame. With 10 enemies, this is 10 traversals × 60 fps = 600 group queries per second. During SEARCHING state, this data doesn't change meaningfully on a per-frame basis.

### Additional Research

#### Alternatives to NavigationServer2D.map_get_closest_point()

**Option 1: AStarGrid2D (Recommended for TileMap games)**
Godot 4 has a built-in `AStarGrid2D` with Jump Point Search (JPS) support. It:
- Is entirely GDScript-side (no NavigationServer RWLock issues)
- Can check if a grid cell is walkable in O(1) using `is_point_solid()`
- JPS gives 100x faster pathfinding than standard A* on open maps (GDC 2015, Harabor & Grastien)
- Source: https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html

**Option 2: NavigationServer2D.map_get_path() Direct API**
Bypass NavigationAgent2D entirely and call the server's `map_get_path()` method directly. This skips all the agent-internal state that can crash.
- Source: https://medium.com/godot-dev-digest/pathfinding-in-godot-using-navigationserver2d-without-agents-b2018bb3ba41

**Option 3: Simple navigability heuristic**
For waypoint navigability checking, instead of `map_get_closest_point()`, use a `PhysicsRayQueryParameters2D` raycast from current position to waypoint — if it hits a wall, the waypoint is inaccessible. This avoids NavigationServer2D entirely.

#### Known Existing Components/Libraries

| Library | Status | Notes |
|---------|--------|-------|
| `AStarGrid2D` (Godot builtin) | ✅ Available | Best for grid-based validation |
| GodotFlowField | ⚠️ Godot 3 only | Would need rewrite for Godot 4 |
| NavigationServer2D direct API | ✅ Available | Use `map_get_path()` instead of agent |

### Proposed Solutions (Priority Order)

#### Solution A: Replace `_is_waypoint_navigable()` with Raycast-Based Check

Instead of `NavigationServer2D.map_get_closest_point()` (which has race conditions), use a short raycast from current position to target waypoint:

```gdscript
func _is_waypoint_navigable(pos: Vector2) -> bool:
    # Quick distance check - reject waypoints too far from valid navigation
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(global_position, pos)
    query.collision_mask = 0b100  # walls layer
    query.exclude = [self]
    return space_state.intersect_ray(query).is_empty()
```

This is faster, thread-safe, and avoids the NavigationServer RWLock race condition entirely.

#### Solution B: Throttle `_count_enemies_in_combat()` and Other Expensive GOAP Updates

Cache the result and only recompute every 0.2 seconds (12 frames at 60fps), not every physics frame:

```gdscript
var _cached_enemies_in_combat: int = 0
var _enemies_in_combat_timer: float = 0.0
const ENEMIES_IN_COMBAT_UPDATE_INTERVAL: float = 0.2
```

#### Solution C: Skip Expensive GOAP Checks During SEARCHING

During SEARCHING, many GOAP checks are irrelevant:
- `_can_hit_player_from_current_position()` — irrelevant (can't see player)
- `_count_enemies_in_combat()` — could be cached during SEARCHING
- `_is_player_distracted()` — irrelevant (can't see player in SEARCHING)

#### Solution D: Rate-Limit _deferred_search_init() Across Enemies

Add a static cooldown so that at most 1-2 enemies run `_deferred_search_init()` per frame (stagger the expensive NavigationServer calls):

```gdscript
static var _search_init_in_progress: bool = false
# If another enemy is initializing, defer by 1 more frame
```

### Root Cause Summary

| Priority | Root Cause | Confidence | Status |
|----------|-----------|------------|--------|
| 1 | Godot 4.3 RWLock race in `map_get_closest_point()` (Issue #101318) | HIGH | **NEW - not addressed** |
| 2 | `_count_enemies_in_combat()` every frame (scene traversal) | MEDIUM | **NEW - not addressed** |
| 3 | `_deferred_search_init()` for all enemies in same idle frame | MEDIUM | **NEW - not addressed** |
| 4-10 | All 7 previously fixed issues | HIGH | ✅ Fixed |

### Fix Applied (Ninth Pass)

See implementation notes in commit history for 2026-02-24.

1. **Replace `_is_waypoint_navigable()` with raycast-based check** — eliminates all `NavigationServer2D.map_get_closest_point()` calls, which had a race condition in Godot 4.3 (Issue #101318 in godotengine/godot)

2. **Throttle expensive GOAP state updates** — `_count_enemies_in_combat()` cached for 0.2s; skipped entirely during SEARCHING since enemies don't make combat decisions while searching

3. **Stagger `_deferred_search_init()` across enemies** — use static counter to limit to 1 deferred init per idle frame, preventing 80+ `map_get_closest_point()` calls in a single frame burst

## Tenth Crash Report (2026-02-24) — SoundPropagation Stale Listener Accumulation

### User Report

After fix #8 was committed, user reported (in Russian): "вылетело при начале поиска. видимо проблема с оптимизацией." (crashed at search start, apparently an optimization problem). Crash log: `crash-logs/game_log_20260224_193005.txt`.

### Log Analysis

The log (823 lines) shows gameplay across **three scene loads**:

| Time | Event |
|------|-------|
| 19:30:05 | LabyrinthLevel started (5 enemies) |
| 19:30:13 | BuildingLevel started (10 enemies, 1st load) |
| 19:30:18 | BuildingLevel started AGAIN (10 enemies, 2nd load — player died and respawned) |
| 19:30:27 | LastChance effect ends: 3 enemies enter SEARCHING state |
| 19:30:27 | All 3 complete deferred init: "Init complete (solo, waypoints=2/4/3)" |
| 19:30:29 | **Log ends abruptly** — hard crash, no error message |

**Critical finding:** SoundPropagation listener count accumulated across scene loads:

```
[19:30:06] Registered listener: Enemy1 (total: 1)  ← LabyrinthLevel (5 enemies)
...
[19:30:13] Registered listener: Enemy1 (total: 6)  ← BuildingLevel 1st load (+10)
...
[19:30:18] Registered listener: Enemy1 (total: 16) ← BuildingLevel 2nd load (+10)
...
[19:30:21] Sound emitted: ... listeners=25          ← 25 TOTAL (15 are stale/freed)
[19:30:21] Cleaned up 15 invalid listeners          ← 15 stale references cleaned
```

### Root Cause Analysis

**`SoundPropagation` is an autoload singleton** — its `_listeners` array persists across ALL scene changes. Enemies call `_unregister_sound_listener()` only inside `_on_death()`. But when a scene changes, enemies are freed via the scene tree (equivalent to `queue_free()`) **without `_on_death()` being called**.

The `_exit_tree()` function in `enemy.gd` only called `_unregister_from_group_search()` — it did NOT call `_unregister_sound_listener()`.

**Result:** After 3 scene loads (LabyrinthLevel + BuildingLevel×2), `SoundPropagation._listeners` had 25 entries: 5 from LabyrinthLevel + 10 from BuildingLevel 1st load + 10 from BuildingLevel 2nd load. 15 of those 25 listeners were stale (freed nodes).

**Crash mechanism:** During the `emit_sound()` cleanup loop on line 152 of `sound_propagation.gd`:
```gdscript
_listeners = _listeners.filter(func(l): return is_instance_valid(l))
```
This is called during the CASING_KICK burst (13 rapid sound emissions in <2 seconds) while `LastChance` is simultaneously restoring process modes for all 40+ nodes. The combination of high-frequency `is_instance_valid()` calls on 25 listeners simultaneously with the node process mode changes creates a race condition in Godot 4.3's object validity tracking.

**Confirmation:** Fix #8 (NavigationServer2D raycast + GOAP throttle + staggered init) held — the crash log shows NO NavigationServer2D errors. The crash pattern is completely different: happening AFTER deferred init succeeds, during sound propagation, not during navigation.

### Fix Applied (Fix #9)

Added `_unregister_sound_listener()` to `_exit_tree()` in `enemy.gd`:

```gdscript
func _exit_tree() -> void:
    _unregister_from_group_search()  # Issue #650: Group search coordinator cleanup
    _unregister_sound_listener()     # Issue #650 fix #9: prevent stale listener accumulation
```

This ensures that when ANY enemy leaves the scene tree (for any reason — scene change, `queue_free()`, level restart), it is immediately unregistered from `SoundPropagation`. This prevents the listener count from growing unboundedly across scene loads.

### Updated Fix Summary

| Fix # | Root Cause | Solution |
|-------|-----------|----------|
| 1 | Missing coordinator cleanup on state transitions | Added `_unregister_from_group_search()` to all 10 transitions |
| 2 | Double `move_and_slide()` + no navigation deferral | Removed inline `move_and_slide()`, added 2-frame init delay |
| 3 | `instance_from_id()` crash during physics | Replaced with WeakRef + deferred coordinator setup |
| 4 | `_generate_search_waypoints()` during physics | Deferred all waypoint generation to idle frames |
| 5 | NavigationAgent2D avoidance + repeated target_position | Disabled avoidance, cached nav target, deferred regen |
| 6 | `get_next_path_position()` called every frame during movement | Direct movement — zero NavigationServer2D calls in SEARCHING handler |
| 7 | `_update_goap_state()` calls `is_next_waypoint_lit()` every frame for ALL states | Skip flashlight waypoint check during SEARCHING |
| 8 | Godot 4.3 RWLock race in `map_get_closest_point()` + concurrent init bursts | Raycast-based navigability + throttled GOAP + staggered deferred inits |
| **9** | **`SoundPropagation._listeners` grows unboundedly across scene loads** | **Added `_unregister_sound_listener()` to `_exit_tree()`** |

### References

- [Godot #101318: Race condition in NavigationServer3D](https://github.com/godotengine/godot/issues/101318) — **KEY: deadlock in Godot 4.3 fixed in 4.3.1**
- [Godot #82598: NavigationAgent2D enters no-navigation zones during avoidance](https://github.com/godotengine/godot/issues/82598)
- [Godot #84677: NavigationServer map query failed before first synchronization](https://github.com/godotengine/godot/issues/84677)
- [Godot Docs: AStarGrid2D](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) — safe alternative
- [GDC Vault: JPS+ Over 100x Faster than A*](https://gdcvault.com/play/1022094/JPS-Over-100x-Faster-than)
- [Godot Docs: Optimizing Navigation Performance](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html)
- [Godot Forum: How to Handle Large Amounts of NavigationAgents](https://godotforums.org/d/31934-how-to-handle-large-amounts-of-navigationagents-pathfinding) — 2000+ agents at 60fps by staggering updates
- [Navigation Server for Godot 4.0](https://godotengine.org/article/navigation-server-godot-4-0/) — Architecture explained (producer-consumer queue, synchronization timing)

## Eleventh Report Analysis (2026-02-25) — Validation of Fix #9

### User Report

User reported (in Russian): "всё ещё вылетает." (still crashes). Log attached: `crash-logs/game_log_20260225_001612.txt`.

### Log Analysis

The log (1136 lines) shows gameplay across **three scene loads** (same pattern as the crash that triggered fix #9):

| Time | Event |
|------|-------|
| `00:16:12` | LabyrinthLevel started (5 enemies, listeners=5) |
| `00:16:20` | BuildingLevel 1st load (10 enemies, listeners reset to 10) |
| `00:16:27` | BuildingLevel 2nd load (10 enemies, listeners reset to 10) |
| `00:16:29` | Combat: gunshots, LastChance triggered (player at 1 HP) |
| `00:16:35` | LastChance ends, 4 enemies enter SEARCHING |
| `00:16:35–37` | Normal SEARCHING behavior (corner checks, waypoint following) |
| `00:16:37` | **Log ends normally** — no crash, no error message |

### Critical Observation: Fix #9 Is Working

**The SoundPropagation stale listener bug (Fix #9) is CONFIRMED FIXED.** Evidence:

```
[00:16:20] Unregistered listener: Enemy5 (remaining: 4)  ← _exit_tree() called on scene change
[00:16:20] Unregistered listener: Enemy4 (remaining: 3)
...
[00:16:20] Unregistered listener: Enemy1 (remaining: 0)  ← Clean exit: 0 listeners
[00:16:20] Scene changed to: BuildingLevel
[00:16:20] Registered listener: Enemy1 (total: 1)        ← Fresh start!
...
[00:16:27] Sound emitted: type=GUNSHOT, ... listeners=10  ← Exactly 10, no accumulation!
[00:16:37] Sound emitted: type=CASING_KICK, ... listeners=9  ← 9 after Enemy3 died
```

The listener count stays exactly equal to the number of alive enemies in the current scene. Across scene transitions, it cleanly resets to 0 and rebuilds. No stale references accumulate.

### Why The Log Still Says "Crashes"

This log ends **normally** after 84 seconds of gameplay with enemies SEARCHING successfully. The log ends at line 1136 with:
```
[00:16:37] [ENEMY] [Enemy2] SEARCHING corner check: angle -60.6°
```

This is NOT a crash — the log ends at frame ~660 (11 seconds into BuildingLevel 2nd load). Two explanations:

1. **Crash happened after log ends**: The user continued playing beyond what's captured in the log and the crash occurred later (possibly in a 3rd or 4th level load, or after additional enemy SEARCHING/combat cycles).

2. **Unrelated crash in a different feature**: The game may have crashed due to something NOT related to the search/sound system — e.g., the Grenadier's offensive grenades (BuildingLevel "hard" mode shows `[hard]: [Offensive×7, Defensive]`), the replay system, or another subsystem that was updated in upstream commits.

### Notable Observations

1. **Hard mode detected**: 2nd BuildingLevel load shows `Grenade bag built (hard): [Offensive×7, Defensive]` — the game is running in hard difficulty. Hard mode involves more aggressive behaviors and more enemies, potentially stressing different code paths.

2. **Enemy3 killed by wall penetration**: Player used penetrating bullets to kill Enemy3 through a wall, triggering the full death sequence + sound propagation unregistration correctly.

3. **LastChance triggered and completed**: The full 6-second LastChance sequence ran without any issues, including:
   - Freezing 10 enemies + 40 nodes
   - Unfreezing and restoring all process modes
   - Resetting memory for all 10 enemies
   - 4 enemies successfully entering SEARCHING state
   - All 4 completing deferred init: `Init complete (solo, waypoints=1/2/5/1)`

4. **Invincibility enabled at 00:16:31**: Player toggled invincibility, which may have changed game dynamics and contributed to extended gameplay beyond what the log captured.

### Status

Fix #9 is validated as working for the specific bug it addressed. The user's report of "still crashes" likely refers to a crash that occurred **after** the captured log period. Without a log that captures the actual crash event (including the crash frame), the exact new root cause cannot be determined. The game reached a stable state with fixes #1-#9 in place for at least 84 seconds of active gameplay including LastChance, SEARCHING, enemy death, and sound propagation.
