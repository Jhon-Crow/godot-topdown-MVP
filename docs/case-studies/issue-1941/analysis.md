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

The implementation uses option 3: a procedural CanvasItem overlay shader attached to the existing pause background `ColorRect`. It draws radial cracks, small branch cracks, scratches, haze, tint, darkening, and vignette directly into the overlay.

This keeps the pause menu simple, avoids renderer-specific screen texture issues, and gives the requested cracked/scratched glass impression without adding image assets.

## Verification

- Added `test_pause_menu_background_uses_cracked_glass_shader` to ensure `PauseMenu.tscn` keeps the cracked glass shader attached to its full-screen background.
- Existing PauseMenu tests continue to verify scene load, instantiation, and button signal wiring.
