# Case Study: Issue #1456 — Map Persist Not Working After Restart

## Summary

After the initial fix (PR #1476, commit `c3345806`) was deployed, the owner
tested it and reported "не сработало" (it didn't work). The player still
landed on the default `LabyrinthLevel` instead of the last played level on
every game restart.

This document reconstructs the exact failure sequence from the attached game
logs, identifies the root cause, and describes the corrective fix.

---

## Logs Analysed

| File | Session Start | Session End | Duration |
|------|--------------|-------------|----------|
| `game_log_20260325_070908.txt` | 07:09:08 | 07:09:14 | ~6 s |
| `game_log_20260325_070919.txt` | 07:09:19 | 07:09:25 | ~6 s |

---

## Timeline Reconstruction

### Session 1 — `game_log_20260325_070908.txt`

```
07:09:08  Game starts.  Default scene = LabyrinthLevel.
07:09:08  [PersistManager] _load_state()   → loads save file (no last_level yet)
07:09:08  [PersistManager] _connect_signals() → tree_changed connected
07:09:08  *** tree_changed fires (LabyrinthLevel is the current root scene)
          _on_tree_changed runs, _navigation_ready = false (bug: no guard yet)
          _is_level_scene("res://scenes/levels/LabyrinthLevel.tscn") → true
          _save_state_with_level("LabyrinthLevel.tscn") called
          → WRITES last_level = LabyrinthLevel.tscn  ← CRITICAL OVERWRITE
          log line 121: "Auto-saved current level: res://scenes/levels/LabyrinthLevel.tscn"

07:09:09  _navigate_to_last_level() runs (deferred)
          last_level = LabyrinthLevel.tscn (already overwritten by above)
          current_path = LabyrinthLevel.tscn
          → "Already at last played level"  (no navigation — correct for this run)

07:09:12  Player or LevelsMenu triggers navigation to BuildingLevel.
          log line 268: "Last level saved: res://scenes/levels/BuildingLevel.tscn"
          log line 292: "Auto-saved current level: res://scenes/levels/BuildingLevel.tscn"
          → save file now correctly holds last_level = BuildingLevel.tscn

07:09:14  Game exits.  Save file = BuildingLevel.tscn  ✓
```

### Session 2 — `game_log_20260325_070919.txt` (5 s later)

```
07:09:19  Game starts again.  Default scene = LabyrinthLevel.
07:09:20  [PersistManager] _load_state()   → reads save file: last_level = BuildingLevel.tscn ✓
07:09:20  [PersistManager] _connect_signals() → tree_changed connected
07:09:20  *** tree_changed fires (LabyrinthLevel is the current root scene)
          _on_tree_changed runs, _navigation_ready = false (no guard)
          _is_level_scene("res://scenes/levels/LabyrinthLevel.tscn") → true
          _save_state_with_level("LabyrinthLevel.tscn") called
          → OVERWRITES last_level = LabyrinthLevel.tscn  ← BUG TRIGGERED
          log line 121: "Auto-saved current level: res://scenes/levels/LabyrinthLevel.tscn"

07:09:20  _navigate_to_last_level() runs (deferred)
          get_last_level() now returns LabyrinthLevel.tscn (already overwritten!)
          current_path = LabyrinthLevel.tscn
          → "Already at last played level: LabyrinthLevel.tscn"
          → NO navigation to BuildingLevel  ← USER-VISIBLE BUG

07:09:20  Auto-saved level = LabyrinthLevel (locked in again for next session)
```

---

## Root Cause

`_on_tree_changed` is connected in `_connect_signals()`, which is called
**synchronously** in `_ready()`.  However, `_navigate_to_last_level()` is
scheduled with `call_deferred`, so it runs **one frame later**.

Because `tree_changed` fires during the same frame that `_ready()` runs —
when the engine is setting up the default scene (`LabyrinthLevel`) — the
auto-save in `_on_tree_changed` executes **before** `_navigate_to_last_level`
has had a chance to read the saved level and redirect the player.

Result: every game launch **overwrites** the previously saved level with
`LabyrinthLevel.tscn` before the redirect can happen.

### Why Was This a Race Condition?

GDScript's `call_deferred` inserts a call into the end of the current frame's
message queue.  Signal handlers connected via `signal.connect()` fire
**immediately** when the signal is emitted — they are not deferred.
`tree_changed` is emitted by the engine itself when scene tree structure
changes, and the very first emission (for the initial main scene) happens
during the same `_ready` phase, **before** the deferred queue is flushed.

```
Frame N (startup):
  autoload._ready() runs:
    _load_state()            → reads BuildingLevel.tscn from disk ✓
    _connect_signals()       → tree_changed handler registered
    call_deferred(_navigate) → queued for end of frame
    call_deferred(_set_ready) → queued for end of frame (not yet in code)

  engine emits tree_changed (LabyrinthLevel is root):
    _on_tree_changed()       → saves LabyrinthLevel.tscn ← OVERWRITE
                               (because no guard exists yet)

  deferred queue flushes:
    _navigate_to_last_level() → reads last_level = LabyrinthLevel.tscn (corrupted)
                                 → no redirect needed (already there)
```

---

## Fix Applied

A boolean guard `_navigation_ready` was introduced.  `_on_tree_changed`
returns early while this flag is `false`.  A second deferred call,
`_set_navigation_ready()`, is queued immediately after `_navigate_to_last_level`
in `_ready()`.  Because both are in the same deferred batch, `_set_navigation_ready`
runs right after navigation has been dispatched — from that point on, all
subsequent scene changes are auto-saved normally.

```gdscript
# In _ready():
call_deferred("_navigate_to_last_level")
call_deferred("_set_navigation_ready")   # ← new

# New guard in _on_tree_changed():
func _on_tree_changed() -> void:
    if not _navigation_ready:             # ← new guard
        return
    ...
```

### Corrected Execution Timeline

```
Frame N (startup):
  _ready():
    _load_state()              → reads BuildingLevel.tscn ✓
    _connect_signals()         → tree_changed handler registered
    call_deferred(_navigate)   → queued
    call_deferred(_set_ready)  → queued

  engine emits tree_changed (LabyrinthLevel):
    _on_tree_changed():
      _navigation_ready == false → return immediately  ← FIX
      (NO overwrite)

  deferred queue flushes:
    _navigate_to_last_level()  → reads last_level = BuildingLevel.tscn ✓
                                  → navigates to BuildingLevel  ✓
    _set_navigation_ready()    → _navigation_ready = true

Frame N+M (BuildingLevel finishes loading):
  engine emits tree_changed:
    _on_tree_changed():
      _navigation_ready == true
      scene_path = BuildingLevel.tscn → _is_level_scene = true
      → saves BuildingLevel.tscn  ✓ (correct and harmless)
```

---

## Impact

- **Affected versions:** all builds containing PR #1476 commit `c3345806`
  through this fix
- **Trigger:** every single game restart when the player had previously
  navigated away from `LabyrinthLevel`
- **User experience:** player always returned to `LabyrinthLevel` regardless
  of last played level — the original reported bug was not fixed

---

## Additional Context (Online Research)

The pattern of a startup signal racing with deferred initialisation is a
well-known Godot footgun documented in the Godot community:

- Godot signals connected in `_ready()` can fire within the same frame for
  autoloads because the scene tree is already partially constructed when
  autoloads initialise.
- The standard mitigation is either (a) defer the signal connection itself,
  or (b) add a "ready" guard flag — both achieve the same result.  Option (b)
  was chosen here to keep the connection synchronous and avoid missing any
  scene changes that happen between deferred calls.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/autoload/persist_manager.gd` | Added `_navigation_ready` flag and `_set_navigation_ready()` method; guard in `_on_tree_changed()` |
| `tests/unit/test_persist_manager.gd` | Three new tests covering the startup-guard logic |
| `docs/case-studies/issue-1456/` | This analysis and the original game logs |
