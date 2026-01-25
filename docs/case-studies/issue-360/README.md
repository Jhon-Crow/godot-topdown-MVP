# Case Study: Issue #360 - Add Bloody Footprints

## Issue Summary

**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/360

**Problem Description (Russian):**
> если враг или игрок вступает в лужу крови за ними должны появляться кровавые следы ботинок, которые будут всё прозрачнее с каждым шагом, пока не исчезнут.
> они не должно исчезать со временим, их максимально количество не ограничено.

**English Translation:**
> If an enemy or player steps into a blood puddle, bloody boot footprints should appear behind them, which will become more transparent with each step until they disappear.
> They should NOT disappear over time, their maximum number is NOT limited.

## Requirements Analysis

### Core Requirements

1. **Blood Puddle Detection**: Detect when player or enemy steps into a blood puddle
2. **Footprint Spawning**: Spawn footprint decals behind the character while they have "bloody feet"
3. **Fading Transparency**: Each consecutive footprint should be more transparent than the previous
4. **Persistence**: Footprints do NOT fade over time - they persist indefinitely
5. **Unlimited Count**: No maximum limit on footprints (performance considerations still apply)
6. **Both Characters**: Feature applies to both player and enemies

### Key Behaviors

- Footprints appear **after** stepping into blood (tracking blood outward)
- Transparency decreases step-by-step (e.g., 100% → 80% → 60% → 40% → 20% → 0%)
- The number of "bloody steps" before footprints stop is configurable
- Footprints should rotate to match character's movement direction

## Technical Research

### Existing Codebase Analysis

#### Blood System Components

1. **BloodDecal.tscn** (`scenes/effects/BloodDecal.tscn`)
   - Sprite2D-based blood stain effect
   - Uses GradientTexture2D (32x32 radial gradient)
   - Has optional auto_fade functionality (disabled by default)
   - Script: `scripts/effects/blood_decal.gd`

2. **BloodEffect.tscn** (`scenes/effects/BloodEffect.tscn`)
   - GPUParticles2D blood spray effect
   - Spawns BloodDecal instances at particle landing positions
   - Uses `effect_cleanup.gd` script

3. **ImpactEffectsManager** (`scripts/autoload/impact_effects_manager.gd`)
   - Autoload singleton managing all impact effects
   - Spawns blood decals via `spawn_blood_effect()`
   - Has `MAX_BLOOD_DECALS: int = 100` limit (but footprints should be unlimited per requirements)
   - Already handles blood puddle spawning at hit locations

#### Character Movement Systems

1. **Player** (`scripts/characters/player.gd`)
   - CharacterBody2D-based movement
   - Uses `_physics_process()` for movement via `move_and_slide()`
   - Has velocity tracking for movement direction
   - Walking animation system exists (`_update_walk_animation()`)

2. **Enemy** (`scripts/objects/enemy.gd`)
   - CharacterBody2D-based movement with AI states
   - Uses NavigationAgent2D for pathfinding
   - Walking animation system exists

### External Research

#### Godot Implementation Approaches

