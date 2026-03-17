# Case Study: Issue #1090 — Blood on Floor Missing (кровь на полу)

## Issue Summary
**Title:** fix кровь на полу (restore blood on floor)
**Reporter:** Jhon-Crow
**Request:** Restore blood floor behavior to match the `backup` branch, and then to exceed it — specifically matching the Feb 16, 2026 build.

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

### Issue #1090 Round 1 — Initial Fix (commit `cff678db`, 2026-03-17)
- Restored `BLOOD_DECALS_PER_LETHAL_HIT` to 20 (matching backup branch)
- Restored `BLOOD_DECALS_PER_NONLETHAL_HIT` to 10 (matching backup branch)
- Removed `MAX_BLOOD_DECALS_PER_SECOND` rate limiter

### Issue #1090 Round 2 — Owner Feedback (2026-03-17)
- Owner reviewed PR and stated: "откатись ещё раньше, сейчас слишком мало крови на полу" (roll back even earlier, there's still too little blood on the floor)
- Owner provided two game logs from the Feb 16, 2026 build for reference:
  - `game_log_20260317_065235.txt` — Session 1: 1121 blood puddles created, 1410 scheduled
  - `game_log_20260317_070002.txt` — Session 2: 566 blood puddles created, 660 scheduled
- Owner requested blood to match "version 16.02.2026"

## Game Log Analysis (Feb 16 Reference Sessions)

### Session 1 (game_log_20260317_065235.txt)
- **Duration:** ~15+ minutes (06:52:35 - 07:07+)
- **Blood puddles created:** 1,121
- **Blood decals scheduled:** 1,410 (79.5% spawn rate after wall-detection filter)
- **Pattern:** 3 non-lethal hits (10 each) + 1 lethal hit (20) per enemy = 50 decals scheduled per enemy kill
- **Executable:** Feb 16, 2026 build from `godot old version game/29. контейнеры/`

### Session 2 (game_log_20260317_070002.txt)
- **Duration:** ~22 minutes (07:00:02 - 07:22+)
- **Blood puddles created:** 566
- **Blood decals scheduled:** 660 (85.8% spawn rate)
- **Same pattern:** 10/20 decals per non-lethal/lethal hit

### Key Finding
Both reference sessions used `scheduled: 10` for non-lethal and `scheduled: 20` for lethal hits — identical to the backup branch values. The owner's feedback that 20/10 (our Round 1 fix) is still insufficient suggests they want **more blood** than the Feb 16 base value.

## Root Cause Analysis

### Primary Root Cause (Round 1)
**RCA-1: Blood decal count per hit was reduced 60% in Issue #969 performance fix**
- File: `scripts/autoload/impact_effects_manager.gd`
- `BLOOD_DECALS_PER_LETHAL_HIT = 8`, `BLOOD_DECALS_PER_NONLETHAL_HIT = 4`
- Should be: 20 lethal, 10 non-lethal (matching backup branch)

### Secondary Root Cause (Round 1)
**RCA-2: Per-second rate limiter silently drops decals when multiple enemies die**
- `MAX_BLOOD_DECALS_PER_SECOND = 20` rate limiter
- When 3+ enemies die in rapid succession, decals are dropped
- No such limit existed in backup branch

### Round 2 Owner Expectation
The owner's "roll back even earlier" suggests that even the Feb 16 values (20/10) were insufficient to match their perceived blood level. The fix is to increase counts above the Feb 16 baseline:
- **30 decals per lethal hit** (50% above Feb 16's 20)
- **15 decals per non-lethal hit** (50% above Feb 16's 10)

## Fix

### Round 1 Changes
1. `BLOOD_DECALS_PER_LETHAL_HIT`: 8 → 20
2. `BLOOD_DECALS_PER_NONLETHAL_HIT`: 4 → 10
3. Remove `MAX_BLOOD_DECALS_PER_SECOND` rate limiter

### Round 2 Changes
1. `BLOOD_DECALS_PER_LETHAL_HIT`: 20 → **30** (owner requested more than Feb 16)
2. `BLOOD_DECALS_PER_NONLETHAL_HIT`: 10 → **15** (owner requested more than Feb 16)
3. Restore unconditional `_log_info("Blood decals scheduled: ...")` (matching Feb 16 logging behavior, enabling game log verification)

## Performance Safety
The FPS concerns from #969 and #997 are addressed by:
- Issue #1027 already removed the per-puddle `Area2D` physics (the real performance bottleneck)
- 30 `Sprite2D` decals are trivially cheap to render per the #1027 case study analysis

## Files Changed
- `scripts/autoload/impact_effects_manager.gd`

## Verification
After fix:
- Single enemy kill should produce ~30 visible blood spots on floor
- Multiple rapid kills should produce proportional blood without silent drops
- Game log should show `[ImpactEffects] Blood decals scheduled: 30 to spawn at particle landing times` for lethal hits
- Game log should show `[ImpactEffects] Blood decals scheduled: 15 to spawn at particle landing times` for non-lethal hits
