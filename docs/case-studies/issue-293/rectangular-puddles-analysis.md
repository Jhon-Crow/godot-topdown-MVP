# Case Study: Rectangular Blood Puddles Regression (Issue #293)

## Executive Summary

**Issue**: Blood puddles reverted to rectangular appearance after Round 8 changes
**Root Cause**: Gradient simplification removed critical offset points, creating abrupt transitions
**Impact**: Visual quality degradation, user dissatisfaction with repeated regression
**Resolution**: Restore gradient offsets while maintaining flat matte appearance

---

## Timeline of Events

### Round 5 (Commit bc08bc1) - ✅ Working
**Date**: ~2026-01-24 (earlier)
**Change**: "Fix rectangular blood drops - proper circular gradient"
**Gradient Configuration**:
- 9 offsets: `0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0`
- Smooth color transitions from dark red (0.4) to darker (0.25)
- Alpha: 1.0 → 1.0 → 0.95 → 0.8 → 0.5 → 0.25 → 0.08 → 0 → 0
- Result: **Circular blood drops with smooth edges**

### Round 7 (Commit ecc2943) - Requirement Change
**Date**: ~2026-01-24
**User Feedback**: Blood should be flat matte, not 3D balls
**Analysis**: Bright center (0.4 red) created 3D sphere appearance
**Change**: Uniform dark color (0.25 red) throughout

### Round 8 (Commit 829a00f) - ❌ Regression Introduced
**Date**: ~2026-01-24
**Intent**: "Fix rectangular blood puddles with smoother gradient"
**Actual Change**: **Simplified gradient from 9 to 6 offsets**
**Gradient Configuration**:
- 6 offsets: `0, 0.55, 0.62, 0.68, 0.707, 1.0`
- Uniform color: 0.25 red throughout (correct for matte appearance)
- Alpha: 0.95 → 0.85 → 0.5 → 0.15 → 0 → 0
- **Problem**: Missing offsets 0.2, 0.35, 0.45 created large jump from 0 to 0.55
- Result: **Rectangular appearance returned**

### Round 9 (Current) - Fix Required
**Date**: 2026-01-24
**User Report**: "лужи опять стали прямоугольными" (puddles became rectangular again)
**Attached Evidence**: game_log_20260124_065031.txt showing blood effects spawning

---

## Root Cause Analysis

### Technical Investigation

#### Why Fewer Gradient Stops Cause Rectangular Appearance

1. **Radial Gradient Mechanics**
   - `fill_from = (0.5, 0.5)` - center point
   - `fill_to = (1.0, 1.0)` - diagonal corner
   - Distance from center to corner = sqrt(0.5² + 0.5²) = 0.707

2. **Offset Distribution Problem**

   **Round 5 (Working)**:
   ```
   Offset: 0    0.2   0.35  0.45  0.55  0.62  0.68  0.707  1.0
   Gap:      0.2   0.15  0.1   0.1   0.07  0.06  0.027  0.293
   ```
   - Maximum gap: 0.293 (beyond visible circle)
   - In visible range (0-0.707): max gap 0.2
   - Smooth transitions throughout

   **Round 8 (Broken)**:
   ```
   Offset: 0    0.55  0.62  0.68  0.707  1.0
   Gap:      0.55  0.07  0.06  0.027  0.293
   ```
   - **CRITICAL: 0.55 gap from center!**
   - This covers 77.8% of circle radius with no interpolation
   - Only 3 stops (0.62, 0.68, 0.707) for edge fade
   - Result: Hard edge at ~78% radius appears rectangular

3. **Visual Perception**
   - Human eye detects abrupt transitions as geometric shapes (squares)
   - Gradual transitions perceived as organic shapes (circles)
   - Large gap (0 to 0.55) creates visible "ring" that follows square texture boundaries

### Why This Wasn't Caught Earlier

1. **Focus on Color, Not Distribution**: Round 8 correctly changed color to uniform dark, but accidentally removed offset points
2. **Commit Message Misleading**: "smoother gradient" but actually made it less smooth
3. **No Visual Testing**: Changes made without re-exporting and testing in-game

---

## Research: Gradient Best Practices

### Godot GradientTexture2D Radial Fill

