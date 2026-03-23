# Case Study: Issue #1293 — Inconsistent FPS Drops Across Different Launches

## Summary

**Issue:** Severe and inconsistent FPS drops (1–9 fps instead of 30+) occur across different game launches of the same build. The same executable, same level, and same number of enemies produce dramatically different frame rates on successive runs.

**Russian title:** "почему то при разных запусках происходят сильные просадки fps"
**Translation:** "for some reason across different launches severe FPS drops occur"

**Root Cause:** Godot's `print()` function writes to stdout on every log message. In Windows release builds, stdout handling is non-deterministic — it may be connected to a pipe, console, or NULL device depending on how the OS launches the process. With 40–70 log messages per second, the `print()` overhead causes variable FPS drops. The severity depends on the OS-level stdout state at launch time, explaining the inconsistency.

**Fix:** Gate all `print()` calls in production-path logging functions to `OS.is_debug_build()` only. Log messages still go to the file logger (with write buffering from Issue #885), but skip console output in release builds.

---

## Timeline / Sequence of Events

Three game logs from the same executable were collected within a 3-minute window (04:58:24 – 05:01:29). All three share identical settings: Windows, Godot 4.3-stable, same build, same levels, same enemy configurations.

### Log 1 (game_log_20260322_045824) — 65 seconds, **19 FPS drops** (1–9 fps)

| Time | Event | FPS |
|------|-------|-----|
| 04:58:24 | Game start → LabyrinthLevel (5 enemies) | ~60 fps |
| 04:58:34 | Scene change → BuildingLevel (10 enemies) | 9 fps ↓ |
| 04:58:36 | Debug mode toggled ON | 4 fps |
| 04:58:39–04:59:29 | Repeated deaths/reloads on BuildingLevel | **1–4 fps persistent** |

Characteristic: FPS drops to 1–4 fps immediately after BuildingLevel load and **never recovers** for the entire session.

### Log 2 (game_log_20260322_045958) — 35 seconds, **20 FPS drops** (4–27 fps)

| Time | Event | FPS |
|------|-------|-----|
| 04:59:58 | Game start → LabyrinthLevel (5 enemies) | ~60 fps |
| 05:00:06 | Scene change → BuildingLevel (10 enemies) | 20 fps ↓ |
| 05:00:07–05:00:33 | Gameplay with oscillating FPS | 4–27 fps |

Characteristic: FPS drops but **partially recovers**, oscillating between 4–27 fps.

### Log 3 (game_log_20260322_050045) — 44 seconds, **2 FPS drops** (1 fps, 29 fps)

| Time | Event | FPS |
|------|-------|-----|
| 05:00:45 | Game start → LabyrinthLevel (5 enemies) | 1 fps → 60 fps |
| 05:01:01 | Scene change → BuildingLevel (10 enemies) | ~60 fps ✓ |
| 05:01:08–05:01:29 | Continued gameplay, multiple scene reloads | ~60 fps ✓ |

Characteristic: Single shader-compilation stutter at start, then **smooth 60 fps** throughout — including the same BuildingLevel with 10 enemies that caused 1–4 fps in Log 1.

---

## Root Cause Analysis

### Primary Cause: `print()` in FileLogger and Autoloads

The core `_write_log()` function in `scripts/autoload/file_logger.gd` (line 151) called `print(log_line)` for **every log message**, including in release builds:

```gdscript
func _write_log(level: String, message: String) -> void:
    var log_line := "[%s] [%s] %s" % [timestamp, level, message]
    print(log_line)  # ← This was called 40-70 times/second in gameplay
```

Additionally, **10 other autoload managers** used the same dual-logging pattern:

```gdscript
func _log(message: String) -> void:
    if logger: logger.log_info(message)
    else: print(message)  # ← Fallback print() also runs in release builds
```

#### Why `print()` causes inconsistent FPS on Windows

1. **Stdout pipe state varies per launch**: On Windows, how the OS connects stdout for a GUI application depends on parent process, console allocation, and process creation flags. The exact behavior varies between launches.

2. **Console write is blocking**: When stdout IS connected to a console or pipe, Godot's `print()` calls `WriteFile()` or `WriteConsole()` which can block. With 40–70 messages/second, this accumulates to significant main-thread stalls.

3. **Non-deterministic severity**: The same executable launched at 04:58:24 gets 1–4 fps (stdout blocked), while at 05:00:45 it gets 60 fps (stdout goes to NUL). The difference is entirely in how Windows handles the process's stdout at launch time.

### Contributing Factors

1. **High logging volume**: The game produces 2000–2600 log messages in 35–65 second sessions (34–71 messages/second), driven by:
   - BloodDecal: 600–700 messages per session (blood effects)
   - ENEMY: 400–580 messages per session (AI state changes)
   - SoundPropagation: 150–300 messages per session (sound events)
   - ReplayManager: ~115 messages per session (frame recording)

2. **Write buffering masked the real bottleneck**: Issue #885 added write buffering to reduce disk I/O. This successfully eliminated file write stalls, but the `print()` calls were **outside** the buffer — they executed synchronously for every message.

3. **Shader compilation**: Log 3 shows a single 1-fps frame at game start (shader compilation). This is a one-time cost that doesn't recur, but it can coincide with other stalls to create the impression of worse problems.

### Evidence Ruling Out Other Hypotheses

| Hypothesis | Evidence Against |
|---|---|
| Logging volume causes drops | Log 3 produces **more** log messages/sec (71/s) than Log 1 (34/s) but has no FPS drops |
| Enemy count causes drops | Log 3 runs BuildingLevel with 10 enemies at 60 fps; Log 1 runs same level at 1–4 fps |
| Debug mode causes drops | Log 2 and 3 both have Debug: true; Log 2 drops to 4 fps, Log 3 stays at 60 fps |
| Per-frame logging causes drops | Agent analysis confirmed no ungated per-frame logging; all hot-path logs are properly gated |

---

## Solution Applied

### Fix: Gate `print()` to Debug Builds Only (Issue #1293)

**Files modified (12 files):**

1. `scripts/autoload/file_logger.gd` — Core logger: `print()` gated to `OS.is_debug_build()`
2. `scripts/autoload/impact_effects_manager.gd` — `_log_info()` print gated
3. `scripts/autoload/cinema_effects_manager.gd` — `_log()` fallback gated
4. `scripts/autoload/penultimate_hit_effects_manager.gd` — `_log()` fallback gated
5. `scripts/autoload/last_chance_effects_manager.gd` — `_log()` fallback gated
6. `scripts/autoload/power_fantasy_effects_manager.gd` — `_log()` fallback gated
7. `scripts/autoload/black_metal_effects_manager.gd` — `_log()` fallback gated
8. `scripts/autoload/black_metal_lightning_effects_manager.gd` — `_log()` fallback gated
9. `scripts/autoload/flashbang_player_effects_manager.gd` — `_log()` fallback gated
10. `scripts/autoload/scene_loader.gd` — `_log()` fallback gated
11. `scripts/autoload/nav_mesh_monitor.gd` — `_log()` and `_log_inner()` fallbacks gated
12. `scripts/autoload/replay_system.gd` — `_log_to_file()` fallback gated + removed duplicate direct `print()` calls

**Pattern applied:**

```gdscript
# BEFORE: always prints to console
print(log_line)

# AFTER: only prints in debug/editor builds
if OS.is_debug_build():
    print(log_line)
```

### What This Preserves

- **File logging**: All messages continue to be written to the log file via the buffered FileLogger system (Issue #885)
- **Debug builds**: `print()` still works when running from the Godot editor or debug exports
- **Error visibility**: ERROR-level messages still flush to disk immediately (Issue #885)

### Expected Impact

- Eliminates 40–70 `print()` calls per second from the main thread in release builds
- Removes the non-deterministic stdout I/O overhead that caused inconsistent FPS
- BuildingLevel with 10 enemies should consistently run at 60 fps regardless of how the OS handles stdout
