# Case Study: Issue #915 — Incorrect Ricochet Detection in Trajectory Glasses (M16 and AK)

## Overview

**Issue Title:** fix очки траектории (fix trajectory glasses)

**Reported Behavior:** The trajectory glasses (очки траектории) incorrectly determine whether ricochet is possible/impossible for M16 and AK. Even at a right angle (90°), the glasses show ricochet is possible (green trajectory), when it should not be.

**Reporter:** Jhon-Crow

**Log Files:**
- `game_log_20260225_015038.txt` — original bug report
- `game_log_20260301_012828.txt` — post-first-fix feedback from Jhon-Crow
- `game_log_20260301_021657.txt` — post-second-fix feedback from Jhon-Crow

---

## Timeline / Sequence of Events

### Original Bug (game_log_20260225_015038.txt)

1. **01:50:47** — Player uses trajectory glasses with MakarovPM (9×18mm). System reads `max_ricochet_angle=20.0` and correctly shows 29.6° as invalid (red).

2. **01:50:58** — Player switches to M16 (AssaultRifle). Trajectory glasses read `max_ricochet_angle=90.0` from 5.45×39mm caliber. Near-right-angle shots (82.5°) incorrectly show as green.

3. **01:52:51** — Player switches to AKGL. Trajectory glasses also read `max_ricochet_angle=90.0` from 7.62×39mm caliber. Same bug.

### First Fix Attempt — max_ricochet_angle = 10.0 (Incorrect)

The initial fix changed both caliber files to `max_ricochet_angle = 10.0`. This was too restrictive and did not align with actual bullet behavior.

### Owner Feedback (game_log_20260301_012828.txt) — 2026-02-28

- M16: ray mostly red even at angles where ricochet should work
- AK: all angles still green (old build, fix not yet in binary)

### Second Owner Feedback (game_log_20260301_021657.txt) — 2026-02-28

- AK: still all green (still old build with 90°)
- M16: still mostly red — **owner notes: "M16 ricochets at almost all angles — check the code"**

