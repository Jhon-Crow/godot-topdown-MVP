# Case Study: Issue #94 - AI Enemies Shooting Through Walls in COMBAT State

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/94

**Problem Description (Russian):**
> враги находясь за тонким укрытием или сбоку укрытия начинают стрелять в сторону игрока, при этом все снаряды попадают в стену, в которую направлен выстрел.
> добавь проверку чтоб избежать стрельбы в стену, к которой враг находится впритык.
> сделай надёжный выход врага из укрытия (чтоб выход из укрытия прекращался только тогда, когда враг точно может попасть в игрока).

**English Translation:**
> Enemies behind thin cover or at the side of cover start shooting toward the player, but all projectiles hit the wall they're aiming through.
> Add a check to prevent shooting into a wall that the enemy is right next to.
> Make a reliable cover exit mechanism (so that exiting cover only stops when the enemy can definitely hit the player).

## Timeline and Sequence of Events

### Current Behavior Flow

1. **Enemy detects player** -> `_can_see_player` becomes true via raycast from enemy center to player
2. **Enemy enters COMBAT state** -> Approaches player and starts shooting phase
3. **Enemy positioned near wall/cover edge** -> Enemy is close to or touching thin cover
4. **Shooting logic executes** -> `_shoot()` is called
5. **Shot validation** -> `_should_shoot_at_target()` checks:
   - `_is_firing_line_clear_of_friendlies()` - checks for friendly fire
   - `_is_shot_clear_of_cover()` - checks if obstacles block the shot
6. **BUG: Shot appears clear** -> Raycast from `bullet_spawn_offset` (30px ahead) misses the adjacent wall
7. **Bullet spawns and hits wall** -> Bullet spawns at offset position and immediately collides

## Root Cause Analysis

### Primary Issue: Bullet Spawn Point Validation

**Location:** `scripts/objects/enemy.gd:1893-1917` (`_is_shot_clear_of_cover()`)

The current implementation:
```gdscript
func _is_shot_clear_of_cover(target_position: Vector2) -> bool:
    var direction := (target_position - global_position).normalized()
    var distance := global_position.distance_to(target_position)

    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position + direction * bullet_spawn_offset  # Start from bullet spawn point
    query.to = target_position
    query.collision_mask = 4  # Only check obstacles (layer 3)
    # ... rest of validation
```

**Problem:** The raycast starts from `global_position + direction * bullet_spawn_offset`, which is 30 pixels ahead of the enemy's center. When the enemy is positioned:
- Flush against a wall
- At the side of thin cover
- Very close to any obstacle

The raycast starting point may already be **past** the wall (on the wrong side), or the short distance from enemy center to bullet spawn point crosses through the wall undetected.

### Missing Check: Enemy-to-Spawn-Point Wall Detection

There is no check to verify that the path from the enemy's center to the bullet spawn point is clear.

## First Implementation Attempt (FAILED)

### What Was Done

The first fix attempt added extensive changes to `_process_combat_state()`:
1. Added a new `_is_immediate_path_clear()` function with multiple raycasts (center + two side checks)
2. Modified the exposed phase logic to check wall clearance before entering
3. Added `else: return` branches for null player checks
4. Modified multiple state transitions

### What Went Wrong

**User Feedback:**
> "everything broke - enemies stopped moving, taking damage, etc. F7 debug toggle also stopped working"

**Analysis:**
The changes were too extensive and modified the state machine flow in ways that caused unintended side effects:

1. **Structural changes to `_process_combat_state()`**: The addition of conditional blocks with `else: return` statements altered the control flow
2. **Complex multi-raycast function**: The side-ray checks added complexity that wasn't necessary for the core fix
3. **State machine modifications**: Changes to exposed phase entry/exit conditions affected enemy behavior

The key lesson: **Making multiple changes to a complex state machine simultaneously makes it hard to identify which change caused the regression.**

## Second Implementation Attempt (CONSERVATIVE)

### Approach

After reverting to the main branch, a minimal and conservative fix was implemented:

1. **Single new function**: `_is_bullet_spawn_clear()` - performs ONE raycast from enemy center to bullet spawn point
2. **No state machine changes**: Only the shooting validation was modified
3. **Fail-open safety**: If physics isn't available, allow shooting (prevents total breakage)
4. **Targeted modifications**: Only three places in code were touched

### Implementation Details

