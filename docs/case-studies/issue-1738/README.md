# Case Study: Issue #1738 — Beach Water Distortion Not Visible

## Overview

- **Issue**: [#1738 — update вода на карте Пляж](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1738)
- **PR**: [#1739 — feat(#1738): add screen-space refraction distortion to Beach water](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1739)
- **Reporter**: Jhon-Crow (project owner)
- **Report date**: 2026-03-29
- **Resolution date**: 2026-03-29
- **Severity**: Bug — feature implemented but not visible to user

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

## What the User Should See After Fix

On the Beach level with the correct build:
- Water surface shows a subtle shimmering/lensing effect — background objects (sand, enemies, blood) visible through the water are slightly bent/rippled in sync with the wave animation
- Effect magnitude: ~13–23 pixels of displacement at 1080p
- During last-chance time-stop: distortion freezes completely (distortion_strength set to 0)
- After time resumes: distortion animation restores to 0.012

---

## Prevention

1. Always verify shader offset magnitudes against a known-working reference (e.g. `last_chance.gdshader` uses `ripple_strength = 0.01` directly)
2. When combining two scaled quantities as a product (e.g. `tiny_displacement × tiny_strength`), check the resulting magnitude is in the visible range (>0.001 screen UV = >1 pixel at 1080p)
3. The new `distortion_strength=X.XXXX` log line in `_ready()` will make future regressions immediately visible in game logs
