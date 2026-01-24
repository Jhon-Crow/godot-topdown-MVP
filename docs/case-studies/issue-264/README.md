# Case Study: Issue #264 - Fix Enemy AI Shooting

## Issue Description

**Title**: fix ai врагов (стрельбу) - Fix enemy AI (shooting)

**Problem Statement** (in Russian):
> враги стали реже стрелять и часто промахиваться после добавления моделей врагам.
> исправь.

**Translation**:
> Enemies started shooting less frequently and often missing after adding enemy models.
> Fix it.

## Timeline of Events

| Date | Event | PR/Issue |
|------|-------|----------|
| 2026-01-22 15:24 | Enemy models added | PR #221 |
| 2026-01-22 15:24 | Fixed enemy muzzle direction and model facing | PR #246 |
| 2026-01-22 15:45 | Fixed bullets to fly in barrel direction with AIM_TOLERANCE_DOT check | PR #255 |
| 2026-01-22 19:34 | Death animations added | PR #265 |
| 2026-01-22 | Issue #264 reported - enemies shoot less frequently and miss often | Issue #264 |

## Root Cause Analysis

### Technical Investigation

After thorough analysis of the enemy shooting code in `scripts/objects/enemy.gd`, the root cause has been identified:

#### The Core Problem: Strict Aim Tolerance

In PR #255, a new aim tolerance check was introduced to make enemy shooting more "realistic":

```gdscript
## Minimum dot product between weapon direction and target direction for shooting.
## Bullets only fire when weapon is aimed within this tolerance of the target.
## 0.95 ≈ cos(18°), meaning weapon must be within ~18° of target.
const AIM_TOLERANCE_DOT: float = 0.95
```

This check blocks shooting when `weapon_forward.dot(to_target) < 0.95`:

```gdscript
var aim_dot := weapon_forward.dot(to_target)
if aim_dot < AIM_TOLERANCE_DOT:
    if debug_logging:
        _log_debug("SHOOT BLOCKED: Not aimed at target. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
    return  # Shot blocked!
```

#### Why This Causes Problems

1. **Enemy Model Rotation is Gradual**: The enemy model rotates at `rotation_speed = 25 rad/sec`. This means a 180° turn takes ~126ms.

2. **Weapon Forward vs Target Direction Mismatch**: The weapon's forward direction comes from `_weapon_sprite.global_transform.x.normalized()`. Due to the complex parent-child transform hierarchy (CharacterBody2D → EnemyModel → WeaponMount → WeaponSprite), the weapon direction doesn't instantly match where the enemy is "aiming".

3. **Moving Player**: If the player is moving, the enemy continuously re-aims. The weapon direction is always "catching up" to the target direction, frequently failing the 18° tolerance check.

4. **Flip-Based Coordinate Inversion**: When enemies aim left (angle > 90° or < -90°), the model is flipped vertically (`scale.y = -enemy_model_scale`). The global_transform.x is calculated correctly, but the transform chain adds complexity that can cause small angular discrepancies.

### Mathematical Analysis

For `AIM_TOLERANCE_DOT = 0.95`:
- `cos(18°) ≈ 0.951`
- Only allows shooting when weapon is within ~18° of target

With rotation_speed = 25 rad/sec:
- At 60 FPS, rotation per frame = 25 / 60 ≈ 0.417 rad ≈ 23.9° per frame
- If the player moves, the target angle changes faster than the weapon can track in many scenarios

The angular velocity threshold for "can shoot while tracking":
- `v_threshold = bullet_speed * tan(tolerance_angle) / distance`
- At 300 pixels distance: ~250 pixels/sec player speed would cause constant shot blocking

### Impact

1. **Reduced Fire Rate**: Shots are blocked when weapon isn't precisely aimed, even though the shoot_timer has cooled down
2. **Perceived "Misses"**: Even when shots do fire (passing the 18° check), bullets go in barrel direction which may not hit a moving target
3. **AI Appears Sluggish**: Enemies seem to hesitate before shooting, appearing less aggressive

## Solution

### Option A: Lower Aim Tolerance (Recommended)

Reduce `AIM_TOLERANCE_DOT` from 0.95 to 0.85 (allows ~32° tolerance):

```gdscript
const AIM_TOLERANCE_DOT: float = 0.85  # cos(~32°) - more forgiving
```

This maintains realistic barrel-direction shooting while allowing enemies to fire more frequently.

### Option B: Increase Rotation Speed

Increase `rotation_speed` from 25 to 40+ rad/sec to make enemies aim faster:

```gdscript
@export var rotation_speed: float = 40.0
```

### Option C: Hybrid Approach with Lead Prediction Fix (Best)

1. Lower tolerance slightly to 0.90 (~26° tolerance)
2. Ensure lead prediction accounts for weapon rotation delay
3. Add "snap aim" when very close to tolerance threshold

## Implementation Plan

The recommended fix is **Option A with slight modification to 0.866** (cos(30°) ≈ 30° tolerance):

1. Change `AIM_TOLERANCE_DOT` from 0.95 to 0.866 (~30° tolerance)
2. This provides a good balance between realism (bullets fly in barrel direction) and gameplay (enemies shoot frequently enough to be threatening)

## Files Affected

- `scripts/objects/enemy.gd`: Line ~215, constant `AIM_TOLERANCE_DOT`

## Testing

After implementing the fix:
1. Verify enemies shoot more frequently in combat
2. Verify enemies still aim approximately at player
3. Verify bullets fly in barrel direction (visual consistency)
4. Verify gameplay balance - enemies should be threatening but not overwhelming

---

## Update: Additional Fix Required (2026-01-23)

### New Problem Identified

After implementing the AIM_TOLERANCE_DOT fix, user reported enemies still not shooting even when facing the player point-blank. Analysis of game logs showed:

