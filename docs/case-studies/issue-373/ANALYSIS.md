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

## Update: Third Fix Attempt (2026-01-25)

### Why the Second Fix Was Still Insufficient

After the second fix, the user reported the problem persists (log: `game_log_20260125_100732.txt`). Analysis revealed a subtle bug:

1. In combat states, `_get_target_position()` is called
2. If ALL of these are true: `_can_see_player` is false, memory has decayed, AND `_last_known_player_position` is `Vector2.ZERO` - it returns `global_position`
3. When `target_pos == global_position`, `has_target` was NOT set to true
4. The code then falls through to velocity-based rotation (for moving enemies)
5. This causes the enemy model to rotate toward movement direction instead of player!

### Third Fix Applied

Added a fallback in `_update_enemy_model_rotation()` that uses the player's actual position when memory is unavailable:

```gdscript
if in_combat:  # Issue #373: always face player/target in combat, no velocity fallback
    var target_pos := _get_target_position()
    if target_pos != global_position:
        target_angle = (target_pos - global_position).normalized().angle()
        has_target = true
    elif _player != null:  # Fallback: face player directly even without memory
        target_angle = (_player.global_position - global_position).normalized().angle()
        has_target = true
```

### Why This Works

When in combat state, the enemy will face:
1. Memory/last known position (via `_get_target_position()`) - primary
2. Player's actual position (fallback when memory unavailable)
3. NEVER falls back to velocity-based rotation during combat

This ensures enemies maintain facing toward the player throughout combat, regardless of memory state.

---

## Update: Fourth Fix Attempt (2026-01-25)

### Why the Third Fix Was Still Insufficient

After the third fix, the user reported the problem persists (log: `game_log_20260125_102545.txt`). The user's comment "может дело в рассогласованности языков или в резком включении какого то поведения?" (maybe it's due to language inconsistency or sudden activation of some behavior?) provided a key insight.

Analysis revealed the **fundamental flaw** in the previous approach:

1. All previous fixes still used `_get_target_position()` as the PRIMARY source for rotation
2. `_get_target_position()` returns memory/last known position when `_can_see_player` is false
3. **Memory positions can be STALE** - the player may have moved significantly since the position was recorded
4. When the player moves and the raycast flickers, the enemy would face the OLD (stale) position
5. This causes the visual "turn-away" behavior even though the fallback to player position exists

### Root Cause (Final Analysis)

The problem is a **priority inversion**: We were prioritizing stale memory positions over the player's ACTUAL position in active combat states.

In states like COMBAT, FLANKING, ASSAULT, etc., the enemy is actively engaging and can reasonably be assumed to know where the player is - they should face the player DIRECTLY, not rely on potentially stale memory.

Memory-based facing makes sense for PURSUING and SEARCHING states where the enemy has genuinely lost sight of the player and is tracking their last known location.

### Fourth Fix Applied

Changed the rotation logic to distinguish between:
- **Active combat states** (COMBAT, FLANKING, ASSAULT, RETREATING, SEEKING_COVER, IN_COVER, SUPPRESSED) - face player DIRECTLY
- **Tracking states** (PURSUING, SEARCHING) - use memory/last known position

```gdscript
# Active combat = face player directly. PURSUING/SEARCHING = use memory for last known position.
var active_combat := _current_state in [AIState.COMBAT, AIState.FLANKING, AIState.ASSAULT,
                                         AIState.RETREATING, AIState.SEEKING_COVER,
                                         AIState.IN_COVER, AIState.SUPPRESSED]
var tracking_mode := _current_state in [AIState.PURSUING, AIState.SEARCHING]

if active_combat and _player != null:  # Face player directly in active combat
    target_angle = (_player.global_position - global_position).normalized().angle()
    has_target = true
elif tracking_mode:  # Use memory/last known for PURSUING/SEARCHING
    var target_pos := _get_target_position()
    if target_pos != global_position:
        target_angle = (target_pos - global_position).normalized().angle()
        has_target = true
    elif _player != null:
        target_angle = (_player.global_position - global_position).normalized().angle()
        has_target = true
```

### Why This Works

1. In active combat, enemy ALWAYS faces player's ACTUAL position - no stale memory interference
2. Memory/last known position is still used for PURSUING/SEARCHING where it makes gameplay sense
3. The priority is now correct: actual player position > memory position for active engagement
4. This eliminates the "turn-away" caused by facing stale memory positions

---

## Update: Fifth Investigation (2026-01-25)

