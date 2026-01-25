# Case Study: Issue #373 - Enemies Turn Away When Seeing Player

## Issue Summary

**Original Title (Russian):** "fix враги резко отворачиваются когда видят игрока"
**Translation:** "fix enemies sharply turn away when they see the player"

**Description:** Enemies should not sharply turn away when the player enters their field of view. In the logs, during the first 2 restarts, the enemy turned away instead of starting combat. This possibly occurs only horizontally.

## Log Files Analyzed

- `game_log_20260125_090013.txt` (112KB) - Shows repeated IDLE->COMBAT->PURSUING transitions
- `game_log_20260125_090150.txt` (75KB) - Shows similar patterns

---

## Root Cause Analysis

### The Bug

When enemies detect the player and enter COMBAT state, they quickly lose sight of the player (within 0.5-1 seconds) and transition to PURSUING state. The sequence observed in logs:

```
[09:00:17] [ENEMY] [Enemy3] State: IDLE -> COMBAT
[09:00:18] [ENEMY] [Enemy3] State: COMBAT -> PURSUING
```

This happens because of a race condition between visibility checking and model rotation.

### Technical Analysis

#### Order of Operations in `_physics_process()`

```gdscript
func _physics_process(delta: float) -> void:
    # ... other code ...

    _check_player_visibility()        # Line 979: Checks FOV using current model rotation
    _update_memory(delta)
    _update_goap_state()
    _update_suppression(delta)

    _update_enemy_model_rotation()    # Line 990: Rotates model based on _can_see_player

    _process_ai_state(delta)          # Line 993: Sets velocity based on state
```

#### FOV Check Function

The `_is_position_in_fov()` function uses the enemy model's current rotation to determine the FOV cone:

```gdscript
func _is_position_in_fov(target_pos: Vector2) -> bool:
    # ...
    var facing_angle := _enemy_model.global_rotation if _enemy_model else rotation
    var dir_to_target := (target_pos - global_position).normalized()
    var dot := Vector2.from_angle(facing_angle).dot(dir_to_target)
    var angle_to_target := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
    var in_fov := angle_to_target <= fov_angle / 2.0
    return in_fov
```

#### Model Rotation Priority

In `_update_enemy_model_rotation()`:

```gdscript
func _update_enemy_model_rotation() -> void:
    # ...
    if _player != null and _can_see_player:
        target_angle = player_direction       # Priority 1: Face player if visible
    elif _corner_check_timer > 0:
        target_angle = _corner_check_angle    # Priority 2: Corner check
    elif velocity.length_squared() > 1.0:
        target_angle = velocity.normalized().angle()  # Priority 3: Face movement
    # ...
```

### The Race Condition

1. **Frame N-1:** Enemy is patrolling/moving with corner check active or velocity-based rotation
2. **Frame N:**
   - `_check_player_visibility()` runs first
   - FOV check uses current `_enemy_model.global_rotation` (pointing away from player due to corner check or velocity)
   - Player is NOT in FOV (model is facing wrong direction)
   - `_can_see_player` stays `false`
   - `_update_enemy_model_rotation()` runs
   - Since `_can_see_player` is false, model rotates toward velocity or corner instead of player
   - Cycle repeats

3. **In COMBAT state specifically:**
   - Enemy enters COMBAT when player is briefly visible
   - Movement starts (approaching player or seeking clear shot)
   - Wall avoidance modifies velocity direction
   - `velocity.length_squared() > 1.0` triggers velocity-based rotation
   - Model rotates toward (potentially different) movement direction
   - Next frame: FOV check fails because model is now facing movement direction, not player
   - `_can_see_player` becomes `false`
   - After 0.5s (`COMBAT_MIN_DURATION_BEFORE_PURSUE`), transitions to PURSUING

### Evidence from Logs

Pattern 1: Rapid state transitions
```
[09:00:17] [ENEMY] [Enemy3] State: IDLE -> COMBAT
[09:00:18] [ENEMY] [Enemy3] State: COMBAT -> PURSUING
```

Pattern 2: Multiple occurrences (level restarts)
```
[09:00:41] [ENEMY] [Enemy3] State: IDLE -> COMBAT
[09:00:42] [ENEMY] [Enemy3] State: COMBAT -> PURSUING

[09:00:45] [ENEMY] [Enemy3] State: IDLE -> COMBAT
```

Pattern 3: The corner check is happening during PATROL/PURSUING, and the angles suggest the enemy model is facing various directions:
```
[09:00:17] [ENEMY] [Enemy7] PATROL corner check: angle 89.5°
```

---

## Proposed Solution

### Solution: Use Intent-Based FOV Check for Combat States

When the enemy is in a combat-related state (COMBAT, PURSUING, FLANKING, etc.) or has recently detected the player, the FOV check should consider whether the player WOULD be visible if the enemy were facing toward them, not just whether the player is currently in the model's actual FOV.

### Implementation Approach

**Option A: Always check visibility toward player in combat states (Recommended)**

In combat states, enemies should maintain awareness of the player even if their model is temporarily rotated away due to movement. The FOV restriction should primarily apply to initial detection, not to maintaining combat awareness.