1. "Player distracted - priority attack triggered" logged repeatedly
2. But NO actual gunshots occurred
3. Enemies in COMBAT state but not firing

### Root Cause: Model Rotation Not Updated Before Shooting

The priority attack code sets the enemy body's `rotation` to face the player, then immediately calls `_shoot()`. However:

1. `_shoot()` uses `_get_weapon_forward_direction()` to check if aimed correctly
2. This function returns `_weapon_sprite.global_transform.x.normalized()`
3. The weapon sprite's transform is based on **EnemyModel's rotation**
4. EnemyModel rotation is updated in `_update_enemy_model_rotation()` which runs BEFORE `_process_ai_state()`
5. When priority attack code sets `rotation`, the EnemyModel was already rotated in the previous step
6. Result: Weapon direction doesn't match the newly set body rotation → aim check fails

### Code Flow Problem

```
_physics_process():
  1. _update_enemy_model_rotation()  → Sets EnemyModel rotation based on player
  2. _process_ai_state()             → Priority attack sets body rotation & calls _shoot()
                                       BUT EnemyModel was set BEFORE this!
```

### Solution: Force Model Rotation Before Shooting

Added `_force_model_to_face_direction()` function and called it in priority attack code:

```gdscript
# Priority attack code (lines 1382-1386)
# Aim at player immediately - both body rotation and model rotation
rotation = direction_to_player.angle()
# CRITICAL: Force the model to face the player immediately so that
# _get_weapon_forward_direction() returns the correct aim direction.
_force_model_to_face_direction(direction_to_player)

_shoot()  # Now weapon direction matches → aim check passes!
```

### Files Modified

- `scripts/objects/enemy.gd`:
  - Added `_force_model_to_face_direction()` function
  - Updated distraction attack priority code (lines ~1379-1386)
  - Updated vulnerability attack priority code (lines ~1467-1474)
- `tests/unit/test_enemy.gd`: Added tests for model rotation synchronization

---

## Update: Wall Corner Visibility Fix (2026-01-23)

### New Problem Identified

After implementing the previous fixes, user reported:
1. "Enemies shoot better and more actively now" ✓ (aim tolerance and model sync fixes working)
2. **NEW**: "When player is right next to a wall in a passage, enemies don't see them even when very close"
3. "Sometimes they aim incorrectly (slightly wrong angle)"

### Game Log Analysis

From `game_log_20260123_221826.txt`:

```
[22:19:01] [ENEMY] [Enemy1] Player vulnerable (reloading) but cannot attack: close=true (dist=91), can_see=false
[22:19:01] [ENEMY] [Enemy2] Player vulnerable (reloading) but cannot attack: close=true (dist=84), can_see=false
[22:24:16] [ENEMY] [Enemy1] Player vulnerable (reloading) but cannot attack: close=true (dist=86), can_see=false
[22:24:16] [ENEMY] [Enemy3] Player vulnerable (reloading) but cannot attack: close=true (dist=172), can_see=false
```

The logs show enemies that are **very close** to the player (84-172 pixels) but `can_see=false`.

### Root Cause: Single-Point Raycast Visibility Check

The `_check_player_visibility()` function was using a **single raycast from the enemy center to the player's center**. When the player stands near a wall corner in a narrow passage:

```
                 Wall
                  │
    ┌─────────────┤
    │             │
    │   Enemy ────┼─ Raycast blocked by corner
    │      →      │
    │             │ Player (center blocked, but corners visible)
    │             ├──┐
    │             │▓▓│ ← Player body partly visible
    │             ├──┘
    └─────────────┤
                  │
```

The raycast hits the wall corner before reaching the player's center, even though parts of the player's body are clearly visible to the enemy.

### Solution: Multi-Point Visibility Check

The fix uses multiple raycasts to different points on the player's body (center + 4 diagonal corners):

```gdscript
# Before (single-point check - problematic):
var direction_to_player := (_player.global_position - global_position).normalized()
_raycast.target_position = direction_to_player * raycast_length
_raycast.force_raycast_update()
if _raycast.is_colliding():
    var collider := _raycast.get_collider()
    if collider == _player:
        _can_see_player = true

# After (multi-point check - robust):
var check_points := _get_player_check_points(_player.global_position)
for point in check_points:
    if _is_player_point_visible_to_enemy(point):
        _can_see_player = true  # Any visible point = player visible
```

This approach was already used in `_is_visible_from_player()` (checking if player can see enemy) and `_calculate_player_visibility_ratio()`. The fix simply applies the same pattern to `_check_player_visibility()`.

### Technical Details

**Player check points** (from `_get_player_check_points()`):
- Center: `player.global_position`
- 4 corners at diagonal offsets: `±10 * 0.707` pixels (player radius 14, diagonal ≈ 10)

**Visibility calculation**:
- If **any** point is visible → `_can_see_player = true`
- `_player_visibility_ratio` = (visible points) / (total points)

### Files Modified

- `scripts/objects/enemy.gd`:
  - Modified `_check_player_visibility()` to use multi-point visibility check
  - Uses existing `_get_player_check_points()` and `_is_player_point_visible_to_enemy()` functions

### Research Sources

The multi-point visibility approach is a well-known pattern for handling raycast visibility near corners:
- [Godot Documentation: Ray-casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [KCC Blog: Visibility with Ray-casting in Godot 3.0](https://kidscancode.org/blog/2018/03/godot3_visibility_raycasts/)
- [GitHub Issue: Raycasts clips through edges/corners](https://github.com/godotengine/godot/issues/84108)

### Testing

After implementing the fix:
1. Verify enemies can see players standing near wall corners
2. Verify enemies attack players in narrow passages
3. Verify no regression in normal visibility detection
