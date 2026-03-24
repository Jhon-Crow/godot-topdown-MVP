# Game Log Analysis: 2026-03-17 12:48:47 (Session 11)

## User Feedback

1. Rocket should be directed along movement direction and not rotate freely
2. Rocket must explode on collision (like offensive grenade or VOG)

## Key Findings from Log

### Rockets Launched (but no RpgRocket script logs)

```
[12:49:02] [ENEMY] [Enemy] [RPG] Rocket launched at (288.998, 364.16) dir=(-1, 0)
[12:49:15] [ENEMY] [RpgEnemy1] [RPG] Rocket launched at (2704.032, 1312.802) dir=(-0.99897, -0.04537)
[12:49:16] [ENEMY] [RpgEnemy2] [RPG] Rocket launched at (1639.789, 1890.161) dir=(-0.3159, -0.948792)
... (9 rockets total launched)
```

**Zero** `[RpgRocket]` log entries appear. This means `_ready()` in `rpg_rocket.gd` is NOT executing in the exported build.

## Root Causes

### Root Cause #11a: GDScript _ready() not running in exported builds

The rocket node is instantiated and has `linear_velocity` set externally (so it moves),
but the GDScript code never runs. This is a recurring Godot 4 export pitfall:
dynamically instantiated GDScript nodes may have scripts that don't execute.

**Impact**:
- `body_entered.connect(_on_body_entered)` never called → no explosion
- `rotation = direction.angle()` never set → uses default 0 rotation
- `contact_monitor = true` never set → `body_entered` would never fire even if connected

### Root Cause #11b: contact_monitor not set in .tscn

In Godot 4, `RigidBody2D.body_entered` signal only fires when `contact_monitor = true`
AND `max_contacts_reported > 0`. The `grenade_base.gd` explicitly sets these:

```gdscript
contact_monitor = true
max_contacts_reported = 4
```

But `rpg_rocket.gd` relies on setting these in `_ready()` which doesn't run in exports.
**Fix**: Set `contact_monitor = true` and `max_contacts_reported = 4` in RpgRocket.tscn.

### Root Cause #11c: lock_rotation not set in .tscn

`RigidBody2D` can rotate freely from physics angular forces (torque from collisions).
For a rocket that should always face its travel direction:
- Set `lock_rotation = true` in the .tscn → physics engine won't rotate it
- In `_physics_process`, update `rotation = linear_velocity.angle()` → always faces direction

## Fix Plan

1. **RpgRocket.tscn**: Add `contact_monitor = true`, `max_contacts_reported = 4`, `lock_rotation = true`
2. **RpgRocket.tscn**: Connect `body_entered` signal to `_on_body_entered` in the scene file
3. **rpg_rocket.gd**: In `_physics_process`, update `rotation = linear_velocity.angle()` when moving

## Evidence from grenade_base.gd (working reference)

```gdscript
# Enable contact monitoring for body_entered signal (required for collision detection)
# Without this, body_entered signal will never fire!
contact_monitor = true
max_contacts_reported = 4
```

This confirms that `contact_monitor` must be true for `body_entered` to work.
