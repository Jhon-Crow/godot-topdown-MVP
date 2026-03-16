# Case Study: Issue #652 - Laser Glow Effects

## Issue Description
Add realistic glow effects to all laser sights in the game:
1. Lasers should glow subtly along the beam (like a small aura)
2. A small residual glow at the laser endpoint (like a flashlight tip, but smaller)
3. Effects must match the laser's color (red for M16, green for silenced pistol, blue for Power Fantasy mode)
4. Must work with all lasers: Power Fantasy mode, M16, silenced pistol

## Timeline

### Initial Implementation (v1)
- Created `LaserGlowEffect.cs` - reusable class for laser glow
- Used `Line2D` with additive blending for beam aura
- Used `PointLight2D` with `GradientTexture2D` for endpoint glow
- Integrated into all 6 weapon files

### Feedback from Owner
Two issues reported:
1. **Laser line glow was not visible** - the aura around the beam was too subtle
2. **Endpoint glow was square** - the `GradientTexture2D` radial fill produced visible square edges

Screenshot from owner showing the square artifact:
![Square glow artifact](https://github.com/user-attachments/assets/e42baf67-704e-4565-b180-04a8b6d27223)

### Root Cause Analysis

#### Problem 1: Invisible beam aura
- `GlowAlpha` was set to `0.15` (15% opacity) - too low to be visible on dark backgrounds
- Line width was `12px` (2px base * 6x multiplier) - narrow for a glow effect
- No width curve was applied, so the glow had a flat profile instead of a soft falloff

#### Problem 2: Square endpoint glow
- `GradientTexture2D` with `FillEnum.Radial` creates a radial gradient, but the **texture is still a square bitmap**
- The gradient maps from center to `FillTo` point (top edge center, distance = 0.5)
- Texture corners are at distance `sqrt(0.5^2 + 0.5^2) = ~0.707` from center
- While the gradient fades to zero at 55% radius (0.55), the mapping from normalized gradient position to actual pixel position means corner pixels at distance 0.707 can receive non-zero values due to how Godot interpolates the gradient across the square texture
- Result: visible square boundaries in the light

### Fix (v2)

#### Beam aura fix
- Increased `GlowAlpha` from `0.15` to `0.35` (more visible but still subtle)
- Changed to fixed `GlowLineWidth = 8.0f` (clearer naming)
- Added `WidthCurve` for soft falloff at beam endpoints (thin at start/end, full width in middle)

#### Endpoint glow fix
- Replaced `GradientTexture2D` with pixel-perfect circular texture via `Image`
- Each pixel's brightness is calculated using Euclidean distance from center
- Pixels beyond 55% radius are explicitly set to black (brightness = 0)
- This guarantees a perfectly circular glow with no square artifacts
- Texture size increased from 256x256 to 512x512 to match flashlight scatter light
- `TextureScale` reduced from 0.5 to 0.3 for a tighter, more laser-like dot

## Technical Details

### Approach: Pixel-Perfect Circular Texture
```csharp
// For each pixel, compute Euclidean distance from center
float dx = x - center;
float dy = y - center;
float distance = Mathf.Sqrt(dx * dx + dy * dy);
float normalizedDist = distance / maxRadius;

// Apply gradient based on true circular distance
// Beyond 55% radius -> brightness = 0 (guaranteed circle)
```

### Why GradientTexture2D produces squares
Godot's `GradientTexture2D` with radial fill creates a gradient that maps linearly from a center point to an edge point. The gradient is applied to a rectangular texture, and the mapping follows the direction vector from `FillFrom` to `FillTo`. Pixels at the corners of the texture, which are at a greater Euclidean distance from the center than edge-center pixels, may not map to the expected gradient position, resulting in visible square boundaries.

### Reference Implementation
The flashlight scatter light (`scripts/effects/flashlight_effect.gd`, Issue #644) uses a similar `GradientTexture2D` approach but at a larger scale (`texture_scale = 3.0`), which makes the square edges less noticeable. For the smaller laser endpoint glow (`texture_scale = 0.3`), the square edges were much more visible, necessitating the switch to a pixel-perfect Image-based texture.

## Files Modified
| File | Change |
|------|--------|
| `Scripts/Weapons/LaserGlowEffect.cs` | Fixed glow visibility and square artifact |

## Lessons Learned
1. `GradientTexture2D` with radial fill is not suitable for small-scale `PointLight2D` textures where circular precision matters
2. `Image.CreateEmpty()` + per-pixel distance calculation guarantees perfect circles
3. Line2D `WidthCurve` is useful for creating smooth glow falloff at beam endpoints
4. Additive blending (`CanvasItemMaterial.BlendModeEnum.Add`) requires higher alpha values than normal blending to be visible
