# Issue #452 Case Study: Last Chance Effect Persists After Death/Restart

## Issue Summary
**Title**: fix: the last chance effect doesn't disappear (эффект последнего шанса не исчезает)
**Description**: The visual effect of last chance persists after death/restart

## Timeline of Events

Based on the log file analysis (`game_log_20260203_222415.txt`):

1. **22:24:49**: Player triggers last chance effect during gameplay
   - Visual effects applied (sepia=0.70, brightness=0.60, ripple=0.0080)
   - Saturation boost applied to 6 player sprites

2. **22:24:50**: Scene changes (player dies/restarts)
   - `[LastChance] Resetting all effects (scene change detected)` - Line 2231
   - `[LastChance] Ending last chance effect` - Line 2232
   - `[LastChance] All process modes restored` - Line 2244
   - `[LastChance] Starting visual effects fade-out over 400ms` - Line 2245
   - **CRITICAL**: Scene has already changed, so fade-out operates on stale state

3. **Post-restart**: New scene loads with visual overlay still visible
   - The `_effect_rect` ColorRect is still visible with shader parameters set
   - No log entry for "Visual effects fade-out complete" appears before next scene

## Root Cause Analysis

The bug is in the `reset_effects()` function in `scripts/autoload/last_chance_effects_manager.gd`:

```gdscript
func reset_effects() -> void:
    _log("Resetting all effects (scene change detected)")

    if _is_effect_active:
        _end_last_chance_effect()  # <-- This starts fade-out (sets _is_fading_out = true)

    # Reset fade-out state (Issue #442)
    _is_fading_out = false         # <-- This cancels fade-out but...
    _fade_out_start_time = 0.0

    # ... the _effect_rect is still visible and has shader parameters set!
    # _remove_visual_effects() is NEVER called!
```

### The Problem

1. When scene changes during an active effect, `reset_effects()` is called
2. `_end_last_chance_effect()` is called, which:
   - Sets `_is_effect_active = false`
   - Calls `_unfreeze_time()`
   - Calls `_start_fade_out()` which sets `_is_fading_out = true` and starts fade animation
3. Then `reset_effects()` sets `_is_fading_out = false`, cancelling the fade-out
4. **But the visual overlay (`_effect_rect`) remains visible** with:
   - `sepia_intensity = 0.70`
   - `brightness = 0.60`
   - `ripple_strength = 0.008`
5. `_remove_visual_effects()` is **never** called directly during reset

### The Missing Step

`_remove_visual_effects()` is responsible for:
- Setting `_effect_rect.visible = false`
- Resetting shader parameters to neutral values (sepia=0, brightness=1, ripple=0)
- Restoring original player sprite colors

This function is only called when:
1. `_complete_fade_out()` finishes (which never happens because fade is cancelled)
2. Nowhere else in `reset_effects()`

## Solution

The fix adds a direct call to `_remove_visual_effects()` in `reset_effects()`:

```gdscript
func reset_effects() -> void:
    _log("Resetting all effects (scene change detected)")

    if _is_effect_active:
        _is_effect_active = false
        _unfreeze_time()  # Restore time directly without starting fade

    # Reset fade-out state (Issue #442)
    _is_fading_out = false
    _fade_out_start_time = 0.0

    # CRITICAL FIX (Issue #452): Always remove visual effects immediately
    _remove_visual_effects()

    # ... rest of reset logic
```

This ensures:
1. Visual overlay is hidden immediately on scene change
2. Shader parameters are reset to neutral values
3. No residual effects persist after death/restart

## Files Changed

1. `scripts/autoload/last_chance_effects_manager.gd`
   - Modified `reset_effects()` to call `_remove_visual_effects()` directly
   - No longer relies on fade-out animation completing

2. `tests/unit/test_effects_fade_out.gd`
   - Added new test class `MockLastChanceEffectsManagerWithReset`
   - Added tests for scene-change reset behavior:
     - `test_reset_during_active_effect_clears_visuals()`
     - `test_reset_during_fadeout_clears_visuals_immediately()`
     - `test_reset_clears_effect_active_state()`
     - `test_reset_when_no_effect_active_still_clears_visuals()`

## Testing Verification

The new tests verify:
1. Visual effects are cleared immediately when reset is called during active effect
2. Visual effects are cleared immediately when reset is called during fade-out
3. Effect active state is properly reset
4. Visual cleanup happens even when effect wasn't technically "active"

## Prevention Measures

To prevent similar issues:
1. When implementing time-based cleanup (like fade-out), always ensure there's an immediate fallback
2. Scene change handlers should not rely on gradual animations completing
3. Reset functions should be self-contained and not depend on other async processes
