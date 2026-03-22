# Case Study: Issue #1344 — Remove Background Rectangle from Roguelike Treasure Pedestal

## Summary

**Issue:** The roguelike treasure room pedestal displayed a visible background rectangle — a fake-3D base platform built from multiple ColorRect layers — behind the floating item icon. The user requested its removal ("убери фоновый прямоугольник").

**First fix attempt (PR #1345, commit `bcd69531`):** An AI-generated fix removed the entire pedestal visual AND critical functional code, breaking the game. The owner reported two problems: (1) the entire pedestal was deleted, not just the rectangle, and (2) the game crashed when touching the pedestal.

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| Issue #1180 | Fake-3D volumetric pedestal base added (4 ColorRect layers: shadow, side, top, front) |
| Issue #1299 | Large background square removed; glow_ring shrunk to a thin bar; item now floats |
| Issue #1323 | Crash fix: tween binding changed from `create_tween()` to `pedestal.create_tween()`, `_reconnect_weapon_signals()` added |
| 2026-03-22 ~15:25 | PR #1345 created with commit `bcd69531` — removed glow_ring, base layers, AND also removed `_reconnect_weapon_signals()`, changed `pedestal.create_tween()` back to `create_tween()` |
| 2026-03-22 ~16:40 | Owner (Jhon-Crow) reports: "удалён весь пьедестал, а не прямоугольник на заднем фоне" + game crashes on pedestal touch |
| `game_log_20260322_193750.txt` | Game log shows treasure room spawns successfully at 19:39:10, then log abruptly ends at line 4949 — game crashed |

---

## Root Cause Analysis

### Original Issue (#1344)

The pedestal in `_spawn_treasure_pedestal()` (`scripts/levels/roguelike_level.gd`) was built with these visible rectangular elements:

1. **`glow_ring`** — a thin golden bar on the floor (`ColorRect`, ~105×17 px, semi-transparent gold)
2. **`base_shadow`** — bottom shadow layer shifted down-right (~72×24 px, dark brown)
3. **`base_side`** — right side face (~4×24 px, medium brown)
4. **`base_top`** — top highlight strip (~72×4 px, light gold)
5. **`base`** — front face (~72×20 px, warm gold/wood — `PEDESTAL_BASE_COLOR`)

Together these formed the visible "background rectangle" shown in the issue screenshot.

### First Fix Regression (commit `bcd69531`)

The AI fix correctly identified the visual elements to remove, BUT also introduced two critical regressions by removing unrelated functional code:

**Regression 1 — `_reconnect_weapon_signals()` deleted:**
The function and its call site were removed. This function reconnects `AmmoChanged`/`MagazinesChanged`/`ShotFired` signal handlers after a weapon swap on the pedestal (Issue #1323 fix). Without it, the UI loses sync with the weapon after pickup.

**Regression 2 — Tween binding reverted:**
```gdscript
# CORRECT (Issue #1323 fix — tween dies with pedestal):
var float_tween := pedestal.create_tween()

# BROKEN (reverted to — tween survives pedestal.queue_free()):
var float_tween := create_tween()
```
When the player picks up the item, `pedestal.queue_free()` frees the pedestal, but the level-bound tween keeps running and tries to animate the freed `float_node` — causing a segfault.

### Why the AI removed too much

The "Initial commit with task details" (commit `0a35de1a`) bundled unrelated code changes from a previous issue (#1323) into the branch setup. The subsequent fix commit then partially reverted these, removing functional code that should have been preserved.

---

## Correct Fix

The correct fix is minimal — remove ONLY the visual rectangle elements:

1. Remove `glow_ring` ColorRect (6 lines)
2. Remove all 4 base platform ColorRects: `base_shadow`, `base_side`, `base_top`, `base` (24 lines)
3. Remove the unused `PEDESTAL_BASE_COLOR` constant (2 lines)

**Total: -32 lines, 0 functional changes.**

Everything else remains untouched:
- `_reconnect_weapon_signals()` — weapon signal reconnection after swap
- `pedestal.create_tween()` — tween bound to pedestal lifetime
- Item icon, float animation, labels, collision, pickup logic

---

## Lessons Learned

1. **Minimal changes:** When removing a visual element, only remove the visual code. Do not touch unrelated functional code (signal handlers, tween bindings, etc.).
2. **Understand commit history:** The pedestal had a complex history across Issues #1180, #1299, and #1323. Each issue added or fixed specific functionality. Understanding this history is critical before making changes.
3. **Bundled branch setup changes are dangerous:** If a branch setup commit includes unrelated code changes, those changes can propagate into the fix and cause regressions.
4. **Test pedestal interaction, not just appearance:** The crash only manifested when the player touched the pedestal — purely visual testing would not have caught the tween/signal regressions.

---

## Referenced Files

- `scripts/levels/roguelike_level.gd` — pedestal creation in `_spawn_treasure_pedestal()` (~line 1438)
- `Scripts/Characters/Player.cs` — weapon equip in `ApplySelectedWeaponFromGameManager()` (~line 2769)

## Attached Logs

- `game_log_20260322_193750.txt` — game log from owner's test showing crash after treasure room entry