The log confirms AK binary still uses old value:
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: AKGL -> max_ricochet_angle=90.0
```

---

## Root Cause Analysis (Complete Investigation)

### Surface Root Cause: Wrong max_ricochet_angle in .tres files

Both `caliber_545x39.tres` and `caliber_762x39.tres` had `max_ricochet_angle = 90.0`.

The trajectory glasses check:
```gdscript
var is_valid_ricochet := weapon_max_angle > 0.0 and impact_angle < weapon_max_angle
```

With `weapon_max_angle = 90.0`, ALL angles 0–89° show as green (valid ricochet).

### Deeper Root Cause: C# Bullet.cs Ignores Caliber Data

Investigation revealed a critical architectural inconsistency:

**GDScript `bullet.gd`** (used by MakarovPM and other GDScript weapons):
- Reads `max_ricochet_angle` from `caliber_data` resource
- MakarovPM has `max_ricochet_angle = 20.0` → glasses and bullet behavior are consistent

**C# `Bullet.cs`** (used by AssaultRifle and AKGL via `scenes/projectiles/csharp/Bullet.tscn`):
- Had `private const float MaxRicochetAngle = 90.0f;` **hardcoded**
- Did NOT read from caliber data resources at all
- Comment: "C# Bullet doesn't use caliber resources"

This means:
1. Trajectory glasses read `max_ricochet_angle = 10.0` from `.tres` file → shows red at most angles
2. Actual bullet (`Bullet.cs`) still uses 90.0 hardcoded → ricochets at all angles with varying probability
3. The visualization was **inconsistent** with actual game behavior

The owner was correct: "M16 ricochets at almost all angles" — because `Bullet.cs` uses 90° hardcoded. The 10° threshold in the trajectory glasses did not match reality.

### Probability Curve in Bullet.cs

`Bullet.cs` uses `CalculateRicochetProbability()`:
```csharp
float normalizedAngle = impactAngleDeg / 90.0f;
float powerFactor = Mathf.Pow(normalizedAngle, 2.17f);
float angleFactor = (1.0f - powerFactor) * 0.9f + 0.1f;
return BaseRicochetProbability * angleFactor;
```

Probability at various angles:
| Angle | Probability |
|-------|-------------|
| 0°    | ~100%       |
| 15°   | ~98%        |
| 45°   | ~80%        |
| 67°   | ~52%        |
| 70°   | ~48%        |
| 80°   | ~24%        |
| 90°   | ~10%        |

At 70°, there's still ~48% ricochet probability — ricochet is meaningfully possible at this angle.

---

## Fix Applied

### Fix 1: Make Bullet.cs Read Caliber Data

Added `CaliberData` exported property to `Bullet.cs`:
```csharp
[Export]
public Resource? CaliberData { get; set; }
```

Added `ApplyCaliberData()` method called in `_Ready()` that reads:
- `max_ricochet_angle`
- `max_ricochets`
- `base_ricochet_probability`
- `velocity_retention`
- `ricochet_damage_multiplier`
- `ricochet_angle_deviation`

Updated `BaseWeapon.cs` to pass `WeaponData.Caliber` to C# bullets when spawning:
```csharp
// Pass caliber data so Bullet.cs reads correct ricochet parameters (Issue #915)
csBulletDirect.CaliberData = WeaponData.Caliber;
```

Now both trajectory glasses AND actual bullet behavior read from the same caliber resource.

### Fix 2: Set Correct max_ricochet_angle for Rifle Calibers

Changed both rifle calibers from `10.0` → `70.0`:

**`caliber_545x39.tres` (5.45×39mm — M16/AssaultRifle)**
Changed: `max_ricochet_angle = 90.0` → `max_ricochet_angle = 70.0`

**`caliber_762x39.tres` (7.62×39mm — AK/AKGL)**
Changed: `max_ricochet_angle = 90.0` → `max_ricochet_angle = 70.0`

Rationale: At 70°, the probability curve gives ~48% ricochet chance — ricochet is meaningfully possible. At 82.5° (the original bug angle), there's only ~16% chance — showing as invalid (red) is correct and user-expected behavior. At angles below 70°, ricochets are common enough to show as valid (green).

### Consistency With Other Calibers
| Caliber | max_ricochet_angle | Notes |
|---------|-------------------|-------|
| 5.45×39mm (M16) | 70° | Fixed — was 90° (original bug), briefly 10° (too restrictive) |
| 7.62×39mm (AK) | 70° | Fixed — was 90° (original bug), briefly 10° (too restrictive) |
| 12.7×55mm STS-130 (RSh-12) | 15° | Unchanged |
| 9×18mm Makarov | 20° | Unchanged — works correctly |
| 9×19mm Parabellum | 20° | Unchanged |
| Buckshot | 35° | Unchanged |

---

## Impact on Gameplay

After this fix:
- Trajectory glasses show **green** (valid ricochet) at angles ≤ 70° for M16 and AK — matching actual `Bullet.cs` probability behavior
- Trajectory glasses show **red** (invalid ricochet) at angles > 70° — near-perpendicular shots where ricochet is unlikely (~24% or less)
- Both the visualization AND actual bullet behavior now use the same `max_ricochet_angle` value from the caliber resource
- Fixes the original bug: 82.5° angle now correctly shows red (was incorrectly showing green before)

---

## Files Modified

1. `resources/calibers/caliber_545x39.tres` — `max_ricochet_angle = 70.0` (was 90.0, then 10.0)
2. `resources/calibers/caliber_762x39.tres` — `max_ricochet_angle = 70.0` (was 90.0, then 10.0)
3. `Scripts/Projectiles/Bullet.cs` — added `CaliberData` property and `ApplyCaliberData()` method
4. `Scripts/AbstractClasses/BaseWeapon.cs` — pass caliber to C# bullet when spawning
5. `tests/unit/test_ricochet.gd` — regression tests updated

---

## Verification

After applying the complete fix:

### M16 (AssaultRifle / 5.45×39mm)
- At 82.5° → shows **red** ✅ (82.5° > 70.0°, low ricochet probability)
- At 29.6° → shows **green** ✅ (29.6° < 70.0°, good ricochet probability)
- At 5.8° → shows **green** ✅ (5.8° < 70.0°, near-perfect ricochet)

### AK-GL (AKGL / 7.62×39mm)
- At 67.0° → shows **green** ✅ (67° < 70.0°, ~52% ricochet probability)
- At 82.5° → shows **red** ✅ (82.5° > 70.0°, low ricochet probability)
