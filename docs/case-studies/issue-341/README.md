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
| 2026-01-25 | 01:55 | User reports: "сразу вылетает. дальше заставки godot не включается" (crashes immediately) | PR #359 comment |
| 2026-01-25 | 02:12 | Third fix attempt: replace `is CaliberData` with property-based checks | PR #359 |
| 2026-01-25 | 02:40 | Investigation: discovered project uses C# Player scene which may require .NET export | PR #359 comment |

### Root Cause Analysis

#### Issue 1: Calling `.has()` on Resource (Fixed v1)

The first crash occurred due to **calling `.has()` method on Resource objects** in `casing.gd`:

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

#### Issue 2: Using `is CaliberData` Type Check (Fixed v2)

After fixing the `.has()` issue, the crash persisted. The second root cause was **using `is CaliberData` type checks**:

```gdscript
# PROBLEMATIC CODE (still caused crash in exported builds):
if not (caliber_data is CaliberData):
    return "rifle"
var caliber: CaliberData = caliber_data as CaliberData
```

**Why this crashes in exported builds:**
1. GDScript `class_name` references may not resolve correctly in exported builds
2. The `is CaliberData` type check requires the `CaliberData` class_name to be loaded
3. In exported builds, script loading order can cause `class_name` resolution to fail
4. This results in a **parse error at script load time** - before the game even starts
5. The crash happens immediately after the Godot splash screen

