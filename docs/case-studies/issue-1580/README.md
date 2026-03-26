# Case Study: Rain Drop Animation — Puddle Splashes at Landing Point (Issue #1580)

## Problem Statement

Issue #1580 requests that puddles (circular ripples) appear at the exact point where rain drops (streaks) disappear. The animation should convey three sequential phases:
1. **Falling** — a raindrop moves downward as a streak
2. **Landing** — the streak reaches the ground and disappears
3. **Splashing** — a circular ripple expands outward from the landing point

The original `RainEffect.tscn` (from Issue #1394, fixed in #1499, #1546) had two particle layers — `RainStreaks` and `RainSplashes` — but they were not properly coordinated:
- Streaks used **radial inward velocity** (`radial_velocity_min = -140`, `radial_velocity_max = -80`), causing them to converge toward the screen center rather than fall straight down
- Splash particles appeared at a fixed offset position with random 180° spread, not synchronized with actual streak landing positions
- Streak texture height was 8px (too short for visible drops)
- Initial velocity was zero (no straight-down motion)

## Root Cause Analysis

The scene file was never updated to reflect the intended parameters described in the unit tests (`test_rain_effect.gd`, Issue #1546 fix section). The tests already document the correct values:
- `direction = Vector3(0.1, 1.0, 0.0)` — slightly angled downward fall
- `initial_velocity_min = 500`, `initial_velocity_max = 700` — drops move downward at speed
- `radial_velocity = 0` — no convergence toward center
- `streak texture height >= 16` — long enough to be visible as streaks

### Why the Splash Offset Works

With corrected streak parameters:
- direction normalized: `(0.0995, 0.9950, 0)`
- avg velocity: `600 px/s`
- avg lifetime: `0.18 * (1 - 0.2/2) = 0.162s`
- travel: `x ≈ 9.7px, y ≈ 96.7px`
- streak origin: `(640, 360)` → landing point: `≈ (649.7, 456.7)`
- splash emitter position: `(650, 457)` — matches within ±1px

The splash emitter position `(650, 457)` was already correct for the intended parameters. The scene just needed the streak parameters corrected.

## Solution

### Changes to `scenes/effects/RainEffect.tscn`

| Parameter | Before | After | Reason |
|-----------|--------|-------|--------|
| `GradientTexture2D_streak.height` | `8` | `16` | Streaks must be >= 16px tall for visibility |
| `ParticleProcessMaterial_streak.direction` | `Vector3(0, 0, 0)` | `Vector3(0.1, 1.0, 0.0)` | Drops fall downward with slight crosswind angle |
| `ParticleProcessMaterial_streak.spread` | `0.0` | `5.0` | Natural variation between drops |
| `ParticleProcessMaterial_streak.initial_velocity_min` | `0.0` | `500.0` | Drops need velocity to move downward |
| `ParticleProcessMaterial_streak.initial_velocity_max` | `0.0` | `700.0` | Velocity variation for natural rain |
| `ParticleProcessMaterial_streak.radial_velocity_min` | `-140.0` | `0.0` | Prevent convergence toward screen center |
| `ParticleProcessMaterial_streak.radial_velocity_max` | `-80.0` | `0.0` | Prevent convergence toward screen center |

**No changes needed to:**
- `RainSplashes` position `Vector2(650, 457)` — already matches streak landing point
- `rain_effect.gd` — logic is correct
- Splash material spread/lifetime — already creates convincing ripple effect

## References and Research

### Existing Solutions Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Fix streak parameters in TSCN (chosen) | Minimal change, aligns TSCN with existing tests | None | **Selected** |
| CPUParticles2D with particle_collision signal | Could hook into particle death events | CPU-bound, breaks existing GPU pattern | Rejected |
| GDScript-managed drops (custom Node2D) | Full control of timing | Much more complex, breaks existing architecture | Rejected |
| Shader-based synchronized rain | Pixel-perfect synchronization | Very complex, hard to exclude indoor zones | Rejected |

### Online Research: Top-Down Rain Drop Animation

Top-down rain effects in games typically use a two-layer approach:
- **Layer 1 (streaks)**: Short vertical lines or dashes representing drops in flight. Key parameters: downward direction, moderate-high speed (400–800 px/s), short lifetime (0.1–0.3s), slight angle variation.
- **Layer 2 (splashes)**: Circular ripples expanding outward from landing point. Key parameters: spawned at streak endpoint, zero-to-low outward velocity (0–5 px/s), longer lifetime (0.3–0.6s), radial gradient texture.

Reference: Hotline Miami 2 uses exactly this two-layer approach — visible in the reference screenshots at `docs/case-studies/issue-1394/hm2-rain-reference.png`.

### Mathematical Validation

```
direction = Vector3(0.1, 1.0, 0.0)
normalized_dir = (0.09950, 0.99504, 0)
avg_velocity = (500 + 700) / 2 = 600 px/s
avg_lifetime = 0.18 * (1 - 0.2/2) = 0.162 s  [0.2 = lifetime_randomness]

travel_x = 0.09950 * 600 * 0.162 ≈ 9.67 px
travel_y = 0.99504 * 600 * 0.162 ≈ 96.72 px

streak_origin = (640, 360)
landing_point = (640 + 9.67, 360 + 96.72) = (649.67, 456.72)
splash_position = (650, 457)
error = (0.33 px, 0.28 px) — well within ±10px test tolerance
```

## Testing

Existing tests in `tests/unit/test_rain_effect.gd` already cover the corrected behavior:
- `test_streak_direction_is_downward`: verifies `direction.y > 0`
- `test_streak_has_no_radial_velocity`: verifies both radial velocities = 0
- `test_streak_has_positive_initial_velocity`: verifies `velocity_min > 0` and `max > min`
- `test_streak_texture_is_long_enough`: verifies `height >= 16`
- `test_streak_scale_is_large_enough`: verifies `scale_max >= 2.0`
- `test_splash_offset_matches_streak_endpoint`: verifies splash at `(650, 457)` matches landing math

Additional tests added for Issue #1580:
- `test_splash_appears_at_streak_landing_zone`: confirms splash emission box aligns with streak travel zone
- `test_rain_animation_phases`: documents the three-phase drop animation contract

## File Changes

| File | Change |
|------|--------|
| `scenes/effects/RainEffect.tscn` | Fixed streak direction, velocity, radial velocity, texture height |
| `tests/unit/test_rain_effect.gd` | Added tests for Issue #1580 splash alignment and animation phases |
| `docs/case-studies/issue-1580/README.md` | This case study |
