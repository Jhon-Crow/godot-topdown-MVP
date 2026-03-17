# Case Study: Issue #1090 — Blood on Floor Missing (кровь на полу)

## Issue Summary
**Title:** fix кровь на полу (restore blood on floor)
**Reporter:** Jhon-Crow
**Request:** Restore blood floor behavior to match the `backup` branch.

## Timeline of Events

### Original Behavior (backup branch, ~mid-2025)
- `spawn_blood_effect()` in `impact_effects_manager.gd` spawned **20 decals** per lethal hit, **10** per non-lethal
- No per-second rate limit on blood decal spawning
- Blood pools visibly accumulated on the floor after enemy kills

### Issue #969 — FPS Drop Fix (commit `515deee2`, 2026-03-11)
- **Root Cause Found (RCA-12):** With 20 enemies and M16 at 8 hits/sec, 160 decals/sec were being added via `add_child()`, each triggering `SceneTree.tree_changed`, causing 48+ callbacks/sec
- **Fix applied:** Reduced `BLOOD_DECALS_PER_LETHAL_HIT` from 20 → **8**, `BLOOD_DECALS_PER_NONLETHAL_HIT` from 10 → **4**
- **Side effect:** 60% fewer blood decals on floor after kills — blood visually reduced

### Issue #997 — FPS Drop, State Cycling Fix (commit `8198872b`)
- **RCA-16:** Multiple enemies dying in same second caused `tree_changed` floods
- **Fix applied:** Added `MAX_BLOOD_DECALS_PER_SECOND = 20` rate limiter
- **Side effect:** If 3+ enemies die rapidly (3 × 8 = 24 decals attempted), 4 are silently dropped

### Issue #1027 — Physics/FPS Fix (commits `733c0737`, `faac32b9`)
- Further tuned rate limiting, changed window calculation
- Raised `MAX_BLOOD_DECALS` cap from 150 → 300 after user noticed "blood seems less than before"
- Despite cap increase, per-decal count (8/lethal) and rate limiter (20/sec) remained low

### Current State (main branch)
- `BLOOD_DECALS_PER_LETHAL_HIT = 8` (was 20)
- `BLOOD_DECALS_PER_NONLETHAL_HIT = 4` (was 10)
- `MAX_BLOOD_DECALS_PER_SECOND = 20` (no such limit in backup)
- Net result: ~60-80% fewer blood decals visible on floor compared to backup branch

## Root Cause Analysis

### Primary Root Cause
**RCA-1: Blood decal count per hit was reduced 60% in Issue #969 performance fix**
- File: `scripts/autoload/impact_effects_manager.gd`
- Lines 51-55: `BLOOD_DECALS_PER_LETHAL_HIT = 8`, `BLOOD_DECALS_PER_NONLETHAL_HIT = 4`
- Should be: 20 lethal, 10 non-lethal (matching backup branch)

### Secondary Root Cause
**RCA-2: Per-second rate limiter silently drops decals when multiple enemies die**
- File: `scripts/autoload/impact_effects_manager.gd`
- Lines 59-61, 646-656: `MAX_BLOOD_DECALS_PER_SECOND = 20`
- When 3+ enemies die in rapid succession, decals are dropped
- No such limit existed in backup branch

## Fix

Restore decal counts to backup branch values and remove per-second rate limiter:

1. `BLOOD_DECALS_PER_LETHAL_HIT`: 8 → **20**
2. `BLOOD_DECALS_PER_NONLETHAL_HIT`: 4 → **10**
3. Remove `MAX_BLOOD_DECALS_PER_SECOND` rate limiter and associated variables/logic

The FPS concerns from #969 and #997 are addressed by:
- Issue #1027 already removed the per-puddle Area2D physics (the real performance bottleneck)
- `MAX_BLOOD_DECALS = 0` (unlimited) combined with proper `MAX_BLOOD_DECALS` cap if needed
- The original tree_changed flood was the main FPS killer, not decal count per se
- 20 decals on a Sprite2D is trivially cheap per the #1027 analysis

## Files Changed
- `scripts/autoload/impact_effects_manager.gd`

## Verification
After fix:
- Single enemy kill should produce ~20 visible blood spots on floor
- Multiple rapid kills should produce proportional blood without silent drops
- Matches visual behavior of `backup` branch
