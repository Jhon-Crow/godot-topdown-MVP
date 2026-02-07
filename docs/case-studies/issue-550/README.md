# Case Study: Issue #550 — Enemy Bullets Fly Strictly to the Right

## Problem Summary
Enemies shoot at the player, but their bullets always travel to the right (`Vector2.RIGHT`)
instead of toward the player's actual position. The bug affects all enemy weapon types
(Rifle, Shotgun, UZI) when using C# bullet scenes.

## Timeline of Events
- **Issue #516**: Same bug was reported and fixed in commit `73e4936` but the fix was
  never merged into the `main` branch (the commit became orphaned).
- **Issue #550**: Bug reappears because the fix from #516 was lost.

## Root Cause Analysis

### The Bug
In `scripts/objects/enemy.gd`, the `_spawn_projectile()` function sets bullet properties
(direction, shooter_id, shooter_position) **before** adding the bullet to the scene tree:

```gdscript
# BROKEN: Properties set before add_child
func _spawn_projectile(direction, spawn_pos):
    var p = bullet_scene.instantiate()
    p.global_position = spawn_pos
    if p.has_method("SetDirection"): p.SetDirection(direction)  # Fails silently!
    # ... set shooter_id, shooter_position ...
    get_tree().current_scene.add_child(p)  # Too late!
```

### Why This Fails
In Godot 4.3, C# script nodes have their methods and exported properties registered
during the `_Ready()` lifecycle, which only runs when the node enters the scene tree
(i.e., after `add_child()`). Before that:

1. `has_method("SetDirection")` returns `false` — the C# method is not yet registered
2. `p.get("direction")` returns `null` — exported properties are not yet accessible
3. `p.get("Direction")` returns `null` — same reason

Since all three checks fail, the bullet's `Direction` property retains its default value
of `Vector2.Right`, causing all enemy bullets to fly to the right.

### Evidence from Game Logs
The attached logs confirm the issue:

**Log: `game_log_20260207_063024.txt`**
- Enemy3 is at position (700, 750) shooting at player near (641, 624)
- Bullets hit walls at x=938 and x=926 — traveling RIGHT instead of LEFT toward player
- `shooter_position=(0, 0)` and `shooter_id=0` confirm that no properties were set at all
- Player-fired bullets (using C# weapon classes that call `add_child` first) correctly
  have `shooter_position` and `shooter_id` values

### Contrast with Player Weapons
Player weapons in C# (`BaseWeapon.cs`, `Player.cs`) use `bullet.Call("SetDirection", direction)`
AFTER adding the bullet to the scene. The player's bullet properties are set correctly
because the C# node has already entered the scene tree and its methods are registered.

## Fix Applied
Move `add_child(p)` before all property-setting calls, and use dedicated setter methods:

```gdscript
# FIXED: add_child first, then set properties
func _spawn_projectile(dir, pos):
    var p = bullet_scene.instantiate()
    p.global_position = pos
    get_tree().current_scene.add_child(p)  # C# _Ready() runs, methods become available
    if p.has_method("SetDirection"): p.SetDirection(dir)  # Now works!
    # ... set shooter_id via SetShooterId, shooter_position via SetShooterPosition ...
```

### Why the Fix is Safe
- `_PhysicsProcess()` hasn't been called yet at this point, so the bullet won't move
  with the wrong direction even for a single frame
- The `_Ready()` method in C# Bullet calls `UpdateRotation()` which uses the default
  `Direction = Vector2.Right`, but `SetDirection()` is called immediately after and
  overrides both `Direction` and rotation

## Files Changed
- `scripts/objects/enemy.gd` — `_spawn_projectile()` function (lines 3865-3877)

## Related Issues
- Issue #516: Original report of the same bug (fix was lost)
- Issue #457: Initial C# interop work that added `SetDirection()` support
