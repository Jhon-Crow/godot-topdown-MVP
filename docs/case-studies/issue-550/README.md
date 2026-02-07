# Case Study: Issue #550 — Enemy Bullets Fly Strictly to the Right

## Problem Summary
Enemies shoot at the player, but their bullets always travel to the right (`Vector2.RIGHT`)
instead of toward the player's actual position. The bug affects all enemy weapon types
(Rifle, Shotgun, UZI) when using C# bullet scenes.

## Timeline of Events
- **Issue #516**: Same bug was reported and fixed in commit `73e4936` but the fix was
  never merged into the `main` branch (the commit became orphaned).
- **Issue #550**: Bug reappears because the fix from #516 was lost.
- **Fix attempt 1** (commit `27782e0`): Fixed `_spawn_projectile()` to call `add_child()`
  before setting C# properties. But missed two other shooting functions.
- **User feedback** (`game_log_20260207_141211.txt`): Problem persists — bullets still fly
  rightward. Logs still show `shooter_position=(0, 0), shooter_id=0`.
- **Fix attempt 2**: Found that `_shoot_with_inaccuracy()` and `_shoot_burst_shot()` also
  create bullets manually without using `_spawn_projectile()`, repeating the same bug.

## Root Cause Analysis

### The Bug (Two Parts)

**Part 1: `_spawn_projectile()` (Fixed in attempt 1)**

The function set bullet properties **before** adding the bullet to the scene tree.
For C# bullets, `has_method()` and property access fail before `_Ready()` runs.

**Part 2: `_shoot_with_inaccuracy()` and `_shoot_burst_shot()` (Found in attempt 2)**

These retreat/burst shooting functions create bullets **without** using `_spawn_projectile()`.
They manually call `bullet_scene.instantiate()` and set properties before `add_child()`:

```gdscript
# BROKEN: _shoot_with_inaccuracy() at line 2376-2382
var bullet := bullet_scene.instantiate()
bullet.global_position = bullet_spawn_pos
bullet.direction = direction          # Fails for C# bullets!
bullet.shooter_id = get_instance_id() # Fails for C# bullets!
bullet.shooter_position = bullet_spawn_pos  # Fails for C# bullets!
get_tree().current_scene.add_child(bullet)  # Too late!
```

```gdscript
# BROKEN: _shoot_burst_shot() at line 2442-2448 (same pattern)
var bullet := bullet_scene.instantiate()
bullet.global_position = bullet_spawn_pos
bullet.direction = direction
bullet.shooter_id = get_instance_id()
bullet.shooter_position = bullet_spawn_pos
get_tree().current_scene.add_child(bullet)
```

### Why This Fails
In Godot 4.3, C# script nodes have their methods and exported properties registered
during the `_Ready()` lifecycle, which only runs when the node enters the scene tree
(i.e., after `add_child()`). Before that:

1. `has_method("SetDirection")` returns `false` — the C# method is not yet registered
2. `p.get("direction")` returns `null` — exported properties are not yet accessible
3. Setting `bullet.direction = value` is silently ignored for C# nodes

Since all property-setting fails silently, the bullet's `Direction` property retains its
default value of `Vector2.Right`, causing all enemy bullets to fly to the right.

### Why the First Fix Was Incomplete
The first fix only addressed `_spawn_projectile()`, which is called by `_shoot()` and
`_shoot_shotgun_pellets()`. However, two other shooting functions bypass `_spawn_projectile()`:

- `_shoot_with_inaccuracy()` — Used during RETREAT mode (reduced accuracy fire)
- `_shoot_burst_shot()` — Used during ONE_HIT retreat mode (arc spread burst fire)

These functions were likely written before `_spawn_projectile()` was refactored, and
duplicated the bullet creation logic instead of delegating to it.

### Evidence from Game Logs (After Fix Attempt 1)

**Log: `game_log_20260207_141211.txt`** (provided by Jhon-Crow after fix)
- Enemy bullets still show `shooter_position=(0, 0), shooter_id=0`
- Death animations show `hit direction: (1, 0)` — bullets hitting rightward
- Player bullets correctly show `shooter_position=(404.7, 521.8), shooter_id=50751080005`
- Confirms the issue is in enemy-side code, not in the C# bullet itself

### Configuration That Triggers the Bug
Enemies use C# bullet scenes by default via `WeaponConfigComponent`:
- RIFLE (weapon_type=0): `"bullet_scene_path": "res://scenes/projectiles/csharp/Bullet.tscn"`
- SHOTGUN (weapon_type=1): `"bullet_scene_path": "res://scenes/projectiles/csharp/ShotgunPellet.tscn"`
- UZI (weapon_type=2): `"bullet_scene_path": "res://scenes/projectiles/Bullet9mm.tscn"` (GDScript, unaffected)

## Fix Applied

### Fix 1: `_spawn_projectile()` (commit 27782e0)
Move `add_child(p)` before all property-setting calls, and use dedicated setter methods:

```gdscript
func _spawn_projectile(dir: Vector2, pos: Vector2) -> void:
    var p := bullet_scene.instantiate()
    p.global_position = pos
    get_tree().current_scene.add_child(p)  # C# _Ready() runs first
    if p.has_method("SetDirection"): p.SetDirection(dir)
    elif p.get("direction") != null: p.direction = dir
    # ... set shooter_id, shooter_position with same pattern ...
```

### Fix 2: Refactor `_shoot_with_inaccuracy()` and `_shoot_burst_shot()`
Replace manual bullet creation with `_spawn_projectile()` call:

```gdscript
# BEFORE (broken):
var bullet := bullet_scene.instantiate()
bullet.global_position = bullet_spawn_pos
bullet.direction = direction
bullet.shooter_id = get_instance_id()
bullet.shooter_position = bullet_spawn_pos
get_tree().current_scene.add_child(bullet)

# AFTER (fixed):
_spawn_projectile(direction, bullet_spawn_pos)
```

### Why the Fix is Safe
- `_PhysicsProcess()` hasn't been called yet at this point, so the bullet won't move
  with the wrong direction even for a single frame
- All bullet creation is now centralized in `_spawn_projectile()`, preventing future
  divergence between shooting functions
- Sound, muzzle flash, ammo tracking, and casing effects remain in their respective
  shooting functions (not affected by bullet creation order)

## Files Changed
- `scripts/objects/enemy.gd`:
  - `_spawn_projectile()` (line ~3866): `add_child` before setting props (Fix 1)
  - `_shoot_with_inaccuracy()` (line ~2375): Use `_spawn_projectile()` instead of manual creation (Fix 2)
  - `_shoot_burst_shot()` (line ~2435): Use `_spawn_projectile()` instead of manual creation (Fix 2)

## Game Logs
- `game_log_20260207_055032.txt` — Original bug report log
- `game_log_20260207_063024.txt` — Additional log from issue
- `game_log_20260207_141211.txt` — Log after Fix 1 (problem persists, leading to Fix 2)

## Related Issues
- Issue #516: Original report of the same bug (fix was lost)
- Issue #457: Initial C# interop work that added `SetDirection()` support
