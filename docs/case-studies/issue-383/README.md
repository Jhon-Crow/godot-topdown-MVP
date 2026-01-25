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

3. **_update_debug_label() function (lines 4730-4796):** Updates label text but does not counteract parent rotation.

## Solution Options

### Option 1: Reset global_rotation in _update_debug_label()
Add `_debug_label.global_rotation = 0` after updating the text.
- **Pros:** Simple, minimal code change
- **Cons:** Only works when debug label is updated

### Option 2: Use top_level = true with manual position sync
Set `_debug_label.top_level = true` and manually update position.
- **Pros:** Complete isolation from parent transform
- **Cons:** Requires additional position tracking code

### Option 3: Reset rotation in _process()
Always reset `_debug_label.global_rotation = 0` in the process loop.
- **Pros:** Guaranteed to stay upright every frame
- **Cons:** Slightly more processing (negligible)

### Chosen Solution: Option 1 + 3 Combined

The best approach is to reset `_debug_label.global_rotation = 0` both in `_update_debug_label()` and in a minimal process callback when debug is enabled. This ensures the label stays upright regardless of when the enemy rotates.

However, the simplest and most efficient fix is to just add one line in `_update_debug_label()`:
```gdscript
_debug_label.global_rotation = 0
```

This function is called regularly during enemy updates, so the label will stay upright.

## Online Research References

1. [Godot Forums - How to prevent child node from inheriting parent's rotation](https://godotforums.org/d/22138-how-to-prevent-a-child-node-from-inheriting-it-s-parent-s-rotation) - Solution: negate parent rotation with `set_rotation(-parent_rotation)`
2. [GitHub Issue #56821 - No way for CanvasItem to ignore parent transformation](https://github.com/godotengine/godot/issues/56821)
3. [Godot Forums - How to make a label follow a KinematicBody2D without rotation](https://forum.godotengine.org/t/how-to-make-a-label-follow-a-kinematicbody2d-in-position-but-not-rotation/25237)
4. [Godot Forums - How do I make a node health bar stay unrotated?](https://forum.godotengine.org/t/how-do-i-make-a-node-health-bar-stay-unrotated/27584)

## Implementation

See the fix in `scripts/objects/enemy.gd` at the `_update_debug_label()` function.

## Testing

- Enable debug mode in the game
- Observe that the debug label stays upright when enemy rotates
- Verify label text content is still accurate
