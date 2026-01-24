# Case Study: Round 8 - Rectangular Blood Puddles Regression

## Timeline of Events

### Round 4 (commit 246a198)
**Configuration:**
- `fill_to = Vector2(1.0, 0.5)` - gradient extends to horizontal edge only
- Texture size: 32x32
- **Problem:** This creates rectangular artifacts because the gradient only reaches distance 0.5 from center (0.5, 0.5) to edge (1.0, 0.5), but corners are at distance ~0.707

### Round 5 (commit bc08bc1) - FIX APPLIED
**Configuration:**
- `fill_to = Vector2(1.0, 1.0)` - gradient extends to diagonal corner
- Texture size: 64x64
- Gradient offsets carefully placed to fade at 0.707 (inscribed circle edge)
- **Result:** TRUE CIRCULAR GRADIENT - corners are transparent, no rectangular artifacts
- **Comments in file:** Detailed explanation of the fix

### Round 7 (commit ecc2943) - REGRESSION INTRODUCED
**Configuration:**
- `fill_to = Vector2(1.0, 1.0)` - STILL CORRECT
- **BUT:** Gradient offsets were simplified from 9 stops to 5 stops
- **Changed:** `offsets = PackedFloat32Array(0, 0.5, 0.65, 0.707, 1.0)`
- **Problem:** The gradient color/alpha transition is now concentrated between 0.5-0.707, but the SHAPE is still correct

### Current State (HEAD: ecc2943)
**Same as Round 7 - fill_to is CORRECT, but gradient may need adjustment**

## Root Cause Analysis

### What Changed Between Round 5 and Round 7?

**Round 5 gradient (9 stops):**
```
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
  0.4, 0.03, 0.03, 1.0,     # 0.0: bright center, full opacity
  0.38, 0.025, 0.025, 1.0,  # 0.2: slightly darker
  0.36, 0.022, 0.022, 0.95, # 0.35
  0.33, 0.018, 0.018, 0.8,  # 0.45
  0.30, 0.014, 0.014, 0.5,  # 0.55: significant alpha drop
  0.28, 0.01, 0.01, 0.25,   # 0.62
  0.26, 0.008, 0.008, 0.08, # 0.68
  0.25, 0.005, 0.005, 0,    # 0.707: fully transparent at circle edge
  0.25, 0.005, 0.005, 0     # 1.0: corners also transparent
)
```

**Round 7 gradient (5 stops):**
```
offsets = PackedFloat32Array(0, 0.5, 0.65, 0.707, 1.0)
colors = PackedColorArray(
  0.25, 0.02, 0.02, 0.95,   # 0.0: uniform dark, high opacity
  0.25, 0.02, 0.02, 0.95,   # 0.5: SAME - uniform flat color
  0.25, 0.02, 0.02, 0.7,    # 0.65: start fading alpha
  0.25, 0.02, 0.02, 0,      # 0.707: fully transparent at circle edge
  0.25, 0.02, 0.02, 0       # 1.0: corners also transparent
)
```

### The Problem

The issue is NOT with `fill_to` (which is still correctly set to (1.0, 1.0)), but with how the gradient stops are distributed:

1. **Round 5 had gradual alpha transition** starting from offset 0.45 (alpha 0.8) down to 0.707 (alpha 0)
2. **Round 7 has abrupt alpha transition** - stays at 0.95 until offset 0.5, then drops sharply

This creates visible "steps" or edges in the gradient, which may appear rectangular when the transition is too abrupt.

### Why Does This Look Rectangular?

When a radial gradient has an abrupt alpha transition, the human eye perceives it as an edge. If this edge is:
- Too sharp (goes from 0.95 to 0.7 in just 0.15 offset units)
- Positioned at offset 0.5-0.65 (which is still quite far from the circle edge at 0.707)

The result is a visible ring or boundary that doesn't blend smoothly, creating a "hard edge" appearance.

### Additional Factor: Texture Sampling

At 64x64 resolution with a radial gradient:
- Each pixel represents ~1.56% of the radius
- The sharp transition from offset 0.5 to 0.65 (15% of radius) might only be ~10 pixels
- This creates visible banding or stepping

