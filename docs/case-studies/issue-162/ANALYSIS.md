# Case Study: Issue #162 - Unexpected Bullet Penetrations (прострелы)

## Issue Summary

**Issue:** Unexpected bullet penetrations occur that shouldn't happen according to game design.
**User hypothesis:** Related to performance, bullet speed, or ricochet direction.
**Severity:** Medium - affects gameplay fairness and realism.

## Root Cause Analysis

### Primary Issue: Premature body_exited Signal

The main bug is caused by Godot's physics signal timing. When a bullet enters a wall and starts penetration:

1. `body_entered` fires → `_try_penetration()` is called
2. Bullet is moved forward 5 pixels to avoid re-collision: `global_position += direction * 5.0`
3. **BUG:** This movement can immediately trigger `body_exited` signal in the SAME physics frame
4. Result: Bullet exits penetration with `_penetration_distance_traveled = 0` pixels

**Evidence from logs:**
```
[09:15:40] Starting wall penetration at (344.32074, 1585.6317)
[09:15:40] Body exited signal received for penetrating body
[09:15:40] Exiting penetration at (353.71436, 1624.9415) after traveling 0 pixels through wall
```

The entry point (344, 1585) and exit point (353, 1624) are ~40 pixels apart, yet "0 pixels" is logged because:
- `_penetration_distance_traveled` is only updated in `_physics_process()`
- `body_exited` signal fires before the next physics frame

### Secondary Issue: Cross-Bullet Signal Confusion

When multiple bullets penetrate simultaneously, exit signals can get crossed:

**Evidence from logs:**
```
[09:15:43] Starting wall penetration at (438.85962, 699.79663)   <-- Bullet A at Y=699
[09:15:43] Starting wall penetration at (311.6459, 1398.7283)    <-- Bullet B at Y=1398
[09:15:43] Exiting penetration at (447.0351, 662.3453)           <-- Wrong! This should be at Y~700
[09:15:43] Exiting penetration at (319.42203, 1361.192)
```

The exit position `(447, 662)` for bullet B doesn't match its entry at `(311, 1398)` - they're in completely different areas of the map (~750 pixels apart vertically).

### Godot Known Issues

According to Godot issue tracker:
- [#86199](https://github.com/godotengine/godot/issues/86199): Area2D body_entered signal is emitted too late
- [#23026](https://github.com/godotengine/godot/issues/23026): Area body_exited signal sent while body moves but remains inside
- [#22889](https://github.com/godotengine/godot/issues/22889): Inconsistent generation of Area body_entered/body_exited signals

## Detailed Timeline Reconstruction

### Scenario 1: Zero-Distance Penetration
```
Frame N:
  1. Bullet at (344, 1585) hits wall → body_entered
  2. TryPenetration() starts:
     - _is_penetrating = true
     - _penetrating_body = wall
     - _penetration_distance_traveled = 0
     - global_position += direction * 5.0  → bullet moves to ~(349, 1592)
  3. IMMEDIATE: body_exited fires because bullet moved outside wall collision shape
     - _exit_penetration() called
     - Logs "0 pixels" because no _physics_process ran yet

Frame N+1:
  - Bullet is already destroyed, but was at (353, 1624)
```

### Scenario 2: Cross-Bullet Confusion
```
Frame N:
  1. Bullet A starts penetration at (438, 699)
  2. Bullet B starts penetration at (311, 1398)

Frame N+1:
  3. Bullet A's body_exited fires, but signal may carry stale/wrong body reference
  4. OR: Signal processing order causes incorrect bullet to handle the exit
```

## Proposed Solutions

### Solution 1: Add Minimum Penetration Time Guard (Recommended)

Add a minimum time/frame delay before allowing exit:

```gdscript
# In bullet.gd
var _penetration_start_frame: int = 0
const MIN_PENETRATION_FRAMES: int = 2

func _try_penetration(body: Node2D) -> bool:
    # ... existing code ...
    _penetration_start_frame = Engine.get_physics_frames()
    return true

func _on_body_exited(body: Node2D) -> void:
    if not _is_penetrating or _penetrating_body != body:
        return

    # Guard: Ignore exit signals that come too soon
    var current_frame = Engine.get_physics_frames()
    if current_frame - _penetration_start_frame < MIN_PENETRATION_FRAMES:
        _log_penetration("Ignoring premature body_exited (frame %d, started %d)" % [current_frame, _penetration_start_frame])
        return

    _exit_penetration()
```

### Solution 2: Use Deferred Exit Processing

Instead of immediate exit, queue it for next frame:

```gdscript
func _on_body_exited(body: Node2D) -> void:
    if not _is_penetrating or _penetrating_body != body:
        return

    # Defer to next physics frame to ensure distance is tracked
    call_deferred("_deferred_exit_check", body)

func _deferred_exit_check(body: Node2D) -> void:
    if not _is_penetrating or _penetrating_body != body:
        return
    _exit_penetration()
```

### Solution 3: Rely Only on Raycast Detection

Remove dependency on body_exited signal entirely:

```gdscript
func _physics_process(delta: float) -> void:
    # ... movement code ...

    if _is_penetrating:
        _penetration_distance_traveled += movement.length()

        # Only use raycast detection, ignore body_exited
        if not _is_still_inside_obstacle():
            _exit_penetration()

func _on_body_exited(body: Node2D) -> void:
    # Disabled - use raycast-only detection
    pass
```

### Solution 4: Validate Exit Position (Sanity Check)

Add validation that exit position is reasonable:

```gdscript
func _exit_penetration() -> void:
    if not _is_penetrating:
        return

    var exit_point := global_position
    var distance_from_entry := exit_point.distance_to(_penetration_entry_point)

    # Sanity check: exit should be reasonably close to entry
    # Maximum expected: max_penetration_distance + some tolerance
    var max_reasonable_distance := _get_max_penetration_distance() * 2.0
    if distance_from_entry > max_reasonable_distance:
        _log_penetration("WARNING: Exit position too far from entry (%s > %s), likely signal error" % [distance_from_entry, max_reasonable_distance])
        # Option: Destroy bullet without "successful" penetration effect
        queue_free()
        return

    # ... rest of exit logic ...
```

## Recommended Fix

Combine Solutions 1 and 4:

1. **Frame guard**: Prevent body_exited from triggering until at least 2 physics frames have passed
2. **Sanity validation**: Check that exit position is within reasonable distance of entry
3. **Enhanced logging**: Add frame numbers and distances to debug output

This approach:
- Fixes the immediate "0 pixels" bug
- Provides protection against cross-bullet confusion
- Maintains compatibility with existing raycast-based detection
- Doesn't require major architectural changes

## Testing Recommendations

1. **High-speed shooting test**: Rapid fire at walls to trigger multiple simultaneous penetrations
2. **Point-blank test**: Shoot walls at very close range
3. **Corner test**: Shoot at wall corners where collision shapes may be thin
4. **Performance test**: Test with many bullets simultaneously to check for signal races

## References

- Godot Issue #86199: [Area2D body_entered signal timing](https://github.com/godotengine/godot/issues/86199)
- Godot Issue #23026: [body_exited sent while body remains inside](https://github.com/godotengine/godot/issues/23026)
- Godot Issue #22889: [Inconsistent Area signals](https://github.com/godotengine/godot/issues/22889)
- Godot Forum: [body_exited not working](https://forum.godotengine.org/t/body-exited-not-working/8990)

## Files Affected

- `scripts/projectiles/bullet.gd` - GDScript bullet implementation
- `Scripts/Projectiles/Bullet.cs` - C# bullet implementation (needs same fix)
