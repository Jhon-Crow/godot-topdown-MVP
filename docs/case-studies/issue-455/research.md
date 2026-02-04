# Case Study: Issue #455 - Muzzle Flash and Light Reflection

## Issue Description (Russian)
> у врагов и игрока при выстреле должна происходить вспышка из ствола (небольшое пламя на стволе) и должен появляться отблеск на стенах (чем дальше, тем менее заметный).

## Issue Description (English Translation)
When enemies and the player shoot, there should be:
1. A muzzle flash (small flame at the barrel)
2. Light reflection on walls (less visible the further away)

## Current Codebase Analysis

### Shooting Implementation

#### Player (`scripts/characters/player.gd`)
- `_shoot()` function (lines 584-651)
- Bullet spawned at: `global_position + shoot_direction * bullet_spawn_offset` (offset: 20 pixels)
- Current effects: gunshot sound, shell casing, screen shake, sound propagation
- **No muzzle flash effect currently**

#### Enemy (`scripts/objects/enemy.gd`)
- Three shooting methods: `_shoot()`, `_shoot_with_inaccuracy()`, `_shoot_burst_shot()`
- Bullet spawned at muzzle position via `_get_bullet_spawn_position()`
- `bullet_spawn_offset`: 30 pixels from center
- Current effects: gunshot sound, shell casing ejection, sound propagation
- **No muzzle flash effect currently**

### Existing Visual Effects System

The project uses `ImpactEffectsManager` autoload for spawning effects:
- `DustEffect.tscn` - GPUParticles2D for wall hits
- `BloodEffect.tscn` - GPUParticles2D for lethal hits
- `SparksEffect.tscn` - GPUParticles2D for armor/non-lethal hits
- `Casing.tscn` - RigidBody2D for shell casings

Effects use:
- `GPUParticles2D` nodes with `ParticleProcessMaterial`
- `GradientTexture2D` for particle appearance
- `effect_cleanup.gd` script for auto-removal
- One-shot mode with explosiveness for burst effects

### Scene Structure

**Player Scene:**
```
Player (CharacterBody2D)
├── PlayerModel (Node2D)
│   ├── WeaponMount (Node2D) at position (0, 6)
│   └── Body, Head, Arms (Sprites)
```

**Enemy Scene:**
```
Enemy (CharacterBody2D)
├── EnemyModel (Node2D)
│   ├── WeaponMount (Node2D) at position (0, 6)
│   │   └── WeaponSprite (offset 20, 0)
│   └── Body, Head, Arms (Sprites)
```

## Online Research Findings

### Muzzle Flash Implementation Approaches

#### 1. GPUParticles2D Approach
- **Pros**: Integrates with existing effect system, GPU-accelerated, customizable
- **Cons**: Requires shader warmup to prevent first-shot lag
- **Source**: [Godot Documentation](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html)

#### 2. Sprite Animation Approach (KidsCanCode)
- Use animated sprite with 6 frames, 4 variations
- Play animation on shoot, scale from muzzle end
- Duration: 0.15 seconds
- **Source**: [KidsCanCode Tank Tutorial](https://kidscancode.org/blog/2018/05/godot3_tanks_part8/)

#### 3. Shader-Based Approach
- Additive blending shader with inverse fresnel
- Better for 3D, but can be adapted for 2D
- **Source**: [Godot Shaders - Muzzleflash Shader](https://godotshaders.com/shader/mech-gunfire-effect-muzzleflash-shader/)

#### 4. Combined Sprite + Light Approach (Recommended)
- Static/animated sprite for visual flash
- PointLight2D for wall illumination
- Light fades based on distance (energy attenuation)
- **Source**: Multiple tutorials recommend this for 2D shooters

### Dynamic Lighting in Godot 4

#### PointLight2D Properties
- `energy` - Light intensity (can be animated)
- `texture` - Light shape/falloff texture
- `color` - Light color (orange/yellow for muzzle flash)
- `range_z_min/max` - Z-index range for affecting sprites
- `shadow_enabled` - Enable shadows from LightOccluder2D

#### Wall Reflection Implementation
- Light intensity naturally falls off with distance
- Using `PointLight2D` with appropriate texture creates realistic falloff
- Can add `LightOccluder2D` to walls for shadow casting
- Light `energy` animation: start high, decay to 0 over ~0.05-0.1 seconds

### Best Practices

1. **Keep effect duration short** (0.05-0.15 seconds)
2. **Use one-shot mode** for particle effects
3. **Position at muzzle tip** not character center
4. **Scale with weapon caliber** if applicable
5. **Warmup shaders** to prevent first-shot lag (already implemented for other effects)
6. **Use additive blending** for light effects

## Proposed Solution

### Implementation Strategy

Create a `MuzzleFlashEffect` scene combining:
1. **GPUParticles2D** - Quick burst of orange/yellow particles (flame)
2. **PointLight2D** - Dynamic light that illuminates nearby walls

### Effect Parameters

**Particles:**
- Amount: 8-12 particles
- Lifetime: 0.08-0.1 seconds
- One-shot, high explosiveness (0.95)
- Emission shape: point
- Initial velocity: 100-200 px/s forward
- Scale: 0.3-0.8
- Color: Orange/Yellow gradient (fire colors)

**Light:**
- Color: Orange (1.0, 0.7, 0.3)
- Energy: Start at 2.0, animate to 0 over 0.1 seconds
- Texture: Radial gradient (soft falloff)
- Shadow enabled: true (if walls have occluders)

### Integration Points

1. **Player**: Call `spawn_muzzle_flash()` in `_shoot()` after bullet creation
2. **Enemy**: Call `spawn_muzzle_flash()` in all shooting methods

### Manager Extension

Extend `ImpactEffectsManager` with:
- `_muzzle_flash_scene: PackedScene`
- `spawn_muzzle_flash(position: Vector2, direction: Vector2, caliber_data: Resource = null)`

## File Changes Required

1. **New Files:**
   - `scenes/effects/MuzzleFlash.tscn` - The effect scene
   - `scripts/effects/muzzle_flash.gd` - Script for light animation

2. **Modified Files:**
   - `scripts/autoload/impact_effects_manager.gd` - Add muzzle flash spawning
   - `scripts/characters/player.gd` - Call muzzle flash on shoot
   - `scripts/objects/enemy.gd` - Call muzzle flash on shoot

## References

- [Godot GPUParticles2D Documentation](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html)
- [Godot 2D Particle Systems Tutorial](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html)
- [KidsCanCode - Muzzle Flash Animation](https://kidscancode.org/blog/2018/05/godot3_tanks_part8/)
- [Godot Shaders - Muzzleflash](https://godotshaders.com/shader/mech-gunfire-effect-muzzleflash-shader/)
- [Gravity Ace - Making Better Bullets](https://gravityace.com/devlog/making-better-bullets/)
