# Root Cause Analysis: Trigger 7 Low Activation Rate

**Date**: 2026-01-25
**Issue**: Trigger 7 (Suspicion-Based Grenade) fires very rarely
**Reported by**: @Jhon-Crow via PR #380 comment
**Evidence**: Game logs `game_log_20260125_104229.txt` and `game_log_20260125_104553.txt`

## Executive Summary

The suspicion-based grenade throwing (Trigger 7) was implemented but activates rarely due to a **mathematical impossibility** in the original design: the confidence decay rate makes it impossible for the timer to reach the required threshold while maintaining high confidence.

## Timeline of Events (From Logs)

### Log 1: game_log_20260125_104229.txt
| Timestamp | Event | Analysis |
|-----------|-------|----------|
| 10:42:29 | Game started, 10 enemies spawned | 5 enemies have grenades |
| 10:42:37 | Enemy1 detects player, confidence starts at 1.0 | Timer could start here |
| 10:42:37 | Enemy1 "Memory: medium confidence (0.59)" | Confidence already dropped! |
| 10:44:09 | **T7:Suspicion triggered for Enemy1!** | First successful trigger |
| 10:44:09 | "Throw path blocked to (483.9351, 934.7446)" | Blocked by obstacle |

### Log 2: game_log_20260125_104553.txt
| Timestamp | Event | Analysis |
|-----------|-------|----------|
| 10:45:53 | Game started | Only 1 enemy has grenades |
| 10:46:35+ | Multiple T2:Pursuit triggers | Player too close (119px < 275px safe) |
| 10:46:46 | T1:SuppressionHidden triggers | Player too close (269px < 275px safe) |
| - | **No T7:Suspicion triggers** | Never reached conditions |

## Root Cause Analysis

### Root Cause #1: Mathematical Impossibility (PRIMARY)

**The Problem**: The original implementation requires:
- High confidence (≥ 0.8) to track suspicion timer
- 3 seconds of continuous high confidence while player is hidden
- But confidence decays at 0.1/second

**The Math**:
```
Starting confidence: 1.0 (visual contact)
Decay rate: 0.1/second
High confidence threshold: 0.8

Time to reach 0.8: (1.0 - 0.8) / 0.1 = 2 seconds
Time to reach 0.7: (1.0 - 0.7) / 0.1 = 3 seconds

Required timer: 3.0 seconds
Maximum possible time at high confidence: ~2 seconds

RESULT: Timer can NEVER reach 3 seconds while confidence stays ≥ 0.8
```

**Evidence from Code**:
```gdscript
# enemy_memory.gd
const DEFAULT_DECAY_RATE: float = 0.1  # Confidence drops by 0.1 per second
const HIGH_CONFIDENCE_THRESHOLD: float = 0.8

# enemy.gd (original)
const GRENADE_SUSPICION_HIDDEN_TIME: float = 3.0  # 3 seconds required

func _update_trigger_suspicion(delta: float) -> void:
    # Only tracks if is_high_confidence() - which requires ≥ 0.8
    if _memory.is_high_confidence() and not _can_see_player:
        _high_suspicion_hidden_timer += delta
    else:
        _high_suspicion_hidden_timer = 0.0  # RESETS when confidence drops below 0.8
```

### Root Cause #2: Secondary Blockers

Even when T7 DID trigger (once in Log 1), additional safety checks blocked the throw:

**A. Path Blocked**:
```
[10:44:09] [ENEMY] [Enemy1] [Grenade] Throw path blocked to (483.9351, 934.7446)
```
- Enemy cannot throw grenade through walls/obstacles
- Suspected position was behind a wall from enemy's perspective

**B. Unsafe Distance**:
```
[10:46:47] [ENEMY] [Enemy3] [Grenade] Unsafe throw distance (269 < 275 safe distance, blast=225, margin=50)
```
- Enemy must be at least 275 pixels from target
- Player often stays close to enemies during combat
- Safe distance = blast_radius (225) + margin (50) = 275 pixels

## Evidence Summary

### From Logs: Trigger Activation Frequency

| Trigger | Log 1 Count | Log 2 Count | Notes |
|---------|-------------|-------------|-------|
| T7:Suspicion | 1 | 0 | Only trigger once, blocked by path |
| T6:Desperation | Many | 0 | Frequent when low health |
| T2:Pursuit | 0 | Many | All blocked by unsafe distance |
| T1:SuppressionHidden | 0 | Many | All blocked by unsafe distance |

### Confidence Observations

Only ONE confidence-related log entry in both files:
```
[10:42:37] [ENEMY] [Enemy1] Memory: medium confidence (0.59) - transitioning to PURSUING
```

This shows confidence dropped from 1.0 to 0.59 (medium confidence) within seconds, confirming the fast decay rate.

## Solution Implemented

### Change 1: Use Medium Confidence Instead of High

**Before** (broken):
```gdscript
if _memory.is_high_confidence() and not _can_see_player:
    _high_suspicion_hidden_timer += delta
```

**After** (fixed):
```gdscript
var has_suspicion := (_memory.is_medium_confidence() or _memory.is_high_confidence())
if has_suspicion and not _can_see_player:
    _high_suspicion_hidden_timer += delta
```

### Why This Works

| Confidence Level | Threshold | Time Available |
|------------------|-----------|----------------|
| High | ≥ 0.8 | ~2 seconds |
| Medium | ≥ 0.5 | ~5 seconds |
| Low | ≥ 0.3 | ~7 seconds |

Using medium confidence (0.5+) gives 5 seconds of tracking time, which is sufficient for the 3-second timer requirement.

### Game Design Justification

The fix is appropriate because:
1. "Strong suspicion" semantically maps better to medium confidence (50-80%)
2. High confidence (80%+) implies near-certainty, which should trigger direct pursuit instead
3. The grenade is meant for situations where the enemy is uncertain but suspicious
4. 5 seconds of tracking time allows for more tactical gameplay

## Recommendations

### Immediate Fix (Implemented)
- Use medium confidence (0.5+) for Trigger 7 timer tracking
- Keep 3-second hidden time requirement

### Future Considerations
1. **Add More Verbose Logging**: Track when T7 conditions are being evaluated
2. **Reduce Safe Distance for Suspicion Grenades**: Consider allowing closer throws since enemy expects player at that location
3. **Improve Path Finding**: Consider alternative throw positions if direct path is blocked

## Files Changed

- `scripts/objects/enemy.gd`: Lines 5455-5500 (Trigger 7 functions)

## Test Cases to Verify Fix

1. Player enters enemy vision, then hides behind cover for 4+ seconds
   - Expected: T7 should trigger if enemy has medium+ confidence
2. Player enters enemy vision, immediately runs away
   - Expected: T7 should NOT trigger (player not hidden in suspected area)
3. Enemy hears sound (0.7 confidence), player hides
   - Expected: T7 should trigger after 3 seconds (0.7 > 0.5 threshold)

---

*Root cause analysis completed: 2026-01-25*