**Sources**:
- [GradientTexture2D — Godot Engine (stable) documentation](https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html)
- [Gradient — Godot Engine (stable) documentation](https://docs.godotengine.org/en/stable/classes/class_gradient.html)
- [GradientTexture2D: Support focal point · Issue #5413](https://github.com/godotengine/godot-proposals/issues/5413)

**Key Facts**:
- Radial fill interpolates from `fill_from` to `fill_to` offsets
- Recommended radial setup: `fill_from = Vector2(0.5, 0.5)` (center), `fill_to` calculates radius
- Offset represents normalized distance (0.0 = center, 1.0 = corner)
- For inscribed circle: visible edge at offset ≈ 0.707
- Gradient sampled individually per pixel
- Fewer offsets = larger interpolation steps = visible banding

### Gradient Banding Prevention Techniques

**Sources**:
- [How to fix color banding - Frost.kiwi](https://blog.frost.kiwi/GLSL-noise-and-radial-gradient/)
- [CSS Banding: What It Is, Why It Happens, and How to Fix It](https://piwebpress.com/css-banding/)
- [Grainy Gradients – Frontend Masters Blog](https://frontendmasters.com/blog/grainy-gradients/)
- [Color Banding in Gradient Animation: 10 Quick Fixes](https://www.svgator.com/blog/color-banding-gradient-animation/)

**Best Practices for Smooth Gradients**:
1. **Sufficient Color Stops**: More stops = smoother transitions
2. **Dithering**: Adding noise breaks up quantized steps (not used here due to Godot limitations)
3. **Bit Depth**: Higher precision prevents banding (64x64 texture provides adequate resolution)
4. **Avoid Large Gaps**: Maximum gap between offsets should be < 0.25 for smooth appearance
5. **Layering**: Multiple overlapping gradients can hide banding (used in our merged puddles)

### Blood Splatter Reference Images

Source: [Shutterstock blood-splatter search](https://www.shutterstock.com/ru/search/blood-splatter) (as requested in issue #293)

**Observed Characteristics**:
- Circular to organic blob shapes
- Soft edges with gradual alpha fade
- No hard geometric boundaries
- Darker color in center, slightly lighter at edges (or uniform)
- NO rectangular shapes unless constrained by walls

---

## Proposed Solution

### Fix Strategy

**Restore gradient offset distribution from Round 5, keep uniform color from Round 7**

```gdscript
# Combine best of both:
# - Round 5: Smooth offset distribution (9 stops)
# - Round 7: Uniform dark color (0.25 red)

offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
    0.25, 0.02, 0.02, 1.0,    # center: dark, opaque
    0.25, 0.02, 0.02, 0.98,   # 0.2: dark, nearly opaque
    0.25, 0.02, 0.02, 0.92,   # 0.35: dark, mostly opaque
    0.25, 0.02, 0.02, 0.75,   # 0.45: dark, 75% alpha
    0.25, 0.02, 0.02, 0.5,    # 0.55: dark, 50% alpha
    0.25, 0.02, 0.02, 0.25,   # 0.62: dark, 25% alpha
    0.25, 0.02, 0.02, 0.08,   # 0.68: dark, near transparent
    0.25, 0.02, 0.02, 0,      # 0.707: dark, transparent (circle edge)
    0.25, 0.02, 0.02, 0       # 1.0: dark, transparent (corners)
)
```

### Why This Works

1. ✅ **Smooth Distribution**: 9 offsets with max gap of 0.2 in visible range
2. ✅ **Flat Matte Appearance**: Uniform 0.25 red color (no bright center)
3. ✅ **Circular Shape**: Gradual alpha fade creates soft organic edge
4. ✅ **No Rectangular Artifacts**: Enough interpolation points to smooth texture boundaries

---

## Prevention Measures

### For Future Changes

1. **Always compare with working version** when fixing regressions
2. **Understand what makes it work** before simplifying code
3. **Visual testing required** for any gradient changes
4. **Document the "why"** not just the "what" in comments
5. **Version comparison** before commit:
   ```bash
   git diff <working-commit> HEAD -- scenes/effects/BloodDecal.tscn
   ```

### Testing Checklist

- [ ] Export game build
- [ ] Test blood effects visually
- [ ] Compare with reference images
- [ ] Check at different scales
- [ ] Verify no rectangular appearance
- [ ] Test with multiple overlapping decals

---

## Lessons Learned

1. **Regression Prevention**: When fixing an issue that was previously fixed, ALWAYS check the previous fix first
2. **Simplification Risk**: Removing code/data points can break subtle visual effects
3. **Visual Effects Need Visual Testing**: Can't rely on code review alone
4. **Comments Should Explain Constraints**: Document why each offset exists, not just what it does

---

## References

- Issue #293: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/293
- PR #294: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/294
- Shutterstock blood-splatter: https://www.shutterstock.com/ru/search/blood-splatter
- Godot GradientTexture2D: https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html
- Round 5 commit (working): bc08bc1
- Round 8 commit (broken): 829a00f

---

## Conclusion

The rectangular puddle regression was caused by **over-simplification** of the gradient offset array. While attempting to create a "smoother gradient," the Round 8 changes removed critical interpolation points, creating the exact problem it claimed to fix.

The solution is to restore the offset distribution from Round 5 (which worked) while keeping the uniform dark color from Round 7 (user requirement).

**Key Insight**: More gradient stops ≠ worse performance. In visual effects, sufficient interpolation points are essential for smooth organic shapes.
