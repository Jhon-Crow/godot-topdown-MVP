# Issue #397 Case Study: Enemy Turns Away When Detecting Player

## Problem Description
User reports: "enemy, when detects the player, suddenly turns away" (Russian: "враг, когда обнаруживает игрока резко отварачивается")

This issue persists after the initial fix attempt in commit `dda239d`.

## Timeline of Events (from game_log_20260203_103332.txt)

### First Detection Event (10:33:36)
```
[10:33:36] [ENEMY] [Enemy1] Memory: medium confidence (0.61) - transitioning to PURSUING
[10:33:36] [ENEMY] [Enemy1] State: IDLE -> PURSUING
[10:33:36] [ENEMY] [Enemy1] PURSUING corner check: angle -39.5°
[10:33:36] [ENEMY] [Enemy1] PURSUING corner check: angle -1.6°
```

### Enemy and Player Positions
- Enemy1: (300, 350)
- Player: approximately (384, 980) based on log entries
- Direction to player: (84, 630)
- Expected angle to face player: ~82° (atan2(630, 84))

### Corner Check Angles Observed
The corner check detected perpendicular opening at -39.5°, which is different from the player direction (~82°).

## Analysis of Code Flow

### Model Rotation Priority System (`_update_enemy_model_rotation()`)
1. **Priority 1**: Face player if visible (`_can_see_player` is true)
2. **Priority 2**: Face player if in COMBAT/PURSUING/FLANKING state (Issue #397 fix)
3. **Priority 3**: Face corner check angle (if `_corner_check_timer > 0`)
4. **Priority 4**: Face velocity direction (if moving)
5. **Priority 5**: Face idle scan targets (if in IDLE state)

### Frame-by-Frame Analysis

**Frame N (Transition frame):**
1. `_update_enemy_model_rotation()` runs with `_current_state == IDLE`
   - Priority 5 (idle scan) or Priority 3 (corner check from PATROL) applies
   - Model may face corner/idle direction
2. `_process_ai_state()` runs
   - `_process_idle_state()` triggers transition to PURSUING via memory
   - `_current_state` becomes PURSUING
   - State change is logged

**Frame N+1:**
1. `_update_enemy_model_rotation()` runs with `_current_state == PURSUING`
   - Priority 2 should apply (face player)
   - Model starts rotating toward player
2. `_process_ai_state()` runs
   - `_process_pursuing_state()` is called
   - `_process_corner_check()` detects perpendicular opening
   - Corner check angle is logged (but doesn't affect rotation due to Priority 2)

## Hypothesis

The fix in commit `dda239d` should work correctly. However, the issue might be:

1. **One-frame delay**: During the transition frame (Frame N), the model still faces the IDLE direction before Priority 2 takes effect in Frame N+1.

2. **Smooth rotation appearance**: The smooth rotation (MODEL_ROTATION_SPEED = 3.0 rad/s) means it takes time to rotate from the IDLE direction to face the player. At 60 FPS, a 90° turn takes ~0.5 seconds.

3. **Build timing**: User may be testing with a build that doesn't include the fix.

## Debug Logging Added

Added tracking for rotation priority changes:
```gdscript
if rotation_reason != _last_rotation_reason:
    _log_to_file("Rotation: %s -> %s, state=%s, target=%.1f°" % [...])
```

This will show:
- When priority changes (e.g., "P5:idle_scan" -> "P2:combat_state")
- What state the enemy is in
- What angle it's targeting

## Next Steps

1. User should download new build with debug logging
2. Reproduce the issue and capture new logs
3. Analyze logs to see if Priority 2 is correctly triggering
4. If Priority 2 isn't triggering, investigate why the condition fails
5. If Priority 2 IS triggering but problem persists, the issue might be visual perception during smooth rotation

## Files

- `game_log_20260203_103332.txt` - Original user-provided log file
