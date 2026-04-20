# Case Study: Issue #1911 — Drone Camera Jerk on Control Switch

## Overview

**Issue:** Camera jerks when switching control between player and drone grenade.
**Reporter:** Jhon-Crow
**PR:** #1912
**Status:** Under investigation / fix iteration (3rd iteration)

User's latest report (2026-04-20T11:38:17Z):
> "в момент перехода в режим управления дроном камера дёргается как при перезапуске уровня."
> "At the moment of transition to drone control mode, the camera jerks as if the level is restarting."

Attached log: `logs/game_log_20260420_143657.txt`

---

## Timeline of Iterations

### Iteration 1 — preserve `global_position` after reparent (commit `3b1ec7cc`)

```gdscript
var cam_global_pos := _player_camera.global_position
old_parent.remove_child(_player_camera)
add_child(_player_camera)
_player_camera.global_position = cam_global_pos   # preserve world pos
```

**Problem:** Setting `global_position` after reparenting created a large local `position` offset equal to `cam_world_pos - drone_world_pos`. As the drone moved, `camera.global_position = drone_pos + fixed_offset` — the camera tracked the drone at a permanent world-space offset. User reported "camera moves incorrectly in pilot mode" plus "still jerks at throw end".

### Iteration 2 — zero local position after reparent (commit `8b1b76fe`)

```gdscript
old_parent.remove_child(_player_camera)
add_child(_player_camera)
_player_camera.position = Vector2.ZERO
_player_camera.make_current()
```

Pilot-mode positioning is correct now (camera centers on drone). **But the jerk remains**: user reports a hard cut at the moment of switching to pilot mode, described as "like the level restarts".

---

## Root Cause (Iteration 3 Analysis)

### Observation from the new log

From `logs/game_log_20260420_143657.txt`, representative throw:

```
[14:37:06] THROWING phase started toward (830.8714, 261.6926)
[14:37:06] Drone launched at (209.3842, 351.4258)
[14:37:07] Throw target reached — switching to PILOTING
[14:37:07] Camera attached to drone
[14:37:07] PILOTING phase started at (803.144, 265.696)
```

Player at ~(209, 351). Drone at (803, 266). Expected behavior: `position_smoothing_speed = 5.0` should pan the viewport smoothly from player area to drone area over ~0.5–1.0 seconds. **Observed behavior: an instantaneous hard cut** — the hallmark of a smoothing-state reset.

### The real bug: Camera2D smoothing state resets on reparent

In Godot 4, `Camera2D` keeps an internal `smoothed_camera_pos` value that is updated each (physics) frame, lerping toward the camera node's `global_position`. When the camera is **reparented**, Godot fires `NOTIFICATION_TRANSFORM_CHANGED` / `NOTIFICATION_PARENTED`, and the internal smoothing state is re-synced to the new parent's transform. The net visual effect is a hard cut to the new target — exactly matching the "like level restart" description the user reported.

This is a documented Godot community issue:

