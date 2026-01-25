# Case Study: Issue #347 - Enemy Smooth Rotation

## Issue Summary

**Title:** fix поворот врагов (fix enemy rotation)
**Issue Link:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/347

**Problem:** Currently, enemies instantly change their viewing direction. They should rotate smoothly (quickly but with animation).

## Current Implementation Analysis

### Rotation Code Locations

The enemy rotation code is primarily located in `scripts/objects/enemy.gd`. The file contains several rotation mechanisms:

#### 1. Enemy Model Rotation (`_update_enemy_model_rotation()`)
**Location:** scripts/objects/enemy.gd:1026-1058

This function updates the visual model rotation and has two modes:
- **Smooth rotation:** Only used during IDLE state when scanning (idle_scan_targets)
- **Instant rotation:** Used for combat and movement scenarios

```gdscript
func _update_enemy_model_rotation() -> void:
    if not _enemy_model:
        return
    var target_angle: float
    var use_smooth_rotation := false
    if _player != null and _can_see_player:
        target_angle = (_player.global_position - global_position).normalized().angle()
    elif velocity.length_squared() > 1.0:
        target_angle = velocity.normalized().angle()
    elif _current_state == AIState.IDLE and _idle_scan_targets.size() > 0:
        target_angle = _idle_scan_targets[_idle_scan_target_index]
        use_smooth_rotation = true  # Only smooth rotation during idle scanning
    else:
        return
    if use_smooth_rotation:
        # Smooth rotation logic with MODEL_ROTATION_SPEED
        var delta := get_physics_process_delta_time()
        var current_rot := _enemy_model.global_rotation
        var angle_diff := wrapf(target_angle - current_rot, -PI, PI)
        if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
            _enemy_model.global_rotation = target_angle
        elif angle_diff > 0:
            _enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta
        else:
            _enemy_model.global_rotation = current_rot - MODEL_ROTATION_SPEED * delta
    else:
        _enemy_model.global_rotation = target_angle  # INSTANT ROTATION
```

**Constants:**
- `MODEL_ROTATION_SPEED: float = 3.0` (3.0 rad/s = 172 deg/s)
- `rotation_speed: float = 25.0` (exported variable for body rotation)

#### 2. Body Rotation (Instant Assignment)

Multiple locations in the code directly assign rotation instantly:

**Priority Attack Scenarios:**
- Line 1257: `rotation = direction_to_player.angle()` (distracted player attack)
- Line 1308: `rotation = direction_to_player.angle()` (priority attack with clear shot)

**Combat State:**
- Line 1487: `rotation = direction_to_player.angle()` (sidestepping in combat)
- Line 1539: `rotation = direction_to_player.angle()` (seeking clear shot)
- Line 1592: `rotation = direction_to_player.angle()` (approaching player)

**Patrol State:**
- Line 4084: `rotation = direction.angle()` (patrol movement)

**Retreat State:**
- Line 2033: `rotation = target_angle` (interpolated retreat rotation)

**Search State:**
- Line 4939: `rotation = direction.angle()` (search pattern movement)

#### 3. Gradual Rotation Function (`_aim_at_player()`)
**Location:** scripts/objects/enemy.gd:3836-3856

This function implements smooth rotation but is not widely used:

```gdscript
func _aim_at_player() -> void:
    if _player == null:
        return
    var direction := (_player.global_position - global_position).normalized()
    var target_angle := direction.angle()

    # Calculate the shortest rotation direction
    var angle_diff := wrapf(target_angle - rotation, -PI, PI)

    # Get the delta time from the current physics process
    var delta := get_physics_process_delta_time()

    # Apply gradual rotation based on rotation_speed
    if abs(angle_diff) <= rotation_speed * delta:
        # Close enough to snap to target
        rotation = target_angle
    elif angle_diff > 0:
        rotation += rotation_speed * delta
    else:
        rotation -= rotation_speed * delta
```

This function is only called in a few places (line 1596, etc.) but most combat scenarios use instant rotation.

### Root Cause

The issue occurs because:
1. **Combat scenarios use instant rotation:** Most combat states directly assign `rotation = angle` instead of smoothly interpolating
2. **Model rotation is instant in combat:** `_update_enemy_model_rotation()` only applies smooth rotation during IDLE scanning, but instantly rotates during combat and movement
3. **Inconsistent usage:** The `_aim_at_player()` smooth rotation function exists but is rarely used

### Visual Impact

