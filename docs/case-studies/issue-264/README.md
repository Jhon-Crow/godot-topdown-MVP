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