### Why the Fourth Fix Was Still Insufficient

After the fourth fix, the user reported the problem persists (log: `game_log_20260125_103903.txt`). At this point, we've tried:

1. ✅ Skip FOV check in combat states - prevents visibility flickering
2. ✅ Use target position in combat states - better than velocity-based rotation
3. ✅ Add player fallback when memory empty - ensures always has a target
4. ✅ Face player DIRECTLY in active combat - avoid stale memory positions

All these fixes address potential causes, yet the bug persists. This suggests the root cause might be something we haven't analyzed yet.

### Deep Dive: What Could We Be Missing?

After extensive code analysis, the rotation logic appears correct:
- `_update_enemy_model_rotation()` runs BEFORE `_process_ai_state()`
- In active combat states, it directly uses `_player.global_position`
- The angle calculation and smooth rotation are standard Godot patterns

Potential unexplored areas:
1. **Other rotation modifiers** - `_force_model_to_face_direction()` is called in priority attack code, but it faces TOWARD the player
2. **Timing issues** - One-frame delay during state transitions (rotation calculated before state change)
3. **Visual flip issues** - The Y-scale flip at ±90° boundary could cause visual glitches

### Solution: Add Rotation Tracing

To pinpoint the exact cause, added detailed rotation logging to `_update_enemy_model_rotation()`:

```gdscript
if angle_change_degrees > 30.0:  # Log significant rotation changes
    _log_to_file("ROT %s: %.1f° -> %.1f° (diff=%.1f°, src=%s, state=%s)" % [
        name, rad_to_deg(current_rot), rad_to_deg(target_angle),
        angle_change_degrees, rotation_source, AIState.keys()[_current_state]
    ])
```

This logs:
- Current and target angles (in degrees)
- Angle change magnitude
- Rotation source: `ACTIVE_COMBAT_PLAYER`, `TRACKING_MEMORY`, `TRACKING_PLAYER_FALLBACK`, `VISIBLE_PLAYER`, `CORNER_CHECK`, `VELOCITY`, `IDLE_SCAN`
- Current AI state

### Expected Log Output

When the turn-away occurs, the logs should show exactly which code path triggered it and what the angle change was. This will definitively identify whether:
- The wrong rotation source is being used
- The angle calculation is incorrect
- Some other factor is at play

---

## Update: Sixth Fix Attempt (2026-01-25) - THE ROOT CAUSE FOUND

### The Actual Root Cause

After deep analysis including research on Godot forums and game dev resources, we identified the **actual root cause**: The sprite flip was happening based on **current rotation** instead of **target rotation**.

#### How the Bug Manifested

1. Enemy detects player, starts rotating toward them
2. Rotation is SMOOTH (gradual, at `MODEL_ROTATION_SPEED` = 3.0 rad/s)
3. When current rotation crosses the ±90° (PI/2) threshold...
4. **INSTANT SPRITE FLIP** - the Y-scale changes from +1 to -1 or vice versa
5. This instant flip during smooth rotation creates a visual "pop" or "jerk"
6. Player perceives this as the enemy "turning away sharply"

#### Why Previous Fixes Didn't Work

All previous fixes addressed the **rotation target calculation**:
- Fix 1: Skip FOV in combat (visibility)
- Fix 2: Use `_get_target_position()` (rotation source)
- Fix 3: Add player fallback when memory empty (rotation source)
- Fix 4: Face player DIRECTLY in active combat (rotation source)

But NONE of them addressed the **sprite flip timing**. The rotation target was correct, but the visual flip happened at the wrong moment.

### The Fix

Changed the sprite flip from being based on **current rotation** to **target rotation**:

**Before (buggy):**
```gdscript
# Smooth rotation first
_enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta

# Then flip based on CURRENT rotation (after smooth interpolation)
var aiming_left := absf(_enemy_model.global_rotation) > PI / 2
_model_facing_left = aiming_left
if aiming_left:
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
```

**After (fixed):**
```gdscript
# Flip based on TARGET angle (where we're GOING, not where we ARE)
var target_facing_left := absf(target_angle) > PI / 2
if target_facing_left != _model_facing_left:
    _model_facing_left = target_facing_left
    if _model_facing_left:
        _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
    else:
        _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)

# Then smooth rotation
_enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta
```

### Why This Works

1. **Flip happens at the START**: When we decide to face the player, we immediately know which side they're on (target angle)
2. **No mid-transition flip**: The sprite flip happens once when we start rotating, not during the smooth transition
3. **Consistent visual**: Enemy smoothly rotates toward player without any visual "pop"

