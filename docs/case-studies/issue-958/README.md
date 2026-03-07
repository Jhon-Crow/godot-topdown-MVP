# Case Study: Black Metal Difficulty Mode — White Screen Bug (Issue #958)

## Problem Statement

Issue #958 requested a new "Black Metal" difficulty mode with:
1. Player and enemies have 25% less HP
2. Player moves 25% faster
3. Visual filter: black-and-white + red (red stays red, explosions/bullets/flashes stay vivid, everything else grayscale)

The issue specifically noted: "похожий фильтр использовался в реплее в режиме ghost" (a similar filter was used in the Ghost replay mode).

After initial implementation, the game owner reported that **the entire screen was white** when Black Metal difficulty was selected.

![White screen bug screenshot](./white-screen-screenshot.png)

---

## Timeline of Events

| Time (UTC) | Event |
|------------|-------|
| 2026-03-05 ~17:00 | Initial implementation: Black Metal mode + shader + `BlackMetalEffectsManager` autoload |
| 2026-03-05 18:41 | Session interrupted due to usage limit |
| 2026-03-07 16:29 | Session resumed |
| 2026-03-07 16:40 | Implementation reported complete, PR marked ready |
| 2026-03-07 17:43 | Owner reports: "весь экран на этой сложности белый (ничего не видно)" |
| 2026-03-07 17:44 | New fix session started |
| 2026-03-07 17:48 | Fix attempt 1 (commit `20e501ad`): 1-frame delay via `_process()` counter |
| 2026-03-07 17:50 | PR marked ready again |
| 2026-03-07 18:37 | Owner reports: "всё ещё так же картина" — still white screen |
| 2026-03-07 18:38 | Current session started — deep investigation requested |

---

## Root Cause Analysis

### Root Cause 1: `hint_screen_texture` in `gl_compatibility` Renderer

The `black_metal.gdshader` was implemented using:

```glsl
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
    vec4 original = textureLod(screen_texture, SCREEN_UV, 0.0);
    // ... B&W conversion ...
}
```

In Godot's `gl_compatibility` renderer (OpenGL ES 3.0 / WebGL), `hint_screen_texture` is a **framebuffer copy**. When the shader's `ColorRect` overlay is made visible **before or during scene initialization**, the framebuffer has not yet been rendered and returns an empty/white texture.