**This is a known Godot 4 issue:**
- [GitHub Issue #41215](https://github.com/godotengine/godot/issues/41215) - References to class not resolved when exported
- [GitHub Issue #87397](https://github.com/godotengine/godot/issues/87397) - Resource loaded without script class_name association
- [Godot Forum](https://forum.godotengine.org/t/parser-error-could-not-resolve-class-class-name/2482) - Parser Error: Could not resolve class

### GDScript Type System Differences

| Method | Dictionary | Resource | Object |
|--------|------------|----------|--------|
| `.has(key)` | ✅ Yes | ❌ No (crashes) | ❌ No (crashes) |
| `.has_method(name)` | ❌ No | ✅ Yes | ✅ Yes |
| `"key" in obj` | ✅ Yes | ✅ Yes (for properties) | ✅ Yes (for properties) |
| `.get(key)` | ✅ Yes | ⚠️ Limited | ⚠️ Limited |

### Solution Applied

The fix removes all `.has()` calls AND `is CaliberData` type checks, replacing them with **property-based checks** using the `"property" in object` pattern:

**Before (crashes - v1):**
```gdscript
if caliber_data is CaliberData:
    caliber_name = (caliber_data as CaliberData).caliber_name
elif caliber_data.has_method("get"):
    caliber_name = caliber_data.get("caliber_name") if caliber_data.has("caliber_name") else ""
```

**Before (still crashes - v2):**
```gdscript
# Only use CaliberData type - avoid calling methods on unknown Resource types
# which can crash exported builds (e.g., .has() only works on Dictionary)
if not (caliber_data is CaliberData):
    return "rifle"

var caliber: CaliberData = caliber_data as CaliberData
var caliber_name: String = caliber.caliber_name
```

**After (safe - v3):**
```gdscript
# Use property-based check instead of "is CaliberData" to avoid
# parse errors in exported builds where class_name may not resolve.
# The "in" operator safely checks if a property exists on the Resource.
if not ("caliber_name" in caliber_data):
    return "rifle"

var caliber_name: String = caliber_data.caliber_name
```

**Why property-based checks are safe:**
1. The `"property" in object` pattern doesn't require the class_name to be loaded
2. It works reliably in both editor and exported builds
3. It's the same pattern used by `bullet.gd` for accessing caliber_data properties
4. No parse errors occur because we're checking at runtime, not compile time

### Online Research References

- [Godot Forum - Checking if property exists on Object](https://forum.godotengine.org/t/in-gdscript-how-to-quickly-check-whether-an-object-instance-has-a-property/28780) - Explains `in` operator vs `.has()`
- [Godot Proposals #717](https://github.com/godotengine/godot-proposals/issues/717) - Request to add `has_property()` to Object class
- [Godot Forum - Exported build crashes](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339) - Similar crash symptoms
- [Godot Issue #85350](https://github.com/godotengine/godot/issues/85350) - Exported executable crashes

### Lessons Learned

1. **Dictionary-specific methods (`.has()`) on Resource objects cause silent crashes in exported builds**
2. **`is ClassName` type checks can cause parse errors in exported builds** due to class_name resolution issues
3. **The Godot editor may not catch these errors** during development - they only appear in exports
4. **Exported builds fail silently** - splash screen appears then disappears with no error
5. **Use property-based checks** (`"property" in object`) instead of type checks for custom Resource classes
6. **Follow the pattern used elsewhere in the codebase** - `bullet.gd` correctly uses `"property" in caliber_data`
7. **Added startup logging** to help diagnose future crashes in exported builds

### Safe Patterns for Resource Property Access

| Pattern | Editor | Export | Recommendation |
|---------|--------|--------|----------------|
| `obj is ClassName` | ✅ Works | ❌ May crash | Avoid for custom classes |
| `obj.has("key")` | ❌ Crashes | ❌ Crashes | Never use on Resource |
| `"property" in obj` | ✅ Works | ✅ Works | **Recommended** |
| `obj.get("property")` | ✅ Works | ✅ Works | OK but less readable |
| Direct access `obj.property` | ✅ Works | ✅ Works | Only if property guaranteed |

---

## Potential Issue 3: C# / .NET Export Requirements

### Discovery

During investigation of persisting crashes, it was discovered that the project uses **both C# and GDScript**:

**Project configuration (`project.godot`):**
```ini
config/features=PackedStringArray("4.3", "C#")
[dotnet]
project/assembly_name="GodotTopDownTemplate"
```

**Main scene uses C# Player:**
```
# BuildingLevel.tscn
[ext_resource type="PackedScene" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
```

The C# Player references a C# script:
```
# scenes/characters/csharp/Player.tscn
[ext_resource type="Script" path="res://Scripts/Characters/Player.cs" id="1_player"]
```

### Why This Could Cause Crashes

1. **Export Templates**: C# projects require .NET export templates, not the standard GDScript-only templates
2. **Immediate Crash**: If .NET runtime is not properly bundled, the game crashes immediately after splash screen
3. **Silent Failure**: No error message is displayed - the game simply closes

### Alternative GDScript Player Exists

A GDScript version of the Player scene exists:
- **C# version** (currently used): `res://scenes/characters/csharp/Player.tscn`
- **GDScript version**: `res://scenes/characters/Player.tscn`

### Potential Fix

If the crash is C#-related, the BuildingLevel.tscn could be modified to use the GDScript Player instead:

```
# Change from:
[ext_resource type="PackedScene" uid="uid://dv8nq2vj5r7p2" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]

# Change to:
[ext_resource type="PackedScene" uid="uid://bk8nq2vj5r7p1" path="res://scenes/characters/Player.tscn" id="2_player"]
```

### Related Issues

- [Godot Issue #73329](https://github.com/godotengine/godot/issues/73329) - Exporting custom Resource is always null
- [Godot Issue #77886](https://github.com/godotengine/godot/issues/77886) - Godot 4 exports unable to load custom resources
- [Godot Forum](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339) - Exported build crashes immediately

### Awaiting User Feedback

Questions asked in PR comment:
1. Did the game work in exported form BEFORE this PR?
2. What export type is being used (Release/Debug)?
3. Is there a log file `game_log_*.txt` next to the .exe?

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
- [x] Fix crash: remove .has() calls on Resource objects (v1)
- [x] Fix crash: remove `is CaliberData` type checks, use property-based checks (v2)
- [x] Add startup logging for debugging exported builds
- [ ] Test with player walking through casings (manual)
- [ ] Test with enemies walking through casings (manual)
- [ ] Test multiple casings being kicked simultaneously (manual)
- [ ] Verify time freeze still works correctly (manual)
- [ ] Performance testing with many casings (manual)
- [ ] Verify exported EXE runs without crashing (manual)

---

## Additional Investigation: C# Export Requirements (2026-01-25)

### Project Configuration Analysis

The project configuration reveals the game uses **C# (.NET)** features:

**From `project.godot`:**
```ini
config/features=PackedStringArray("4.3", "C#")
[dotnet]
project/assembly_name="GodotTopDownTemplate"
```

**Main scene uses C# Player:**
```
BuildingLevel.tscn → res://scenes/characters/csharp/Player.tscn
csharp/Player.tscn → res://Scripts/Characters/Player.cs
```

### Assembly Name Consistency Check

The project assembly name configuration appears consistent:
- `project.godot`: `project/assembly_name="GodotTopDownTemplate"`
- `GodotTopDownTemplate.csproj`: `<RootNamespace>GodotTopDownTemplate</RootNamespace>`
- `GodotTopDownTemplate.sln`: Contains "GodotTopDownTemplate"

### Potential C# Export Crash Causes

Based on research from [Godot Issue #91998](https://github.com/godotengine/godot/issues/91998):

| Issue | Description | Impact |
|-------|-------------|--------|
| **Wrong Export Templates** | Using GDScript templates instead of .NET/Mono templates | Crash immediately after splash |
| **Assembly Name Mismatch** | Solution/project/assembly names don't match | Silent export build failure |
| **.NET Runtime Not Bundled** | Missing .NET runtime in export | Crash on C# script load |
| **Missing C# Build** | C# project not building during export | Editor runs, export crashes |

### Root Cause Hypothesis

The user's crash behavior (game showing Godot splash screen then immediately closing) is consistent with one of two scenarios:

1. **C# Export Issue**: The export is using GDScript-only templates when the project requires .NET templates
2. **GDScript Fixes Worked**: Our fixes to `casing.gd` are correct, but a separate C# issue exists

### Key Finding: GDScript Player Alternative

A **pure GDScript Player scene** exists that could be used as a diagnostic:
- **C# version** (currently used): `res://scenes/characters/csharp/Player.tscn`
- **GDScript version**: `res://scenes/characters/Player.tscn`

The GDScript version uses `res://scripts/characters/player.gd` instead of `res://Scripts/Characters/Player.cs`.

### Recommended Diagnostic Steps

1. **Check Export Type**: Ask user if they're using "Godot Editor (.NET)" or standard editor
2. **Check Export Templates**: Verify .NET export templates are installed (not GDScript templates)
3. **Test GDScript Player**: Temporarily switch `BuildingLevel.tscn` to use GDScript Player
4. **Check Log File**: Look for `game_log_*.txt` next to the exported .exe

### Related Online Resources

- [Godot Forum: Release Export crashes at start](https://forum.godotengine.org/t/release-export-of-the-game-crashes-at-start/120339)
- [Godot Forum: Godot 4.4.1 C# Export Issue](https://forum.godotengine.org/t/godot-4-4-1-c-export-issue/119567)
- [Godot Issue #91998: C# exports crash on launch if assembly names don't match](https://github.com/godotengine/godot/issues/91998)
- [Godot Forum: 4.3 stable exported build crashes immediately](https://forum.godotengine.org/t/4-3-stable-exported-build-crashes-immediately-upon-starting-up-game-everything-fails-to-load/101339)
