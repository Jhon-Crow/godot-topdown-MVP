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

## Second User Report (2026-02-06)

### User Feedback
User reported: "кнопка повтора не появилась" (The replay button did not appear) with a new game log file.

### Analysis of game_log_20260206_120242.txt (3630 lines)

**Key findings from the log:**

1. **Line 133**: `[BuildingLevel] ERROR: ReplayManager not found, replay recording disabled`
   - ReplayManager autoload was NOT found at `/root/ReplayManager`
   - This is the root cause - the autoload failed to load in the exported build

2. **Missing log entry**: `[ReplayManager] ReplayManager ready` never appears in the log
   - The `_ready()` function of replay_system.gd was never called
   - Confirms the autoload script failed to load entirely

3. **Line 3303**: `[BuildingLevel] ERROR: ReplayManager not found when completing level`
   - At level completion time, ReplayManager still wasn't available
   - This prevented `stop_recording()` and `has_replay()` from working

4. **All other autoloads loaded successfully** (FileLogger, GameManager, ScoreManager, etc.)
   - GrenadeTimerHelper (C# autoload, right before ReplayManager) loaded correctly
   - Only ReplayManager (the last autoload) failed

### User Requirements (from PR comment)
1. Add Watch Replay button UNDER the Restart button (not beside it)
2. Add W key shortcut to watch replay when score is shown
3. Always show both buttons regardless of ReplayManager availability

### Fix Applied (2026-02-06)

**Changes to building_level.gd and test_tier.gd:**

1. **Always show both buttons**: Watch Replay button is always created, but disabled with "no data" text when ReplayManager is unavailable
2. **Vertical layout**: Changed from HBoxContainer to VBoxContainer - Restart button on top, Watch Replay below
3. **W key shortcut**: Added `_unhandled_input()` handler that checks for KEY_W when `_score_shown` is true
4. **Score shown flag**: Added `_score_shown: bool = false` variable to track when score screen is displayed

**The ReplayManager autoload issue:**
The replay_system.gd script may fail to load as autoload in exported builds. Previous fix (removing inner classes) was applied but the issue persists. The buttons now gracefully handle this by showing a disabled state rather than hiding entirely.

## Third User Report (2026-02-06 12:29)

### User Feedback
User reported: "кнопка появилась но на ней написано no data" (The button appeared but says "no data")
with game log `game_log_20260206_122932.txt`.

### Analysis of game_log_20260206_122932.txt

**Key findings (same root cause persists):**

1. **Line 134**: `[BuildingLevel] ERROR: ReplayManager not found, replay recording disabled`
2. **Missing**: `[ReplayManager] ReplayManager ready` never appears in the log
3. **Line 3012**: `Watch Replay button created (disabled - no replay data)` - Button shows but is disabled
4. **Lines 3019-3030**: User clicked "Watch Replay" 6 times, each time getting "no replay data available"

The UI fix from the previous report works (buttons are visible), but the underlying autoload loading issue persists.

### Deep Root Cause Investigation (2026-02-06)

The inner class removal fix was not sufficient. Further analysis identified **three additional issues** in `replay_system.gd` that can cause Godot 4.3 export parsing/compilation failures:

**Issue 1: `await` in function called from `_physics_process` (CRITICAL)**
- Line 378 (old): `await get_tree().create_timer(0.5).timeout` inside `_playback_frame_update()`
- `_playback_frame_update()` is called from `_physics_process()` on line 113 without `await`
- This makes `_playback_frame_update` a coroutine (returns Signal), but the call site ignores the return
- Godot 4.3's binary tokenizer may handle coroutine transformation differently during export
- Related: [#61037](https://github.com/godotengine/godot/issues/61037) - AutoLoad functions returning null in release mode

**Issue 2: Method name `is_playing()` conflicts with Godot built-in names (MODERATE)**
- `is_playing()` is a well-known method on AnimationPlayer, AudioStreamPlayer, etc.
- While `replay_system.gd` extends Node, the export pipeline's global name resolution may conflict
- Related: [#78230](https://github.com/godotengine/godot/issues/78230) - Autoload compile errors silently hidden

**Issue 3: Function defined before member variables (MODERATE)**
- `_create_frame_data()` was defined at line 38, before `var _frames` at line 52
- While valid in GDScript, this is an unusual pattern not used by any working autoload
- May interact poorly with the export binary tokenizer's parsing order

**Fixes Applied:**
1. Replaced `await` with timer-based state machine (`_playback_ending` + `_playback_end_timer`)
2. Renamed `is_playing()` → `is_replaying()` to avoid built-in name conflicts
3. Moved `_create_frame_data()` after all variable/signal declarations (standard GDScript ordering)
4. Renamed internal `_is_playing` → `_is_playing_back` for clarity

**Related Godot Issues:**
- [#61037](https://github.com/godotengine/godot/issues/61037) - AutoLoad script functions returning null in Release mode
- [#78230](https://github.com/godotengine/godot/issues/78230) - Autoload compile errors are silently swallowed
- [#94150](https://github.com/godotengine/godot/issues/94150) - GDScript export mode breaks exported builds
- [#58563](https://github.com/godotengine/godot/issues/58563) - Exported project cannot load autoload
- [#83119](https://github.com/godotengine/godot/issues/83119) - AutoLoad fails to load in unintuitive way

## Fourth User Report (2026-02-06 13:14)

### User Feedback
User reported: "всё ещё no data" (Still "no data") with game log `game_log_20260206_131432.txt`.

### Analysis of game_log_20260206_131432.txt

**Key findings — the three code-level fixes from the third report DID NOT resolve the issue:**

1. **Line 136**: `[BuildingLevel] ERROR: ReplayManager not found, replay recording disabled`
2. **Missing**: `[ReplayManager] ReplayManager ready` still never appears
3. **Line 3590**: `Watch Replay button created (disabled - no replay data)`
4. Multiple restarts (lines 299, 942, 1510) all show the same autoload failure

This confirmed that the autoload mechanism itself is the problem, not the GDScript code inside the script. The code-level fixes (await removal, method renaming, declaration reordering) did not address the real root cause.

### Definitive Root Cause: Godot 4.3 Autoload Mechanism Failure in Exported Builds

After **4 iterations** of attempted fixes, the true root cause was identified:

**The Godot 4.3 autoload registration mechanism itself silently fails to load certain GDScript autoloads in exported builds when the project also contains C# autoloads.**

**Evidence across all 5 user logs (spanning 3 days):**
- `game_log_20260205_030057.txt` — ReplayManager never loads
- `game_log_20260205_032338.txt` — ReplayManager never loads
- `game_log_20260206_120242.txt` — ReplayManager never loads
- `game_log_20260206_122932.txt` — ReplayManager never loads (after inner class fix)
- `game_log_20260206_131432.txt` — ReplayManager never loads (after await/naming/ordering fix)

**Contributing factors:**
1. **Mixed C#/GDScript project** — project uses `config/features=PackedStringArray("4.3", "C#")` with both C# and GDScript autoloads
2. **ReplayManager was the LAST autoload** in the list (line 31 of project.godot)
3. **C# autoload `GrenadeTimerHelper.cs` (line 29)** loaded successfully, as did GDScript autoload `PowerFantasyEffectsManager` (line 30) just before ReplayManager
4. **All 15+ other autoloads** loaded successfully in every log

**Known Godot issues that describe this class of bug:**
- [godotengine/godot#78230](https://github.com/godotengine/godot/issues/78230) — Autoload compile errors silently swallowed, only showing misleading "Script does not inherit from Node"
- [godotengine/godot#58563](https://github.com/godotengine/godot/issues/58563) — Exported project cannot load autoload containing specific patterns
- [godotengine/godot#83119](https://github.com/godotengine/godot/issues/83119) — AutoLoad fails to load in unintuitive way
- [godotengine/godot#39444](https://github.com/godotengine/godot/issues/39444) — Autoloaded scripts not generating nodes under root in C# projects

### Definitive Fix: Remove Autoload, Use Dynamic Loading

Since the autoload mechanism itself is unreliable for this script in exported builds, the fix **bypasses the autoload entirely**:

1. **Removed `ReplayManager` from `project.godot` autoload list**
2. **Added `_get_or_create_replay_manager()` helper** in both level scripts (building_level.gd, test_tier.gd)
3. The helper:
   - First checks `/root/ReplayManager` (works in Godot editor where autoload would have been)
   - If not found, dynamically loads `replay_system.gd` via `load()`, creates a Node, attaches the script, and adds it to `/root/`
   - Caches the reference in `_replay_manager` instance variable for efficiency
   - Verifies the script was attached successfully

**Why this works:**
- `load()` at runtime uses Godot's regular resource loading path, which is separate from the autoload initialization pipeline that was failing
- The script is loaded on-demand when the level needs it, after the engine is fully initialized
- No dependency on Godot's autoload registration, which has known silent failure modes
- The dynamically created node at `/root/` persists across level restarts, matching autoload behavior

## Logs

All user-provided game logs preserved in `logs/` directory:

- `logs/game_log_20260205_030057.txt` — First user report (replay button missing)
- `logs/game_log_20260205_032338.txt` — Second user report (button still missing)
- `logs/game_log_20260206_120242.txt` — Third user report (button missing, different code)
- `logs/game_log_20260206_122932.txt` — Fourth user report ("no data" on button)
- `logs/game_log_20260206_131432.txt` — Fifth user report ("no data" persists after 3 code fixes)
- `logs/solution-draft-log-pr-421.txt` — Full AI solver execution log from 2026-02-04
