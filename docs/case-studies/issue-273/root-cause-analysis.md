# Root Cause Analysis: Issue #273 - Enemy Grenade Throwing Not Working

## Problem Statement

The owner reported "не работает" (doesn't work) - enemy grenade throwing is not functioning even at HARD difficulty level.

## Evidence from Logs

From the game logs (`game_log_20260124_011237.txt`, `game_log_20260124_011800.txt`):

1. **Player grenade logs are present** - Player can throw grenades successfully
2. **Enemy grenade logs are absent** - No `[ENEMY] ... grenade` or `GrenadeThrower` logs
3. **HARD mode is active** - `[PenultimateHit] Hard mode active` confirms difficulty
4. **Enemy10 is active** - Multiple log entries show `[ENEMY] [Enemy10]` actions
5. **Death animation component initialized** - Shows enemy components loading correctly
6. **GrenadeThrowerComponent NOT initialized** - No log entry for grenade component

## Root Cause: Godot Node Lifecycle Timing Issue

### The Problem

In Godot, the node lifecycle calls `_ready()` in a specific order:
1. **Children's `_ready()` is called BEFORE parent's `_ready()`**

This means:
```
1. Enemy10._ready() runs first
   - Checks `if enable_grenades:` → false (default value)
   - GrenadeThrowerComponent is NOT created

2. BuildingLevel._ready() runs second
   - Calls _configure_enemy_grenades()
   - Sets enemy10.enable_grenades = true
   - BUT IT'S TOO LATE! Enemy's _ready() already ran
```

### Code Flow Analysis

**enemy.gd** (line 706-718):
```gdscript
func _ready() -> void:
    # ... other initialization ...

    # Initialize grenade thrower component (per issue #273)
    if enable_grenades:  # ← This is false at this point!
        _grenade_thrower = GrenadeThrowerComponent.new()
        # ... configuration ...
        add_child(_grenade_thrower)
```

**building_level.gd** (called AFTER enemy._ready()):
```gdscript
func _ready() -> void:
    _setup_enemy_tracking()  # ← Calls _configure_enemy_grenades()

func _configure_enemy_grenades() -> void:
    # ... difficulty check ...
    enemy10.enable_grenades = true  # ← Too late! enemy._ready() already ran
    enemy10.offensive_grenades = 2
```

### Why C# Was Mentioned

The owner mentioned "возможно дело в C#" (maybe it's a C# issue) because:
1. The game uses both GDScript (enemies, levels) and C# (player, weapons)
2. The logs show C# player signals working correctly
3. This was a red herring - the issue is purely a GDScript node lifecycle problem

## Solution

The fix requires one of these approaches:

### Option A: Add Late Initialization Method (Recommended)
Add a method to `enemy.gd` that can be called after `_ready()` to configure grenades:

```gdscript
## Configure grenade system after _ready() has completed.
## Call this from level scripts that need to set up grenades dynamically.
func configure_grenades(enabled: bool, offensive: int, flashbangs: int = 0) -> void:
    enable_grenades = enabled
    offensive_grenades = offensive
    flashbang_grenades = flashbangs

    if enabled and _grenade_thrower == null:
        _grenade_thrower = GrenadeThrowerComponent.new()
        _grenade_thrower.enabled = true
        _grenade_thrower.offensive_grenades = offensive_grenades
        # ... rest of configuration ...
        add_child(_grenade_thrower)
        call_deferred("_register_ally_death_listener")
```

Then in `building_level.gd`:
```gdscript
func _configure_enemy_grenades() -> void:
    # ... difficulty check ...
    if enemy10.has_method("configure_grenades"):
        enemy10.configure_grenades(true, 2, 0)
```

### Option B: Use call_deferred in Enemy
Could defer the grenade initialization, but this is less clean and may cause other issues.

### Option C: Pre-configure in Scene Editor
Set `enable_grenades = true` in the Enemy10 scene file, but this violates the requirement "by default enemies have no grenades".

## Verification Steps

After fix:
1. Run at HARD difficulty
2. Look for log: `GrenadeThrowerComponent initialized for Enemy10` (add this log)
3. Look for log: `Grenade trigger:` when trigger conditions are met
4. Look for log: `Threw frag grenade:` when grenade is thrown

## Timeline

1. Initial implementation created `THROWING_GRENADE` state and `GrenadeThrowerComponent`
2. Level configuration added to `building_level.gd`
3. Testing revealed no enemy grenades being thrown
4. Root cause analysis identified Godot lifecycle timing issue
5. Fix implemented: Added `configure_grenades()` method for late initialization