```gdscript
func _check_player_visibility() -> void:
    # ... existing checks for blinded, confused, etc. ...

    # Check FOV angle
    # In combat-related states, use expanded awareness (check if player could be seen)
    var in_combat_state := _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.ASSAULT]

    if in_combat_state:
        # In combat: check if player is within line-of-sight (ignore model rotation)
        # This simulates the enemy's awareness that the player is there
        if not _is_position_in_detection_range(_player.global_position):
            _continuous_visibility_timer = 0.0
            return
        # Skip FOV check - enemy knows player is there from previous detection
    else:
        # Not in combat: use strict FOV check for initial detection
        if not _is_position_in_fov(_player.global_position):
            _continuous_visibility_timer = 0.0
            return

    # ... rest of visibility check (raycast to player) ...
```

**Option B: Smooth FOV transition during rotation**

When the model is rotating toward the player, temporarily expand FOV to prevent flickering visibility:

```gdscript
func _is_position_in_fov(target_pos: Vector2) -> bool:
    # ... existing code ...

    # If we were seeing the player recently, use expanded FOV during rotation
    if _continuous_visibility_timer > 0.0:
        # Add grace period FOV expansion
        effective_fov = fov_angle + 30.0  # Add 30 degrees during rotation
    else:
        effective_fov = fov_angle

    var in_fov := angle_to_target <= effective_fov / 2.0
    return in_fov
```

**Option C: Decouple model rotation from awareness**

The enemy's "awareness" of player position should be separate from the visual model rotation. The model can smoothly rotate for visual polish, but the AI's knowledge of player position should be instant.

---

## Recommended Fix

Implement **Option A** with a modification: In combat-related states, skip the FOV check entirely but still require line-of-sight (raycast). This matches real-world behavior where a combatant is aware of their opponent's position even when momentarily looking away.

### Code Changes

```gdscript
## In _check_player_visibility(), after the blinded/confused checks:

# Check if player is within detection range (only if detection_range is positive)
if detection_range > 0 and distance_to_player > detection_range:
    _continuous_visibility_timer = 0.0
    return

# FOV check behavior depends on current state
var in_combat_state := _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.ASSAULT, AIState.RETREATING, AIState.SEEKING_COVER]

if in_combat_state:
    # In combat states: enemy maintains awareness of player location
    # Only require line-of-sight, not FOV (enemy knows player is there)
    pass  # Skip FOV check, proceed to raycast visibility check
else:
    # Not in combat: strict FOV check required for initial detection
    if not _is_position_in_fov(_player.global_position):
        _continuous_visibility_timer = 0.0
        return
```

---

## Test Cases

1. **Initial Detection:** Enemy in IDLE/PATROL detects player only when player is in FOV
2. **Combat Awareness:** Enemy in COMBAT maintains awareness of player even when model rotates due to movement
3. **Visibility Loss:** Enemy loses sight when actual raycast is blocked (wall between enemy and player)
4. **State Transitions:** COMBAT->PURSUING should only happen when raycast is blocked, not due to FOV

---

## Update: Second Fix Attempt (2026-01-25)

### What the First Fix Did (Commit 0ea96d1)

The first fix modified `_check_player_visibility()` to skip FOV checks in combat states:
```gdscript
var in_combat_state := _current_state in [AIState.COMBAT, AIState.PURSUING, ...]
if not in_combat_state and not _is_position_in_fov(_player.global_position):
    return  # Only check FOV for initial detection
```

**Result:** Issue persisted - enemies still turning away.

### Why the First Fix Was Insufficient

The first fix addressed the **visibility detection** problem but NOT the **rotation control** problem. Even with FOV check skipped, the model was still being rotated away from the player in `_update_enemy_model_rotation()`:

```gdscript
# Original code (buggy)
if _player != null and _can_see_player:
    target_angle = player.angle()
elif velocity.length_squared() > 1.0:
    target_angle = velocity.angle()  # <-- Falls back to velocity when _can_see_player flickers
```

When `_can_see_player` becomes false (due to raycast flicker at wall edges), the model rotates toward velocity direction, causing the visual "turn away" behavior.

### New Log Files Analyzed (Session 2)

- `game_log_20260125_092258.txt` (1901 lines)
- `game_log_20260125_092345.txt` (1177 lines)

Key observations from logs:
1. COMBAT->PURSUING transitions happen without "Lost sight of player" message
2. Transitions are triggered by vulnerability pursuit code, not visibility loss
3. Corner check angles show model facing various directions during combat

### Root Cause (Refined)

The issue has TWO components:
1. **Visibility detection** - Fixed by skipping FOV in combat states (first fix)
2. **Rotation control** - The model stops facing the player when `_can_see_player` flickers

### Second Fix Applied

Modified `_update_enemy_model_rotation()` to use `_get_target_position()` in combat states:

```gdscript
func _update_enemy_model_rotation() -> void:
    var in_combat_state := _current_state in [AIState.COMBAT, AIState.PURSUING, ...]

    if in_combat_state:
        # Always face target position (player > memory > last known)
        var target_pos := _get_target_position()
        if target_pos != global_position:
            target_angle = (target_pos - global_position).angle()
            has_target = true
    elif _player != null and _can_see_player:
        # Non-combat: only face when visible
        target_angle = (_player.global_position - global_position).angle()
        has_target = true
```

### Why This Works

1. `_get_target_position()` returns: visible player > memory position > last known position
2. In combat states, enemy ALWAYS has a target to face (no velocity fallback)
3. Even if raycast flickers, enemy maintains facing toward last known player position
4. Combined with first fix: enemy doesn't "turn away" during combat

---

## References

- Issue #347: Smooth rotation for visual polish
- Issue #332: Corner checking during movement
- Issue #367: FLANKING/PURSUING wall-stuck detection
- Related concepts: [Game AI awareness systems](https://www.gamedeveloper.com/design/the-ai-of-halo-2)

