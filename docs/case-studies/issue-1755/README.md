# Case Study: Issue #1755 — Game-End Screen Not Appearing in Railway Station Level

## Overview

After the initial implementation of the game-end screen (PR #1778), the owner reported three regressions:
1. Camera behaviour was broken
2. Exit point positions changed
3. The "Конец. Спасибо за игру" message did not appear

## Artifacts

- [`game_log_20260410_022806.txt`](game_log_20260410_022806.txt) — full game log from the owner's Windows session (Godot 4.3-stable, debug=false)

## Timeline of Events

| Time (from log) | Event |
|---|---|
| 02:28:06 | Game started, LabyrinthLevel loaded first |
| 02:28:22 | Player navigates to RailwayStationLevel (scene change begins) |
| 02:28:23 | **`LevelInitFallback] GDScript _ready() did NOT execute`** — C# fallback initializer takes over |
| 02:28:23 | C# fallback registers 15 enemies, places exit zone at **(120, 1544)** — wrong position |
| 02:28:32 | Player restarts the level — same fallback fires again |
| 02:28:40 | Third attempt — same fallback, same wrong exit zone at (120, 1544) |

## Root Cause Analysis

### Primary Root Cause: Duplicate `_unhandled_input` function

The script `scripts/levels/railway_station_level.gd` contained **two definitions** of the virtual method `_unhandled_input(event: InputEvent)`:

- **First definition** (line 641): added by PR #1778 — handles game-end screen dismiss on any key/mouse press
- **Second definition** (line 1038): pre-existing — handles the 'W' key shortcut to watch a replay on the score screen

In GDScript, a **duplicate function definition is a parse error**. When Godot tries to load the script it fails silently and the entire `.gd` file is treated as unattached. The C# `LevelInitFallback` system detects that `_ready()` never ran and performs its own minimal initialization.

Consequences of the script failing to load:
- `_ready()` never executed → no `_setup_exit_zone()` call → exit zones were not placed by our script
- `_show_game_end_screen()` was never reachable
- `_configure_camera()` was never called → camera defaults (no limits) were used → "camera broken"
- The C# fallback placed a **single exit zone at (120, 1544)** — a position that doesn't correspond to any embankment gap
- The C# fallback treated all 15 scene enemies as active (including the Exit_DroneOperator guards near the exit), meaning the exit would never activate until all 15 were killed

### Why It Worked Before

Before PR #1778, the script had only **one** `_unhandled_input` (the replay-key one at line 1038). The script parsed successfully, `_ready()` ran, and the level worked normally.

When PR #1778 added a **new** `_unhandled_input` for the game-end screen dismiss, the second definition made the script unparseable.

### Exit Zone Position Analysis

The script's intended exit zone positions were correct based on the scene geometry:

| Embankment | Center X | Half-width | Covers X |
|---|---|---|---|
| Embankment1 | 400 | 350 | 50..750 |
| Embankment2 | 1150 | 350 | 800..1500 |
| Embankment3 | 2150 | 350 | 1800..2500 |
| Embankment4 | 3200 | 350 | 2850..3550 |

Resulting gaps and exit zone centers:
- Gap 1: x=750..800 → center (775, 1000), width 50 px ✓
- Gap 2: x=1500..1800 → center (1650, 1000), width 300 px ✓
- Gap 3: x=2500..2850 → center (2675, 1000), width 350 px ✓

The C# fallback created a single zone at **(120, 1544)** — far from any gap.

### Camera Analysis

`_configure_camera()` sets `LIMIT_TOP = 900`. Since the embankment's south face is at y=900 and exit zones at y=1000 are south of that, the camera limit is not the cause of the player being unable to reach exits. The camera not being configured at all (when the script failed) caused the "camera broken" report — Godot's Camera2D default limits mean the camera could scroll to show the upper-left corner of the map, which would look "broken" compared to expected behavior.

## Fix Applied

Merged the two `_unhandled_input` handlers into a single function that handles both cases:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    # Game-end screen: any click or key dismisses it and shows the score screen.
    if _game_end_screen_shown:
        if event is InputEventMouseButton or event is InputEventKey:
            if event.is_pressed():
                _dismiss_game_end_screen()
        return
    # Score screen: W key triggers the watch-replay shortcut.
    if _score_shown:
        if event is InputEventKey and event.pressed and not event.echo:
            if event.keycode == KEY_W:
                _on_watch_replay_pressed()
```

This eliminates the parse error, allowing the script to load correctly, `_ready()` to execute, and all level initialization (exit zones, camera limits, game-end screen) to work as intended.

## Lessons Learned

1. **GDScript silently degrades** when there is a parse error — the script simply doesn't attach, and a C# fallback (if present) masks the failure making it hard to detect.
2. **Duplicate virtual method definitions** in GDScript cause a parse error at runtime rather than a compile-time warning visible to the developer.
3. **Test with the full scene**: unit tests that mock the scene would not have caught this, because the parse error only manifests when the full `.gd` file is loaded by Godot's script engine.
4. **Always search for existing definitions** before adding a new override of a built-in virtual method like `_unhandled_input`, `_process`, `_ready`, etc.
