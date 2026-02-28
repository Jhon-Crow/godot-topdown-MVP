# Issue #930 Case Study: Fix Force Field Visual (Силовое поле)

## Issue Description

**Title:** `fix визуал силового поля` ("fix force field visual")

**Body (Russian):** "Силовое поле должно выглядеть как силовой пузырь с анимацией" — "The force field should look like a force bubble with animation."

The user provided two reference images showing the desired look:
1. `images/desired_1.png` — A human figure inside a glowing translucent blue sphere with an opaque/glass-like surface and swirling surface texture.
2. `images/desired_2.png` — A glowing energy sphere with a dark semi-transparent interior, bright glowing rim, and visible animated surface energy lines/particles.

Current state (see `images/current_state.png`): A thin blue ring/circle outline around the player. The center is fully transparent — it looks like just a circle border, not a bubble.

---

## Data Collected

- `images/desired_1.png` — Reference image 1 (desired bubble appearance): 284×177 PNG
- `images/desired_2.png` — Reference image 2 (desired bubble appearance): 462×280 PNG
- `images/current_state.png` — Current broken visual (thin blue ring outline): 195×142 PNG

### Historical Context (Previous Issues)

This issue is the third iteration of force field visual complaints:
- **Issue #906** / PR #907: Initial force field visual with bullet trapping implemented. Shader was designed as Fresnel rim bubble.
- **Issue #912** / PR #913: Force field still showed as large blue-filled circle (gradient texture bleeding), then as white square (shader not compositing in exports). Fix: Use `_create_ring_texture()` programmatic donut as primary visual, shader as optional enhancement.
- **Issue #930** (this issue): Force field now shows as thin blue ring — transparent center, visible rim only. Still not matching the desired bubble with translucent interior.

---

## Root Cause Analysis

### Why the current visual looks like a thin ring instead of a bubble

After Issue #912's fix, `_setup_shield_visual()` uses `_create_ring_texture()` as the **primary visual** — a 256×256 programmatic image that is:
- Fully transparent in the center (radius 0–84%)
- Blue glowing rim at radius 84–100%

The shader (`force_field.gdshader`) is loaded as an optional enhancement. The shader also currently outputs only the rim:
```glsl
// ---- Combined alpha ----
// Rim-only effect: completely transparent center with bright glowing edge
float combined = rim * glow_intensity * pulse;
```

Both the base texture AND the shader are designed with a transparent center. The result is a ring outline — correct behavior per the code, but not matching the desired bubble look.

### What the desired look requires

The reference images show:
1. A **semi-transparent interior** — the bubble is not hollow. The interior is dark but translucent (like frosted glass or a soap bubble). The game map/background is slightly visible through it.
2. A **bright glowing rim** at the edge — correctly implemented.
3. **Animated swirling surface texture** — energy lines, shimmer, particle-like dots moving across the surface.
4. **Iridescent color shift** — cyan/blue tones, possibly slight purple shift.

The fix requires:
- Adding interior fill alpha to both the ring texture and the shader.
- Making the interior semi-transparent (not opaque, not fully transparent).
- Enhancing the animation with multi-layer shimmer and surface energy patterns.

---

## Online Research: Godot 2D Force Field / Shield Bubble Effects

### Best Practices (Godot 4 canvas_item shaders)

According to the Godot documentation and community resources:
- **Canvas_item shaders** run per-pixel on 2D nodes. They receive `UV` coordinates (0.0–1.0) and can use `TIME` for animation.
- For a bubble effect, the standard approach is:
  1. Fresnel-like term: `pow(r, n)` where r is normalized distance from center — gives high alpha at edge, low at center.
  2. Interior fill: `smoothstep(0.3, 0.7, r)` — creates a soft fill that is transparent at center and opaque at rim.
  3. Rim glow: A sharp narrow band at r ≈ 0.9–1.0 with high alpha.
  4. Animation: `sin(TIME * speed + offset)` for pulsing; `sin(angle * n + TIME * s)` for rotating shimmer.

### Known Implementations / Similar Solutions