When enemies detect the player or change their attack direction, they instantly snap to the new angle, which looks unnatural and robotic. This is especially noticeable when:
- Enemies switch from idle/patrol to combat
- Enemies track the player during combat
- Enemies change direction while moving

## Research: Godot Smooth Rotation Best Practices

### Key Techniques

Based on Godot community best practices and official documentation:

#### 1. Using `wrapf` for Angle Wrapping
The most important aspect is properly handling angle wrapping to ensure rotation takes the shortest path:
```gdscript
var angle_diff := wrapf(target_angle - current_angle, -PI, PI)
```

#### 2. Constant Speed Rotation
For turret-style rotation at constant speed:
```gdscript
rotation += clamp(rotation_speed * delta, 0, abs(theta)) * sign(theta)
```
This ensures the rotation doesn't overshoot the target.

#### 3. Interpolation with `lerp_angle`
For smoother, acceleration-based rotation:
```gdscript
rotation = lerp_angle(rotation, target_angle, speed * delta)
```
Note: `lerp_angle` automatically handles angle wrapping.

#### 4. Transform-Based Rotation (3D)
For 3D scenarios, using transform interpolation:
```gdscript
transform = transform.interpolate_with(target_transform, speed * delta)
```

### Recommended Approach for 2D Top-Down Enemies

For this use case, the best approach is **constant speed rotation with proper angle wrapping**, which:
- Provides predictable, smooth animation
- Maintains consistent rotation speed
- Looks professional and polished
- Allows enemies to track targets realistically

The existing `_aim_at_player()` function already implements this correctly and should be used consistently.

## Proposed Solutions

### Solution 1: Extend `_update_enemy_model_rotation()` for All States (Recommended)

**Approach:** Modify `_update_enemy_model_rotation()` to always use smooth rotation, not just during idle scanning.

**Advantages:**
- Minimal code changes
- Centralized rotation logic
- Uses existing MODEL_ROTATION_SPEED constant
- Automatically handles vertical flipping

**Implementation:**
```gdscript
func _update_enemy_model_rotation() -> void:
    if not _enemy_model:
        return
    var target_angle: float
    var has_target := false

    if _player != null and _can_see_player:
        target_angle = (_player.global_position - global_position).normalized().angle()
        has_target = true
    elif velocity.length_squared() > 1.0:
        target_angle = velocity.normalized().angle()
        has_target = true
    elif _current_state == AIState.IDLE and _idle_scan_targets.size() > 0:
        target_angle = _idle_scan_targets[_idle_scan_target_index]
        has_target = true

    if not has_target:
        return

    # Always use smooth rotation
    var delta := get_physics_process_delta_time()
    var current_rot := _enemy_model.global_rotation
    var angle_diff := wrapf(target_angle - current_rot, -PI, PI)

    if abs(angle_diff) <= MODEL_ROTATION_SPEED * delta:
        _enemy_model.global_rotation = target_angle
    elif angle_diff > 0:
        _enemy_model.global_rotation = current_rot + MODEL_ROTATION_SPEED * delta
    else:
        _enemy_model.global_rotation = current_rot - MODEL_ROTATION_SPEED * delta

    # Update facing direction and scale
    var aiming_left := absf(_enemy_model.global_rotation) > PI / 2
    _model_facing_left = aiming_left
    if aiming_left:
        _enemy_model.scale = Vector2(enemy_model_scale, -enemy_model_scale)
    else:
        _enemy_model.scale = Vector2(enemy_model_scale, enemy_model_scale)
```

### Solution 2: Replace Instant Body Rotation with Smooth Rotation

**Approach:** Replace all `rotation = angle` assignments with calls to `_aim_at_player()` or a new smooth rotation function.

**Advantages:**
- More control over rotation speed
- Can have different speeds for different scenarios

**Disadvantages:**
- Requires changes in many locations
- More complex to maintain
- May need to create variants for non-player targets

### Solution 3: Use Godot's Tween System

**Approach:** Use Tween nodes to animate rotation changes.

**Advantages:**
- Very smooth animations
- Built-in easing functions
- Can chain multiple animations

**Disadvantages:**
- More complex setup
- Potential performance overhead with many enemies
- Harder to cancel/interrupt mid-rotation
- Overkill for this use case

### Solution 4: Hybrid Approach (Recommended Alternative)

**Approach:**
1. Keep smooth model rotation for visual appearance
2. Allow instant body rotation for game logic (shooting, movement)
3. Increase MODEL_ROTATION_SPEED for faster response

