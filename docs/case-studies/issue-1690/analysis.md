# Case Study: Issue #1690 — Armory Button Gold Highlight Persists After Apply on Score Screen

## Overview

**Issue**: The armory button on the score screen retains its gold/highlighted style ("★ Armory — Items Available!") even after the player opens the armory, unlocks all available items, and presses **Apply** to close it.

**Expected behavior**: After pressing Apply and leaving no remaining items to unlock, the button should revert to plain "Armory" text with no gold styling.

**Affected levels** (at the time the issue was filed): SewerLevel, FactoryLevel, Labyrinth2Level
**Previously fixed level**: BuildingLevel, and all others (beach, castle, city, decadence, docks, labyrinth, railway_station, revolver, test_tier, winter_forest)

---

## Timeline of Events

### 2026-03-17 — First partial fix (commit `99a2984a`)
- Added `apply_pressed_from_score_screen.connect(...)` to ~11 level scripts.
- Three levels were **missed**: `sewer_level.gd`, `factory_level.gd`, `labyrinth2_level.gd`.

### 2026-03-26 — Gold shine overlay fix (commit `731a00e2`)
- Added `shine_overlay.queue_free()` inside `_remove_armory_button_gold_style()` for all 14 level scripts.
- Also added `back_pressed` callback to the three levels that were missing it (`sewer`, `factory`, `labyrinth2`).
- Still missing: `apply_pressed_from_score_screen` for those same three levels.

### 2026-03-28 — PR #1703 (our fix, commit `aaca6120`)
- Added `apply_pressed_from_score_screen.connect(...)` to `sewer_level.gd`, `factory_level.gd`, and `labyrinth2_level.gd`.
- Brings all 14 active level scripts into parity.

### 2026-03-28 — PR #1703 (additional fix, commit `ce771328`)
- Fixed `LevelInitFallback.RemoveArmoryButtonGoldStyle()` in C# to also remove `ArmoryGoldShineOverlay`.
- Root cause: when GDScript `_ready()` fails to execute (Godot 4.3 tokenization bug), `LevelInitFallback` handles the score screen. Its `RemoveArmoryButtonGoldStyle()` removed text/color/stylebox overrides but missed the `ColorRect` child named `ArmoryGoldShineOverlay`, leaving the shine visible even after all items were unlocked.
- Confirmed from `game_log_20260328_184635.txt` line 1017: `GDScript _ready() did NOT execute — performing C# fallback initialization`

### 2026-03-28 18:00 — Tester report #1 (`game_log_20260328_180006.txt`)
- **Build**: `I:/Загрузки/godot exe/UNLOCKES/Godot-Top-Down-Template.exe` (OLD binary, predates `99a2984a`)
- **Scenario**: BuildingLevel completed, armory opened, items unlocked, Apply pressed.
- **Observation**: Gold highlight persisted.
- **Root cause at the time**: The `UNLOCKES` build was compiled before `apply_pressed_from_score_screen` was connected in `building_level.gd`. The signal fired in the armory but there was no listener in the level script.

### 2026-03-28 18:22 — Tester report #2 (`game_log_20260328_182254.txt`)
- **Build**: Same OLD binary (`I:/Загрузки/godot exe/UNLOCKES/Godot-Top-Down-Treatment.exe`).
- **Scenario**:
  1. Session starts at **LabyrinthLevel** (S rank, score 23130).
  2. Armory opened from LabyrinthLevel score screen (line 1003).
  3. Items unlocked: mini_uzi, Recoil Compensator, Combat Disposition.
  4. mini_uzi selected as weapon (loadout change → Apply button enabled).
  5. Apply pressed → in the OLD binary, `labyrinth_level.gd` did NOT have `apply_pressed_from_score_screen` connected. Gold highlight on LabyrinthLevel score screen was NOT removed.
  6. Player presses "Next Level" → transitions to **BuildingLevel**.
  7. BuildingLevel completed (S rank), NEW unlock conditions met (shotgun, silenced_pistol, Extended Magazine, Frag Grenade).
  8. Armory opened at BuildingLevel score screen.
  9. All 4 new items unlocked, shotgun selected as weapon.
  10. Apply pressed.
- **Observation**: Gold highlight persisted on BuildingLevel score screen.
- **Root cause**: In the OLD binary, `building_level.gd` did NOT have `apply_pressed_from_score_screen` connected at the time the binary was compiled. (That connection was added in commit `99a2984a` on March 17, but the `UNLOCKES` binary was compiled before that date.)

