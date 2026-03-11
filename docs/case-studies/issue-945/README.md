# Case Study: Issue #945 — Update Tutorial Training Lines

## Overview

| Field | Value |
|---|---|
| Issue | [#945 — update строки обучения](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/945) |
| Pull Request | [#946 — Fix tutorial training lines](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/946) |
| Branch | `issue-945-2a1f269473d3` |
| Resolution Date | 2026-03-02 (ongoing — 3rd review round 2026-03-07) |
| Status | Fixed (original requirements + 2nd review bugs + 3rd review bugs) |

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

## Third Review Round Bugs (2026-03-02 — Fixed 2026-03-07)

Owner `Jhon-Crow` posted 10 new bugs after the second session. All were fixed in a third session.

### Bug 3rd#1: Hint spacing still too small (overlap)

**Fix:** Increased `HINT_SPACING` from 50 to 60 in both `tutorial_level.gd` and `labyrinth_level.gd`.

### Bug 3rd#2: Shotgun bolt-ready hint not appearing after 1st shot

**Root cause:** The `ShotFired` signal was used as a fallback for weapons that do not emit `Fired`, but the connection was missing for shotgun.

**Fix:** Added explicit `ShotFired` signal fallback in `_connect_weapon_fired_signal()`.

### Bug 3rd#3: Red highlight does not change for most multi-step operations

**Root cause:** Sniper bolt-cycle hint was a static string. The `BoltStepChanged` signal was not connected for the bolt-cycle hint.

**Fix:** Added `_on_sniper_bolt_step_changed()` handler that calls `_build_sniper_bolt_hint_bbcode(step)` and overwrites the hint text in-place each time a bolt step completes.

### Bug 3rd#4: Sniper bolt-action shown as single combined action

**Before:** `[color=#ff4444][←↓↑→][/color] Передёрни затвор` — all 4 arrows in one bracket.

**After:** `[color=#ff4444][←][/color] [color=#888888][↓] [↑] [→][/color] Передёрни затвор` — 4 separate steps, current step red.

**Fix:** Added `_build_sniper_bolt_hint_bbcode(step: int) -> String` helper that renders each of the 4 directions as its own bracket `[←]`, `[↓]`, `[↑]`, `[→]`.

### Bug 3rd#5: Grenade tutorial shown simultaneously with reload (should be after)

**Root cause:** The original Issue #808 implementation intentionally showed reload and grenade hints simultaneously. The 3rd review reversed this requirement.

**Fix:** Removed grenade hint from `_add_reload_hints()` (and from the bolt-cycle path and scope path). Grenade hint now added in `_on_player_reload_completed()` (and after `BoltStepChanged` completes, after scope training ends) only when the step advances to `THROW_GRENADE`.

### Bug 3rd#6: M16 should show fire-mode switch hint (B) after reload

**Fix:** Added a check in `_on_player_reload_completed()`: if weapon is `_has_assault_rifle` but NOT `_has_ak_gl`, show `HINT_FIRE_MODE` with `[B]` key.

### Bug 3rd#7: Shotgun reload hint count doesn't update and hint doesn't dismiss

**Root cause:** The `ShellCountChanged` signal was not connected to update the hint text. The hint was also not dismissed when reload completed.

**Fix:**
- Connected `ShellCountChanged` → `_on_shell_count_changed()` which calls `_build_shotgun_reload_hint_bbcode()` and updates `HINT_BOLT_CYCLE` in-place.
- `_build_shotgun_reload_hint_bbcode()` computes `shells_needed = capacity - current_ammo` and renders `xN`.
- Added `_dismiss_hint(HINT_BOLT_CYCLE)` in `_on_player_reload_completed()` for shotgun.

### Bug 3rd#8: Revolver hammer-cock hint disappears after reload (should persist)

**Root cause:** `_on_player_reload_completed()` called `_dismiss_hint(HINT_HAMMER_COCK)`.

**Fix:** Removed that call. Hammer-cock hint is now only dismissed by `_on_revolver_hammer_cocked()`.

### Bug 3rd#9: Grenade tutorial shown even if player has no grenades

**Fix:** Added `_player_has_grenades() -> bool` helper. Grenade hint only added when this returns true. If player has no grenades and the step advances to `THROW_GRENADE`, the tutorial auto-completes.

### Bug 3rd#10: AK should show underbarrel grenade launcher hint (RMB) after reload

**Fix:**
- Added `_has_ak_gl: bool = false` flag, set in `_connect_player_signals()` when AKGL weapon detected.
- Added `const HINT_GRENADE_LAUNCHER := "grenade_launcher"` and `HINT_COLOR_GRENADE_LAUNCHER`.
- Added `_ak_gl_has_round_loaded() -> bool` helper.
- In `_on_player_reload_completed()`: if `_has_ak_gl and _ak_gl_has_round_loaded()`, show `HINT_GRENADE_LAUNCHER` with `[ПКМ]` key. M16 fire-mode hint is only shown for `_has_assault_rifle and not _has_ak_gl`.

---

## Files Changed (All Rounds)

| File | Change |
|---|---|
| `scripts/levels/tutorial_level.gd` | Round 1: shot counter, colors, BBCode. Round 2: overlap fix. Round 3: 10 bug fixes |
| `scripts/levels/labyrinth_level.gd` | Round 2: full overhaul to match tutorial. Round 3: 10 bug fixes mirrored |
| `tests/unit/test_tutorial_level.gd` | Round 1: all new tests. Round 2: updated for fix #1-#5. Round 3: 14 new tests + updated existing |
| `tests/unit/test_labyrinth_level.gd` | Round 2: new file, full coverage. Round 3: 15 new tests + updated 10 existing |

---

---

## Sixth Review Round — Root Cause Analysis of AK/Revolver Tutorial Lines Missing on Labyrinth Map

### Symptom

After round 5, @Jhon-Crow reported:
> "строки обучения для револьвера и АК не появляются на карте Лабиринт, так же у них сломался счётчик."
> (Tutorial lines for Revolver and AK do not appear on the Labyrinth map; their counters are also broken.)

### Timeline Reconstruction

1. **Round 4 fix (commit `280d48aa`)**: Added AKGL and Revolver weapon-setup code to `labyrinth_level.gd`'s `_setup_selected_weapon()` function. The function already had an early-return guard for M16, Shotgun, etc. to avoid double-equipping when the C# Player had already set up the weapon; however the guard's `weapon_names` dictionary did **not** include `"ak_gl"` or `"revolver"`.

2. **Round 5 fix (commit `11a624df`)**: Fixed AKGL's SWITCH_FIRE_MODE stuck-step in `tutorial_level.gd`, and added `ReloadStateChanged` connection for Revolver. **Did not fix the duplicate-weapon issue** — owner still reported missing tutorial lines.

### Root Cause

#### Godot C#/GDScript _ready() execution order

In Godot 4 the C# `Player` node is a child of the `LabyrinthLevel` scene. Children's `_ready()` runs **before** the parent's `_ready()`. Therefore:

1. **`Player.cs _Ready()`** executes first:
   - Calls `ApplySelectedWeaponFromGameManager()`.
   - That method correctly swaps the default MakarovPM for AKGL/Revolver using `RemoveChild()` + `AddChild()`.
   - Sets `CurrentWeapon` to the newly created node (e.g. the `AKGL` instance).

2. **`labyrinth_level.gd _ready()`** executes second:
   - Calls `_setup_player_tracking()` → `_setup_selected_weapon()`.
   - Because `"ak_gl"` was **not** in `weapon_names`, the "already equipped by C# Player" early-return check was **skipped**.
   - The function instantiated a **second** AKGL, added it to the player with `_player.add_child(akgl)`.
   - Godot auto-renamed the duplicate to `"AKGL@2"` (or similar) to avoid name collisions.
   - `_player.EquipWeapon(akgl)` then updated `CurrentWeapon` to point to this duplicate.

3. **Back in `_setup_player_tracking()`**, `get_node_or_null("AKGL")` returned the **first** AKGL (the one created by C# Player, with the canonical name `"AKGL"`).
   - All tutorial signals (`Fired`, `AmmoChanged`, etc.) were connected to this **idle first node**.
   - The player actually fired using the **duplicate second node** (`CurrentWeapon`).
   - Since the duplicate emitted no connected signals, the shot counter never incremented, tutorial hints never appeared, and the ammo counter never updated.

#### Why only AKGL and Revolver were affected

All other weapons (Shotgun, MiniUzi, SilencedPistol, SniperRifle, AssaultRifle) were listed in `weapon_names`, so the early-return check worked for them. AKGL and Revolver were added to `_setup_selected_weapon()` in round 4 but were **accidentally omitted** from the `weapon_names` guard dictionary.

### Fix Applied (Round 6)

**File: `scripts/levels/labyrinth_level.gd`**

1. **Added `"ak_gl": "AKGL"` and `"revolver": "Revolver"` to `weapon_names`** in `_setup_selected_weapon()`.
   Now the early-return check fires for all seven weapon types, preventing duplicate nodes.

2. **Added `CartridgeInserted` signal connection** for Revolver (in the `"Revolver"` branch of the `match weapon.name:` block in `_setup_player_tracking()`).
   `tutorial_level.gd` already had this; `labyrinth_level.gd` was missing it. Without it the ammo counter froze mid-reload (cartridges loaded one-by-one) because `AmmoChanged` fires only at full-reload completion, not per cartridge.

3. **Added `_on_revolver_cartridge_inserted()` handler** to `labyrinth_level.gd`, mirroring the handler in `tutorial_level.gd`.

**File: `tests/unit/test_labyrinth_level.gd`**

- Updated header to document round 6 fixes and root cause.

---

## Possible Future Improvements

- Refactor tutorial hint logic into a shared autoload or base class to avoid duplicating the same system in each level script.
- Add integration tests that run in a real Godot scene to verify visual positioning (currently unit tests use mock objects and cannot test `label.position`).
- Consider making hint colors configurable via a resource/theme rather than hardcoded constants.
- Add a shared helper for `_setup_selected_weapon()` so all level scripts stay in sync when new weapons are added.
- Add a unit test that verifies the `weapon_names` dictionary includes all selectable weapons (prevents silent regressions like this round 6 bug).
