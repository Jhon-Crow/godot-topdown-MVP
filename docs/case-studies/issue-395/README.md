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

## Phase 2: Debug Indicator Bug (February 3, 2026)

### Problem Report

After the initial fix was deployed, user reported that the debug indicator (yellow/orange line showing suspected position) was STILL pointing in the wrong direction, even though the rotation logic was now using `_memory.suspected_position`.

### Root Cause Analysis

Investigation of the `_draw()` function revealed a coordinate system bug:

```gdscript
# In _draw() - BUGGY CODE
var to_suspected := _memory.suspected_position - global_position
draw_line(Vector2.ZERO, to_suspected, confidence_color, 1.0)
```

**THE PROBLEM:**
- `_draw()` uses LOCAL coordinates for all drawing operations
- The enemy's `rotation` property affects the coordinate system
- `to_suspected` is calculated in GLOBAL coordinates
- When the enemy rotates (via `rotation = ...` calls in priority attacks, hit reactions, etc.), the draw coordinates are incorrectly rotated

### Evidence from Logs

In `game_log_20260203_120643.txt`, we can see multiple places where `rotation` is modified:
- Line 1167: `rotation = direction_to_player.angle()` (priority attack)
- Line 1218: `rotation = direction_to_player.angle()` (vulnerability attack)
- Line 4099: `_force_model_to_face_direction(attacker_direction)` (hit reaction)

These rotations cause the debug indicator to appear to point in the wrong direction, even though the underlying `_memory.suspected_position` is correct.

### The Fix

Added a helper function to convert global position offsets to local draw coordinates:

```gdscript
## Convert a global position offset to local draw coordinates.
## Issue #395: The enemy's body rotation affects _draw() coordinates, so we must
## counter-rotate global vectors to draw them correctly in local space.
func _global_to_local_draw(global_offset: Vector2) -> Vector2:
    return global_offset.rotated(-rotation)
```

Applied this conversion to ALL draw calls in `_draw()`:
- Line to player (when visible)
- Bullet spawn point
- Cover position
- Clear shot target
- Pursuit cover
- Flank target/cover
- **Suspected position** (the key indicator!)

### Visual Demonstration

```
Before fix:
  Enemy rotation = 45°
  Global vector to target = (100, 0) → points EAST
  _draw() interprets (100, 0) in LOCAL coords → appears to point NORTHEAST

After fix:
  Enemy rotation = 45°
  Global vector to target = (100, 0) → points EAST
  _global_to_local_draw((100,0)) = (70.7, -70.7) → rotated by -45°
  _draw() draws this in LOCAL coords → appears to point EAST (correct!)
```

### Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Added `_global_to_local_draw()` helper function |
| `scripts/objects/enemy.gd` | Fixed all `_draw()` calls to use local coordinates |

---

## Conclusion

This issue had TWO bugs:

1. **Rotation Priority Bug (Initial Fix):** Priority 2 rotation was using actual player position instead of memory/suspected position.

2. **Debug Indicator Bug (Phase 2 Fix):** The `_draw()` function was calculating positions in global coordinates but Godot's draw functions use local coordinates. When the enemy's body rotates, all debug indicators appeared rotated.

The combination of these bugs created a confusing situation where:
- The rotation logic was ACTUALLY working correctly (pointing to memory position)
- But the debug indicator showed the WRONG direction (due to coordinate system bug)
- This made it appear like the rotation was wrong, when it was actually the visualization that was wrong

### Lessons Learned

1. **Coordinate Systems:** Always be explicit about whether you're working in global or local coordinates, especially in `_draw()` functions.

2. **Debug Tools Can Lie:** When debug visualization disagrees with expected behavior, verify the debug code itself before assuming the underlying logic is wrong.

3. **Multiple Rotations:** In Godot, CharacterBody2D can have BOTH a body `rotation` AND a child model `global_rotation`. These are independent and affect different things.
