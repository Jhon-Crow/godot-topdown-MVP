# Case Study: Issue #1573 — Update Waves (Performance Lag + Shore Extension)

## Issue Summary (Russian → English)

> когда игрок подходит к волнам - пролаг
> **"When the player approaches the waves — there is a lag/stutter"**
>
> так же сделай чтоб когда градиент (волна) доходит до конца воды - линия воды заходила дальше на сушу.
> **"Also make it so that when the gradient (wave) reaches the edge of the water — the water line extends further onto the land/shore."**

References: [PR #1556](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1556) (previous wave work in Issue #1550)

---

## Game Log Evidence

From `game_log_20260326_141228.txt`:

```
[14:12:30] [WARN] [FPS] Drop detected: 3 fps (threshold: 30)
```

This FPS drop occurs at game start (frame ~60), triggered by the shader warmup for multiple post-processing effects. The player then transitions to BeachLevel at `[14:12:34]`, where:

```
[14:12:35] [INFO] [BeachLevel] Water node found OK — visual=true shader=true collision=true pos=(1264, 242)
```

No subsequent FPS drops were logged during the 80-second session — which means the lag is a **one-time stutter on first entry into the water collision zone**, not a continuous frame-rate issue. This stutter is caused by:

1. **Shader parameter warm-up**: First call to `mat.set_shader_parameter()` on a live material compiles the shader variant and syncs a GPU buffer.
2. **`_process()` activates the moment a body enters the Area2D trigger**: All per-frame work (iteration, GPU uploads) kicks in simultaneously without any gradual ramp-up.
3. **`_cleanup_grenades()` called every frame**: Even when there are no grenades.
4. **`_suppress_bloody_footprints()` called every frame**: Even when no bodies are in water.

---

## Files Involved

| File | Role |
|------|------|
| `scripts/objects/water_body.gd` | Area2D controller — per-frame updates, shader param uploads |
| `scripts/shaders/realistic_water.gdshader` | GLSL canvas shader — wave animation, foam, shore fade |
| `scenes/objects/WaterBody.tscn` | Pre-baked scene: WaterVisual (ColorRect 2400×356) + WaterCollision |
| `scenes/levels/BeachLevel.tscn` | Water node at `(1264, 242)`, Shoreline ColorRect at y=380–440 |

---

## Root Cause Analysis

### Problem 1: Lag When Player Approaches Waves

**Root cause:** `_process()` in `water_body.gd` runs _every game frame_ unconditionally, calling:

```gdscript
func _process(_delta: float) -> void:
    for body in _bodies_in_water.keys():   # empty dict until player enters
        ...
    _suppress_bloody_footprints()          # iterates same dict — always runs
    _obstacle_update_frame += 1
    if _obstacle_update_frame >= OBSTACLE_UPDATE_INTERVAL:
        _obstacle_update_frame = 0
        _update_obstacle_shader_params()   # GPU upload every 3 frames — always runs
    _cleanup_grenades()                    # iterates another dict — always runs
```

**Two sub-problems:**

1. **Unnecessary GPU uploads when no bodies are in water**: `_update_obstacle_shader_params()` calls `mat.set_shader_parameter("obstacle_count", 0)` and `mat.set_shader_parameter("obstacle_uvs", [...])` every 3 frames even when `_bodies_in_water` is empty. The first time parameters are pushed to a live ShaderMaterial can cause a GPU stall on some drivers.

2. **Unnecessary dict iteration every frame**: `_suppress_bloody_footprints()` and `_cleanup_grenades()` iterate their dictionaries even when empty, adding pointless overhead.

**Fix:** Gate all per-frame work behind a check — if `_bodies_in_water.is_empty()`, skip body-dependent updates. Only push obstacle shader params when something has actually changed. Skip grenade cleanup when there are no connected grenades.

### Problem 2: Wave/Gradient Doesn't Extend onto Shore

**Root cause:** The WaterVisual `ColorRect` has a fixed size of `2400×356` pixels. The shore fade in the shader:

```glsl
float shore_fade = smoothstep(0.0, shore_fade_width, uv.y);
alpha *= shore_fade;
```

fades alpha from 0→1 within the top 8% of the ColorRect (`shore_fade_width = 0.08`). This makes the water transparent at its top edge, but the water rectangle itself stops exactly at `y = (242 - 178) = 64`. The `Shoreline` ColorRect in `BeachLevel.tscn` starts at `y = 380`. The `Sand` layer starts at `y = 400`.

So the visual gap is:
- Water top edge: `y = 242 - 178 = 64`
- Shoreline top: `y = 380`
- The water gradient never reaches the sand/shoreline area visually because the ColorRect doesn't extend that far.

**Fix:** Extend the WaterVisual ColorRect upward by increasing `water_height` and shifting the position. Alternatively, increase `shore_fade_width` in the shader so more of the wave pattern is visible at the top edge, and extend the ColorRect downward into the sand area. The simplest approach matching the issue description ("water line extends further onto land") is to increase `water_height` in `WaterBody.tscn` (and in `BeachLevel.tscn`) so the bottom of the water overlaps the shoreline/sand area, and adjust `shore_fade_width` so the gradient blends naturally.

---

## Solution Design

### Fix 1: Performance Optimization (water_body.gd)

- Skip `_update_obstacle_shader_params()` when `_bodies_in_water.is_empty()` — no bodies = no obstacles to push
- Skip `_suppress_bloody_footprints()` when `_bodies_in_water.is_empty()`
- Skip `_cleanup_grenades()` when `_connected_grenades.is_empty()`
- Track a `_obstacle_params_dirty` flag: only re-upload shader params when bodies have moved significantly OR when a body has entered/exited
- Increase `OBSTACLE_UPDATE_INTERVAL` from 3 to 6 frames (bodies rarely move faster than 60px in 3 frames at typical game speeds)

### Fix 2: Wave Extends onto Shore (WaterBody.tscn + BeachLevel.tscn + shader)

The Water node in BeachLevel is at `position = Vector2(1264, 242)` with `water_height = 356`. This places the water rectangle from y=64 (top) to y=420 (bottom: 242 + 178 = 420). The Sand starts at y=400. So the water _already_ slightly overlaps the sand at the bottom, but the player/camera approaches from the sand (y>400) toward the water.

Looking at it from the player's perspective approaching from below (y > 400 in screen space going upward), the "shore edge" is where water meets sand. The request is for waves (the animated foam streaks traveling toward shore) to visually wash a bit onto the sand area.

**Approach:** Increase `water_height` to extend the ColorRect further into the sand area (e.g., add 60px to the bottom), and increase `shore_fade_width` in the shader so the wave gradient blends over a wider zone, giving the impression of wave wash-over.

**Specifically:**
- In `WaterBody.tscn` and `BeachLevel.tscn`: increase `water_height` from 356 to 420 (extend 64px into sand)
- In `realistic_water.gdshader`: increase default `shore_fade_width` from `0.08` to `0.12` so the top-edge fade is more gradual, and extend the surf foam visibility near y=1 (bottom edge) by adding a bottom shore fade that lets foam wash onto the extended area

**Wait** — re-reading the scene: Water node is at `(1264, 242)`, and the water visual is positioned at `(-water_width/2, -water_height/2)` relative to the node, so:
- Top of water: `242 - 356/2 = 242 - 178 = 64`
- Bottom of water: `242 + 356/2 = 242 + 178 = 420`

The Sand ColorRect is at y=400–2064. So the bottom of the water (y=420) already overlaps the sand by 20px.

The Shore ColorRect is at y=380–440 (60px tall).

The "wave reaching shore" means: when surf bands travel from deep (y=1 in UV) toward shallow (y=0 in UV / top of water in world space), the wave bands should visually overshoot slightly onto the sand. The water visual needs to overlap the sand more at the bottom — but since the Water node is at the TOP of the level (y=242), and sand is below (y>400), extending the water ColorRect downward (increasing water_height) will make waves appear to lap onto the sand.

**Final approach:**
- Increase `water_height` from 356 to 420 in both the scene and script (extends 32px further into sand at the bottom)
- Add a `bottom_fade_width` uniform to the shader so the bottom edge of the extended water fades out smoothly (transparent at y=1, visible foam wash in the last 15% of UV)
- This creates a "wet sand" look where foam washes onto the beach

---

## Known Patterns / References

- **Godot shader uniform upload cost**: `set_shader_parameter()` triggers a GPU uniform buffer update. In Godot 4.x, this is batched per draw call but still triggers a material state dirty flag each call. Minimizing calls when values haven't changed is a standard optimization.
- **Shore wash / wave runup**: Common 2D water shader technique is to extend the water rect past the shoreline and use alpha fade. Used in games like Stardew Valley, Terraria, and various Godot 2D demos.
- **Dirty-flag pattern**: Standard game engine pattern — only update GPU state when the CPU-side data changes.

---

## Implementation Notes

See:
- `scripts/objects/water_body.gd` — performance fixes
- `scripts/shaders/realistic_water.gdshader` — bottom fade for wave wash
- `scenes/objects/WaterBody.tscn` — water_height update
- `scenes/levels/BeachLevel.tscn` — water_height update
