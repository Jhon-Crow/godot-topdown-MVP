# Issue #416 Case Study: Add Replay Feature

## Issue Summary
- **Issue**: [#416 - добавить возможность посмотреть повтор](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/416)
- **Pull Request**: [#421](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/421)
- **Description**: Add ability to watch a replay after completing a level (Hotline Miami style)

## Timeline of Events

### Initial Implementation (2026-02-03)
1. **10:39 UTC** - AI solver started working on the issue
2. **10:40 UTC** - Usage limit reached, session interrupted before implementation could complete
3. Session created CLAUDE.md file and draft PR #421

### Second Attempt (2026-02-04 ~14:19 UTC)
1. AI solver resumed work on PR #421
2. Implemented full replay system:
   - Created `scripts/autoload/replay_manager.gd` - Core recording/playback system
   - Modified `scripts/levels/building_level.gd` - Added replay integration
   - Modified `scripts/levels/test_tier.gd` - Added replay integration
   - Modified `project.godot` - Registered ReplayManager autoload
3. PR updated with implementation details

### User Feedback (2026-02-04 ~23:22 UTC)
User reported: "кнопка смотреть повтор не появилась" (The "Watch Replay" button did not appear)

### Investigation (2026-02-05)
- Found merge conflict with upstream/main (exit zone feature)
- Resolved conflicts, keeping both replay and exit zone features
- Added detailed logging to diagnose why button might not appear

## Root Cause Analysis

### CONFIRMED ROOT CAUSE (2026-02-05)

**Inner class in autoload script causes parse error during export**

Analysis of user-provided game log (`game_log_20260205_030057.txt`) revealed:
```
[03:00:58] [BuildingLevel] ERROR: ReplayManager not found, replay recording disabled
```

Analysis of CI build logs showed the actual error:
```
Parse Error: There is already a variable named "replay_manager" declared in this scope.
at: GDScript::reload (res://scripts/autoload/replay_manager.gd:642)
ERROR: Failed to load script "res://scripts/autoload/replay_manager.gd" with error "Parse error".
ERROR: Failed to create an autoload, script 'res://scripts/autoload/replay_manager.gd' is not compiling.
```

**The Problem:**
- The `replay_manager.gd` script contained an inner class `class FrameData:`
- Godot 4.3 has a known issue with inner classes in autoload scripts during export
- The script file name `replay_manager` created a naming conflict during compilation
- This caused the autoload to fail to load entirely in the exported build

**Evidence:**
- `replay_manager.gd` was the ONLY autoload script with an inner class
- All other autoloads (15+ scripts) loaded successfully
- The error occurred during Godot's export process, not in the editor
- The game log showed GrenadeTimerHelper (the autoload before ReplayManager) loaded correctly

**The Fix:**
- Refactored the inner `class FrameData:` to use Dictionary-based frame storage instead
- Added helper function `_create_frame_data()` to create frame data dictionaries
- Updated all references from object property access to dictionary access

**Related Godot Issues:**
- [#75582](https://github.com/godotengine/godot/issues/75582) - Autoload singletons conflict with resource preloading
- [#110908](https://github.com/godotengine/godot/issues/110908) - Autoload naming issues in 4.5 (similar class of bugs)

### Previously Suspected Causes (Now Ruled Out):

1. **Merge Conflict with Exit Zone Feature**
   - Upstream added an "exit zone" feature that changes level completion flow
   - Player must now walk to exit zone after killing all enemies
   - Score/victory screen shows when reaching exit, not immediately after kills
   - Replay recording might have timing issues with new flow

2. **Recording Timing Issues**
   - Recording starts in `_ready()` after `_setup_player_tracking()` and `_setup_enemy_tracking()`
   - If these fail silently, `_player` or `_enemies` might be null/empty
   - Recording would have no data to record

3. **Button Visibility Condition**
   - Button only appears if `replay_manager.has_replay()` returns `true`
   - `has_replay()` returns `_frames.size() > 0`
   - If no frames recorded, button won't appear

## Implementation Details

### ReplayManager Features:
- Records game state at 60 FPS
- Captures player position, rotation, sprite flip state
- Captures enemy positions, rotations, alive states
- Captures bullet and grenade positions
- Maximum 5-minute recording duration
- Playback with speed controls (0.5x, 1x, 2x, 4x)
- Progress bar and time display
- ESC key or button to exit replay

### Level Integration:
- Recording starts in `_ready()` via `_start_replay_recording()`
- Recording stops when level completes via `stop_recording()`
- "Watch Replay" button conditionally shown if replay data exists
- Replay playback creates ghost entities for visualization

## Debug Logging Added

To diagnose the issue, detailed logging was added:

```gdscript
# In building_level.gd / test_tier.gd:
print("[Level] Starting replay recording - Player: %s, Enemies count: %d")
print("[Level] Replay status: has_replay=%s, duration=%.2fs")

# In replay_manager.gd:
print("[ReplayManager] Recording started: Level=%s, Player=%s, Enemies=%d")
print("[ReplayManager] Recording stopped: %d frames, %.2fs duration")
```

## Files Modified

### New Files:
- `scripts/autoload/replay_manager.gd` - Core replay system (746 lines)

### Modified Files:
- `project.godot` - Added ReplayManager autoload
- `scripts/levels/building_level.gd` - Replay recording/playback integration
- `scripts/levels/test_tier.gd` - Replay recording/playback integration

## Next Steps for Debugging

1. **Run the game and check console output** for the debug messages
2. **Verify recording starts** - Should see "Replay recording started"
3. **Verify recording stops** - Should see "Recording stopped: X frames"
4. **Check frame count** - If 0 frames, recording failed

## Possible Fixes to Try

1. Ensure `_player` and `_enemies` are not null when starting recording
2. Verify ReplayManager autoload is properly initialized before levels load
3. Check if `_physics_process` is being called during gameplay
4. Verify exit zone flow properly triggers `_complete_level_with_score()`

## Logs

- `logs/solution-draft-log-pr-421.txt` - Full AI solver execution log from 2026-02-04
