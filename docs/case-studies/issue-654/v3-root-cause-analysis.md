# Issue #654 — v3 Root Cause Analysis

## User Feedback (v2)

> "эффект не тот" (the effect is wrong)

The user provided a screenshot showing the current v2 effect (large discrete blue blobs along the beam) vs the reference (smooth continuous red glow with the beam as the brightest element).

## Visual Comparison

### v2 Effect (Wrong)
- Large discrete blue "orbs" scattered along the laser beam
- Looks like a "string of Christmas lights" — individual particles are clearly visible as separate objects
- The glow layers are barely visible; particles dominate the visual

### Reference Effect (Correct)
- A smooth, continuous glow around the entire beam length
- The beam core is the brightest element (thin bright line)
- Glow fades smoothly outward (Gaussian-like falloff)
- Dust motes are barely visible as tiny specks, NOT large orbs

## Root Causes

### 1. Dust Particles Too Large (Primary Cause)
- **v2 setting:** 32px texture at 0.8-2.0x scale = 25-64 pixel blobs
- **Problem:** These are 10-30x larger than real dust motes visible in a laser beam
- **Fix:** 6px texture at 0.3-0.8x scale = 2-5 pixel specks

### 2. Too Few Particles
- **v2 setting:** 32 particles with 1.2s lifetime
- **Problem:** Not enough density for particles to blend into background; each one stands out individually
- **Fix:** 80 particles with 0.8s lifetime — more numerous but shorter-lived, creating subtle shimmer

### 3. Particle Alpha Too High
- **v2 setting:** Color ramp peak at 0.9-1.0 alpha
- **Problem:** Particles are fully opaque, drawing all visual attention away from the beam
- **Fix:** Color ramp peak at 0.4 alpha — particles are subtle accents, not focal points

### 4. Glow Layer Alpha Values Wrong
- **v2 setting:** 0.8 / 0.4 / 0.2 / 0.1 (too flat, all layers similarly bright)
- **Problem:** Outer layers too bright relative to inner layers, creating a washed-out/flat glow instead of focused beam
- **Fix:** 0.6 / 0.15 / 0.05 / 0.02 (steep Gaussian-like falloff, glow concentrated near core)

### 5. Emission Area Too Wide
- **v2 setting:** DustEmissionHalfHeight = 6px
- **Problem:** Particles spawn too far from beam center, making them look disconnected
- **Fix:** DustEmissionHalfHeight = 2px — particles stay close to the beam

## Key Insight
The dominant visual effect should come from the **Line2D glow layers** (which produce a smooth continuous glow along the entire beam), NOT from particles. Particles are meant to be a subtle secondary accent — tiny flickering specks that add life to the effect, not the main visual feature.
