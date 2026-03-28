# Case Study: Issue #1684 — Camera Limits on Building Map (Right/Bottom Walls)

## Summary

**Issue:** The right and bottom walls on the Building map did not restrict the camera — players could scroll the camera past these walls into the void.

**Regression introduced:** The fix applied in the 3rd attempt (`ConfigureBuildingCameraLimits` in `LevelInitFallback.cs`) broke camera limits on **all other maps** that use the `LevelInitFallback` component (Полигон/TestTier, Доки/DocksLevel, CityLevel, FactoryLevel, SewerLevel, RevolverLevel, RailwayStationLevel).

---

## Timeline of Events

| Attempt | Commit | Action | Result |
|---------|--------|--------|--------|
| 1st | `eec0f018` | Verified camera limit values in BuildingLevel.tscn documentation | No code change, issue unchanged |
| 2nd | `ce900887` | Added Camera2D subnode property override to `BuildingLevel.tscn` | Issue not fixed — scene override not reliably applied at runtime |
| 3rd | `76956769` | Added `ConfigureBuildingCameraLimits()` to `LevelInitFallback.cs`, called **unconditionally** | Building fix worked, but **broke all other maps** — camera limits on Polygon, Docks, etc. set to Building map values |
| 4th (this fix) | — | Added `BuildingLevel` name guard to `ConfigureBuildingCameraLimits()` call | Only applies on BuildingLevel |

---

## Root Cause Analysis

### Original Issue

The `Camera2D` node lives in `Player.tscn` with default limits `limit_right=4128, limit_bottom=3088`. The Building map is smaller (right wall at x=2464, bottom wall at y=2064). The GDScript `_configure_camera()` in `BuildingLevel.gd` was supposed to override these limits at runtime, but due to the Godot 4.3 binary tokenization bug ([godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150)), GDScript `_ready()` sometimes fails to execute, leaving the default (large) limits intact.

### Regression Root Cause

`LevelInitFallback.cs` exists in 8 level scenes:
- `BuildingLevel.tscn` (the target)
- `TestTier.tscn` (Полигон)
- `DocksLevel.tscn` (Доки)
- `CityLevel.tscn`
- `FactoryLevel.tscn`
- `SewerLevel.tscn`
- `RevolverLevel.tscn`
- `RailwayStationLevel.tscn`

The `ConfigureBuildingCameraLimits()` call at line 120 (3rd attempt code) was placed **before** any level-name guard, so it executed on every level that has `LevelInitFallback`. The Building-specific values (right=2464, bottom=2064) were applied to all other maps.

**Contrast with correct pattern:** `ApplyBuildingLevelAmmoConfig()` (line 417) already had the correct guard:
```csharp
if (levelRoot.Name != "BuildingLevel") return;
```

### Evidence from Game Log

```
[18:17:56] [LevelInitFallback] ConfigureBuildingCameraLimits: limits set — left=64 top=64 right=2464 bottom=2064 — Issue #1684
[18:17:56] [LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
[18:17:56] [LevelInitFallback] Полигон loaded (C# fallback) - Tactical Combat Arena
```

The camera limits were set (line 419) before the level name was even logged (line 421), confirming the call was unconditional.

---

## Fix Applied

**File:** `Scripts/Components/LevelInitFallback.cs`

**Change:** Added `BuildingLevel` name check before calling `ConfigureBuildingCameraLimits()`:

```csharp
// Before (broken):
ConfigureBuildingCameraLimits();

// After (fixed):
if (parent.Name == "BuildingLevel")
    ConfigureBuildingCameraLimits();
```

This mirrors the existing pattern used by `ApplyBuildingLevelAmmoConfig`.

---

## Affected Maps (Regression)

The following maps had incorrect camera limits applied by the 3rd attempt fix:
- Полигон (`TestTier.tscn`)
- Доки (`DocksLevel.tscn`)
- Двойной коридор — likely `CityLevel.tscn` or another scene
- CityLevel, FactoryLevel, SewerLevel, RevolverLevel, RailwayStationLevel

All are fixed by the level-name guard.

---

## Game Log Reference

`game_log_20260328_181755.txt` — captured by Jhon-Crow on 2026-03-28, showing the regression with `ConfigureBuildingCameraLimits` executing on Полигон, DocksLevel, and other maps.
