# Case Study: Issue #1253 — Sound Visibility Toggle in Experimental Menu

## Summary

**Request (Russian):** "добавь в экспериментал переключатель отображения звука (для дэбага слышимости стрельбы). и реализуй"

**Translation:** "Add a sound display toggle to the experimental menu (for debugging shooting audibility). And implement it."

**Goal:** Add a toggle in the Experimental menu that, when enabled, renders a visual overlay of sound propagation circles when the player or enemies fire. This lets developers verify that gunshots are hearable at the correct radius and that the propagation system is working.

## Context

### Sound Propagation System

The game has a `SoundPropagation` autoload (`scripts/autoload/sound_propagation.gd`) that handles gameplay-relevant sound propagation — gunshots alerting nearby enemies. It is separate from `AudioManager` (actual audio playback).

Key propagation distances (pixels):
- `GUNSHOT`: 1468.6 px (≈ viewport diagonal)
- `EXPLOSION`: 2200 px
- `RELOAD`: 900 px
- `EMPTY_CLICK`: 600 px
- `RELOAD_COMPLETE`: 900 px
- `GRENADE_LANDING`: 112 px
- `CASING_KICK`: 900 px

When `emit_sound()` is called, it notifies all registered `Node2D` listeners (`on_sound_heard` / `on_sound_heard_with_intensity`) that are within the propagation radius.

### Existing Debug Infrastructure

- `ExperimentalSettings` autoload persists all experimental toggles to `user://experimental_settings.cfg`
- `ExperimentalMenu` scene/script provides the UI (CheckButton rows in a VBoxContainer inside a ScrollContainer)
- Pattern for each toggle: add variable to `ExperimentalSettings`, add getter/setter, save/load in cfg, add UI row to `.tscn`, wire up in `experimental_menu.gd`

### NavMesh Visible Toggle (reference implementation, Issue #1187)

The most recent analogous feature was the "Show Nav Mesh" toggle (#1187). It:
1. Added `nav_mesh_visible_enabled: bool = false` to `ExperimentalSettings`
2. Added `set_nav_mesh_visible_enabled` / `is_nav_mesh_visible_enabled`
3. Added a `NavMeshMonitor` autoload that renders a custom overlay
4. Added the UI row to `ExperimentalMenu.tscn` + wired in `experimental_menu.gd`

## Solution Design

### Approach: `SoundVisualizer` Autoload

Add a new autoload `SoundVisualizer` (`scripts/autoload/sound_visualizer.gd`) that:
1. Listens to a signal emitted by `SoundPropagation` when a sound is emitted
2. When enabled, draws an expanding ring circle at the sound origin showing the propagation radius
3. Uses a `CanvasLayer` + `Node2D` to draw directly in world space
4. Each ring fades out over ~1.5 seconds to avoid cluttering the screen

### Signal Hook in SoundPropagation

`SoundPropagation.emit_sound()` now emits a `sound_emitted(sound_type, position, source_type, propagation_distance)` signal. `SoundVisualizer` connects to this signal and renders the rings.

### Visual Design

- Circle outline at the propagation radius (gunshot: ~1468 px)
- Color-coded by source type: blue = player, red = enemy, grey = neutral
- Expanding ring animation from center → full radius over 0.5s, then hold + fade for 1.0s
- Thin inner dot at the sound origin
- Text label showing sound type (GUNSHOT, RELOAD, etc.)

### Files Changed

| File | Change |
|------|--------|
| `scripts/autoload/sound_propagation.gd` | Added `sound_emitted` signal, emitted in `emit_sound()` |
| `scripts/autoload/sound_visualizer.gd` | **New** — draws propagation circles |
| `scripts/autoload/experimental_settings.gd` | Added `sound_visualizer_enabled` variable + getter/setter + save/load |
| `scripts/ui/experimental_menu.gd` | Added `@onready` ref, signal connection, UI update, toggle handler |
| `scenes/ui/ExperimentalMenu.tscn` | Added `SoundVisualizerContainer` row + description label |
| `project.godot` | Registered `SoundVisualizer` autoload |

## Alternative Approaches Considered

### Alternative 1: Mute Audio Bus

Muting the `Effects` or `Master` audio bus would silence all sounds — not visual debugging of propagation. Does not address "display" of sound.

### Alternative 2: Extend SoundPropagation with debug drawing

Could draw directly in `SoundPropagation` by adding a `CanvasLayer` child. Rejected: autoloads should not own rendering nodes. Separate `SoundVisualizer` follows the pattern established by `NavMeshMonitor`.

### Alternative 3: Plugin (e.g., Godot debug draw plugin)

Third-party plugins like `godot_debug_draw` (github.com/Zylann/godot_debug_draw) can draw shapes in 2D/3D. Rejected: project already has a working pattern for custom overlays; adding a dependency is unnecessary overhead.

## Implementation Notes

- Default: disabled (`sound_visualizer_enabled = false`)
- Works in both debug and release builds (uses standard `draw_*` APIs)
- Only draws when `ExperimentalSettings.is_sound_visualizer_enabled()` returns `true`
- Rings are cleaned up automatically after fade-out; no persistent memory leak
- Sound type labels use the enum key names from `SoundType` for readability