## Proposed Solutions

### Solution 1: Restore More Gradient Stops (Recommended)
Bring back intermediate gradient stops between 0.5 and 0.707 to create smoother alpha transition:

```
offsets = PackedFloat32Array(0, 0.5, 0.58, 0.65, 0.707, 1.0)
colors = PackedColorArray(
  0.25, 0.02, 0.02, 0.95,   # 0.0: uniform dark
  0.25, 0.02, 0.02, 0.95,   # 0.5: uniform dark
  0.25, 0.02, 0.02, 0.75,   # 0.58: gentler alpha drop
  0.25, 0.02, 0.02, 0.4,    # 0.65: continuing fade
  0.25, 0.02, 0.02, 0,      # 0.707: fully transparent
  0.25, 0.02, 0.02, 0       # 1.0: corners transparent
)
```

### Solution 2: Extend Flat Region, Sharper Edge Fade
Keep the flat matte appearance longer, but make the final fade very smooth:

```
offsets = PackedFloat32Array(0, 0.6, 0.67, 0.707, 1.0)
colors = PackedColorArray(
  0.25, 0.02, 0.02, 0.95,   # 0.0: uniform dark
  0.25, 0.02, 0.02, 0.95,   # 0.6: stay flat longer
  0.25, 0.02, 0.02, 0.4,    # 0.67: start fade closer to edge
  0.25, 0.02, 0.02, 0,      # 0.707: transparent at circle edge
  0.25, 0.02, 0.02, 0       # 1.0: corners transparent
)
```

### Solution 3: Higher Resolution Texture
Increase texture size to 128x128 to reduce banding artifacts (at cost of memory).

## Verification Steps

1. **Export the game** after applying the fix
2. **Shoot enemies** and observe blood puddles
3. **Look for:**
   - Are puddles circular or rectangular?
   - Is there a visible "ring" or hard edge?
   - Do overlapping puddles blend smoothly?

## Research Sources

Based on Godot GradientTexture2D documentation:
- [GradientTexture2D Documentation](https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html)
- For radial gradients, `fill_to` determines the radius of the gradient
- The gradient offsets (0.0 to 1.0) map to the distance from `fill_from` to `fill_to`
- At offset 0.707, we're at the edge of the inscribed circle (for a square texture)

## Recommended Fix

Use **Solution 1** with more gradient stops for smoother blending while maintaining the flat matte appearance requested in Round 7.

## Implementation (Round 8)

Applied the fix with the following gradient configuration:

```gdscript
offsets = PackedFloat32Array(0, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
  0.25, 0.02, 0.02, 0.95,  # 0.0: uniform dark, 95% opacity
  0.25, 0.02, 0.02, 0.85,  # 0.55: still quite opaque (85%)
  0.25, 0.02, 0.02, 0.5,   # 0.62: mid fade (50%)
  0.25, 0.02, 0.02, 0.15,  # 0.68: nearly transparent (15%)
  0.25, 0.02, 0.02, 0,     # 0.707: fully transparent at circle edge
  0.25, 0.02, 0.02, 0      # 1.0: corners also transparent
)
```

### Key Changes from Round 7

1. **Extended flat region**: Color stays at 95% opacity until offset 0.55 (was 0.5)
2. **Smoother fade**: Added 6 gradient stops (was 5) with gentler alpha transitions
3. **Gradual steps**: Alpha now drops 85% → 50% → 15% → 0% instead of abrupt 95% → 70% → 0%
4. **Maintained flat matte look**: Color remains uniform dark (0.25, 0.02, 0.02) throughout

This should eliminate the rectangular appearance while keeping the flat matte blood drops from Round 7.

## Testing Tools

Created a gradient visualizer for future debugging:
- `experiments/blood_gradient_visualizer.tscn` - Scene to visualize blood decals
- `experiments/blood_gradient_visualizer.gd` - Displays decals at multiple scales
- Run this scene to verify circular vs rectangular appearance before exporting
