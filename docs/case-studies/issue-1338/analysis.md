# Case Study: Issue #1338 - Suppressed Enemies Stay in Place Instead of Seeking Cover

## Problem Statement

Suppressed enemies remain stationary while under fire instead of actively moving to cover. The expected behavior is that when an enemy is suppressed (under fire), it should immediately find the nearest cover position hidden from the player and move there.

## Timeline of Events

### Phase 1: Initial Report (2026-03-22 17:17)

- **Log file**: `game_log_20260322_171711.txt`
- **Reporter**: Jhon-Crow (repo owner)
- **Observation**: "подавленные враги должны сразу идти в укрытие" (suppressed enemies should immediately go to cover)
- When the player hides from view, the enemy stops being suppressed and does not seek cover

### Phase 2: First Fix Attempt (commit d5010345)

- Changed suppressed state to transition to `SEEKING_COVER` state when suppression ends
- This was later reverted/modified based on owner feedback

### Phase 3: Owner Feedback on Issue (2026-03-22 18:49)

- Owner requested: "revert retreat behavior to the first commit in the backup branch"
- Owner specified: "return cover search logic - rays are cast from the player, nearest cover to the enemy where rays can't reach is the target cover"

### Phase 4: Second Fix (commit 067ac5f0)

- Added `POST_SUPPRESSION_COVER_DURATION` (3s) timer
- Rewrote `_find_cover_position()` to cast rays from player
- Changed `_transition_to_in_cover()` to `_transition_to_seeking_cover()` when suppression ends
- **Problem**: enemy still stayed in place WHILE suppressed because `velocity = Vector2.ZERO` at start of `_process_suppressed_state()`

### Phase 5: Owner Reports Bug Still Present (2026-03-23 00:32)

- **Log file**: `game_log_20260323_033050.txt`
- **Observation**: "подавленный враг остаётся стоять на месте" (suppressed enemy stays in place)
- Log evidence shows `SUPPRESSED -> IN_COVER` transitions where enemy stays at current position
- Enemy never moves during the SUPPRESSED state because velocity is forced to zero

## Root Cause Analysis

### The Core Problem

In `_process_suppressed_state()`, the very first line was:

```gdscript
velocity = Vector2.ZERO
```

This unconditionally freezes the enemy in place every frame while in the SUPPRESSED state. The enemy cannot move toward cover because its velocity is zeroed out before any movement logic runs.

The SUPPRESSED state was designed as a "pinned down" state where the enemy stays still, but the desired behavior is that the enemy should actively seek cover even while being suppressed.

### Evidence from Game Logs

From `game_log_20260323_033050.txt`:
```
[03:31:12] [ENEMY] [Enemy3] State: IN_COVER -> SUPPRESSED     # enters suppressed, velocity=0
[03:31:14] [ENEMY] [Enemy3] State: SUPPRESSED -> IN_COVER     # exits at same position
[03:31:14] [ENEMY] [Enemy4] State: SUPPRESSED -> IN_COVER     # exits at same position
```

The enemies enter SUPPRESSED and stay motionless. When suppression ends they go to IN_COVER at the same position they were already at (since they were previously in cover). No movement occurs.

### Cover Search Logic

The `_find_cover_position()` function already implements the correct ray-from-player approach:
- Casts rays FROM the player position in all directions
- Finds obstacles that block those rays
- Places cover positions 35px past the obstacle (away from player)
- Verifies the position is reachable and truly hidden from the player
- Picks the nearest hidden cover to the enemy

## Fix (Phase 6)

Rewrote `_process_suppressed_state()` to actively seek cover while suppressed:

1. **Find cover**: calls `_find_cover_position()` if no valid cover is known
2. **Move to cover**: uses `_move_to_target_nav()` to navigate toward cover while visible
3. **Stop when hidden**: sets `velocity = Vector2.ZERO` only after reaching a hidden position
4. **Shoot while moving**: enemy can still fire at player/companion while moving to cover
5. **Exit suppression**: when no longer under fire, transitions to IN_COVER (if hidden) or SEEKING_COVER (if still exposed)

### Expected State Flow After Fix

```
SUPPRESSED (actively moving to cover) -> IN_COVER (arrived, hidden) -> (3s timer) -> PURSUING
```

### Previous Incorrect Flow

```
SUPPRESSED (frozen, velocity=0) -> IN_COVER (same position) -> PURSUING
```

## Data Files

- `game_log_20260322_171711.txt` - Original issue report log
- `game_log_20260323_033050.txt` - Post-first-fix log showing bug still present