```gdscript
## Check if there's an obstacle immediately in front of the enemy that would block bullets.
## This prevents shooting into walls that the enemy is flush against or very close to.
## Uses a single raycast from enemy center to the bullet spawn position.
func _is_bullet_spawn_clear(direction: Vector2) -> bool:
    var space_state := get_world_2d().direct_space_state
    if space_state == null:
        return true  # Fail-open: allow shooting if physics not available

    # Check from enemy center to bullet spawn position plus a small buffer
    var check_distance := bullet_spawn_offset + 5.0

    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position
    query.to = global_position + direction * check_distance
    query.collision_mask = 4  # Only check obstacles (layer 3)
    query.exclude = [get_rid()]

    var result := space_state.intersect_ray(query)
    if not result.is_empty():
        _log_debug("Bullet spawn blocked: wall at distance %.1f" % [
            global_position.distance_to(result["position"])])
        return false

    return true
```

### Changes Made

1. **`_should_shoot_at_target()`**: Added call to `_is_bullet_spawn_clear()` at the start
2. **`_shoot_with_inaccuracy()`**: Added post-inaccuracy check to prevent rotated shots hitting walls
3. **`_shoot_burst_shot()`**: Added post-rotation check for burst fire

### Total Lines Changed: ~50 (compared to ~150 in first attempt)

## Lessons Learned

1. **Minimal changes**: When fixing a bug in a complex system, make the smallest possible change
2. **Don't modify state machines unless necessary**: The core issue was in shooting validation, not state transitions
3. **Fail-open for safety**: Non-critical checks should fail open (allow the action) if the check itself fails
4. **Test incrementally**: Each change should be testable in isolation
5. **Preserve existing behavior**: Only modify what's strictly necessary to fix the bug

## Impact Assessment

### Files Modified
- `scripts/objects/enemy.gd`

### Risk Level: Low
- Changes are additive (new validation check)
- No state machine modifications
- Existing functionality is preserved
- Fail-open design prevents total breakage

## Testing Strategy

1. **Basic test**: Enemy next to thin wall should not shoot into wall
2. **Normal combat**: Enemy not near walls should shoot normally
3. **Edge cases**:
   - Enemy flush against wall, player on other side
   - Enemy at corner of cover
   - Enemy at edge of thin pillar
4. **Regression test**: Verify enemies still move, take damage, F7 debug works

## Third Implementation Attempt: Critical Bug Fix

### Problem Discovery

After the second implementation, users reported that AI was completely broken - enemies didn't move, didn't respond to damage, and F7 debug toggle didn't work.

### Root Cause Analysis

Upon examining the CI build logs, we discovered **GDScript parse errors** in the `enemy.gd` file:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "sidestep_dir" variable because the value doesn't have a set type.
SCRIPT ERROR: Parse Error: Cannot infer the type of "test_position" variable because the value doesn't have a set type.
ERROR: Failed to load script "res://scripts/objects/enemy.gd" with error "Parse error".
```

**The script failed to load entirely**, which explains why:
- Enemies didn't move (no AI logic running)
- Enemies didn't take damage (no hit processing)
- F7 debug toggle didn't work (no debug label toggling)

### Technical Details

The issue was in the `_find_sidestep_direction_for_clear_shot()` function:

```gdscript
# BROKEN - type inference fails inside for loop with untyped iterator
for side_multiplier in [1.0, -1.0]:
    var sidestep_dir := perpendicular * side_multiplier  # Error: Can't infer type
    var test_position := global_position + sidestep_dir * check_distance  # Error: Can't infer type
```

When using `:=` (inferred type) for variables inside a for loop where the iterator variable is untyped, Godot's parser can't infer the type because it doesn't know that `side_multiplier` is a `float`.

### Fix Applied

```gdscript
# FIXED - explicit types for loop iterator and variables
for side_multiplier: float in [1.0, -1.0]:
    var sidestep_dir: Vector2 = perpendicular * side_multiplier
    var test_position: Vector2 = global_position + sidestep_dir * check_distance
