# Case Study: Issue #79 - Dead Enemies Must Ignore Bullets

## Issue Summary

**Issue**: [#79 - убитые враги должны сразу игнорировать пули](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/79)

**Translation**: "Killed enemies should immediately ignore bullets"

**Problem**: When enemies are killed, they continue to absorb/block bullets during the respawn delay period, wasting player ammunition. Since ammunition management is a core gameplay mechanic, this significantly impacts game balance.

## Timeline of Events

### Initial Report
- **Date**: 2026-01-18
- **Reporter**: Jhon-Crow (repository owner)
- **Description**: Dead enemies continue to block bullets instead of letting them pass through

### First Fix Attempt
- **Commit**: `17e8010` (2026-01-18 08:57:37)
- **Approach**: Disabled HitArea's `monitorable` and `monitoring` properties using `set_deferred()` in the `_on_death()` function
- **Result**: Did not fully resolve the issue

### User Feedback
- **Date**: 2026-01-18 11:06-11:08
- **Logs Provided**:
  - `game_log_20260118_110600.txt` (16KB)
  - `game_log_20260118_110624.txt` (105KB)
- **Feedback**: "пули не пролетают сквозь убитого врага, а должны" (bullets don't pass through dead enemy, but they should)

## Technical Analysis

### How Bullet-Enemy Collision Works

```
Bullet (Area2D)          HitArea (Area2D)          Enemy (CharacterBody2D)
collision_layer: 16      collision_layer: 2
collision_mask: 39       collision_mask: 16
    |                         |                         |
    |---area_entered()------->|                         |
    |                    on_hit()---------------------->|
    |                         |                   on_hit()
    |                         |                   (applies damage)
    |<--signal processed------|                         |
    queue_free()              |                         |
    (bullet destroyed)        |                         |
```

### The Flawed Fix Approach

The initial fix attempted to disable collision by setting:
```gdscript
if _hit_area:
    _hit_area.set_deferred("monitorable", false)
    _hit_area.set_deferred("monitoring", false)
```

### Why It Doesn't Work

Based on investigation and Godot engine issue reports:

1. **[Issue #62506](https://github.com/godotengine/godot/issues/62506)**: `set_deferred()` with `monitorable`/`monitoring` has inconsistent behavior depending on the order of property assignment

2. **[Issue #100687](https://github.com/godotengine/godot/issues/100687)**: When two Area2Ds are already overlapping and one toggles its `monitorable` property, the other Area2D's signals are NOT re-triggered

3. **Timing Issue**: Bullets traveling at 2500 pixels/second can enter the HitArea during the same physics frame that the enemy dies. The collision signal may already be queued before `set_deferred()` executes.

4. **Deferred Execution**: `set_deferred()` schedules the change for the end of the current frame, but collision signals from the same frame have already been registered.

### Root Cause

The fundamental issue is that **disabling `monitorable`/`monitoring` does not affect already-registered collision events**. The bullet's `area_entered` signal was connected when it entered the HitArea's collision shape, and toggling `monitorable` after the fact doesn't "un-enter" the area.

## Proposed Solution

A multi-layered approach is needed:

### Layer 1: Disable the CollisionShape2D
```gdscript
var hit_collision: CollisionShape2D = _hit_area.get_node_or_null("HitCollisionShape")
if hit_collision:
    hit_collision.set_deferred("disabled", true)
```
This physically removes the collision shape from the physics engine.

### Layer 2: Move to an unused collision layer
```gdscript
_hit_area.set_deferred("collision_layer", 0)
_hit_area.set_deferred("collision_mask", 0)
```
This prevents any future collision detection even if the shape somehow remains active.

### Layer 3: Keep existing monitorable/monitoring disabling
As an additional safety measure, keep the original fix in place.

### Layer 4: Add explicit check in bullet collision handler
Modify the bullet to check if the parent entity is alive before counting the hit:
```gdscript
# In bullet.gd _on_area_entered()
var parent: Node = area.get_parent()
if parent and parent.has_method("is_alive") and not parent.is_alive():
    return  # Don't destroy bullet for dead enemies
```

## Log Analysis

From `game_log_20260118_110624.txt`:

```
[11:06:26] [ENEMY] [Enemy3] Hit taken, health: 1/2
[11:06:26] [ENEMY] [Enemy3] Hit taken, health: 0/2
[11:06:26] [ENEMY] [Enemy3] Enemy died
[11:06:26] [INFO] [SoundPropagation] Unregistered listener: Enemy3 (remaining: 9)
[11:06:26] [INFO] [SoundPropagation] Sound emitted: type=GUNSHOT, pos=(450, 764.6466), source=PLAYER...
[11:06:26] [INFO] [SoundPropagation] Sound result: notified=3, out_of_range=3...
```

The logs show enemies dying, but we cannot see if bullets are being absorbed because the bullet destruction isn't logged. Adding debug logging to the bullet collision would help diagnose this in the future.

## Files Involved

- `scripts/objects/enemy.gd` - Enemy AI with death handling
- `scripts/objects/hit_area.gd` - Forwards on_hit to parent
- `scripts/projectiles/bullet.gd` - Bullet collision handling
- `scenes/objects/Enemy.tscn` - Scene with HitArea and HitCollisionShape

## References

- [Godot Issue #62506](https://github.com/godotengine/godot/issues/62506) - set_deferred() on Area2D monitoring/monitorable reports collisions inconsistently
- [Godot Issue #100687](https://github.com/godotengine/godot/issues/100687) - Area2D doesn't detect when overlapping Area2D's monitorable is toggled
- [Godot Issue #27441](https://github.com/godotengine/godot/issues/27441) - Area2D/3D monitoring and monitorable not working according to docs
- [Godot Forum Discussion](https://forum.godotengine.org/t/why-does-setting-the-monitorable-property-to-false-make-monitoring-stop-working-in-the-same-area2d/7966)

## Conclusion

The issue stems from fundamental limitations in how Godot handles Area2D collision toggling at runtime. A robust solution requires multiple complementary approaches: disabling the collision shape, changing collision layers, and adding explicit alive-state checks in the bullet code.
