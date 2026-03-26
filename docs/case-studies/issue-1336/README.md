# Case Study: Issue #1336 — Sniper Enemy Laser Sight

## Summary

**Issue:** Add a laser sight to the sniper enemy rifle that always indicates where the next shot will travel (must match the tracer direction).

**Follow-up feedback (2026-03-26):** The laser snaps abruptly from point to point; it must animate smoothly. Additionally, after computing the shot target, the laser must sweep to align with the shot direction — and the actual shot must only fire *once* the laser is already pointing in that direction.

---

## Data Sources

| File | Source | Description |
|------|--------|-------------|
| `game_log_20260326_083206.txt` | Owner upload in PR #1501 | Runtime log from a real play session on Windows (Godot 4.3-stable) |

---

## Timeline Reconstruction

### Initial implementation (PR #1501, branch `issue-1336-73ca6cfc52a7`)

The laser sight was added in `scripts/components/enemy_sniper_component.gd`:

- A `Line2D` node (`_laser_line`) is created in `_create_laser_sight()` and added to the current scene.
- Every frame `_update_laser_sight()` calls `_get_laser_direction()` which computes the **exact** final direction:
  - Blind-fire mode: `(_blind_fire_target - enemy.global_position).normalized()`
  - Direct-fire mode: `(player.global_position - enemy.global_position).normalized()`
- The Line2D endpoints are updated **immediately** every frame to the final direction.

### Problem 1: Abrupt jumps

Because `_get_laser_direction()` returns the instantaneous final direction and the laser endpoints are set directly without interpolation, the laser teleports to the new target each frame. When the blind-fire target changes (e.g., player moves around cover), the laser snaps across the screen.

**Root cause:** No interpolation/smoothing of the laser's displayed angle. The function sets `_laser_line.set_point_position()` directly from the computed direction without a lerp.

### Problem 2: Shot fires before laser reaches the target direction

The shooting logic in `process_combat` / `process_pursuing` fires immediately when `blind_fire_timer >= BLIND_FIRE_COOLDOWN`. The laser direction is a cosmetic-only overlay — it has no influence on when the shot is actually triggered.

The owner's requirement is:
> "after computing the shot target, the laser must move to coincide with the future tracer, and only when the laser is pointing in the same direction should the shot happen."

**Root cause:** The laser display angle (`_current_laser_angle`) is purely cosmetic and decoupled from the shooting decision. There is no "alignment check" before firing.

---

## Evidence from Game Log

From `game_log_20260326_083206.txt`:

```
[08:32:43] Sniper blind-fire at predicted position (263.683, 390.0027), ammo=4
[08:32:49] Sniper blind-fire at predicted position (1841.176, 1201.841), ammo=2
[08:32:54] Sniper blind-fire at predicted position (1380.968, 1023.198), ammo=1
[08:32:59] Sniper blind-fire at predicted position (1380.968, 1023.198), ammo=0
[08:33:09] Sniper blind-fire at predicted position (885.8273, 1256.021), ammo=3
```

Observations:
- Between shots the target position can change drastically (e.g., from `(263, 390)` to `(1841, 1201)` — a 1600px jump). Without smoothing the laser visually snaps across the entire level.
- Shots fire at hardcoded cooldown (`BLIND_FIRE_COOLDOWN = 5.0s`) regardless of laser angle.
- The game was running at Hard difficulty (`[DifficultyManager] Loaded difficulty: Hard (value: 2)`).

---

## Root Cause Analysis

| # | Root Cause | Effect | Fix |
|---|------------|--------|-----|
| RC-1 | Laser endpoints set directly from final direction, no interpolation | Laser snaps/teleports each frame when target changes | Maintain a smoothly-interpolated `_current_laser_angle` using `lerp_angle()`, update it every frame toward `_get_laser_direction().angle()` |
| RC-2 | Shooting decision (blind_fire_timer threshold) is independent of laser angle | Shot fires immediately when cooldown expires, before laser reaches target | Add a `_laser_aligned` flag / angle tolerance check; block the shot until `abs(angle_diff) < threshold` |

---

## Solution Design

### Smooth laser animation (RC-1 fix)

Maintain a persistent angle variable `_laser_current_angle: float` that is updated every frame:

```gdscript
var target_angle := _get_laser_direction().angle()
_laser_current_angle = lerp_angle(_laser_current_angle, target_angle, LASER_ROTATION_SPEED * delta)
var smooth_dir := Vector2.from_angle(_laser_current_angle)
```

`LASER_ROTATION_SPEED` controls how fast the laser sweeps (radians/second). A value of ~3.0 rad/s (≈172°/s) gives a visually telegraphed sweep.

### Shoot-lock behavior (RC-2 fix)

Before calling `fire_at_predicted_position()` / `_shoot()`, check whether the laser has reached the target:

```gdscript
var target_angle := _get_laser_direction().angle()
var angle_diff := abs(wrapf(_laser_current_angle - target_angle, -PI, PI))
var laser_aligned := angle_diff < LASER_ALIGNMENT_THRESHOLD  # e.g. 0.05 rad ≈ 3°
if laser_aligned:
    fire_at_predicted_position(blind_target)
```

The shot is only released once the visible laser beam is pointing in the correct direction, making the laser a genuine telegraph for the player.

---

## References

- [Godot docs — lerp_angle()](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html#class-globalscope-method-lerp-angle)
- [Godot forum — Rotate smoothly towards desired direction](https://forum.godotengine.org/t/rotate-smoothly-towards-desired-direction/53147)
- [Godot recipes — Smooth rotation](https://kidscancode.org/godot_recipes/4.x/3d/rotate_interpolate/index.html)
- PR #1501: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1501
- Issue #1336: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1336
