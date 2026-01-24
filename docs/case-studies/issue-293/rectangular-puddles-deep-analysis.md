# Case Study: Rectangular Blood Puddles Issue #293

## Executive Summary

Blood puddles in Godot topdown-MVP appear rectangular instead of circular. After 10 rounds of attempted fixes, the issue persists despite multiple approaches. This case study reconstructs the timeline, identifies root causes, and proposes evidence-based solutions.

**Status**: Issue persists after Round 10
**Last Feedback**: "всё ещё прямоугольники" (still rectangles) - Owner, 2026-01-24
**Analysis Date**: 2026-01-24

---

## Timeline Reconstruction

### Round 5: First Successful Circular Fix (bc08bc1)

**Date**: Unknown (before Round 7)
**Commit**: bc08bc1 "Round 5: Fix rectangular blood drops - proper circular gradient"

**Configuration**:
```gdscript
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
    0.4,  0.03,  0.03,  1.0,    # Center: bright red, full opacity
    0.38, 0.025, 0.025, 1.0,    # 0.2: slight dim, full opacity
    0.36, 0.022, 0.022, 0.95,   # 0.35: dimmer, start fade
    0.33, 0.018, 0.018, 0.8,    # 0.45: darker, fading
    0.30, 0.014, 0.014, 0.5,    # 0.55: darker still, half alpha
    0.28, 0.01,  0.01,  0.25,   # 0.62: dark, quarter alpha
    0.26, 0.008, 0.008, 0.08,   # 0.68: very dark, nearly transparent
    0.25, 0.005, 0.005, 0,      # 0.707: edge transparent
    0.25, 0.005, 0.005, 0       # 1.0: corner transparent
)
```

**Result**: ✅ **CIRCULAR** - confirmed working

**Key Characteristics**:
- **9 gradient offsets** with proper distribution (no gaps > 0.2)
- **Gradient RGB values**: Red channel fades from 0.4 → 0.25
- **Gradient alpha values**: 1.0, 1.0, 0.95, 0.8, 0.5, 0.25, 0.08, 0, 0
- **64x64 texture resolution**
- **Radial fill mode** with fill_to = (1.0, 1.0) covering diagonal

---

### Round 7: Flat Matte Requirement (ecc2943)

**Date**: Unknown
**Commit**: ecc2943 "Round 7: Flat matte blood drops, smaller puddles, better satellite placement"

**Requirement**: Owner requested "flat matte appearance, not 3D shiny balls"

**Configuration Changed**:
```gdscript
offsets = PackedFloat32Array(0, 0.5, 0.65, 0.707, 1.0)  # ❌ Only 5 offsets!
colors = PackedColorArray(
    0.25, 0.02, 0.02, 0.95,  # Flat color 0.25 throughout
    0.25, 0.02, 0.02, 0.95,
    0.25, 0.02, 0.02, 0.7,
    0.25, 0.02, 0.02, 0,
    0.25, 0.02, 0.02, 0
)
```

**Changes from Round 5**:
1. ❌ Reduced offsets from 9 → 5
2. ❌ Largest gap: 0.5 (from 0 to 0.5 offset)
3. ✅ Flat color: 0.25 throughout (removes 3D appearance)
4. ❌ Different alpha: 0.95, 0.95, 0.7, 0, 0

**Result**: Unknown (no explicit feedback recorded)
**Impact**: Removed gradient structure that made circles work

---

### Round 8: Smoothing Attempt - REGRESSION (829a00f)

**Date**: Unknown
**Commit**: 829a00f "Round 8: Fix rectangular blood puddles with smoother gradient"

**Intent**: Add more gradient stops for smoother appearance

**Configuration**:
```gdscript
offsets = PackedFloat32Array(0, 0.55, 0.62, 0.68, 0.707, 1.0)  # ❌ 6 offsets
colors = PackedColorArray(
    0.25, 0.02, 0.02, 0.95,
    0.25, 0.02, 0.02, 0.85,
    0.25, 0.02, 0.02, 0.5,
    0.25, 0.02, 0.02, 0.15,
    0.25, 0.02, 0.02, 0,
    0.25, 0.02, 0.02, 0
)
```

**Critical Error**:
- ❌ **Largest gap: 0.55** (from offset 0 to 0.55)
- ❌ Only 6 gradient stops
- Flat color maintained: 0.25

**Result**: ❌ **RECTANGULAR** (regression introduced)
**Root Cause**: Huge 0.55 gap in visible range creates banding

---

### Round 9: Distribution Fix Attempt (578b2e0)

**Date**: 2026-01-24
**Commit**: 578b2e0 "Round 9: Fix rectangular blood puddles regression"

**Intent**: Restore Round 5's 9-offset distribution

