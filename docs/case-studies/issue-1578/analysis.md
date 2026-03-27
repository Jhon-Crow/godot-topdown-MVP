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
