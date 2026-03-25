# Issue #1456 — Map Persistence Root Cause Analysis

## Problem Statement

After restarting the game, the player always lands on **LabyrinthLevel** (the default
starting scene defined in `project.godot`), regardless of which level was played last.

---

## Four Fix Attempts — Timeline

### Attempt 0 (baseline): No persistence at all

`LevelsMenu._on_level_selected()` already called `PersistManager.save_last_level(level_path)`, and
`PersistManager._navigate_to_last_level()` ran deferred on startup to redirect to the saved level.
The redirection worked — but **every subsequent startup the saved level was overwritten back to
LabyrinthLevel** before the redirect could complete.

---

### Attempt 1 (`c3345806`): Auto-save on `tree_changed` — no guard

**Change**: Connected `tree_changed` to `_on_tree_changed` which saved `current_scene.scene_file_path`.

**Failure** (from `game_log_20260325_070908.txt` / `game_log_20260325_070919.txt`):

```
1. _ready() fires — _load_state() reads BuildingLevel from file correctly
2. _connect_signals() — tree_changed is now connected
3. tree_changed fires immediately for LabyrinthLevel (the default main scene)
4. _on_tree_changed() auto-saves LabyrinthLevel.tscn → OVERWRITES BuildingLevel
5. call_deferred("_navigate_to_last_level") runs — but saved level is now LabyrinthLevel
6. "Already at last played level: LabyrinthLevel.tscn" → no redirect
```

Log evidence (`game_log_20260325_070919.txt`, line 121):
> `Auto-saved current level: LabyrinthLevel.tscn`  (immediately on startup)
> `Already at last played level: LabyrinthLevel.tscn`  (too late — damage done)

---

### Attempt 2 (`f484d158`): `_navigation_ready` guard — lifted too early

**Change**: Added `_navigation_ready` flag, lifted by `_set_navigation_ready()` scheduled
deferred immediately after `_navigate_to_last_level()`.

**Failure** (from `game_log_20260325_124153.txt` / `game_log_20260325_124210.txt`):

```
1. call_deferred("_navigate_to_last_level") scheduled
2. call_deferred("_set_navigation_ready") scheduled in the SAME batch
3. _navigate_to_last_level() fires → SceneLoader.load_level() starts 0.3 s tween
4. _set_navigation_ready() fires → _navigation_ready = true  ← GUARD LIFTED TOO EARLY
5. SceneLoader background loading fires tree_changed while current_scene = LabyrinthLevel
6. _on_tree_changed(): _navigation_ready == true → saves LabyrinthLevel  ← OVERWRITES
```

Log evidence (`game_log_20260325_124153.txt`, line 227):
> `Auto-saved current level on scene change: res://scenes/levels/LabyrinthLevel.tscn`

---

### Attempt 3 (`ffa4f941`): `_startup_navigation_target` guard — correct but incomplete

**Change**: Replaced `_set_navigation_ready()` with `_startup_navigation_target` field.
Guard lifted only when `current_scene.scene_file_path == _startup_navigation_target`.

**Partial success**: The auto-save race condition was fixed.
Session 1 (`game_log_20260325_130634.txt`) worked correctly:
```
[13:06:35] Navigating to last played level: BuildingLevel.tscn
[13:06:35] Last level saved: BuildingLevel.tscn   ← from LevelsMenu explicit save
[13:06:39] Startup navigation complete — arrived at: BuildingLevel.tscn ✓
[13:06:39] Auto-saved current level on scene change: BuildingLevel.tscn ✓
```

**Failure** in session 2 (`game_log_20260325_130647.txt`):
```
[13:06:48] Navigating to last played level: BuildingLevel.tscn
[13:06:48] Starting background load for: BuildingLevel.tscn
[13:06:48] ERROR: Invalid resource (falling back to sync): BuildingLevel.tscn
           ↑ SceneLoader._process() got THREAD_LOAD_INVALID_RESOURCE
           ↑ Code path: _hide_loading_screen() — loading ABORTED silently
[13:06:48] Background load started successfully  ← logged after abort (log ordering)
```

