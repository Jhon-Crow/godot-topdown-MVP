# Case Study: Issue #103 - Improve Enemy Movement System

## Executive Summary

This case study analyzes the failed attempt (PR #104) to implement an improved enemy AI search behavior in a Godot 4.3 top-down game. The implementation added a SEARCHING state to allow enemies to search for players at their last-known position after losing line of sight. However, the changes caused a critical regression where enemies stopped functioning entirely in exported builds, despite passing CI tests and working in the editor.

## Issue Overview

### Original Request

**Issue #103** (Created: 2026-01-18)
- **Title**: улучшить систему перемещения (Improve movement system)
- **Author**: Jhon-Crow (Repository Owner)

**Translated Requirements**:
1. When player disappears from enemy's field of view, enemy should mark a small invisible zone where the player was last seen as a "potential player zone"
2. Enemy should build a full route to this zone and then search it
3. Behind all covers and in room corners there should be invisible inspection points that the enemy must check if they are in the "potential player zone"
4. When all points in the potential player zone are checked, it's considered a "no player zone"
5. Upon encountering the player, zones should reset
6. Expand existing AI behavior and GOAP system
7. **Preserve all existing functionality**

**Warning from User**:
> "не делай как в https://github.com/Jhon-Crow/godot-topdown-MVP/pull/104 он сломал врагов полностью и не смог починить."
> ("Don't do like in PR #104 - it completely broke enemies and couldn't be fixed.")

---

## Timeline of Events

### Phase 1: Initial Implementation (2026-01-18 02:48-02:57 UTC)

1. **02:48** - PR #104 created with initial task details commit
2. **02:55** - AI solver implemented SEARCHING state with 280 new lines in `enemy.gd`:
   - Added `SEARCHING` state to `AIState` enum
   - Added last-known-position tracking variables
   - Added inspection point generation using raycasts
   - Added search zone visualization for debugging
   - Added new GOAP actions: `SearchAreaAction`, `InspectHidingSpotAction`
3. **02:57** - Solution draft log posted, PR marked ready for review

### Phase 2: First Regression Report (2026-01-18 03:03-03:04 UTC)

4. **03:03** - User tested exported build and reported:
   > "всё поведение сломалось. враги не получают урон и не действуют."
   > ("All behavior is broken. Enemies don't take damage and don't act.")

   User attached log files:
   - `game_log_20260118_060214.txt`
   - `game_log_20260118_060254.txt`

5. **03:04** - AI work session started to investigate

### Phase 3: Fix Attempt (2026-01-18 03:04-03:14 UTC)

6. **03:11** - AI applied "fix" by reverting transition from SEARCHING back to PURSUING
7. **03:13** - Posted analysis claiming:
   - The log files showed no enemy spawn logs
   - Reverted combat state transition back to PURSUING
   - SEARCHING state code preserved but disabled

### Phase 4: Continued Failure (2026-01-18 03:18-03:19 UTC)

8. **03:18** - User reported fix didn't work:
   > "нет, всё ещё враги просто стоят на месте и никакой интерактивности."
   > ("No, enemies still just stand in place and no interactivity.")
   > "дебаг так же не работает" ("Debug also doesn't work.")

   User attached: `game_log_20260118_061726.txt`

9. **03:19** - PR #104 closed (failure acknowledged)

---

## Root Cause Analysis

### Critical Evidence: The Log Files

All three user-provided log files show the same pattern:

```
[06:02:14] [INFO] GAME LOG STARTED
[06:02:14] [INFO] [GameManager] GameManager ready
[06:02:19] [INFO] [GameManager] Debug mode toggled: ON
[06:02:26] [INFO] GAME LOG ENDED
```

**What's Missing**:
- No enemy spawn logs (`_log_spawn_info()` in `enemy.gd:_ready()`)
- No enemy state transitions
- No combat or AI behavior logs
- No error messages

This indicates that **enemies were not spawning at all** or their `_ready()` function was failing silently.

### Identified Root Causes

#### Primary Cause: Physics Raycast Timing Issue

The `_generate_inspection_points()` function (added in PR #104) uses:

```gdscript
var space_state := get_world_2d().direct_space_state
var query := PhysicsRayQueryParameters2D.new()
query.from = search_center
query.to = search_center + direction * INSPECTION_CHECK_DISTANCE
query.collision_mask = 4  # Only check obstacles (layer 3)
var result := space_state.intersect_ray(query)
```

**Known Godot 4.x Issue**: According to [GitHub Issue #94614](https://github.com/godotengine/godot/issues/94614), collision detection doesn't work on the first physics frame. This behavior differs between:
- Editor/Debug builds: Physics may be pre-initialized
- Exported/Release builds: First-frame physics queries can fail

If `_transition_to_searching()` is called during `_ready()` or early initialization, the raycast could cause undefined behavior in export builds.

#### Secondary Cause: State Machine Race Condition

The change from:
```gdscript
if not _can_see_player:
    _transition_to_pursuing()
```

To:
```gdscript
if not _can_see_player:
    _transition_to_searching()
```

This potentially triggered during enemy spawn when `_can_see_player` is false, calling `_generate_inspection_points()` before the physics world was ready.

#### Tertiary Cause: Silent Failure Pattern

The code lacks defensive checks:
```gdscript
func _transition_to_searching() -> void:
    # ...
    if _last_known_player_position != Vector2.ZERO:
        _search_zone_active = true
        _generate_inspection_points()  # Can fail silently on export
    else:
        _transition_to_pursuing()  # Fallback, but still in SEARCHING state
```

The function sets `_current_state = AIState.SEARCHING` **before** the conditional check, meaning if the condition fails, the enemy is in SEARCHING state but falls through to PURSUING - a state inconsistency.

### Why the "Fix" Didn't Work

The attempted fix only reverted one transition but left other SEARCHING-related code that could still be triggered:

1. `_check_player_visibility()` was modified to track `_last_known_player_position`
2. Search zone clearing logic was added
3. Debug visualization code for SEARCHING state remained active
4. GOAP world state updates for search-related variables were still computed

Any of these could have caused issues in the already-damaged codebase.

---

## Technical Analysis: GOAP Implementation

### Current GOAP Architecture

The codebase uses a simplified GOAP system with:
- `goap_planner.gd`: A* search planner for action sequences
- `goap_action.gd`: Base class for actions with preconditions/effects
- `enemy_actions.gd`: Concrete action implementations

**Existing Actions** (pre-issue):
1. SeekCoverAction
2. EngagePlayerAction
3. FlankPlayerAction
4. PatrolAction
5. StaySuppressedAction
6. ReturnFireAction
7. FindCoverAction
8. RetreatAction
9. RetreatWithFireAction
10. PursuePlayerAction
11. AssaultPlayerAction

### PR #104 Added Actions

```gdscript
class SearchAreaAction extends GOAPAction:
    preconditions = {
        "player_visible": false,
        "has_search_zone": true,
        "search_zone_cleared": false
    }
    effects = {
        "is_searching": true,
        "search_zone_cleared": true
    }

class InspectHidingSpotAction extends GOAPAction:
    preconditions = {
        "is_searching": true,
        "inspection_points_remaining": true
    }
    effects = {
        "hiding_spot_checked": true
    }
```

**Problem**: The GOAP system wasn't actually used for the state transitions - the code relied on direct state machine transitions instead.

---

## Industry Best Practices Research

### F.E.A.R. GOAP Implementation

According to [Jeff Orkin's GDC 2006 presentation](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf):

1. **Three-State FSM**: F.E.A.R. uses only three states: moving, playing animation, interacting with smart objects
2. **A* for Action Planning**: The GOAP planner constructs action sequences using A*
3. **Last Known Position**: Maintained as part of the world state for search behaviors

### Recommended Patterns

Based on industry research:

1. **Last Known Position (LKP) Pattern**:
   - Store position where player was last seen as world state variable
   - LKP updates only while player is visible
   - Search goal activates when LKP exists and player not visible

2. **Occupancy Maps** (from Third Eye Crime):
   - Use probability-based knowledge representation
   - More realistic pursuit and search behavior
   - Source: [Dynamic Guard Patrol in Stealth Games](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903)

3. **Investigation Points**:
   - Pre-define inspection points in level design
   - Or generate dynamically with **deferred raycast calls** to avoid timing issues
   - Priority-order by proximity to LKP

---

## Proposed Solutions

### Solution 1: Deferred Physics Initialization (Recommended)

```gdscript
func _transition_to_searching() -> void:
    if _last_known_player_position == Vector2.ZERO:
        _log_debug("No last known position, falling back to PURSUING")
        _transition_to_pursuing()
        return

    _current_state = AIState.SEARCHING
    _search_timer = 0.0
    # ... other initializations ...

    # CRITICAL: Defer raycast-based operations to next physics frame
    call_deferred("_deferred_generate_inspection_points")

func _deferred_generate_inspection_points() -> void:
    # Only proceed if still in SEARCHING state
    if _current_state != AIState.SEARCHING:
        return

    # Wait for physics to be ready
    if not is_inside_tree():
        return

    await get_tree().physics_frame
    _generate_inspection_points()
```

### Solution 2: Pre-Placed Inspection Points

Instead of generating inspection points dynamically with raycasts, use pre-placed nodes in the level:

```gdscript
# In level scene
@export var inspection_points: Array[Marker2D] = []

# Enemy finds nearby points
func _find_inspection_points_near(position: Vector2, radius: float) -> Array[Vector2]:
    var level = get_parent()
    if level.has_method("get_inspection_points"):
        return level.get_inspection_points(position, radius)
    return []
```

### Solution 3: Incremental Feature Activation

Add a feature flag to enable SEARCHING behavior only after testing:

```gdscript
@export var enable_searching_behavior: bool = false

func _process_combat_state(delta: float) -> void:
    # ...
    if not _can_see_player:
        if enable_searching_behavior and _last_known_player_position != Vector2.ZERO:
            _transition_to_searching()
        else:
            _transition_to_pursuing()
```

---

## Lessons Learned

### 1. Editor vs Export Behavior Differences

Godot 4.x has documented differences between editor and export builds regarding:
- Physics initialization timing
- First-frame collision detection
- Raycast availability

**Mitigation**: Always test exported builds before marking implementation complete.

### 2. Silent Failure in Game Engines

GDScript doesn't crash on many runtime errors - it just silently fails. This makes debugging difficult.

**Mitigation**:
- Add extensive logging with debug flags
- Use `assert()` for development builds
- Check return values from physics queries

### 3. Atomic Changes

The PR made multiple changes simultaneously:
- Added new state
- Modified existing state transitions
- Added GOAP actions
- Added debug visualization
- Modified player visibility tracking

**Mitigation**: Make smaller, testable changes that can be bisected if issues arise.

### 4. Testing Requirements

CI tests passed but the game was broken in export builds.

**Mitigation**:
- Add integration tests that run the exported game
- Test state machine transitions explicitly
- Add tests for physics-dependent code

---

## Data Files

This case study includes the following data files:

| File | Description |
|------|-------------|
| `issue-103-details.json` | Full issue data from GitHub API |
| `issue-103-comments.json` | Issue comments |
| `pr-104-details.json` | Full PR #104 data |
| `pr-104-diff.txt` | Code changes in PR #104 |
| `pr-104-conversation-comments.json` | PR discussion comments |
| `pr-104-review-comments.json` | PR review comments |
| `pr-106-details.json` | Current PR #106 data |
| `all-prs.json` | All repository PRs for context |
| `all-issues.json` | All repository issues for context |
| `logs/game_log_20260118_060214.txt` | First user log (broken build) |
| `logs/game_log_20260118_060254.txt` | Second user log (broken build) |
| `logs/game_log_20260118_061726.txt` | Third user log (still broken after fix) |
| `logs/solution-draft-log-1.txt` | AI solver log (initial implementation) |
| `logs/solution-draft-log-2.txt` | AI solver log (fix attempt) |

---

## References

### Primary Sources
- [Issue #103](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/103)
- [PR #104 (Failed)](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/104)
- [Godot Issue #94614 - First-frame collision detection](https://github.com/godotengine/godot/issues/94614)

### Research Sources
- [Building the AI of F.E.A.R. with Goal Oriented Action Planning](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning)
- [Three States and a Plan: The A.I. of F.E.A.R. (GDC 2006)](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf)
- [Dynamic Guard Patrol in Stealth Games (AIIDE Paper)](https://ojs.aaai.org/index.php/AIIDE/article/download/7425/7308/10903)
- [Godot Ray-casting Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [Godot Physics Troubleshooting](https://docs.godotengine.org/en/stable/tutorials/physics/troubleshooting_physics_issues.html)
- [godot-goap - GOAP Example for Godot](https://github.com/viniciusgerevini/godot-goap)

### Forum Discussions
- [Godot Forum - Raycast collision being inconsistent](https://forum.godotengine.org/t/raycast-collision-being-inconsistent/130817)
- [Godot Forum - Enemy AI Not Working As Intended](https://forum.godotengine.org/t/enemy-ai-not-working-as-intended/55725)
- [Toxigon - Making enemies that don't feel stupid in Godot](https://toxigon.com/godot-enemy-ai)

---

## Conclusion

The failure of PR #104 was caused by a combination of:
1. **Physics timing issues** in exported Godot builds
2. **Insufficient state machine validation** before state changes
3. **Lack of export-specific testing**
4. **Attempted fix that didn't address root cause** (only partial revert)

The recommended approach for implementing this feature is to:
1. Use deferred physics operations
2. Add feature flags for incremental activation
3. Test extensively in exported builds
4. Use pre-placed inspection points where possible
5. Add comprehensive logging for debugging

---

*Case Study Compiled: 2026-01-18*
*Author: AI Issue Solver (Claude)*