**Advantages:**
- Separates visual from logical concerns
- Maintains existing shooting accuracy
- Simple implementation

**Implementation:**
- Modify `_update_enemy_model_rotation()` to always smooth rotate (as in Solution 1)
- Optionally increase `MODEL_ROTATION_SPEED` from 3.0 to 5.0-8.0 rad/s for faster visual response
- Keep instant body rotation for game logic

## Existing Godot Components/Libraries

### Built-in Solutions
1. **Tween Node** - Built into Godot, provides smooth property interpolation
2. **AnimationPlayer** - Can animate rotation with custom curves
3. **lerp_angle()** - Built-in function for angle interpolation

### Community Solutions
1. **Smooth Look At** - Various implementations on Godot Asset Library
2. **AI Behavior Trees** - May include rotation smoothing (e.g., Beehave plugin)

### Recommendation
Use built-in Godot functions (`wrapf`, constant speed rotation) as they're simple, performant, and well-suited for this use case. No external libraries needed.

## Implementation Plan

### Recommended Implementation: Solution 1 (Smooth Model Rotation for All States)

**Step 1:** Modify `_update_enemy_model_rotation()` function
- Remove the `use_smooth_rotation` flag
- Apply smooth rotation logic to all rotation scenarios
- Keep existing angle calculation logic

**Step 2:** Remove instant model rotation assignments
- Line 1052: Remove the `else: _enemy_model.global_rotation = target_angle` branch
- Update `_force_model_to_face_direction()` to use smooth rotation or keep instant for priority attacks

**Step 3:** Consider adjusting rotation speed
- Test current MODEL_ROTATION_SPEED (3.0 rad/s = 172 deg/s)
- If too slow, increase to 5.0-8.0 rad/s
- Add as exported variable if needed for per-enemy customization

**Step 4:** Keep body rotation instant
- Body rotation is used for game logic (FOV, shooting direction)
- Visual rotation (model) is what the player sees
- This separation is actually beneficial

**Step 5:** Test scenarios
- Idle to combat transition
- Enemy tracking player during combat
- Priority attacks
- Patrol direction changes
- Search pattern rotation

### Priority Attack Consideration

For priority attacks (lines 1257, 1308), we may want to keep instant rotation or use a faster rotation speed to ensure enemies can react quickly to distracted players. This requires testing to balance visual smoothness with gameplay responsiveness.

## Expected Results

After implementation:
- Enemies will smoothly rotate toward targets instead of snapping instantly
- Visual appearance will be more polished and professional
- Combat behavior will remain accurate (body rotation still instant for logic)
- Rotation speed of 3.0 rad/s (172 deg/s) should feel quick but smooth
- May need slight adjustment based on gameplay feel

## Testing Strategy

1. **Visual Testing:**
   - Observe enemy rotation during idle scanning
   - Watch enemy rotation when detecting player
   - Check rotation during combat movement
   - Verify priority attack rotation

2. **Gameplay Testing:**
   - Ensure enemies can still aim accurately
   - Verify shooting timing isn't delayed
   - Check FOV detection works correctly
   - Test flanking and cover behaviors

3. **Performance Testing:**
   - Monitor FPS with multiple enemies
   - Check for rotation jitter or stuttering
   - Verify no race conditions in rotation updates

## References

