# Case Study: Issue #154 - Blood Effects Enhancement

## Issue Summary
Update blood effects to match the style of "First Cut: Samurai Duel" game, including:
- Blood should not fly through walls
- Blood should fly in bullet direction (realistically)
- More blood particles with higher volume/pressure
- Effect variability
- Puddles/drops at particle landing points

## Problem Analysis

### Symptoms Reported
1. Particles spread too much from impact point
2. Blood passes through obstacles/walls
3. Effects follow the same pattern (lack of variability)
4. Game crashes during gameplay

### Root Cause Analysis

#### 1. Wall Collision Issues
The current implementation uses `PhysicsRayQueryParameters2D` for collision detection, checking only the next frame's movement distance. This approach has limitations:
- Very fast particles may pass through thin walls between frames
- The raycast only checks from current position to the next movement position
- If particles spawn close to or inside walls, collision detection may fail

#### 2. Excessive Particle Count
The system spawns both:
- GPU particles (80 particles via BloodEffect.tscn)
- Physics-based particles (up to 25 per hit via blood_particle.gd)

With multiple enemies being hit, this creates potentially hundreds of particles, which could cause:
- Performance degradation
- Memory pressure
- Potential crashes on lower-end systems

#### 3. Hybrid System Complexity
The current approach uses a hybrid system:
- `GPUParticles2D` for immediate visual spray (doesn't respect physics)
- Custom `blood_particle.gd` nodes for physics-based collision

The GPU particles cannot collide with walls by design, so any visible "passing through walls" is from these non-physics particles.

### Evidence from Logs

The game logs (`game_log_20260121_042421.txt` and `game_log_20260121_042447.txt`) show:
- Normal gameplay flow with enemy spawning and combat
- No explicit error messages or crash traces
- The logs end abruptly during combat, suggesting the crash occurred but wasn't logged

The logs are gameplay logs, not crash dumps, so the specific crash cause isn't visible.

## Timeline of Events

1. **Initial Request**: User requests blood effects like "First Cut: Samurai Duel"
2. **First Implementation**: Hybrid GPU + physics particles system implemented
3. **Feedback 1**: Particles spread too much, pass through walls, lack variability
4. **Iteration 2**: Reduced spread, adjusted physics, added contextual patterns
5. **Feedback 2**: Game crashes, blood still passes through walls

## Proposed Solution

### Replace Hybrid System with Fully Procedural Approach

Instead of relying on GPU particles for visuals, implement a pure procedural blood system:

1. **CPU-based Particles Only**
   - Use pure Node2D-based particles with manual physics
   - Every particle has wall collision checking
   - No GPU particles that ignore physics

2. **Improved Wall Collision**
   - Check collision before spawning (don't spawn particles inside walls)
   - Use continuous collision detection with smaller step sizes
   - Implement "safe spawn" offset from impact point

3. **Optimized Particle Count**
   - Reduce total particle count
   - Use pooling to avoid garbage collection pressure
   - Implement distance-based LOD (fewer particles when far from camera)

4. **Procedural Variety**
   - Randomize particle sizes, velocities, and colors
   - Base patterns on hit context (angle, distance, target velocity)
   - Create organic-looking splatter patterns

## References

- [Godot Forum: Persistent Blood Splatter](https://forum.godotengine.org/t/how-to-implement-persistent-blood-splatter/121948)
- [GitHub: Directional Blood Splatter Component](https://github.com/kubsterman/directional-blood-splatter)
- [Reddit: Dynamic Blood Splatter Effects](https://www.reddit.com/r/gamedev/comments/15ev1k/how_to_pull_off_dynamic_bloodsplatter_effect/)

## Files Affected

- `scripts/effects/blood_particle.gd` - Main procedural blood particle logic
- `scripts/effects/blood_decal.gd` - Blood stain/puddle system
- `scripts/autoload/impact_effects_manager.gd` - Effect spawning manager
- `scenes/effects/BloodEffect.tscn` - GPU particle scene (to be replaced)
- `scenes/effects/BloodParticle.tscn` - Physics particle scene
- `scenes/effects/BloodDecal.tscn` - Blood decal scene
