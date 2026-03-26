# Case Study: Issue #1550 — Update Water on Beach Map

## Issue Summary (Russian → English)

> добавь анимацию волн (с пеной) воде.
> сделай так, чтоб волна прерывалась об игрока/врага (как реальная, логика как и у лучей света).
> так же сделай так, чтоб верхняя стена не попадала в камеру (огранич высоту)

**Translated:**
1. Add wave animation (with foam) to the water.
2. Make waves break on the player/enemy (like real waves — same logic as light rays).
3. Ensure the top wall (WallTop) does not appear in camera view (restrict camera top limit).

---

## Current State Analysis

### Files Involved

| File | Role |
|------|------|
| `scenes/levels/BeachLevel.tscn` | Main beach scene. Has `Water` node at `(1264, 242)` referencing `WaterBody.tscn`. `WallTop` at `(1264, 48)`. |
| `scenes/objects/WaterBody.tscn` | Pre-baked water scene with `WaterVisual` (ColorRect) + `WaterCollision` (CollisionShape2D). |
| `scripts/objects/water_body.gd` | Area2D-based physics, splash effects, blood diffusion. Applies shader at `_ready()`. |
| `scripts/shaders/realistic_water.gdshader` | GLSL shader with animated wave bands and foam. |
| `scripts/effects/water_splash_effect.gd` | Procedural expanding ripple rings when bodies enter water. |
| `scenes/characters/csharp/Player.tscn` | Camera2D node with `limit_top = 0` (shows WallTop at y=48). |
| `scripts/levels/beach_level.gd` | Level coordinator. Has `_setup_water()` hook. |

### Problem 1: Wave Animation with Foam

**Current state:** The shader (`realistic_water.gdshader`) already has animated wave bands and foam/white-caps, implemented in issue #1445. The shader uses:
- `wave_speed`, `wave_frequency`, `wave_amplitude` for primary waves
- `ripple_speed`, `ripple_frequency`, `ripple_amplitude` for secondary ripples
- `foam_threshold`, `foam_sharpness`, `foam_color` for foam/white-cap rendering
- Shore fade at the top edge

However the foam animation is based only on UV position — it doesn't react to obstacles. The waves scroll horizontally uniformly without breaking patterns.

**Improvement needed:** Enhance foam visibility and add animated foam streaks that march toward the shore (top-edge) to simulate incoming surf.

### Problem 2: Waves Breaking on Player/Enemy

**Current state:** The wave shader has no knowledge of player/enemy positions. It renders as a static texture with animated UVs. The splash effect (`water_splash_effect.gd`) is triggered by physics bodies entering water, but waves don't visually "break" around obstacles.

**Light-ray analogy:** In the game, light/visibility is handled via raycasting — rays stop at obstacles. By analogy, wave fronts should stop or deflect when they hit a body.

**Approach:** The most feasible approach for a 2D top-down Godot 4 game is:
- Track obstacle positions (player, enemies) in the water area.
- Pass their UV-space positions to the shader as uniform arrays.
- In the shader, compute distance from each wave line to each obstacle and attenuate/stop wave amplitude within that radius.

Since Godot 4 shaders support `uniform` arrays (limited to ~16 elements), we can pass up to ~8 obstacle positions.

### Problem 3: Camera Top Limit (WallTop Visibility)

**Current state:**
- `WallTop` is a `StaticBody2D` at position `(1264, 48)` — size `(2464, 32)`, so it spans y ∈ [32, 64].
- Camera2D in `Player.tscn` has `limit_top = 0`.
- Viewport (default Godot 4) height is typically 1080px.
- The water starts at y=64 and the sand at y=400.

**Problem:** With `limit_top = 0`, when the player is near the top of the map, the camera can pan to show the area above the water/beach, including the invisible collision wall.

**Fix:** Set `limit_top` to a value that keeps the wall above the viewport. The WallTop is at y ∈ [32, 64]. The camera center is the player position. With a 1080p viewport and no zoom, the camera shows ±540px from center. So `limit_top` should be set to at least `64` (wall bottom) so the camera cannot show above y=64. A cleaner value is `limit_top = 64` or slightly higher (e.g., `80`) to give a small margin.

However, since different levels use different coordinate ranges, this should be handled either:
- Globally in the Player scene (bad: affects all levels)
- Per-level by the beach_level.gd script overriding the camera limit at runtime

**Best approach:** Override camera `limit_top` in `beach_level.gd`'s `_setup_camera()` (called from `_ready()`) to `64` or a more meaningful value like the water top edge (`64`).

---

## Known Techniques and References

### 1. Wave Animation with Foam (2D Godot)
- **GDShader foam patterns**: Use secondary wave functions with different frequencies to create foam bands that march toward shore. See Godot Shaders community examples (godotshaders.com) for "ocean" and "2D water" shaders.
- **Shore foam**: A separate sin-based function with faster speed scrolling toward y=0 (shore) creates convincing foam streaks.

