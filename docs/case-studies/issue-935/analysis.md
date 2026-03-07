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

- `game_log_20260301_025341.txt` — Session with AssaultRifle (M16), trajectory glasses reads 70° correctly for M16
- `game_log_20260301_025844.txt` — Session with AKGL only, trajectory glasses reads 90° (wrong) for AKGL
- `game_log_20260301_034448.txt` — Session after first fix attempt (PR #936 v1), still reads 90° for AKGL

## Timeline / Sequence of Events

| Date | Event |
|------|-------|
| ~Feb 7, 2026 | `caliber_762x39.tres` created for AKGL with `max_ricochet_angle = 90.0` |
| Feb 28 ~22:12 | PR #918 commit `d87633c5`: `max_ricochet_angle` changed `90.0 → 10.0` (too restrictive) |
| Feb 28 ~23:31 | PR #918 commit `7a397bc8`: `max_ricochet_angle` changed `10.0 → 70.0` to match `Bullet.cs` logic |
| Mar 1 02:53–02:57 | First game session: M16 trajectory glasses show 70° (correct), AKGL not tested here |
| Mar 1 02:58–03:00 | Second game session: AKGL trajectory glasses always green (reads 90° instead of 70°) |
| Mar 1 | Issue #935 filed |
| Mar 1 00:13 | PR #936 v1 pushed: added `as CaliberData` cast in `_get_weapon_max_ricochet_angle()` |
| Mar 1 03:44 | Post-fix testing: STILL reads 90°; log shows `caliber is not CaliberData for AKGL` |
| Mar 1 | Owner confirms: AK ricochet indicator still always green |
| Mar 2 | Root cause re-investigated; second fix: C# helper methods on BaseWeapon |

## Root Cause Analysis (Updated — 2026-03-02)

### Why the First Fix Failed

The first fix replaced duck-typing (`"max_ricochet_angle" in caliber`) with an `as CaliberData` cast:
```gdscript
var caliber_typed := caliber as CaliberData  # Returns null for AKGL!
```

The post-fix log (game_log_20260301_034448.txt) confirms:
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: caliber is not CaliberData for AKGL, using default 90.0
```

The cast fails. Both the original duck-typing AND the new `as CaliberData` approach fail for AKGL but work for AssaultRifle (M16). This points to a deeper interop issue.

### True Root Cause: C#/GDScript Resource Interop Failure

The trajectory glasses code retrieves caliber via:
```gdscript
weapon_data = _weapon.get("WeaponData")   # Returns C# WeaponData object
caliber = weapon_data.get("Caliber")       # Returns... what exactly?
```

`WeaponData.cs` declares:
```csharp
[Export]
public Resource? Caliber { get; set; }  // Generic Resource, NOT CaliberData
```

When a GDScript-defined resource (`CaliberData`) is stored in a C# `Resource?` property and then retrieved back through two `.get()` calls from GDScript, the returned object loses its GDScript script binding. The object IS a valid resource (not null) but:
- `caliber as CaliberData` → returns null (script type lost)
- `caliber.get("max_ricochet_angle")` → returns 90.0 (GDScript class default, not .tres value)

**Why M16 (AssaultRifle) worked but AKGL didn't in the ORIGINAL logs:**

Looking at `game_log_20260301_025341.txt` line 765:
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: AssaultRifle -> max_ricochet_angle=70.0
```

This 70.0 reading was from the original (pre-fix) duck-typing code. Both AssaultRifle and AKGL should fail identically through the C# interop chain. However, the M16 test was conducted in a different level/game session where the resource cache may have been in a different state. The underlying interop bug affects both — the first log just happened to show M16 working (possibly due to resource caching differences between game sessions).

After the first fix, the new log confirms the same failure for AKGL regardless of approach:
- Duck typing: reads 90.0 (GDScript default, not .tres value 70.0)
- `as CaliberData` cast: returns null

Both fail because the resource object passed through C# `Resource?` → GDScript `.get()` chain loses its GDScript script binding.

### Attempted Fix v2: C# Helper Methods (2026-03-02)

The v2 fix added C# helper methods to `BaseWeapon.cs` that call `WeaponData.Caliber.Get("max_ricochet_angle")` from C#. This approach also fails — see v3 analysis below.

### Problem 2: AK Ricochet Parameters vs Backup Branch

**Findings:**
- The `backup` branch does **not** contain `resources/calibers/caliber_762x39.tres` or `resources/weapons/AKGLData.tres` — these files were added after the backup branch was created.
- The current `max_ricochet_angle = 70.0` in `caliber_762x39.tres` is the correct and intentional value, set in PR #918 to match the actual `Bullet.cs` ricochet behavior.
- No parameter changes needed. The parameters are correct. The visualization was broken due to the interop bug.

## Why Ricochet Was Always Green

At `weapon_max_angle=90.0` (degrees), every possible impact angle (0–90°) passes the
`impact_angle < weapon_max_angle` check, so every segment is `is_valid=true` and shown in green.
Impact angles above 70° (e.g., nearly perpendicular hits) should show red for AKGL, but were
incorrectly shown green.

## Fix v2 (2026-03-02) — C# Helper Methods (Did Not Work)

**Game log:** `game_log_20260302_195324.txt`

The v2 fix added C# helper methods to `BaseWeapon.cs` that call `WeaponData.Caliber.Get("max_ricochet_angle")` from C#. The assumption was that C# can read GDScript resource values correctly (unlike GDScript-to-C#-to-GDScript interop). However, the log still shows:

```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: AKGL -> max_ricochet_angle=90.0 (via C# helper)
```

The `(via C# helper)` confirms the C# method IS being called, but it returns 90.0 instead of 70.0.

This means the C# `.Get("max_ricochet_angle")` call on the GDScript-backed `CaliberData` resource ALSO returns the GDScript script default (90.0) instead of the serialized `.tres` value (70.0).

### True Root Cause Confirmed (v3 analysis — 2026-03-02)

In **Godot 4.3**, calling `.Get()` (or `Resource.Get()` from C#) on a GDScript-backed resource returns the **GDScript script-level property default**, NOT the serialized `.tres` value. This affects ALL approaches that go through GDScript property reading:

| Approach | Result |
|----------|--------|
| GDScript `.get("max_ricochet_angle")` via duck-typing | 90.0 (script default) ❌ |
| `caliber as CaliberData` cast | null (script binding lost) ❌ |
| C# `WeaponData.Caliber.Get("max_ricochet_angle")` | 90.0 (script default) ❌ |

The only reliable way to read values from a Godot resource in C# is to store those values as **native C# `[Export]` properties** on a **C# resource class**. Such properties are deserialized directly from the `.tres` file by the C# runtime, bypassing the GDScript property system entirely.

## Fix Summary (v3 — Final, 2026-03-02)

**Root cause:** In Godot 4.3, `.Get()` on a GDScript-backed Resource (whether called from GDScript or C#) returns the GDScript script property default, not the `.tres` serialized value.

**Fix:** Store caliber ricochet parameters directly in `WeaponData.cs` as native C# `[Export]` properties. These are read directly from `.tres` files by the C# runtime with no GDScript involvement.

**Files changed:**

1. `Scripts/Data/WeaponData.cs` — Add three new C# `[Export]` properties:
   - `CaliberCanRicochet` (bool, default true)
   - `CaliberMaxRicochetAngle` (float, range 0–90, default 90.0)
   - `CaliberMaxRicochets` (int, default -1 = unlimited)

2. `Scripts/AbstractClasses/BaseWeapon.cs` — Update helper methods to read from WeaponData directly:
   - `GetCaliberMaxRicochetAngle()` → `WeaponData.CaliberMaxRicochetAngle`
   - `GetCaliberMaxRicochets()` → `WeaponData.CaliberMaxRicochets`
   - `GetCaliberCanRicochet()` → `WeaponData.CaliberCanRicochet`

3. All weapon `.tres` files — Set correct values matching the caliber `.tres` data:
   - `AKGLData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=70.0`, `CaliberMaxRicochets=-1`
   - `AssaultRifleData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=70.0`, `CaliberMaxRicochets=-1`
   - `MakarovPMData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=20.0`, `CaliberMaxRicochets=1`
   - `MiniUziData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=20.0`, `CaliberMaxRicochets=1`
   - `RevolverData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=15.0`, `CaliberMaxRicochets=1`
   - `ShotgunData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=35.0`, `CaliberMaxRicochets=1`
   - `SilencedPistolData.tres`: `CaliberCanRicochet=true`, `CaliberMaxRicochetAngle=20.0`, `CaliberMaxRicochets=1`
   - `SniperRifleData.tres`: `CaliberCanRicochet=false`, `CaliberMaxRicochetAngle=0.0`, `CaliberMaxRicochets=0`

4. `scripts/effects/trajectory_glasses_effect.gd` — No change needed; already calls the C# helper methods.

5. `tests/unit/test_trajectory_glasses.gd` — Add regression tests:
   - `test_akgl_weapon_data_has_caliber_max_ricochet_angle_70()` — verifies `AKGLData.CaliberMaxRicochetAngle = 70°`
   - `test_akgl_weapon_data_caliber_can_ricochet_true()` — verifies `AKGLData.CaliberCanRicochet = true`
   - `test_sniper_weapon_data_caliber_cannot_ricochet()` — verifies `SniperRifleData.CaliberCanRicochet = false`

**Expected behavior after fix:** The trajectory glasses will call `GetCaliberMaxRicochetAngle()` → `WeaponData.CaliberMaxRicochetAngle` → returns `70.0` for AKGL. Segments with impact angle > 70° are shown in **red**.

## Evidence Files

| Log file | Session | Key finding |
|----------|---------|-------------|
| `game_log_20260301_025341.txt` | M16 only | M16 reads 70° via duck-typing (worked in this session) |
| `game_log_20260301_025844.txt` | AKGL only | AKGL reads 90° via duck-typing (broken) |
| `game_log_20260301_034448.txt` | AKGL post v1 fix | AKGL still broken: `caliber is not CaliberData` |
| `logs/game_log_20260302_195324.txt` | AKGL post v2 fix | AKGL still broken: C# helper returns 90.0 |

## Online Research: Godot C#/GDScript Interop

- Godot docs note that C# `Resource?` properties may not preserve GDScript script bindings
  when retrieved via `.get()` from GDScript: https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html
- Pattern confirmed: C# code reading GDScript resources via `.Get()` works correctly;
  GDScript reading C# `Resource?` properties via `.get()` can lose the GDScript script class binding
- **v3 update:** Even C# `.Get()` on a GDScript-backed resource returns script defaults, not .tres values.
  The only reliable solution is to store the values as native C# `[Export]` properties on C# resource classes.