### Technical Background

This is a known issue in 2D game development with smooth rotation + sprite flip:
- [Godot Issue #25759](https://github.com/godotengine/godot/issues/25759): Random flipping when rotated
- [Godot Issue #12335](https://github.com/godotengine/godot/issues/12335): Flipping 2D characters with non-uniform scaling
- Best practice: Flip based on **intent** (target), not **current state**

---

## Update: Seventh Fix Attempt (2026-01-25) - THE ACTUAL ROOT CAUSE

### Why the Sixth Fix Was Still Insufficient

After the sixth fix, the user reported the problem persists (log: `game_log_20260125_110119.txt`). Analysis of the rotation logs revealed the true root cause:

```
948:[11:01:29] ROT Enemy3: 126.6° -> 165.6° (diff=39.0°, src=ACTIVE_COMBAT_PLAYER, state=COMBAT)
951:[11:01:29] ROT Enemy3: -64.9° -> 166.8° (diff=128.3°, src=ACTIVE_COMBAT_PLAYER, state=COMBAT)
```

Notice how the current rotation jumped from `126.6°` to `-64.9°` in just one frame! The target angle only moved from `165.6°` to `166.8°`, so the target was stable. This 191° jump in current rotation is the visual "turn away".

### The True Root Cause: No Rotation Compensation When Flipping

When the sprite's Y-scale is flipped, the visual interpretation of the rotation angle changes:

**Without Y-flip:** Rotation `θ` → Sprite faces direction `θ`
**With Y-flip:** Rotation `θ` → Sprite faces direction `-θ` (mirrored)

The sixth fix changed the flip timing to be based on target angle instead of current angle, but it **did not compensate the rotation** when the flip happened!

Here's what was happening:
1. Enemy3 is at rotation `126.6°`, facing upper-left
2. Player is at angle `165.6°` (behind the enemy, to the left)
3. Since `|165.6°| > 90°`, target is "facing left", so we flip the sprite
4. **Y-scale flips to negative**
5. Now the same rotation value `126.6°` visually appears as `-126.6°` (reflected)
6. Wrapped to the valid range, this becomes approximately `-64.9°` (lower-right)
7. **Enemy visually snaps from facing upper-left to facing lower-right** - the "turn away"!

### The Actual Fix

When the Y-scale flips, we must also negate the rotation to maintain the same visual direction:

```gdscript
var target_facing_left := absf(target_angle) > PI / 2
if target_facing_left != _model_facing_left:
    _model_facing_left = target_facing_left
    # CRITICAL: Compensate rotation when flipping to maintain visual direction
    # Before flip: visual_angle = rotation
    # After flip: visual_angle = -rotation
    # So we negate rotation to keep visual_angle unchanged
    _enemy_model.global_rotation = -_enemy_model.global_rotation
    _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale if _model_facing_left else enemy_model_scale)
```

### Why This Works

1. **Before flip:** rotation = `126.6°`, Y-scale positive → visual direction = `126.6°`
2. **After flip:** rotation = `-126.6°`, Y-scale negative → visual direction = `-(-126.6°)` = `126.6°`

The visual direction stays the same! The sprite smoothly continues rotating toward the target instead of snapping to the opposite direction.

### Mathematical Proof

In 2D with Y-scale reflection:
- If Y-scale is positive (s, s), rotation θ gives visual angle θ
- If Y-scale is negative (s, -s), rotation θ gives visual angle -θ

To maintain visual continuity when changing from positive to negative Y-scale:
```
visual_before = θ
visual_after = -θ_new = θ (we want same visual)
Therefore: θ_new = -θ
```

We must negate the rotation when we flip the Y-scale.

---

## Update: Eighth Fix Attempt (2026-01-25)

### Why the Seventh Fix Was Still Insufficient

After the seventh fix, the user reported the problem persists (log: `game_log_20260125_111417.txt`). The user's description was clear: "когда я попадаю в поле зрения врага слева - он резко поворачивается вправо и плавно поворачивается по часовой стрелке ко мне" (When I enter the enemy's field of view from the left - he sharply turns to the right and then smoothly turns clockwise toward me).

Analysis revealed **TWO remaining issues**:

#### Issue 1: Smooth rotation didn't account for "visual space"

The seventh fix compensated the rotation when the Y-scale flipped, but the smooth rotation calculation still operated in "raw" rotation space, not "visual" space:

```gdscript
# After flip, current_rot is negated (correct)
var current_rot := _enemy_model.global_rotation  // e.g., -30° (raw)
// But with Y-scale negative, visual is actually +30°!
var angle_diff := wrapf(target_angle - current_rot, -PI, PI)
// target_angle = 165°, current_rot = -30°
// angle_diff = 165° - (-30°) = 195° (almost full circle!)
```

The math was comparing target angle (in visual space) with current rotation (in raw space), causing the enemy to take the "long way around" when rotating.

#### Issue 2: `_force_model_to_face_direction()` wasn't compensating

The function `_force_model_to_face_direction()` (used for priority attacks) was setting rotation directly without accounting for Y-scale:

```gdscript
_enemy_model.global_rotation = target_angle  // Visual appears as -target_angle when Y-scale negative!
```

This caused instant visual "snap" in the wrong direction when the enemy performed a priority attack.

### The Eighth Fix

Two changes were made:

**1. Smooth rotation in "visual space":**
```gdscript
# Get current VISUAL rotation (accounting for Y-scale flip)
var raw_rot := _enemy_model.global_rotation
var visual_rot := -raw_rot if _model_facing_left else raw_rot

# Smooth rotation in VISUAL space
var angle_diff := wrapf(target_angle - visual_rot, -PI, PI)
var new_visual_rot: float
if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
    new_visual_rot = target_angle
elif angle_diff > 0:
    new_visual_rot = visual_rot + MODEL_ROTATION_SPEED * delta
else:
    new_visual_rot = visual_rot - MODEL_ROTATION_SPEED * delta

# Convert back to RAW rotation
_enemy_model.global_rotation = -new_visual_rot if _model_facing_left else new_visual_rot
```

**2. Fix `_force_model_to_face_direction()`:**
```gdscript
# When Y-scale is negative, visual angle = -raw_rotation
# So to achieve visual = target_angle, raw must be -target_angle
_enemy_model.global_rotation = -target_angle if target_facing_left else target_angle
```

**3. Added `_get_visual_rotation()` helper and updated FOV functions:**

All functions that read the enemy model's rotation to determine facing direction now use the visual rotation (via `_get_visual_rotation()`), ensuring consistent behavior throughout the codebase.

### Why This Works

The fix introduces the concept of two coordinate spaces:
- **Raw rotation**: The actual value stored in `_enemy_model.global_rotation`
- **Visual rotation**: What the player sees on screen

When Y-scale is negative: `visual_rotation = -raw_rotation`

All rotation math now happens in visual space, then converts back to raw space for storage. This ensures:
1. Smooth rotation takes the shortest visual path
2. Instant rotation sets the correct visual direction
3. FOV checks use the actual visual facing direction

---

## Summary of All Fix Attempts

| Fix # | What It Addressed | Why It Wasn't Enough |
|-------|-------------------|---------------------|
| 1 | Skip FOV in combat states | Addressed visibility detection, not rotation |
| 2 | Use `_get_target_position()` in combat | Rotation source was correct, but flip timing wrong |
| 3 | Add player fallback when memory empty | Edge case, not the main issue |
| 4 | Face player DIRECTLY in active combat | Rotation target was correct, flip still broken |
| 5 | Add rotation tracing | Diagnostic only |
| 6 | Flip based on TARGET angle | Fixed flip timing but no rotation compensation |
| 7 | Compensate rotation when flipping | Fixed flip compensation but smooth rotation still in wrong space |
| 8 | **Work in visual space for all rotation math** | **✅ ACTUAL ROOT CAUSE FIXED** |

The real issue was a coordinate space mismatch: rotation math was happening in "raw" space while Y-scale flip operates in "visual" space.

---

## References

- Issue #347: Smooth rotation for visual polish
- Issue #332: Corner checking during movement
- Issue #367: FLANKING/PURSUING wall-stuck detection
- Related concepts: [Game AI awareness systems](https://www.gamedeveloper.com/design/the-ai-of-halo-2)
- Common Godot issue: [180/-180 degree wrap-around in FOV calculations](https://godotforums.org/d/18193-enemy-not-rotating-properly-towards-the-player)
- Sprite flip best practices: Flip based on target direction, not current rotation
- [Godot GitHub Issues](https://github.com/godotengine/godot/issues) on scale/rotation interactions
- 2D transform mathematics: When Y-scale flips, visual angle = -rotation angle

