# Case Study: Issue #1 — ReplayManager Not Working in Exported Builds

## Summary

The ReplayManager system, implemented as a GDScript autoload (`replay_system.gd`), consistently fails to load its methods in exported Godot 4.3 builds with C# enabled. The symptom is that `has_method("start_recording")` returns `false` despite the script being attached to the node, and `GDScript.new()` returns `null`. This prevents replay recording from ever starting, resulting in the "Watch Replay" button always showing "no data".

## Timeline / Sequence of Events

| Date/Time | Log File | Error Pattern |
|-----------|----------|---------------|
| Feb 5, 03:00 | game_log_20260205_030057.txt | `ERROR: ReplayManager not found, replay recording disabled` |
| Feb 5, 03:23 | game_log_20260205_032338.txt | `ERROR: ReplayManager not found, replay recording disabled` (up to 10+ repeated errors) |
| Feb 6, 12:02 | game_log_20260206_120242.txt | `ERROR: ReplayManager not found, replay recording disabled` |
| Feb 6, 12:29 | game_log_20260206_122932.txt | `ERROR: ReplayManager not found` — Watch Replay button now appears but disabled |
| Feb 6, 13:14 | game_log_20260206_131432.txt | Same pattern, button shows "no data" |
| Feb 6, 14:14 | game_log_20260206_141414.txt | New: `WARNING: ReplayManager created but start_recording method not found` |
| Feb 6, 14:32 | game_log_20260206_143228.txt | Detailed: autoload exists, scene loaded, `script.new()` returned null, all 4 strategies fail |
| Feb 6, 18:51 | game_log_20260206_185149.txt | Same: all 4 loading strategies fail, same GDScript ID `<GDScript#-9223372007242988300>` |
| Feb 6, 20:15 | game_log_20260206_201555.txt | Same: all loading strategies fail, Watch Replay shows "no data" |

### Key Observations from Timeline

1. **ReplayManager autoload IS registered** (present at `/root/ReplayManager` since ~14:14)
2. **The GDScript resource IS loaded** (shows `<GDScript#-9223372007242988300>`)
3. **But methods are NOT accessible** — `has_method("start_recording")` returns `false`
4. **`_ready()` never fires** — the log message "ReplayManager ready (script loaded and _ready called)" never appears in any log
5. **`GDScript.new()` returns null** — the script cannot be instantiated
6. **Same GDScript ID across all attempts** — all 4 loading strategies produce the same broken script instance
7. **All 16+ other GDScript autoloads work perfectly** — only `replay_system.gd` fails

## Root Cause Analysis

### Direct Cause

The GDScript file `replay_system.gd` fails to **compile/parse** when loaded in an exported Godot 4.3 build with C# (Mono) enabled. The GDScript resource object is created (so `load()` succeeds and `get_script()` is non-null), but the bytecode is never compiled, so:
- `has_method()` returns `false` for all custom methods
- `GDScript.new()` returns `null`
- `_ready()` and other virtual functions never execute
- The node exists in the scene tree but is functionally inert

### Why This Specific Script Fails