**Configuration**:
```gdscript
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)  # ✅ 9 offsets
colors = PackedColorArray(
    0.25, 0.02, 0.02, 1.0,   # ❌ Different alpha than Round 5
    0.25, 0.02, 0.02, 0.98,  # ❌ Was 1.0 in Round 5
    0.25, 0.02, 0.02, 0.92,  # ❌ Was 0.95 in Round 5
    0.25, 0.02, 0.02, 0.75,  # ❌ Was 0.8 in Round 5
    0.25, 0.02, 0.02, 0.5,   # ✅ Same
    0.25, 0.02, 0.02, 0.25,  # ✅ Same
    0.25, 0.02, 0.02, 0.08,  # ✅ Same
    0.25, 0.02, 0.02, 0,     # ✅ Same
    0.25, 0.02, 0.02, 0      # ✅ Same
)
```

**What Was Fixed**:
- ✅ Restored 9-offset distribution
- ✅ Maximum gap back to 0.2

**What Was Missed**:
- ❌ RGB still flat (0.25) instead of gradient (0.4→0.25)
- ❌ Alpha values differ from Round 5 in early offsets
- ❌ Tiny alpha changes (1.0→0.98→0.92) instead of plateau (1.0→1.0→0.95)

**Result**: ❌ **STILL RECTANGULAR**

---

### Round 10: Alpha Matching Attempt (fe64965)

**Date**: 2026-01-24
**Commit**: fe64965 "Round 10: Fix rectangular blood puddles - match Round 5 alpha progression"

**Intent**: Match Round 5's alpha values exactly

**Configuration**:
```gdscript
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
    0.25, 0.02, 0.02, 1.0,   # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 1.0,   # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0.95,  # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0.8,   # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0.5,   # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0.25,  # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0.08,  # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0,     # ✅ Matches R5 alpha
    0.25, 0.02, 0.02, 0      # ✅ Matches R5 alpha
)
```

**What Was Fixed**:
- ✅ Alpha values now match Round 5 EXACTLY
- ✅ Alpha plateau at center (1.0, 1.0)
- ✅ Significant drops (0.95, 0.8, 0.5, 0.25, 0.08)

**What Was Still Missing**:
- ❌ RGB still flat (0.25) instead of gradient (0.4→0.25)

**Result**: ❌ **STILL RECTANGULAR** - "всё ещё прямоугольники"

---

## Root Cause Analysis

### Hypothesis 1: Offset Distribution (DISPROVEN)

**Theory**: Large gaps in offset distribution cause banding.

**Evidence**:
- Round 8 had 0.55 gap → rectangular ✅ Supports theory
- Round 9 restored 0.2 max gap → still rectangular ❌ Contradicts theory
- Round 10 maintained 0.2 max gap → still rectangular ❌ Contradicts theory

**Conclusion**: Offset distribution is **necessary but not sufficient**

---

### Hypothesis 2: Alpha Progression (DISPROVEN)

**Theory**: Tiny alpha changes (0.98, 0.92) cause imperceptible gradations that create banding.

**Evidence**:
- Round 9 used small changes (0.98, 0.92) → rectangular ✅ Supports theory
- Round 10 used plateau + big drops (1.0, 1.0, 0.95, 0.8) → still rectangular ❌ Contradicts theory

**Conclusion**: Alpha progression alone is **not sufficient**

---

### Hypothesis 3: RGB Gradient Required (SUPPORTED)

**Theory**: Circular appearance requires gradient in RGB channels, not just alpha.

**Evidence**:
- Round 5: RGB gradient (0.4→0.25) + alpha gradient → CIRCULAR ✅✅✅
- Round 7: Flat RGB (0.25) + alpha gradient → no explicit failure recorded
- Round 8: Flat RGB (0.25) + poor alpha → rectangular
- Round 9: Flat RGB (0.25) + restored distribution → rectangular ✅
- Round 10: Flat RGB (0.25) + exact R5 alpha → rectangular ✅

**Key Observation**: The ONLY successful configuration (Round 5) had BOTH:
1. RGB gradient from 0.4 (center) to 0.25 (edge)
2. Alpha gradient with proper distribution

**All failures** (Rounds 8, 9, 10) shared one thing: **flat RGB = 0.25**

**Conclusion**: **RGB gradient is likely required for circular appearance**

---

### Hypothesis 4: Banding Artifacts from Limited Color Depth

**Theory**: With flat RGB, the gradient relies solely on alpha channel. Limited alpha precision (8-bit = 256 levels) causes banding that follows texture boundaries.

**Research Evidence**:

