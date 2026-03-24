# Case Study: Issue #1445 — Realistic Water on the Beach Level

## Problem Statement

Issue #1445 requests adding realistic water to the Beach map (`BeachLevel.tscn`) with:

1. **Wave animation** — waves resembling a real ocean beach.
2. **Physical interaction** — water reacts when the player (or enemies) walk through it (ripple/splash effect).
3. **Light refraction** — light bends as it passes through water (background distortion).

Previously the water was represented by a plain `ColorRect` (`WaterEdge`), with no animation or interactivity.

---

## Research Findings

### 2D Water Rendering Techniques

| Technique | Description | Cost |
|---|---|---|
| Sum-of-sines waves | Stack multiple `sin()` calls with different frequency/speed to create convincing wave bands | Low |
| Gerstner waves | Circular displacement of vertices; more physically accurate ocean surface | Medium |
| Noise-based displacement | Perlin/Simplex noise animates water surface organically | Medium |
| Screen-space refraction | Distort `SCREEN_TEXTURE` UV by wave normal → bend background light | Low–Medium |
| Foam / white-caps | Threshold the wave height value and blend a white foam color | Low |

### Known Libraries & Shaders

- **GodotShaders.com** — "2D Water Distortion Effect", "Gerstner Wave Ocean Shader" (MIT license).
- **[boujie_water_shader](https://github.com/Chrisknyfe/boujie_water_shader)** — Godot 4.1+ infinite ocean with foam.
- **[Godot4WaterShader](https://github.com/bramreth/Godot4WaterShader)** — Visual shader, beginner-friendly.
- **[laverneth/water](https://github.com/laverneth/water)** — 2D splash node with Area2D interaction (direct analogue to our implementation).

### Player Interaction Pattern

Standard Godot 4 pattern:
1. `Area2D` with `RectangleShape2D` covers the water region.
2. `body_entered` / `body_exited` signals track which bodies are in the water.
3. `_process` measures body displacement; when it exceeds a threshold, a splash is spawned.
4. The splash is a short-lived `Node2D` that draws expanding arcs in `_draw()`.

---

## Solution Implemented

### New Files

| File | Purpose |
|---|---|
| `scripts/shaders/realistic_water.gdshader` | `canvas_item` shader: animated sum-of-sines waves, light refraction via `SCREEN_TEXTURE`, foam, depth gradient, shore fade. |
| `scripts/effects/water_splash_effect.gd` | `Node2D` that draws 3 expanding concentric ripple rings procedurally (no texture required). |
| `scripts/objects/water_body.gd` | `Area2D` that creates the visual `ColorRect` + shader, the `CollisionShape2D`, and manages body tracking + splash spawning. |
| `scenes/objects/WaterBody.tscn` | Packed scene wrapping `water_body.gd`. |

### Modified Files

| File | Change |
|---|---|
| `scenes/levels/BeachLevel.tscn` | Replaced plain `WaterEdge` ColorRect with `WaterBody` instance at same position/size. |
| `scripts/levels/beach_level.gd` | Added `_setup_water()` call in `_ready()` + function body that verifies the node. |

### Shader Design (realistic_water.gdshader)

```glsl
// Primary wave (horizontal)
float wave1 = sin(uv.x * wave_frequency + TIME * wave_speed)
            + sin(uv.x * wave_frequency * 0.73 - TIME * wave_speed * 0.6);

// Secondary ripple (diagonal)
float wave2 = sin((uv.x + uv.y * 0.4) * ripple_frequency + TIME * ripple_speed) * ...;

// Screen-space refraction
vec2 refract_offset = vec2(dx, dy) * refraction_strength;
vec4 screen_col = texture(SCREEN_TEXTURE, SCREEN_UV + refract_offset);

// Foam where wave crest > threshold
float foam_val = smoothstep(foam_threshold, 1.0, pow(clamp(wave1*0.5+0.5, 0.0, 1.0), foam_sharpness));
```

Key parameters (all tunable via shader uniforms):
- `wave_speed`, `wave_frequency`, `wave_amplitude`
- `ripple_speed`, `ripple_frequency`, `ripple_amplitude`
- `refraction_strength`
- `shallow_color`, `deep_color`, `foam_color`
- `foam_threshold`, `shore_fade_width`

### Interaction Design (water_body.gd)

- `Area2D` collision mask covers player (layer 1) and enemies (layer 2).
- On `body_entered` → immediate splash.
- Per-frame distance check → new splash every `splash_interval` pixels of movement.
- Splash nodes are parented to the level (not the water body) so they render correctly.

---

## Trade-offs & Alternatives

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Use `AnimatedSprite2D` with sprite sheets | Easy, no GPU cost | Requires art assets, no refraction | Rejected |
| Godot `CPUParticles2D` for ripples | Built-in, no code | Hard to match exact position, less control | Rejected |
| Custom `_draw()` arcs (chosen) | No assets needed, precise control | CPU side-draw call per frame | Accepted |
| 3rd-party boujie_water_shader | Very realistic | External dependency, 3D-style API | Rejected for now |

---

## References

- GodotShaders.com — 2D Water Distortion Effect: https://godotshaders.com/shader/2d-water-distortion-effect-godot-4/
- GodotShaders.com — Gerstner Wave Ocean Shader: https://godotshaders.com/shader/gerstner-wave-ocean-shader/
- laverneth/water (Area2D interaction): https://github.com/laverneth/water
- Porting Water Ripple Shader Unity→Godot: https://80.lv/articles/tutorial-porting-a-water-ripple-shader-from-unity-to-godot/
- Ocean Waves and Shaders (math primer): https://peterbraden.co.uk/article/ocean-waves-2/
- Water Simulation in GLSL: https://jayconrod.com/posts/34/water-simulation-in-glsl
