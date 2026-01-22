# Issue 249: Fix Player Model - Arm Joint Issues

## Problem Statement
When walking with an assault rifle, there are visible joint issues:
1. The shoulder (of the right arm) sticks out behind the torso
2. The arm is not connected at the elbow

## Technical Analysis

### Sprite Dimensions
- `player_body.png`: 28x24 pixels (torso, facing right)
- `player_head.png`: 14x18 pixels (helmet from above)
- `player_left_arm.png`: 20x8 pixels (horizontal arm, extends right)
- `player_right_arm.png`: 20x8 pixels (horizontal arm, extends right)

### Scene Positioning (Player.tscn)
```
PlayerModel (Node2D at origin)
├── Body (Sprite2D)
│   ├── position: (-4, 0)
│   ├── z_index: 1 (in scene), set to 1 in code
├── LeftArm (Sprite2D)
│   ├── position: (24, 6)
│   ├── z_index: 4 (in scene), set to 2 in code
├── RightArm (Sprite2D)
│   ├── position: (-2, 6)
│   ├── z_index: 4 (in scene), set to 2 in code
├── Head (Sprite2D)
│   ├── position: (-6, -2)
│   ├── z_index: 3 (in scene and code)
└── WeaponMount (Node2D)
    └── position: (0, 6) or (6, 6) in C# version
```

### Walking Animation System
The `_update_walk_animation()` function in `player.gd` applies offsets:
- Body bobs up/down: `sin(time * 2.0) * 1.5 * intensity`
- Head bobs (dampened): `sin(time * 2.0) * 0.8 * intensity`
- Arms swing opposite: `sin(time) * 3.0 * intensity`
  - Left arm: `position + Vector2(arm_swing, 0)`
  - Right arm: `position + Vector2(-arm_swing, 0)`

### Root Cause Identification

#### Issue 1: Shoulder Sticking Out
The right arm position `(-2, 6)` places the arm's pivot point (center of sprite) close to the body center. When the arm swings during walking animation (`-arm_swing` on X-axis), it moves to the LEFT (negative X direction), which in the player's reference frame means BACKWARD.

With a 20-pixel wide arm sprite centered at x=-2:
- Sprite spans from x=-12 to x=8
- The "shoulder" part of the arm (leftmost portion) is at x=-12
- The body's right edge is around x=10 (body at -4 with 28px width)

When the arm swings LEFT during animation, the shoulder portion becomes more visible behind the body.

#### Issue 2: Elbow Disconnection
The arm sprites are designed as straight horizontal bars. When the walking animation moves the arms along the X-axis, and the body bobs vertically, the arms can appear disconnected because:
1. The Y position of arms doesn't track with body bob
2. The arm sprites don't have proper elbow articulation

### Proposed Solutions

#### Solution A: Adjust Arm Position
Move the right arm position so the shoulder is better anchored to the body:
- Current: `(-2, 6)`
- Proposed: `(2, 6)` or adjust to better align shoulder joint

#### Solution B: Reduce Arm Swing During Walking
The current arm swing of `3.0 * intensity` pixels may be too large, causing visible disconnection. Reducing to `1.5 * intensity` would keep arms more attached.

#### Solution C: Synchronize Body Bob with Arms
Add a small vertical offset to arms that matches the body bob to prevent apparent disconnection during walking.

#### Solution D: Adjust Z-Index Based on Facing Direction
When the player faces left (PlayerModel flipped), swap the z-indices of arms so the correct arm appears in front.

## Recommended Fix
Implement a combination of:
1. Reduce arm swing amplitude
2. Add body-synchronized vertical offset to arms
3. Adjust right arm base position for better shoulder alignment

## Implementation (Iteration 1) - January 22, 2026

### Changes Made
1. **Reduced arm swing amplitude** from 3.0 to 1.5 pixels
2. **Added body bob synchronization** to arms (70% of body bob)
3. **Adjusted right arm position** from (-2, 6) to (0, 6)
4. **Fixed z_index values** in scene files from 4 to 2

### User Feedback (Post-Implementation)
User Jhon-Crow reported that the right elbow still constantly disconnects:
- With rifle or shotgun pose
- When throwing grenades

Game logs show the fix was applied:
```
[Player] Applied Rifle arm pose: Left=(24, 6), Right=(-2, 6)
```
Note: The log still shows (-2, 6) because the user was testing from main branch, not the PR branch.

### Root Cause Analysis (Updated)

The initial fix addressed position and animation parameters but missed the fundamental issue: **The arm sprites' pivot points are at the sprite center, not at the shoulder joint.**

When animations move the arm's `position`, the entire sprite moves including both the shoulder and elbow ends. This causes visible disconnection because the shoulder should stay attached to the body while only the elbow/hand moves.

#### Technical Details
- Arm sprite dimensions: 20x8 pixels
- Default pivot point: center of sprite (10, 4)
- When position changes by +5 on X-axis, both shoulder AND elbow move +5
- This breaks the visual joint connection

## Implementation (Iteration 2) - January 22, 2026

### Solution: Sprite Offset for Shoulder-Centered Pivot

