# Case Study: Issue #830 — Revolver-Optimized Level Map

## Overview

**Issue:** [#830](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/830) — Create a level map designed for revolver gameplay
**Pull Request:** [#870](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/870)
**Status:** Fixed (second iteration after owner feedback)

---

## Issue Requirements

The issue requested a new level map with three constraints:

1. **Partial reload opportunities** — player must be able to reload at least partially
2. **Enemy line penetration** — sections where shooting through multiple enemies is possible
3. **Max 5 enemies in close combat** — player should never face more than 5 enemies simultaneously in one viewport/combat zone

Additionally (from owner feedback on PR #870):
- The map must allow **any weapon** to be selected, not force the revolver
- The map should be **named after its visual shape**, not after the weapon
- Enemy zones must **not have direct line-of-sight to each other** or to the spawn zone

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 2026-02-24 ~14:00 | Initial solution implemented: `RevolverLevel.tscn` + `revolver_level.gd` |
| 2026-02-24 14:07 | First draft marked "Ready to merge" — all CI passed |
| 2026-02-24 15:53 | Owner (Jhon-Crow) tested in game, found critical bugs (see below) |
| 2026-02-24 15:53 | Owner attached `game_log_20260224_184659.txt` as evidence |
| 2026-02-24 20:33 | Second work session started, PR converted to draft |
| 2026-02-24 ~21:00 | Second iteration with redesigned map and weapon fix |

---

## Root Cause Analysis

### Bug 1: All enemies detect player immediately at spawn (critical)

**Symptom:** All 6 corridor enemies entered COMBAT/PURSUING state within 3 seconds of level load.

**Evidence from game_log_20260224_184659.txt:**
```
[18:47:10] [ENEMY] [CorridorEnemy5] State: IDLE -> COMBAT
[18:47:10] [ENEMY] [CorridorEnemy6] State: IDLE -> PURSUING
[18:47:10] [ENEMY] [CorridorEnemy4] State: IDLE -> PURSUING
```
Player is at position (200, 850). CorridorEnemy5 is at (750, 1150) — that's ~900 pixels away.
The state transition happens via `P1:visible` (player visible through line-of-sight).

**Root cause:** The original map had no vertical dividers separating the spawn zone from the corridor zones. The corridor walls (y=400/700 for top corridor, y=1000/1300 for bottom) only blocked horizontal passage but left the entire map open left-to-right. With `detection_range = 0` (unlimited), any enemy in line-of-sight to the player would immediately enter combat.

**Map coordinates analysis:**
- Player spawn: (200, 850) — in the open center-left area
- Top corridor enemies: x=650-850, y=550 — visible from spawn, 450-650 px away
- Bottom corridor enemies: x=650-850, y=1150 — also visible from spawn
- No walls between x=64 (left boundary) and x=500 (start of corridor walls)

**Fix applied:**
1. Added `ZoneDividers` node with vertical wall segments at x=480 and x=1000, covering y=64 to y=592 (top) and y=1208 to y=1664 (bottom), leaving only a narrow passage at y=700-1000 center for player movement between zones
2. Set `detection_range = 350.0` on all corridor enemies (previously 0 = unlimited)
3. Corridor enemies at x=620-860 are now 160-350px inside their corridor zone — safely beyond detection range from spawn

### Bug 2: Forced revolver weapon selection

**Symptom:** `_setup_selected_weapon()` removed all non-revolver weapons from the player and forced-equipped the RSh-12 revolver, removing player choice.

**Evidence from revolver_level.gd (original):**
```gdscript
# Remove any existing weapon
for weapon_name in ["MakarovPM", "Shotgun", "MiniUzi", "SilencedPistol", "SniperRifle", "AssaultRifle", "AKGL"]:
    var weapon = _player.get_node_or_null(weapon_name)
    if weapon:
        weapon.queue_free()
```

**Root cause:** The initial implementation incorrectly interpreted "map designed for revolver" as "always uses revolver." The correct interpretation is that the map design (corridors, cover placement) is *optimized for* revolver play, but the player should be able to bring any weapon.

**Fix applied:** Removed the `_setup_selected_weapon()` function and its call from `_setup_player_tracking()`. Player keeps whatever weapon they selected.

### Bug 3: Level named "РШ-12 ПОЛИГОН" (RSh-12 Polygon/Range)

**Symptom:** Level name referred to the weapon rather than the map's visual appearance.

**Root cause:** Map was named after its intended use case rather than its layout.

**Fix applied:** Renamed to "DOUBLE CORRIDOR" which accurately describes the H-shaped layout with two parallel horizontal corridors.

---

## Map Layout Comparison

### Original Layout (broken)
```
 ┌─────────────────────────────────────┐
 │                                     │
 │ SPAWN │ [wall]──────────────[wall]  │
 │ (200, │  TOP CORRIDOR (y=400-700)   │
 │  850) │ [CE1][CE2][CE3]             │
 │       │                             │
 │       │ ← no vertical separator →   │
 │       │                             │
 │       │  BOTTOM CORRIDOR (y=1000-1300)│
 │       │ [CE4][CE5][CE6]             │
 │       │ [wall]──────────────[wall]  │
 └─────────────────────────────────────┘
CE = CorridorEnemy — ALL enemies have clear sight line to player spawn!
```

### Fixed Layout (correct)
```
 ┌─────────────────────────────────────┐
 │         │480          │1000         │
 │ ════════╪             ╪═════════════│  (top wall segments)
 │         │  [CE1][CE2][CE3]          │
 │  SPAWN  │   TOP CORRIDOR            │
 │ (200,   │             RELOAD │FINAL │
 │  850)   │             ZONE   │ZONE  │
 │         │   BOTTOM CORRIDOR         │
 │         │  [CE4][CE5][CE6]          │
 │ ════════╪             ╪═════════════│  (bottom wall segments)
 └─────────────────────────────────────┘
Vertical dividers at x=480 block sight from spawn to corridors.
Player must approach corridor entrances to trigger enemy detection.
```

---

## Game Design Analysis

### Revolver gameplay mechanics addressed

1. **Partial reload (cylinder mechanic):** Cover in reload zones at x=1000-1340 allows player to duck behind ReloadCover1/2 objects and reload between encounters.

2. **Penetration kills:** Three enemies lined up in each corridor (620, 740, 860 at same y-coordinate) allow 1-3 penetration kills per corridor with revolver's 5 rounds.

3. **Max 5 in combat:** Zone dividers at x=480 ensure player can only trigger one corridor group at a time. Maximum simultaneous combat: 3 corridor + 2 adjacent reload guards = 5 enemies.

### Detection range tuning

Setting `detection_range = 350` was chosen based on the corridor enemy positions:
- Corridor entrance (doorway at x=480): enemies are 140-380px inside the corridor
- Player approaching from spawn (x=200) reaches x=480 before any enemy enters detection range
- Once player enters the corridor (x>480), they are within detection range of at most 3 enemies per corridor (same row, same y-band)

---

## Files Modified

| File | Change |
|------|--------|
| `scenes/levels/RevolverLevel.tscn` | Complete redesign: added ZoneDividers, updated corridor walls, renamed enemies, set detection_range, renamed level label to "DOUBLE CORRIDOR" |
| `scripts/levels/revolver_level.gd` | Removed `_setup_selected_weapon()` function and its call; updated level name in print statements; updated comment/docstring |

---

## Files Added

| File | Description |
|------|-------------|
| `docs/case-studies/issue-830/game_log_20260224_184659.txt` | Game log captured by owner during playtesting showing the enemy detection bug |
| `docs/case-studies/issue-830/CASE_STUDY.md` | This document |

---

## Online Research

### Godot 4 Enemy Detection Patterns
Godot's `NavigationAgent2D` and `Area2D`-based enemy detection commonly suffer from unlimited sight-line detection when `detection_range` is not explicitly set. The standard fix is:
- Set `detection_range` to a finite value matching the intended encounter zone radius
- Add `LightOccluder2D` components on walls (already present) to support raycasting
- Use room-based level design with wall separators between zones

### Level Design for Limited-Ammo Weapons (Revolver/Shotgun)
Game design literature on limited-ammo weapons ("high impact, low capacity") recommends:
- **Encounter isolation**: Each encounter should be cleanly separated so the player cannot be overwhelmed by enemies from multiple zones simultaneously
- **Guaranteed cover approach paths**: Cover should be reachable without crossing enemy sight lines
- **Zone transitions as decision points**: Doorways/corridors between zones give the player a moment to choose whether to engage or reload first

References:
- Level design principles for tactical shooters: encounter spacing, sight-line blocking
- Doom/FEAR level design: room-clearing mechanics with door-based encounter gating

---

## Lessons Learned

1. **Always test line-of-sight before finalizing enemy placement.** In open-area maps, enemies can see across the entire map; vertical dividers must be added explicitly.

2. **`detection_range = 0` means unlimited in this codebase.** Always set an explicit value for enemies in enclosed zones.

3. **"Designed for weapon X" ≠ "forces weapon X".** Level design should reward a specific playstyle without removing player agency.

4. **Level naming should reflect appearance, not context.** Players browsing the level select will not understand "RSh-12 POLYGON" but will understand "DOUBLE CORRIDOR."
