# Issue 88: Enemy AI Combat State Fix - Case Study Analysis

## Issue Summary
The enemy AI has behavior issues in COMBAT and PURSUING states where enemies stand behind cover and infinitely cycle through the timer without actually moving toward the player.

## Feedback History

### Initial Feedback (Round 1)
1. In PURSUING state, enemies just stand still (countdown doesn't progress)
2. In COMBAT state, enemies should come out for direct contact with player, then return to cover if state doesn't change by timer expiry. Currently they just cycle the timer while standing still.

### Follow-up Feedback (Round 2)
Despite first round of fixes, the issue persists: "In PURSUING or COMBAT states, enemies just stand behind cover and infinitely cycle through the timer."

## Root Cause Analysis (Deep Dive)

### Problem 1: PURSUING State - Infinite Timer Loop

**Code Path Analysis:**

Looking at `_process_pursuing_state()`:

```gdscript
# Check if we're waiting at cover
if _has_valid_cover and not _has_pursuit_cover:
    # Currently at cover, wait for 1-2 seconds before moving to next cover
    _pursuit_cover_wait_timer += delta
    velocity = Vector2.ZERO

    if _pursuit_cover_wait_timer >= PURSUIT_COVER_WAIT_DURATION:
        _find_pursuit_cover_toward_player()
        if _has_pursuit_cover:
            # Found cover, will move on next frame
        else:
            # Fallback: transition to COMBAT or FLANKING
```

**Bug 1: Premature "Reached Cover" Detection (LINE 1285)**

```gdscript
if distance < 15.0 or not _is_visible_from_player():
    # Reached cover or hidden from player
```

The condition `or not _is_visible_from_player()` was **catastrophic**:
- When enemy starts from cover, they are ALREADY not visible from player
- This makes the condition immediately true before any movement
- Enemy instantly considers they've "reached" the target cover
- Resets to waiting phase → infinite loop

**Fix:** Removed the visibility check. Only distance matters for "reached cover":
```gdscript
if distance < 15.0:
    # Reached pursuit cover
```

**Bug 2: Finding Cover Too Close to Current Position**

`_find_pursuit_cover_toward_player()` could find a cover position that was only a few pixels away from the enemy's current position:
1. Enemy at position A finds cover B, which is 10 pixels away
2. `_has_pursuit_cover = true`
3. Movement code runs, but `distance < 15.0` is immediately true
4. Enemy "reaches" cover B without moving
5. Back to waiting phase → infinite loop

**Fix:** Added minimum distance check in `_find_pursuit_cover_toward_player()`:
```gdscript
# Skip covers that are too close to current position (would cause looping)
# Must be at least 30 pixels away to be a meaningful movement
if cover_distance_from_me < 30.0:
    continue
```

### Problem 2: COMBAT State - Wrong State Transition When Player Not Visible

**Code Path Analysis:**

In `_process_combat_state()`:

```gdscript
# If can't see player, try flanking or pursue
if not _can_see_player:
    _combat_exposed = false
    _combat_approaching = false
    if enable_flanking and _player:
        _transition_to_flanking()
    else:
        _transition_to_idle()
    return
```

**Bug:** When the player is not visible, the enemy transitions to FLANKING or IDLE instead of PURSUING. This is incorrect because:
- PURSUING state is specifically designed for chasing a player who is not visible
- Going to IDLE completely breaks the combat loop
- FLANKING may not work if flanking is disabled

**Fix:** Changed to always transition to PURSUING when player not visible:
```gdscript
# If can't see player, pursue them (move cover-to-cover toward player)
if not _can_see_player:
    _combat_exposed = false
    _combat_approaching = false
    _log_debug("Lost sight of player in COMBAT, transitioning to PURSUING")
    _transition_to_pursuing()
    return
```

## Implementation Details

### Files Modified
- `scripts/objects/enemy.gd`

### Changes Summary

1. **Line 1285:** Removed `or not _is_visible_from_player()` from pursuit cover arrival check
2. **Lines 1952-1955:** Added minimum distance check (30px) for pursuit cover candidates
3. **Lines 762-768:** Changed COMBAT state to transition to PURSUING (not FLANKING/IDLE) when player not visible

### Debug Labels
The debug labels continue to show current phase information:
- PURSUING: Shows `(WAIT Xs)` or `(MOVING)`
- COMBAT: Shows `(APPROACH)` or `(EXPOSED Xs)`

## Testing Checklist

1. **PURSUING State:**
   - [ ] Enemy waits ~1.5s at cover
   - [ ] Enemy actually MOVES to next cover (not instantly "arriving")
   - [ ] If no cover found, enemy transitions to COMBAT or FLANKING
   - [ ] Debug label shows `(WAIT)` then `(MOVING)` phases

2. **COMBAT State:**
   - [ ] Enemy approaches player (APPROACH phase visible)
   - [ ] Once close or time exceeded, enemy enters EXPOSED phase
   - [ ] Enemy returns to cover after shooting
   - [ ] If player goes behind cover, enemy transitions to PURSUING

3. **State Flow:**
   - [ ] IN_COVER → PURSUING (when player not visible)
   - [ ] PURSUING → COMBAT (when player becomes visible)
   - [ ] COMBAT → PURSUING (when player hides)
   - [ ] COMBAT → SEEKING_COVER → IN_COVER (after exposed shooting)

## Technical Deep Dive

### Why the Visibility Check Was Wrong

The original code at line 1285 was:
```gdscript
if distance < 15.0 or not _is_visible_from_player():
```

This was intended to handle two cases:
1. Enemy reached the physical cover position (distance < 15)
2. Enemy became hidden from player before reaching cover

However, case #2 creates an impossible situation:
- Enemy starts at cover A (hidden from player)
- Wants to move to cover B (closer to player)
- The instant they try to move, `_is_visible_from_player()` returns FALSE
- They're immediately considered "at cover B" without moving!

The correct behavior is to ONLY check distance. The enemy must physically travel to the new cover position regardless of visibility.

### Cover Distance Threshold

The 30-pixel minimum distance prevents:
1. Micro-movements that look like standing still
2. Numerical precision issues where cover positions are nearly identical
3. The edge case where the same cover is found multiple times

30 pixels was chosen because:
- Character collision radius is ~24 pixels
- 30px ensures visible movement on screen
- Small enough to allow nearby covers when appropriate

## References
- enemy.gd lines 740-852 (COMBAT state processing)
- enemy.gd lines 1279-1302 (PURSUING movement code)
- enemy.gd lines 1913-1976 (_find_pursuit_cover_toward_player)
- Feedback comments on PR #89