**Evidence from codebase:**
- `cinema_effects_manager.gd` (v5.3) explicitly documents this: *"This manager uses an OVERLAY-BASED approach that does NOT use hint_screen_texture. This avoids known bugs in Godot's gl_compatibility renderer that cause white screens."*
- Godot issue tracker: [#79914 — screen_texture glitches in Compatibility mode](https://github.com/godotengine/godot/issues/79914)
- Godot issue tracker: [#66458 — OpenGL Compatibility renderer issues](https://github.com/godotengine/godot/issues/66458)

### Root Cause 2: Black Metal Filter Activates on Scene Load

Unlike other `hint_screen_texture` shaders in the codebase (`hit_effects_manager`, `last_chance_effects_manager`, `power_fantasy_effects_manager`), which are triggered **during gameplay** (after the scene has fully rendered), Black Metal is a **difficulty setting** — meaning the filter must be active from the very first frame when a new level loads.

This is fundamentally different from:
- `HitEffectsManager`: activated on player hit — always mid-gameplay
- `LastChanceEffectsManager`: activated when player nearly dies — always mid-gameplay
- `PowerFantasyEffectsManager`: activated on enemy kill — always mid-gameplay

None of these managers face the scene-load timing problem.

### Root Cause 3: 1-Frame Delay Was Insufficient

The first fix attempt (commit `20e501ad`) deferred visibility by 1 frame using `_process()`:

```gdscript
const ACTIVATION_DELAY_FRAMES: int = 1

func _process(_delta: float) -> void:
    if _waiting_for_activation:
        _activation_frame_counter += 1
        if _activation_frame_counter >= ACTIVATION_DELAY_FRAMES:
            _waiting_for_activation = false
            if _is_active and _filter_rect:
                _filter_rect.visible = true
```

However, **1 frame is not sufficient** for the `gl_compatibility` renderer's framebuffer to be fully populated. The screen texture may still return white on frame 1 in certain platform/driver configurations. Additionally, on scene transitions, the timing of when `_on_tree_changed()` fires relative to the renderer's framebuffer swap can vary.

### Root Cause 4: Fundamental Mismatch with Codebase Architecture

The `cinema_effects_manager` v5.3 was specifically rewritten (from v4.x) to remove `hint_screen_texture` dependency because of exactly this class of bug. The architectural decision was documented explicitly:

```
ARCHITECTURE (v5.3):
This manager uses an OVERLAY-BASED approach that does NOT use hint_screen_texture.
This avoids known bugs in Godot's gl_compatibility renderer that cause white screens.
Instead of sampling the screen and modifying it, we create transparent overlays
that blend on top of the rendered scene using standard alpha blending.
```

The Black Metal filter was implemented following the `ghost_replay.gdshader` pattern (which was itself fixed in issue #543 from a different white screen bug), rather than the `cinema_effects_manager` pattern which correctly handles the scene-load case.

---

## Comparison of Filter Implementations in the Codebase

| Filter | Shader Approach | Activation Timing | White Screen Risk |
|--------|----------------|-------------------|-------------------|
| `cinema_film.gdshader` | **Overlay (no screen_texture)** | Always active (autoload) | **None** ✅ |
| `saturation.gdshader` (hit effects) | `hint_screen_texture` | Mid-gameplay only | Low ✅ |
| `last_chance.gdshader` | `hint_screen_texture` | Mid-gameplay only | Low ✅ |
| `ghost_replay.gdshader` | `hint_screen_texture` | Mid-gameplay only (replay mode) | Low ✅ |
| `black_metal.gdshader` (v1) | `hint_screen_texture` | **Scene load + mid-gameplay** | **High** ❌ |

---

## Proposed Solutions

### Solution A (Recommended): Overlay-Based Approach — Follow `cinema_effects_manager` Pattern

Remove `hint_screen_texture` from `black_metal.gdshader` and implement the desaturation effect using blend modes and overlays, identical to the `cinema_film.gdshader` approach.

**How to achieve B&W effect without screen texture:**
- Apply a **dark semi-transparent grey overlay** using `BLEND_MODE_MUL` (multiply blend mode) on the `CanvasLayer`. A grey overlay with multiply blend desaturates the scene — all colors approach grey when multiplied by a neutral grey.
- Add **vignette** effect (cinema-style — purely generative, no screen read needed)
- Add **film grain** (cinema-style — purely generative noise)
- The "red stays vivid" behavior is achieved architecturally: the Black Metal overlay is at **layer 97**, while blood/hit effects at layers 100+ render ABOVE the overlay and remain in full color

**Pros:**
- Eliminates the white screen bug permanently
- Consistent with codebase's established pattern for always-active filters
- No reliance on platform-specific timing

**Cons:**
- The B&W effect is not pixel-perfect (cannot selectively desaturate individual game-world pixels while preserving red/fire in the world)
- Red/fire preservation works only for effects on higher CanvasLayers, not world-space sprites

### Solution B: Warmed-Up `hint_screen_texture` with Sufficient Delay

Keep `hint_screen_texture` but:
1. Perform warmup in `_ready()` (same as `hit_effects_manager`)
2. Use a timer delay of 200-300ms (not frame count) before showing on scene load
3. Use `SceneTree.idle_frame` signal or a Timer node for reliable timing

**Pros:**
- Preserves the exact B&W + red per-pixel effect
- More accurate to the original design spec

**Cons:**
- Risk of brief white flash on very slow systems/first frame
- Depends on platform-specific timing
- Against the documented codebase pattern for always-active filters

### Solution C: Separate "Active During Gameplay" vs "Scene Load" Handling

Split the filter management:
- During a level load: show a black screen overlay (fade-in) that transitions to B&W filter once scene is fully loaded
- During gameplay: use the screen-texture based filter normally

**Pros:**
- Correct visual for gameplay
- No white flash (replaced by intentional black fade)

**Cons:**
- Complex implementation
- Changes game feel (black fade on every level load in Black Metal mode)

---

## Implemented Fix

**Solution A was implemented** — the overlay-based approach following `cinema_effects_manager` v5.3.

The `black_metal.gdshader` was rewritten to not use `hint_screen_texture`. Instead:
- A **dark, semi-transparent overlay** with adjusted blend mode desaturates the scene
- Vignette and grain effects (like cinema) reinforce the grim B&W aesthetic
- Red/vivid effects show through from higher CanvasLayers (hit effects at layer 100+)

The `black_metal_effects_manager.gd` was updated to remove the now-unnecessary activation delay logic, since overlay-based shaders have no timing dependency.

---

## References

- [Godot #79914 — screen_texture glitches in Compatibility mode](https://github.com/godotengine/godot/issues/79914)
- [Godot #66458 — OpenGL Compatibility renderer issues tracker](https://github.com/godotengine/godot/issues/66458)
- [Godot Forum — Screen_texture in GL_compatibility](https://forum.godotengine.org/t/screen-texture-behaves-strangely-with-gl-compatibility-renderer-but-works-fine-with-forward/93296)
- Case Study issue-543: Ghost Mode Replay White Screen (same class of bug)
- Case Study issue-431: Cinema Effects fixes (documents the overlay approach)
- `scripts/autoload/cinema_effects_manager.gd` — reference implementation (overlay approach)
- `scripts/autoload/hit_effects_manager.gd` — reference implementation (screen_texture + warmup, mid-gameplay only)
