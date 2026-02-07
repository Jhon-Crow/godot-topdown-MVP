# Case Study: Issue #543 — Ghost Mode Replay Shows White Screen

## Problem

When watching a replay in Ghost mode, the screen appeared white/blank instead of
showing the expected red/black/white stylized filter (Sin City / MadWorld aesthetic).

The issue was reported as:
> должен показывать повтор в чёрно-красно-белом виде
> (should show replay in black-red-white view)

## Root Cause Analysis

### The Shader Bug

The `ghost_replay.gdshader` was written as a standard `canvas_item` shader that
sampled from `TEXTURE` using `UV` coordinates:

```glsl
vec4 original = texture(TEXTURE, UV);
```

However, this shader was applied to a fullscreen `ColorRect` overlay created in
`ReplayManager.cs` → `CreateGhostFilter()`. On a `ColorRect`, the built-in
`TEXTURE` variable refers to the rect's own texture — which is essentially empty
(white/undefined). The shader therefore processed white pixels, producing a
white screen output.

### The Failed Workaround

The C# code in `CreateGhostFilter()` included comments acknowledging the issue:

```csharp
// The shader reads from TEXTURE, but for a ColorRect overlay we need
// screen_texture. Since the ghost_replay shader uses TEXTURE (which is
// the rect's own texture), we use a SubViewport approach instead.
```

Instead of fixing the shader, a modulation-based fallback was added via
`ApplyGhostColorToWorld()`, which tinted the Environment and TileMap nodes with
dark modulate colors. But this approach:

1. Did not produce the intended red/black/white aesthetic
2. Left the broken shader `ColorRect` in place (producing white)
3. The transparent `ColorRect` (`Color(0,0,0,0)`) with the broken shader material
   still rendered white/undefined pixels from the empty `TEXTURE`

### Why Other Shaders Worked

The project already had a working screen-reading shader — `saturation.gdshader` —
used by `HitEffectsManager`, `PenultimateHitEffectsManager`, and
`PowerFantasyEffectsManager`. It correctly used:

```glsl
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// ...
vec4 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0);
```

The `cinema_film.gdshader` deliberately avoids `screen_texture` due to known
`gl_compatibility` renderer bugs and uses an overlay-based approach instead. But
the `saturation.gdshader` demonstrates that `hint_screen_texture` with `textureLod`
works reliably in this project's `gl_compatibility` renderer configuration.

## Fix

### 1. Updated `ghost_replay.gdshader`

Changed from reading the rect's own texture to reading the rendered screen:

- **Before:** `texture(TEXTURE, UV)` — reads empty/white ColorRect texture
- **After:** `textureLod(screen_texture, SCREEN_UV, 0.0)` — reads the actual
  rendered scene

Added `uniform sampler2D screen_texture : hint_screen_texture, repeat_disable,
filter_nearest;` following the same pattern as `saturation.gdshader`.

Set `COLOR.a = 1.0` to ensure full opacity (the shader fully replaces the screen
content with the filtered version).

### 2. Simplified `CreateGhostFilter()` in `ReplayManager.cs`

- Removed the broken `ApplyGhostColorToWorld()` method and its dark modulation
  tinting of Environment/TileMap nodes
- Removed the transparent `ColorRect.Color` hack
- The shader now handles all visual filtering via screen-space post-processing
- Simplified `RestoreWorldColors()` to a no-op since no world modulation is
  applied anymore

## References

- [Godot 4 Custom Post-Processing](https://docs.godotengine.org/en/stable/tutorials/shaders/custom_postprocessing.html)
- [Godot 4 Screen-Reading Shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html)
- GitHub Issue godotengine/godot#79914 — screen_texture glitches in Compatibility mode
- PR #421 — Original Ghost/Memory replay modes implementation

## Files Changed

- `scripts/shaders/ghost_replay.gdshader` — Fixed screen texture sampling
- `Scripts/Autoload/ReplayManager.cs` — Simplified ghost filter creation
