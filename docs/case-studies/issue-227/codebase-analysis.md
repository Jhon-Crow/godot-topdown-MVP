# Codebase Analysis for Issue #227: UZI Pose Fix

## Problem Summary
When the player/enemy holds an UZI, they hold it the same way as the M16 (as if the UZI had a long barrel with two hands far apart). The UZI should be held with two hands in a different pose than the M16 (shorter barrel, hands closer together).

## Key Findings

### 1. Weapon Configuration Files
- **MiniUziData.tres**: UZI configuration (Fire Rate: 25.0, Magazine: 32, Range: 800)
- **AssaultRifleData.tres**: M16 configuration (Fire Rate: 10.0, Magazine: 30, Range: 1500)
- **Critical Issue**: `WeaponData` class has NO weapon type/category field to distinguish between different weapon types (SMG, rifle, shotgun)

### 2. Player Model Structure (Player.tscn)
```
Player (CharacterBody2D)
├── PlayerModel (Node2D)
│   ├── Body (Sprite2D) - z_index: 1
│   ├── LeftArm (Sprite2D) - z_index: 4
│   ├── RightArm (Sprite2D) - z_index: 4
│   ├── Head (Sprite2D) - z_index: 3
│   └── WeaponMount (Node2D) - position: (0, 6)
```

### 3. Walking Animation System (player.gd)
- Base Positions stored in `_ready()`:
  - Body: `(-4, 0)`
  - Head: `(-6, -2)`
  - LeftArm: `(24, 6)`
  - RightArm: `(-2, 6)`
  - WeaponMount: `(0, 6)`
- Walking animation only affects body parts (body, head, arms)
- **NO weapon-specific walking variations exist**

### 4. Weapon Sprite Positioning
- **MiniUzi Scene**: Sprite offset Vector2(15, 0)
- **AssaultRifle Scene**: Sprite offset Vector2(15, 0)
- **Both use identical sprite rotation code**

### 5. Root Cause
1. **No Weapon Type System**: No mechanism to distinguish between weapon types
2. **No Arm Positioning During Shooting**: Arms only animate during grenade handling
3. **Fixed Weapon Mounting Point**: Weapon only rotates around fixed point
4. **No Walking Animation Variation**: Same animation regardless of equipped weapon

## Solution Approach

To fix the UZI pose, we need to:
1. Add weapon type identification mechanism
2. Modify arm positions based on weapon type in player.gd
3. Apply different arm positions for UZI vs rifle weapons

### Implementation Details

The fix should modify the player's arm positions when holding the UZI to create a compact two-handed grip appropriate for a submachine gun, rather than the spread-out rifle grip.

Key changes needed in `player.gd`:
- Detect current weapon type
- Apply weapon-specific arm base positions
- Adjust walking animation arm swing for compact weapons
