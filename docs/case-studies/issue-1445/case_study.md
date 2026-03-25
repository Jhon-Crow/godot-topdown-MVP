# Case Study: Issue #1445 — Realistic Water on the Beach Level

## Problem Statement

Issue #1445 requests adding realistic water to the Beach map (`BeachLevel.tscn`) with:

1. **Wave animation** — waves resembling a real ocean beach.
2. **Physical interaction** — water reacts when the player (or enemies) walk through it (ripple/splash effect).
3. **Light refraction** — light bends as it passes through water.

Previously the water was represented by a plain `ColorRect` (`WaterEdge`), with no animation or interactivity.

### Feedback from PR #1479 Review (Iteration 2)

The repository owner identified 5 issues with the initial implementation:

1. **Water is white** — The shader used `SCREEN_TEXTURE` which doesn't work properly without `BackBufferCopy` setup in 2D canvas. The `ColorRect` default white color showed through.
2. **Ripple circles visible through player** — `WaterSplashEffect` z_index was 3, same as player head, causing ripples to render on top of the player.
3. **Blood doesn't spread in water** — No interaction between blood effects and water body.
4. **Bloody footprints shouldn't remain in water** — Only a spreading color change should occur, not discrete footprint decals.
5. **No reaction to shell casings, grenades, or explosions** — Water only detected player/enemy bodies (collision layers 1 and 2), ignoring casings (layer 7) and grenades (layer 6).

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

### SCREEN_TEXTURE Gotchas in Godot 4

In Godot 4, `SCREEN_TEXTURE` in `canvas_item` shaders requires either:
- A `BackBufferCopy` node to capture what's behind the object, or
- The node to be rendered after the background in a specific rendering order.

Without proper setup, `SCREEN_TEXTURE` returns white/transparent, which was the root cause of Issue #1 (white water). The fix was to make the shader self-contained — drawing water colors directly from the shader's depth gradient rather than relying on `SCREEN_TEXTURE` distortion.

### Known Libraries & Shaders

