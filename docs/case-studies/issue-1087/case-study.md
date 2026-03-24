# Case Study: Issue #1087 — Breaching Charge Passage at Wrong Position

## Summary

The breach passage appeared at the wrong location (e.g., top of the wall or a corner) instead of where the player placed the charge.

## Timeline of Events

1. **Issue #1087 opened** — User requested breaching charges feature.
2. **PR #1089 created** — Initial implementation: carve wall passage, directional explosion, LED marker.
3. **Feedback round 1** — "Thin walls disappear entirely; passage too small (56 px)."
   - Fix: restored `BREACH_PASSAGE_WIDTH` to 120 px; thin walls now faded (alpha 0.25) instead of hidden.
4. **Feedback round 2** — "The hole appears where the charge is NOT placed." (with screenshots and log)
   - Root cause found: `_charge_position` was cleared to `Vector2.ZERO` before being used.

## Root Cause Analysis

### The Bug

In `breaching_charges_effect.gd`, function `detonate()`:

```gdscript
var det_pos := _charge_position   # saved locally — correct
...
# Clear state before applying effects (prevent double-detonation)
_charge_position = Vector2.ZERO   # <-- CLEARED HERE

...
_open_wall_passage(wall)          # called AFTER clearing
```

Inside `_open_wall_passage()`:

```gdscript
var breach_world: Vector2 = _charge_position   # reads ZERO, not the actual position!
var breach_local: Vector2 = wall.to_local(breach_world)
```

`wall.to_local(Vector2.ZERO)` converts world origin (0,0) to the wall's local space. For a wall at position (450, 800), this gives local coordinates `(-450, -800)` — far outside the wall. The clamp then pushes this to the wall boundary minimum (e.g., y = -90 for half_h=150, half_breach=60), so the breach always appeared at the same edge of the wall.

### Evidence from Game Log

```
[07:53:18] Charge placed on 'Storage_WallRight' at (438, 769.6947)
[07:53:19] Vertical passage carved in 'Storage_WallRight' at local y=-90  ← wrong (expected ~-30)

[07:53:29] Charge placed on 'Storage_WallRight' at (438, 816.6948)
[07:53:30] Vertical passage carved in 'Storage_WallRight' at local y=-90  ← same wrong value despite different hit position
```

Two different world positions mapped to identical local y = -90 (the clamped minimum), confirming the breach_world was always (0,0).

### Screenshots

- `screenshot_wrong_breach_position_1.png` — Charge visible in wall center; breach appears at left corner.
- `screenshot_wrong_breach_position_2.png` — Similar misalignment on a different wall.

## Fix

Pass the saved `det_pos` (local copy) as a parameter to `_open_wall_passage` instead of reading the instance variable after it was cleared:

```gdscript
# Before (buggy):
_charge_position = Vector2.ZERO
...
_open_wall_passage(wall)  # reads _charge_position = (0,0)

# After (fixed):
_charge_position = Vector2.ZERO
...
_open_wall_passage(wall, det_pos)  # uses the saved local copy
```

And updated the function signature:
```gdscript
func _open_wall_passage(wall: Node, breach_world_pos: Vector2) -> void:
    ...
    var breach_local: Vector2 = wall.to_local(breach_world_pos)
```

## Files Changed

- `scripts/effects/breaching_charges_effect.gd`

## Attached Evidence

- `game_log_20260317_075301.txt` — Full game session log showing repeated wrong local y=-90
- `screenshot_wrong_breach_position_1.png` — First screenshot from user report
- `screenshot_wrong_breach_position_2.png` — Second screenshot from user report
