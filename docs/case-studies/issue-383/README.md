# Case Study: Issue #383 - Fix Debug Assumptions of Enemies

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/383
**Title:** fix debug of enemy assumptions (дебаг предположений врагов)
**Description (translated):** "Currently it rotates when the enemy rotates, likely showing incorrect information."

## Timeline of Events

1. **Debug label functionality exists**: The enemy debug label (`DebugLabel`) displays AI state information including:
   - Current AI state (IDLE, PATROL, COMBAT, RETREATING, etc.)
   - Sub-state details (EXPOSED, APPROACH, RUSHING, etc.)
   - Memory confidence percentage and behavior mode

2. **Bug manifestation**: When the enemy character rotates (to face player, during movement, etc.), the debug label rotates along with the enemy because it inherits the parent's transform.

3. **User expectation**: The debug label should remain horizontal/upright regardless of enemy rotation, so the text remains readable.

4. **Initial fix attempt (2026-01-25)**: Added `_debug_label.global_rotation = 0` in `_update_debug_label()`.

5. **User feedback (2026-01-25)**: User reported "проблема не решена" (problem not solved) - the label still rotates.

6. **Root cause investigation**: Identified that the initial fix was insufficient because:
   - There are early returns from `_physics_process()` that skip `_update_debug_label()`
   - Setting rotation every frame is fragile and can be affected by timing issues

## Root Cause Analysis

### Technical Root Cause

The `DebugLabel` node is defined in `scenes/objects/Enemy.tscn` as a direct child of the `Enemy` (CharacterBody2D) node:

```
Enemy (CharacterBody2D)
├── EnemyModel (Node2D)
│   ├── Body, Head, Arms, etc.
├── DebugLabel (Label)  <-- This is the problematic node
```

In Godot, child nodes inherit their parent's transform by default. When the Enemy node rotates (via `rotation` property changes), the DebugLabel rotates as well, making the text appear tilted or upside-down.

### Why the Initial Fix Failed

The initial fix using `_debug_label.global_rotation = 0` in `_update_debug_label()` had two problems:

1. **Early returns in _physics_process()**: The function `_update_debug_label()` is only called from `_physics_process()`, but there are several early return statements that can skip this call:
   - Line 1036: `if not _is_alive: return` - dead enemy
   - Line 1075: `return # Skip rest of physics process this frame` - globally stuck enemy transitioning to SEARCHING

2. **Timing sensitivity**: Even when called, resetting `global_rotation` every frame can be affected by the order of operations between setting the enemy's rotation and the render cycle.

### Evidence from Codebase

1. **Enemy.tscn (line 78-85):** DebugLabel is positioned with offsets but no rotation control:
   ```
   [node name="DebugLabel" type="Label" parent="."]
   visible = false
   offset_left = -50.0
   offset_top = -50.0
   ```

2. **enemy.gd rotation code:** Multiple places modify `rotation`:
   - Line 1376: `rotation = direction_to_player.angle()`
   - Line 1426-1427: Aim at player
   - Line 2490: `rotation += delta * 1.5`
   - And many more throughout the file

## Solution Options

### Option 1: Reset global_rotation in _update_debug_label() (INITIAL FIX - INSUFFICIENT)
Add `_debug_label.global_rotation = 0` after updating the text.
- **Pros:** Simple, minimal code change
- **Cons:** Only works when `_update_debug_label()` is called; skipped during early returns

### Option 2: Use top_level = true with manual position sync (CHOSEN SOLUTION)
Set `_debug_label.top_level = true` and manually update position.
- **Pros:** Complete isolation from parent transform - label never inherits rotation
- **Cons:** Requires additional position tracking code
- **Why this is better:** Works reliably regardless of when enemy rotates or whether updates are called

### Option 3: Reset rotation in _process()
Always reset `_debug_label.global_rotation = 0` in the process loop.
- **Pros:** Guaranteed to stay upright every frame
- **Cons:** Still can have timing issues with render cycle

## Chosen Solution: Option 2 - top_level = true

The proper fix uses the `top_level` property:

1. **In `_ready()`**: Call `_setup_debug_label_top_level()` to set `_debug_label.top_level = true`

2. **In `_update_debug_label()`**: Manually position the label at `global_position + Vector2(-50, -50)` since it no longer inherits position from parent

This approach completely isolates the label from parent transforms, ensuring it never rotates regardless of enemy state or timing.

```gdscript
## Setup debug label to be independent of parent rotation (Issue #383).
func _setup_debug_label_top_level() -> void:
    if _debug_label == null:
        return
    _debug_label.top_level = true
    # Position will be manually updated in _update_debug_label()

## In _update_debug_label():
_debug_label.global_position = global_position + Vector2(-50, -50)
```

## Online Research References

1. [Godot Forums - How to prevent child node from inheriting parent's rotation](https://godotforums.org/d/22138-how-to-prevent-a-child-node-from-inheriting-it-s-parent-s-rotation) - Solution: use `top_level = true`
2. [GitHub Issue #56821 - No way for CanvasItem to ignore parent transformation](https://github.com/godotengine/godot/issues/56821) - Recommends `top_level` property
3. [Godot Forums - How to make a label follow a KinematicBody2D without rotation](https://forum.godotengine.org/t/how-to-make-a-label-follow-a-kinematicbody2d-in-position-but-not-rotation/25237)
4. [Godot Forums - How do I make a node health bar stay unrotated?](https://forum.godotengine.org/t/how-do-i-make-a-node-health-bar-stay-unrotated/27584) - Recommends `top_level` property

## Implementation

Changes made to `scripts/objects/enemy.gd`:

1. Added `_setup_debug_label_top_level()` function
2. Call `_setup_debug_label_top_level()` in `_ready()`
3. Updated `_update_debug_label()` to manually position the label using `global_position`

## Testing

- Enable debug mode in the game (F7)
- Observe that the debug label stays upright when enemy rotates
- Verify label text content is still accurate
- Verify label follows the enemy position correctly

## Regression Test

Added test in `tests/unit/test_pursuing_state.gd`:
- `test_debug_label_rotation_stays_upright()`: Verifies the label uses `top_level = true`
- `test_debug_label_position_follows_enemy()`: Verifies position is calculated correctly