- **GodotShaders.com** — "2D Water Distortion Effect", "Gerstner Wave Ocean Shader" (MIT license).
- **[boujie_water_shader](https://github.com/Chrisknyfe/boujie_water_shader)** — Godot 4.1+ infinite ocean with foam.
- **[Godot4WaterShader](https://github.com/bramreth/Godot4WaterShader)** — Visual shader, beginner-friendly.
- **[laverneth/water](https://github.com/laverneth/water)** — 2D splash node with Area2D interaction (direct analogue to our implementation).

### Z-Index Hierarchy in This Project

| Node | z_index | Purpose |
|---|---|---|
| Floor/background | 0 | Base layer |
| Blood decals | 0 | Floor stains |
| Water visual (ColorRect) | 1 | Water surface |
| Blood footprints | 1 | Floor marks |
| Player body | 1 | Character body sprite |
| Player head | 3 | Head above body |
| Player arms | 4 | Arms above head |
| Armband/effects | 5 | Top layer |

### Collision Layer Map

| Layer | Bitmask | Usage |
|---|---|---|
| 1 | 1 | Player |
| 2 | 2 | Enemies |
| 3 | 4 | Obstacles (walls, terrain) |
| 5 | 16 | Projectiles |
| 6 | 32 | Grenades |
| 7 | 64 | Blood puddles, shell casings |

---

## Solution Implemented

### Files Added

| File | Purpose |
|---|---|
| `scripts/shaders/realistic_water.gdshader` | `canvas_item` shader: animated sum-of-sines waves, foam, depth gradient, shore fade. Self-contained (no `SCREEN_TEXTURE`). Blood tint uniform for diffusion. |
| `scripts/effects/water_splash_effect.gd` | `Node2D` that draws expanding concentric ripple rings procedurally. Configurable for small (casings), normal (player), and large (explosions) splashes. z_index=0 to render below characters. |
| `scripts/effects/water_blood_diffusion.gd` | `Node2D` that draws expanding, fading blood clouds in water. Replaces footprints for blood-in-water interaction. |
| `scripts/objects/water_body.gd` | `Area2D` that manages water visual, collision, body/object tracking, splash spawning, bloody footprint suppression, and blood diffusion. Detects layers 1, 2, 6, 7. |
| `scenes/objects/WaterBody.tscn` | Packed scene wrapping `water_body.gd`. |

### Files Modified

| File | Change |
|---|---|
| `scenes/levels/BeachLevel.tscn` | Replaced plain `WaterEdge` ColorRect with `WaterBody` instance at same position/size. |
| `scripts/levels/beach_level.gd` | Added `_setup_water()` call in `_ready()` + function body that verifies the node. |

### Fix Details

#### Fix #1: Water is white
- **Root cause**: Shader used `SCREEN_TEXTURE` which doesn't work without `BackBufferCopy` in 2D. `ColorRect` default color is white.
- **Fix**: Removed `SCREEN_TEXTURE` dependency. Shader now draws water colors directly using depth gradient (shallow → deep blue). Set `ColorRect.color` to transparent so shader has full control.

#### Fix #2: Ripple circles visible through player
- **Root cause**: `WaterSplashEffect.z_index = 3`, same as player head sprite.
- **Fix**: Set `z_index = 0` so ripples render at base level, below all character parts (body z=1, head z=3, arms z=4).

#### Fix #3: Blood should spread in water
- **Fix**: Added `WaterBloodDiffusion` effect — expanding, fading red circles drawn with `draw_circle()`. Spawned when blood puddles appear in water (via `area_entered` signal detecting blood puddle Area2Ds) and when characters with bloody feet enter water.

#### Fix #4: No bloody footprints in water
- **Fix**: `WaterBody._suppress_footprints_on_body()` finds the `BloodyFeetComponent` on characters in water and calls `set_blood_level(0)` to prevent footprint spawning. Blood diffusion is spawned instead.

#### Fix #5: React to shell casings, grenades, and explosions
- **Fix**: Expanded `collision_mask` to `0b01100011` (layers 1+2+6+7 = 99).
  - **Casings** (group `"casings"`, RigidBody2D layer 7): Small splash on entry via `configure_small()`.
  - **Grenades** (group `"grenades"`, RigidBody2D layer 6): Normal splash on entry + connected to `exploded` signal for large splash on detonation via `configure_large()`.
  - Deduplication: Casings tracked in `_processed_casings` dict; grenades in `_connected_grenades` dict.

### Shader Design (realistic_water.gdshader)

```glsl
// Primary wave (horizontal)
float wave1 = sin(uv.x * wave_frequency + TIME * wave_speed)
            + sin(uv.x * wave_frequency * 0.73 - TIME * wave_speed * 0.6);

// Secondary ripple (diagonal)
float wave2 = sin((uv.x + uv.y * 0.4) * ripple_frequency + TIME * ripple_speed) * ...;

// Depth gradient (no SCREEN_TEXTURE needed)
vec4 water_base = mix(shallow_color, deep_color, depth);

// Foam where wave crest > threshold
float foam_val = smoothstep(foam_threshold, 1.0, pow(...));

// Blood diffusion via uniform tint
vec3 final_rgb = mix(water_col.rgb, blood_tint.rgb, blood_tint.a);
```

Key parameters (all tunable via shader uniforms):
- `wave_speed`, `wave_frequency`, `wave_amplitude`
- `ripple_speed`, `ripple_frequency`, `ripple_amplitude`
- `shallow_color`, `deep_color`, `foam_color`
- `foam_threshold`, `shore_fade_width`
- `blood_tint` (for global blood diffusion)

---

## Trade-offs & Alternatives

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Use `SCREEN_TEXTURE` refraction | True optical distortion | Requires `BackBufferCopy`, breaks in some 2D setups | Removed (caused white water) |
| Use `AnimatedSprite2D` with sprite sheets | Easy, no GPU cost | Requires art assets, no dynamic effects | Rejected |
| Godot `CPUParticles2D` for ripples | Built-in, no code | Hard to match exact position, less control | Rejected |
| Custom `_draw()` arcs (chosen) | No assets needed, precise control | CPU side-draw call per frame | Accepted |
| 3rd-party boujie_water_shader | Very realistic | External dependency, 3D-style API | Rejected for now |

---

## Iteration 3: "No physical water — just a blue background" (2026-03-25)

### User Feedback

After the Iteration 2 fixes were merged into the branch, the user reported:
> "сейчас вообще нет физической воды (просто голубой фон)" ("There is no physical water at all — just a blue background")
>
> Log file: `docs/case-studies/issue-1445/game_log_20260325_123952.txt`

### Timeline Reconstruction (from game_log_20260325_123952.txt)

| Time | Event |
|---|---|
| 12:39:52 | Game started on LabyrinthLevel |
| 12:39:57 | PersistManager saved last level: BeachLevel |
| 12:39:58 | Scene loaded: BeachLevel |
| 12:39:58 | BeachLevel._ready() fired; 8 enemies tracked; weapon set up |
| 12:39:58 | **No WaterBody log messages appear** |
| 12:40:05 | Scene restarted (BeachLevel again) |
| 12:40:05 | **Again: no WaterBody log messages** |

The WaterBody node is present in the scene file (`scenes/levels/BeachLevel.tscn` line 60), the `WaterBody.tscn` packed scene exists, and `beach_level.gd` calls `_setup_water()`. However, there are no log entries from the WaterBody. Since `_ready()` used `print()` rather than the file logger's `log_info()` for some messages, some could be missing from the log. But the visual effect (animated water waves) was completely absent from the user's view.

### Root Cause Analysis

**Root cause: `ColorRect.offset_*` properties are no-ops when the node's parent is a `Node2D`.**

The water visual is a `ColorRect` (a `Control` node) added as a child of `Area2D` (a `Node2D`). In Godot 4:

- `ColorRect.offset_left/right/top/bottom` only have effect within a `Control` container hierarchy (e.g., inside a `VBoxContainer`, `CanvasLayer`, or root Control).
- When a `Control` is placed inside a `Node2D`, positioning must use `position` and `size` instead.
- Setting `offset_*` on a `Control` whose parent is a `Node2D` results in a **zero-sized or default-positioned rectangle** that renders nothing visible.

Evidence from the codebase: every other place that creates a `ColorRect` as a child of a `Node2D` (e.g., `roguelike_level.gd` floor rects) correctly uses `floor_rect.position = ...` and `floor_rect.size = ...`. Every `ColorRect` using `offset_*` / `set_anchors_preset()` is inside a `CanvasLayer` or `Control` container.

The resulting visual: a `ColorRect` of effectively zero size (or pinned to top-left with wrong dimensions) rendered on top of the solid-blue `Background` ColorRect in the scene. The `Background` (`Color(0.15, 0.55, 0.85, 1)`, full 2528×2128px) filled the screen with solid blue, making the invisible water area indistinguishable.

### Fix (Iteration 3)

**`scripts/objects/water_body.gd` — `_create_visual()`**: Changed from `offset_*` to `position + size`:

```gdscript
# Before (broken):
_visual.offset_left   = -water_width  * 0.5
_visual.offset_top    = -water_height * 0.5
_visual.offset_right  =  water_width  * 0.5
_visual.offset_bottom =  water_height * 0.5

# After (correct):
_visual.position = Vector2(-water_width * 0.5, -water_height * 0.5)
_visual.size     = Vector2(water_width, water_height)
```

Added structured `_log()` helper in `WaterBody` (mirrors `beach_level.gd` pattern) so future game logs will capture WaterBody initialization status.

---

## References

- GodotShaders.com — 2D Water Distortion Effect: https://godotshaders.com/shader/2d-water-distortion-effect-godot-4/
- GodotShaders.com — Gerstner Wave Ocean Shader: https://godotshaders.com/shader/gerstner-wave-ocean-shader/
- laverneth/water (Area2D interaction): https://github.com/laverneth/water
- Porting Water Ripple Shader Unity→Godot: https://80.lv/articles/tutorial-porting-a-water-ripple-shader-from-unity-to-godot/
- Ocean Waves and Shaders (math primer): https://peterbraden.co.uk/article/ocean-waves-2/
- Godot 4 SCREEN_TEXTURE docs: https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html