### Online Resources
- [Smooth rotation :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/3d/rotate_interpolate/index.html)
- [How do i make things rotate smoothly? - Godot Forum](https://forum.godotengine.org/t/how-do-i-make-things-rotate-smoothly/57390)
- [Smoothly rotate node towards an angle - Godot Forums](https://godotforums.org/d/35243-smoothly-rotate-node-towards-an-angle)
- [Coding enemy AI in Godot Engine | Gravity Ace](https://gravityace.com/devlog/drone-ai/)
- [Make a smoother rotation to a point (2D) - Godot Forum](https://godotengine.org/qa/46816/make-a-smoother-rotation-to-a-point-2d)

### Related Issues
- Issue #254: Aim-before-shoot behavior (rotation_speed: 25.0)
- Issue #264: Enemy aim tolerance and weapon direction
- Issue #332: FOV visualization and corner checking
- Issue #66: Field of view angle implementation

## Follow-up: Corner Check Rotation Issue (2026-01-25)

### Problem Report

After the initial fix was implemented, the user reported that "enemies still turn jerkily when there's no direct contact with the player." A game log was provided: `game_log_20260125_030937.txt`.

### Log Analysis

Examining the log revealed patterns of sudden angle changes:

```
[03:09:52] [ENEMY] [Enemy1] PURSUING corner check: angle -129.2°
[03:09:53] [ENEMY] [Enemy1] PURSUING corner check: angle -92.7°     # ~36° jump
[03:09:53] [ENEMY] [Enemy1] PURSUING corner check: angle 122.7°    # ~215° INSTANT JUMP!
[03:09:55] [ENEMY] [Enemy1] PURSUING corner check: angle -168.3°
[03:09:55] [ENEMY] [Enemy1] PURSUING corner check: angle 11.7°     # ~180° INSTANT JUMP!
```

These large angle jumps indicated the problem was specifically with **corner checking**, not the main rotation system.

### Root Cause Identified

The corner checking system (Issue #332) uses `_force_model_to_face_direction()` which bypasses smooth rotation:

**File:** `scripts/objects/enemy.gd`
- `_detect_perpendicular_opening()` (line ~4098): Calls `_force_model_to_face_direction(perp_dir)` - INSTANT
- `_process_corner_check()` (line ~4106): Calls `_force_model_to_face_direction(Vector2.from_angle(_corner_check_angle))` - INSTANT

The initial fix made `_update_enemy_model_rotation()` smooth, but corner checking used a separate code path (`_force_model_to_face_direction()`) that still rotated instantly.

### Timeline of Events

1. **Initial Issue #347:** Enemies rotate instantly when changing direction
2. **First Fix (0ec1f01):** Made `_update_enemy_model_rotation()` always use smooth rotation
3. **Line Count Fix (857fd3b):** Reduced enemy.gd from 5005 to 4999 lines
4. **User Report (2026-01-25):** Jerky rotation still observed during corner checks
5. **Root Cause Analysis:** Corner check system bypassed smooth rotation
6. **Second Fix:** Integrated corner check into `_update_enemy_model_rotation()` priority system

### Solution Implementation

**Changes to `_update_enemy_model_rotation()`:**
- Added corner check angle as priority 2 (after player visibility, before velocity)
- When `_corner_check_timer > 0`, uses `_corner_check_angle` as target

**Changes to corner check functions:**
- Removed `_force_model_to_face_direction()` calls
- Corner angle is now stored and the smooth rotation system handles the interpolation

**Priority Order for Rotation Targets:**
1. Player (when visible) - highest priority
2. Corner check angle (when actively checking) - **NEW**
3. Movement velocity direction
4. Idle scan targets (for IDLE state)

### Code Changes Summary

```diff
 func _update_enemy_model_rotation() -> void:
     # ... existing code ...
     if _player != null and _can_see_player:
         target_angle = (player_pos - global_position).normalized().angle()
         has_target = true
+    elif _corner_check_timer > 0:
+        target_angle = _corner_check_angle
+        has_target = true
     elif velocity.length_squared() > 1.0:
         target_angle = velocity.normalized().angle()

 func _detect_perpendicular_opening(move_dir: Vector2) -> bool:
     # ... raycast logic ...
     if space_state.intersect_ray(query).is_empty():
         _corner_check_angle = perp_dir.angle()
-        _force_model_to_face_direction(perp_dir)  # REMOVED
         return true

 func _process_corner_check(delta: float, move_dir: Vector2, state_name: String) -> void:
     if _corner_check_timer > 0:
         _corner_check_timer -= delta
-        _force_model_to_face_direction(Vector2.from_angle(_corner_check_angle))  # REMOVED
```

### Lessons Learned

1. **Test all rotation paths:** Multiple code paths can affect rotation; need to test all scenarios
2. **Log analysis is valuable:** The corner check log messages helped identify the exact source
3. **Priority-based systems:** Centralized rotation with priority ordering is cleaner than multiple force functions
4. **Preserve `_force_model_to_face_direction()` for priority attacks:** Still needed for instant aiming before shooting

## Conclusion

The issue is well-understood and has a straightforward solution. The codebase already contains the necessary smooth rotation logic in `_update_enemy_model_rotation()`, but it's currently only applied during idle scanning. By removing the conditional and applying smooth rotation in all scenarios, we can achieve the desired smooth rotation effect while maintaining game logic accuracy.

The recommended approach (Solution 1/4 Hybrid) provides the best balance of visual quality, code simplicity, and gameplay responsiveness.

**Update (2026-01-25):** Corner checking was identified as a secondary source of instant rotation. The fix integrates corner check rotation into the smooth rotation system by adding it as a priority target in `_update_enemy_model_rotation()`.
