# Case Study: Issue #1338 - Suppressed Enemies Stay in Place Instead of Seeking Cover

## Problem Statement

Suppressed enemies remain stationary after suppression ends instead of moving to a hidden cover position. The expected behavior is that when an enemy is no longer under fire (suppression ends), it should find the nearest cover position hidden from the player and move there.

## Timeline of Events

### Phase 1: Initial Report (2026-03-22 17:17)

- **Log file**: `game_log_20260322_171711.txt`
- **Reporter**: Jhon-Crow (repo owner)
- **Observation**: "подавленные враги должны сразу идти в укрытие" (suppressed enemies should immediately go to cover)
- When the player hides from view, the enemy stops being suppressed and does not seek cover

### Phase 2: First Fix Attempt (commit d5010345)

- Changed suppressed state to transition to `SEEKING_COVER` state
- This was later reverted/modified based on owner feedback

### Phase 3: Owner Feedback on Issue (2026-03-22 18:49)

- Owner requested: "revert retreat behavior to the first commit in the backup branch"
- Owner specified: "return cover search logic - rays are cast from the player, nearest cover to the enemy where rays can't reach is the target cover"

### Phase 4: Second Fix (commit 067ac5f0)

- Added `POST_SUPPRESSION_COVER_DURATION` (3s) timer
- Rewrote `_find_cover_position()` to cast rays from player
- **Bug introduced**: Transition from `SUPPRESSED` went to `IN_COVER` instead of `SEEKING_COVER`

### Phase 5: Owner Reports Bug Still Present (2026-03-23 00:32)

- **Log file**: `game_log_20260323_033050.txt`
- **Observation**: "подавленный враг остаётся стоять на месте" (suppressed enemy stays in place)
- Log evidence shows `SUPPRESSED -> IN_COVER` transitions where enemy stays at current position

## Root Cause Analysis

### The State Machine Bug

The enemy AI state machine has two distinct cover-related states:

1. **`SEEKING_COVER`** - Active state where the enemy:
   - Calls `_find_cover_position()` to locate a hidden position
   - Calls `_move_to_target_nav(_cover_position, combat_move_speed)` to physically move there
   - Transitions to `IN_COVER` once hidden from player

2. **`IN_COVER`** - Passive state where the enemy:
   - Sets `velocity = Vector2.ZERO` (stays stationary)
   - Waits, shoots if player visible, eventually transitions to PURSUING/COMBAT

### The Bug

In `_process_suppressed_state()` (line 1862-1867), when suppression ends (`not _under_fire`):

```gdscript
# Bug: transitions to IN_COVER (stationary) instead of SEEKING_COVER (moves to cover)
_transition_to_in_cover()
```

This skips the movement phase entirely. The enemy changes its internal state to "in cover" but never actually moves to a cover position. It stays at whatever position it was at when suppression ended.

### Evidence from Game Logs

From `game_log_20260323_033050.txt`:
```
[03:31:14] [ENEMY] [Enemy3] State: SUPPRESSED -> IN_COVER   # stays in place
[03:31:14] [ENEMY] [Enemy4] State: SUPPRESSED -> IN_COVER   # stays in place
```

After several seconds, Enemy3 eventually transitions `IN_COVER -> SEEKING_COVER` (line 1775) because the player flanked its position (it was visible from the player). But this is reactive, not proactive — the enemy should have sought cover immediately when suppression ended.

## Fix

Changed line 1867 from `_transition_to_in_cover()` to `_transition_to_seeking_cover()`.

This ensures the enemy:
1. Finds a cover position via `_find_cover_position()` (rays cast from player)
2. Physically moves to that position via navigation
3. Transitions to `IN_COVER` only after arriving and being hidden from the player
4. Stays in cover for the `POST_SUPPRESSION_COVER_DURATION` (3s) before pursuing

### Expected State Flow After Fix

```
SUPPRESSED -> SEEKING_COVER -> (moves to cover) -> IN_COVER -> (3s timer) -> PURSUING
```

### Previous Incorrect Flow

```
SUPPRESSED -> IN_COVER (stays in place, velocity=0) -> (3s timer) -> PURSUING
```

## Data Files

- `game_log_20260322_171711.txt` - Original issue report log
- `game_log_20260323_033050.txt` - Post-first-fix log showing bug still present
