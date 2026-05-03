# Issue 1941 Case Study: Pause Background Cracked Glass Shader

## Request

Issue #1941 asks to add a shader so the pause background looks like slightly scratched or cracked glass, then collect repository and external research data in `docs/case-studies/issue-1941` and use it to evaluate solutions.

## Repository Findings

- `scenes/ui/PauseMenu.tscn` already has a full-screen `ColorRect` behind the pause controls.
- The project uses Godot 4 CanvasItem shaders in `scripts/shaders`.
- `scripts/shaders/cinema_film.gdshader` documents a practical compatibility concern: overlay-only effects are more robust than screen-reading effects in Godot Compatibility rendering.
- `tests/unit/test_pause_menu.gd` already covers PauseMenu scene loading and button connectivity, making it the correct place for a regression guard.

## External Research

- Godot's official screen-reading shader documentation describes `hint_screen_texture` and `SCREEN_UV` for shaders that sample the rendered scene behind a CanvasItem.
- Godot 4 removed the old `SCREEN_TEXTURE` built-in, so Godot 4 shaders should declare a `sampler2D` uniform with `hint_screen_texture` when screen sampling is needed.
- Community cracked-glass shaders commonly use screen sampling for refraction, but this project already notes Compatibility renderer risk for such effects.

## Solution Options

1. **Screen-reading refractive glass shader**
   - Pros: can distort the actual paused scene behind the menu.
   - Cons: higher renderer compatibility risk and possible conflicts with other screen-reading effects.

2. **Texture-based cracked glass overlay**
   - Pros: predictable and art-directable.
   - Cons: needs an additional texture asset and may scale poorly across resolutions without careful import settings.

3. **Procedural overlay CanvasItem shader**
   - Pros: no extra asset, deterministic, compatible with the existing pause background, and robust across renderers.
   - Cons: does not physically refract the scene behind the menu.

## Implemented Approach

The implementation uses option 3: a procedural CanvasItem overlay shader attached to the existing pause background `ColorRect`.

### v1 (initial) — line-segment approach
Cracks were drawn with an explicit loop over 12 `line_segment()` calls radiating from a fixed centre. This produced visually thick, artificial-looking neon lines (feedback: "очень жирные линии" — "very thick lines").

### v2 (revised) — Voronoi + FBM approach
Ported from the [godotshaders.com/shader/cracked-glass/](https://godotshaders.com/shader/cracked-glass/) reference implementation.  Key differences:

- **Voronoi cell-edge distance** replaces explicit line segments. The `voronoi_edge()` function computes the signed distance to the nearest Voronoi cell border, naturally generating a spider-web of thin cracks across the whole screen.
- **FBM warp** (`fbm()`) displaces the Voronoi lookup coordinates before sampling, making crack paths irregular and organic rather than perfectly straight.
- **Multi-scale accumulation** (controlled by `crack_depth`) layers several successively-zoomed Voronoi grids so large primary cracks have fine secondary cracks branching from them.
- **crack_sharpness / crack_width** replace the old fixed `smoothstep` widths; the defaults are tuned for sub-pixel-thin cracks (`crack_width = 0.0015`).
- The original godotshaders.com shader uses `hint_screen_texture` for refraction; this project omits that to stay compatible with Godot's GL Compatibility renderer (same reasoning documented in `cinema_film.gdshader`).

## Verification

- `test_pause_menu_background_uses_cracked_glass_shader` ensures `PauseMenu.tscn` keeps the cracked glass shader attached to its full-screen background.
- Existing PauseMenu tests continue to verify scene load, instantiation, and button signal wiring.
