# Case Study: Issue #397 - Enemy Turns Away When Detecting Player

## Problem Description
When an enemy detects the player (transitions from IDLE to PURSUING state), the enemy's model briefly turns away from the player instead of facing them.

**User Report (Russian):** "враг, когда обнаруживает игрока резко отварачивается" - "the enemy, when detecting the player, sharply turns away"

## Timeline of Investigation

### Initial Analysis
1. The issue was reported as a continuation of Issue #386 (FLANKING state turning away bug)
2. Initial fix extended the #386 solution to COMBAT and PURSUING states

### Log Analysis (game_log_20260203_103332.txt)

**Key Sequence for Enemy1:**
```
[10:33:32] Enemy1 spawned at (300, 350), behavior: GUARD
[10:33:36] Memory: medium confidence (0.61) - transitioning to PURSUING
[10:33:36] State: IDLE -> PURSUING
[10:33:36] PURSUING corner check: angle -39.5°
[10:33:36] PURSUING corner check: angle -1.6°
...
[10:33:42] GLOBAL STUCK for 4.0s, State: PURSUING -> SEARCHING
```

**Player Position at Detection:**
- Player was at approximately (385, 981) when Enemy1 detected them
- Enemy1 was at (324, 402)
- Angle from enemy to player: ~84° (mostly downward/south)

**Observations:**
1. The "corner check" messages continue even in PURSUING state - this is expected (corner checks are calculated but should be IGNORED for rotation)
2. No "ROT_CHANGE" logs appear - this suggests the log was from an older build without the verbose logging
3. The corner check angle (-39.5°) is perpendicular to the enemy's movement direction, NOT the direction to the player

## Technical Analysis

### Rotation Priority System (enemy.gd)
The `_update_enemy_model_rotation()` function uses this priority order:
1. **P1:visible** - Face player if `_can_see_player == true`
2. **P2:combat_state** - Face player if in COMBAT/PURSUING/FLANKING state (Fix for #386, #397)
3. **P3:corner** - Face corner check angle if `_corner_check_timer > 0`
4. **P4:velocity** - Face movement direction if moving
5. **P5:idle_scan** - Face idle scan targets if in IDLE state

### The Fix
```gdscript
# Priority 2: During active combat states, maintain focus on player even without visibility
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING] and _player != null:
    target_angle = (_player.global_position - global_position).normalized().angle()
    has_target = true
```

This should override corner checks (P3) when the enemy is in PURSUING state.

### Hypotheses for Remaining Issue

1. **Timing Issue**: The state change and rotation update may have a one-frame delay
2. **Smooth Rotation**: The enemy smoothly rotates at ~172°/s, so turning 180° takes ~1 second
3. **Multiple Rotation Sources**: Other code paths may be setting model rotation outside `_update_enemy_model_rotation()`

## Files in This Case Study
- `logs/game_log_20260203_103332.txt` - Original log file from user testing
- `README.md` - This analysis document

## Next Steps
1. User needs to test with the latest build that includes verbose ROT_CHANGE logging
2. Log should show whether P2:combat_state priority is being selected
3. If P2 is selected but enemy still turns away, investigate smooth rotation path
