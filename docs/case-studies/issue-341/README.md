# Case Study: Issue #341 - Interactive Shell Casings

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/341

**Original Request (Russian):**
> сделай гильзы на полу интерактивными
> должны реалистично отталкиваться при ходьбе игрока/врагов со звуком гильзы

**English Translation:**
> Make shell casings on the floor interactive
> They should realistically push away when the player/enemies walk, with shell casing sound

---

## Executive Summary

This case study documents the investigation into implementing interactive shell casings that can be kicked by players and enemies. **The previous implementation attempts using Area2D signals have failed**, and this document presents **alternative approaches** based on thorough research.

### Problem Summary

The previous implementation attempted to use:
1. An Area2D "KickDetector" child node on casings to detect characters entering
2. `body_entered` signal to trigger kick physics
3. Direct impulse application from within the casing script

**Issues encountered:**
- Exported builds crash immediately after splash screen
- Characters may not interact with casings in all cases
- Potential `class_name` resolution issues in exported builds

---

## Alternative Implementation Approaches

### Approach A: Character-Side Push Detection (RECOMMENDED)

**Concept:** Instead of the casing detecting characters, the **character detects collisions with casings** after `move_and_slide()` and applies impulses.

**Why this is better:**
1. **More reliable collision detection** - Uses built-in collision system via `get_slide_collision()`
2. **No signal connection issues** - No signals that might fail in exported builds
3. **Single point of control** - Logic lives in character scripts, easier to debug
4. **Proven pattern** - This is the officially recommended approach from [Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/)

**Implementation:**

In `scripts/characters/player.gd`:
```gdscript
const CASING_PUSH_FORCE = 50.0

func _physics_process(delta: float) -> void:
    # ... existing movement code ...
    move_and_slide()

    # Push casings after movement
    _push_casings()

func _push_casings() -> void:
    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        if collider is RigidBody2D and collider.has_method("receive_kick"):
            var push_dir = -collision.get_normal()
            collider.receive_kick(push_dir * velocity.length() * CASING_PUSH_FORCE / 100.0)
```

In `scripts/effects/casing.gd`:
```gdscript
func receive_kick(impulse: Vector2) -> void:
    if _is_time_frozen:
        return
    if _has_landed:
        _has_landed = false
        _auto_land_timer = 0.0
    apply_central_impulse(impulse)
    angular_velocity = randf_range(-10.0, 10.0)
    _play_kick_sound_if_loud_enough(impulse.length())
```

**Collision layer setup:**
- Casing `collision_layer`: Layer for items (e.g., layer 3)
- Casing `collision_mask`: Static bodies (walls, obstacles)
- Player/Enemy `collision_mask`: Must include the items layer

**Pros:**
- Uses Godot's built-in collision detection
- No Area2D nodes or signals needed
- Works reliably in exported builds
- Follows the same pattern used for pushing boxes and other physics objects

**Cons:**
- Requires modifying both player and enemy scripts
- Characters must be set to collide with casings (may affect game feel)

---

### Approach B: Collision Layer One-Way Detection

**Concept:** Configure collision layers so that **casings detect characters, but characters don't detect casings**. The RigidBody2D naturally gets pushed by the physics engine.

**Why this might work:**
1. **Pure physics solution** - No code changes to casing detection
2. **Automatic pushing** - Physics engine handles the interaction
3. **Simpler implementation** - Just collision layer configuration

**Implementation:**

In `scenes/effects/Casing.tscn`:
```
[node name="Casing" type="RigidBody2D"]
collision_layer = 8    # Layer 4 (items)
collision_mask = 7     # Layers 1-3 (player, enemies, walls)
```

In player/enemy scenes, ensure the `collision_mask` does **NOT** include layer 4, but the casing's `collision_mask` **DOES** include player and enemy layers.

**Note:** This approach relies on the physics engine's handling of asymmetric collisions. The RigidBody2D will be pushed when it collides with the CharacterBody2D, even if the CharacterBody2D doesn't "see" it.

**Pros:**
- No script changes needed (just scene configuration)
- Natural physics interactions

**Cons:**
- Less control over push force and direction
- May result in unpredictable behavior (casings clipping through walls)
- The mass of casings won't matter - they'll all be pushed the same

---

### Approach C: Proximity-Based Push (No Collision Required)

**Concept:** In `_physics_process`, check distance to nearby characters and apply forces based on proximity, without requiring actual collisions.

**Why this might work:**
1. **No collision detection issues** - Uses pure distance calculations
2. **Works regardless of collision layers** - Characters don't need to collide with casings
3. **Smooth, natural-looking kicks** - Force can be proportional to character speed

**Implementation:**