- [godotforums.org — Camera2D jumps when player character reparented](https://godotforums.org/d/27618-camera2d-jumps-when-player-character-reparented-to-new-node): "Camera2D resets when the node hierarchy changes, causing sudden position jumps despite smoothing being enabled."
- [forum.godotengine.org — How to prevent discrete camera jumps when re-parenting](https://forum.godotengine.org/t/how-to-prevent-discrete-camera-jumps-when-re-parenting-a-node/26582): official recommendation is to **not reparent the Camera2D**; instead use a controller/rig that tracks the target without changing hierarchy.
- [Godot Issue #50807 — `reset_smoothing()` does not work as described](https://github.com/godotengine/godot/issues/50807): internal order-of-operations bug makes smoothing-state reset visually inconsistent.
- [Godot Issue #68394 — Camera2D intermittent jumps with smoothing](https://github.com/godotengine/godot/issues/68394): related reports.

### Why the THROWING→PILOTING transition produces the hardest visible jump

During THROWING phase, the camera stays parented to the player — viewport smoothly follows the player. When `_start_piloting()` fires, two things happen on the **same frame**:

1. `_attach_camera_to_drone()` removes the camera from the player and adds it as a child of the drone (which is at the aim point, often hundreds of pixels away).
2. The Camera2D's internal smoothing state gets reset because the parent transform changed from `(player_pos)` to `(drone_pos)`.

The viewport snaps to the drone's position rather than smoothly panning — visually indistinguishable from a scene reload.

### Why iteration 1 (`global_position` preservation) felt partially smoother

In iteration 1, the camera's node-level `global_position` was kept at the old player location for 1 frame before drone motion pulled it along. This briefly preserved the smoothing target at the old spot, reducing the visible jump. BUT it broke pilot-mode tracking (permanent world offset). Iteration 2 traded one bug for the other.

---

## The Correct Fix: avoid reparenting entirely

Use **`top_level = true`** on the Camera2D while in pilot mode. This decouples the camera's transform from its parent (the Player) without changing the node hierarchy. We then write `camera.global_position = drone.global_position` each physics frame. Godot's built-in `position_smoothing` continues to operate on its internal state uninterrupted — producing the smooth pan the user expects.

When the drone explodes (or is otherwise dismissed):
- Set `camera.top_level = false` and `camera.position = Vector2.ZERO`.
- The camera re-attaches to the player's transform. Its `global_position` now resolves to `player.global_position`, and `position_smoothing` smoothly pans the viewport from the drone's last location back to the player — no reparenting, no smoothing reset.

### Why this works

- `top_level = true` turns a child node into a world-space node without changing its place in the scene tree (see [Godot docs — CanvasItem.top_level](https://docs.godotengine.org/en/4.3/classes/class_canvasitem.html#class-canvasitem-property-top-level)).
- No `remove_child` / `add_child` fires, so `NOTIFICATION_PARENTED` never triggers on the Camera2D.
- `position_smoothing`'s internal `smoothed_camera_pos` is never invalidated by hierarchy changes; only the camera's `global_position` changes, which is exactly what smoothing is designed to handle.
- The community's established solution ("stable camera rig with a tracked target") is functionally equivalent to this, but `top_level` is a one-line in-place change that requires no scene restructuring.

---

## Timeline of Events (new log `game_log_20260420_143657.txt`)

Session starts at `14:36:57`. Player is on `LabyrinthLevel` (camera limits 48..1968 × 48..1128).

| Time | Event |
|------|-------|
| 14:36:58 | Camera2D limits set for labyrinth level |
| 14:37:00 | Drone grenade ready; pin pulled |
| 14:37:01 | 1st throw — target `(354, 547)`, launched at `(174, 945)` |
| 14:37:02 | Throw target reached → `Camera attached to drone` → PILOTING at `(343, 570)` |
| 14:37:06 | 2nd throw — target `(830, 261)`, launched at `(209, 351)` |
| 14:37:07 | Throw reached → PILOTING at `(803, 265)` |
| 14:37:14 | 3rd throw — target `(965, 214)`, launched at `(209, 349)` |
| 14:37:15 | PILOTING at `(945, 218)` |
| 14:37:23 | 4th throw — target `(1159, 151)`, launched at `(208, 347)` |
| 14:37:25 | PILOTING at `(1135, 156)` |
| 14:37:29 | 5th throw — target `(1343, 161)`, launched at `(209, 350)` |
| 14:37:31 | PILOTING at `(1317, 165)` |

Every PILOTING transition involves a camera move of 400–1100 px. With `position_smoothing_speed = 5.0` these should pan smoothly over ~0.5–1.0 s. They do not — they hard-cut. The user perceives "as if level restarts".

---

## Fix Applied (Iteration 3)

File: `scripts/projectiles/drone_grenade.gd`

### Changes

- Remove the `remove_child` + `add_child` reparenting in both `_attach_camera_to_drone()` and `_detach_camera_from_drone()`.
- Keep the Camera2D a child of the Player. Flip `top_level` to decouple/recouple its transform.
- In `_physics_process`, while the drone owns the camera, write `_player_camera.global_position = global_position`.
- On detach, set `top_level = false` and `position = Vector2.ZERO` so the camera reverts to a normal child of the player.

### Pseudocode

```gdscript
func _attach_camera_to_drone() -> void:
    if _player_camera == null:
        return
    _player_camera.top_level = true               # decouple from player transform
    _player_camera.global_position = global_position
    _player_camera.make_current()
    _camera_owned_by_drone = true

func _detach_camera_from_drone() -> void:
    if _player_camera == null or not is_instance_valid(_player_camera):
        return
    _camera_owned_by_drone = false
    _player_camera.top_level = false              # re-attach to player transform
    _player_camera.position = Vector2.ZERO        # local offset back to center
    _player_camera.make_current()

func _physics_process(delta):
    ...
    if _camera_owned_by_drone and _player_camera:
        _player_camera.global_position = global_position
```

### Why this matches the user's expectation

- THROWING→PILOTING: camera's `global_position` changes from player position to drone position in one frame. `position_smoothing` interpolates the viewport smoothly from player area to drone area. No jerk.
- PILOTING: every physics frame the camera's global_position equals drone's global_position. `position_smoothing` keeps the viewport slightly trailing but centered on the drone (same feel as normal player tracking). No world-space offset bug from iteration 1.
- Explosion: `top_level = false` + `position = Vector2.ZERO` puts the camera back under player's transform. Its new `global_position = player.global_position`. `position_smoothing` pans back smoothly from the drone's last location.

---

## Verification Checklist

1. Throw drone from player position to a far aim point (≥ 400 px).
2. Observe: camera smoothly pans from player to drone over ~0.5–1.0 s (no snap).
3. Pilot the drone with WASD — camera stays centered on drone, no world-offset drift.
4. Let the drone explode — camera smoothly pans back to player.
5. Repeat with multiple consecutive throws — no degradation.

---

## References

- [Godot Engine docs — Camera2D (4.3)](https://docs.godotengine.org/en/4.3/classes/class_camera2d.html)
- [Godot Engine docs — CanvasItem.top_level (4.3)](https://docs.godotengine.org/en/4.3/classes/class_canvasitem.html#class-canvasitem-property-top-level)
- [godotforums.org — Camera2D jumps when player character reparented](https://godotforums.org/d/27618-camera2d-jumps-when-player-character-reparented-to-new-node)
- [forum.godotengine.org — How to prevent discrete camera jumps when re-parenting](https://forum.godotengine.org/t/how-to-prevent-discrete-camera-jumps-when-re-parenting-a-node/26582)
- [Godot Issue #50807 — `reset_smoothing()` does not work as described](https://github.com/godotengine/godot/issues/50807)
- [Godot Issue #68394 — Camera2D intermittent position jumps with smoothing](https://github.com/godotengine/godot/issues/68394)