1. **Trail Effect with Line2D** ([DEV Community](https://dev.to/gauravk_/how-to-create-trail-effect-in-godot-engine-49mo))
   - Uses Line2D node for drawing trails
   - Not ideal for discrete footprints

2. **Particle-based Trails** ([Godot Shaders](https://godotshaders.com/shader/particle-based-trail/))
   - GPU-efficient for continuous trails
   - Overkill for discrete footprint spawning

3. **Sprite2D with Tween Fading** ([Godot Forum](https://forum.godotengine.org/t/persistent-decals-2d/32011))
   - Most appropriate for this use case
   - Each footprint is a Sprite2D instance
   - Alpha value set at spawn time (no animation needed per requirements)

#### Game Development Best Practices

1. **Polygon Treehouse's Footprint System** ([Blog](https://www.polygon-treehouse.com/blog/2018/3/29/footprints-are-go))
   - Uses animation events to trigger footprints at foot landing
   - Fades footprints over time (we don't need this)
   - Limits footprint count for performance (we need unlimited)

2. **Blood Trail FX Asset** ([Realtime VFX Store](https://realtimevfxstore.com/products/blood-trail-fx))
   - Commercial asset with bloody footprints
   - Shows that footprints should be textured (boot shape)
   - Frequency of spawning is adjustable

### Available Libraries/Components

1. **DecalCo Plugin** ([GitHub](https://github.com/Master-J/DecalCo))
   - Shader-based decal solution for Godot 3.x
   - Not compatible with Godot 4.x directly

2. **GPUTrail Plugin** ([GitHub](https://github.com/celyk/GPUTrail))
   - GPU-based trail for Godot 4
   - Better for continuous trails, not discrete footprints

## Proposed Solutions

### Solution 1: Component-Based Footprint Manager (Recommended)

**Architecture:**
```
BloodyFeetComponent (Node)
├── Tracks "blood level" (decreases with each step)
├── Detects blood puddle entry via Area2D overlap
├── Spawns footprint decals at step intervals
└── Attached to Player and Enemy nodes

FootprintDecal (Sprite2D scene)
├── boot-shaped texture
├── z_index = -1 (below characters)
├── rotation matches movement direction
└── modulate.a set at spawn time (no fade animation)

BloodyFeetManager (Autoload)
├── Preloads footprint scene
├── Tracks all footprints (for scene cleanup)
└── Handles footprint spawning requests
```

**Pros:**
- Clean separation of concerns
- Reusable component for any character
- Integrates with existing ImpactEffectsManager pattern
- Easy to test

**Cons:**
- Requires new component class
- Needs to hook into character movement

### Solution 2: Extend Existing Blood Decal System

**Architecture:**
- Add Area2D to BloodDecal for collision detection
- Add `bloody_feet` tracking directly to Player/Enemy scripts
- Spawn footprints from character scripts

**Pros:**
- Uses existing infrastructure
- Minimal new code

**Cons:**
- Clutters character scripts
- Less reusable
- Harder to maintain

### Solution 3: Signal-Based Event System

**Architecture:**
- Blood puddles emit `entered` signal
- Characters subscribe and set internal state
- Characters emit `step_taken` signal with position/direction
- BloodyFeetManager listens and spawns footprints

**Pros:**
- Fully decoupled
- Very testable
- Event-driven

**Cons:**
- More complex signal wiring
- May have performance overhead from many signals

## Recommended Approach

**Solution 1 (Component-Based)** is recommended because:

1. Follows existing project patterns (components like HealthComponent, VisionComponent)
2. Easy to attach to both Player and Enemy
3. Self-contained logic
4. Can integrate with existing ImpactEffectsManager for decal management
5. Testable in isolation

## Implementation Plan

### Phase 1: Create Footprint Assets
1. Create `footprint.png` texture (boot-shaped, grayscale for tinting)
2. Create `BloodFootprint.tscn` scene (Sprite2D with script)

### Phase 2: Implement Core System
1. Create `BloodyFeetComponent` component
2. Implement blood puddle detection (Area2D overlap)
3. Implement step tracking (distance-based or animation-event)
4. Implement footprint spawning with decreasing alpha

### Phase 3: Integration
1. Add component to Player scene
2. Add component to Enemy scene
3. Make blood decals detectable as "puddles"

### Phase 4: Testing
1. Unit tests for BloodyFeetComponent
2. Integration tests for footprint spawning
3. Manual gameplay testing

## Technical Specifications

### BloodyFeetComponent Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `blood_steps_count` | int | 6 | Number of bloody footprints before clean |
| `step_distance` | float | 30.0 | Distance between footprint spawns (pixels) |
| `initial_alpha` | float | 0.8 | Alpha of first footprint |
| `alpha_decay_rate` | float | 0.15 | Alpha reduction per step |

### Footprint Decal Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `z_index` | int | -1 | Below characters |
| `modulate.a` | float | varies | Set at spawn time |
| `rotation` | float | varies | Matches movement direction |
| `scale` | Vector2 | (0.5, 0.5) | Size of footprint |

### Blood Detection

Blood puddles need Area2D collision to be detected. Options:
1. Add Area2D child to BloodDecal scene
2. Use collision layer/mask for "blood" (new layer 7?)
3. Group-based detection ("blood_puddle" group)

## Files to Create/Modify

### New Files
- `scenes/effects/BloodFootprint.tscn` - Footprint decal scene
- `scripts/effects/blood_footprint.gd` - Footprint script
- `scripts/components/bloody_feet_component.gd` - Main component
- `tests/unit/test_bloody_feet_component.gd` - Unit tests
- `assets/sprites/effects/footprint.png` - Boot texture (or generate procedurally)

### Modified Files
- `scenes/effects/BloodDecal.tscn` - Add Area2D for detection
- `scripts/effects/blood_decal.gd` - Add group membership
- `scenes/characters/Player.tscn` - Add BloodyFeetComponent
- `scenes/objects/Enemy.tscn` - Add BloodyFeetComponent

## Performance Considerations

1. **Unlimited footprints**: While requirements say unlimited, extremely high counts could impact performance
   - Consider optional soft limit (e.g., 1000) that removes oldest when exceeded
   - Or implement spatial culling for off-screen footprints

2. **Area2D overlap checks**: Use appropriate collision layers to minimize checks
   - Only characters should detect blood puddles
   - Blood puddles should only be detected by characters

3. **Texture memory**: Footprint texture should be small (16x32 or similar)
   - Consider using same gradient-based approach as BloodDecal

## References

### Internal Code References
- `scripts/effects/blood_decal.gd` - Existing blood stain implementation
- `scripts/autoload/impact_effects_manager.gd` - Effect spawning patterns
- `scripts/components/health_component.gd` - Component pattern example

### External References
- [How to create Trail Effect in Godot Engine](https://dev.to/gauravk_/how-to-create-trail-effect-in-godot-engine-49mo)
- [Using Area2D - Godot Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)
- [Footprints are GO! - Polygon Treehouse](https://www.polygon-treehouse.com/blog/2018/3/29/footprints-are-go)
- [Persistent decals 2D - Godot Forum](https://forum.godotengine.org/t/persistent-decals-2d/32011)
- [Blood Trail FX - Realtime VFX Store](https://realtimevfxstore.com/products/blood-trail-fx)