- **Godot Forum "Energy Shield 2D" shader** (2023): Uses `fresnel = pow(r, 2.0)` + `inner = smoothstep(0.0, 0.8, r)` to achieve filled bubble look with translucent center. Mix `inner * 0.3 + fresnel * 0.7` as alpha.
- **"Soap bubble" shader patterns**: Iridescent shimmer via angle-based sin waves, combined Fresnel + thin rim band.
- **GDShader.com community examples**: For a "force field bubble", recommended combination of:
  - Thin rim at outer edge (r > 0.85)
  - Soft fill across interior (linear falloff from center)
  - Noise-based or sin-based surface pattern
  - Alpha = `mix(fill * 0.25, rim * glow, pulse)`

### Key Insight for Top-Down 2D Games

In a top-down 2D game, the "bubble" effect differs from a 3D sphere:
- There is no perspective distortion — the bubble is always viewed from directly above
- The fill should be uniform across the circle, not sphere-shaped (no highlight at top-left corner from a "light source")
- The rim glow at the edge should be the most prominent feature
- A subtle soft fill (alpha 0.10–0.25) makes the interior visible as "something is there" without blocking gameplay visibility

---

## Proposed Solutions

### Solution A: Shader-Only Approach (Recommended for Godot 4 exports)

Given Issue #912's lesson that shaders may not apply correctly in exported builds, the safest approach is to make the **base ring texture** itself look like a bubble (with interior fill), while also updating the shader to match.

**Texture change**: Modify `_create_ring_texture()` to also paint a soft fill in the interior (alpha 0.08–0.15 in the center, ramping up to 0.7–0.9 at the rim).

**Shader change**: Add `inner_fill` term back but with low alpha (unlike the removed `inner_glow` which was too strong). Use `fresnel = pow(r, 2.5)` at alpha 0.15 for the interior fill. Keep the rim glow at full brightness.

### Solution B: Multi-layer Sprite Approach

Use two overlapping `Sprite2D` nodes:
1. A filled semi-transparent circle (inner layer) for the translucent interior.
2. A ring texture (outer layer) for the glowing rim.

**Downside**: More nodes, harder to animate consistently.

### Solution C: Animated Texture Generation

Generate the texture dynamically in `_process()` using GDScript `Image` API, updating the texture each frame with animated noise patterns.

**Downside**: Extremely expensive (CPU texture generation per frame at 60fps). Not recommended.

### Chosen Approach: Solution A

Modify `_create_ring_texture()` to include a soft translucent interior fill, matching the desired bubble appearance even without shader support. Update the shader to also include the interior fill for enhanced animated version.

**Changes needed:**
1. `scripts/shaders/force_field.gdshader`: Add interior fill component (`fresnel` at low alpha), enhance animation.
2. `scripts/effects/force_field_effect.gd`: Modify `_create_ring_texture()` to include interior fill.

---

## Implementation Plan

### 1. Update `_create_ring_texture()` in `force_field_effect.gd`

The ring texture will include:
- Transparent exterior (r > 1.0) — unchanged
- Semi-transparent interior fill: alpha = `sin(r * PI * 0.5) * 0.18` for r = 0–0.84 (soft gradient from ~0.18 at center to 0 at inner rim edge)
- Blue glowing rim at r = 0.84–1.0: alpha via bell curve `sin(t * PI) * 0.9` — unchanged

The interior fill provides the "frosted bubble glass" look even without shader support.

### 2. Update `force_field.gdshader`

The shader will include:
- **Interior fill**: `fill = pow(r, 1.5) * 0.25 * pulse` — grows from center outward, fades toward center
- **Rim glow**: unchanged (narrow band at r ≈ 0.92)
- **Surface shimmer**: Two overlapping sin waves at different angles for energy surface pattern
- **Iridescent color**: unchanged
- **Combined alpha**: `clamp(rim * glow_intensity + fill, 0.0, 1.0) * pulse * edge_fade`

### 3. Add unit tests in `tests/unit/test_force_field_visual.gd`

Test the visual constants and ring texture properties via a mock class.

---

## Expected Outcome

After fix:
- The force field will appear as a translucent blue bubble (not just a ring outline)
- The interior will have ~15-20% opacity, enough to see the field without blocking gameplay
- The rim will glow brightly
- The animation will pulse and shimmer with energy patterns
- The effect will work correctly in both editor and exported games (texture provides fallback look)
