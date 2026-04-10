# Case Study: Issue #1738 — Beach Water Distortion Not Visible

## Overview

- **Issue**: [#1738 — update вода на карте Пляж](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1738)
- **PR**: [#1739 — feat(#1738): add screen-space refraction distortion to Beach water](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1739)
- **Reporter**: Jhon-Crow (project owner)
- **Report date**: 2026-03-29
- **Resolution date**: 2026-04-10 (second iteration)
- **Severity**: Bug — feature implemented but not visible to user

## Collected Logs

- [`game_log_20260329_182221.txt`](./game_log_20260329_182221.txt) — game log from first user test (build predating PR)

---

## Timeline of Events

| Time (UTC+3) | Event |
|---|---|
| ~18:22 | Player launches exported build from local folder (`I:/Загрузки/godot exe/ОСадКИ/`) |
| 18:23:07 | Player enters BeachLevel; log records `Water node found OK — visual=true shader=true` |
| ~18:23–18:25 | Player observes water — no distortion visible |
| 2026-03-29T15:23 | Owner posts comment: "искажения нет" (no distortion), attaches game log |
| 2026-03-29T16:03 | AI work session started to investigate root cause |

---

## Collected Evidence

### Game Log
- File: [`game_log_20260329_182221.txt`](./game_log_20260329_182221.txt)
- Key entries:
  ```
  [18:23:07] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
  ```
- **No** `[WaterBody]` log entries at all — the script version in the build predates our logging additions.
- Build info: `build_info.cfg not found` — raw exported binary without version tracking.
- Engine: Godot 4.3-stable (official), OS: Windows, Debug: false

### Environment
- The build was run from `I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe` — a pre-existing exported binary, **not** rebuilt from the PR branch.
- No `[WaterBody]` log entries → the `water_body.gd` in the build is the pre-PR version.

---

## Root Cause Analysis

### Finding 1: Build predates the PR

The game log was produced with an **old exported build** that does not include the changes from PR #1739. This is confirmed by:
1. Zero `[WaterBody]` log lines (our PR adds distortion-strength logging in `_ready()`)
2. `build_info.cfg not found` (no version tracking)
3. The exe path being a Загрузки (Downloads) folder with no relation to the repository

However, a second root cause exists in the PR code itself that would have caused the distortion to be invisible **even with the correct build**:

### Finding 2: Distortion math bug — double-scaling to sub-pixel values

In the original `realistic_water.gdshader` (PR #1739, first iteration):

```glsl
vec2 refract_offset = vec2(total_disp, total_disp * 0.5) * distortion_strength * occ_factor;
```

Where:
- `total_disp = wave1_occ * wave_amplitude + wave2_occ * ripple_amplitude`
- `wave_amplitude = 0.010`, `ripple_amplitude = 0.003`
- Therefore `total_disp ∈ [-0.013, 0.013]` (UV fractions)
- `distortion_strength = 0.008`

Actual screen-UV offset:
```
refract_offset ≈ 0.013 × 0.008 = 0.0001 (= 0.01% of screen width)
```

At 1920×1080: **0.0001 × 1920 ≈ 0.19 pixels** — sub-pixel, completely invisible.

**Comparison with `last_chance.gdshader`** (working reference):
```glsl
float ripple = sin(...) * ripple_strength;  // ripple_strength = 0.01
vec2 distorted_uv = SCREEN_UV + normalize(uv_from_center) * ripple;
```
Here `ripple_strength = 0.01` = direct 1% screen offset = ~19 pixels at 1080p — clearly visible.

### Finding 3: Double occlusion factor

The original code also applied `occ_factor` twice:
- Once inside `wave1_occ = wave1 * occ_factor`
- Once again as `* occ_factor` at the end of the refract_offset expression

This would have further reduced the offset near obstacles.

---

## Fix Applied

### `scripts/shaders/realistic_water.gdshader`

**Before (invisible):**
```glsl
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.008;
// ...
vec2 refract_offset = vec2(total_disp, total_disp * 0.5) * distortion_strength * occ_factor;
```

**After (visible):**
```glsl
// 0.012 ≈ 1.2% of screen width ≈ 13 px at 1080p — clearly visible
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.012;
// ...
// wave1_occ, wave2_occ ∈ [-1, 1] — use as direction, distortion_strength as magnitude
// wave1_occ/wave2_occ already include occ_factor, no double-multiplication
vec2 refract_offset = vec2(wave1_occ, wave2_occ * 0.5) * distortion_strength;
```

**Why this works:**
- `wave1_occ ∈ [-1, 1]` provides the distortion direction in sync with visible wave motion
- `distortion_strength = 0.012` is the direct screen-UV offset (matches `last_chance.gdshader` pattern)
- Maximum offset: `1.0 × 0.012 = 0.012` = 1.2% of screen = ~23px at 1920px width — clearly visible

### `scripts/objects/water_body.gd`

Added `distortion_strength` value to the `_ready()` log line so future builds report it at startup:
```
[WaterBody] Ready — visual=true shader=OK ... distortion_strength=0.0120
```

### `tests/unit/test_water_body.gd`

Updated default value in `MockWaterBodyTimeStop` from `0.008` to `0.012` to match the shader default.

---

## What the User Should See After Fix (First Iteration)

On the Beach level with the correct build (PR commit `2c9baf3b`):
- Water surface shows a subtle shimmering/lensing effect — background objects visible through the water are slightly bent/rippled in sync with wave animation
- Effect magnitude: ~13–23 pixels of displacement at 1080p
- During last-chance time-stop: distortion freezes completely

However, the owner tested with a fresh build from this branch and reported **"не сработало"** (did not work) on 2026-03-30.

---

## Second Investigation — 2026-04-10

### User Feedback

Owner comment on PR #1739 (2026-03-30):
> "не сработало, должно выглядеть так:" [attached reference image showing wavy distortion bands]

The reference image shows clear wave-band distortion — horizontal wavy lines distorting the visible background through the water (like looking at a pool from above with sunlight causing rippled caustic bands).

### Finding 4: Distortion still invisible due to alpha blending

Even with the corrected `distortion_strength = 0.012`, the distortion remained invisible because:

**Alpha blending kills the refraction**: The water's `shallow_color.a ≈ 0.88` and `deep_color.a ≈ 0.94`. The shader composes:
```glsl
vec3 final_rgb = mix(screen_col.rgb, water_col.rgb, water_col.a);
```
This means ~88–94% of the final pixel is opaque water colour, and only ~6–12% is the distorted scene.
Even at ±0.012 UV offset (≈13 px), only 12% of that shows through — the effect was too subtle.

### Finding 5: Distortion was only horizontal (X-axis)

The first fix used:
```glsl
vec2 refract_offset = vec2(wave1_occ, wave2_occ * 0.5) * distortion_strength;
```
- `wave1 = sin(uv.x * ...)` — varies along X → creates horizontal shear
- `wave2 = sin(uv.x * ...) * sin(uv.x * ...)` — still only X-axis variation

The reference image shows **both X and Y distortion** — horizontal bands that wobble the scene vertically (Y-axis displacement creates visible wave bands running across the water horizontally).

### Fix Applied — Second Iteration

**`scripts/shaders/realistic_water.gdshader`** changes:

1. **`wave2` now uses `uv.y`** for vertical variation:
   ```glsl
   // Before: uv.x only → horizontal shear only
   float wave2 = sin(uv.x * ...) * sin(uv.x * ...);
   // After: uv.y primary → creates visible horizontal wave bands
   float wave2 = sin(uv.y * ripple_frequency + TIME * ripple_speed)
               * sin(uv.x * ripple_frequency * 0.7 - TIME * ripple_speed * 0.5);
   ```

2. **Y-axis displacement is now full strength** (not halved):
   ```glsl
   // Before: vec2(wave1_occ, wave2_occ * 0.5)
   // After:  vec2(wave1_occ, wave2_occ)
   vec2 refract_offset = vec2(wave1_occ, wave2_occ) * distortion_strength;
   ```

3. **`distortion_strength` raised from `0.012` to `0.025`** (2.5% screen = ~27 px at 1080p):
   ```glsl
   uniform float distortion_strength : hint_range(0.0, 0.1) = 0.025;
   ```

**Why this produces the visible effect:**
- `wave2 = sin(uv.y * 6.0 + TIME * 0.5) * sin(...)` creates horizontal bands that scroll vertically
- These bands, used as Y-axis offset, displace the background up and down in alternating stripes
- Result: the characteristic wave-band shimmer seen in the reference image
- At ±0.025 UV (~27 px), even 12% contribution is visually prominent

---

## What the User Should See After Second-Iteration Fix

On the Beach level with a fresh build from branch `issue-1738-ed6a6a650ce1`:
- Visible wavy horizontal bands shimmer across the water surface
- The background (sand, beach objects) appears distorted/bent by the wave motion
- Bands scroll from deep water toward the shore in sync with wave animation
- During last-chance time-stop: all distortion freezes (distortion_strength = 0)
- After time resumes: distortion restores to 0.025

Check game log for: `[WaterBody] Ready — ... distortion_strength=0.0250`

---

## Prevention

1. Always verify shader offset magnitudes against a known-working reference (e.g. `last_chance.gdshader` uses `ripple_strength = 0.01` directly)
2. When combining two scaled quantities as a product, check the resulting magnitude is in the visible range (>0.001 screen UV = >1 pixel at 1080p)
3. For 2D top-down water distortion, use **both X and Y** wave displacement — Y-axis displacement creates the characteristic wave-band shimmer effect
4. The `distortion_strength=X.XXXX` log line in `_ready()` makes future regressions immediately visible in game logs
