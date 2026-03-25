# Case Study: Issue #1456 — Map Persist Not Working After Restart

## Summary

After a first fix attempt (PR #1476, commit `c3345806`) and a second fix attempt
(commit `f484d158`) were both deployed and tested, the owner reported "не сработало"
(it didn't work) both times. The player still always landed on the default
`LabyrinthLevel` instead of the last played level on every game restart.

This document reconstructs the full failure sequence from all four game logs,
identifies the true root cause of each failure, and describes the final corrective fix.

---

## Logs Analysed

| File | Session Start | Bug triggered? | Notes |
|------|--------------|----------------|-------|
| `game_log_20260325_070908.txt` | 07:09:08 | Yes (original) | First session — no save yet |
| `game_log_20260325_070919.txt` | 07:09:19 | Yes (original) | Second session — shows overwrite |
| `game_log_20260325_124153.txt` | 12:41:53 | Yes (2nd fix attempt) | SceneLoader race visible |
| `game_log_20260325_124210.txt` | 12:42:10 | Yes (2nd fix attempt) | Same SceneLoader race |

---

## Bug 1 — Original Race Condition (commits `c3345806`)

### Timeline Reconstruction

**Session 1 — `game_log_20260325_070908.txt`**

```
07:09:08  Game starts.  Default scene = LabyrinthLevel.
07:09:08  [PersistManager] _load_state()   → loads save file (no last_level yet)
07:09:08  [PersistManager] _connect_signals() → tree_changed connected
07:09:08  *** tree_changed fires (LabyrinthLevel is the current root scene)
          _on_tree_changed runs — no guard exists yet
          _is_level_scene("res://scenes/levels/LabyrinthLevel.tscn") → true
          _save_state_with_level("LabyrinthLevel.tscn") called
          → WRITES last_level = LabyrinthLevel.tscn  ← CRITICAL OVERWRITE
          log line 121: "Auto-saved current level: res://scenes/levels/LabyrinthLevel.tscn"

07:09:09  _navigate_to_last_level() runs (deferred)
          last_level = LabyrinthLevel.tscn (already overwritten by above)
          current_path = LabyrinthLevel.tscn
          → "Already at last played level"  (no navigation)

07:09:12  Player picks BuildingLevel from the menu.
          log: "Last level saved: res://scenes/levels/BuildingLevel.tscn"
          log: "Auto-saved current level: res://scenes/levels/BuildingLevel.tscn"
          → Save file now correctly holds last_level = BuildingLevel.tscn

07:09:14  Game exits.  Save file = BuildingLevel.tscn  ✓
```

**Session 2 — `game_log_20260325_070919.txt` (5 s later)**

```
07:09:19  Game starts again.  Default scene = LabyrinthLevel.
07:09:20  _load_state() → reads save file: last_level = BuildingLevel.tscn ✓
07:09:20  _connect_signals() → tree_changed connected
07:09:20  *** tree_changed fires (LabyrinthLevel is the current root scene)
          _on_tree_changed runs — still no guard
          → OVERWRITES last_level = LabyrinthLevel.tscn  ← BUG TRIGGERED
          log line 121: "Auto-saved current level: LabyrinthLevel.tscn"

07:09:20  _navigate_to_last_level() runs (deferred)
          get_last_level() → LabyrinthLevel.tscn (already overwritten)
          → "Already at last played level: LabyrinthLevel.tscn"
          → NO navigation to BuildingLevel  ← USER-VISIBLE BUG
```

### Root Cause 1

`tree_changed` fires **before** `_navigate_to_last_level()` (which is deferred),
so `_on_tree_changed` ran and overwrote the saved level on every startup.

### Fix Attempt 1 (not sufficient)

A `_navigation_ready` flag was added. A second deferred call `_set_navigation_ready()`
was queued immediately after `_navigate_to_last_level()` in `_ready()`, raising the
flag in the same deferred batch. This prevented the very first `tree_changed` (which
fires before the deferred queue flushes) from overwriting the save.

---

## Bug 2 — SceneLoader Background-Loading Race (commit `f484d158`)

The first fix correctly blocked the initial `tree_changed` event, but introduced a
second race: when SceneLoader performs **background** scene loading, it fires
`tree_changed` multiple times **while `current_scene` is still `LabyrinthLevel`**.
The guard was lifted too early (right after `_navigate_to_last_level()` called
`SceneLoader.load_level()`) — allowing those intermediate events through.

### Timeline Reconstruction

**Session from `game_log_20260325_124153.txt`**

```
12:41:53  Game starts.  Default scene = LabyrinthLevel.
12:41:53  _load_state() → last_level = BeachLevel.tscn ✓
12:41:53  _connect_signals() → tree_changed connected
12:41:53  _navigate_to_last_level() (deferred):
            → SceneLoader.load_level("BeachLevel.tscn") called (background)
12:41:53  _set_navigation_ready() (deferred):
            → _navigation_ready = true  ← GUARD LIFTED TOO EARLY

12:41:54  SceneLoader fires tree_changed while loading BeachLevel in the background.
          current_scene is STILL LabyrinthLevel at this point.
          _on_tree_changed():
            _navigation_ready == true  (guard already lifted)
            current_scene.scene_file_path = "LabyrinthLevel.tscn"
            _is_level_scene → true
            → SAVES LabyrinthLevel.tscn  ← OVERWRITES BeachLevel  ← BUG AGAIN
          log line 227: "Auto-saved current level on scene change: LabyrinthLevel.tscn"

12:42:01  Player manually picks BuildingLevel from the menu.
          → Save file corrected to BuildingLevel.tscn (visible in log)
```

**Session from `game_log_20260325_124210.txt`** shows the identical pattern:
```
12:42:11  _navigate_to_last_level() → navigating to BuildingLevel.tscn
12:42:11  SceneLoader starts background load
12:42:11  tree_changed fires while current_scene = LabyrinthLevel
          → log line 227: "Auto-saved current level: LabyrinthLevel.tscn"  ← OVERWRITE
```

### Root Cause 2

`_set_navigation_ready()` was queued in the **same deferred batch** as
`_navigate_to_last_level()`. `SceneLoader.load_level()` kicks off asynchronous
background loading immediately. This generates `tree_changed` events in subsequent
frames — **after** the deferred batch has flushed and `_navigation_ready` has been
set to `true` — but **before** `current_scene` has actually changed from
`LabyrinthLevel` to the target level. The guard was lifted before the scene
actually arrived.

```
Frame N (deferred queue):
  _navigate_to_last_level():
    SceneLoader.load_level("BuildingLevel.tscn")  ← starts background load
  _set_navigation_ready():
    _navigation_ready = true  ← guard lifted immediately after requesting load

Frame N+1, N+2, … (background loading in progress):
  SceneLoader fires tree_changed (background load activity)
  current_scene is STILL LabyrinthLevel
  _on_tree_changed():
    _navigation_ready == true  ← guard is already up
    saves LabyrinthLevel.tscn  ← BUG: guard lifted before scene changed
```

---

## Final Fix

Instead of lifting the guard after *requesting* navigation, the guard is now lifted
when `current_scene` **actually changes** to the target level.

- `_navigate_to_last_level()` records the destination in `_startup_navigation_target`
  and sets `_navigation_ready = true` directly when no navigation is needed.
- `_on_tree_changed()` checks `_startup_navigation_target`: if the incoming
  `current_scene.scene_file_path` does **not** match the target, the event is
  ignored. When it does match, the guard is lifted and normal auto-saving resumes.
- `_set_navigation_ready()` and the extra `call_deferred` in `_ready()` are removed.

```gdscript
# _navigate_to_last_level() — sets target instead of lifting guard early
_startup_navigation_target = last_level
SceneLoader.load_level(last_level)   # async — does NOT lift guard

# _on_tree_changed() — guard aware of target
func _on_tree_changed() -> void:
    var current_scene := get_tree().current_scene
    if current_scene == null or current_scene == _previous_scene:
        return
    if not _navigation_ready:
        if _startup_navigation_target == "":
            return
        var current_path = current_scene.scene_file_path
        if current_path != _startup_navigation_target:
            return   # still waiting — ignore LabyrinthLevel events
        # Arrived! Lift the guard.
        _navigation_ready = true
        _startup_navigation_target = ""
    _previous_scene = current_scene
    ...auto-save...
```

### Corrected Execution Timeline

```
Frame N (deferred):
  _navigate_to_last_level():
    _startup_navigation_target = "BuildingLevel.tscn"
    SceneLoader.load_level("BuildingLevel.tscn")
  (no _set_navigation_ready call — guard stays down)

Frames N+1 … N+M (SceneLoader background loading):
  tree_changed fires, current_scene = LabyrinthLevel
  _on_tree_changed():
    _navigation_ready == false
    _startup_navigation_target == "BuildingLevel.tscn"
    current_scene.scene_file_path == "LabyrinthLevel.tscn" ≠ target
    → RETURN immediately  ← FIX: no overwrite

Frame N+M+1 (scene transition complete):
  SceneLoader changes current_scene to BuildingLevel
  tree_changed fires
  _on_tree_changed():
    _navigation_ready == false
    current_scene.scene_file_path == "BuildingLevel.tscn" == target ✓
    → _navigation_ready = true  (guard lifted)
    → saves BuildingLevel.tscn  ✓
```

---

## Impact Summary

| Version | Trigger | Result |
|---------|---------|--------|
| Original (no fix) | Any game restart after playing a non-Labyrinth level | Always stuck on LabyrinthLevel |
| Fix attempt 1 (`c3345806`) | Game restart when SceneLoader background-loads the saved level | Still stuck on LabyrinthLevel |
| Fix attempt 2 (`f484d158`) | Game restart when SceneLoader background-loads the saved level | Still stuck on LabyrinthLevel |
| Final fix | None | Correctly navigates to last played level on every restart |

---

## Additional Context (Online Research)

The two-layer race condition uncovered here is a known pattern in Godot:

1. **Immediate signal emission during `_ready()`**: `tree_changed` can fire within
   the same frame as `_ready()` for autoloads because the scene tree is partially
   constructed when autoloads initialise. Deferred calls offer no protection against
   signals that fire *before* the deferred queue flushes.

2. **SceneLoader background events**: Godot's `ResourceLoader.load_threaded_request`
   (used internally by `SceneLoader`) performs loading on a background thread and can
   emit tree modifications as resources are assembled. The `tree_changed` signal is
   not restricted to frame boundaries and can fire mid-load.

The robust solution for this class of bug is to track the *expected destination* and
lift the guard only when the destination has actually been reached — not when
navigation has been *requested*.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/autoload/persist_manager.gd` | `_startup_navigation_target` field; guard in `_on_tree_changed()` checks target path; `_set_navigation_ready()` removed; `_navigation_ready` set directly inside `_navigate_to_last_level()` |
| `tests/unit/test_persist_manager.gd` | Five new tests covering the startup-guard logic (background-load race, guard lift, post-navigation saves, first-launch, already-at-saved-level) |
| `docs/case-studies/issue-1456/` | This analysis and all four game logs |
