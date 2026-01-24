# Case Study: Issue #313 - Grenade Throwing Direction Bug

## Summary

The grenade throwing system had a critical bug where grenades flew in unexpected directions, particularly when throwing in cardinal directions (up, down, left, right). The user reported that grenades didn't fly where they intended them to go.

## Problem Description

From the issue (translated from Russian):
- User wanted to throw grenades in specific directions
- Grenades flew diagonally instead of in the intended direction
- Screen resolution: 1920x1080
- Request: Fix the throw so grenades fly where intended

## Timeline of Events

1. **2026-01-24 09:49-09:56** - User tested max-power throws in various directions
2. **2026-01-24 10:20-10:35** - User tested medium-power throws, logs show detailed debugging
3. The logs revealed a critical warning: `"No throw method found! Using C# fallback"`

## Root Cause Analysis

### Primary Issue: Cross-Language Method Detection Failure

The logs showed:
```
[Player.Grenade.Throw] Method availability: velocity_based=False, legacy=False
[Player.Grenade.Throw] WARNING: No throw method found! Using C# fallback to unfreeze and apply velocity
```

The GDScript methods `throw_grenade_velocity_based()` and `throw_grenade()` were NOT being detected by the C# code's `has_method()` call. This is a known issue with Godot's GDScript-C# interop.

### Secondary Issue: Wrong Direction Calculation in Fallback

When the C# fallback kicked in, it used "player_to_mouse" direction:
- Log: `Direction source: player_to_mouse (FIXED in issue #281)`

This direction calculates the vector from player position to mouse position, NOT the mouse velocity direction.

### The Mathematical Problem

Example from medium-down throw:
- **Player position**: (150, 360) - left side of screen
- **Mouse position at release**: (672.7, 719.3) - bottom-right area
- **Mouse velocity**: (-341.9, 0) - moving LEFT at 180°
- **Expected throw direction**: DOWN (positive Y, minimal X)
- **Actual throw direction**: (0.824, 0.566) - RIGHT-DOWN at 34.5°

The "player_to_mouse" vector from (150, 360) to (672.7, 719.3) is (522.7, 359.3) which points RIGHT-DOWN, not DOWN.

### Why This Happens

On a 1920x1080 screen:
1. Player is positioned on the LEFT side of the level (X=150)
2. When trying to throw DOWN, user moves mouse to bottom of screen
3. Due to screen geometry, the mouse ends up at (672, 719) - to the RIGHT of player
4. The horizontal distance (522px) is comparable to vertical distance (359px)
5. The resulting vector points diagonally, not vertically

## Solution Implemented

Added a direct physics fallback in `player.gd` that:

1. Detects when neither GDScript method is found via `has_method()`
2. Directly manipulates the grenade's RigidBody2D physics
3. Uses the **mouse velocity direction** (not player-to-mouse) for throw direction
4. Applies the same physics formulas as `grenade_base.gd`

### Key Code Change

```gdscript
# CRITICAL FIX for issue #313: Direct physics fallback
if not method_called:
    if _active_grenade is RigidBody2D:
        _active_grenade.freeze = false
        # Calculate throw using mouse velocity direction
        _active_grenade.linear_velocity = throw_direction * throw_speed
```

The critical fix is that `throw_direction` is calculated from `release_velocity.normalized()` (mouse velocity), NOT from player-to-mouse position.

## Log Files

The following log files were collected:

### Max Power Throws
- `max-right.txt` - Throwing to the right (worked correctly)
- `max-left.txt` - Throwing to the left
- `max-down.txt` - Throwing down (showed diagonal flight)
- `max-up.txt` - Throwing up
- `max-top-right-corner.txt` - Top-right corner
- `max-bottom-right-corner.txt` - Bottom-right corner
- `max-top-left-corner.txt` - Top-left corner
- `max-bottom-left-corner.txt` - Bottom-left corner

### Medium Power Throws
- `medium-down.txt` - Medium power down (detailed debugging enabled)
- `medium-up.txt` - Medium power up
- `medium-right.txt` - Medium power right
- `medium-left-or-right.txt` - Medium power (direction uncertain)

## Lessons Learned

1. **Cross-language interop can fail silently** - Always have fallback paths
2. **Direction calculation matters** - "player_to_mouse" vs "mouse_velocity" give very different results
3. **Screen geometry affects UX** - Wide screens make vertical throws difficult if using position-based direction
4. **Detailed logging is essential** - The `Method availability: velocity_based=False` log was key to diagnosis

## References

- [Godot Forum: Aiming toward mouse movement direction](https://forum.godotengine.org/t/in-a-2d-game-how-do-i-aim-towards-the-mouses-moving-direction-instead-of-aiming-towards-the-cursor/2451)
- [Godot Docs: Mouse and input coordinates](https://docs.godotengine.org/en/stable/tutorials/inputs/mouse_and_input_coordinates.html)
- PR #260: Implement realistic velocity-based grenade throwing physics
