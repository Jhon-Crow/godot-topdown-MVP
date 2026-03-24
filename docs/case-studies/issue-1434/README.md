# Case Study: Issue #1434 — Difficulty Label Hidden Behind Revolver Drum UI

## Overview

**Issue**: The "Difficulty: Hard" HUD label was obscured by the revolver cylinder drum visualization in the top-left HUD area. Additionally, "Kills" and "Accuracy" debug labels were appearing on some levels in non-debug contexts. On some levels (e.g. Building), the difficulty label disappeared entirely.

**Reporter**: Jhon-Crow
**Affected levels**: ALL levels that support equipping a Revolver weapon (RevolverLevel, BuildingLevel, CityLevel, FactoryLevel, DocksLevel, DecadenceLevel, BeachLevel, CastleLevel, LabyrinthLevel, Labyrinth2Level, TestTier, RoguelikeLevel, ArenaLevel)

---

## Artifacts Collected

- `game_log_20260324_134754.txt` — Game session log from owner showing the bug in production (first feedback)
- `game_log_20260324_141539.txt` — Game session log from owner showing the bug after first fix attempt (second feedback)
- `screenshot_not_fixed.png` — Screenshot showing the drum still covering "Difficulty: Hard" after the first fix attempt
- `screenshot2.png` — Screenshot showing the drum still partially covering "Difficulty: Hard" after the second fix (revolver_level)
- `screenshot_building.png` — Screenshot showing the difficulty label completely absent on Building level after second fix

---

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-03-24 ~10:00 | First fix committed: moved DifficultyLabel from y=45 to y=65 in revolver_level.gd |
| 2026-03-24 10:13 | Second fix: DifficultyLabel y=65→70, OffsetBottom 62→68, kill/accuracy labels guarded by debug mode |
| 2026-03-24 10:49 | Owner reports: STILL not fixed, screenshot shows drum still covering difficulty text |
| 2026-03-24 10:49 | Owner also reports kills/accuracy still showing on some levels |
| 2026-03-24 ~11:00 | Third fix: killed KillsLabel/AccuracyLabel conditional guard, DifficultyLabel y=70 |
| 2026-03-24 ~14:15 | Owner reports (second feedback): original problem persists on revolver_level (y=70 too close), AND on Building level difficulty label disappeared entirely |
| 2026-03-24 20:28 | AI work session started to investigate |
| 2026-03-24 ~21:00 | Root cause discovered: ALL 13 level scripts had DifficultyLabel at y=45 (obscured by drum y=30-68); only revolver_level.gd was previously fixed |

---

## Root Cause Analysis

### Issue 1: DifficultyLabel Obscured on revolver_level

**Root cause (final)**: Insufficient margin between drum visual bottom (y=68) and DifficultyLabel top.

- First fix: y=65 (still 3px INSIDE drum area)
- Second fix: y=70 (only 2px gap — visually imperceptible at game's canvas scaling)
- **Correct fix**: y=80 (12px gap — clearly visible)

The `RevolverCylinderUI` draws a semi-transparent dark background panel:
```
panelHeight = ActiveSlotRadius*2 + panelPadding*2 = 11*2 + 8*2 = 38px
Control at OffsetTop=30, OffsetBottom=68 → visual bottom = y=68
```

With `window/stretch/mode="canvas_items"` scaling, even a 2px gap can appear as a visual overlap.

### Issue 2: DifficultyLabel Completely Hidden on Building Level (and 12 other levels)

**Root cause**: The first and second fixes ONLY updated `revolver_level.gd`. All other 12 level scripts (`building_level.gd`, `city_level.gd`, `factory_level.gd`, `docks_level.gd`, etc.) still had `DifficultyLabel` at `offset_top=45`, which is **inside** the drum panel area (y=30-68).

When a Revolver is equipped on any of these levels:
1. `Revolver.cs::SetupCylinderHUD()` creates `RevolverCylinderUI` at `OffsetTop=30, OffsetBottom=68`
2. The dark background panel renders from y=30 to y=68
3. `DifficultyLabel` at y=45 is completely covered by this panel
4. On Building level specifically, the label appeared to disappear entirely (y=45 is at the center of the drum panel)

### Issue 3: Kills/Accuracy Labels Showing in Non-Debug Mode

**Root cause**: `LevelInitFallback.cs`'s `SetupDebugUI()` created `KillsLabel` and `AccuracyLabel` unconditionally regardless of `ExperimentalSettings.debug_mode_enabled`.

**Fix**: Guard behind `is_debug_mode_enabled()` check (already applied in second fix commit).

---

## HUD Layout (Correct After Final Fix)

```
y=10  AmmoLabel top
y=30  Drum (RevolverCylinderUI) top
y=45  AmmoLabel bottom
y=68  Drum visual bottom (OffsetTop=30 + panelHeight=38)
      ← 12px gap ←
y=80  DifficultyLabel top  ← FIXED (was 45 on most levels, 70 on revolver_level)
y=110 DifficultyLabel bottom
      ← 5px gap ←
y=115 MagazinesLabel top   ← also adjusted to avoid overlap
y=145 MagazinesLabel bottom
```

---

## Files Changed (Final Fix)

1. **`scripts/levels/revolver_level.gd`**: DifficultyLabel `offset_top` 70→80, `offset_bottom` 100→110; MagazinesLabel 105→115/135→145
2. **`scripts/levels/building_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
3. **`scripts/levels/city_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
4. **`scripts/levels/factory_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
5. **`scripts/levels/docks_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
6. **`scripts/levels/decadence_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
7. **`scripts/levels/beach_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
8. **`scripts/levels/castle_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
9. **`scripts/levels/labyrinth_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
10. **`scripts/levels/labyrinth2_level.gd`**: DifficultyLabel 45→80/75→110
11. **`scripts/levels/test_tier.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
12. **`scripts/levels/roguelike_level.gd`**: DifficultyLabel 45→80/75→110; MagazinesLabel 105→115/135→145
13. **`scripts/levels/arena_level.gd`**: DifficultyLabel 72→80/102→110
14. **`Scripts/Components/LevelInitFallback.cs`**: KillsLabel 70→80/100→110; AccuracyLabel 100→115/130→145; MagazinesLabel 125→150/155→180

---

## References

- [Godot Issue #94150](https://github.com/godotengine/godot/issues/94150) — GDScript binary tokenization bug (why LevelInitFallback exists)
- Issue #691 — Original RevolverCylinderUI implementation
- Issue #770 — Cylinder transparency during reload
