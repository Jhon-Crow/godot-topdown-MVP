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

---

## Follow-up Issue: Two New Bugs (Reported 2026-04-10)

After the parse-error fix landed, the game-end screen appeared correctly. However two new bugs were reported in the PR comments:

> 1. не исчезает при клике мышкой (doesn't disappear on mouse click)
> 2. если нажать любую клавишу срабатывает переход к экрану счёта, но если ещё раз нажать любую клавишу экран счёта появляется заново (должно обрабатываться только одно нажатие) — if you press any key the score screen appears, but pressing any key again makes the score screen appear again (only one press should be handled)

### Artifact

- [`game_log_20260410_155902.txt`](game_log_20260410_155902.txt) — second game log from the owner's Windows session; confirms GDScript now loads correctly (`GDScript _ready() already ran (enemies tracked: 15)`)

### Root Cause: Bug 1 — Mouse Click Does Not Dismiss

`_show_game_end_screen()` created the black background `ColorRect` with `mouse_filter = Control.MOUSE_FILTER_IGNORE`. In Godot 4, a Control node with `MOUSE_FILTER_IGNORE` passes input events through — it does **not** generate `gui_input` signals and does **not** cause the engine to route a `InputEventMouseButton` through `_unhandled_input` on a Node2D parent.

Godot 4's input routing for mouse events on a Control node with `MOUSE_FILTER_IGNORE`:
- The event is forwarded to the next control in the focus chain, not bubbled to `_unhandled_input` on the scene root.
- `_unhandled_input` receives events only after **all Control nodes in the scene tree have explicitly ignored** them. A full-screen `ColorRect` with `MOUSE_FILTER_IGNORE` is still a visible viewport-covering Control; the engine considers mouse events "handled by the GUI" at that layer before they reach `_unhandled_input`.

Result: mouse button presses were silently consumed by the GUI system and never delivered to `_unhandled_input`.

### Root Cause: Bug 2 — Score Screen Re-Appears on Repeated Key Presses

After `_dismiss_game_end_screen()` was called:
1. The function removed the overlay nodes and called `_proceed_to_score_screen()`.
2. But `_game_end_screen_shown` was **never reset to `false`** — it stayed `true`.
3. The next key press triggered `_unhandled_input` again.
4. `_game_end_screen_shown` was `true` → entered the if-block → called `_dismiss_game_end_screen()` again.
5. `_proceed_to_score_screen()` was called a second time → score screen appeared again.

There was no guard preventing `_dismiss_game_end_screen()` from running more than once.

### Fix Applied (2026-04-10)

Two changes in `scripts/levels/railway_station_level.gd`:

**1. Mouse input — switch to `gui_input` on the background ColorRect:**

```gdscript
bg.mouse_filter = Control.MOUSE_FILTER_STOP   # was MOUSE_FILTER_IGNORE
bg.gui_input.connect(func(ev: InputEvent) -> void:
    if ev is InputEventMouseButton and ev.is_pressed():
        _dismiss_game_end_screen()
)
```

`MOUSE_FILTER_STOP` causes the ColorRect to absorb mouse events and emit `gui_input`, which we use to call `_dismiss_game_end_screen()` exactly once.

**2. Idempotent dismiss guard:**

Added `var _game_end_dismissed: bool = false` to the class variables.

`_dismiss_game_end_screen()` now starts with:
```gdscript
if _game_end_dismissed:
    return
_game_end_dismissed = true
```

`_unhandled_input()` checks `_game_end_screen_shown and not _game_end_dismissed` so that once dismissed, subsequent key presses fall through to the score-screen branch (W key replay shortcut) instead of re-triggering dismiss.

### Why This Was Not Obvious

- `MOUSE_FILTER_IGNORE` sounds like "ignore the mouse filter", but it actually means "this node ignores mouse input" (i.e., the node is invisible to mouse events). The naming is counterintuitive.
- The lack of a dismiss guard was an oversight: the assumption was that the `_game_end_screen_shown` flag would prevent a second call, but that flag was never cleared.

### Lessons Learned (Follow-up)

1. **Control.MOUSE_FILTER_IGNORE means "this node ignores mouse"** — use `MOUSE_FILTER_STOP` + `gui_input` signal when you need a full-screen overlay to capture mouse clicks.
2. **One-shot handlers need an explicit "already fired" guard** — flags that gate entry (`_game_end_screen_shown`) must be cleared or supplemented with a "dismissed" flag to prevent re-entry after the action executes.