### 2026-03-28 18:46 — Tester report #3 (`game_log_20260328_184635.txt`)
- **Build**: Same OLD binary (`I:/Загрузки/godot exe/UNLOCKES/Godot-Top-Down-Template.exe`), "Build info: not available (build_info.cfg not found)".
- **Scenario**:
  1. All progress cleared and "All weapons unlocked" disabled in experimental settings (lines 553-558).
  2. Game restarted — starting fresh.
  3. BuildingLevel played and completed with rank A+, score 43601.
  4. Items unlocked in armory: shotgun, Frag Grenade, Extended Magazine, Combat Disposition.
  5. Log ends at line 2526 right after last item unlock (18:47:50).
  6. Tester reported: "не исправлено (возможно дело в прогрессбарах?)" — "not fixed, possibly progress bars"
- **Key finding**: `[LevelInitFallback] GDScript _ready() did NOT execute — performing C# fallback initialization` (line 1017)
  - GDScript `building_level.gd` `_ready()` did NOT run
  - Score screen was created by `LevelInitFallback.cs` (C# code)
  - When Back/Apply is triggered, `LevelInitFallback.RemoveArmoryButtonGoldStyle()` is called
  - But that C# method **did NOT remove `ArmoryGoldShineOverlay`** — only text/color/stylebox overrides
  - This is a separate bug from the GDScript signal-connection issue
- **New root cause**: `LevelInitFallback.RemoveArmoryButtonGoldStyle()` was missing `shineOverlay.QueueFree()` call.
  This is fixed in commit `ce771328` (PR #1703).

---

## Root Cause Analysis

### Primary Root Cause: Missing Signal Connection

The armory menu emits `apply_pressed_from_score_screen` when the player presses **Apply** with a loadout change while `opened_from_score_screen = true`. Each level script is responsible for connecting to this signal in its `_on_armory_button_pressed()` function and calling `_remove_armory_button_gold_style()` when no more items remain available.

Three level scripts — `sewer_level.gd`, `factory_level.gd`, `labyrinth2_level.gd` — were missing this connection through multiple rounds of fixes, finally resolved in PR #1703.

### Secondary Root Cause: Missing Shine Overlay Removal in C# Path

When GDScript `_ready()` fails to execute (due to Godot 4.3 binary tokenization bug, godotengine/godot#94150), `LevelInitFallback.cs` handles the entire score screen. Its `RemoveArmoryButtonGoldStyle()` method removed the text/color/stylebox overrides from the armory button but **did not remove the `ArmoryGoldShineOverlay` ColorRect child**. This caused the gold shine animation to persist even after all items were unlocked.

Confirmed by log line 1017 in `game_log_20260328_184635.txt`:
```
[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
```

Fixed in commit `ce771328` by adding:
```csharp
var shineOverlay = armoryBtn.FindChild("ArmoryGoldShineOverlay", true, false);
shineOverlay?.QueueFree();
```

### Tertiary Root Cause: Old Test Binary

Both tester-provided logs were captured using a binary compiled from the `UNLOCKES` build folder (`I:/Загрузки/godot exe/UNLOCKES/`). This binary predates the `apply_pressed_from_score_screen` connection added to `building_level.gd` (commit `99a2984a`, March 17, 2026) and to `labyrinth_level.gd` (commit `731a00e2`, March 26, 2026).

**Evidence**:
- Both logs reference identical executable path: `I:/Загрузки/godot exe/UNLOCKES/Godot-Top-Down-Template.exe`
- The second log (March 28) still uses the same old binary — no rebuild occurred between test runs
- Log 2 shows `UnlockManager` skipping corrupt save entries for `silenced_pistol` and `ak_gl` — same behavior as log 1, confirming same build

### Why `apply_pressed_from_score_screen` is Only Emitted on Loadout Change

In `armory_menu.gd`, the signal is only emitted when `weapon_changed OR grenade_changed OR active_item_changed`:

```gdscript
# armory_menu.gd:1272
if weapon_changed or grenade_changed or active_item_changed:
    if opened_from_score_screen:
        apply_pressed_from_score_screen.emit()
        queue_free()
```

If the player unlocks items but keeps their existing loadout, the Apply button is **disabled** (`_update_apply_button_state()` uses `_has_pending_changes()`). The player must press **Back** instead, which triggers the `back_pressed` callback — also checking `has_any_available_unlock()`.

This design is correct: if no loadout change was made, Apply is grayed out, and Back correctly removes the gold if nothing is left to unlock.

---

## Signal Flow (Fixed Code)

```
[Score Screen] → [Player clicks gold Armory button]
    ↓
_on_armory_button_pressed() in level script
    ↓
armory_menu.back_pressed.connect(func():
    armory_menu.queue_free()
    if not unlock_manager.has_any_available_unlock():
        _remove_armory_button_gold_style()   ← clears gold on Back
)
armory_menu.apply_pressed_from_score_screen.connect(func():
    if not unlock_manager.has_any_available_unlock():
        _remove_armory_button_gold_style()   ← clears gold on Apply
)
    ↓
[Player opens armory, unlocks items, presses Apply or Back]
    ↓
Signal fires → callback executes → gold removed if no items remain
```

---

## Evidence from Logs

### Log 1 (`game_log_20260328_180006.txt`)
- 540KB, 3864 lines
- Records a full play session: LabyrinthLevel → BuildingLevel → factory/sewer levels
- Key event: BuildingLevel condition met, items available → armory opened → items unlocked → Apply pressed (no confirmation in log of gold removal — signal was unconnected in old binary)
- The log does NOT contain any line confirming `_remove_armory_button_gold_style` was called

### Log 2 (`game_log_20260328_182254.txt`)
- 208KB, 2443 lines
- Records: LabyrinthLevel (S rank) → BuildingLevel (S rank)
- LabyrinthLevel armory session: mini_uzi + Recoil Compensator + Combat Disposition unlocked, mini_uzi selected → Apply pressed
- BuildingLevel armory session: shotgun + silenced_pistol + Extended Magazine + Frag Grenade unlocked, shotgun selected
- Both sessions end without evidence of gold style removal — confirming the old binary's signal connections were absent

---

## What PR #1703 Fixes (Updated)

| Level Script | `back_pressed` connected | `apply_pressed_from_score_screen` connected |
|---|---|---|
| `beach_level.gd` | ✅ | ✅ |
| `building_level.gd` | ✅ | ✅ |
| `castle_level.gd` | ✅ | ✅ |
| `city_level.gd` | ✅ | ✅ |
| `decadence_level.gd` | ✅ | ✅ |
| `docks_level.gd` | ✅ | ✅ |
| `labyrinth_level.gd` | ✅ | ✅ |
| `railway_station_level.gd` | ✅ | ✅ |
| `revolver_level.gd` | ✅ | ✅ |
| `test_tier.gd` | ✅ | ✅ |
| `winter_forest_level.gd` | ✅ | ✅ |
| **`factory_level.gd`** | ✅ (added 731a00e2) | **✅ (added by PR #1703)** |
| **`labyrinth2_level.gd`** | ✅ (added 731a00e2) | **✅ (added by PR #1703)** |
| **`sewer_level.gd`** | ✅ (added 731a00e2) | **✅ (added by PR #1703)** |

### C# Fallback Path (LevelInitFallback.cs)

| Method | `ArmoryGoldShineOverlay` removal |
|---|---|
| `RemoveArmoryButtonGoldStyle()` | **✅ Fixed in commit `ce771328` (PR #1703)** |

---

## Proposed Solutions & Recommendations

### 1. Immediate Action (Done — PR #1703)
Add `apply_pressed_from_score_screen.connect(...)` to `sewer_level.gd`, `factory_level.gd`, and `labyrinth2_level.gd`.

### 2. For Testing
The tester should rebuild the game from the **current `main` branch** (or the `issue-1690-fb619a93c54d` branch) to verify the fix. The `UNLOCKES` binary predates multiple fixes and will continue to exhibit the bug.

```
# To rebuild from main:
git checkout main
git pull origin main
# Open project in Godot 4.3, export/run from there
```

### 3. Future Prevention
Consider adding a regression test that parses all `*_level.gd` files and asserts both `back_pressed` and `apply_pressed_from_score_screen` are connected in `_on_armory_button_pressed()`. The existing test in `tests/unit/test_armory_score_screen_highlight.gd` already includes source-file regression guards for the three fixed files.

### 4. Architectural Improvement (Future)
The current design requires each level script to manually connect both signals. A more robust approach would be to centralize this logic in a shared base class or `ScoreScreenManager` autoload, so that new levels automatically inherit the gold-removal behavior without needing per-level boilerplate.

---

## Files in This Case Study

| File | Description |
|---|---|
| `analysis.md` | This document |

### Game Logs (not committed — excluded by .gitignore)

The tester-provided logs are attached to the pull request comments and available via GitHub:
- **Log 1** (540KB) — attached to [PR #1703 comment by Jhon-Crow, 2026-03-28 15:03](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1703#issuecomment-4148225196): `game_log_20260328_180006.txt`
- **Log 2** (208KB) — attached to [PR #1703 comment by Jhon-Crow, 2026-03-28 15:25](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1703#issuecomment-4148259764): `game_log_20260328_182254.txt`
- **Log 3** (213KB) — attached to [PR #1703 comment by Jhon-Crow, 2026-03-28 15:49](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1703#issuecomment-4148336478): `game_log_20260328_184635.txt`
