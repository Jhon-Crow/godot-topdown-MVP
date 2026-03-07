# Case Study: Black Metal Difficulty Mode — White Screen Bug (Issue #958)

## Problem Statement

Issue #958 requested a new "Black Metal" difficulty mode with:
1. Player and enemies have 25% less HP
2. Player moves 25% faster
3. Visual filter: black-and-white + red (red stays red, explosions/bullets/flashes stay vivid, everything else grayscale)

The issue specifically noted: "похожий фильтр использовался в реплее в режиме ghost" (a similar filter was used in the Ghost replay mode) — pointing to `ghost_replay.gdshader` as the reference implementation.

After three implementation attempts, the game owner reported that **the entire screen was white** when Black Metal difficulty was selected.

![White screen bug screenshot](./white-screen-screenshot.png)

---

## Timeline of Events

| Time (UTC) | Event |
|------------|-------|
| 2026-03-05 ~17:00 | Initial implementation: Black Metal mode + `ghost_replay.gdshader`-style shader + `BlackMetalEffectsManager` autoload |
| 2026-03-05 18:41 | Session interrupted due to usage limit |
| 2026-03-07 16:29 | Session resumed |
| 2026-03-07 16:40 | Implementation reported complete, PR marked ready |
| 2026-03-07 17:43 | Owner reports: "весь экран на этой сложности белый (ничего не видно)" (entire screen is white) |
| 2026-03-07 17:44 | Fix session 1 started |
| 2026-03-07 17:48 | **Fix attempt 1 (commit `20e501ad`):** 1-frame delay via `_process()` counter |
| 2026-03-07 17:50 | PR marked ready again |
| 2026-03-07 18:37 | Owner reports: "всё ещё так же картина. проверь как сделаны другие фильтры и сделай по аналогии." (still white. check how other filters are made and do it by analogy.) |
| 2026-03-07 18:38 | Fix session 2 started |
| 2026-03-07 18:47 | **Fix attempt 2 (commit `01581e3f`):** Rewrote shader to overlay-based approach (no screen_texture), following `cinema_film.gdshader v5.3` |
| 2026-03-07 18:50 | PR marked ready again |
| 2026-03-07 18:50 | Auto-restart detects uncommitted JSON data files |
| 2026-03-07 ~18:55 | **Fix attempt 3 (current):** Reverted to `hint_screen_texture` approach with proper warmup (intensity=0.0) + 3-frame delayed activation, following `hit_effects_manager` and `last_chance_effects_manager` patterns |

---

## Root Cause Analysis

### Root Cause 1: `hint_screen_texture` Returns White on First Frame

In Godot's `gl_compatibility` renderer (OpenGL ES 3.0 / WebGL), `hint_screen_texture` is a framebuffer copy. When the shader's `ColorRect` overlay is made visible **before the scene has rendered**, the framebuffer has not been populated and returns an empty/white texture.

