# Case Study: Issue #652 - Add Glow Effects to Lasers

## Problem Statement
Lasers in the game need visual glow effects:
1. A subtle aura/glow around the laser beam
2. A small residual glow at the laser endpoint (like a flashlight dot)
3. Effects must match the laser's color
4. Must work with all lasers: Power Fantasy mode (MakarovPM, SniperRifle, MiniUzi, Shotgun), AssaultRifle, SilencedPistol

## Technical Context

### Renderer Constraint
The project uses `gl_compatibility` renderer (project.godot line 141). This means:
- **WorldEnvironment glow is NOT supported** (requires Forward+ or Mobile renderer)
- No post-processing glow pass available
- Must use alternative approaches for glow effects

Reference: [Godot Issue #66455](https://github.com/godotengine/godot/issues/66455)

### Current Laser Implementation
All lasers are `Line2D` nodes created programmatically in C#:
- Width: 2.0 pixels
- Cap modes: Round
- Updated every frame via raycasting against obstacles (collision mask = 4)

### Weapons with Lasers
| Weapon | Laser Color | Activation |
|--------|------------|------------|
| AssaultRifle | Red `(1,0,0,0.5)` or Blue (Power Fantasy) | Always on |
| SilencedPistol | Green `(0,1,0,0.5)` | Always on |
| MakarovPM | Blue `(0,0.5,1,0.6)` | Power Fantasy only |
| SniperRifle | Blue `(0,0.5,1,0.6)` | Power Fantasy only |
| MiniUzi | Blue `(0,0.5,1,0.6)` | Power Fantasy only |
| Shotgun | Blue `(0,0.5,1,0.6)` | Power Fantasy only |

### Existing Light System
The project uses `PointLight2D` with `GradientTexture2D` (radial fill) for:
- Flashlight scatter light (energy: 0.4, small radius)
- Muzzle flash (energy: 4.5)
- Explosion flashes

## Solution: Dual Line2D + PointLight2D

### Approach
Since WorldEnvironment glow is unavailable in gl_compatibility:
1. **Glow aura**: A second, wider `Line2D` behind the main laser with additive blending (`CanvasItemMaterial.BlendMode = Add`) and low alpha
2. **Endpoint glow**: A `PointLight2D` with radial gradient texture at the laser's hit point

### Why This Approach
- Works in gl_compatibility renderer (no post-processing needed)
- Matches existing codebase patterns (PointLight2D with GradientTexture2D)
- Low performance cost (one extra Line2D + one PointLight2D per weapon)
- Color-matching is trivial (derives from weapon's laser color)
- Additive blending creates convincing soft glow without shaders

### Implementation
Created `LaserGlowEffect` helper class in `Scripts/Weapons/LaserGlowEffect.cs`:
- Manages glow Line2D and endpoint PointLight2D
- `Create(parentNode, laserColor)` - creates glow nodes
- `Update(startPoint, endPoint)` - syncs with main laser
- `SetVisible(visible)` - shows/hides glow
- `Cleanup()` - removes glow nodes

### Glow Parameters
- Glow line width: 6x main laser width (12px vs 2px)
- Glow line alpha: 0.15 (very subtle)
- Glow blend mode: Additive
- Endpoint light energy: 0.4
- Endpoint light texture scale: 0.5
- Endpoint light shadow: disabled

### Alternatives Considered
1. **Shader-based glow**: Requires .gdshader file, harder to tune, may conflict with RealisticVisibilityComponent
2. **Screen-space post-processing**: Requires HDR, affects all bright elements, expensive on low-end devices
3. **Multiple intermediate Line2D layers**: More nodes but potentially smoother falloff

## References
- [Godot PointLight2D docs](https://docs.godotengine.org/en/stable/classes/class_pointlight2d.html)
- [Godot CanvasItemMaterial docs](https://docs.godotengine.org/en/stable/classes/class_canvasitemmaterial.html)
- [Godot Issue #66455 - gl_compatibility glow limitation](https://github.com/godotengine/godot/issues/66455)