The SceneLoader received `THREAD_LOAD_INVALID_RESOURCE` during background loading.
**The old handler called `_hide_loading_screen()` which aborted without a sync fallback.**
The target scene never became `current_scene`, so `_startup_navigation_target` was never
cleared and `_navigation_ready` stayed `false` forever — leaving the player on LabyrinthLevel
with auto-save permanently blocked.

---

## Root Cause (Confirmed)

**Two bugs work together:**

### Bug 1 — PersistManager: auto-save race condition

`tree_changed` fires with `current_scene = LabyrinthLevel` during SceneLoader's background
loading phase, overwriting the correctly saved non-Labyrinth level.

**Fix**: `_startup_navigation_target` guard — only lift `_navigation_ready` when
`current_scene.scene_file_path` actually equals the target (not when navigation is merely
requested).  This was correct in Attempt 3.

### Bug 2 — SceneLoader: silent abort on `THREAD_LOAD_INVALID_RESOURCE`

In Godot 4.3, `ResourceLoader.load_threaded_get_status()` can intermittently return
`THREAD_LOAD_INVALID_RESOURCE` for a resource that `ResourceLoader.exists()` confirms as
present.  The existing `THREAD_LOAD_FAILED` branch already handled this correctly (calls
`_fallback_sync_load()`), but `THREAD_LOAD_INVALID_RESOURCE` called `_hide_loading_screen()`
directly — **silently aborting the load without any fallback**.

This was confirmed online: Godot issues report that `load_threaded_request` can return
`THREAD_LOAD_INVALID_RESOURCE` or `THREAD_LOAD_FAILED` for valid scenes on repeat loads
in the same session, especially for heavier scenes.

**Fix**: treat `THREAD_LOAD_INVALID_RESOURCE` identically to `THREAD_LOAD_FAILED` — call
`_fallback_sync_load()` so the scene transition always completes.

---

## Corrected Execution Timeline

```
Startup (session 2, after fix):
──────────────────────────────
1. PersistManager._ready():
   _load_state() reads BuildingLevel from file ✓
   _connect_signals() → tree_changed connected
   call_deferred("_navigate_to_last_level")

2. Deferred: _navigate_to_last_level():
   _startup_navigation_target = "BuildingLevel.tscn"
   SceneLoader.load_level("BuildingLevel.tscn")

3. SceneLoader background loading fires tree_changed (current_scene = LabyrinthLevel):
   _on_tree_changed():
     _navigation_ready == false
     current_scene.scene_file_path ("LabyrinthLevel") ≠ target ("BuildingLevel")
     → RETURN — guard blocks save  ✓

4. THREAD_LOAD_INVALID_RESOURCE occurs:
   Old code: _hide_loading_screen() → silent abort  ✗
   New code: _fallback_sync_load() → sync load succeeds → scene changes to BuildingLevel ✓

5. tree_changed fires with current_scene = BuildingLevel:
   _on_tree_changed():
     current_scene.scene_file_path == _startup_navigation_target ✓
     _navigation_ready = true
     _startup_navigation_target = ""
     → auto-saves BuildingLevel.tscn  ✓
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/autoload/scene_loader.gd` | `THREAD_LOAD_INVALID_RESOURCE` now calls `_fallback_sync_load()` instead of `_hide_loading_screen()` |
| `scripts/autoload/persist_manager.gd` | `_startup_navigation_target` guard; `_on_tree_changed()` auto-save with startup protection; `tree_changed` connected in `_connect_signals()` |
| `tests/unit/test_persist_manager.gd` | Five new startup-guard unit tests |
| `tests/unit/test_scene_loader.gd` | Two new INVALID_RESOURCE fallback unit tests |
| `docs/case-studies/issue-1456/` | This analysis + four game logs from all three failed sessions |