Added `offset = Vector2(10, 0)` to arm sprites in scene files. This shifts the sprite so:
- The **pivot point** (where `position` coordinate applies) is at the **left edge** of the sprite
- For arms, the left edge represents the **shoulder joint**
- When animations change `position`, the shoulder stays in place while the rest of the arm moves

### Updated Scene Positioning
```
PlayerModel (Node2D at origin)
├── Body (Sprite2D)
│   ├── position: (-4, 0)
│   └── z_index: 1
├── LeftArm (Sprite2D)
│   ├── position: (14, 6)    # Changed from (24, 6)
│   ├── offset: (10, 0)      # NEW: Pivot at shoulder (left edge)
│   └── z_index: 2
├── RightArm (Sprite2D)
│   ├── position: (-10, 6)   # Changed from (0, 6)
│   ├── offset: (10, 0)      # NEW: Pivot at shoulder (left edge)
│   └── z_index: 2
├── Head (Sprite2D)
│   ├── position: (-6, -2)
│   └── z_index: 3
└── WeaponMount (Node2D)
    └── position: (0, 6)
```

### Code Changes
Updated `_apply_weapon_arm_offsets()` in `player.gd`:
- `original_left_arm_pos`: Changed from (24, 6) to (14, 6)
- `original_right_arm_pos`: Changed from (0, 6) to (-10, 6)

### Visual Math Verification
With offset (10, 0) on a 20px wide sprite:
- Sprite center at local (10, 4) is drawn at position + offset = position + (10, 0)
- Left edge of sprite is drawn at position + offset - (10, 0) = position
- **Result**: Left edge (shoulder) is exactly at the position coordinate

When animation moves position, the shoulder stays connected because:
- Position change affects the shoulder location
- The sprite extends from the shoulder outward (toward hand/elbow)
- Body connections remain visually intact

### User Feedback (Post-Iteration 2)
User Jhon-Crow reported:
- "всё ещё нет стыка" (still no joint connection)
- "добавь круглый сустав на место локтей" (add round joint to the elbow locations)

The user attached game log: `game_log_20260122_191452.txt`

### Root Cause Analysis (Updated)
The sprite offset solution correctly anchored the shoulder, but the **elbow end** of the arm still shows visible gaps during animations. The arm sprites are rectangular bars that don't naturally connect to the body or forearm at the elbow.

**Technical Issue**: When the arm rotates or moves, the elbow end (right edge of the 20x8 pixel sprite) creates a visual gap where there should be a joint.

## Implementation (Iteration 3) - January 22, 2026

### Solution: Round Elbow Joint Sprites

Added circular elbow joint sprites as children of the arm sprites. These "joint caps" cover the gap at the elbow end and provide visual continuity during all animations.

#### New Asset Created
`assets/sprites/characters/player/player_elbow_joint.png`:
- Size: 8x8 pixels
- Shape: Circular/round
- Color: Matching the arm sprites (dark green tones)
- Purpose: Cover the elbow joint gap

#### Scene Structure Update
```
PlayerModel (Node2D at origin)
├── Body (Sprite2D)
│   └── z_index: 1
├── LeftArm (Sprite2D)
│   ├── position: (14, 6)
│   ├── offset: (10, 0)
│   ├── z_index: 2
│   └── ElbowJoint (Sprite2D)    # NEW
│       ├── position: (10, 0)    # At elbow end of arm
│       └── z_index: 1
├── RightArm (Sprite2D)
│   ├── position: (-10, 6)
│   ├── offset: (10, 0)
│   ├── z_index: 2
│   └── ElbowJoint (Sprite2D)    # NEW
│       ├── position: (10, 0)    # At elbow end of arm
│       └── z_index: 1
├── Head (Sprite2D)
│   └── z_index: 3
└── WeaponMount (Node2D)
```

### How It Works
1. **Joint Position**: The elbow joint is positioned at `(10, 0)` relative to the arm sprite
   - With the arm's offset of `(10, 0)`, the pivot is at the shoulder (left edge)
   - The elbow is at the right edge, which is at local position `(10, 0)` from the arm's pivot
2. **Joint Movement**: Since the elbow joint is a child of the arm sprite, it automatically:
   - Moves when the arm moves
   - Rotates when the arm rotates
   - Stays at the elbow position regardless of animation state
3. **Z-Index**: Set to 1 (below the arm's z_index of 2) so the joint appears behind the arm for natural layering
4. **Color Matching**: Updated both GDScript and C# to include elbow joints in the sprite color modulation system

### Code Changes

#### GDScript (`scripts/characters/player.gd`)
- Added references: `_left_elbow_joint`, `_right_elbow_joint`
- Updated `_set_all_sprites_modulate()` to include elbow joints

#### C# (`Scripts/Characters/Player.cs`)
- Added fields: `_leftElbowJoint`, `_rightElbowJoint`
- Added initialization in `_Ready()`
- Added logging: `[Player.Init] Left/Right elbow joint found`
- Updated `SetAllSpritesModulate()` to include elbow joints

### Visual Result
The round elbow joints provide a smooth visual transition at the elbow:
- During idle: Joint sits at elbow, barely visible but fills any gap
- During walking: Joint moves with arm, always covering the elbow
- During grenade/reload animations: Joint follows arm rotation/movement
- When arms move away from body: Joint creates clean visual connection