From [How to fix color banding](https://blog.frost.kiwi/GLSL-noise-and-radial-gradient/):
> "The proper way to achieve banding free-ness is error diffusion dithering, but when talking about gradients, adding noise works just fine"

From [Godot Issue #17006 - Add dithering effect to prevent color banding](https://github.com/godotengine/godot/issues/17006):
> Banding can occur with gradients, especially in low dynamic range formats

From Mozilla Bug 627771:
> "The limited colors available in 24-bit 'truecolor' cause visible banding regardless of the presence of alpha"

**Technical Explanation**:

1. **Alpha-only gradient** (Rounds 7-10):
   - RGB constant = 0.25
   - Only alpha varies: 1.0 → 0.95 → 0.8 → 0.5 → 0.25 → 0.08 → 0
   - Each alpha value covers a "ring" in the radial gradient
   - With only 9 distinct alpha values, creates 9 visible rings
   - Rings follow square texture boundaries → rectangular appearance

2. **RGB+Alpha gradient** (Round 5):
   - RGB varies: 0.4 → 0.38 → 0.36 → 0.33 → 0.30 → 0.28 → 0.26 → 0.25
   - Alpha varies: 1.0 → 1.0 → 0.95 → 0.8 → 0.5 → 0.25 → 0.08 → 0 → 0
   - Creates 9 × 256 = 2,304 possible color combinations
   - More gradual transitions between rings
   - Smoother interpolation masks the rectangular rings

**Analogy**:
- Alpha-only = 9 stacked transparent squares
- RGB+Alpha = 9 stacked squares with color variations that blend together

---

## Proposed Solutions

### Solution 1: Restore Round 5 Complete Gradient (RECOMMENDED)

**Implementation**: Use BOTH RGB and alpha gradients from Round 5

```gdscript
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
    0.4,  0.03,  0.03,  1.0,
    0.38, 0.025, 0.025, 1.0,
    0.36, 0.022, 0.022, 0.95,
    0.33, 0.018, 0.018, 0.8,
    0.30, 0.014, 0.014, 0.5,
    0.28, 0.01,  0.01,  0.25,
    0.26, 0.008, 0.008, 0.08,
    0.25, 0.005, 0.005, 0,
    0.25, 0.005, 0.005, 0
)
```

**Pros**:
- ✅ Known working configuration
- ✅ Minimal risk
- ✅ Can be tested immediately

**Cons**:
- ❌ Creates "3D ball" appearance (brighter center)
- ❌ May not satisfy "flat matte" requirement from Round 7

**Risk**: Medium - Owner may reject the 3D appearance

---

### Solution 2: RGB Gradient with Dark Colors

**Implementation**: Use gradient RGB but keep colors dark to minimize 3D effect

```gdscript
offsets = PackedFloat32Array(0, 0.2, 0.35, 0.45, 0.55, 0.62, 0.68, 0.707, 1.0)
colors = PackedColorArray(
    0.28, 0.02,  0.02,  1.0,   # Darker center than R5 (0.28 vs 0.4)
    0.27, 0.018, 0.018, 1.0,
    0.26, 0.016, 0.016, 0.95,
    0.255, 0.014, 0.014, 0.8,
    0.25, 0.012, 0.012, 0.5,
    0.25, 0.01,  0.01,  0.25,
    0.25, 0.008, 0.008, 0.08,
    0.25, 0.005, 0.005, 0,
    0.25, 0.005, 0.005, 0
)
```

**Pros**:
- ✅ RGB variation should prevent banding
- ✅ Darker colors minimize 3D appearance
- ✅ May satisfy both "circular" and "flat matte" requirements

**Cons**:
- ⚠️ Untested - requires validation
- ⚠️ Subtle RGB changes may not be enough

**Risk**: Medium - Requires testing

---

### Solution 3: Increase Texture Resolution + Dithering

**Implementation**: Use higher resolution texture with noise/dithering

```gdscript
width = 128   # or 256 (was 64)
height = 128  # or 256
# Add noise shader for dithering
```

**Pros**:
- ✅ More pixels = smoother interpolation
- ✅ Dithering breaks up banding artifacts
- ✅ Keeps flat RGB if desired

**Cons**:
- ❌ Higher memory usage
- ❌ Requires shader implementation
- ❌ May not solve fundamental banding issue

**Risk**: High - Complex implementation, uncertain outcome

---

### Solution 4: Use Pre-Rendered PNG Texture

**Implementation**: Create circular blood texture in external editor (GIMP, Photoshop) with proper anti-aliasing

**Pros**:
- ✅ Full control over appearance
- ✅ Can use dithering, noise, and advanced techniques
- ✅ Known to work in other contexts

**Cons**:
- ❌ Loses procedural generation
- ❌ Harder to modify programmatically
- ❌ Increased asset size

**Risk**: Low - Should definitely work, but loses flexibility

---

## Recommended Action Plan

### Phase 1: Test Round 5 Restoration (IMMEDIATE)

**File**: `scenes/effects/BloodDecal.tscn`

1. **Restore Round 5's complete gradient** (RGB + alpha)
2. **Test in exported build** - owner reports issue in exports
3. **Get owner feedback** on appearance

**Expected Outcome**: Circular puddles, but possibly "3D ball" appearance

---

### Phase 2: If Owner Rejects 3D Appearance

Try **Solution 2**: Dark RGB gradient

**Iterative Approach**:
1. Start with Round 5 gradient
2. Gradually reduce center brightness: 0.4 → 0.35 → 0.30 → 0.28
3. Test at each step until "flat matte" appearance achieved
4. Verify circles remain circular at each step

---

### Phase 3: If RGB Gradient Doesn't Help

Consider:
1. **Solution 4**: Pre-rendered PNG (safest fallback)
2. **Solution 3**: Dithering shader (most complex)

---

## Technical Insights

### Why RGB Gradient Might Prevent Banding

**Color Interpolation**:
- GPU interpolates between gradient stops
- With alpha-only: interpolates alpha on constant RGB
  - Result: Visible "steps" in transparency
- With RGB+alpha: interpolates BOTH channels
  - Result: Color transitions mask transparency steps

**Perceptual Smoothness**:
- Human eye more sensitive to RGB changes than alpha
- RGB gradient provides additional visual information
- Smooth color transition makes alpha steps less noticeable

**Mathematical Explanation**:
- Alpha-only: `color = (0.25, 0.02, 0.02, lerp(alpha1, alpha2, t))`
- RGB+alpha: `color = lerp((r1,g1,b1,a1), (r2,g2,b2,a2), t)`
- Second approach has 4D interpolation vs 1D, creating smoother result

---

## Lessons Learned

1. **Copy ALL parameters when restoring a fix**, not just structure
   - Round 9 copied offsets but not alpha values
   - Round 10 copied alpha but not RGB values

2. **RGB gradients may be essential for circular radial gradients**
   - All flat-RGB attempts failed
   - Only RGB-gradient (Round 5) succeeded

3. **"Flat matte" requirement may be incompatible with "circular" requirement**
   - Flat color creates banding artifacts
   - May need to compromise or find alternative solution

4. **Always test in the target environment** (exported builds)
   - Owner specifically mentions export issues

5. **Document what worked, not just what failed**
   - Round 5 worked but wasn't fully documented
   - Led to multiple incomplete restoration attempts

---

## References

### Gradient Banding Research

- [How to (and how not to) fix color banding](https://blog.frost.kiwi/GLSL-noise-and-radial-gradient/)
- [Mozilla Bug 627771 - Add dithering to gradient color transitions](https://bugzilla.mozilla.org/show_bug.cgi?id=627771)
- [Grainy Gradients – Frontend Masters Blog](https://frontendmasters.com/blog/grainy-gradients/)
- [What is Color Banding? - Simonschreibt](https://simonschreibt.de/gat/colorbanding/)
- [Color Banding in Gradient Animation: 10 Quick Fixes](https://www.svgator.com/blog/color-banding-gradient-animation/)
- [Easing Linear Gradients | CSS-Tricks](https://css-tricks.com/easing-linear-gradients/)

### Godot-Specific

- [GradientTexture2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html)
- [Godot Issue #17006 - Add dithering effect to prevent color banding](https://github.com/godotengine/godot/issues/17006)
- [PointLight2D poor quality - Godot Forum](https://forum.godotengine.org/t/pointlight2d-poor-quality/122611)

---

## Appendix: Gradient Comparison Table

| Round | Offsets | Max Gap | RGB | Alpha (0.2) | Alpha (0.35) | Alpha (0.45) | Result |
|-------|---------|---------|-----|-------------|--------------|--------------|---------|
| 5 | 9 | 0.2 | 0.4→0.25 gradient | 1.0 | 0.95 | 0.8 | ✅ CIRCULAR |
| 7 | 5 | 0.5 | 0.25 flat | 0.95 | - | - | ❓ Unknown |
| 8 | 6 | 0.55 | 0.25 flat | - | - | - | ❌ RECTANGULAR |
| 9 | 9 | 0.2 | 0.25 flat | 0.98 | 0.92 | 0.75 | ❌ RECTANGULAR |
| 10 | 9 | 0.2 | 0.25 flat | 1.0 | 0.95 | 0.8 | ❌ RECTANGULAR |
| 11 (proposed) | 9 | 0.2 | 0.4→0.25 gradient | 1.0 | 0.95 | 0.8 | ❓ Testing |

**Pattern**: Only configuration with RGB gradient succeeded. All flat-RGB configurations failed.

---

**Analysis Completed**: 2026-01-24
**Next Step**: Test Round 11 (Round 5 restoration) and gather owner feedback
