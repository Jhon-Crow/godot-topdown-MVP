# Issue 222: Codebase Analysis

## Date: 2026-01-22

## Project Structure Overview

This is a Godot 4 top-down game project using a hybrid C#/GDScript approach.

### Key Files

#### Weapon Implementation
- **`Scripts/AbstractClasses/BaseWeapon.cs`** (600 lines) - Base class for all weapons
  - Handles firing, ammunition, magazine management
  - Provides reload functionality via `StartReload()`, `InstantReload()`, `StartReloadSequence()`
  - Emits signals: `Fired`, `ReloadStarted`, `ReloadFinished`, `AmmoChanged`, `MagazinesChanged`

- **`Scripts/Weapons/AssaultRifle.cs`** (812 lines) - Assault rifle implementation
  - Extends BaseWeapon with fire modes (Automatic/Burst)
  - Has laser sight, recoil, spread mechanics
  - Currently NO reload animation - only sound effects

#### Player Implementation
- **`scripts/characters/player.gd`** (1456 lines) - Main player controller
  - Has detailed walking animation system using programmatic sprite position/rotation
  - Has grenade throwing animation system with multiple phases
  - Has reload FUNCTIONALITY via input handling (R-F-R sequence)
  - Currently NO visual reload animation for rifle
  - Has arm sprites: `_left_arm_sprite` and `_right_arm_sprite`

#### Player Scene Structure
- **`scenes/characters/Player.tscn`**:
  ```
  Player (CharacterBody2D)
  ├── CollisionShape2D
  ├── PlayerModel (Node2D)
  │   ├── Body (Sprite2D, z_index=1)
  │   ├── LeftArm (Sprite2D, z_index=4, position=(24, 6))
  │   ├── RightArm (Sprite2D, z_index=4, position=(-2, 6))
  │   ├── Head (Sprite2D, z_index=3)
  │   └── WeaponMount (Node2D)
  ├── Camera2D
  ├── HitArea
  └── ThreatSphere
  ```

## Current Animation System Analysis

### Walking Animation (Reference Implementation)
```gdscript
func _update_walk_animation(delta: float, input_direction: Vector2) -> void:
    # Uses sine waves for bobbing motion
    var body_bob := sin(_walk_anim_time * 2.0) * 1.5 * walk_anim_intensity
    var head_bob := sin(_walk_anim_time * 2.0) * 0.8 * walk_anim_intensity
    var arm_swing := sin(_walk_anim_time) * 3.0 * walk_anim_intensity

    # Apply offsets to sprites
    _body_sprite.position = _base_body_pos + Vector2(0, body_bob)
    _left_arm_sprite.position = _base_left_arm_pos + Vector2(arm_swing, 0)
    _right_arm_sprite.position = _base_right_arm_pos + Vector2(-arm_swing, 0)
```

### Grenade Animation (Reference Implementation)
The grenade animation system is an excellent reference with:
1. **Phase-based state machine** (`GrenadeAnimPhase` enum)
2. **Position constants** for arm targets (e.g., `ARM_LEFT_CHEST`, `ARM_RIGHT_THROW`)
3. **Rotation constants** for arm orientations
4. **Duration constants** for each phase
5. **Smooth interpolation** using `lerp()` and `lerpf()`

## Current Reload Logic (No Animation)

The reload happens in three steps (R-F-R sequence):
1. **Step 1 (R press)**: `_reload_sequence_step = 1`, plays `play_reload_mag_out` sound
2. **Step 2 (F press)**: `_reload_sequence_step = 2`, plays `play_reload_mag_in` sound
3. **Step 3 (R press)**: Calls `_complete_reload()`, plays `play_m16_bolt` sound

Currently, only sounds play - NO arm movement animation.

## Proposed Solution

Following the pattern established by the grenade animation system:

1. Create `ReloadAnimPhase` enum similar to `GrenadeAnimPhase`
2. Add position/rotation constants for reload arm movements
3. Add `_update_reload_animation()` function
4. Integrate with existing reload input handling

### Animation Phases to Implement
1. **GRAB_MAGAZINE**: Left hand moves to chest/vest area to grab magazine
2. **INSERT_MAGAZINE**: Left hand moves to weapon, inserts magazine
3. **PULL_BOLT**: Right hand (or both) pulls charging handle
4. **RETURN_IDLE**: Arms return to normal holding position

## Sources
- [Godot 2D Sprite Animation Docs](https://docs.godotengine.org/en/stable/tutorials/2d/2d_sprite_animation.html)
- [AnimatedSprite2D Class Reference](https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html)
- [Top-Down Movement GDQuest](https://www.gdquest.com/tutorial/godot/2d/top-down-movement/)
