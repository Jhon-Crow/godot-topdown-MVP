# Case Study: Issue #935 — Fix Ricochet Glasses Always Green for AK

## Overview

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/935
**Title:** fix очки рикошета для AK (fix ricochet glasses for AK)
**Reported:** 2026-03-01
**Fixed in:** PR #936

Two problems reported:
1. The trajectory glasses (ricochet visualization) always shows green segments for the AKGL weapon, regardless of actual ricochet feasibility.
2. Check whether AK ricochet parameters were changed and, if so, restore them to the `backup` branch values.

## Evidence Files

- `game_log_20260301_025341.txt` — Session with AssaultRifle (M16), then AKGL
- `game_log_20260301_025844.txt` — Session with AKGL only

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| ~Feb 7, 2026 | `caliber_762x39.tres` created for AKGL with `max_ricochet_angle = 90.0` |
| Feb 28 ~22:12 | PR #918 commit `d87633c5`: `max_ricochet_angle` changed `90.0 → 10.0` (too restrictive) |
| Feb 28 ~23:31 | PR #918 commit `7a397bc8`: `max_ricochet_angle` changed `10.0 → 70.0` to match `Bullet.cs` logic |
| Mar 1 02:53–02:57 | First game session: trajectory glasses always green for both M16 and AKGL |
| Mar 1 02:58–03:00 | Second game session: trajectory glasses always green for AKGL (`weapon_max_angle=90.0`) |
| Mar 1 | Issue #935 filed |

## Root Cause Analysis

### Problem 1: Trajectory Glasses Always Green

The log clearly shows:
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: AKGL -> max_ricochet_angle=90.0
[TrajectoryGlasses] seg 0 (bounce 0/5): impact_angle=17.7, weapon_max_angle=90.0, is_valid=true
```

The `caliber_762x39.tres` resource has `max_ricochet_angle = 70.0`, but the trajectory glasses
reads `90.0` — the fallback constant `MAX_RICOCHET_ANGLE = 90.0`.

**Location:** `scripts/effects/trajectory_glasses_effect.gd`, functions `_get_weapon_max_ricochet_angle()` and `_get_weapon_max_ricochets()`

**Root cause:** Godot C#/GDScript interop property access issue. When caliber data is
retrieved via double indirection:
```gdscript
weapon_data = _weapon.get("WeaponData")   # C# object → C# WeaponData
caliber = weapon_data.get("Caliber")       # C# WeaponData → GDScript CaliberData resource
```

The returned `caliber` is a valid `CaliberData` resource, but subsequent attempts to read
its GDScript-defined `@export` properties via `.get("max_ricochet_angle")` silently return
the GDScript default value (`90.0`) instead of the value stored in the `.tres` file (`70.0`).
The `"max_ricochet_angle" in caliber` check also failed to trigger the update, so the
fallback `MAX_RICOCHET_ANGLE = 90.0` was used.

The working pattern in `bullet.gd` (line 623) uses a **typed variable** and direct property
access, which resolves the GDScript class correctly:
```gdscript
max_angle = caliber_data.max_ricochet_angle if "max_ricochet_angle" in caliber_data else DEFAULT_MAX_RICOCHET_ANGLE
```

Here `caliber_data` is a direct GDScript `@export var`, not obtained via C# interop.

**Fix:** Cast caliber to `CaliberData` and access properties directly:
```gdscript
var caliber_typed := caliber as CaliberData
if caliber_typed == null:
    return MAX_RICOCHET_ANGLE
var angle := caliber_typed.max_ricochet_angle
```

This ensures the GDScript class is properly resolved and returns the `.tres` value (70.0).

### Problem 2: AK Ricochet Parameters vs Backup Branch

**Findings:**
- The `backup` branch does **not** contain `resources/calibers/caliber_762x39.tres` or `resources/weapons/AKGLData.tres` — these files were added after the backup branch was created.
- The current `max_ricochet_angle = 70.0` in `caliber_762x39.tres` is the correct and intentional value, set in PR #918 to match the actual `Bullet.cs` ricochet behavior.
- The previous intermediate value of `10.0` would have been too restrictive.
- The `90.0` default was appropriate before caliber-specific limits were introduced, but now that 70° is set in the data file, the trajectory glasses should display it correctly.

**Conclusion:** No parameter changes needed. The parameters are correct. The visualization was broken due to the interop bug.

## Why Ricochet Was Always Green

At `weapon_max_angle=90.0` (degrees), every possible impact angle (0–90°) passes the
`impact_angle < weapon_max_angle` check, so every segment is `is_valid=true` and shown in green.
Impact angles above 70° (e.g., nearly perpendicular hits) should show red for AKGL, but were
incorrectly shown green.

## Online Research: Godot C#/GDScript Interop

- Godot docs confirm that `.get()` on a C# object uses Godot's property interface, which may
  wrap GDScript `Resource` objects differently from when accessed natively in GDScript.
- Using `as CaliberData` cast ensures the GDScript runtime resolves the script class and gives
  full access to all `@export` properties with their stored `.tres` values.
- See also: https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html

## Fix Summary

**File changed:** `scripts/effects/trajectory_glasses_effect.gd`

In `_get_weapon_max_ricochet_angle()` and `_get_weapon_max_ricochets()`:
- Added `as CaliberData` cast before accessing caliber properties
- Replaced `.get("prop")` with direct typed property access (`caliber_typed.prop`)
- This matches the pattern used successfully in `bullet.gd`

After the fix, `_get_weapon_max_ricochet_angle()` will correctly return `70.0` for AKGL,
and the trajectory glasses will show red segments for impact angles > 70°.
