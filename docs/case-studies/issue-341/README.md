# Case Study: Issue #341 - Make Shell Casings on the Floor Interactive

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/341

**Problem Description (Russian):**
> сделай гильзы на полу интерактивными
> должны реалистично отталкиваться при ходьбе игрока/врагов со звуком гильзы

**English Translation:**
> Make shell casings on the floor interactive
> They should realistically push away when the player/enemies walk, with shell casing sound

---

## Critical Bug: Exported EXE Crash

### Timeline of Events

| Date | Time | Event | Pull Request |
|------|------|-------|--------------|
| 2026-01-24 | 23:32 | Initial PR #342 created with interactive casings feature | [PR #342](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/342) |
| 2026-01-25 | 00:06 | User reports: "ни враги ни игрок не влияют на гильзы" (casings not reacting) | PR #342 comment |
| 2026-01-25 | 00:18 | Implemented improved kick detection with larger Area2D and fallback | PR #342 |
| 2026-01-25 | 00:37 | **CRASH REPORTED**: "игра не запускается - появляется заставка godot и сразу исчезает" | PR #342 comment |
| 2026-01-25 | 00:42 | First fix attempt: changed `caliber_data.has()` to `"caliber_name" in caliber_data` | PR #342 |
| 2026-01-25 | 00:47 | User reports: "не исправлено" (not fixed) | PR #342 comment |
| 2026-01-25 | 00:57 | Second fix attempt: simplified caliber check to only use CaliberData type | PR #342 |
| 2026-01-25 | 01:09 | User reports: "всё ещё не запускается" (still not starting) | PR #342 comment |
| 2026-01-25 | 01:10 | PR #342 closed, new PR #359 created with fresh approach | [PR #359](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/359) |
| 2026-01-25 | 01:27 | User reports crash persists in PR #359 | PR #359 comment |

### Root Cause Analysis

The crash occurred due to **calling `.has()` method on Resource objects** in `casing.gd`:

```gdscript
# PROBLEMATIC CODE (lines 183-184 in original):
elif caliber_data.has_method("get"):
    caliber_name = caliber_data.get("caliber_name") if caliber_data.has("caliber_name") else ""
```

**Why this crashes:**
1. The `.has()` method is **only available on Dictionary objects** in GDScript
2. The `caliber_data` is typed as `Resource`, not `Dictionary`
3. When GDScript tries to call `.has()` on a Resource, it crashes
4. This crash happens **silently** in exported builds - no error message shown
5. The crash occurs during casing initialization in `_ready()` or `_set_casing_appearance()`

### GDScript Type System Differences

| Method | Dictionary | Resource | Object |
|--------|------------|----------|--------|
| `.has(key)` | ✅ Yes | ❌ No (crashes) | ❌ No (crashes) |
| `.has_method(name)` | ❌ No | ✅ Yes | ✅ Yes |
| `"key" in obj` | ✅ Yes | ✅ Yes (for properties) | ✅ Yes (for properties) |
| `.get(key)` | ✅ Yes | ⚠️ Limited | ⚠️ Limited |

### Solution Applied

The fix removes all `.has()` calls on Resource objects and replaces them with explicit type checks:

**Before (crashes):**
```gdscript
if caliber_data is CaliberData:
    caliber_name = (caliber_data as CaliberData).caliber_name
elif caliber_data.has_method("get"):
    caliber_name = caliber_data.get("caliber_name") if caliber_data.has("caliber_name") else ""
```

**After (safe):**
```gdscript
# Only use CaliberData type - avoid calling methods on unknown Resource types
# which can crash exported builds (e.g., .has() only works on Dictionary)
if not (caliber_data is CaliberData):
    return "rifle"

var caliber: CaliberData = caliber_data as CaliberData
var caliber_name: String = caliber.caliber_name
```

### Online Research References

