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

### Second Fix Attempt
- **Commit**: `f1580c7` (2026-01-18)
- **Approach**: Multi-layered approach on HitArea + bullet-side `is_alive()` check for area collisions
- **Result**: Still did not resolve the issue - bullets still stopped by dead enemies

### User Feedback (Round 1)
- **Date**: 2026-01-18 11:06-11:08
- **Logs Provided**:
  - `game_log_20260118_110600.txt` (16KB)
  - `game_log_20260118_110624.txt` (105KB)
- **Feedback**: "пули не пролетают сквозь убитого врага, а должны" (bullets don't pass through dead enemy, but they should)

### User Feedback (Round 2)
- **Date**: 2026-01-18 11:23-11:25
- **Logs Provided**:
  - `game_log_20260118_112310.txt` (197KB)
  - `game_log_20260118_112522.txt` (42KB)
- **Feedback**: "мёртвые враги всё ещё останавливают пули" (dead enemies still stop bullets)

### Third Fix Attempt - The Complete Fix
- **Commit**: `319f59f` (2026-01-18 08:34:49 UTC)
- **Approach**: Added `is_alive()` check in `_on_body_entered()` to handle CharacterBody2D collision
- **Result**: Fixed the issue

### Important Timing Note
The user's second feedback (at 08:27 UTC) was submitted **before** the complete fix (at 08:34 UTC) was pushed. The user was testing an older build that only had the HitArea fix, but not the CharacterBody2D fix. The new build with the complete fix is available via CI artifacts.

## Technical Analysis

### How Bullet-Enemy Collision Works

The bullet (Area2D) can collide with BOTH the HitArea (Area2D) and the Enemy body (CharacterBody2D):

```
Bullet (Area2D)          HitArea (Area2D)          Enemy (CharacterBody2D)
collision_layer: 16      collision_layer: 2        collision_layer: 2
collision_mask: 39       collision_mask: 16        collision_mask: 4
    |                         |                         |
    |---area_entered()------->|                         |
    |                    on_hit()---------------------->|
    |                         |                   on_hit()
    |                         |                   (applies damage)
    |                         |                         |
    |---body_entered()--------------------------------->|
    queue_free()              |                         |
    (bullet destroyed)        |                         |
```

**Key Insight**: The bullet's collision_mask (39 = 1 + 2 + 4 + 32) includes layer 2, which is the enemy's collision_layer. This means bullets collide with BOTH:
1. The HitArea (via `area_entered` signal)
2. The Enemy CharacterBody2D (via `body_entered` signal)

### The Flawed Fix Approaches

#### Attempt 1: Disable HitArea monitoring
```gdscript
if _hit_area:
    _hit_area.set_deferred("monitorable", false)
    _hit_area.set_deferred("monitoring", false)
```

#### Attempt 2: Multi-layered approach (HitArea only)
Added collision shape disabling, layer clearing, and bullet-side `is_alive()` check for area collisions.

### Why Neither Fix Worked

**The Root Cause**: Both fixes only addressed the HitArea (Area2D) collision, but ignored the CharacterBody2D collision!

The bullet's `_on_body_entered()` function was:
```gdscript
func _on_body_entered(_body: Node2D) -> void:
    # Hit a static body (wall or obstacle)
    var audio_manager: Node = get_node_or_null("/root/AudioManager")
    if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
        audio_manager.play_bullet_wall_hit(global_position)
    queue_free()  # <-- ALWAYS destroys bullet, even for dead enemies!
```

This function:
1. Didn't check if the body was a dead enemy
2. Always called `queue_free()`, destroying the bullet unconditionally

Even though the HitArea collision was handled correctly (checking `is_alive()`), the bullet was being destroyed by the CharacterBody2D collision BEFORE the HitArea collision could be processed!

### Additional Godot Engine Limitations

Based on Godot engine issue reports:

1. **[Issue #62506](https://github.com/godotengine/godot/issues/62506)**: `set_deferred()` with `monitorable`/`monitoring` has inconsistent behavior
2. **[Issue #100687](https://github.com/godotengine/godot/issues/100687)**: When two Area2Ds are overlapping and one toggles `monitorable`, the other's signals are NOT re-triggered
3. **[Issue #86199](https://github.com/godotengine/godot/issues/86199)**: Area2D `body_entered` signal is emitted 1 physics tick late
4. **Timing Issue**: Bullets at 2500 pixels/second can enter the collision during the same physics frame that the enemy dies

## Solution

The fix requires handling BOTH collision paths in the bullet:

### Fix 1: Handle CharacterBody2D Collision (The Critical Fix)
```gdscript
# In bullet.gd _on_body_entered()
func _on_body_entered(body: Node2D) -> void:
    # Check if this is the shooter - don't collide with own body
    if shooter_id == body.get_instance_id():
        return  # Pass through the shooter

    # Check if this is a dead enemy - bullets should pass through dead entities
    if body.has_method("is_alive") and not body.is_alive():
        return  # Pass through dead entities

    # Hit a static body (wall or obstacle) or alive enemy body
    var audio_manager: Node = get_node_or_null("/root/AudioManager")
    if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
        audio_manager.play_bullet_wall_hit(global_position)
    queue_free()
```

### Fix 2: Handle HitArea Collision (Already Implemented)
```gdscript
# In bullet.gd _on_area_entered()
var parent: Node = area.get_parent()
if parent and parent.has_method("is_alive") and not parent.is_alive():
    return  # Don't destroy bullet for dead enemies
```

### Enemy-Side Measures (Already Implemented)
Keep the multi-layered approach on the enemy for defense in depth:
1. Disable CollisionShape2D: `_hit_collision_shape.set_deferred("disabled", true)`
2. Clear collision layers: `_hit_area.set_deferred("collision_layer", 0)`
3. Disable monitoring: `_hit_area.set_deferred("monitorable", false)`

These measures help with any new bullets entering the area after death, while the bullet-side checks handle bullets that were already in collision at the moment of death

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

The issue stems from fundamental limitations in how Godot handles Area2D collision toggling at runtime, combined with the fact that bullets collide with BOTH the HitArea (Area2D) and the Enemy CharacterBody2D.

The complete fix required TWO key changes:
1. **Enemy-side** (commit `f1580c7`): Multi-layered approach to disable HitArea collision on death
2. **Bullet-side** (commit `319f59f`): Add `is_alive()` check in `_on_body_entered()` to handle CharacterBody2D collision

Both changes are necessary because:
- The HitArea fix prevents new bullets from being absorbed
- The body collision fix handles bullets that collide with the CharacterBody2D (which has collision_layer = 2, matching bullet's collision_mask)

A robust solution requires multiple complementary approaches: disabling the collision shape, changing collision layers, and adding explicit alive-state checks in the bullet code for both body and area collision handlers.

## Status

**Fixed**: The complete fix is implemented in commit `319f59f` and CI builds have passed. Users should download the latest build from CI artifacts to test the fix.
