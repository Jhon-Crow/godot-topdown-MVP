# Issue 1933: Unlock Card Sparks

## Issue

Owner request: add large sparks at the final moment when the player opens an available unlock card by holding LMB in the armory menu.

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

Chosen option: programmatic UI sparks.

## Implementation

`_emit_unlock_sparks(slot)` creates a non-clipping `UnlockSparkLayer` over the card and emits 18 large gold/orange `ColorRect` sparks from the card center. Each spark flies outward 58-126 px, rotates, shrinks, fades, and the layer removes itself after the burst.

The reveal animation calls `_emit_unlock_sparks(slot)` as the card opening starts, so the sparks appear at the completion moment of the hold-to-unlock interaction.

## Verification

Added source-level regression tests in `tests/unit/test_armory_menu.gd` to ensure:

- the unlock reveal invokes `_emit_unlock_sparks(slot)`;
- the spark burst uses a large visible count and size;
- sparks can fly outside the card bounds.
