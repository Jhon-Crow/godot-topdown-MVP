# Root Cause Analysis: Issue #227 - UZI Pose Fix

## Problem Statement
When the player holds an UZI, they hold it the same way as the M16 (as if the UZI had a long barrel). The UZI should be held with two hands in a compact pose appropriate for a submachine gun.

## Root Cause

### Primary Cause: Fixed Arm Positions
The player's arm positions are fixed and do not adapt to the equipped weapon type.

**Location**: `scripts/characters/player.gd`

**Evidence**:
```gdscript
# Base positions stored in _ready() - lines 242-250
_base_left_arm_pos = _left_arm_sprite.position   # (24, 6)
_base_right_arm_pos = _right_arm_sprite.position  # (-2, 6)
```

These positions are designed for a rifle (M16) with a long barrel, where:
- Left arm is extended forward (x=24) to support the front of the rifle
- Right arm is closer to the body (x=-2) holding the pistol grip

### Secondary Cause: No Weapon Type Detection
The player script has no mechanism to:
1. Detect which weapon is currently equipped
2. Adjust arm positions based on weapon type
3. Apply different base positions for different weapon categories

### Current Arm Positioning in Walking Animation
```gdscript
# Lines 384-433 - _update_walk_animation()
# Arms always return to the same base positions regardless of weapon
if _left_arm_sprite:
    _left_arm_sprite.position = _base_left_arm_pos + Vector2(arm_swing, 0)
if _right_arm_sprite:
    _right_arm_sprite.position = _base_right_arm_pos + Vector2(-arm_swing, 0)
```

### Weapon Scene Configurations
Both weapons use similar sprite offsets:
- **MiniUzi.tscn**: `offset = Vector2(15, 0)`
- **AssaultRifle.tscn**: `offset = Vector2(20, 0)`

The UZI has a slightly smaller offset (15 vs 20), but the arm positions don't account for this difference.

## Expected Behavior

For the UZI (compact SMG):
- Both hands should be closer together
- Left arm should be less extended (supporting a shorter barrel/handguard)
- Arms should create a compact, two-handed grip appropriate for a submachine gun

For the M16 (rifle):
- Hands spread further apart
- Left arm extended forward to support long barrel
- Traditional rifle stance

## Solution Approach

Add weapon-aware arm positioning to the player script:

1. **Detect equipped weapon type** by checking children of WeaponMount or player
2. **Apply weapon-specific arm offsets** to create appropriate poses:
   - SMG pose: Arms closer together for compact grip
   - Rifle pose: Arms spread for long barrel support
3. **Adjust base positions dynamically** when weapon changes or during _ready()

## Technical Implementation

### Option A: Modify `_ready()` in player.gd
- Detect weapon type after weapon is added
- Apply appropriate base arm positions

### Option B: Add setter/signal for weapon changes
- When weapon is equipped, adjust arm positions accordingly
- More flexible for runtime weapon switching

### Recommended: Option A (simpler)
Since weapons are set at level initialization and don't change during gameplay, we can simply detect the weapon in `_ready()` or add a deferred call to adjust positions.

## Files to Modify
1. `scripts/characters/player.gd` - Add weapon detection and arm position adjustment

## Testing
1. Start game with M16 selected - verify rifle pose
2. Start game with Mini UZI selected - verify compact SMG pose
3. Verify walking animation works correctly with both weapons
4. Verify grenade animation still works (it has its own arm positioning)
