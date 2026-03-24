# Case Study: Issue #1434 — Difficulty Label Hidden Behind Revolver Drum UI

## Overview

**Issue**: The "Difficulty: Hard" HUD label was obscured by the revolver cylinder drum visualization in the top-left HUD area. Additionally, "Kills" and "Accuracy" debug labels were appearing on some levels in non-debug contexts.

**Reporter**: Jhon-Crow
**Affected levels**: RevolverLevel (primary), BuildingLevel and others using `LevelInitFallback.cs`

---

## Artifacts Collected

- `game_log_20260324_134754.txt` — Game session log from owner showing the bug in production
- `screenshot_not_fixed.png` — Screenshot showing the drum still covering "Difficulty: Hard" after the first fix attempt

---

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-03-24 10:13 | First fix committed: moved DifficultyLabel from y=45 to y=65, shifted LevelInitFallback.cs debug labels by 20px |
| 2026-03-24 10:14 | Fix reported as "ready to merge" |
| 2026-03-24 10:49 | Owner (Jhon-Crow) reports: fix NOT working, screenshot shows drum still covering difficulty text |
| 2026-03-24 10:49 | Owner also reports kills/accuracy still showing on some levels |

---

## Root Cause Analysis

### Issue 1: DifficultyLabel Still Behind the Drum

**Root cause**: Off-by-6 pixel error in the first fix.

The `RevolverCylinderUI` Control node is positioned at:
- `OffsetTop = 30`
- `OffsetBottom = 62` → Control bounds height = 32px

But the actual drawn content in `_Draw()` uses:
```
panelHeight = ActiveSlotRadius * 2 + panelPadding * 2
           = 11 * 2 + 8 * 2
           = 22 + 16
           = 38px
```

The drawn content **overflows** the Control bounds by 6px:
- Control bounds: y = 30 to y = 62
- Visual content: y = 30 to y = **68** (30 + 38)

The first fix moved `DifficultyLabel` to `offset_top = 65`, which is still **3px above** the actual bottom of the drawn content (y=68). The label's background started inside the drum panel, causing the text to appear hidden behind the semi-transparent dark background.

**Fix**:
1. Update `OffsetBottom` of `RevolverCylinderUI` from 62 to 68 in both `Revolver.cs` and `LevelInitFallback.cs` to match the actual visual content height.
2. Move `DifficultyLabel` to `offset_top = 70` in `revolver_level.gd` to ensure a 2px gap below the drum.

### Issue 2: KillsLabel and AccuracyLabel Showing on Some Levels

**Root cause**: `LevelInitFallback.cs`'s `SetupDebugUI()` creates `KillsLabel` and `AccuracyLabel` **unconditionally**, regardless of whether `ExperimentalSettings.debug_mode_enabled` is true.

Affected levels (where `LevelInitFallback` C# fallback runs):
- BuildingLevel
- FactoryLevel
- CityLevel
- DocksLevel
- TestTier

**Evidence from game log** (line 658): `[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization` — this triggers `SetupDebugUI()` which creates the labels unconditionally.

Note: `ExperimentalSettings.debug_mode_enabled = true` in the owner's session (line 41 of log: `Debug: true`), which is why they saw the labels. But the correct behavior is to gate these behind the debug flag.

**Fix**: In `LevelInitFallback.cs`, check `ExperimentalSettings.is_debug_mode_enabled()` before creating `KillsLabel` and `AccuracyLabel`.

---

## HUD Layout (Correct After Fix)

```
y=10  ┌──────────────────────┐
      │  AmmoLabel            │  (y=10 to y=45)
y=45  └──────────────────────┘
y=45  ┌──────────────────────────────────────┐
      │  RevolverCylinderUI (drum)            │  (y=45 to y=83, visual height=38px)
      │  ○ ○ ● ○ ○  (5 cylinder slots)       │
y=83  └──────────────────────────────────────┘
```

Wait — actually the drum starts at y=30 (overlapping ammo label), which appears intentional for the visual effect. The correct layout is:

```
y=10  AmmoLabel top
y=30  Drum top (overlaps ammo label bottom — intentional)
y=45  AmmoLabel bottom
y=68  Drum visual bottom (OffsetTop=30 + panelHeight=38)
y=70  DifficultyLabel top  ← FIXED (was 65, now 70)
y=100 DifficultyLabel bottom
y=105 MagazinesLabel top
y=135 MagazinesLabel bottom
```

---

## Files Changed

1. **`scripts/levels/revolver_level.gd`**: DifficultyLabel `offset_top` 65 → 70, `offset_bottom` 95 → 100
2. **`Scripts/Weapons/Revolver.cs`**: RevolverCylinderUI `OffsetBottom` 62 → 68
3. **`Scripts/Components/LevelInitFallback.cs`**:
   - RevolverCylinderUI `OffsetBottom` 62 → 68
   - KillsLabel and AccuracyLabel creation guarded by `debug_mode_enabled` check

---

## References

- [Godot Issue #94150](https://github.com/godotengine/godot/issues/94150) — GDScript binary tokenization bug (why LevelInitFallback exists)
- Issue #691 — Original RevolverCylinderUI implementation
- Issue #770 — Cylinder transparency during reload
