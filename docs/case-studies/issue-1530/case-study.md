# Case Study: Issue #1530 — Sniper Enemy Aim Inertia

## Issue Summary

**Title:** update враг снайпер (update enemy sniper)

**Requirements:**
1. The enemy sniper's crosshair/aim should have **inertia**.
2. If the player abruptly reverses direction, the sniper should **miss** — as if the sniper was tracking and trying to predict the player's momentum.
3. During normal movement (approximately one direction, no zigzags), the sniper should continue to hit as accurately as before.

---

## Root Cause Analysis

### Current Behaviour

The enemy sniper fires using `_calculate_lead_prediction()` in `enemy.gd` (lines 4020–4072). This method reads the player's *instantaneous* `CharacterBody2D.velocity` to compute a ballistic lead point:

```gdscript
var player_velocity := Vector2.ZERO
if _player is CharacterBody2D:
    player_velocity = _player.velocity
# ...
predicted_pos = player_pos + player_velocity * time_to_target
```

Because this uses raw velocity with no memory, a player direction reversal on frame N causes the sniper to re-compute the lead in the *opposite* direction on frame N+1 — perfectly compensating for the reversal. There is **no inertia**.

Separately, `EnemySniperComponent.process_combat()` calls `enemy._aim_at_player()` for the visual rotation (which gradually rotates toward the player's current position), but the *actual fire direction* is computed independently at the moment of shooting via `_calculate_lead_prediction()`.

### Why Inertia Is the Right Fix

A real sniper tracks a target's *perceived momentum*. When a target suddenly reverses, the sniper's aim — which was leaning forward in the old direction — takes time to correct. The bullet goes where the sniper *expected* the player to be, not where they are.

This is fundamentally a **velocity memory** problem: the sniper needs to remember the velocity history and respond to it with lag.

---

## Solution: Exponential Moving Average (EMA) of Player Velocity

### Chosen Approach

An **Exponential Moving Average (EMA)** is the canonical game-dev technique for adding temporal momentum to a signal:

```
smoothed_velocity = alpha * current_velocity + (1 - alpha) * smoothed_velocity
```

- `alpha` ∈ (0, 1): smoothing factor — lower = more inertia, slower correction.
- At 60 fps with `alpha = 0.12`, the EMA has a half-life of ~5 frames (~85 ms).
- On sudden reversal, the EMA still points in the old direction for ~300–500 ms before correcting — a meaningful miss window.
- During steady movement, the EMA converges to the true velocity within ~200 ms — imperceptible to the player.

### Alternative Approaches Considered

| Approach | Pros | Cons |
|---|---|---|
| **EMA (chosen)** | O(1), deterministic, tunable, geometrically motivated | None for this use case |
| Ring-buffer history | More accurate average | Higher memory, more state to manage |
| Random spread injection | Easy to add | Non-deterministic, feels arbitrary/cheap |
| Separate visual/fire aim | Visible cursor lag distinct from bullet | Bullet still hits during reversal |

The EMA is the simplest solution that satisfies all constraints.

### Tuning the `AIM_INERTIA_ALPHA` Constant

| Alpha | Half-life at 60 fps | Behaviour |
|---|---|---|
| 0.20 | ~3 frames (50 ms) | Light inertia; sniper corrects quickly after reversal |
| **0.12** | **~5 frames (85 ms)** | **Recommended — miss window ~400 ms, still hits steady movement** |
| 0.08 | ~8 frames (130 ms) | Heavy inertia; larger miss window, may feel unfair |
| 0.05 | ~13 frames (215 ms) | Very heavy; misses even moderate direction changes |

---

## Implementation Plan

### Files Modified

1. **`scripts/components/enemy_sniper_component.gd`** — Add EMA state variables, `AIM_INERTIA_ALPHA` constant, `_update_velocity_ema()` method, and cold-start / re-acquisition reset logic.
2. **`scripts/objects/enemy.gd`** — In `_calculate_lead_prediction()`: when `_sniper_component != null`, use `_sniper_component._smoothed_player_velocity` instead of raw `_player.velocity`.

### Non-sniper Impact

Zero. The EMA lives entirely inside `EnemySniperComponent`. The branch in `_calculate_lead_prediction()` is guarded by `_sniper_component != null`, which is only true for `WeaponType.SNIPER_RIFLE` enemies. All other enemy types continue using raw player velocity for lead prediction.

---

---

## Additional Fix: Rotation Speed Override (owner feedback on PR #1531)

After the initial implementation, the repository owner (Jhon-Crow) requested that the sniper's **weapon rotation speed** also be limited — not just the lead prediction velocity.

### Problem

The default `rotation_speed = 25.0 rad/s` (set in `enemy.gd`) caused the sniper's model to snap almost instantly to the player's position. Even with EMA inertia on the *prediction*, the sniper could still visually track rapid movement perfectly, making evasion feel impossible.

### Fix

In `_ready()` of `EnemySniperComponent`, the enemy's `rotation_speed` is now overridden:

```gdscript
const SNIPER_AIM_ROTATION_SPEED: float = 3.2  # rad/s — matches player's ASVK

func _ready() -> void:
    # ...
    if enemy != null and enemy.get("rotation_speed") != null:
        enemy.rotation_speed = SNIPER_AIM_ROTATION_SPEED
```

### Derivation of 3.2 rad/s

The value matches the player's own ASVK sniper rifle rotation speed:

- `SniperRifle.cs`: `NonAimingSensitivityFactor = 0.04f`
- `SniperRifleData.tres`: `WeaponData.Sensitivity = 8.0`
- `effectiveSensitivity = 8.0 * 0.04 = 0.32`
- `rotationSpeed = 0.32 * 10.0 = 3.2 rad/s`

### Combined Effect

Both mechanisms now work together:

| Mechanism | Effect |
|---|---|
| `rotation_speed = 3.2 rad/s` | Sniper can't visually track fast/erratic movement — aim physically lags behind |
| EMA (`alpha = 0.12`) | Lead prediction uses smoothed velocity — bullet lands where player *was* heading |

The sniper accurately hits stationary or slow-moving players (~1–2 seconds to lock on), but misses fast-moving or reversing players.

---

## Third Iteration: Laser-Driven Aim (owner feedback on PR #1531, 2026-03-26)

### Problem Report (game_log_20260326_114107.txt)

After the second fix, the owner reported that the sniper **still aimed too fast**. The root cause was
identified more precisely:

> "снайпер может поворачиваться с любой скоростью... вообще трассер должен совпадать с лазером снайпера."
> (the sniper can rotate at any speed... and the tracer must match the sniper's laser)

### Root Cause of "Still Too Fast"

The second fix overrode `enemy.rotation_speed = 3.2` and relied on `_aim_at_player()` to rotate
`enemy.rotation` (the CharacterBody2D's body angle) slowly. However:

1. **`_update_enemy_model_rotation()` uses `MODEL_ROTATION_SPEED = 3.0` (hardcoded constant)** for
   the visual model — this part was already slow, but the weapon sprites' effective pointing direction
   was computed via `_get_weapon_forward_direction()`.

2. **`_get_weapon_forward_direction()` bypassed all rotation limits** when `_can_see_player`:
   ```gdscript
   if _player and is_instance_valid(_player) and _can_see_player:
       return (_player.global_position - global_position).normalized()  # INSTANT
   ```
   This made the **bullet travel in the exact instant direction to the player**, regardless of how
   slowly the visual model was turning.

3. **Tracer/laser mismatch**: the tracer comes from `shoot_sniper_hitscan(direction, ...)` where
   `direction = _get_weapon_forward_direction()` (instant), while the laser sweeps slowly. They were
   different directions.

### Fix: Laser-Driven Weapon Aim

The laser sight already correctly interpolates toward the player at `LASER_ROTATION_SPEED = 3.0 rad/s`.
It is the single authoritative source of "where the sniper is currently aiming".

The fix makes **all three systems** (model rotation, bullet direction, tracer) derive from the laser:

#### 1. Public getter in `EnemySniperComponent`

```gdscript
func get_aim_direction() -> Vector2:
    return Vector2.from_angle(_laser_current_angle)
```

#### 2. `_get_weapon_forward_direction()` uses laser for snipers

```gdscript
if weapon_type == WeaponType.SNIPER_RIFLE and _sniper_component != null:
    return _sniper_component.get_aim_direction()
```

#### 3. `_get_bullet_spawn_position()` uses laser for snipers

```gdscript
if weapon_type == WeaponType.SNIPER_RIFLE and _sniper_component != null:
    weapon_forward = _sniper_component.get_aim_direction()
```

#### 4. `_update_enemy_model_rotation()` syncs model to laser for snipers

```gdscript
if weapon_type == WeaponType.SNIPER_RIFLE and _sniper_component != null:
    target_angle = _sniper_component.get_aim_direction().angle()
    _enemy_model.global_rotation = target_angle  # direct assignment, no double-interpolation
    return
```

By directly setting `_enemy_model.global_rotation` to the laser angle (skipping the
`MODEL_ROTATION_SPEED` lerp), we avoid a double interpolation while preserving the single
smooth sweep already provided by the laser's `lerp_angle`.

### Result

| System | Before (2nd fix) | After (3rd fix) |
|---|---|---|
| Visual model rotation | Slow (MODEL_ROTATION_SPEED=3.0) | Follows laser exactly |
| Bullet direction | Instant (bypass) | Follows laser (slow) |
| Tracer direction | Instant (bypass) | Follows laser (matches) |
| Laser direction | Slow (LASER_ROTATION_SPEED=3.0) | Unchanged |
| Model ↔ laser ↔ tracer | Mismatch | All three in sync |

---

## References

- [Predictive Aim Mathematics for AI Targeting — Game Developer](https://www.gamedeveloper.com/programming/predictive-aim-mathematics-for-ai-targeting)
- [A Probabilistic Shot Accuracy Model for FPS Enemy AI — System Void Games](http://systemvoidgames.com/2020/05/23/a-probabilistic-shooting-accuracy-model-for-fps-enemy-ai/)
- [Adaptive Shooting for Bots in FPS Games (arXiv:1806.05554)](https://arxiv.org/pdf/1806.05554)
- [Intuitive Explanation of Exponential Moving Average — Towards Data Science](https://towardsdatascience.com/intuitive-explanation-of-exponential-moving-average-2eb9693ea4dc/)
- [Shooting a Moving Target — Game Developer](https://www.gamedeveloper.com/programming/shooting-a-moving-target)
