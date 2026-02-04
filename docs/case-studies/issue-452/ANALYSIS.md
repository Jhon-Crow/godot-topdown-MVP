# Case Study: Issue #452 - Last Chance Visual Effect Persists After Death/Restart

## Summary

Visual effects from the "penultimate hit" effect (saturation + contrast overlay in normal mode) and "last chance" effect (sepia + ripple overlay in hard mode) persist after player death and scene restart.

## Timeline Reconstruction

From `game_log_20260203_224400.txt`:

### Session 1: Hard Mode (22:45:40 - 22:45:46)

1. **22:45:39** - Player damaged to 1 HP
2. **22:45:40** - LastChance effect triggered (sepia/brightness/ripple)
3. **22:45:46** - Effect duration expired, fade-out started
4. **22:45:46** - Player died during fade-out (grenade explosion)
5. **22:45:46** - Fade-out completed
6. **22:45:46** - Scene changed (restart), `reset_effects()` called
7. Result: Effects cleared correctly

### Session 2: Normal Mode (22:46:10 - 22:46:11)

1. **22:46:10** - Player damaged to 1 HP
2. **22:46:10** - PenultimateHit effect triggered (saturation/contrast)
3. **22:46:11** - Scene changed (player used quick restart)
4. **22:46:11** - `reset_effects()` called, which called `_end_penultimate_effect()`
5. **22:46:11** - `_end_penultimate_effect()` started fade-out animation
6. **22:46:11** - `reset_effects()` cancelled fade-out (`_is_fading_out = false`)
7. **BUG**: `_remove_visual_effects()` was never called!
8. Result: Saturation overlay remained visible after restart

## Root Cause Analysis

### The Bug

In `PenultimateHitEffectsManager.reset_effects()`:

```gdscript
func reset_effects() -> void:
    _log("Resetting all effects (scene change detected)")
    _end_penultimate_effect()  # This starts a fade-out animation!

    # Reset fade-out state (Issue #442)
    _is_fading_out = false  # This cancels the fade-out...
    _fade_out_start_time = 0.0

    # ...but _remove_visual_effects() is never called!
```

The sequence of events:

1. `_end_penultimate_effect()` is called
2. It sets `_is_effect_active = false`
3. It restores `Engine.time_scale = 1.0`
4. It calls `_start_fade_out()` which sets `_is_fading_out = true`
5. Back in `reset_effects()`, we set `_is_fading_out = false`
6. **The overlay is never hidden** because `_remove_visual_effects()` is only called when fade-out completes

### Why It Worked in Hard Mode

The `LastChanceEffectsManager` already had this fix applied in the initial PR:

```gdscript
func reset_effects() -> void:
    # ... state reset ...

    # CRITICAL FIX (Issue #452): Always remove visual effects immediately
    _remove_visual_effects()  # <-- This was missing in PenultimateHit!
```

## The Fix

Add a direct call to `_remove_visual_effects()` in `PenultimateHitEffectsManager.reset_effects()`:

```gdscript
func reset_effects() -> void:
    _log("Resetting all effects (scene change detected)")

    if _is_effect_active:
        _is_effect_active = false
        Engine.time_scale = 1.0

    _is_fading_out = false
    _fade_out_start_time = 0.0

    # CRITICAL FIX (Issue #452): Always remove visual effects immediately
    _remove_visual_effects()

    _player = null
    _connected_to_player = false
    _player_original_colors.clear()
```

## Lessons Learned

1. **Consistency is key**: When fixing a bug in one manager, check if similar managers have the same issue.
2. **Fade-out animations need cleanup paths**: If a fade-out can be interrupted (scene change, death, etc.), ensure the cleanup code is always called.
3. **State machine complexity**: The interaction between `_is_effect_active`, `_is_fading_out`, and `_remove_visual_effects()` created a subtle bug where cancelling the fade-out prevented cleanup.

## Files Changed

- `scripts/autoload/penultimate_hit_effects_manager.gd` - Added `_remove_visual_effects()` call in `reset_effects()`

## Test Cases

1. Normal mode: Take damage to 1 HP, then restart (Q key) during effect - effect should clear
2. Normal mode: Take damage to 1 HP, wait for effect to end, then restart - effect should be cleared
3. Normal mode: Take damage to 1 HP, die, restart - effect should clear
4. Hard mode: All above cases should also work for the LastChance effect
