# Issue 1933: Unlock Card Sparks

## Issue

Owner request: add large sparks at the final moment when the player opens an available unlock card by holding LMB in the armory menu. Follow-up feedback asked for more sparks, slower movement, gravity-like downward arcs, and a bright sparkler-style glow.

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

3. Generate large UI spark shards programmatically.
   - Minimal dependencies.
   - Works directly in card-local coordinates.
   - Easy to test by source contract and visual inspection.
   - Can fake glow per spark with local halo/core controls without requiring project-wide bloom settings.

Chosen option: programmatic UI sparks.

## Implementation

`_emit_unlock_sparks(slot)` creates a non-clipping `UnlockSparkLayer` over the card and emits 36 gold/orange sparks from the card center. Each spark is an elongated streak (thin rectangle, aspect ratio 2.5–4.5×) rotated to point along its travel direction, with a bright core and a larger translucent halo for a sparkler glow in UI-space.

Sparks are distributed across an upward fan (~±80° from vertical, like a YouTube like-button burst) rather than a full 360° ring. This gives the effect the characteristic diagonal-left and diagonal-right scatter the owner requested, instead of corn-like jets going straight up.

Motion is split into two tween phases over 0.70–1.05 s: an upward arc peak, then a downward landing. Each spark decelerates as it climbs and accelerates as it falls, simulating gravity. The streak's rotation is fixed to its launch angle so it always looks like a flying spark, not a tumbling blob.

The reveal animation calls `_emit_unlock_sparks(slot)` as the card opening starts, so the sparks appear at the completion moment of the hold-to-unlock interaction.

## Online Research Notes

Godot canvas items support per-item material/blend behavior, and canvas item shaders document additive blending (`blend_add`) for glow-like 2D effects. For this UI case, a local halo/core structure was chosen instead of a shader or renderer-level bloom setting because it is deterministic, needs no scene/project setting changes, and keeps the effect scoped to the unlock card.

## Verification

Added source-level regression tests in `tests/unit/test_armory_menu.gd` to ensure:

- the unlock reveal invokes `_emit_unlock_sparks(slot)`;
- the spark burst uses a defined count and size (36 sparks, max 8 px width);
- sparks can fly outside the card bounds;
- sparks use slower arc motion with downward fall;
- sparks include a glow halo plus bright core;
- sparks are elongated streaks (streak_ratio), not round circles;
- a fan angle constant (UNLOCK_SPARK_ANGLE_CENTER) is defined, so sparks go up-left/up-right rather than all directions.
