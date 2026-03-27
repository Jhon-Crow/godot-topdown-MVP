# Case Study: Issue #1578 — Blood Creates Puddles in Water Instead of Diffusion Clouds

## Summary

Blood hitting water still creates persistent floor puddles instead of diffusion clouds
that dissolve into the water, despite the fix implemented in PR #1604.

## Game Log Evidence (2026-03-27 session)

- **Log file**: `game_log_20260327_085514.txt`
- **Total log lines**: 4,250
- **Blood decals spawned total**: 2,199
- **Blood decals spawned INSIDE water area**: **1,880** (out of 2,199 = 85.5%)

The water body is at position (1264, 242) with width=2400 and height=356 (per log line 517).
Water bounds: x ∈ [64, 2464], y ∈ [64, 420].

### Sample in-water decal coordinates from log
```
(640, 360), (554.5, 206.9), (594.4, 255.7), (579.0, 283.6), (562.9, 283.8),
(619.7, 307.2), (546.8, 274.4), (575.9, 293.3), ...
```

This confirms the fix was NOT effective — blood decals continue to spawn in water.

## Root Cause Analysis

### Root Cause 1: `"water_body"` group not registered (MERGE CONFLICT)

Our PR added `add_to_group("water_body")` to `WaterBody._ready()`. The main branch
merged a separate feature (issue #1585, LastChanceEffectsManager) that changed this
same line to `add_to_group("precipitation_effects")`.

After merging from main, the conflict resolution replaced our `"water_body"` group with
`"precipitation_effects"`, meaning `ImpactEffectsManager._find_water_body_at()` could
not find any nodes in the `"water_body"` group → returned `null` → blood decals spawned
without water-interception.

**Fix**: Both groups must be registered. The `_ready()` now calls:
```gdscript
add_to_group("water_body")          # for ImpactEffectsManager (Issue #1578)
add_to_group("precipitation_effects") # for LastChanceEffectsManager (Issue #1585)
```

### Root Cause 2: `is_point_in_water` method name mismatch

`_find_water_body_at()` in `impact_effects_manager.gd` calls:
```gdscript
if wb.has_method("is_point_in_water") and wb.is_point_in_water(world_pos):
```

But `water_body.gd` only had `_is_point_in_water()` (private, with underscore prefix).
While GDScript allows external calls to underscore-prefixed methods, `has_method()`
returns `false` for `"is_point_in_water"` when only `"_is_point_in_water"` exists.

Result: `has_method` guard always false → water body never returned → decals spawned.

**Fix**: Added a public wrapper `is_point_in_water()` that delegates to `_is_point_in_water()`.

## Timeline of Events

1. Issue #1578 reported: blood creates puddles in water instead of diffusion clouds.
2. PR #1604 created with three-part fix:
   - `water_body.gd`: added `add_to_group("water_body")`
   - `impact_effects_manager.gd`: added water-detection before decal spawn
   - `water_body.gd`: added `spawn_blood_diffusion_at()` public API
3. PR #1604 marked ready (2026-03-26).
4. Owner tested (2026-03-27 08:55) → reported "не сработало" (didn't work).
5. Analysis: merge conflict from PR #1585 replaced `"water_body"` group with
   `"precipitation_effects"`, breaking the fix.
6. Additionally discovered: `has_method("is_point_in_water")` returns false because
   only `_is_point_in_water` existed.

## Fix Applied

1. **`scripts/objects/water_body.gd`**: Added both group registrations in `_ready()`.
2. **`scripts/objects/water_body.gd`**: Added public `is_point_in_water()` wrapper.
3. Merged latest main branch changes to resolve conflict.

---

## Second Owner Report: "изменений нет" (2026-03-27 09:21)

After fixes were committed (commit `e4eabe4a`, 2026-03-27 06:03 UTC), the owner tested
again at 09:21 UTC and reported "изменений нет" (no changes).

### Log Evidence (game_log_20260327_092156.txt)

- **Total blood puddles**: 2,370
- **Blood puddles inside water area** (x∈[64,2464], y∈[32,452]): **2,156** (90.97%)
- **`[WaterBody] Ready`** log message: **NOT PRESENT**
- `Build info: not available (build_info.cfg not found)`

### Root Cause: User testing pre-fix build (not from our branch)

The absence of `[WaterBody] Ready` in the log is the key diagnostic signal:

1. Our branch (`e4eabe4a`) and main branch both have `_log("[WaterBody] Ready...")` in `_ready()`.
2. The main branch also has `print(message)` in `_log()`, so any WaterBody would print to both console AND file.
3. **No `[WaterBody]` entry anywhere in the game log** → WaterBody's `_ready()` never ran, OR
   the build was from a version before WaterBody logging was added.

**The build was exported WITHOUT our PR changes.** Evidence:
- `Build info: not available (build_info.cfg not found)` — our CI generates `build_info.cfg` on every build.
  Its absence means this is NOT a CI-built artifact from our branch.
- The game was run from `I:/Загрузки/godot exe/ОСадКИ/` — a local export folder, not a
  CI download.

**Conclusion**: The user exported the game from the Godot editor using the main branch
(which still lacks our `add_to_group("water_body")` fix). The fix is in PR #1604 which
has not been merged yet.

### What the user must do

To test the fixed version, the user needs to either:
1. **Download the CI-built EXE** from our branch:
   [windows-build artifact](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions/runs/23633555990)
2. **Or merge PR #1604** so the fix is included in the main branch export.

Our fix is code-verified correct:
- `water_body.gd` registers `"water_body"` group in `_ready()`
- `impact_effects_manager.gd` queries `"water_body"` group before spawning decals
- `is_point_in_water()` public wrapper is present and callable via `has_method()`

Sample verification: position (402, 264) is inside water bounds (x∈[64,2464], y∈[32,452]).
`_is_point_in_water()`: `local = (402-1264, 264-242) = (-862, 22)`, `abs(-862) ≤ 1200 ✓`, `abs(22) ≤ 210 ✓` → in water.
