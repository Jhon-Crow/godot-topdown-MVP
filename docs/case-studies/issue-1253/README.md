# Issue #1253 — Sound Visibility Toggle

**Request:** Add a sound display/visualization toggle to the Experimental menu for debugging shooting audibility.

See [case-study.md](case-study.md) for the full analysis and solution design.

## Key Files

- `scripts/autoload/sound_propagation.gd` — emits `sound_emitted` signal
- `scripts/autoload/sound_visualizer.gd` — new overlay renderer
- `scripts/autoload/experimental_settings.gd` — `sound_visualizer_enabled` toggle
- `scripts/ui/experimental_menu.gd` — UI wiring
- `scenes/ui/ExperimentalMenu.tscn` — new UI row
- `project.godot` — SoundVisualizer autoload registration
