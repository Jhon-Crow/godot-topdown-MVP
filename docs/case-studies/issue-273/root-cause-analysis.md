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
6. **2026-01-24**: User testing revealed additional bugs (see below)

---

## User Feedback Session - 2026-01-24

### Additional Bugs Identified

From game logs (`logs/feedback-20260124/`):

#### Bug 1: Enemy Self-Damage on Grenade Throw

**Symptom**: Enemy throws grenade and immediately dies from the explosion.

**Evidence from logs** (`game_log_20260124_021256.txt`):
```
[02:13:27] [ENEMY] [Enemy10] Threw frag grenade: target=(969.3239, 1385.152), deviation=3.5°, distance=141
[02:13:27] [INFO] [GrenadeBase] Grenade created at (1071.949, 1427.096) (frozen)
[02:13:27] [INFO] [GrenadeBase] LEGACY throw_grenade() called! Direction: (-0.8937, -0.448665), Speed: 140.8 (unfrozen)
[02:13:27] [INFO] [GrenadeBase] Collision detected with Enemy10 (type: CharacterBody2D)
[02:13:27] [INFO] [FragGrenade] Impact detected! Body: Enemy10 (type: CharacterBody2D), triggering explosion
[02:13:27] [ENEMY] [Enemy10] Enemy died (ricochet: false, penetration: false)
```

**Root Cause**:
The `frag_grenade.gd` `_on_body_entered()` function was triggering explosion on `CharacterBody2D` collision, which includes the thrower enemy itself. The grenade's collision mask includes enemies (layer 2), and the grenade spawns close enough to the thrower that it collides immediately.

**Fix**: Modified `frag_grenade.gd` to only explode on `StaticBody2D` and `TileMap` collision, not on `CharacterBody2D`:
```gdscript
# Before (buggy):
if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
    _trigger_impact_explosion()

# After (fixed):
if body is StaticBody2D or body is TileMap:
    _trigger_impact_explosion()
```

**Rationale**: Grenades should explode when hitting walls/obstacles or landing on the ground, not when passing through enemies/player. Characters receive damage from the blast radius, not direct collision.

#### Bug 2: THROWING_GRENADE Shows as UNKNOWN in Debug

**Symptom**: When debug mode is enabled (F7), the enemy's state label shows "UNKNOWN" instead of "THROWING_GRENADE".

**Root Cause**: The `_get_state_name()` function in `enemy.gd` was missing a case for `AIState.THROWING_GRENADE`.

**Fix**: Added the missing case:
```gdscript
AIState.THROWING_GRENADE:
    return "THROWING_GRENADE"
```

Also added debug info for grenade count:
```gdscript
if _current_state == AIState.THROWING_GRENADE:
    if _grenade_thrower:
        var grenades_left := _grenade_thrower.offensive_grenades + _grenade_thrower.flashbang_grenades
        state_text += "\n(GRENADES: %d)" % grenades_left
```

#### Verification: Grenade Configuration

**User question**: Are all enemies at HARD difficulty on Building level equipped with grenades?

**Answer**: No, and this is **correct per the original issue requirements**. The original issue specified:
> "дай 2 наступательные гранаты врагу находящемуся на карте здание в помещении main hall."
> Translation: "give 2 offensive grenades to the enemy located on the Building map in the main hall room."

Only **Enemy10** (the enemy in the main hall) is configured with grenades, which matches the requirement.

**Evidence from logs**:
```
[02:12:56] [ENEMY] [Enemy10] Grenade system configured: offensive=2, flashbangs=0
```

No other enemies show grenade configuration logs.

#### Verification: GOAP Integration

**User question**: Is the new behavior integrated into the existing GOAP system?

**Answer**: Yes. The GOAP world state properly tracks grenade-related information:

```gdscript
_goap_world_state["has_grenades"] = _grenade_thrower != null and _grenade_thrower.has_grenades()
_goap_world_state["is_throwing_grenade"] = _current_state == AIState.THROWING_GRENADE
```

The grenade throw check is called from `IN_COVER` and `SUPPRESSED` states, which aligns with the tactical behavior described in the issue requirements.
