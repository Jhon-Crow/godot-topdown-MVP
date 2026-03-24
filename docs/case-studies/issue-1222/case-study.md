# Case Study: Issue #1222 — Pause Menu Buttons Not Clickable

## Summary

**Issue:** [#1222](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1222)
**PR:** [#1223](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1223)
**Branch:** `issue-1222-9e69d2b70117`
**Date:** 2026-03-20
**Status:** Fixed

### Issue Description (translated from Russian)

> "Nothing can be pressed in the pause menu (not even the back button). The problem appeared after merging one of today's branches (check). Add tests for the future."

---

## Timeline / Sequence of Events

| Time (UTC) | Event |
|------------|-------|
| ~04:09 | PR #1181 merged — pedestal icon updates |
| ~04:27 | PR #1191 merged — navmesh visibility toggle in Experimental menu |
| ~05:16 | **PR #1190 merged** — `fix(#1186): fix AI state disabling, add IDLE toggle, **move Optimization into Performance**` — renames `OptimizationButton` → `PerformanceButton` in SettingsMenu |
| ~05:32 | PR #1199 merged — add icons to pause menu buttons |
| ~05:39 | PR #1203 merged — honor IDLE disable at enemy spawn |
| ~06:57 | **PR #1201 merged** — `fix(#1200): add hover highlight and full-card label to settings rows` — **adds `optimization_button.tooltip_text = "Optimization"` to `settings_menu.gd`**, referencing a variable that PR #1190 already removed |
| ~07:03 | PR #1197 merged — Laser Sight unlock |
| ~07:06 | PR #1179 merged — armor overlays follow player movement |
| ~20:39 | PR #1210 merged — cold blue ceiling lights on Laboratory map |
| ~20:40 | **Bug reported** — Issue #1222 opened |

---

## Root Cause Analysis

### The Regression Chain

**Step 1 — PR #1190** renamed `OptimizationButton`/`optimization_button` to `PerformanceButton`/`performance_button` in `scripts/ui/settings_menu.gd`:

```gdscript
# BEFORE (PR #1186 original):
@onready var optimization_button: Button = $MenuContainer/.../OptimizationButton

# AFTER PR #1190:
@onready var performance_button: Button = $MenuContainer/.../PerformanceButton
```

**Step 2 — PR #1201** added tooltip setup to `settings_menu.gd`'s `_ready()`:

```gdscript
# Added by PR #1201 (Issue #1200):
optimization_button.tooltip_text = "Optimization"   # ← references old, removed variable!
```

This introduced a reference to `optimization_button` which is no longer declared anywhere in `settings_menu.gd`.

### Why This Breaks the Pause Menu

In GDScript 4, using an undeclared identifier causes a **compile-time parse error**, not a runtime error. This means `scripts/ui/settings_menu.gd` **fails to parse entirely**.

`scenes/ui/SettingsMenu.tscn` references `settings_menu.gd` as its script, so the scene also becomes unloadable.

`scripts/ui/pause_menu.gd` uses `preload()` to load `SettingsMenu.tscn` at line 68:

```gdscript
settings_menu_scene = preload("res://scenes/ui/SettingsMenu.tscn")
```

In GDScript, **`preload()` is evaluated at compile time** (parse phase). If the preloaded resource fails to load, the calling script (`pause_menu.gd`) itself **fails to parse and cannot be attached** to the PauseMenu node.

The result: `PauseMenu` node has no working script → all button signal connections are never made → **no button in the pause menu responds to clicks**.

This explains exactly the reported symptom: "nothing can be pressed (not even the back button)."

### Evidence

1. `settings_menu.gd` line 49 references `optimization_button` which is `null` (not declared)
2. `pause_menu.gd` line 68 uses `preload("res://scenes/ui/SettingsMenu.tscn")`
3. `SettingsMenu.tscn` references `settings_menu.gd` as its script
4. GDScript parse-time preload failure → caller script fails to parse → PauseMenu has no script

---

## Fix

Remove the stale `optimization_button.tooltip_text = "Optimization"` line from `settings_menu.gd`'s `_ready()` and replace it with the correct `performance_button.tooltip_text = "Performance"` (matching what the Performance button actually does).

**File:** `scripts/ui/settings_menu.gd`, line 49

```gdscript
# WRONG (introduced by PR #1201):
optimization_button.tooltip_text = "Optimization"

# FIXED:
performance_button.tooltip_text = "Performance"
```

---

## Prevention

1. **Test added:** `tests/unit/test_pause_menu.gd` — verifies that `PauseMenu.tscn` and `SettingsMenu.tscn` can be instantiated without errors, and that all pause menu buttons have their `pressed` signals connected.
2. **Root lesson:** When a variable/node is renamed in one PR, all other pending/in-flight PRs that reference the old name must be updated simultaneously. A CI lint step that checks for undeclared GDScript variables would catch this automatically.

---

## Related PRs

| PR | Title | Relation |
|----|-------|----------|
| #1190 | fix(#1186): move Optimization into Performance | Renamed `optimization_button` → `performance_button` |
| #1201 | fix(#1200): add hover highlight and full-card label | Reintroduced old name `optimization_button` — **root cause** |
| #1223 | fix(#1222): restore pause menu by fixing stale optimization_button reference | **This fix** |