```

### Additional Improvements

1. **Added FileLogger autoload**: Writes log files next to the EXE for debugging exported builds
2. **Enhanced null checking**: Defensive coding for `get_world_2d()` and `direct_space_state`
3. **Added logging calls**: Enemy spawn, hit, death, and state change events are logged to file

### Lesson Learned

**Always check CI build logs for parse errors.** The build can succeed (producing an EXE) even if scripts have parse errors. In Godot, a script with parse errors simply won't load, causing silent failures at runtime.

## Collected Data

### CI Build Logs

The `ci-logs/` directory contains the CI build logs collected during the investigation:
- `build-21103908270.log` - Build after sidestep behavior commit
- `build-21104089330.log` - Build after parse error fixes
- `build-21104116910.log` - Build after type inference fixes
- `latest-build.log` - Most recent CI build log

These logs were essential for discovering the GDScript parse errors that caused the AI to completely fail in exported builds.

## Fourth Implementation: Cover Exit Loop Fix

### Problem Discovery (2026-01-18)

User reported that enemies were still stuck in cover, cycling through COMBAT → SEEKING_COVER → IN_COVER repeatedly without actually exiting cover to engage the player.

**User Feedback (Russian):**
> "сейчас враги в COMBAT состоянии не выходят из-за укрытия, просто перезапускается таймер по кругу.
> а должны выходить на ту линию, с которой в последний раз можно было стрелять в игрока"

**Translation:**
> "Currently enemies in COMBAT state don't exit cover, the timer just restarts in a loop.
> They should exit to the line from which they could last shoot at the player."

### Root Cause Analysis

The `_is_bullet_spawn_clear()` check correctly prevented shooting into walls, but created a new issue:

1. Enemy in IN_COVER state sees player and transitions to COMBAT
2. In COMBAT state, `_is_bullet_spawn_clear()` returns false (wall blocking bullet spawn)
3. Enemy tries to sidestep to find clear shot position
4. Sidestep fails (no clear position nearby due to wall geometry)
5. After timeout, enemy transitions to SEEKING_COVER or PURSUING
6. PURSUING leads back to IN_COVER
7. Loop repeats indefinitely

**The core issue:** When the enemy can't find a clear shot by sidestepping, they need to **move out from cover** entirely, not just cycle back to cover.

### Solution Implemented

Added a new "clear shot seeking" phase to the COMBAT state:

```gdscript
## --- Clear Shot Movement (move out from cover to get clear shot) ---
var _clear_shot_target: Vector2 = Vector2.ZERO
var _seeking_clear_shot: bool = false
var _clear_shot_timer: float = 0.0
const CLEAR_SHOT_MAX_TIME: float = 3.0
const CLEAR_SHOT_EXIT_DISTANCE: float = 60.0
```

**New behavior flow:**

1. Enemy enters COMBAT from IN_COVER
2. `_is_bullet_spawn_clear()` returns false
3. **NEW:** Enemy enters "seeking clear shot" phase
4. **NEW:** `_calculate_clear_shot_exit_position()` calculates a target position that:
   - Is perpendicular to the player direction (moves around cover edge)
   - Has a clear path from current position
   - Would allow the bullet spawn point to be unobstructed
5. Enemy moves toward that target position
6. When bullet spawn becomes clear, enemy immediately enters exposed shooting phase
7. After shooting duration (2-3s), enemy returns to cover

**Fallback behavior:**
- If no clear shot found after 3 seconds, enemy transitions to FLANKING state
- FLANKING attempts to navigate around obstacles from a different angle

### Debug Visualization Added

Added visual debug drawing when F7 debug mode is enabled:

- **Red line:** Direction to player (when visible)
- **Green circle:** Bullet spawn point (if clear)
- **Red X:** Bullet spawn point (if blocked)
- **Cyan line + circle:** Path to cover position
- **Yellow line + triangle:** Path to clear shot target (when seeking clear shot)
- **Orange line + circle:** Path to pursuit cover
- **Magenta line + diamond/circle:** Path to flank target/cover

The debug label also shows:
- `(SEEK SHOT X.Xs)` - Time remaining in clear shot seeking phase
- `(EXPOSED X.Xs)` - Time remaining in exposed shooting phase
- `(APPROACH)` - Approaching player

### Files Modified

- `scripts/objects/enemy.gd`:
  - Added clear shot seeking variables (~10 lines)
  - Rewrote `_process_combat_state()` to include clear shot seeking phase (~100 lines)
  - Added `_calculate_clear_shot_exit_position()` function (~50 lines)
  - Added `_draw()` function for debug visualization (~70 lines)
  - Updated `_transition_to_combat()` to reset clear shot variables (~3 lines)
  - Updated `_update_debug_label()` to show clear shot seeking state (~3 lines)

### Testing Plan

- [ ] Enemies should move out from cover to find clear shot position
- [ ] Debug mode (F7) should show:
  - Yellow triangle at clear shot target
  - Red X at bullet spawn point when blocked
  - Green circle at bullet spawn point when clear
- [ ] Enemies should shoot when they find a clear position
- [ ] Enemies should return to cover after shooting for 2-3 seconds
- [ ] Enemies should transition to FLANKING if no clear shot found

## Collected User Log Files

The `user-logs/` directory contains game log files uploaded by users:
- `game_log_20260118_045534.txt` - Log showing enemy state cycling issue

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/94
- Pull Request: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/95
- Main file: `scripts/objects/enemy.gd`
- Key functions:
  - `_process_combat_state()` - Lines 779-966 (rewritten)
  - `_calculate_clear_shot_exit_position()` - Lines 969-1019 (NEW)
  - `_is_bullet_spawn_clear()` - Line 2007 (was 1923)
  - `_draw()` - Lines 3140-3205 (NEW debug visualization)
