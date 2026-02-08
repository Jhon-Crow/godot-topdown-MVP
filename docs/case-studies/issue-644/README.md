# Case Study: Issue #644 — Light Scattering for Flashlight

## Problem Description

The flashlight beam in the game only creates a directional cone of light using a `PointLight2D` with a cone texture. In reality, when a flashlight beam hits a surface, the light scatters and creates an ambient glow around the impact point, illuminating the surrounding area. This effect is called "рассеивание света" (light scattering/diffusion).

## Current Implementation Analysis

### Existing Flashlight System (`flashlight_effect.gd`)
- Uses a single `PointLight2D` with a pre-baked cone texture (`flashlight_cone_18deg.png`)
- 18-degree total cone (9 degrees each side)
- `energy = 8.0`, `texture_scale = 6.0`
- `shadow_enabled = true` — light stops at walls
- Maximum range: 600 pixels (beam range for blinding)
- Positioned at weapon barrel, rotates with player aim

### Key Constraints
- Shadows must work correctly — scatter light should NOT pass through walls
- Must not interfere with existing fog of war (`RealisticVisibilityComponent`)
- Must not affect enemy blinding mechanics
- Performance must remain acceptable (runs on every physics frame)

## Solution Approach

### Technique: Dynamic Scatter Light at Beam Impact Point

Add a second `PointLight2D` with a radial gradient texture that follows the beam's endpoint. Use a raycast to find where the beam hits a wall (or reaches max range), and place the scatter light at that point.

**Implementation:**
1. Cast a ray from the flashlight origin along the beam direction
2. If a wall is hit, place the scatter light at the hit position
3. If no wall is hit, place it at the maximum beam range
4. Use a soft radial gradient texture with early fadeout (matching existing codebase pattern)
5. Low energy (0.3-0.5) relative to the main beam (8.0) for subtle ambient effect
6. `shadow_enabled = true` so scatter light respects walls

### Why This Approach
- Physically plausible — real flashlights create scatter at the impact point
- Uses existing Godot 2D lighting system (no shaders needed)
- Consistent with codebase patterns (early-fadeout gradients, PointLight2D usage)
- Minimal performance impact — one additional PointLight2D + one raycast per frame

### References
- [Godot 2D Lights and Shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html)
- [PointLight2D Documentation](https://docs.godotengine.org/en/stable/classes/class_pointlight2d.html)
- Existing codebase: `_create_window_light_texture()` for early-fadeout gradient pattern
- Existing codebase: `realistic_visibility_component.gd` for radial gradient creation

## Files Changed
- `scripts/effects/flashlight_effect.gd` — Added scatter light logic
- `scenes/effects/FlashlightEffect.tscn` — Added ScatterLight PointLight2D node
- `tests/unit/test_flashlight_effect.gd` — Added scatter light tests