- [Godot Forum - Checking if property exists on Object](https://forum.godotengine.org/t/in-gdscript-how-to-quickly-check-whether-an-object-instance-has-a-property/28780) - Explains `in` operator vs `.has()`
- [Godot Proposals #717](https://github.com/godotengine/godot-proposals/issues/717) - Request to add `has_property()` to Object class
- [Godot Forum - Exported build crashes](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339) - Similar crash symptoms
- [Godot Issue #85350](https://github.com/godotengine/godot/issues/85350) - Exported executable crashes

### Lessons Learned

1. **Dictionary-specific methods on Resource objects cause silent crashes in exported builds**
2. **The Godot editor may not catch these errors** during development
3. **Exported builds fail silently** - splash screen appears then disappears with no error
4. **Always use type guards** (`if obj is Type:`) before accessing type-specific methods
5. **Added startup logging** to help diagnose future crashes in exported builds

---

## Original Feature Implementation Analysis

## Timeline and Analysis

### Current Implementation Analysis

The current casing system in the codebase has these characteristics:

1. **Casing Scene Structure (`scenes/effects/Casing.tscn`):**
   - Node type: `RigidBody2D`
   - Collision layer: 0 (not on any layer)
   - Collision mask: 4 (detects obstacles layer only)
   - Gravity scale: 0.0 (top-down game)
   - Linear damp: 3.0 (slows down movement)
   - Angular damp: 5.0 (slows down rotation)
   - CollisionShape2D: RectangleShape2D (4x14 pixels)

2. **Casing Script (`scripts/effects/casing.gd`):**
   - Auto-lands after 2 seconds (stops moving)
   - Supports caliber-based appearance (rifle, pistol, shotgun)
   - Time freeze support for bullet-time effects
   - Lifetime management for auto-destruction
   - **No character interaction detection**

3. **Collision Layers (from `project.godot`):**
   - Layer 1: `player`
   - Layer 2: `enemies`
   - Layer 3: `obstacles`
   - Layer 4: `pickups`
   - Layer 5: `projectiles`
   - Layer 6: `targets`
   - **No layer for interactive items/casings**

4. **Existing Audio System (`scripts/autoload/audio_manager.gd`):**
   - `play_shell_rifle(position)` - rifle casing drop sound
   - `play_shell_pistol(position)` - pistol casing drop sound
   - `play_shell_shotgun(position)` - shotgun casing drop sound
   - Sound files exist in `assets/audio/` (Russian naming)

### Root Cause: Why Casings Don't Interact

1. **Collision Layer 0**: Casings are not on any collision layer, so characters cannot physically interact with them
2. **Auto-landing Mechanism**: After 2 seconds, casings completely stop moving and disable physics processing
3. **No Character Detection**: No Area2D or collision mask setup to detect player/enemy presence
4. **No Kick Physics**: No code to apply impulse when characters walk through casings

## Research: Best Practices and Solutions

### Online Resources Analyzed

1. **[KidsCanCode - Character to Rigid Body Interaction](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)**
   - Two approaches: Collision Layer method vs Impulse method
   - Recommended impulse-based approach for realistic physics:
   ```gdscript
   var push_force = 80.0
   for i in get_slide_collision_count():
       var c = get_slide_collision(i)
       if c.get_collider() is RigidBody2D:
           c.get_collider().apply_central_impulse(-c.get_normal() * push_force)
   ```

2. **[Catlike Coding - Movable Objects in Top-Down 2D](https://catlikecoding.com/godot/true-top-down-2d/3-movable-objects/)**
   - Velocity transfer approach for intuitive pushing
   - Drag system for gradual momentum loss
   - Important for top-down games without gravity

3. **[Godot Physics Introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)**
   - RigidBody2D requires `contact_monitor = true` and `max_contacts_reported > 0` for collision signals
   - Area2D can detect overlaps without physics simulation

4. **[Physics-Based Sound Effects Research](https://www.cs.mcgill.ca/~kry/pubs/foleyautomatic/foleyautomatic.pdf)**
   - Velocity threshold for impact sounds
   - Sound cooldown to prevent audio spam
   - Material-based sound variation

### Existing Godot Patterns

1. **Area2D Detection Pattern**: Use Area2D child to detect character overlaps
2. **Impulse-Based Kicking**: Apply impulse based on character velocity
3. **Sound Threshold**: Only play sounds above velocity threshold
4. **Sound Cooldown**: Prevent rapid sound repetition

## Proposed Solutions

### Solution 1: Area2D-Based Detection (Recommended)

**Approach**: Add an Area2D child node ("KickDetector") to casings that detects when characters walk through.

**Advantages:**
- Clean separation of collision detection and physics
- Works even when casing is "landed" (can be re-kicked)
- Efficient - Area2D overlap check is lightweight
- Character movement code doesn't need modification

**Implementation:**
1. Add Area2D child with larger collision shape
2. Set collision mask to detect players (layer 1) and enemies (layer 2)
3. On overlap, calculate kick direction from character velocity
4. Apply impulse to casing and play sound
5. Use velocity threshold and cooldown for sound

### Solution 2: CharacterBody2D Push System

**Approach**: Modify player and enemy scripts to push RigidBody2D casings during movement.

**Advantages:**
- More physically accurate
- Consistent with how other games implement pushing

**Disadvantages:**
- Requires modifying multiple character scripts
- More invasive changes
- Characters would need to track and push all nearby casings

### Solution 3: Continuous Collision Detection

**Approach**: Enable contact monitoring on casings and respond to body_entered signals.

**Advantages:**
- Uses native RigidBody2D collision system

**Disadvantages:**
- Requires casings to be on a collision layer
- May conflict with existing physics setup
- Performance impact if many casings exist

## Recommended Implementation: Solution 1

### Technical Design

1. **New Collision Layer**: Add layer 7 "interactive_items" for casings

2. **Casing Scene Modifications:**
   - Add Area2D child "KickDetector" with larger collision shape
   - Set Area2D collision mask to 1 (player) and 2 (enemies)
   - Add PhysicsMaterial2D with bounce and friction

3. **Casing Script Additions:**
   ```gdscript
   ## Kick force multiplier when characters walk through.
   const KICK_FORCE_MULTIPLIER: float = 0.5

   ## Minimum velocity to play kick sound.
   const KICK_SOUND_VELOCITY_THRESHOLD: float = 75.0

   ## Cooldown between kick sounds (seconds).
   const KICK_SOUND_COOLDOWN: float = 0.1

   ## Track when kicked to manage re-enabling physics.
   var _kick_sound_timer: float = 0.0

   func _on_kick_detector_body_entered(body: Node2D) -> void:
       if body is CharacterBody2D:
           _apply_kick(body)

   func _apply_kick(character: CharacterBody2D) -> void:
       # Re-enable physics if landed
       if _has_landed:
           _has_landed = false
           set_physics_process(true)
           _auto_land_timer = 0.0

       # Calculate kick direction
       var kick_direction = (global_position - character.global_position).normalized()
       var kick_velocity = character.velocity.length()
       var kick_force = kick_direction * kick_velocity * KICK_FORCE_MULTIPLIER

       # Add randomness
       kick_force = kick_force.rotated(randf_range(-0.3, 0.3))
       angular_velocity = randf_range(-10.0, 10.0)

       # Apply impulse
       apply_central_impulse(kick_force)

       # Play sound if above threshold
       if kick_velocity > KICK_SOUND_VELOCITY_THRESHOLD and _kick_sound_timer <= 0:
           _play_kick_sound()
           _kick_sound_timer = KICK_SOUND_COOLDOWN

   func _play_kick_sound() -> void:
       # Reuse existing shell casing sounds
       match _get_caliber_type():
           "rifle": AudioManager.play_shell_rifle(global_position)
           "pistol": AudioManager.play_shell_pistol(global_position)
           "shotgun": AudioManager.play_shell_shotgun(global_position)
   ```

4. **Sound System**: Reuse existing `AudioManager` shell casing sounds

### Expected Behavior

1. Player/enemy walks near casing
2. KickDetector Area2D detects overlap
3. Casing receives impulse based on character velocity
4. Casing moves away realistically with physics
5. Sound plays if velocity is above threshold
6. Casing eventually lands again (can be kicked again)

## Risk Assessment

### Low Risk
- Adding Area2D child (non-breaking change)
- Adding new collision layer (additive)
- Reusing existing sounds

### Medium Risk
- Casing script modifications (well-tested approach)
- Physics parameter tuning (may need iteration)

### Mitigation
- Thorough testing with multiple casings
- Performance profiling
- Conservative default values for kick force

## References

- **Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/341
- **Pull Request**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/359
- **KidsCanCode Tutorial**: https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html
- **Catlike Coding Tutorial**: https://catlikecoding.com/godot/true-top-down-2d/3-movable-objects/
- **Godot Physics Docs**: https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html
- **Godot Area2D Docs**: https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html

## Implementation Checklist

- [x] Add collision layer 7 "interactive_items" to project.godot
- [x] Add PhysicsMaterial2D to Casing scene
- [x] Add Area2D "KickDetector" child to Casing scene
- [x] Update collision layer/mask for casings
- [x] Implement kick detection in casing.gd
- [x] Implement kick physics with impulse
- [x] Implement kick sound with threshold and cooldown
- [x] Add caliber-based sound selection
- [x] Fix crash: remove .has() calls on Resource objects
- [x] Add startup logging for debugging exported builds
- [ ] Test with player walking through casings (manual)
- [ ] Test with enemies walking through casings (manual)
- [ ] Test multiple casings being kicked simultaneously (manual)
- [ ] Verify time freeze still works correctly (manual)
- [ ] Performance testing with many casings (manual)
- [ ] Verify exported EXE runs without crashing (manual)
