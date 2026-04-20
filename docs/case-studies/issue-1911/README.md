# Case Study: Issue #1911 — Drone Camera Jerk on Control Switch

## Overview

**Issue:** Camera jerks when switching control between player and drone grenade.  
**Reporter:** Jhon-Crow  
**PR:** #1912  
**Status:** Under investigation / fix iteration

---

## Timeline of Events

### Initial Report (Issue #1911)

The user reported two symptoms:
1. Camera jerks when switching from player → drone (at throw end / THROWING→PILOTING transition)
2. Camera jerks when switching from drone → player (at explosion / EXPLODED→player transition)

### First Fix Attempt (commit `3b1ec7cc`)

The first fix preserved the camera's `global_position` before reparenting and restored it after reparenting. The idea: keep the camera at the same world location and let `position_smoothing` animate it toward the new parent.

**Code:**
```gdscript
var cam_global_pos := _player_camera.global_position
old_parent.remove_child(_player_camera)
add_child(_player_camera)
_player_camera.global_position = cam_global_pos  # ← preserve world pos
```

**Why this was wrong:** Setting `global_position` after reparenting sets a large local `position` offset (= `cam_global_pos - new_parent.global_position`). Camera2D's smoothing target is `parent.global_position + camera.position`, which evaluates to `cam_global_pos`. This means:
- The camera's **node** global position = `cam_global_pos` (correct for 1 frame)
- But as the drone moves, `camera.global_position = drone_pos + fixed_offset` — a rigid world-space offset from the drone
- The viewport tracks this, staying permanently `cam_global_pos - drone_spawn_pos` pixels offset from the drone
- Result: **camera moves incorrectly in pilot mode** (offset view, not centered on drone)

### User Feedback on First Fix

From PR comment by Jhon-Crow (2026-04-20T10:49:27Z):
> "камера теперь двигается не правильно в режиме пилота. так же камера всё ещё дёргается в момент окончания броска."
> (Camera now moves incorrectly in pilot mode. Also the camera still jerks at end of throw.)

Attached: `game_log_20260420_134731.txt`

---

## Root Cause Analysis

### How Camera2D Position Smoothing Works in Godot 4

`Camera2D` with `position_smoothing_enabled = true` interpolates the **viewport** toward the camera node's `global_position`. The camera node's global position is: `parent.global_position + camera.position` (local offset).

When `position_smoothing_speed = 5.0`, the viewport center moves ~63% of the way to the target each second.

### Bug: Non-Zero Local Position After Reparent

After reparenting camera to drone and setting `global_position = old_world_pos`:

```
camera.position = old_world_pos - drone.global_position   # e.g. (−800, +300)
camera.global_position = drone.global_position + camera.position = old_world_pos
```

The camera node is at the old player position. The smoothing target = `old_world_pos`. No smoothing occurs initially. But as the **drone moves**:

```
drone moves by (+10, 0) each frame
camera.global_position = (drone_pos + Δ) + fixed_offset = old_world_pos + Δ
```

The camera moves with the drone but at a permanent world-space offset. The viewport shows a location `offset` pixels away from the drone — not centered on it.

**This is why the camera moved incorrectly in pilot mode.**

### Bug: Throw-End Jerk

During THROWING phase, the camera remains parented to the player (viewport shows player area). When PILOTING starts (`_start_piloting` → `_attach_camera_to_drone`):

- With first fix: `global_position = cam_global_pos` = player position ≈ camera's current position
  - Sets `camera.position = player_pos - drone_pos` = large negative offset (drone just arrived at aim point, which is far from player)
  - Camera global pos = `drone_pos + (player_pos - drone_pos)` = `player_pos`
  - Viewport smooths toward `player_pos`... but viewport is ALREADY at `player_pos` → no visible movement
  - BUT: camera `position` is a large offset → broken pilot mode as described above
  - The jerk may come from position_smoothing jerking as offset resolves

### Correct Fix

The Camera2D should always have `position = Vector2.ZERO` when parented to a moving node, so it properly centers on that node. Godot's built-in `position_smoothing` then handles smooth viewport animation automatically:

```gdscript
# Reparent camera to drone
old_parent.remove_child(_player_camera)
add_child(_player_camera)
_player_camera.position = Vector2.ZERO   # center on drone
_player_camera.make_current()
```

Result:
- Camera node global_position = `drone.global_position` (= aim point, far from player)
- Viewport is currently showing player's area
- `position_smoothing` animates viewport from player's area → drone's position: **smooth pan**
- As drone moves, camera.global_pos = drone.global_pos (no offset): **correct centering**

Same logic applies on detach (explosion → player).

---

## Sequence of Events (from game_log_20260420_134731.txt)

```
[13:47:40] DroneGrenade: Player found: Player, Camera: Camera2D
[13:47:40] DroneGrenade: THROWING phase started toward (335.9328, 1097.945)
[13:47:40] DroneGrenade: Drone launched at (203.0851, 1027.964)
[13:47:40] DroneGrenade: Throw target reached — switching to PILOTING
[13:47:40] DroneGrenade: Camera attached to drone          ← BUG: wrong position set here
[13:47:40] DroneGrenade: Player control disabled
[13:47:40] DroneGrenade: PILOTING phase started at (319.2086, 1089.135)
```

Key observation: throw target reached almost immediately (same timestamp as launch), meaning the drone covered a short distance. Camera was still at ~(150, 1000) while drone was at (319, 1089). The first fix set `camera.position = (150,1000) - (319,1089) = (-169, -89)` — a small-ish offset in this case, but still incorrect.

In the second tutorial throw:
```
[13:47:47] THROWING phase started toward (1040.033, 146.1519)
[13:47:47] Drone launched at (223.1104, 375.1772)
[13:47:47] Throw target reached — switching to PILOTING
[13:47:47] Camera attached to drone
[13:47:47] PILOTING phase started at (1017.002, 152.6086)
```

Player at ~(150, 360), drone at (1017, 152). Camera offset = `(150,360) - (1017,152) = (-867, +208)`. This large offset causes the camera to orbit the drone at nearly 900px distance — clearly broken pilot mode.

---

## Fix Applied (Second Iteration)

File: `scripts/projectiles/drone_grenade.gd`

**`_attach_camera_to_drone()`:** Remove the `global_position` manipulation. Set `position = Vector2.ZERO` to center camera on drone. Let `position_smoothing` animate the viewport smoothly.

**`_detach_camera_from_drone()`:** Same — set `position = Vector2.ZERO` on player, let smoothing handle the return pan.

---

## Possible Future Improvements

1. **During THROWING phase:** Optionally keep camera on player (current behavior) or smoothly track the drone mid-flight. Currently camera attaches only when PILOTING starts, which is correct UX.
2. **Smoothing speed tuning:** `position_smoothing_speed = 5.0` may feel too slow for long throws. Could dynamically adjust speed based on distance.
3. **Camera limits:** Level scripts set Camera2D limits. After reparenting to drone, limits still apply (good). After returning to player, same limits. No issue here.
