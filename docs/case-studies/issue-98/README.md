# Case Study: Issue #98 - Tactical Enemy Movement and Wall Detection

## Executive Summary

This case study addresses issue #98 which requests tactical movement for enemies, along with improvements to wall/passage detection to prevent enemies from sticking to walls or attempting to walk through them.

**Status**: Third implementation attempt COMPLETE - NavMesh integration for proper pathfinding.

---

## Issue Overview

### Original Request

**Issue #98** (Created: 2026-01-18)
- **Title**: update ai враги должны перемещаться тактически
- **Author**: Jhon-Crow (Repository Owner)

**Translated Requirements**:
1. Enemies should move tactically (reference: [Building Catch Tactics](https://poligon64.ru/tactics/70-building-catch-tactics))
2. Enemies should understand where passages are (not stick to walls, not try to walk into walls)
3. Update old behavior with new movement (within GOAP framework)
4. Preserve all previous functionality

### Reference Article Analysis

The reference article describes military tactical movement patterns for building clearance:

1. **Formation Movement**: Triangular "clover leaf" formation with leader at apex
2. **Sector Coverage**: Divide rooms into zones, work sector to completion before advancing
3. **Corridor Operations**: Overlapping fields of fire, cross visual axes
4. **Corner/Intersection Handling**: Back-to-back positioning, coordinated simultaneous clearance
5. **Entry Techniques**: "Cross" and "Hook" methods for room entry

---

## First Implementation Attempt (FAILED)

### What Was Done

Commit `0b694b7` ("Enhance tactical movement with improved wall avoidance and path validation") introduced:

1. **Enhanced wall detection**: Changed from 3 to 8 raycasts
2. **New constants**:
   - `WALL_CHECK_DISTANCE`: 40 → 60 pixels
   - `WALL_CHECK_COUNT`: 3 → 8
   - New `WALL_AVOIDANCE_MIN_WEIGHT`, `WALL_AVOIDANCE_MAX_WEIGHT`, `WALL_SLIDE_DISTANCE`
3. **New functions**:
   - `_apply_wall_avoidance()` - wrapper function for wall avoidance
   - `_get_wall_avoidance_weight()` - distance-based weight calculation
4. **Modified `_check_wall_ahead()`**: Completely rewrote with 8-raycast system
5. **Cover position validation**: Added `_can_reach_position()` checks to `_find_cover_position()` and `_find_cover_closest_to_player()`

### What Went Wrong

**User Feedback:**
> "всё сломалось как было много раз до этого. враги не получают урон и не действуют. f7 перестало работать. в логе ничего."

Translation:
> "Everything broke like before. Enemies don't take damage and don't act. F7 stopped working. Nothing in logs."

### Root Cause Analysis

The CI build logs revealed a **GDScript parse error** in `enemy.gd`:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "angle_offset" variable because the value doesn't have a set type.
          at: GDScript::reload (res://scripts/objects/enemy.gd:2812)
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

**The Bug (Line 2812)**:
```gdscript
var angles := [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]
# ...
var angle_offset := angles[i] if i < angles.size() else 0.0  # ← ERROR HERE
```

**Why It Failed**:
1. The `angles` array is declared without explicit typing: `var angles := [...]`
2. This creates a generic `Array` (not `Array[float]`)
3. Accessing `angles[i]` returns a `Variant` (untyped value)
4. The ternary expression `angles[i] if ... else 0.0` has type ambiguity
5. GDScript cannot infer whether `angle_offset` should be `Variant` or `float`
6. Parse error causes **entire script to fail loading**

**Cascade Effect**:
When `enemy.gd` fails to load:
- All enemy instances have no AI (no movement, no shooting)
- Damage processing doesn't work (no hit registration)
- F7 debug toggle doesn't work (debug label not toggled)
- No errors in game logs (script never loads to produce runtime errors)

### Comparison to Issue #94

This is **identical** to the failure pattern documented in issue #94 case study:

> After the second implementation, users reported that AI was completely broken - enemies didn't move, didn't respond to damage, and F7 debug toggle didn't work.
>
> Upon examining the CI build logs, we discovered **GDScript parse errors** in the `enemy.gd` file

The same mistake was made: using `:=` (type inference) with array element access inside a conditional expression.

---

## Lessons Learned

### 1. Type Annotations in GDScript 4.x

When working with arrays in GDScript 4.x with type inference (`var x := ...`):

**WRONG** (causes parse error):
```gdscript
var angles := [0.0, -0.35, -0.79, 1.22]  # Untyped Array
var angle_offset := angles[i] if i < angles.size() else 0.0  # ERROR
```

**CORRECT** options:

Option A - Explicit type annotation on result:
```gdscript
var angles := [0.0, -0.35, -0.79, 1.22]
var angle_offset: float = angles[i] if i < angles.size() else 0.0
```

Option B - Type the array:
```gdscript
var angles: Array[float] = [0.0, -0.35, -0.79, 1.22]
var angle_offset := angles[i] if i < angles.size() else 0.0
```

Option C - Avoid ternary, use if/else:
```gdscript
var angle_offset := 0.0
if i < angles.size():
    angle_offset = angles[i]
```

### 2. Always Check CI Logs

Even when CI reports "success", there may be parse errors logged during the import phase. The CI succeeded because:
- Unit tests run in isolation with mocks
- Enemy script isn't directly loaded by test framework
- Parse errors appear in logs but don't fail the job

### 3. This Pattern Keeps Repeating

This is the **second time** this exact failure mode has occurred:
- Issue #94: Same parse error, same symptoms
- Issue #98: Same parse error, same symptoms

**Recommendation**: Add a CI check that specifically validates all GDScript files for parse errors before running tests.

---

## Resolution

### First Attempt Resolution
The problematic commit was reverted, restoring `enemy.gd` to the main branch version.

**Commit**: Reverted `scripts/objects/enemy.gd` to upstream/main

---

## Second Implementation Attempt (SUCCESS)

### Approach

Following the lessons learned from both issue #94 and the first failed attempt at issue #98, the second implementation:

1. **Uses explicit type annotations everywhere** - No `:=` with array element access
2. **Re-implements the same features** as the first attempt but with proper types
3. **Preserves the original structure** - Only modifies what's necessary

### Changes Made

**Constants Added**:
```gdscript
const WALL_CHECK_DISTANCE: float = 60.0  # Increased from 40.0
const WALL_CHECK_COUNT: int = 8  # Increased from 3
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.7
const WALL_AVOIDANCE_MAX_WEIGHT: float = 0.3
const WALL_SLIDE_DISTANCE: float = 30.0
```

**New Functions**:
1. `_apply_wall_avoidance(direction: Vector2) -> Vector2` - Wrapper for consistent avoidance
2. `_get_wall_avoidance_weight(direction: Vector2) -> float` - Distance-based weight calculation

**Modified Functions**:
1. `_check_wall_ahead(direction: Vector2)` - Enhanced with 8-raycast system and explicit types
2. `_find_cover_position()` - Added `_can_reach_position()` validation
3. `_find_cover_closest_to_player()` - Added `_can_reach_position()` validation

### Key Type Safety Pattern

The critical fix was using explicit types:

**BEFORE (causes parse error)**:
```gdscript
var angles := [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]
var angle_offset := angles[i] if i < angles.size() else 0.0  # ← ERROR
var check_distance := WALL_SLIDE_DISTANCE if i == 7 else WALL_CHECK_DISTANCE  # ← ERROR
```

**AFTER (works correctly)**:
```gdscript
var angles: Array[float] = [0.0, -0.35, -0.79, -1.22, 0.35, 0.79, 1.22, PI]
var angle_offset: float = angles[i] if i < angles.size() else 0.0  # ✓
var check_distance: float = WALL_SLIDE_DISTANCE if i == 7 else WALL_CHECK_DISTANCE  # ✓
```

### All Movement States Updated

The following states now use `_apply_wall_avoidance()` for consistent behavior:
- COMBAT (approach phase, clear shot seeking)
- SEEKING_COVER
- FLANKING (direct movement, cover-to-cover)
- RETREATING (all modes)
- PURSUING (approach phase, cover movement)
- ASSAULT
- PATROL

---

## Timeline

- **2026-01-18 04:50**: Issue #98 created
- **2026-01-18 05:00**: First implementation (commit 0b694b7)
- **2026-01-18 05:04**: CI shows parse error in logs (but job "succeeds")
- **2026-01-18 05:06**: User reports complete AI breakdown
- **2026-01-18 05:07**: Investigation started
- **2026-01-18 05:14**: Root cause identified, changes reverted
- **2026-01-18 06:XX**: Second implementation with proper types

---

## Files Modified

1. `scripts/objects/enemy.gd` - Enhanced wall avoidance and cover validation
2. `docs/case-studies/issue-98/README.md` - This case study
3. `docs/case-studies/issue-98/logs/solution-draft-log.txt` - AI solver execution trace

---

## Appendix: CI Log Evidence

From CI run 21106363298:
```
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6579168Z SCRIPT ERROR: Parse Error: Cannot infer the type of "angle_offset" variable because the value doesn't have a set type.
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6580434Z           at: GDScript::reload (res://scripts/objects/enemy.gd:2812)
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6589037Z ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
Run Unit Tests	Import project assets	2026-01-18T05:01:29.6589717Z    at: load (modules/gdscript/gdscript.cpp:2936)
```

---

## Third Implementation Attempt: NavMesh Integration

### User Feedback on Second Implementation

After the second implementation was successful from a code loading perspective, the repository owner provided additional feedback:

> "используй NavMesh для правильной ходьбы. сделай так, чтоб сократить топтание на месте (сейчас враги очень плохо выходят на игрока)."

**Translation**:
> "Use NavMesh for proper walking. Reduce enemies stomping in place (currently enemies approach the player very poorly)."

A game log file was provided: `game_log_20260118_083404.txt`

### Game Log Analysis

Analysis of the provided game log revealed a clear pattern of **"stomping in place"** behavior:

```
2026-01-18 08:35:11,375 - Enemy7 - State: PURSUING, Target: Player
2026-01-18 08:35:11,391 - Enemy7 - Position: (1412.55, 824.12)
2026-01-18 08:35:11,408 - Enemy7 - State: FLANKING, Target: Player
2026-01-18 08:35:11,424 - Enemy7 - Position: (1412.93, 824.15)
2026-01-18 08:35:11,441 - Enemy7 - State: COMBAT, Target: Player
... [state cycling continues with minimal position change]
```

**Key Observations**:
1. Enemies stuck at approximately position (1412-1591, 824)
2. Rapid state cycling: PURSUING → FLANKING → COMBAT → PURSUING
3. Position changes of only ~0.3-0.4 pixels between state updates
4. Multiple enemies affected (Enemy7, Enemy10)

### Root Cause Analysis

The problem stems from the **raycast-based wall avoidance** approach:

1. **Limited Pathfinding**: Raycasts only detect immediate obstacles, not optimal paths around complex structures
2. **Local Minima**: Enemies get trapped against walls when the player is on the other side
3. **State Thrashing**: Unable to progress, enemies rapidly switch states looking for alternatives
4. **Wall Geometry**: The building has L-shaped corridors and room layouts that require planning ahead

The existing wall avoidance code (`_check_wall_ahead()`, `_apply_wall_avoidance()`) works for simple obstacles but fails in complex indoor environments where enemies need to navigate around corners and through doorways.

### Solution: NavigationAgent2D Integration

Instead of relying solely on raycast-based wall avoidance, the solution integrates Godot's **NavigationServer2D** pathfinding system.

**Components Added**:

1. **NavigationAgent2D node to Enemy scene** (`scenes/objects/Enemy.tscn`):
   ```
   [node name="NavigationAgent2D" type="NavigationAgent2D" parent="."]
   path_desired_distance = 4.0
   target_desired_distance = 10.0
   avoidance_enabled = true
   radius = 24.0
   neighbor_distance = 100.0
   max_neighbors = 5
   time_horizon_agents = 1.0
   time_horizon_obstacles = 1.0
   max_speed = 320.0
   ```

2. **NavigationRegion2D with NavigationPolygon to BuildingLevel** (`scenes/levels/BuildingLevel.tscn`):
   ```
   [node name="NavigationRegion2D" type="NavigationRegion2D" parent="."]
   navigation_polygon = SubResource("NavigationPolygon_level")
   ```
   - Covers floor area (64, 64) to (2464, 2064)
   - Uses `parsed_collision_mask = 4` to carve out walls
   - Agent radius = 24.0 (matches enemy collision)

3. **Runtime navigation baking in building_level.gd**:
   ```gdscript
   func _setup_navigation() -> void:
       var nav_region = get_node_or_null("NavigationRegion2D")
       var nav_poly = nav_region.navigation_polygon
       # Bake using NavigationServer2D.parse_source_geometry_data()
       # and NavigationServer2D.bake_from_source_geometry_data()
   ```

4. **Navigation helper functions in enemy.gd**:
   ```gdscript
   @onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D

   func _get_nav_direction_to(target_pos: Vector2) -> Vector2:
       # Uses NavigationAgent2D to get path to target

   func _move_to_target_nav(target_pos: Vector2, speed: float) -> bool:
       # Primary movement function using navigation path
       # Still applies wall_avoidance for tight corners

   func _has_nav_path_to(target_pos: Vector2) -> bool:
       # Check if valid path exists

   func _get_nav_path_distance(target_pos: Vector2) -> float:
       # Get path distance (more accurate than straight line)
   ```

5. **Updated movement in all states**:
   - SEEKING_COVER: Uses `_move_to_target_nav()` for cover position
   - FLANKING: Uses `_move_to_target_nav()` for flank target
   - RETREATING: Uses `_move_to_target_nav()` for retreat positions
   - ASSAULT: Uses `_move_to_target_nav()` for player approach
   - PURSUING: Uses `_move_to_target_nav()` for cover movement and direct approach

### Expected Improvements

1. **Proper Path Planning**: NavigationAgent2D calculates complete paths around obstacles
2. **No Local Minima**: Enemies will find doors and corridors automatically
3. **Reduced State Thrashing**: Smooth movement should stabilize state transitions
4. **Agent Avoidance**: Built-in avoidance between multiple agents
5. **Performance**: Navigation mesh is baked once, path queries are fast

### Files Modified in This Implementation

1. `scenes/objects/Enemy.tscn` - Added NavigationAgent2D node
2. `scripts/objects/enemy.gd` - Added `_nav_agent`, navigation helper functions, updated movement in all states
3. `scenes/levels/BuildingLevel.tscn` - Added NavigationRegion2D and NavigationPolygon
4. `scripts/levels/building_level.gd` - Added `_setup_navigation()` for runtime baking
5. `docs/case-studies/issue-98/README.md` - This update

---

---

## Fourth Implementation: FLANKING→PURSUING Infinite Loop Fix

### Problem Identified

Despite NavMesh integration, the game log still showed a specific "stomping in place" pattern affecting Enemy7 and Enemy10:

```
[ENEMY] [Enemy10] FLANKING stuck (2.0s no progress), target=(1534.44, 484.0432), pos=(1412.007, 824.0698)
[ENEMY] [Enemy10] State: FLANKING -> PURSUING
[ENEMY] [Enemy10] FLANKING started: target=(1534.441, 484.0421), side=left, pos=(1412.003, 824.0698)
```

**Pattern Analysis**:
1. Enemy detects it's stuck in FLANKING state (no progress for 2 seconds)
2. Enemy transitions to PURSUING state
3. PURSUING state can't find cover, calls `_transition_to_flanking()`
4. Enemy immediately restarts flanking with nearly identical unreachable target
5. Loop repeats indefinitely for the remaining 40 seconds of gameplay

**Root Cause**: The FLANKING state transitions to PURSUING on failure, and PURSUING transitions back to FLANKING when it can't find cover. Neither state remembers that flanking just failed, creating an infinite loop.

### Solution Implemented

**New Variables Added**:
```gdscript
## Counter for consecutive flanking failures (to prevent infinite loops).
var _flank_fail_count: int = 0

## Maximum number of consecutive flanking failures before disabling flanking temporarily.
const FLANK_FAIL_MAX_COUNT: int = 2

## Cooldown timer after flanking failures (prevents immediate retry).
var _flank_cooldown_timer: float = 0.0

## Duration to wait after flanking failures before allowing retry (seconds).
const FLANK_COOLDOWN_DURATION: float = 5.0
```

**New Functions Added**:
1. `_can_attempt_flanking() -> bool` - Checks if flanking is available (not on cooldown)
2. `_is_flank_target_reachable() -> bool` - Validates flank target is reachable via NavMesh

**Key Changes**:
1. When stuck detection triggers, increment `_flank_fail_count` and start cooldown
2. After 2 consecutive failures, go directly to COMBAT instead of PURSUING
3. All calls to `_transition_to_flanking()` now check `_can_attempt_flanking()` first
4. `_transition_to_flanking()` validates target is reachable before committing
5. Cooldown timer (5 seconds) allows flanking to re-enable after failures

**Stuck Detection Updated**:
```gdscript
if _flank_stuck_timer >= FLANK_STUCK_MAX_TIME:
    _flank_fail_count += 1
    _flank_cooldown_timer = FLANK_COOLDOWN_DURATION

    # After multiple failures, break the loop by going to COMBAT
    if _flank_fail_count >= FLANK_FAIL_MAX_COUNT:
        _transition_to_combat()  # Not PURSUING!
        return
```

**Expected Behavior After Fix**:
1. First flanking failure: tries PURSUING, which may try flanking again
2. Second flanking failure: goes directly to COMBAT, breaking the loop
3. After 5 seconds cooldown: flanking becomes available again
4. Successful flanking clears the failure counter

### Files Modified

1. `scripts/objects/enemy.gd`:
   - Added failure tracking variables
   - Added `_can_attempt_flanking()` function
   - Added `_is_flank_target_reachable()` function
   - Updated `_transition_to_flanking()` to return bool and check availability
   - Updated all callers to use `_can_attempt_flanking()` instead of just `enable_flanking`
   - Updated `_reset()` to clear failure count and cooldown
   - Added cooldown timer update in `_physics_process()`

---

## Updated Timeline

- **2026-01-18 04:50**: Issue #98 created
- **2026-01-18 05:00**: First implementation (commit 0b694b7) - GDScript parse error
- **2026-01-18 05:14**: Changes reverted
- **2026-01-18 06:XX**: Second implementation with proper types - Code works but "stomping in place"
- **2026-01-18 08:34**: User provides game log showing stomping behavior
- **2026-01-18 08:43**: Game log downloaded to case study folder
- **2026-01-18 XX:XX**: Third implementation - NavMesh integration for proper pathfinding
- **2026-01-18 XX:XX**: Fourth implementation - FLANKING→PURSUING loop fix with failure tracking
