# Gas Grenade Visual Effect Research - Issue #718

## Issue Summary
- **Issue**: Gas grenade visual effect is not visible
- **Expected**: Dark reddish smoke effect (similar to smoke grenade but dark reddish color)
- **Current State**: Effect exists but not visible enough

## Research Findings

### Game Design Best Practices

#### Color Design for Gas Grenades
Sources from game communities show that:
- Games like Insurgency and Arma 3 use configurable smoke grenade colors
- Rainbow Six Siege has gas grenade effects (Smoke character's remote gas grenade)
- Color coding helps players distinguish grenade types instantly

**Sources**:
- [Insurgency Smoke Grenade Color Discussion](https://steamcommunity.com/app/222880/discussions/0/612823460273535916/)
- [Arma 3 Colored Smoke Discussion](https://steamcommunity.com/app/107410/discussions/0/618458030662557412/)

### Godot Engine 2D Particle Systems

#### Official Documentation
Godot provides comprehensive particle system support:
- **GPUParticles2D**: High-performance particle system using GPU
- **CPUParticles2D**: CPU-based fallback for compatibility
- Key properties: gravity, scale curves, color ramps

**Key Techniques for Smoke**:
1. **Gravity**: Use negative values for rising smoke (e.g., (0, -50))
2. **Scale Curves**: Define size changes throughout particle lifetime
3. **Color Ramps**: Define color changes via gradients
4. **Lifetime**: Control how long particles persist

**Sources**:
- [Godot 2D Particle Systems (Latest)](https://docs.godotengine.org/en/latest/tutorials/2d/particle_systems_2d.html)
- [Godot 2D Particle Systems (Stable)](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html)
- [GPUParticles2D Effects Tutorial](https://uhiyama-lab.com/en/notes/godot/gpu-particles2d-effects/)
- [Godot Shaders - Smoke](https://godotshaders.com/shader-tag/smoke/)

### Sprite-Based Smoke Effects

#### Creating Smoke Sprites
Kenney's guide recommends:
1. Arrange dots in circular shape
2. Use varying opacity (80%, 60%, 40%, 20%)
3. Apply Gaussian blur until circles blend
4. Result: single cloud of smoke

**Color Adaptation**:
- Smoke sprites work for fog and smoke
- Can be colored red for blood effects
- Can be colored blue for water
- **Application**: Can be colored dark red for gas grenade

**Sources**:
- [Kenney - Drawing Particle Effect Sprites](https://kenney.nl/knowledge-base/learning/drawing-particle-effect-sprites)
- [OpenGameArt - Smoke Particle Assets](https://opengameart.org/content/smoke-particle-assets)
- [itch.io - Smoke Game Assets](https://itch.io/game-assets/tag-smoke)

### 2D Particle Technical Implementation

**Core Concepts**:
- Particles rendered as 2D quads (billboarding)
- Texture with transparent areas
- Large group of tiny sprites simulating organic effects

**Best Practices**:
- Use texture atlases for performance
- Alpha blending for transparency
- Layer multiple particle sprites for depth

**Sources**:
- [LearnOpenGL - 2D Game Particles](https://learnopengl.com/In-Practice/2D-Game/Particles)
- [Unity 2D Particle Effects](https://learn.unity.com/course/2D-adventure-robot-repair/unit/enhance-your-game/tutorial/create-2d-particle-effects?version=6.3)

## Current Implementation Analysis

### AggressionCloud (scripts/effects/aggression_cloud.gd)

**Visual Setup**:
```gdscript
func _setup_cloud_visual() -> void:
    _cloud_visual = Sprite2D.new()
    _cloud_visual.texture = _create_cloud_texture(int(cloud_radius))
    _cloud_visual.modulate = Color(0.9, 0.25, 0.2, 0.35)  # Reddish semi-transparent
    _cloud_visual.z_index = -1  # Draw below characters
    add_child(_cloud_visual)
```

**Texture Creation**:
```gdscript
func _create_cloud_texture(radius: int) -> ImageTexture:
    # Creates circular gradient with soft falloff
    # Color: (0.85, 0.2, 0.15, alpha) - reddish
    # Uses quadratic falloff for soft edges
```

**Fade Behavior**:
```gdscript
func _update_cloud_visual() -> void:
    # Fade out in last 5 seconds
    if _time_remaining < 5.0:
        var fade_ratio := _time_remaining / 5.0
        _cloud_visual.modulate.a = 0.35 * fade_ratio
```

### Potential Issues Identified

1. **Low Initial Alpha**: 0.35 alpha might be too transparent
2. **Static Texture**: Single static sprite, no animation/particles
3. **Z-Index**: Drawing below characters (-1) might be occluded
4. **No Particle Movement**: Lacks organic smoke movement
5. **Single Color**: No color variation within cloud
6. **No Billowing Effect**: Static circle vs. animated smoke

## Comparison with Flashbang Effect

Flashbang uses:
- **PointLight2D** with shadow_enabled
- Higher energy (8.0)
- Visible flash effect
- Wall occlusion awareness

Gas grenade could benefit from:
- Multiple layered sprites
- Particle system for movement
- Higher visibility/contrast
- Animation/rotation

## Proposed Solutions

### Option 1: GPUParticles2D System (Best Practice)
**Pros**:
- Organic smoke movement
- GPU-accelerated performance
- Built-in animation support
- Professional appearance

**Cons**:
- More complex implementation
- Requires particle texture assets
- Need to tune many parameters

**Implementation**:
- Use GPUParticles2D with smoke texture
- Configure for slow upward drift
- Dark red color ramp
- Emit particles continuously for 20s

### Option 2: Enhanced Sprite with Animation (Quick Fix)
**Pros**:
- Simple implementation
- Works with existing code
- Low performance impact

**Cons**:
- Less organic appearance
- Limited movement

**Implementation**:
- Increase alpha to 0.6-0.8
- Add rotation animation
- Layer multiple sprites with offsets
- Add pulsing/billowing effect

### Option 3: Hybrid Approach (Recommended)
**Pros**:
- Balance of quality and simplicity
- Good performance
- Professional look

**Cons**:
- Medium complexity

**Implementation**:
- Use 3-5 layered animated sprites
- Gentle rotation and scale variation
- Higher alpha values
- Add slight color variation
- Optional: Light particle overlay for depth

## Next Steps

1. ✅ Research completed
2. ⏳ Analyze why current effect is invisible
3. ⏳ Test current implementation visually
4. ⏳ Choose solution approach
5. ⏳ Implement improved visual effect
6. ⏳ Test and validate visibility
