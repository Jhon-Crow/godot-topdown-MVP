# Case Study: Issue #196 - Walking Animation with Assault Rifle

## Timeline of Events

### 2026-01-22T00:40:06Z - Related Issue PR #191 Feedback
User @Jhon-Crow provided feedback on PR #191 with reference images showing the desired soldier pose:
- Referenced images from Shutterstock showing tactical top-down soldier poses
- Reported that the player was at 90 degrees to the rifle (rifle appeared at player's left side)
- Requested a more tactical pose matching the reference

### 2026-01-22T00:52:15Z - Issue #196 Created
Original request: "Continue from PR #191, add walking animation with assault rifle"

### 2026-01-22T00:57:46Z - Initial Implementation (PR #197)
Walking animation was implemented with:
- Body bob: Up/down movement during walking
- Head bob: Dampened vertical movement
- Arm swing: Alternating horizontal movement
- Smooth transitions: Lerp-based return to idle

### 2026-01-22T01:07:38Z - Feedback on PR #197
User @Jhon-Crow reported the same issues as PR #191:
1. Rifle rotated 90 degrees (player perpendicular to rifle)
2. Need more tactical pose with hands gripping rifle
3. Player should hold rifle with hands locked on weapon

## Root Cause Analysis

### The 90-Degree Rotation Problem

**Root Cause**: Misalignment between player sprite orientation and rifle sprite orientation.

The player sprites (body, head, arms) were designed to face UP (negative Y direction in Godot):
- `player_body.png`: Oval shape with narrow sides on left/right
- `player_head.png`: Positioned above body
- Arms: Positioned on sides of body

The rifle sprite (`m16_rifle_topdown.png`) points RIGHT (positive X direction):
- The `AssaultRifle` node rotates independently based on mouse cursor position
- The `PlayerModel` node (containing body parts) does NOT rotate with the rifle

**Result**: When viewed from above, the player appears to hold the rifle at their left side (90 degrees off) because:
- Player body faces UP
- Rifle points RIGHT
- No compensation for this orientation mismatch

### Technical Architecture

```
Player (CharacterBody2D)
├── PlayerModel (Node2D) - Contains all body sprites
│   ├── Body (Sprite2D) - Faces UP
│   ├── Head (Sprite2D) - Faces UP
│   ├── LeftArm (Sprite2D) - Positioned for UP orientation
│   ├── RightArm (Sprite2D) - Positioned for UP orientation
│   └── WeaponMount (Node2D) - Weapon attachment point
├── AssaultRifle (Node2D) - Separate from PlayerModel
│   ├── RifleSprite (Sprite2D) - Points RIGHT, rotates to aim
│   └── LaserSight (Line2D) - Points in aim direction
└── ...
```

The `AssaultRifle.cs` script handles rotation via `UpdateRifleSpriteRotation()`:
```csharp
private void UpdateRifleSpriteRotation(Vector2 direction)
{
    float angle = direction.Angle();
    _rifleSprite.Rotation = angle;
    bool aimingLeft = Mathf.Abs(angle) > Mathf.Pi / 2;
    _rifleSprite.FlipV = aimingLeft;
}
```

The rifle sprite rotates to follow the mouse, but the player body remains static in its UP-facing orientation.

## Solution

### Approach: Rotate Player Sprites to Match Rifle Base Orientation

1. **Rotate all player sprites 90 degrees clockwise** so they face RIGHT by default
   - This matches the rifle's base orientation (pointing right)
   - When the game starts, player and rifle both face right

2. **Reposition sprite elements** for a tactical rifle-holding pose:
   - Body: Centered, facing right
   - Head: In front of body (to the right)
   - Left Arm: Extended forward to hold rifle foregrip
   - Right Arm: Closer to body, near trigger area
   - WeaponMount: Positioned where rifle would be gripped

### Changes Made

#### Sprite Rotations
All player sprites in `assets/sprites/characters/player/` were rotated 90 degrees clockwise:
- `player_body.png`: (24x28) -> (28x24)
- `player_head.png`: (18x14) -> (14x18)
- `player_left_arm.png`: (8x20) -> (20x8)
- `player_right_arm.png`: (8x20) -> (20x8)

#### Scene Position Updates
Updated `scenes/characters/Player.tscn` and `scenes/characters/csharp/Player.tscn`:

| Sprite | Old Position | New Position | Rationale |
|--------|--------------|--------------|-----------|
| Body | (0, 4) | (-4, 2) | Shifted left to center model |
| Head | (0, -10) | (6, -2) | Moved right (front of body) |
| LeftArm | (-12, 5) | (18, -4) | Extended forward for foregrip |
| RightArm | (12, 5) | (8, 8) | Near body for trigger grip |
| WeaponMount | (8, 12) | (24, 2) | Forward position for rifle |

## Reference Images

The user provided reference images showing tactical soldier poses from a top-down view:
- Soldiers facing the same direction as their rifles
- Both hands gripping the rifle (one on foregrip, one on trigger)
- Body aligned with weapon direction

![Reference](reference_image.png)

## Lessons Learned

1. **Sprite Orientation Consistency**: When creating modular sprite systems, ensure all sprites are designed for the same base orientation, matching the primary weapon/tool direction.

2. **Top-Down Game Design**: In top-down games, the "forward" direction is typically RIGHT (positive X), as this matches how humans naturally read (left to right) and how most sprites are designed.

3. **Modular vs. Integrated Design**: The current architecture separates PlayerModel (body) from Weapon (rifle), which allows independent aiming but creates orientation challenges. Alternative approaches:
   - Rotate entire PlayerModel to match aim direction (current game doesn't do this)
   - Use pre-made sprites for different aim angles
   - Use skeletal animation with IK (Inverse Kinematics)

## Files Modified

- `assets/sprites/characters/player/player_body.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_head.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_left_arm.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_right_arm.png` - Rotated 90° CW
- `assets/sprites/characters/player/player_combined_preview.png` - Regenerated
- `scenes/characters/Player.tscn` - Updated sprite positions
- `scenes/characters/csharp/Player.tscn` - Updated sprite positions

## Iteration 2: Rifle Stock and Arm Visibility Fix (2026-01-22)

### Feedback Received

User @Jhon-Crow provided feedback on PR #197:

> **Positive Note**: "It is the best model and animation so far, I'll make a note about it"

However, two issues were identified:
1. **Rifle Stock Position**: The rifle stock was sticking out of the back of the player's head instead of being attached to the right shoulder
2. **Arms Not Visible**: The arms were not visible on the weapon

### Root Cause Analysis

The rifle positioning issue stemmed from coordinate system misunderstanding:
- The rifle sprite has an offset of `(20, 0)` which shifts its visual center 20 pixels forward
- The PlayerModel and AssaultRifle both rotate around Player origin `(0, 0)`
- The arm z_index was 2, same level as rifle z_index 1, causing rendering order issues

When both PlayerModel and rifle rotate to the same angle to aim at the mouse:
- The rifle visual center was too far forward
- The stock (left side of rifle) ended up overlapping with the head
- Arms were rendered behind the rifle sprite

### Solution

1. **Repositioned body parts for Door Kickers 2 style tactical pose**:
   - Body at `(-4, 0)` - shifted back to provide space for rifle
   - Head at `(-6, -2)` - behind and above to look down sights
   - RightArm at `(-2, 6)` - at stock/trigger area (shoulder level)
   - LeftArm at `(24, 6)` - extended forward at foregrip area
   - WeaponMount at `(0, 6)` or `(6, 6)` for shoulder-level rifle mounting

2. **Increased arm z_index to 4** (rifle is z_index 1) to ensure arms always render on top of the weapon

3. **Positioned rifle at shoulder height** (`position = Vector2(0, 6)` on C# scene) so the stock is at the player's right shoulder area

### Position Reference Table (Updated)

| Sprite | Previous Position | New Position | Rationale |
|--------|-------------------|--------------|-----------|
| Body | (-4, 2) | (-4, 0) | Centered for rotation |
| Head | (6, -2) | (-6, -2) | Behind body, looking down sights |
| LeftArm | (18, -4) | (24, 6) | Extended to foregrip, shoulder level |
| RightArm | (8, 8) | (-2, 6) | Near stock/trigger, shoulder level |
| WeaponMount | (24, 2) | (0, 6) / (6, 6) | At shoulder for proper stock placement |
| AssaultRifle | (0, 0) | (0, 6) | Shoulder height for tactical pose |

### Technical Notes

The key insight is that in Godot 2D:
- X+ is right (forward when facing right)
- Y+ is down (toward player's right side in top-down view)

For a proper tactical rifle stance (Door Kickers 2 style):
- Rifle stock should be tucked against right shoulder (positive Y from center)
- Head should be positioned to look down the rifle sights
- Right arm holds stock/trigger area
- Left arm extends forward to foregrip
- Arms must have higher z_index than rifle to appear "gripping" the weapon
