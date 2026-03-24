# Case Study: Top-Down Rain Precipitation Effect (Issue #1394)

## Problem Statement

The Docks level needed a weather precipitation system that:
1. Adds atmospheric top-down rain visual effect
2. Supports "rare rain" — intermittent episodes rather than constant rain
3. Excludes rain from indoor areas (WarehouseA, WarehouseB)
4. Is reusable for other maps and future precipitation types

## Root Cause Analysis

The project had no weather/precipitation system at all. The existing particle effects (`DustEffect`, `SparksEffect`, `BloodEffect`, etc.) were all one-shot effects triggered by gameplay events, not continuous environmental effects.

### Key Technical Challenges

1. **Large map coverage**: The Docks map is ~5000x4000 pixels, much larger than the viewport (1280x720). Rain must follow the camera.
2. **Building detection**: WarehouseA (500x600px at position 400,1800) and WarehouseB (700x840px at position 4400,2800) have roofs — rain should not appear when the camera is inside.
3. **Performance**: Continuous particle effects must be lightweight. GPUParticles2D processes particles on the GPU, so even 120 particles have minimal CPU impact.
4. **Intermittent rain**: "Rare rain" means rain episodes occur randomly, not constantly.

## Solution

### Architecture

The solution consists of three parts:

1. **`scripts/effects/rain_effect.gd`** — Reusable rain controller script (extends GPUParticles2D)
   - Manages rain episodes with configurable timing (interval between episodes, duration)
   - Follows the active camera automatically
   - Supports rectangular exclusion zones for indoor areas
   - Toggles particle emission based on camera position relative to exclusion zones

2. **`scenes/effects/RainEffect.tscn`** — Reusable rain particle scene
   - GPUParticles2D with ParticleProcessMaterial configured for top-down rain appearance
   - Box emission shape (700px wide) for even rain distribution across viewport
   - Downward + slight diagonal direction for natural rain appearance
   - Semi-transparent blue-gray raindrop texture (2x12px gradient)
   - 120 particles with 1.2s lifetime, gravity 800 on Y-axis

3. **Level integration** — DocksLevel.tscn includes the RainEffect scene, and docks_level.gd configures exclusion zones

### Exclusion Zone Approach

Rather than using collision-based detection (which would require physics setup), the solution uses simple Rect2 bounds checking. This is:
- **Fast**: A single `Rect2.has_point()` check per zone per frame
- **Simple**: No physics layers or collision shapes needed
- **Configurable**: Each level defines its own zones in its setup script

### Rain Episode Timing

For "rare rain" on the Docks:
- **Interval between episodes**: 30-90 seconds (randomized)
- **Episode duration**: 10-30 seconds (randomized)
- All timing is configurable via exported properties

## Existing Solutions Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| GPUParticles2D (chosen) | GPU-accelerated, follows existing effect patterns, simple | Limited collision options | **Selected** — best fit for project patterns |
| CPUParticles2D | Can collide with physics bodies | CPU-bound, doesn't match existing codebase | Rejected |
| Shader-based rain | Pixel-perfect coverage, zero overdraw | Complex implementation, hard to configure per-zone | Rejected |
| Tilemap-based animation | Integrates with tile system | Project doesn't use tilemaps for weather | Rejected |

## File Changes

| File | Change Type | Description |
|------|------------|-------------|
| `scripts/effects/rain_effect.gd` | New | Rain controller with episodes and exclusion zones |
| `scenes/effects/RainEffect.tscn` | New | Rain GPUParticles2D scene |
| `scenes/levels/DocksLevel.tscn` | Modified | Added RainEffect instance to level |
| `scripts/levels/docks_level.gd` | Modified | Added `_setup_rain()` with WarehouseA/B exclusion zones |
| `tests/unit/test_rain_effect.gd` | New | 24 unit tests for rain logic |

## Testing

Unit tests cover:
- Initial state (not emitting, no active episode)
- Episode lifecycle (start, stop, scheduling)
- Timing ranges (interval and duration within configured bounds)
- Exclusion zone detection (add, clear, point-in-zone checks)
- Building enter/exit behavior (rain stops/resumes)
- Warehouse-specific zone coordinates
- Edge cases (starting inside building, boundary points)

## References

- [Godot GPUParticles2D documentation](https://docs.godotengine.org/en/4.3/classes/class_gpuparticles2d.html)
- [Dynamic Weather Systems in Godot (Wayline)](https://www.wayline.io/blog/dynamic-weather-systems-godot)
- [Particle Systems in Godot - Rain (Dante's Lab)](https://www.dlab.ninja/2024/12/particle-systems-in-godot-introduction.html)
- [2D Particle Systems tutorial (Godot docs)](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html)

## Future Extensibility

The `RainEffect` scene and script are designed to be reusable:
- Any level can instance `RainEffect.tscn` and configure exclusion zones
- Different precipitation types (snow, hail) can be created by duplicating the scene with different particle materials
- The timing properties are all exported, so each level can have different weather patterns
- The `start_raining` flag allows levels to begin with rain already active
