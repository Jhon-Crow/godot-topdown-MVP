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

## Third Investigation — 2026-04-10 (Iteration 3)

### User Feedback

Owner comment on PR #1739 (2026-04-10):
> "проверил новый билд нет изменений" (checked new build, no changes)

After both previous fixes, the owner still reports no visible distortion in a fresh build.

### Finding 6: Screen-space refraction fundamentally cannot produce visible water distortion at 88% opacity

The entire approach of relying on `hint_screen_texture` + blending to produce the visible distortion was architecturally flawed:

```glsl
// 88% opaque water → only 12% of distorted screen bleeds through
vec3 final_rgb = mix(screen_col.rgb, water_col.rgb, water_col.a);
//                                                  ^^^^ = 0.88
```

Even with a 27px offset, if the distorted background pixels differ only slightly from the undistorted ones (and against blue-ish sandy/beach ground, they often don't differ much at all), the 12% contribution is imperceptible.

**Godot forum research** confirms this is a known issue: water shaders with `hint_screen_texture` and high opacity values have invisible refraction because the screen bleed is overwhelmed by the opaque water color.

### Finding 7: The reference image shows internal water color modulation, not see-through transparency

Looking at the reference image (attached to PR comment on 2026-03-30):
- The water shows **horizontal bands of lighter/darker blue** scrolling across the surface
- This is NOT the background showing through — the water itself is the source of the distortion
- This is a **brightness/luminance modulation** effect: wave crests appear brighter, troughs appear darker
- This is how real ocean looks from above: sunlight reflects differently at wave crests vs troughs

### Fix Applied — Third Iteration (2026-04-10)

**Root cause**: Relying on screen texture bleed (12% contribution) as the sole distortion signal.

**Fix**: Add **wave-band shimmer** as the primary distortion — multiply the water's own base color by a wave-derived brightness multiplier. This is **always visible** regardless of opacity.

```glsl
// shimmer_signal ∈ [-1, 1]: positive = crest (bright), negative = trough (dark)
float shimmer_signal = (wave1_occ + wave2_occ * 0.6) * (1.0 / 1.6);

// distortion_strength = 0.35 → crests at 1.35×, troughs at 0.65× brightness
float shimmer = 1.0 + shimmer_signal * distortion_strength;

// Apply to the water base colour — ALWAYS visible regardless of alpha
vec4 water_shimmered = vec4(clamp(water_base.rgb * shimmer, 0.0, 1.0), water_base.a);
```

**Changed parameters:**
- `distortion_strength`: range changed from `hint_range(0.0, 0.1)` → `hint_range(0.0, 1.0)`, default `0.025` → `0.35`
- Screen-space refraction offset: `distortion_strength * 0.04` (so at 0.35, offset = 0.014 screen-UV ≈ 15px — secondary effect)
- Primary distortion: internal water color shimmer (always visible)

**Why shimmer = 0.35 is correct:**
- At `wave1_occ = +1.0` (wave crest): `shimmer = 1 + 1.0 × 0.35 = 1.35` → water is 35% brighter → clearly visible as a lighter band
- At `wave1_occ = -1.0` (wave trough): `shimmer = 1 - 1.0 × 0.35 = 0.65` → water is 35% darker → clearly visible as a darker band
- Combined with `wave2` (Y-axis), this creates horizontal bands of alternating bright/dark water exactly matching the reference image

---

## What the User Should See After Third-Iteration Fix

On the Beach level with a fresh build from branch `issue-1738-ed6a6a650ce1`:
- Clear horizontal wavy bands of lighter/darker water scroll across the surface
- Effect is **always visible** — it's within the water color itself, not a transparency trick
- Bands scroll from deep water toward the shore in sync with wave animation
- During last-chance time-stop: `distortion_strength` is set to `0.0` → flat water (no shimmer)
- After time resumes: distortion restores to `0.35`

Check game log for: `[WaterBody] Ready — ... distortion_strength=0.3500`

---

## Fourth Investigation — 2026-04-17 (Follow-up)

### User Feedback

Owner comment on PR #1739 (2026-04-11):
> "РАБОТАЕТ, зафиксируй это как удачный коммит. теперь сделай так, чтоб оригинальная (не искажённая картинка) не отображалась, а отображалась только искажённая (то есть чтоб не двоилась, а была только подвижная искажённая версия, как будто смотрим сквозь волны)"

Translation: the shimmer works; now remove the original/non-distorted picture so it does not double, leaving only the moving distorted version as if looking through waves.

### Finding 8: The accepted shimmer still used a stable water layer as the dominant final image

The third iteration made wave bands visible, but the final composition still used the old alpha overlay:

```glsl
vec3 final_rgb = mix(screen_col.rgb, water_col.rgb, water_col.a);
```

With `water_col.a` near `0.88`, the stable water colour remained 88% of the visible result. That can read as a second, non-distorted layer over the refracted sample.

### Fix Applied — Fourth Iteration (2026-04-17)

The shader now uses the refracted screen sample as the primary image and applies the animated water colour only as a tint:

```glsl
vec3 refracted_tinted = screen_col.rgb * water_col.rgb;
vec3 final_rgb = mix(screen_col.rgb, refracted_tinted, 0.25);
```

This preserves the accepted moving wave shimmer signal, but removes the dominant stable/original overlay. The visible water is now mostly the distorted scene sample, lightly tinted by animated blue water and foam brightness.

Regression coverage was added to `tests/unit/test_water_body.gd` to lock in the composition rule: the issue #1738 final image must stay closer to the distorted sample than to the old stable water overlay.

---

## Prevention

1. Never use `hint_screen_texture` blending as the **sole** distortion mechanism for opaque nodes — 88% opacity means only 12% of the distorted scene bleeds through, making the effect imperceptible.
2. For opaque water surfaces, use **internal colour modulation** (brightness ×shimmer factor): wave crests brighter, troughs darker — always visible regardless of alpha.
3. Always verify shader offset magnitudes against a known-working reference (e.g. `last_chance.gdshader` uses `ripple_strength = 0.01` directly).
4. The `distortion_strength=X.XXXX` log line in `_ready()` makes future regressions immediately visible in game logs.
5. When iterating on visual effects, ask the user for a **reference screenshot** early — the reference image on 2026-03-30 would have clarified the desired effect (internal color modulation) immediately.
6. After a visual effect is accepted, check the final compositing path separately: an effect can be visible but still layered over an unwanted stable/original image.
