# Case Study: Issue #149 - Impact Effects Analysis

## Issue Summary

**Issue**: Add visual hit effects when bullets impact different surfaces
**Status**: Partially implemented but not working correctly
**Date**: 2026-01-21

## User Feedback (from PR #151 comments)

The repository owner (Jhon-Crow) reported the following problems:

1. **"от пуль игрока из стен не вылетает пыль"** - Dust doesn't fly out of walls from player bullets
2. **"эффект попадания в стену должен быть реалистичнее (по физике, мелкие частицы)"** - Wall hit effect should be more realistic (physics, smaller particles)
3. **"частицы крови должны вылетать реалистично (референс first cut samurai duel)"** - Blood particles should fly realistically (reference: First Cut: Samurai Duel)
4. **"пыль должна повисать в помещении"** - Dust should linger in the room
5. **"кровь должна оставаться на полу"** - Blood should stay on the floor

## Technical Analysis

### Current Implementation

The impact effects system consists of:

1. **ImpactEffectsManager** (`scripts/autoload/impact_effects_manager.gd`)
   - Autoload singleton managing particle effects
   - Methods: `spawn_dust_effect()`, `spawn_blood_effect()`, `spawn_sparks_effect()`

2. **Effect Scenes** (`scenes/effects/`)
   - `DustEffect.tscn` - GPUParticles2D for wall dust
   - `BloodEffect.tscn` - GPUParticles2D for blood splatter
   - `SparksEffect.tscn` - GPUParticles2D for armor sparks

3. **Bullet Script** (`scripts/projectiles/bullet.gd`)
   - `_spawn_wall_hit_effect()` method calls ImpactEffectsManager

### Root Cause Investigation

#### Issue 1: Dust not appearing from player bullets

Looking at the bullet collision flow in `bullet.gd`:

```gdscript
func _on_body_entered(body: Node2D) -> void:
    # Check if this is the shooter - don't collide with own body
    if shooter_id == body.get_instance_id():
        return  # Pass through the shooter

    # Check if this is a dead enemy - bullets should pass through dead entities
    if body.has_method("is_alive") and not body.is_alive():
        return  # Pass through dead entities

    # Hit a static body (wall or obstacle) or alive enemy body
    # Try to ricochet off static bodies (walls/obstacles)
    if body is StaticBody2D or body is TileMap:
        if _try_ricochet(body):
            return  # Bullet ricocheted, don't destroy

    # Spawn wall dust effect
    _spawn_wall_hit_effect(body)
    # ...
```

**Finding**: The code path seems correct. `_spawn_wall_hit_effect()` should be called when:
- Bullet hits a StaticBody2D/TileMap and ricochet FAILS
- Bullet hits any other body type

The issue might be:
1. **Effect scene not loading** - Check if scenes exist at expected paths
2. **Scene node not being added to tree correctly**
3. **Particles not emitting** - Check `emitting = true` state
4. **Particles not visible** - Z-index, modulate, or scale issues

Let me check the `_add_effect_to_scene` method:

```gdscript
func _add_effect_to_scene(effect: Node2D) -> void:
    var scene := get_tree().current_scene
    if scene:
        scene.add_child(effect)
    else:
        # Fallback: add to self (autoload node)
        add_child(effect)
```

**Potential Issue**: If `get_tree().current_scene` is null during the bullet collision, effects might be added to the autoload node which could have rendering issues.

### Issue 2-5: Effect Realism

Current particle settings are basic:

| Effect | Amount | Lifetime | Spread | Initial Velocity | Gravity |
|--------|--------|----------|--------|------------------|---------|
| Dust | 12 | 0.5s | 70° | 80-180 px/s | 150 |
| Blood | 20 | 0.6s | 45° | 100-250 px/s | 300 |
| Sparks | 8 | 0.3s | 90° | 150-350 px/s | 400 |

**Problems**:
1. Dust lifetime too short (0.5s) - should linger longer (3-5s)
2. Blood doesn't leave persistent stains - needs decal system
3. Particles too large (scale 0.3-0.8) - should be smaller (0.1-0.4)
4. Not enough particles for realistic effect

### Reference: First Cut: Samurai Duel

Based on research, First Cut: Samurai Duel uses:
- Pressure-based blood spurts with varying velocity
- High particle counts (up to 10000)
- Persistent blood stains on environment and characters
- Blood drips and secondary effects
- Customizable parameters for Multiplier, Gravity, Volume, Stain Chance

## Proposed Solutions

### Fix 1: Add Debug Logging

Add logging to trace effect spawning:

```gdscript
func spawn_dust_effect(position: Vector2, surface_normal: Vector2, caliber_data: Resource = null) -> void:
    print("[ImpactEffectsManager] spawn_dust_effect called at ", position)
    if _dust_effect_scene == null:
        print("[ImpactEffectsManager] ERROR: _dust_effect_scene is null")
        return
    # ...
```

### Fix 2: Improve Dust Effect

- Increase lifetime to 2.0s (lingering dust)
- Add damping to slow down particles
- Smaller particles (scale 0.1-0.3)
- More particles (20-30)
- Lower gravity for floating effect

### Fix 3: Improve Blood Effect

- Higher initial velocity for spray effect
- More particles (40-60)
- Add secondary "drip" emitter
- Implement decal/stain system for persistence

### Fix 4: Add Blood Decals

Create a new system that:
1. Spawns a Sprite2D/CanvasItem at blood impact position
2. Uses blood splatter textures
3. Persists until scene change or manual cleanup
4. Has maximum stain limit to prevent performance issues

## Files Changed

- `scripts/autoload/impact_effects_manager.gd` - Add decal system
- `scenes/effects/DustEffect.tscn` - Improve particle settings
- `scenes/effects/BloodEffect.tscn` - Improve particle settings
- `scenes/effects/BloodDecal.tscn` (new) - Blood stain sprite

## Game Log Analysis

The attached `game_log_20260121_031820.txt` shows:
- Multiple bullet hits registering ("Hit taken")
- Sound propagation working correctly
- No evidence of impact effects being triggered (no logging for effects)

This suggests the effect system may be silently failing or not being called.
