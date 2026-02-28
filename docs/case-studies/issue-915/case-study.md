# Case Study: Issue #915 — Incorrect Ricochet Detection in Trajectory Glasses (M16 and AK)

## Overview

**Issue Title:** fix очки траектории (fix trajectory glasses)

**Reported Behavior:** The trajectory glasses (очки траектории) incorrectly determine whether ricochet is possible/impossible for M16 and AK. Even at a right angle (90°), the glasses show ricochet is possible (green trajectory), when in fact it should be impossible (red).

**Reporter:** Jhon-Crow

**Log File:** `game_log_20260225_015038.txt` (63,856 lines)

---

## Timeline / Sequence of Events

1. **01:50:47** — Player starts using trajectory glasses with MakarovPM (Makarov pistol). The system correctly uses `max_ricochet_angle=20.0` and shows ricochet as invalid at angles > 20°.

2. **01:50:58** — Player switches to M16 (AssaultRifle weapon). Trajectory glasses weapon reference is updated.

3. **01:50:59** — Trajectory glasses activate. The system reads `max_ricochet_angle=90.0` from AssaultRifle's caliber (5.45x39mm). At an impact angle of 28.4° (valid) and also 61.7° (incorrectly shown as valid).

4. **01:52:51** — Player switches to AK+GL (AKGL weapon). Trajectory glasses also read `max_ricochet_angle=90.0` from AK's caliber (7.62x39mm). Same issue persists.

5. **01:53:55** — Second activation of trajectory glasses with AssaultRifle. Shows angles of **82.5°** as valid/green for ricochet — at near-right angles! This is physically wrong.

---

## Evidence from Game Log

### Makarov PM (Correct Behavior):
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: MakarovPM -> max_ricochet_angle=20.0
[TrajectoryGlasses] seg 0 (bounce 0/1): impact_angle=29.6, weapon_max_angle=20.0, is_valid=false, final_seg=false
```
✅ 29.6° > 20.0° → correctly marked as invalid (red)

### AssaultRifle / M16 (Incorrect Behavior):
```
[TrajectoryGlasses] _get_weapon_max_ricochet_angle: AssaultRifle -> max_ricochet_angle=90.0
[TrajectoryGlasses] seg 0 (bounce 0/5): impact_angle=61.7, weapon_max_angle=90.0, is_valid=true, final_seg=false
[TrajectoryGlasses] seg 0 (bounce 0/5): impact_angle=82.5, weapon_max_angle=90.0, is_valid=true, final_seg=false
```
❌ 61.7° < 90.0° → incorrectly marked as valid (green)
❌ 82.5° < 90.0° → incorrectly marked as valid (green, near right angle!)

---

## Root Cause Analysis

### Problem Location
The bug is in the **caliber data resource files**:
- `resources/calibers/caliber_545x39.tres` (5.45×39mm — used by M16/AssaultRifle)
- `resources/calibers/caliber_762x39.tres` (7.62×39mm — used by AK/AKGL)

Both files have `max_ricochet_angle = 90.0`, meaning they allow ricochet at any angle up to 90°.

### How The Visualization Works
In `scripts/effects/trajectory_glasses_effect.gd`, line 410:
```gdscript
var is_valid_ricochet := weapon_max_angle > 0.0 and impact_angle < weapon_max_angle
```

When `weapon_max_angle = 90.0` and `impact_angle = 82.5`:
- `90.0 > 0.0` = `true`
- `82.5 < 90.0` = `true`
- `is_valid_ricochet = true` → **shows green (ricochet possible)**

This is visually incorrect because at 82.5°, the ricochet probability is extremely low (~10%).

### Why `max_ricochet_angle = 90.0` Was Set

The value of 90° for rifle calibers was likely set because the actual `_calculate_ricochet_probability()` function in `caliber_data.gd` applies a probability curve:
```
probability = 0.9 * (1 - (angle/90)^2.17) + 0.1
```

At 90°, this gives ≈10%, not 0%. So the caliber data `max_ricochet_angle=90.0` was configured to allow the probability curve to work at all angles. However, this makes the trajectory glasses show ALL angles (0-89°) as green.

### Real-World Physics

High-velocity rifle rounds tend to ricochet at much shallower angles than pistol rounds:
- **Pistol rounds** (9x18mm, 9x19mm): ricochet commonly at angles up to ~20°
- **Rifle rounds** (5.45x39mm, 7.62x39mm): due to higher velocity and energy, ricochet typically only at very shallow angles (< 10-15°)
- **Comparison in game**: 12.7x55mm (RSh-12 revolver) correctly set at 15°

Reference: This behavior is consistent with Arma 3 ballistics documentation (referenced in the caliber_data.gd comments).

---

## Proposed Fix

Set realistic `max_ricochet_angle` values in the caliber data for rifle rounds:

### `caliber_545x39.tres` (5.45×39mm — M16/AssaultRifle)
Change: `max_ricochet_angle = 90.0` → `max_ricochet_angle = 10.0`

Rationale: 5.45×39mm is a high-velocity round (~880 m/s muzzle velocity). Real-world data shows these rounds typically ricochet only at angles ≤ 10° from the surface.

### `caliber_762x39.tres` (7.62×39mm — AK/AKGL)
Change: `max_ricochet_angle = 90.0` → `max_ricochet_angle = 10.0`

Rationale: 7.62×39mm has similar characteristics, though slightly lower velocity. Setting it to 10° matches the same conservative angle as 5.45×39mm.

### Impact on Gameplay
- The trajectory glasses will now show red (invalid) for most impact angles with M16/AK, matching real-world expectations.
- The actual ricochet mechanics in `bullet.gd` are also affected by this change — bullets will only ricochet at very shallow angles (< 10°) which is more realistic.
- Makarov PM at 20° remains unchanged (already correct).
- RSh-12 at 15° remains unchanged (already correct).

---

## Files to Modify

1. `resources/calibers/caliber_545x39.tres` — set `max_ricochet_angle = 10.0`
2. `resources/calibers/caliber_762x39.tres` — set `max_ricochet_angle = 10.0`
3. `tests/unit/test_trajectory_glasses.gd` — update/add tests for caliber-specific ricochet limits

---

## Verification

After the fix:
- At 82.5° with AssaultRifle → should show red (82.5° > 10.0°)
- At 5° with AssaultRifle → should show green (5° < 10.0°)
- At 15° with MakarovPM → should still show red (15° < 20.0°, now becomes valid; wait, 15° < 20° = valid, which is correct for Makarov at that angle)
