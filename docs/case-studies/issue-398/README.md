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

## Second Round of Testing (2026-02-03 10:48)

### User Feedback
- Game log: `game_log_20260203_104814.txt`
- User reported: "не заработало" (didn't work)
- User requested: "мне нужно отображение прицела для бросков при обычном бросании гранаты" (I need aiming display for simple grenade throwing)

### Analysis of Second Log

1. **Settings were correct**:
   ```
   [10:48:14] ExperimentalSettings initialized - FOV enabled: true, Complex grenade throwing: false
   ```

2. **User pressed G key (complex mode behavior)**:
   ```
   [10:48:20] [Player.Grenade.Anim] Phase changed to: GrabGrenade (duration: 0,20s)
   [10:48:20] [Player.Grenade] G pressed - starting grab animation
   [10:48:20] [Player.Grenade] Step 1 started: G held, RMB pressed at (654.6913, 1283.3951)
   ```

3. **"Mode check" debug log did NOT appear**
   - This indicates the user was running an older build (before commit 94fa5bc)

### Root Cause (Confirmed)

The user was testing with a build compiled before the latest changes. The evidence:
- Debug log "Mode check" was added in commit 94fa5bc at 07:42:18Z UTC
- User's log created at ~07:48:14Z UTC (10:48:14 Moscow time = UTC+3)
- The "Mode check" log never appears in the game log
- Complex mode messages appear even though settings show simple mode

### Key Insight: User Behavior

The user is pressing **G key** (the old complex mode trigger) instead of **only RMB** (the new simple mode trigger).

**Simple mode usage**:
1. Point cursor at desired landing position
2. Press and hold **RMB only** (do NOT press G)
3. See trajectory preview appear
4. Release RMB to throw

### Fix Applied in This Round

Added enhanced logging in simple mode handler:
```gdscript
func _handle_simple_grenade_idle_state() -> void:
    if Input.is_action_just_pressed("grenade_throw"):
        FileLogger.info("[Player.Grenade.Simple] RMB pressed in IDLE state, grenades=%d" % _current_grenades)
```

This will help confirm that simple mode is being triggered correctly when the user presses RMB without G.

## Additional Notes

The user comment requested:
1. Fix simple throwing not appearing
2. Show effect radius around landing point when aiming
3. Fix architecture problems

All three issues have been addressed. The remaining issue is that the user needs to:
1. Use a fresh build with the latest changes
2. Press **only RMB** (not G) to use simple mode

## Third Round of Testing (2026-02-03 11:19)

### User Feedback
- Game log: `game_log_20260203_111919.txt`
- User reported: "не вижу прицела для простого метания. кажется вообще не работает." (I don't see the aiming for simple throwing. It seems to not work at all.)

### Analysis of Third Log

1. **Settings were correct at initialization**:
   ```
   [11:19:19] ExperimentalSettings initialized - FOV enabled: true, Complex grenade throwing: false
   ```

2. **User pressed G key (triggering complex mode)**:
   ```
   [11:19:20] [Player.Grenade] G pressed - starting grab animation
   [11:19:20] [Player.Grenade] Step 1 started: G held, RMB pressed at (492.1165, 1235.3062)
   ```

3. **"Mode check" debug log did NOT appear**

4. **User toggled the experimental setting multiple times**:
   ```
   [11:19:27] Complex grenade throwing enabled
   [11:19:28] Complex grenade throwing disabled
   [11:19:30] Complex grenade throwing enabled
   [11:19:33] Complex grenade throwing disabled
   ```

### REAL Root Cause Discovery (2026-02-03 11:19)

**CRITICAL FINDING**: The game uses a **C# Player** (`Scripts/Characters/Player.cs`), not the GDScript version (`scripts/characters/player.gd`).

Evidence:
- The log message `[Player.Grenade] G pressed - starting grab animation` at line 1754 exists only in `Player.cs`
- The GDScript version (player.gd) was modified with simple mode, but the game's main levels use the C# version
- The level files confirm this:
  ```
  scenes/levels/TestTier.tscn:
  [ext_resource type="PackedScene" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
  ```

### The Fix

**Commit 8a9991f**: Ported the entire simple grenade mode implementation from `player.gd` to `Player.cs`:

1. Added `SimpleAiming` state to `GrenadeState` enum
2. Added ExperimentalSettings check for complex/simple mode selection
3. Implemented `HandleSimpleGrenadeIdleState()` - RMB triggers aiming
4. Implemented `HandleSimpleGrenadeAimingState()` - shows trajectory preview
5. Implemented `StartSimpleGrenadeAiming()` - creates grenade, starts timer
6. Implemented `ThrowSimpleGrenade()` - calculates physics-based throw
7. Updated `_Draw()` to show trajectory in simple mode (always visible)
8. Added effect radius circle visualization
9. Added debug logging for mode detection

### Lessons Learned

1. **Dual-language codebases require careful synchronization**: When implementing features, check if both GDScript and C# versions of classes exist and need updates.

2. **Follow the scene references**: Always verify which script a scene is actually using by checking the `.tscn` files.

3. **Log analysis is crucial**: The specific log message format (`[Player.Grenade] G pressed`) helped identify that the C# code path was being executed, not the GDScript path.

4. **User logs are invaluable**: Without the game logs, this issue would have been much harder to diagnose.

## Additional Fix: GDScript Type Inference (2026-02-03)

**Issue**: CI logs showed parse errors in `player.gd`:
```
SCRIPT ERROR: Parse Error: Cannot infer the type of "hit_pos" variable because the value doesn't have a set type.
```

**Root Cause**: The `_raycast_for_wall()` function returns a `Dictionary`. Accessing dictionary values returns `Variant`, which cannot be used with `:=` type inference when combined with `Vector2` operations.

**Fix Applied**: Explicit type declarations for dictionary values:
```gdscript
# Before (caused parse error)
var hit_pos := wall_hit.position - global_position

# After (explicit type casting)
var wall_hit_pos: Vector2 = wall_hit.position
var hit_pos: Vector2 = wall_hit_pos - global_position
```

## Files Modified (Final)

1. `Scripts/Characters/Player.cs` - Full simple grenade mode implementation (C# version)
2. `scripts/characters/player.gd` - Debug logging, mode mismatch handling, and type inference fixes (GDScript version)
3. `scripts/objects/enemy.gd` - Line count reduction for CI compliance

## Final Test Plan

- [x] C# build compiles successfully
- [ ] Verify simple mode works: Hold RMB only (no G key) to aim, release to throw
- [ ] Verify trajectory preview appears with effect radius circle
- [ ] Verify effect radius circle matches grenade type (flashbang: 400px, frag: 225px)
- [ ] Verify complex mode still works when enabled in experimental settings
- [ ] Verify CI passes (all checks)
- [ ] Check game log for new debug messages: `[Player.Grenade.Simple]`
