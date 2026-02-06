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
| Feb 6, 21:30 | game_log_20260206_213011.txt | C# ReplayManager loads, `_Ready` fires, but `has_method("start_recording")` returns false — PascalCase naming issue |

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
   - Uses C# PascalCase conventions (GDScript callers must use PascalCase for user-defined methods)
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
- GDScript callers use `has_method("StartRecording")` to access C# methods with PascalCase names
- GDScript calling code updated to use PascalCase method names (Godot does NOT auto-convert user-defined C# method names)

## Bug #2: GDScript-to-C# Method Naming (PascalCase Required)

After the C# rewrite was deployed, the ReplayManager C# class loaded successfully (`_Ready` fired, line 58 in log 20260206_213011), but GDScript's `has_method("start_recording")` still returned `false`.

### Root Cause

In Godot 4.x, user-defined C# methods exposed to GDScript retain their original PascalCase names. The automatic snake_case-to-PascalCase conversion **only applies to built-in Godot engine methods**, NOT to user-defined methods. This is documented in the [Godot cross-language scripting docs](https://docs.godotengine.org/en/4.3/tutorials/scripting/cross_language_scripting.html).

The GDScript code was using:
```gdscript
replay_manager.has_method("start_recording")  # WRONG — returns false
replay_manager.start_recording(...)            # WRONG — method not found
```

When it should use:
```gdscript
replay_manager.has_method("StartRecording")    # CORRECT — returns true
replay_manager.StartRecording(...)             # CORRECT — calls C# method
```

### Evidence from Codebase

Other C# methods in the same project are already called with PascalCase from GDScript:
- `weapon.has_method("GetMagazineAmmoCounts")` → works
- `_player.has_method("EquipWeapon")` → works
- `weapon.has_method("ConfigureAmmoForEnemyCount")` → works

### Fix

Updated all ReplayManager method calls in `building_level.gd` and `test_tier.gd` from snake_case to PascalCase:
- `start_recording` → `StartRecording`
- `stop_recording` → `StopRecording`
- `has_replay` → `HasReplay`
- `get_replay_duration` → `GetReplayDuration`
- `start_playback` → `StartPlayback`
- `clear_replay` → `ClearReplay`

## Supporting Evidence

### From Godot Documentation and Issues

- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065): Confirms that `load()` returns GDScript objects even with parse errors, and `new()` returns null silently
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150): Confirms GDScript export mode issues in Godot 4.3
- [Godot Forum: Autoload Script Functions Not Called](https://forum.godotengine.org/t/autoload-script-functions-not-being-called-in-exported-build/127658): Confirms autoload methods don't work in exported builds

### From Game Logs

All 10 game logs collected in `docs/case-studies/issue-1/logs/` show the progression:
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
- `game_log_20260206_201555.txt` — All strategies still fail
- `game_log_20260206_213011.txt` — C# ReplayManager loads, but snake_case `has_method()` fails (PascalCase naming fix needed)
