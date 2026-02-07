# Case Study: Issue #592 - Fix PM (Makarov Pistol)

## Issue Summary

Three improvements requested for the Makarov PM pistol weapon:

1. **Stun effect on bullet hit** - 100ms inability to shoot and move when hit by a bullet
2. **Smaller pistol model** - The pistol model in the player's hands should be smaller
3. **Better pistol positioning** - The pistol should be held further from the player's body and should not slide/shift when the player turns

## Technical Analysis

### Current Architecture

The game has two parallel implementations:
- **GDScript player** (`scripts/characters/player.gd`) - Original implementation
- **C# player** (`Scripts/Characters/Player.cs`) - Newer implementation with weapon system

The Makarov PM is implemented as a C# weapon:
- **Scene**: `scenes/weapons/csharp/MakarovPM.tscn`
- **Script**: `Scripts/Weapons/MakarovPM.cs`
- **Base class**: `Scripts/AbstractClasses/BaseWeapon.cs`
- **Data**: `resources/weapons/MakarovPMData.tres`

### Issue 1: Stun Effect (100ms)

**Current hit handling flow:**
1. Bullet (`bullet.gd`) detects hit on `HitArea` (Area2D)
2. `hit_area.gd` forwards to parent's `on_hit_with_info()` or `on_hit()`
3. GDScript player: `on_hit_with_info()` applies damage, flash, blood
4. C# player: `on_hit_with_info()` calls `TakeDamage()` which applies damage

**Solution approach:**
- Add a `_is_stunned` flag and `_stun_timer` to both player implementations
- When hit, set `_is_stunned = true` and `_stun_timer = 0.1` (100ms)
- In `_physics_process()`, skip movement and shooting input while stunned
- Decrement stun timer each frame, clear stun when timer expires

**Reference**: Godot's built-in timer approach works well for short effects. Using a simple float timer is more lightweight than SceneTreeTimer for frame-accurate timing.

### Issue 2: Smaller Pistol Model

**Current state:**
- MakarovSprite in `MakarovPM.tscn` has no scale override (default 1.0)
- Sprite offset is `Vector2(15, 0)` pixels

**Solution approach:**
- Add a `scale` property to the MakarovSprite node in the .tscn file
- A scale of ~0.7 should make it visibly smaller while still recognizable

### Issue 3: Pistol Position and Rotation Stability

**Current state:**
- In the C# player scene, MakarovPM is positioned at `Vector2(0, 6)` as a direct child of Player
- The WeaponMount node exists at `Vector2(6, 6)` under PlayerModel but is NOT used for the Makarov
- The MakarovPM handles its own rotation via `UpdateAimDirection()` and `UpdateWeaponSpriteRotation()`
- The sprite uses `offset = Vector2(15, 0)` which creates visual sliding during rotation since the pivot point is at the weapon origin, not at the grip

**Root cause of sliding:**
The MakarovSprite rotates around its node origin (0,0) but is offset by (15,0). This means when the weapon rotates, the visual center of the pistol traces a circle of radius 15 around the pivot point. This creates the appearance of the pistol "sliding" in the player's hands.

**Solution approach:**
- Move the MakarovPM further from the player body by increasing its position offset
- Reduce the sprite offset to bring the pivot point closer to the grip area
- This minimizes the visual arc during rotation and keeps the pistol stable

## Existing Patterns

The codebase already has similar patterns:
- **Enemy stun**: Enemies have hit reactions that temporarily affect behavior
- **Weapon detection**: `_detect_and_apply_weapon_pose()` handles different weapon types
- **Arm positioning**: Different poses for rifle, SMG, shotgun via offset constants

## Implementation Files Modified

1. `scripts/characters/player.gd` - Add stun effect to GDScript player
2. `Scripts/Characters/Player.cs` - Add stun effect to C# player
3. `scenes/weapons/csharp/MakarovPM.tscn` - Adjust sprite scale and position
4. `scenes/characters/csharp/Player.tscn` - Adjust MakarovPM position offset