### 2. Wave Breaking on Obstacles (2D Godot Shader)
- **Uniform arrays**: Godot 4 GLSL supports `uniform vec2 obstacle_positions[8]`. Each frame, GDScript passes player/enemy UV coordinates to the shader.
- **Distance-based attenuation**: In the fragment shader, for each obstacle, compute UV-space distance and reduce wave amplitude accordingly (similar to shadow/occlusion logic).
- **Light2D analogy**: The game already uses `LightOccluder2D` nodes for realistic light occlusion. Waves can use a similar "occlusion" concept by masking wave motion in shadow/obstacle zones.
- **Alternative — ShaderMaterial + CPU**: A CPU-side "wave front" simulation updates a texture mask each frame; the shader samples this mask. More accurate but heavier.

### 3. Camera Limit (Godot 4)
- `Camera2D.limit_top` property restricts how high the camera can scroll.
- Per-level override: Call `player.get_node("Camera2D").limit_top = VALUE` from the level script after the player is available.
- Godot docs: https://docs.godotengine.org/en/stable/classes/class_camera2d.html#property-descriptions

---

## Proposed Solutions

### Solution A (Implemented)

1. **Foam enhancement in shader**: Add a third "foam streak" wave function with high frequency, faster speed, and stronger amplitude near y=0 to simulate surf rushing toward shore.

2. **Wave obstacle interruption**:
   - In `water_body.gd`: Track up to 8 bodies inside water, convert their global positions to UV coordinates, and push them to the shader via `ShaderMaterial.set_shader_parameter()` each frame.
   - In the shader: Add `uniform vec2 obstacle_uvs[8]` and `uniform int obstacle_count`. For each pixel, find closest obstacle and reduce wave displacement/foam within a radius.

3. **Camera limit**: In `beach_level.gd`'s `_ready()`, after player setup, retrieve the player's `Camera2D` and set `limit_top` to `64` (bottom of WallTop) so the wall is always off-screen.

### Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| Shader uniform obstacle positions | GPU efficient, no extra nodes | Max 8 obstacles, UV math required |
| CPU wave mask texture | Accurate for many obstacles | Expensive, complex |
| Per-frame script override | Simple, flexible | CPU cost per body per frame |

---

## Key Values

| Parameter | Value |
|-----------|-------|
| WallTop position | `(1264, 48)`, height 32px → bottom edge at y=64 |
| WallBottom position | `(1264, 2080)`, height 32px → top edge at y=2064 |
| WallLeft position | `(48, 1064)`, width 32px → right edge at x=64 |
| WallRight position | `(2480, 1064)`, width 32px → left edge at x=2464 |
| Water node position | `(1264, 242)`, height 356px → top edge at y=64 |
| Water top edge (world) | y = 242 - 178 = 64 |
| Camera limit_top (fix) | 64 (water top edge = WallTop bottom) |
| Camera limit_bottom (fix) | 2064 (WallBottom top edge) |
| Camera limit_left (fix) | 64 (WallLeft right edge) |
| Camera limit_right (fix) | 2464 (WallRight left edge) |
| Viewport height (default 1080p) | 1080px |

---

## Second Feedback (2026-03-26 — owner @Jhon-Crow)

After the shader fix commit (`d07c7491`) was deployed, the owner provided new feedback:

**Original (Russian):**
> хорошо. но сейчас мелкие волны слишком быстрые и непрозрачные (должны выглядеть как неровность воды, более широкие и медленные)
> так же похоже большая волна (редкий градиент) не под тем углом
> так же сделай так, чтоб границы карты (со всех старон) не попадали в поле зрения камеры (огранич)

**Translated:**
1. Small waves are too fast and opaque (should look like water irregularities — wider and slower)
2. Large wave (rare gradient) appears to be at the wrong angle
3. Restrict camera limits on **all sides** (not just top) so map borders never show

**Root causes:**
- `ripple_speed = 1.4` and `ripple_frequency = 18.0` produce fast, busy stripes
- `surf_speed = 1.2` makes the foam streaks animate too quickly
- `surf_intensity = 0.45` and `foam_sharpness = 8.0` make foam too opaque/sharp
- The secondary ripple formula `sin((uv.x + uv.y * 0.4) * ripple_frequency + ...)` creates diagonal stripes that look like "wrong angle" gradients
- Camera limits were only set on the top; the other 3 walls also needed limits

**Game log evidence (game_log_20260326_131128.txt):**
```
[BeachLevel] Water node found OK — visual=true shader=false collision=true pos=(1264, 242)
```
Note: this log was from the build before `d07c7491` was applied. The new shader fix should resolve `shader=false`.

**Fixes applied (second round):**
1. **Shader parameters tuned** — ripple is slower, wider, more transparent; surf foam is gentler
2. **All 4 camera limits** set in `_setup_camera_limits()` using WallTop/Bottom/Left/Right coordinates
