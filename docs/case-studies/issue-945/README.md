# Case Study: Issue #945 — Update Tutorial Training Lines

## Overview

| Field | Value |
|---|---|
| Issue | [#945 — update строки обучения](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/945) |
| Pull Request | [#946 — Fix tutorial training lines](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/946) |
| Branch | `issue-945-2a1f269473d3` |
| Resolution Date | 2026-03-02 |
| Status | Fixed (both original requirements and post-review bugs) |

---

## Timeline / Sequence of Events

### 2026-03-02T15:25:22Z — Initial commit
`65fcdfa` — "Initial commit with task details": session started, research files created.

### 2026-03-02T15:35:49Z — First implementation
`3d3ae17` — "Fix tutorial training lines per issue #945": implemented all three requirements in `tutorial_level.gd` and `tests/unit/test_tutorial_level.gd`.

### 2026-03-02T15:39:05Z — Reverted bad commit
`94b6ca28` — Reverted "Initial commit with task details" (removed task-management boilerplate from the repo).

### 2026-03-02T15:39:14Z — AI session log posted
PR comment: solution draft log uploaded as Gist, AI session marked as finished.

### 2026-03-02T15:41:28Z — "Ready to merge" posted
Automated monitoring declared all CI checks passing with no conflicts.

### 2026-03-02T15:51:28Z — Owner feedback (Jhon-Crow)
Two bugs reported (see "Bugs Found" section below). Owner also requested this case study.

### 2026-03-02T15:52:12Z — New AI session started
PR converted back to draft mode, second session begins.

### 2026-03-02T16:00:41Z — Bugs fixed
`66add97` — "Fix hint overlap and update Lab level to match tutorial hint format (Issue #945)":
- Bug 1 (overlap) fixed in `tutorial_level.gd`
- Bug 2 (Lab level not updated) fixed in `labyrinth_level.gd`
- New tests added: `tests/unit/test_labyrinth_level.gd`

### 2026-03-02T16:00:50Z — All CI checks pass
Five GitHub Actions workflows all report `success` on the final commit.

---

## Issue Requirements

From [#945](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/945) (Russian, with translations):

1. **Reload hint timing** — "строка, объясняющая как произвести полную перезарядку (для любого оружия) должна появляться после 2 выстрелов"
   - The reload instruction line should appear only after 2 shots so the player experiences running out of ammo before being told how to reload.

2. **Unique colors per simultaneous hint** — "одновременно отображаемые строки должны быть разных цветов (подбери подходящие текущему стилю игры цвета)"
   - Each simultaneously visible hint line must have a distinct color matching the game's visual style.

3. **Red highlight on next button** — "кнопки, которые нужно нажать должны быть выделены красным (если действие многосоставное - красным должно быть выделено то, что нужно нажать сейчас)"
   - The next button to press is highlighted red; for multi-step actions (R→F→R reload), only the CURRENT next step is red, completed steps turn grey.

---

## Bugs Found During Review

### Bug 1: New hint line overlaps existing hint

**Reported by Jhon-Crow (2026-03-02T15:51:28Z):**
> "появляющаяся новая строка перекрывает уже существующую"
> ("the newly appearing [hint] line overlaps the already existing one")

**Root cause:**
`_dismiss_hint()` in `tutorial_level.gd` called `queue_free()` on the old label but did NOT set `label.visible = false` first. In Godot, `queue_free()` is deferred — the node is not immediately destroyed. It stays rendered for the rest of the current frame. If a new hint is added in the same frame (e.g., reload hint revealed immediately after fire-mode hint dismissed), the old label is still visible at its position while the new label renders at the same position, causing one-frame overlap that is visible to the player.

**Fix applied:**
Set `label.visible = false` immediately before calling `label.queue_free()` in `_dismiss_hint()` (both `tutorial_level.gd` and `labyrinth_level.gd`). The label is hidden synchronously so it cannot overlap the new hints even during the same frame.

```gdscript
# Before:
func _dismiss_hint(hint_key: String) -> void:
    var label: RichTextLabel = _hint_labels[hint_key]
    label.queue_free()   # deferred — still visible this frame!
    _hint_labels.erase(hint_key)

# After:
func _dismiss_hint(hint_key: String) -> void:
    var label: RichTextLabel = _hint_labels[hint_key]
    label.visible = false   # hide immediately — no overlap possible
    label.queue_free()
    _hint_labels.erase(hint_key)
```

**Key insight:** This is a general Godot pattern: when visually replacing one node with another, always set `visible = false` before `queue_free()` to avoid one-frame flicker or overlap.

### Bug 2: Laboratory level (Лаборатория) tutorial lines not updated

**Reported by Jhon-Crow (2026-03-02T15:51:28Z):**
> "строки обучения на карте Лаборатория не изменилось (во всей игре должны быть строки обучения одного формата)"
> ("the tutorial lines on the Laboratory map did not change; across the entire game, tutorial lines must be in the same format")

**Root cause:**
The first implementation session only updated `scripts/levels/tutorial_level.gd`. The `scripts/levels/labyrinth_level.gd` (the "Лаборатория" / Laboratory map) has its own parallel tutorial hint system that was NOT updated. Its `_add_tutorial_hint()` function was still creating plain `Label` nodes with the old single-yellow-color approach, with no BBCode and no 2-shot delay for reload.

**Fix applied:**
`labyrinth_level.gd` tutorial system was fully updated to mirror `tutorial_level.gd`:
- `Label.new()` → `RichTextLabel.new()` with `bbcode_enabled = true` and `fit_content = true`
- Unique color constants defined: green reload, orange grenade, purple bolt-cycle, yellow hammer-cock
- Reload/grenade BBCode text with `[color=#ff4444]` for next button, `[color=#888888]` for done steps
- `_tutorial_shots_fired` counter and `_tutorial_reload_hint_revealed` flag added
- `Fired` signal connected to `_on_tutorial_weapon_fired()` for 2-shot counting
- `ReloadSequenceProgress` signal connected for dynamic per-step highlighting
- `label.visible = false` added before `queue_free()` in `_dismiss_tutorial_hint()` (Bug 1 fix applied here too)

---

## Files Changed

| File | Change |
|---|---|
| `scripts/levels/tutorial_level.gd` | Main implementation: shot counter, `RichTextLabel`, colors, BBCode, overlap fix (+3 lines in bug-fix commit) |
| `scripts/levels/labyrinth_level.gd` | Full tutorial system overhaul to match `tutorial_level.gd` (+166 lines) |
| `tests/unit/test_tutorial_level.gd` | Tests for all 3 new behaviors + updated existing tests for 2-shot requirement |
| `tests/unit/test_labyrinth_level.gd` | New: full test coverage for Lab level tutorial (Issue #808 + #945) |

---

## Implementation Details

### Requirement 1: Reload hint after 2 shots

```gdscript
var _shots_fired: int = 0
var _reload_hint_revealed: bool = false

func _on_weapon_fired() -> void:
    if _reload_hint_revealed:
        return
    _shots_fired += 1
    if _shots_fired >= 2:
        _reload_hint_revealed = true
        _reveal_reload_hint()
```

The `Fired` signal is connected for each weapon type in `_connect_player_signals()`.

### Requirement 2: Unique colors per hint

```gdscript
const HINT_COLOR_FIRE_MODE   := Color(0.3, 0.9, 1.0, 1.0)   # Cyan
const HINT_COLOR_RELOAD      := Color(0.4, 1.0, 0.5, 1.0)   # Green
const HINT_COLOR_GRENADE     := Color(1.0, 0.65, 0.0, 1.0)  # Orange
const HINT_COLOR_BOLT_CYCLE  := Color(0.85, 0.6, 1.0, 1.0)  # Purple
const HINT_COLOR_HAMMER_COCK := Color(1.0, 0.8, 0.3, 1.0)   # Yellow
```

Applied via `label.add_theme_color_override("default_color", _get_hint_color(hint_key))`.

### Requirement 3: Red highlight on next button

Standard R→F→R reload at step 1:
```
[color=#ff4444][R][/color] [color=#888888][F] [R][/color] Перезарядись
```

At step 2 (R pressed, F next):
```
[color=#888888][R][/color] [color=#ff4444][F][/color] [color=#888888][R][/color] Перезарядись
```

Dynamic updates via `ReloadSequenceProgress` signal connection.

---

## CI / Test Results (Final)

All 5 GitHub Actions workflows passed on commit `66add97f`:

| Workflow | Result |
|---|---|
| C# Build Validation | ✅ success |
| Gameplay Critical Systems Validation | ✅ success |
| Architecture Best Practices Check | ✅ success |
| C# and GDScript Interoperability Check | ✅ success |
| Run GUT Tests | ✅ success |

**GUT test suite summary:**
- Scripts: 85
- Tests: 3315 total (3164 passing, 61 failing, 90 pending/risky)
- The 61 failing tests are pre-existing failures unrelated to this issue (same failures existed before this PR; CI workflow treats them as acceptable)
- All new tests for Issue #945 (Tutorial level and Lab level) pass

---

## Key Lessons / Root Causes

1. **Godot `queue_free()` is deferred** — nodes are not immediately removed. Any visual replacement must set `visible = false` synchronously to avoid one-frame overlap.

2. **Cross-level consistency** — when a UI system is duplicated across multiple level scripts, all copies must be updated together. The lack of a shared base class or autoload for the tutorial hint system meant the Lab level was missed in the first pass. Consider refactoring into a shared `TutorialHintManager` autoload to prevent this class of bug in the future.

3. **`RichTextLabel` vs `Label`** — `RichTextLabel` with `fit_content = true` and `scroll_active = false` is the correct Godot node for BBCode-formatted text in tutorial overlays. The `fit_content` property requires `custom_minimum_size` to also be set for proper sizing.

---

## Possible Future Improvements

- Refactor tutorial hint logic into a shared autoload or base class to avoid duplicating the same system in each level script.
- Add integration tests that run in a real Godot scene to verify visual positioning (currently unit tests use mock objects and cannot test `label.position`).
- Consider making hint colors configurable via a resource/theme rather than hardcoded constants.