In `scripts/effects/casing.gd`:
```gdscript
const KICK_DISTANCE = 20.0  # Pixels
const KICK_FORCE = 30.0

func _physics_process(delta: float) -> void:
    if _is_time_frozen or not _has_landed:
        return

    # Find nearby characters
    var characters = get_tree().get_nodes_in_group("kickable_sources")
    for character in characters:
        if character is CharacterBody2D:
            var distance = global_position.distance_to(character.global_position)
            if distance < KICK_DISTANCE and character.velocity.length() > 10.0:
                _apply_proximity_kick(character)

func _apply_proximity_kick(character: CharacterBody2D) -> void:
    var direction = (global_position - character.global_position).normalized()
    var force = direction * character.velocity.length() * KICK_FORCE / 100.0
    _has_landed = false
    _auto_land_timer = 0.0
    apply_central_impulse(force)
    angular_velocity = randf_range(-10.0, 10.0)
    _play_kick_sound_if_loud_enough(force.length())
```

Player and enemies need to be added to the "kickable_sources" group.

**Pros:**
- No dependency on collision system
- Works regardless of how collisions are configured
- Easy to tune the kick distance and force

**Cons:**
- Less performant (checking distances every frame for every casing)
- May kick casings that are behind walls
- Requires characters to be in a specific group

---

### Approach D: AnimatableBody2D Instead of RigidBody2D

**Concept:** Use `AnimatableBody2D` which is designed for objects that move based on code, not physics. Characters can push them directly via `move_and_slide()`.

**Why this might work:**
1. **Designed for this use case** - AnimatableBody2D is meant for movable platforms and objects
2. **No physics complexity** - Movement is purely code-driven
3. **Simpler mental model** - No mass, gravity, or impulses to worry about

**Implementation:**

Change Casing from RigidBody2D to AnimatableBody2D and implement push handling in `_physics_process()`.

**Cons:**
- Loss of realistic physics behavior (bounce, friction, angular momentum)
- Casings won't tumble realistically
- More code needed for realistic movement simulation

---

## Comparison Matrix

| Approach | Reliability | Performance | Physics Realism | Code Complexity | Export Safety |
|----------|------------|-------------|-----------------|-----------------|---------------|
| A: Character-Side Push | HIGH | HIGH | MEDIUM | MEDIUM | HIGH |
| B: Collision Layer Trick | MEDIUM | HIGH | LOW | LOW | HIGH |
| C: Proximity-Based | HIGH | LOW | LOW | MEDIUM | HIGH |
| D: AnimatableBody2D | HIGH | HIGH | LOW | HIGH | HIGH |

---

## Recommendation

**Approach A (Character-Side Push Detection)** is recommended because:

1. It uses the proven `get_slide_collision()` pattern that is well-documented and tested
2. It keeps the casing script simple (no Area2D, no signals)
3. It's the official recommendation from Godot documentation and tutorials
4. It gives precise control over push force based on character velocity
5. It avoids the potential signal/Area2D issues that caused problems in exported builds

---

## Previous Implementation Analysis

### What Was Tried (PR #359)

1. **Area2D KickDetector approach:**
   - Added Area2D child node to detect characters entering
   - Connected `body_entered` signal to apply kick impulse
   - Changed collision layers to enable interaction

2. **Crash fixes:**
   - Replaced `.has()` calls on Resource with `"key" in object`
   - Replaced `is CaliberData` type checks with property-based checks

### Why It Failed

The root cause is likely one of:

1. **Signal issues in exported builds** - Godot 4.4 dev builds have known issues where signals don't work in exported builds ([GitHub #100097](https://github.com/godotengine/godot/issues/100097))

