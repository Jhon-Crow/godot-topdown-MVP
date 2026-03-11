# Case Study: Issue #997 — Continued FPS Drop Fix During Shootouts

## Summary

This issue continues the work from PR #980 (Issue #969) to fix FPS drops during shootouts with multiple enemies. The new log file (`game_log_20260311_212307.txt`) shows that despite the 11 fixes from PR #980, the 20-enemy DocksLevel scenario still experiences severe FPS drops (5-7 fps).

## Log Analyzed

| Log file | Duration | FPS drops | Worst FPS | Enemies |
|---|---|---|---|---|
| game_log_20260311_212307.txt | ~2 min | 42 | 1 fps (warmup) / 5 fps (combat) | 20 |

**Session details:**
- Level: DocksLevel (20 enemies)
- Weapon: M16 (high fire rate)
- Difficulty: Easy with invincibility enabled
- Time range: 21:23:07 - 21:25:12

## Key Findings from Log Analysis

### State Cycling Still Active (RCA-17 Unresolved)

The log shows rapid state cycling for enemies without cover access, despite the SUPPRESSED_MIN_DURATION fix from PR #980:

**Example: OpenArea_Patrol2 cycling pattern:**
```
[21:23:12] SUPPRESSED → SEEKING_COVER
[21:23:13] SEEKING_COVER → COMBAT      ← immediate (no cover found)
[21:23:13] COMBAT → RETREATING
[21:23:13] RETREATING → SUPPRESSED     ← immediate (no cover found)
[21:23:14] SUPPRESSED → SEEKING_COVER  ← after 0.5s minimum
... cycle repeats 4+ times per second
```

**Statistics from new log:**
- SEEKING_COVER state transitions: 278
- COMBAT state transitions: 758
- RETREATING state transitions: 664
- Total state transitions: 1,269 in ~2 minutes

### Root Cause: Minimum Duration Only Covers SUPPRESSED

The PR #980 fix (RCA-11) added `SUPPRESSED_MIN_DURATION = 0.5s` but the other states in the cycling chain have no minimum:
1. `SUPPRESSED → SEEKING_COVER` (after 0.5s min) ✅
2. `SEEKING_COVER → COMBAT` (immediate, no cover found) ❌
3. `COMBAT → RETREATING` (immediate) ❌
4. `RETREATING → SUPPRESSED` (immediate, no cover found) ❌

This means the cycle is still only throttled to ~2 cycles/second at best, but in practice enemies cycle faster because SEEKING_COVER and RETREATING exit immediately when no cover is found.

### BloodDecal Burst Spawning

Despite Fix 10 reducing decals from 20→8 (lethal) and 10→4 (non-lethal), the log shows 650 BloodDecal events in ~2 minutes. When multiple enemies die in quick succession, decal bursts still overwhelm the `tree_changed` callback system.

## Fixes Applied

### Fix 12: Add Minimum Durations to SEEKING_COVER and RETREATING States

**Files Modified:** `scripts/objects/enemy.gd`

Added minimum duration tracking to complete the state cycling prevention:

```gdscript
# New constants (line 157-158)
const SEEKING_COVER_MIN_DURATION: float = 0.3
var _seeking_cover_entry_time: float = -999.0

const RETREATING_MIN_DURATION: float = 0.3
var _retreating_entry_time: float = -999.0
```

**Changes to state processing:**
- `_transition_to_seeking_cover()`: Now records entry time
- `_transition_to_retreating()`: Now records entry time
- `_process_seeking_cover_state()`: Checks minimum duration before transitioning to COMBAT
- `_process_retreating_state()`: Checks minimum duration before transitioning to SUPPRESSED/COMBAT

**Expected Impact:**
- Full cycle minimum: 0.5s (SUPPRESSED) + 0.3s (SEEKING_COVER) + 0.3s (RETREATING) = **1.1 seconds minimum per cycle**
- Previous: ~5 cycles/second → Now: **~0.9 cycles/second** = **82% reduction** in state-driven overhead

### Fix 13: Per-Second Rate Limiting for Blood Decals

**Files Modified:** `scripts/autoload/impact_effects_manager.gd`

Added per-second rate limiting to prevent tree_changed floods during multi-kill scenarios:

```gdscript
# New constants (line 57-59)
const MAX_BLOOD_DECALS_PER_SECOND: int = 20
var _blood_decals_this_second: int = 0
var _blood_decal_rate_limit_frame: int = -1
```

**Changes to decal spawning:**
- `_schedule_delayed_decal()`: Now checks and increments per-second counter
- Counter resets every ~60 physics frames (approximately 1 second at 60fps)
- Decals beyond the limit are silently skipped

**Expected Impact:**
- Previous: 35-36 decals/second spikes → Now: **20 decals/second max**
- Reduced `tree_changed` callback overhead by ~43% during kill streaks

## Remaining Architectural Issues (Not Addressed in This PR)

### RCA-14: Sound Propagation O(N) Scans

Every GUNSHOT and CASING_KICK still scans all listeners. Requires spatial partitioning for proper fix.

### RCA-15: All 20 Enemy AI Run Every Physics Frame

The fundamental overhead of 20 AI state machines updating at 60fps remains. Requires LOD-based staggered updates.

## Testing Checklist

- [ ] Verify MiniUzi/M16 no longer causes severe FPS drops with 20 enemies
- [ ] Confirm enemies still seek cover when available (transitions not broken)
- [ ] Confirm SUPPRESSED minimum duration still enforced (RCA-11)
- [ ] Confirm SEEKING_COVER minimum duration enforced (new)
- [ ] Confirm RETREATING minimum duration enforced (new)
- [ ] Confirm blood decals still spawn visually (rate limited but visible)
- [ ] Confirm no gameplay regression (enemies still behave correctly)

## Files Changed

| File | Change |
|---|---|
| `scripts/objects/enemy.gd` | Added SEEKING_COVER_MIN_DURATION, RETREATING_MIN_DURATION with entry time tracking (Fix 12) |
| `scripts/autoload/impact_effects_manager.gd` | Added MAX_BLOOD_DECALS_PER_SECOND rate limiting (Fix 13) |
| `docs/case-studies/issue-997/README.md` | This documentation |
| `docs/case-studies/issue-997/logs/game_log_20260311_212307.txt` | New log file from issue |

## References

- [Issue #997](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/997) — Original bug report
- [PR #980](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/980) — Previous FPS optimization work (Issue #969)
- [Case Study: Issue #969](../issue-969/README.md) — Full analysis with RCA-1 through RCA-17
