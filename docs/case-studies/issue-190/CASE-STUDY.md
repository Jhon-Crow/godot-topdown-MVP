# Case Study: Issue #190 - Update Player Model

## Overview

**Issue**: [#190 - update модельку игрока](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/190)
**Pull Request**: [#191](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/191)
**Date**: January 22, 2026

## Problem Statement

The player model in the top-down game needed several improvements:
1. Link player model rotation to weapon rotation
2. Add weapon holding pose (for assault rifle)
3. Update colors and style based on reference image
4. Increase model scale to match weapon scale

After the initial implementation, the owner reported a critical issue:
> "The player is at 90 degrees to the rifle (the rifle is at the player's left side)"

## Timeline of Events

### Phase 1: Initial Implementation (00:24 - 00:30 UTC)

1. **00:24:25** - AI solver started working on issue #190
2. **00:24:48** - Pull Request #191 created as draft
3. **00:25:XX** - Initial analysis of the issue requirements:
   - Read the issue which requested in Russian:
     - "привяжи поворот модельки игрока к повороту оружия" (link player model rotation to weapon rotation)
     - "добавь позу держания текущего оружия" (add weapon holding pose)
     - "детализируй цвета и вид модели с помощью референса" (detail colors and appearance using reference)
     - "немного увеличь модельку" (slightly increase model size)

4. **Implementation completed**:
   - Updated player sprites with tactical appearance
   - Added `_update_aim_rotation()` function to rotate PlayerModel toward mouse cursor
   - Scaled model to 1.3x
   - Repositioned sprites for weapon-holding stance

### Phase 2: Owner Feedback (00:40 UTC)

The owner (Jhon-Crow) reviewed the implementation and identified a fundamental problem:

> "сделай модельку (позу и форму) более похожей на [reference images]"
> "сейчас игрок находится под углом 90 градусов к винтовке (она у него на левом боку), исправь."

Translation: "The player is at 90 degrees to the rifle (it's at their left side), fix it."

### Phase 3: Root Cause Analysis (current session)

## Root Cause Analysis

### The Core Problem

The fundamental issue was a **sprite orientation mismatch**:

1. **Weapon orientation**: The M16 rifle sprite (`m16_rifle_topdown.png`) is oriented to point **RIGHT** (positive X direction)

2. **Player sprite orientation**: The original player sprites were designed to face **UP** (negative Y direction):
   - Head positioned at the top (negative Y)
   - Body in center
   - Arms on the left and right sides
   - This is the natural way to draw a top-down character

3. **When the code rotates the PlayerModel** to face the mouse cursor using `_player_model.rotation = _aim_direction.angle()`, the weapon rotates correctly, but the player body remains oriented perpendicular to the weapon direction.

### Visual Explanation

```
BEFORE FIX (incorrect):
Player faces UP, weapon points RIGHT

        Head
         |
   Arm--Body--Arm  ======> Rifle
         |
       (down)

When rotated 0° (aiming right), player body faces UP while rifle points RIGHT.
This creates a 90-degree angle between player and weapon.


AFTER FIX (correct):
Player and weapon both face RIGHT

       Head
         \
          Body--Arm ======> Rifle
         /
       Arm

When rotated 0° (aiming right), player body faces RIGHT, same as rifle.
Player appears to be holding the rifle in front of them.
```

### Why This Happened

The initial implementation correctly:
- Added rotation code to rotate the PlayerModel
- Repositioned sprites to create a holding pose
- Scaled the model appropriately

However, it failed to account for the fact that the **base orientation** of the player sprites (facing UP) didn't match the **base orientation** of the weapon (pointing RIGHT). Simply repositioning sprites within the PlayerModel doesn't change their base orientation.

## Solution

### Fix Applied

1. **Rotate all player sprites 90 degrees clockwise**:
   - `player_body.png`: Rotated so player faces RIGHT
   - `player_head.png`: Rotated correspondingly
   - `player_left_arm.png`: Rotated to extend forward
   - `player_right_arm.png`: Rotated to extend forward

2. **Update sprite positions** in both Player.tscn files:
   - Head: Position behind body (negative X since player faces right)
   - Arms: Extend forward (positive X) to hold rifle
   - WeaponMount: At the front of the player model

### Position Changes

| Sprite | Old Position | New Position |
|--------|-------------|--------------|
| Head | (-2, -14) | (-12, -2) |
| LeftArm | (-10, 8) | (14, -4) |
| RightArm | (14, 6) | (10, 6) |
| Body | (0, 0) | (0, 0) |
| WeaponMount | (16, 4) | (20, 0) |

## Lessons Learned

1. **Coordinate system matters**: In top-down games with rotating sprites, the base orientation of sprites must match the base orientation of equipped items (weapons, tools, etc.)

2. **Reference images are critical**: The owner's reference images (showing soldiers from bird's-eye view) clearly showed the expected pose - facing the same direction as the weapon.

3. **Rotation ≠ Reorientation**: Rotating a container node doesn't change the relative orientation of its children. If sprites are designed to face one direction, they need to be re-drawn or rotated at the image level to face a different base direction.

4. **Test with rotation**: When implementing rotation-based aiming, test at various angles (0°, 90°, 180°, 270°) to ensure the visual appearance is correct at all orientations.

## Files Modified

- `assets/sprites/characters/player/player_body.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_head.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_left_arm.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_right_arm.png` - Rotated 90° CW
- `scenes/characters/Player.tscn` - Updated sprite positions
- `scenes/characters/csharp/Player.tscn` - Updated sprite positions

## References

- [Original Issue #190](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/190)
- [Pull Request #191](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/191)
- Reference images in `./references/` folder:
  - `soldier-reference.png` - Bird's-eye view of soldiers holding rifles
  - `original-reference.png` - Pixel art reference from issue

## Conclusion

This case study demonstrates the importance of understanding coordinate systems and sprite orientation in game development. A visual bug that appears minor (90-degree offset) can have a fundamental cause (mismatched base orientations) that requires changes at the asset level, not just the code level.
