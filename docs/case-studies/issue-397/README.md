# Case Study: Issue #397 - Enemy Turns Away When Detecting Player

## Problem Description
When an enemy detects the player (transitions from IDLE to PURSUING state), the enemy's model briefly turns away from the player instead of facing them.

**User Report (Russian):** "враг, когда обнаруживает игрока резко отварачивается" - "the enemy, when detecting the player, sharply turns away"

## Root Cause Found (2026-02-03)

The debug logging revealed the actual problem: **SEARCHING and ASSAULT states were missing from the rotation priority combat states list**.

### Evidence from Logs

From `game_log_20260203_110137.txt`:
```
[11:01:41] [Enemy1] State: IDLE -> PURSUING
[11:01:41] [Enemy1] ROT_CHANGE: P5:idle_scan -> P2:combat_state, state=PURSUING  (Good - facing player)
...
[11:01:46] [Enemy1] GLOBAL STUCK for 4.0s, State: PURSUING -> SEARCHING
[11:01:46] [Enemy1] ROT_CHANGE: P2:combat_state -> P3:corner, state=SEARCHING  (Bad - facing corner angle!)
```

When an enemy transitioned to SEARCHING state (after being stuck for 4 seconds), they lost the P2:combat_state priority and fell back to P3:corner (corner check direction), which made them turn away from the player.

Similarly:
```
[11:01:47] [Enemy4] GLOBAL STUCK for 4.0s, State: PURSUING -> SEARCHING
[11:01:47] [Enemy4] ROT_CHANGE: P2:combat_state -> P3:corner, state=SEARCHING, target=-90.0°
```

## Technical Analysis

### Rotation Priority System (enemy.gd)
The `_update_enemy_model_rotation()` function uses this priority order:
1. **P1:visible** - Face player if `_can_see_player == true`
2. **P2:combat_state** - Face player if in combat-related state (even without visibility)
3. **P3:corner** - Face corner check angle if `_corner_check_timer > 0`
4. **P4:velocity** - Face movement direction if moving
5. **P5:idle_scan** - Face idle scan targets if in IDLE state

### The Bug
Original P2 condition (line 912):
```gdscript
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING] and _player != null:
```

Missing states:
- **SEARCHING** - "Methodically searching area where player was last seen" - should definitely face player
- **ASSAULT** - "Coordinated multi-enemy assault" - should definitely face player

### The Fix
Updated P2 condition to include SEARCHING and ASSAULT:
```gdscript
# Priority 2: During active combat states, maintain focus on player even without visibility (#386, #397)
# Includes SEARCHING and ASSAULT - enemies should always face player during these states
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT] and _player != null:
```

## Timeline of Investigation

### Phase 1: Initial Analysis
1. Issue reported as continuation of Issue #386 (FLANKING state turning away bug)
2. Initial fix extended #386 solution to COMBAT and PURSUING states
3. Added debug logging (ROT_CHANGE messages) to track rotation priority

### Phase 2: User Testing (2026-02-03)
1. User reported problem persists with new logs
2. Log files: `game_log_20260203_110137.txt`, `game_log_20260203_110542.txt`
3. Debug logging revealed SEARCHING state transition as root cause

### Phase 3: Fix Implementation
1. Added SEARCHING and ASSAULT to rotation priority combat states
2. Condensed debug logging to stay under 5000 line limit

## Files in This Case Study
- `game_log_20260203_103332.txt` - Initial log file from user testing (no ROT_CHANGE logs)
- `game_log_20260203_110137.txt` - Log with verbose rotation logging
- `game_log_20260203_110542.txt` - Additional log with verbose rotation logging
- `README.md` - This analysis document

## Lessons Learned
1. **Complete state coverage matters**: When implementing behavior that should apply to "combat states", all relevant states must be included
2. **Debug logging is essential**: The ROT_CHANGE logging immediately revealed which state transitions caused the problem
3. **State transitions are often the source of bugs**: The bug only manifested when transitioning from PURSUING to SEARCHING