This is documented behavior in Godot issues:
- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065): `load()` returns a `GDScript` even with parse errors, but `new()` fails and errors are undetectable
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150): GDScript export mode breaks builds with binary tokenization
- [godotengine/godot#91713](https://github.com/godotengine/godot/issues/91713): Scripts fail to load with parse errors on exported projects

The script `replay_system.gd` is one of the larger and more complex GDScript files (~819 lines), using:
- Typed function parameters (`level: Node2D`, `player: Node2D`, etc.)
- Complex dictionary and array operations
- Scene loading via `load()` at runtime
- Signal definitions
- Multiple method signatures with return types

While each of these is valid GDScript, the combination appears to trigger a silent parse failure in the binary tokenization pipeline. Setting `script_export_mode=0` (text mode) was attempted but did NOT resolve the issue — the script still fails to parse in the exported build.

### Why Other GDScript Autoloads Work

The 16+ other GDScript autoloads in this project are simpler scripts (typically 50-200 lines) that use basic constructs. The `replay_system.gd` is significantly more complex and likely hits an edge case in the GDScript parser/compiler during the export process.

### Previous Fix Attempts (All Failed)

| Attempt | Fix | Result |
|---------|-----|--------|
| 1 | Remove inner classes from replay_system.gd | Still fails |
| 2 | Rename replay_manager.gd to replay_system.gd (avoid naming collision with autoload) | Still fails |
| 3 | Use scene-based autoload (ReplayManager.tscn) instead of script-based | Still fails |
| 4 | Multi-strategy loading: autoload, scene instantiate, script.new(), Node+set_script() | All 4 strategies fail |
| 5 | Set `script_export_mode=0` (text mode instead of binary tokens) | Still fails |
| 6 | Re-export after text mode change | Still fails |

## Solution

### Chosen Approach: Rewrite ReplayManager in C#

Since this is a mixed C#/GDScript project where C# scripts (Player.cs, Enemy.cs, weapons, etc.) all work reliably in exported builds, the solution is to rewrite the ReplayManager as a C# class.

**File:** `Scripts/Autoload/ReplayManager.cs`

C# scripts are compiled by the .NET SDK into a DLL, completely bypassing the GDScript parser/tokenizer. This eliminates the root cause entirely.

### Changes Made

1. **New file: `Scripts/Autoload/ReplayManager.cs`**
   - Faithful port of all functionality from `replay_system.gd`
   - Uses C# PascalCase conventions (Godot auto-converts to snake_case for GDScript callers)
   - Same recording, playback, ghost entity, and UI features
   - `[GlobalClass]` attribute for Godot integration

2. **Modified: `project.godot`**
   - Changed autoload from: `ReplayManager="*res://scenes/autoload/ReplayManager.tscn"`
   - Changed autoload to: `ReplayManager="*res://Scripts/Autoload/ReplayManager.cs"`

3. **Modified: `scripts/levels/building_level.gd`**
   - Removed complex 4-strategy `_get_or_create_replay_manager()` function
   - Replaced with simple autoload accessor: `get_node_or_null("/root/ReplayManager")`

4. **Modified: `scripts/levels/test_tier.gd`**
   - Same simplification as building_level.gd

### Why This Solution Works

- C# scripts are compiled by the .NET SDK, not the GDScript tokenizer
- The GrenadeTimerHelper.cs autoload already works reliably in exports (same pattern)
- GDScript callers use `has_method("start_recording")` which maps to C# `StartRecording` via Godot's automatic snake_case conversion
- No changes needed in GDScript calling code — method names remain the same

## Supporting Evidence

### From Godot Documentation and Issues

- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065): Confirms that `load()` returns GDScript objects even with parse errors, and `new()` returns null silently
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150): Confirms GDScript export mode issues in Godot 4.3
- [Godot Forum: Autoload Script Functions Not Called](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658): Confirms autoload methods don't work in exported builds

### From Game Logs

All 9 game logs collected in `docs/case-studies/issue-1/logs/` show the same pattern:
- ReplayManager GDScript fails to provide methods
- Recording never starts
- No replay data is ever available
- Watch Replay button consistently shows "no data"

## Logs

All game logs from user testing sessions are preserved in `docs/case-studies/issue-1/logs/`:

- `game_log_20260205_030057.txt` — First report: ReplayManager not found
- `game_log_20260205_032338.txt` — Repeated errors
- `game_log_20260206_120242.txt` — After autoload registration
- `game_log_20260206_122932.txt` — Button appears, shows "no data"
- `game_log_20260206_131432.txt` — Still "no data"
- `game_log_20260206_141414.txt` — Method not found despite script attached
- `game_log_20260206_143228.txt` — All 4 loading strategies documented failing
- `game_log_20260206_185149.txt` — Same failure, player controls issue also reported
- `game_log_20260206_201555.txt` — Latest: all strategies still fail
