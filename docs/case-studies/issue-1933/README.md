# Issue 1933: Unlock Card Sparks

## Issue

Owner request: add sparks at the final moment when the player opens an available unlock card by holding LMB in the armory menu. Follow-up feedback asked for more sparks, slower movement, gravity-like downward arcs, diagonal up-left/up-right travel like YouTube like-button particles, and finally tiny orange 1x1 to 1x3 px sparks with realistic glow similar to the Doom 2016 main menu embers.

## Existing Flow

Unlock cards are handled in `scripts/ui/armory_menu.gd`:

- `_update_progress_overlay()` shows hold progress while LMB is held.
- `_play_unlock_reveal_animation()` runs after the unlock completes.
- The reveal sequence already removes the progress overlay, plays the success sound, flashes the card, scales the icon, and then runs the callback that refreshes the card into its unlocked state.

The best insertion point is the start of `_play_unlock_reveal_animation()`, immediately after creating the reveal flash. That corresponds to the requested “last moment” when the held unlock opens.

## Related Components

The project already has particle-style visual effects such as `scenes/effects/SparksEffect.tscn` and `ImpactEffectsManager.spawn_sparks_effect()`. Those are world-space impact effects. The armory menu is UI-space, so a local Control-based spark burst is more reliable: it stays parented to the card, renders above the card, and does not require world scene managers or coordinate conversion.

## Solution Options

1. Reuse `SparksEffect.tscn` through `ImpactEffectsManager`.
   - Good for world impacts.
   - Risky for armory UI because the manager places effects in world/root scene coordinates.

2. Add a dedicated UI particle scene.
   - Clean separation and designer-friendly.
   - More files and import metadata for a small one-shot effect.

3. Generate tiny UI spark embers programmatically.
   - Minimal dependencies.
   - Works directly in card-local coordinates.
   - Easy to tune by source contract and visual inspection.
   - Can fake glow per spark with local halo/core controls without requiring project-wide bloom settings.

Chosen option: programmatic UI sparks.

## Implementation

`_emit_unlock_sparks(slot)` creates a non-clipping `UnlockSparkLayer` over the card and emits 36 orange sparks from the card center. Each visible spark core is intentionally tiny: 1 px wide and 1-3 px high. A larger low-alpha orange outer glow plus a warmer inner glow surrounds each core so the effect reads as a hot ember/spark instead of a UI rectangle.

Sparks are distributed across an upward fan (~±80° from vertical, like a YouTube like-button burst) rather than a full 360° ring. This gives the effect the characteristic diagonal-left and diagonal-right scatter the owner requested, instead of corn-like jets going straight up.

Motion is split into two tween phases over 0.70–1.05 s: an upward arc peak, then a downward landing. Each spark decelerates as it climbs and accelerates as it falls, simulating gravity. The tiny core may be 1-3 px tall and rotates with travel direction, but the visible mass remains pixel-sized so it resembles Doom 2016-style menu embers rather than long rectangular streaks.

The reveal animation calls `_emit_unlock_sparks(slot)` as the card opening starts, so the sparks appear at the completion moment of the hold-to-unlock interaction.

## Regression log, May 3 2026

Owner feedback after commit `ae9e6f9a` reported that the whole armory screen no longer displayed. The attached runtime log is preserved at `docs/case-studies/issue-1933/logs/game_log_20260503_170820.txt`. The log shows the exported Windows build was running branch `issue-1933-b70261fed6d9` at commit `ae9e6f9ae99f44374fbd60aaf74cd31b41c7d494`, opened the pause-menu armory at `17:09:07`, instantiated `res://scenes/ui/ArmoryMenu.tscn`, and attached `res://scripts/ui/armory_menu.gd`, but then reported `_populate_weapon_grid method NOT found` even though that method exists in source. That points to the script not being fully usable in the exported Godot 4.3 runtime, rather than the armory UI flow being absent.

The newest spark code used `var halo_diameter := max(core_size.x, core_size.y) * rng.randf_range(...)`. In GDScript 4.3, the generic `max()` returns a Variant and `:=` depends on inference. Exported builds can fail script loading or method lookup when parse/type inference hits an unsupported or ambiguous construct. The fix rewrites this to explicit float steps using `maxf()`, a typed `glow_scale`, and a typed `halo_diameter`, keeping the same visual result while avoiding the risky inference path.

## Online Research Notes

Godot canvas items support per-item material/blend behavior, and canvas item shaders document additive blending (`blend_add`) for glow-like 2D effects. For this UI case, a local layered glow/core structure was chosen instead of a shader or renderer-level bloom setting because it is deterministic, needs no scene/project setting changes, and keeps the effect scoped to the unlock card. The latest visual target is closer to small orange Doom 2016 menu embers than large sparkler shards, so the implementation now favors tiny cores with transparent heat halos.

## Verification

Added source-level regression tests in `tests/unit/test_armory_menu.gd` to ensure:

- the unlock reveal invokes `_emit_unlock_sparks(slot)`;
- the spark burst uses a defined count and tiny core size (36 sparks, 1 px wide and 1-3 px high);
- sparks can fly outside the card bounds;
- sparks use slower arc motion with downward fall;
- sparks include outer glow, inner glow, and bright orange core layers;
- sparks are no longer large rectangular streaks;
- a fan angle constant (UNLOCK_SPARK_ANGLE_CENTER) is defined, so sparks go up-left/up-right rather than all directions;
- spark glow sizing avoids Variant `max()` inference and uses explicit float typing so the armory script remains loadable in Godot 4.3 exported builds.
