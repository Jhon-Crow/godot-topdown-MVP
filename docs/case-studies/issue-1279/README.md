# Case Study: Issue #1279 — Neon Glow on Decadence Map

## Summary

**Issue:** The bright purple/pink neon elements on the Decadence map lacked dynamic lighting (glow effect).
**Request:** Add neon glow with dynamic shadows to bright pink and purple elements.
**Feedback:** After initial implementation, the owner requested the glow be smoother (no sharp corners, like real neon) and illuminate more space.

---

## Timeline / Sequence of Events

| Time (UTC) | Event |
|---|---|
| Issue opened | Owner requests neon glow for bright purple elements on Decadence map |
| PR #1280 created | AI solver adds 20 `PointLight2D` nodes with radial `GradientTexture2D`, `shadow_enabled = true` |
| 2026-03-21 12:30 | Owner comments: requests glow for two specific colors (pink + purple), provides screenshot |
| 2026-03-21 12:37 | AI confirms both colors covered, all CI passes |
| 2026-03-21 12:46 | Owner provides game log (`game_log_20260321_154334.txt`) and requests: (1) smoother glow, no sharp corners; (2) wider illumination radius; (3) case study analysis in this folder |

---

## Root Cause Analysis

### Problem: Sharp corners on glow

**Cause:** The `GradientTexture2D` used by `PointLight2D` had only **2 gradient stops** at offsets `0.0` and `1.0`:
```
colors = PackedColorArray(R, G, B, 1.0,  R, G, B, 0.0)
```
This creates an abrupt linear fade from fully opaque at center to fully transparent at edge — a hard, perceptible transition ring with no "bell curve" shape.

Real neon light follows an inverse-square or gaussian falloff: very bright at center, then rapidly fading in a smooth curve, with no perceivable hard boundary.

**Fix:** Add intermediate gradient stops at `0.1`, `0.3`, `0.6` with decreasing alpha to produce a smooth gaussian-like falloff:
- At 0.0 (center): alpha 1.0
- At 0.1: alpha 0.85
- At 0.3: alpha 0.5
- At 0.6: alpha 0.15
- At 1.0 (edge): alpha 0.0

### Problem: Insufficient illumination radius

**Cause:** `texture_scale = 6.0` with 128×128 px texture → effective radius ≈ 384 px. The Decadence map is 2400×2000 px with walls of the corresponding size, so 384 px radius leaves large dark zones between lights.

**Fix:** Increase `texture_scale` to `10.0` for wall lights (radius ≈ 640 px) and `8.0` for dance floor lights. Also slightly increase `energy` to compensate for the softer gradient.

---

## Evidence from Game Log

- **File:** `logs/game_log_20260321_154334.txt`
- **Session on DecadenceLevel:** 15:43:50 → 15:45:04 (≈74 seconds)
- **Enemies:** 13 active enemies (VIPGuard1/2, BarBouncer1/2, BarGunman, DanceFloorThug1/2, DanceFloorGunman, BackAlleyThug1/BackAlleyGunman, StorageGuard1/2, RadioJammer)
- **FPS drops noted:** Two drops to 29 fps (threshold 30) at 15:44:40 and 15:44:41 — indicative of mild performance pressure from the 20 shadow-enabled lights
- **No errors** related to lighting system in the log

---

## Facts About Godot 4 Radial Gradient Glow

- `GradientTexture2D` with `fill = 1` uses radial (circular) fill — the texture is circular, not square
- `PointLight2D` renders this texture as a billboard, so the **visual shape is already circular**
- The issue is the **gradient profile** (how alpha varies from center to edge), not the shape
- A 2-stop linear gradient in alpha space appears as a sharply bounded disk rather than a soft glow
- Adding intermediate stops with a steep initial falloff mimics the gaussian profile of real light

---

## Solution Applied

### Changes to `DecadenceLevel.tscn`

**Gradient sub-resources** — added `offsets` array and intermediate alpha stops for smooth falloff:

| Gradient | Before | After |
|---|---|---|
| `Gradient_neon_pink` | 2 stops (alpha 1→0, linear) | 5 stops (1→0.85→0.5→0.15→0, smooth) |
| `Gradient_neon_purple` | 2 stops (alpha 1→0, linear) | 5 stops (1→0.85→0.5→0.15→0, smooth) |

**PointLight2D nodes** — wall neon lights:

| Parameter | Before | After |
|---|---|---|
| `texture_scale` | 6.0 | 10.0 |
| `energy` | 0.8 | 1.2 |

**PointLight2D nodes** — dance floor neon lights:

| Parameter | Before | After |
|---|---|---|
| `texture_scale` | 5.0 | 8.0 |
| `energy` | 1.0 | 1.4 |

---

## Performance Note

The FPS drops observed (29 fps, threshold 30) during the game session with 20 shadow-enabled `PointLight2D` nodes are mild and at the threshold. Increasing `texture_scale` does NOT significantly affect performance (it's a scale multiplier, not additional draw calls). Shadow computation cost is the same regardless of light radius. The main cost is per-light shadow pass, which remains 20 lights.
