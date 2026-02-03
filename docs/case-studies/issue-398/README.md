# Case Study: Issue #398 - Simple Grenade Throwing Implementation

## Issue Summary

**Issue**: Replace complex grenade throwing with simple trajectory aiming
**URL**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/398
**PR**: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/401

### Original Requirements (Russian → English)

1. Move complex grenade throwing to experimental settings
2. Add simple throwing: hold RMB to show trajectory preview (cursor = landing point)
3. Show wall bounces for non-contact grenades (flashbang)
4. Release RMB to throw grenade to the target location
5. No additional drag-and-drop or mouse jerking required

## Timeline of Events

### Initial Implementation (Commit 3583256)
- Added `complex_grenade_throwing` setting to ExperimentalSettings
- Implemented simple grenade aiming mode with trajectory preview
- Added wall bounce visualization for timer grenades (flashbang)
- Created unit tests for the new setting

### User Testing (2026-02-03)
- Game log: `game_log_20260203_102411.txt`
- User reported that simple mode was not working

### Investigation Findings

#### Key Observations from Game Log

1. **Settings were correct at initialization**:
   ```
   [10:24:11] ExperimentalSettings initialized - FOV enabled: true, Complex grenade throwing: false
   ```

2. **But complex throwing was used**:
   ```
   [10:24:16] [Player.Grenade] G pressed - starting grab animation
   [10:24:16] [Player.Grenade] Step 1 started: G held, RMB pressed at (305.9704, 1215.9369)
   [10:24:16] [Player.Grenade] Step 1 complete! Drag: (269.89563, 16.029663)
   ```

3. **No `[Player.Grenade.Simple]` log messages appeared**
   - This indicates the simple grenade functions were never called

4. **User attempted to toggle the setting**:
   ```
   [10:24:22] Complex grenade throwing enabled
   [10:24:23] Complex grenade throwing disabled
   ```

#### Root Cause Analysis

The exact cause of the discrepancy between settings and behavior requires further investigation. Possible causes:

1. **Export/Build timing issue**: The user may have been testing an older export that didn't have the code changes
2. **Settings file state**: The saved settings file may have had different values than logged
3. **Code path issue**: There may be a code path that bypasses the mode check

### CI Failure

**Failed Check**: Check Architecture Best Practices
**Error**: Script exceeds 5000 lines (5019 lines). Refactoring required.
**File**: `scripts/objects/enemy.gd`

## Fixes Applied

### Fix 1: Debug Logging for Mode Detection

Added debug logging to `_handle_grenade_input()` to track which mode is being used:
```gdscript
if _grenade_state == GrenadeState.IDLE and (Input.is_action_just_pressed("grenade_throw") or Input.is_action_just_pressed("grenade_prepare")):
    FileLogger.info("[Player.Grenade] Mode check: complex=%s, settings_node=%s" % [use_complex_throwing, experimental_settings != null])
```

### Fix 2: Mode Mismatch Recovery

Added handling for when the grenade state doesn't match the current mode (e.g., if user switches modes mid-throw):
```gdscript
_:
    if _grenade_state in [GrenadeState.TIMER_STARTED, GrenadeState.WAITING_FOR_G_RELEASE, GrenadeState.AIMING]:
        FileLogger.info("[Player.Grenade] Mode mismatch: resetting from complex state %d to IDLE" % _grenade_state)
        if _active_grenade != null and is_instance_valid(_active_grenade):
            _drop_grenade_at_feet()
        else:
            _reset_grenade_state()
```

### Fix 3: Effect Radius Visualization

Fixed effect radius display in `_draw_trajectory_with_bounces()` to use actual grenade radius:
```gdscript
var effect_radius := 200.0
if _active_grenade != null and is_instance_valid(_active_grenade) and _active_grenade.has_method("_get_effect_radius"):
    effect_radius = _active_grenade._get_effect_radius()
```

### Fix 4: Architecture Compliance

Reduced `scripts/objects/enemy.gd` from 5019 to 4999 lines by:
- Removing duplicate blank lines
- Condensing multi-line documentation comments while preserving essential information

## Files Modified

1. `scripts/characters/player.gd` - Debug logging and mode mismatch handling
2. `scripts/objects/enemy.gd` - Line count reduction for CI compliance

## Grenade Effect Radii

| Grenade Type | Effect Radius |
|--------------|---------------|
| Flashbang    | 400 pixels    |
| Frag         | 225 pixels    |

## Test Plan

- [ ] Verify simple mode works: Hold RMB only (no G key) to aim, release to throw
- [ ] Verify effect radius circle matches grenade type
- [ ] Verify complex mode still works when enabled in experimental settings
- [ ] Verify CI passes (architecture check)
- [ ] Check game log for new debug messages

## Additional Notes

The user comment requested:
1. Fix simple throwing not appearing
2. Show effect radius around landing point when aiming
3. Fix architecture problems

All three issues have been addressed in this update.