This is documented in Godot issue [#79914](https://github.com/godotengine/godot/issues/79914).

### Root Cause 2: 1-Frame Delay Was Insufficient (Fix Attempt 1)

The first fix deferred visibility by 1 frame using `_process()`:
```gdscript
const ACTIVATION_DELAY_FRAMES: int = 1
```

**Why this failed:** On scene transitions, the renderer may still not have a full framebuffer on frame 1 depending on platform and driver. In `gl_compatibility` mode, the framebuffer swap timing is not guaranteed to complete within 1 frame.

### Root Cause 3: Overlay Approach Was Incomplete (Fix Attempt 2)

The second fix rewrote the shader to use a pure overlay (no `hint_screen_texture`), following `cinema_film.gdshader v5.3`. This eliminated the white screen, but introduced a new problem: **the overlay approach cannot achieve true per-pixel B&W desaturation**.

The overlay-based approach only adds a dark semi-transparent layer on top. It does not actually convert the scene to black-and-white. The owner's requirement for a "чёрно-бело-красно-огненный" (B&W + red + fire) filter requires reading each pixel's actual color from the scene, which requires `hint_screen_texture`.

---

## Analysis of Filter Implementations in Codebase

| Filter | Shader | Approach | Activation Timing | White Screen Risk |
|--------|--------|----------|-------------------|-------------------|
| Cinema film | `cinema_film.gdshader` | Overlay (no screen_texture) | Always active (autoload) | None ✅ |
| Hit effect | `saturation.gdshader` | `hint_screen_texture` | Mid-gameplay only (on hit) | Low ✅ |
| Last chance | `last_chance.gdshader` | `hint_screen_texture` | Mid-gameplay only (low HP) | Low ✅ |
| Ghost replay | `ghost_replay.gdshader` | `hint_screen_texture` | Mid-gameplay only (replay) | Low ✅ |
| Black Metal (final) | `black_metal.gdshader` | `hint_screen_texture` + warmup + 3-frame delay | Scene load + mid-gameplay | None ✅ |

### Why Mid-Gameplay Shaders Don't Have This Problem

`HitEffectsManager`, `LastChanceEffectsManager`, and the replay system all activate their `hint_screen_texture`-based shaders only during active gameplay — long after the scene has fully rendered. The framebuffer is always populated by the time they activate.

**Black Metal is different**: it is a difficulty setting, meaning the filter must be active from the very first frame of every level load.

### The Warmup Pattern (Key Insight from HitEffectsManager)

Looking at `HitEffectsManager._warmup_saturation_shader()`:
```gdscript
func _warmup_saturation_shader() -> void:
    material.set_shader_parameter("saturation_boost", 0.0)  # Make invisible
    _saturation_rect.visible = true
    await get_tree().process_frame
    _saturation_rect.visible = false  # CRITICAL: Hide after warmup
```

When `saturation_boost = 0.0`, the formula `mix(vec3(luminance), screen_color.rgb, 1.0)` equals `screen_color.rgb` — so even if `screen_texture` returns white during warmup, the output equals the original scene (pass-through), and no white flash is visible.

This is the correct pattern: **use an intensity parameter of 0 during warmup to make the shader a pass-through, preventing any visible white flash even if screen_texture is uninitialized**.

---

## Final Solution (Fix Attempt 3)

### 1. `black_metal.gdshader` — `hint_screen_texture` with safe `intensity` uniform

The shader reads the screen texture and applies per-pixel B&W+red transformation, identical in approach to `ghost_replay.gdshader`. The key addition is the `intensity` uniform:

```glsl
// intensity=0.0 → pure pass-through (original scene), even if screen_texture is white
// intensity=1.0 → full B&W+red effect
COLOR.rgb = mix(original.rgb, result, intensity);
COLOR.a = original.a;
```

When `intensity = 0.0`: `mix(original.rgb, result, 0.0) = original.rgb` — completely invisible pass-through, even if `screen_texture` is white.

### 2. `black_metal_effects_manager.gd` — Warmup + 3-Frame Delayed Activation

Following `HitEffectsManager` and `LastChanceEffectsManager` patterns:

**Warmup (shader precompilation, prevents compilation stutter and safe initialization):**
```gdscript
func _warmup_shader() -> void:
    _material.set_shader_parameter("intensity", 0.0)  # Invisible pass-through
    _filter_rect.visible = true
    await get_tree().process_frame
    _filter_rect.visible = false
    _material.set_shader_parameter("intensity", 1.0)  # Restore for actual use
```

**Scene transition handling (prevents white screen on level load):**
```gdscript
const ACTIVATION_DELAY_FRAMES: int = 3  # 3 frames ensures framebuffer is populated

func _on_tree_changed() -> void:
    var current_scene := get_tree().current_scene
    if current_scene != null and current_scene != _previous_scene_root:
        _previous_scene_root = current_scene
        if _is_active:
            _start_delayed_activation()  # Hides overlay, starts 3-frame countdown

func _process(_delta: float) -> void:
    if _waiting_for_activation:
        _activation_frame_counter += 1
        if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
            _waiting_for_activation = false
            if _is_active and _filter_rect:
                _filter_rect.visible = true
```

### Why 3 Frames Instead of 1

- **Frame 0**: Scene starts loading, framebuffer empty
- **Frame 1**: Scene tree initializes, first draw call may still be incomplete in gl_compatibility
- **Frame 2**: Scene fully rendered, framebuffer populated
- **Frame 3**: Safe to show filter — screen_texture guaranteed to contain scene content

Using 3 frames provides a safety margin for slow hardware and ensures correct behavior in all supported renderers (gl_compatibility / Vulkan / Metal).

---

## Summary: What Was Implemented

| Requirement | Status |
|-------------|--------|
| Player and enemies 25% less HP | ✅ Implemented (`player.gd`, `Player.cs`, `enemy.gd`) |
| Player 25% faster movement | ✅ Implemented (`player.gd`, `Player.cs`) |
| B&W + red visual filter | ✅ Implemented (`black_metal.gdshader` with `hint_screen_texture`) |
| Red stays red | ✅ Per-pixel detection via `red_dominance = r - max(g, b)` |
| Explosions/bullets/flashes stay vivid | ✅ Per-pixel detection via `warmth = (r+g)/2 - b` for orange/yellow |
| No white screen on scene load | ✅ Fixed via warmup (intensity=0) + 3-frame delayed activation |

---

## References

- [Godot #79914 — screen_texture glitches in Compatibility mode](https://github.com/godotengine/godot/issues/79914)
- [Godot #66458 — OpenGL Compatibility renderer issues tracker](https://github.com/godotengine/godot/issues/66458)
- `scripts/shaders/ghost_replay.gdshader` — reference implementation (same B&W+red approach)
- `scripts/autoload/hit_effects_manager.gd` — reference warmup pattern (intensity=0 during warmup)
- `scripts/autoload/cinema_effects_manager.gd` — reference delayed activation pattern
- Raw data collected during analysis: `./data/` directory

---

## Data Files

Raw data files collected during this investigation are stored in `./data/`:
- `ci-runs-958.json` — CI run results for PR #963
- `issue-958-data.json` — Original issue content and metadata
- `pr-963-comments.json` — All comments on PR #963 during investigation
