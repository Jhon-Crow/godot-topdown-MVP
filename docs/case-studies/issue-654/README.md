# Case Study: Issue #654 - Enhanced Laser Glow and Dust Particle Animation

## Issue Description
Enhance the laser sight effects with:
1. **Realistic volumetric glow** around the full length of the laser beam (not just the endpoint)
2. **Dust particle animation** along the laser beam (as if the laser is visible through atmospheric dust)

This builds on PR #653 which added the initial laser glow (aura Line2D + endpoint PointLight2D).

## Reference Images Analysis

### Reference 1: Glow Along Beam (ref_glow.png)
- Shows a wide, bright red laser beam with a very prominent glow aura
- The glow extends significantly beyond the core beam (estimated 20-40px total width)
- The glow has a smooth gradient falloff from bright center to transparent edges
- Color is bright red with high energy appearance

### Reference 2-3: Dust Particles (ref_dust1.png, ref_dust2.png)
- Shows laser beams visible through atmospheric dust/smoke
- Small bright motes/specks scattered along the beam path
- Particles appear to shimmer and float near the beam
- Bright spots where dust catches the laser light
- Creates a "visible in dusty air" effect

## Technical Context

### Renderer Constraint
The project uses `gl_compatibility` renderer (no WorldEnvironment glow available).

### Existing Implementation (PR #653)
- `LaserGlowEffect.cs` creates:
  - 1x glow Line2D (8px wide, 35% alpha, additive blending)
  - 1x endpoint PointLight2D (pixel-perfect circular texture)
- Integrated into 6 weapon files

## Solution Approach

### Part 1: Enhanced Volumetric Glow (Multi-Layered Line2D)

Replace the single glow Line2D with **multiple layered Line2D nodes**:
- Each layer uses additive blending (`CanvasItemMaterial.BlendModeEnum.Add`)
- Progressively wider widths and lower alpha values
- Layers stack to create a smooth volumetric falloff effect

**Glow layers (4 total):**
| Layer | Width | Alpha | Purpose |
|-------|-------|-------|---------|
| Core boost | 4px | 0.6 | Brighten the beam core |
| Inner glow | 12px | 0.25 | Close glow around beam |
| Mid glow | 24px | 0.12 | Extended glow |
| Outer glow | 40px | 0.05 | Subtle wide atmospheric glow |

All layers have:
- Additive blending material
- Round cap modes
- WidthCurve for soft endpoint falloff
- ZIndex behind the main laser

### Part 2: Dust Particle Animation (GPUParticles2D)

Add a `GpuParticles2D` node with box emission shape stretched along the laser beam:

**Approach:**
1. Position GPUParticles2D at beam midpoint
2. Rotate to match beam angle
3. Stretch EmissionBoxExtents.x to half beam length
4. Update position/rotation/extents every frame as beam moves

**Particle settings:**
- Amount: 20-30 particles
- Lifetime: 0.8-1.2 seconds
- Slow velocity (5-15 px/s) for floating dust feel
- No gravity (particles float freely)
- Small scale (1-3 pixels)
- Color ramp with fade-in and fade-out
- Additive blending for glow feel
- Small random spread from beam center

### Alternatives Considered

1. **Shader-based glow** (Laser Blaster Glow shader) — More complex, harder to tune
2. **CPUParticles2D** — Fully compatible but requires manual emission_points update
3. **Multiple intermediate Line2D layers** — What we chose (simplest, fits existing architecture)
4. **Screen-space post-processing** — Not available in gl_compatibility

### Why This Approach

- Multi-layered Line2D is the simplest extension of the existing code
- GPUParticles2D with box emission is used elsewhere in the codebase (MuzzleFlash, ExplosionFlash)
- Both techniques are compatible with gl_compatibility renderer
- Low performance overhead (a few extra Line2D + one GPUParticles2D per weapon)
- Fits the existing `LaserGlowEffect.cs` architecture perfectly

## Files Modified
| File | Change |
|------|--------|
| `Scripts/Weapons/LaserGlowEffect.cs` | Multi-layered glow + dust particles |

No changes needed to weapon files — the existing `Create()`, `Update()`, `SetVisible()`, `Cleanup()` API is preserved.

## References
- [GDQuest - 2D Laser in Godot 4](https://www.gdquest.com/library/laser_2d/)
- [Laser Blaster Glow Shader](https://godotshaders.com/shader/laser-blaster-glow/)
- [GPUParticles2D Documentation](https://docs.godotengine.org/en/stable/classes/class_gpuparticles2d.html)
- [ParticleProcessMaterial Documentation](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html)
- [CanvasItemMaterial Documentation](https://docs.godotengine.org/en/stable/classes/class_canvasitemmaterial.html)
