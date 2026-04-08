# Case Study: Issue #1732 — Fix Gunslinger Mode Complexity

## Overview

This case study documents the investigation and fixes for Issue #1732, which covers multiple bugs and feature requests for the **Gunslinger** difficulty mode in the top-down shooter game.

## Timeline of Events

### Session 1 (2026-03-29 17:24–17:28)
- Game log: `game_log_20260329_172444.txt`
- Player tested Hard → Gunslinger → Power Fantasy → Gunslinger (multiple switches)
- **16 enemies killed**, **16 kill effects triggered** (100% rate)
- First fix (PR #1733 commit `3d5ccec8`) was under test

### Session 2 (2026-03-29 18:00–18:02)
- Game log: `game_log_20260329_180024.txt`
- Player tested Power Fantasy → Gunslinger (multiple levels)
- **30 enemies killed**, **30 kill effects triggered** (100% rate)
- Enemy glow was still square/rectangular despite the fix
- Player reported: slowdown "not always triggering" (visual always works)
- Player reported: light still rectangular, not bright enough

## Issues Found

### 1. Enemy Glow is Square/Rectangular

**Root cause:** `GradientTexture2D` with `gt.width = 256; gt.height = 128` produces a rectangular texture. When used as a `PointLight2D` texture, the gradient fill radiates from the center of the texture dimensions, so a 256×128 texture produces an elliptical/rectangular appearance, not a true circle.

**Other light sources** in the codebase (e.g. `building_level.gd:_create_warm_light_texture()`, `labyrinth2_level.gd:_create_warm_light_texture()`) use `ImageTexture` with manual pixel-distance falloff using `Vector2.distance_to(center)` — this produces a perfect circle.

**Fix:** Replaced `GradientTexture2D` with `ImageTexture` created via `_create_gunslinger_glow_texture()` that uses circular pixel-distance falloff (`pow(1.0 - t, 2.0)` where `t = dist/radius`). Also increased `energy` from `1.2` to `2.0` and `texture_scale` from `0.8` to `1.6`.

### 2. Kill Slowdown Not Always Triggering

**Root cause investigation:**

From the game logs, `Engine.time_scale` is set to `0.1` in `power_fantasy_effects_manager.gd::_start_effect()`. The `reset_effects()` method is called on scene changes (level transitions) and restores `time_scale = 1.0`.

**Identified edge case:** In `_start_effect()`, when `_is_effect_active` is already `true` (consecutive rapid kills), the code returns early without re-applying `Engine.time_scale = EFFECT_TIME_SCALE`. If `reset_effects()` fires between kills and sets `_is_effect_active = false` and `Engine.time_scale = 1.0`, then a subsequent kill enters the "already active" early-return path (since `_is_effect_active` was just reset to `true` by the current kill) — but this is correctly handled.

**Another edge case:** The scene change detection uses `_on_tree_changed()` which fires every time `current_scene` changes. When killing the last enemy in roguelike rooms, the scene changes almost immediately (within the 600ms effect window). The `reset_effects()` call sets `time_scale = 1.0` while the visual saturation overlay (autoload child, survives scene changes) remains visible.

**Fix applied:** In `_start_effect()`, when `_is_effect_active` is already true, also re-apply `Engine.time_scale = EFFECT_TIME_SCALE` if it was somehow reset (e.g. by `reset_effects()` or another system). This makes the kill effect robust against intermediate resets.

### 3. Player Speed Not Increased in Gunslinger Mode

**Root cause:** `difficulty_manager.gd::get_player_speed_multiplier()` only handled `BLACK_METAL` (1.25x) and defaulted to 1.0x for all other modes. Gunslinger was not added.

**Fix:** Added `Difficulty.GUNSLINGER` case returning `1.5` (50% faster).

## Files Changed

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | Replaced `GradientTexture2D` glow with circular `ImageTexture`; added `_create_gunslinger_glow_texture()` helper |
| `scripts/autoload/difficulty_manager.gd` | Added `GUNSLINGER` → `1.5` to `get_player_speed_multiplier()` |
| `scripts/autoload/power_fantasy_effects_manager.gd` | Re-apply `Engine.time_scale` in `_start_effect()` when already-active effect has stale time_scale |
| `scripts/characters/player.gd` | Updated comment to mention Gunslinger speed boost |
| `Scripts/Objects/Enemy.cs` | Updated stale comment about kill effect duration |
| `tests/unit/test_difficulty_manager.gd` | Added `test_player_speed_multiplier_gunslinger_is_1_5()` test; updated mock |

## References

- Godot `PointLight2D` documentation: light texture should be a white-on-black radial image for correct circular illumination
- `GradientTexture2D.FILL_RADIAL` produces an ellipse based on texture dimensions, not a true circle
- Issue log analysis confirms visual (saturation) always fires; slowdown is affected by scene change timing