2. **Area2D one-frame delay** - Area2D `body_entered` signal fires one physics tick late ([GitHub #86199](https://github.com/godotengine/godot/issues/86199)), which may cause missed detections

3. **Class name resolution** - Using `class_name` references in scripts can cause parse errors in exported builds ([GitHub #41215](https://github.com/godotengine/godot/issues/41215))

4. **C#/.NET export configuration** - The project uses hybrid C#/GDScript and may require .NET export templates

---

## Online Research Sources

### Official Documentation
- [Using CharacterBody2D](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html) - Official Godot documentation
- [Physics Introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)

### Tutorials
- [Character to Rigid Body Interaction](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/) - KidsCanCode Godot 4 Recipes
- [Movable Objects in Top-Down 2D](https://catlikecoding.com/godot/true-top-down-2d/3-movable-objects/) - Catlike Coding

### Godot Forum Discussions
- [How to push a RigidBody2D with a CharacterBody2D](https://forum.godotengine.org/t/how-to-push-a-rigidbody2d-with-a-characterbody2d/2681)
- [CharacterBody2d & RigidBody2D Interaction](https://forum.godotengine.org/t/characterbody2d-rigidbody2d-interaction/72851)
- [Area2D body_entered signal not working](https://forum.godotengine.org/t/area2d-body-entered-signal-not-working-at-all/83466)

### Known Godot Issues
- [#100097 - Signals don't work in exported builds (4.4-dev6)](https://github.com/godotengine/godot/issues/100097)
- [#86199 - Area2D body_entered signal fires late](https://github.com/godotengine/godot/issues/86199)
- [#41215 - Class references not resolved when exported](https://github.com/godotengine/godot/issues/41215)
- [#91998 - C# exports crash if assembly names don't match](https://github.com/godotengine/godot/issues/91998)

---

## Existing Libraries and Components

### Relevant Godot Addons

1. **[Godot 4 2D Destructible Objects](https://github.com/VSeryi/Godot-4-2D-Destructible-Objects)**
   - Script that divides sprites into blocks and makes them explode
   - Configurable collision layers and debris behavior
   - May provide useful patterns for debris interaction

2. **[Godot Destruction Physics](https://godotforums.org/d/30024-godot-destruction-physics)**
   - Destruction physics for Godot 4.0
   - Includes debris handling

### Example Projects

1. **[character_vs_rigid](https://github.com/godotrecipes/character_vs_rigid)**
   - Example code from KidsCanCode tutorial
   - Demonstrates the recommended impulse-based pushing pattern

---

## Implementation (Approach A)

**Status: IMPLEMENTED** ✅

The Character-Side Push Detection approach has been implemented with the following changes:

### Collision Layer Configuration

| Entity | `collision_layer` | `collision_mask` | Notes |
|--------|------------------|------------------|-------|
| Casing | 64 (layer 7) | 4 (walls) | Now on dedicated layer for items |
| Player | 1 | 68 (4+64) | Added layer 7 to mask |
| Enemy | 2 | 68 (4+64) | Added layer 7 to mask |

### Files Modified

1. **`scenes/effects/Casing.tscn`**
   - Changed `collision_layer` from 0 to 64 (layer 7)

2. **`scripts/effects/casing.gd`**
   - Added `receive_kick(impulse: Vector2)` method to handle being kicked
   - Added `_play_kick_sound(impulse_strength: float)` for audio feedback
   - Re-enables physics when a landed casing is kicked

3. **`scenes/characters/csharp/Player.tscn`**
   - Changed `collision_mask` from 4 to 68 (added layer 7)

4. **`scenes/characters/Player.tscn`**
   - Changed `collision_mask` from 4 to 68 (added layer 7)

5. **`scenes/objects/Enemy.tscn`**
   - Changed `collision_mask` from 4 to 68 (added layer 7)

6. **`Scripts/AbstractClasses/BaseCharacter.cs`**
   - Added `PushCasings()` method called after `MoveAndSlide()`
   - Uses `GetSlideCollision()` to detect casings and applies impulse

7. **`scripts/objects/enemy.gd`**
   - Added `_push_casings()` method called after `move_and_slide()`
   - Applies push impulse to casings based on velocity

### How It Works

1. After `MoveAndSlide()` (C#) or `move_and_slide()` (GDScript), the character checks all slide collisions
2. For each collision with a `RigidBody2D` that has a `receive_kick` method (i.e., a casing):
   - Calculate push direction from collision normal
   - Calculate push strength based on character velocity
   - Call `receive_kick(impulse)` on the casing
3. The casing:
   - Re-enables physics if it had landed
   - Applies the impulse for realistic physics
   - Adds random spin for visual appeal
   - Plays kick sound if impulse is above threshold

---

## Timeline of Previous Attempts

### PR #342 (Closed)
| Date (UTC) | Event |
|------------|-------|
| 2026-01-24 23:32 | PR created with Area2D approach |
| 2026-01-25 00:06 | User: "casings not reacting" |
| 2026-01-25 00:37 | User: "game crashes after splash" |
| 2026-01-25 01:10 | PR closed |

### PR #359 (Current)
| Date (UTC) | Event |
|------------|-------|
| 2026-01-25 01:10 | PR created with fixes |
| 2026-01-25 01:27 | User: "crashes same way" |
| 2026-01-25 02:12 | Fixed type checks |
| 2026-01-25 05:25 | User: "try different approach" |
| 2026-01-25 08:33 | User: "not fixed, revert and try different approach" |
| 2026-01-25 08:49 | Code reverted, case study updated with alternative approaches |
| 2026-01-25 16:55 | User: "casings don't react to player/enemies" (game now runs without crash) |
| 2026-01-25 16:56 | Implementing Approach A (Character-Side Push Detection) |

---

## Files in This Case Study

- `README.md` - This document
- `issue-341-details.txt` - Original issue description
- `issue-341-comments.txt` - Issue comments
- `pr-342-details.txt` - First PR details
- `pr-342-comments.txt` - First PR comments
- `pr-359-details.txt` - Current PR details
- `pr-359-comments.txt` - Current PR comments
- `logs/` - AI work session logs

---

*Case study last updated: 2026-01-25*
*Status: Approach A (Character-Side Push Detection) IMPLEMENTED*
