# Case Study: Issue #395 - Enemies Turn Wrong Direction on Gunshot Sound

## Issue Summary

**Title (Russian):** враги слыша звук выстрела поворачиваются не в ту сторону или вообще не поворачиваются на выстрел

**Title (English):** Enemies hearing the gunshot turn in the wrong direction or don't turn toward the shot at all

**Description:** After the player shoots, the debug indicator shows that enemies assume the player's position is in a different or even opposite direction. At the same time, enemies don't turn toward the player.

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/395

---

## Timeline of Events

### 1. Sound Detection System (Working Correctly)

When the player shoots:
1. `player.gd` line 615-617 calls `sound_propagation.emit_sound(0, global_position, 0, self, weapon_loudness)`
2. `sound_propagation.gd` propagates the sound to all registered listeners within range
3. `enemy.gd` receives the callback via `on_sound_heard_with_intensity()`

### 2. Sound Position Storage (Working Correctly)

In `enemy.gd` lines 688-694:
```gdscript
# Store the position of the sound as a point of interest
_last_known_player_position = position

# Update memory system with sound-based detection (Issue #297)
if _memory:
    _memory.update_position(position, SOUND_GUNSHOT_CONFIDENCE)
```

The sound source position is correctly stored in:
- `_last_known_player_position` - legacy tracking variable
- `_memory.suspected_position` - memory system with confidence tracking

### 3. State Transition (Working Correctly)

In `enemy.gd` line 697:
```gdscript
_transition_to_combat()
```

The enemy correctly enters COMBAT state to investigate the sound.

### 4. Rotation Update (THE BUG)

In `enemy.gd` lines 895-900:
```gdscript
# Priority 2: During active combat states, maintain focus on player even without visibility (#386, #397)
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT] and _player != null:
    target_angle = (_player.global_position - global_position).normalized().angle()
    has_target = true
    rotation_reason = "P2:combat_state"
```

**THE PROBLEM:** Priority 2 uses `_player.global_position` (the player's actual current position) instead of:
- `_last_known_player_position` (where the sound came from), or
- `_memory.suspected_position` (the memory system's tracked position)

---

## Root Cause

The Priority 2 rotation logic was added in commit `dda239d` to fix Issue #397 (enemies turning away when they see the player). However, this fix introduced a regression:

**Before fix #397:** Enemies would face wrong directions during combat states
**After fix #397:** Enemies always face the player's **actual** position, even when they shouldn't know it

The fix was too broad - it made enemies face `_player.global_position` in ALL combat states, regardless of whether:
- The enemy can actually see the player
- The enemy only heard a sound and shouldn't know the player's exact position

### Why the Debug Shows Correct Position but Enemy Faces Wrong Direction

The debug visualization in `_draw()` (lines 4723-4744) correctly draws:
- A line to `_memory.suspected_position`
- A confidence-based circle showing uncertainty

But the rotation code ignores this and uses `_player.global_position` directly.

---

## Visual Representation

```
Player (actual position)          Sound Source Position
        P                                  S
        |                                  |
        v                                  v
  [Enemy should face S]          [Enemy actually faces P]
          \                              /
           \                            /
            \                          /
             --------ENEMY-----------
```

When player shoots from position S but then moves to position P:
- Debug indicator shows correct position S
- Enemy turns toward actual player position P (wrong!)

---

## Affected Files

| File | Lines | Issue |
|------|-------|-------|
| `scripts/objects/enemy.gd` | 897-900 | Priority 2 rotation uses wrong position |

---

## Solution Design

The fix should modify Priority 2 to:
1. Only use `_player.global_position` when the enemy **can see** the player
2. Use `_memory.suspected_position` (or `_last_known_player_position`) when the enemy **cannot see** the player but is in a combat state

### Proposed Code Change

```gdscript
# Priority 2: During active combat states, maintain focus on last known position when player not visible
elif _current_state in [AIState.COMBAT, AIState.PURSUING, AIState.FLANKING, AIState.SEARCHING, AIState.ASSAULT]:
    var target_position: Vector2
    if _player != null:
        # Use memory system's suspected position if available, otherwise last known
        if _memory and _memory.has_target():
            target_position = _memory.suspected_position
        elif _last_known_player_position != Vector2.ZERO:
            target_position = _last_known_player_position
        else:
            target_position = _player.global_position  # Fallback
    else:
        # No player reference, use stored position
        if _memory and _memory.has_target():
            target_position = _memory.suspected_position
        elif _last_known_player_position != Vector2.ZERO:
            target_position = _last_known_player_position
        else:
            # No target information available
            return  # or continue to next priority
    target_angle = (target_position - global_position).normalized().angle()
    has_target = true
    rotation_reason = "P2:combat_state"
```

---

## Related Issues and PRs

- **Issue #397:** Enemy turns away when seeing player (fixed by adding Priority 2)
- **Issue #386:** Enemy faces player during FLANKING state
- **Issue #347:** Smooth rotation implementation
- **Issue #297:** Memory system for enemy position tracking

---

## Testing Recommendations

1. **Basic Sound Test:**
   - Place player behind cover
   - Shoot in IDLE enemy's hearing range
   - Verify enemy turns toward sound source, not player's actual position

2. **Moving Player Test:**
   - Player shoots, then immediately moves
   - Verify enemy faces original shot position, not new player position

3. **Multiple Sounds Test:**
   - Player shoots multiple times from different positions
   - Verify enemy tracks each sound correctly

4. **Regression Test:**
   - Verify Issue #397 fix still works (enemy doesn't turn away when visible)
   - Verify Issue #386 fix still works (FLANKING state rotation)

---

## Conclusion

This is a classic case of a fix for one issue (enemies turning away) introducing a regression for another scenario (sound-based detection). The solution requires making the rotation logic context-aware: use actual player position only when the enemy has visual confirmation, otherwise use the memory/suspected position from sound detection.
