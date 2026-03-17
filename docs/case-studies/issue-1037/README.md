# Case Study: Issue #1037 — Add New Map After Docks (Factory Level)

## Overview

**Issue:** [#1037](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1037)
**Title:** Add Factory level after Docks map
**Status:** Resolved in PR #1038
**Branch:** `issue-1037-547ef877fcd2`

---

## Problem Statement

The game owner (Jhon-Crow) requested a new level after the Docks map with the following requirements:

- **13 enemies total**
- **Building-style** map (similar to `BuildingLevel`)
- **Maximum 2 enemies per room**
- **All enemies: 4–6 HP**
- **No force-field (Силовое поле) enemy types**

---

## Timeline / Sequence of Events

1. **2026-03-16 (initial)** — Issue #1037 opened requesting a "Factory" level after Docks.

2. **2026-03-16 (first PR)** — PR #1038 created with `FactoryLevel.tscn` and `factory_level.gd`. The level included:
   - 7 rooms in a 3×3 grid layout (using 2 vertical column walls + 2 horizontal row walls)
   - 13 enemies distributed across rooms
   - Cover objects (crates, barrels, tables)

3. **2026-03-16 (owner feedback)** — The repository owner (Jhon-Crow) reported two bugs after reviewing the map in-game:
   - **Bug 1 — Invisible walls**: Collision shapes existed with no visible wall rectangle (the `CollisionShape2D` covered a different region than the `ColorRect`)
   - **Bug 2 — Passable visual walls**: Visual wall rectangles existed with no matching collision (the `ColorRect` displayed a wall, but players and bullets could pass through)

4. **Root cause identified**: The `ColorRect` offsets (visual) and `RectangleShape2D` sizes (physics) were authored with **mismatched dimensions**. The `ColorRect` used asymmetric offsets (e.g., `left=-1200, right=-112`) while the collision shape was always centered (symmetric around the node's position). These two did not cover the same region, producing "ghost walls" and "hollow walls".

5. **2026-03-16 (fix — wall geometry)** — Complete redesign of the interior wall layout in `FactoryLevel.tscn`:
   - All 18 interior wall segments redesigned with **exactly matching** `ColorRect` offsets and `RectangleShape2D` sizes
   - Each segment verified: `shape_width == right_offset - left_offset` and `shape_height == bottom_offset - top_offset`

6. **2026-03-16 (second owner feedback)** — The repository owner reported a second class of bug:
   - **Bug 3 — Missing passages at column intersections**: "из левых 3 комнат невозможно попасть в остальные (нет прохода, но враги там есть)" (from the left 3 rooms it's impossible to get to the others — there's no passage, but enemies are there).
   - The left column of rooms (ENTRY HALL, STORAGE, BOILER ROOM) was completely isolated from the center and right columns.

7. **Root cause identified (Bug 3)**: The row wall segments (RowTop_L2, RowTop_C1, RowMid_L2, RowMid_C1, etc.) at column wall intersections had **zero gap** — they abutted directly against the column walls leaving no doorway for the player to pass through. Similarly between center and right columns via Column B wall.

8. **2026-03-16 (fix — missing doorways)** — Fixed 8 row wall segments by shortening them to create 120px doorways centered on each column wall:
   - `RowTop_L2`, `RowMid_L2`: x range 484→720 (was 484→768), position x 626→602
   - `RowTop_C1`, `RowMid_C1`: x range 840→1104 (was 792→1104), position x 948→972
   - `RowTop_C2`, `RowMid_C2`: x range 1225→1489 (was 1225→1537), position x 1381→1357
   - `RowTop_R1`, `RowMid_R1`: x range 1610→1944 (was 1562→1944), position x 1753→1777

---

## Root Cause Analysis

### The Core Bug: Asymmetric ColorRect + Centered CollisionShape2D

In Godot 4, a `StaticBody2D`'s child `CollisionShape2D` using a `RectangleShape2D` is **always centered** on the parent node's position. The `size` property defines total width and height (half-extents are `size/2`).

A child `ColorRect`, however, is positioned using `offset_left`, `offset_top`, `offset_right`, `offset_bottom` — relative to the parent node's position. These can be **asymmetric** (e.g., all four can be different values).

The original `FactoryLevel.tscn` was authored with asymmetric `ColorRect` offsets that did NOT correspond to the symmetric collision shape. Example from the buggy file:

```
[node name="TopRow_Divider" type="StaticBody2D"]
position = Vector2(1264, 700)

# Visual: a rectangle from x=64 to x=1152 (asymmetric, 1088px wide)
[node name="ColorRect"]
offset_left = -1200.0
offset_top = -12.0
offset_right = -112.0      ← note: BOTH offsets negative = left-biased
offset_bottom = 12.0

# Collision: a centered rectangle 800px wide (extends from x=864 to x=1664)
[node name="CollisionShape2D"]
shape = SubResource("RectangleShape2D_wall_h_long")  # size = Vector2(800, 24)
```

In this example:
- Visual wall covers x = 1264-1200 to 1264-112 = **x=64 to x=1152**
- Collision covers x = 1264-400 to 1264+400 = **x=864 to x=1664**
- Overlap: only x=864 to 1152 (**288px**) — the rest are ghost/hollow walls

### Why This Produces Both Bug Types

- **Invisible walls**: Where collision extends beyond the visual rect (x=1152 to x=1664 in the example) — player is blocked by nothing visible
- **Passable visual walls**: Where the visual rect extends beyond the collision (x=64 to x=864 in the example) — player walks through visible wall

### Contributing Factor: Author Error During Map Design

The map was authored without a visual editor (hand-written `.tscn` file). Without Godot's editor showing both the visual and the physics overlay simultaneously, mismatches are easy to introduce and hard to detect by eye.

---

## Solution

### Bug 1 & 2: Invariant: Always Symmetric and Matching

For every wall segment, the following must hold:

```
ColorRect.offset_left  = -(shape_width / 2)   [for horizontal walls]
ColorRect.offset_right = +(shape_width / 2)

ColorRect.offset_top    = -(shape_height / 2)  [for vertical walls]
ColorRect.offset_bottom = +(shape_height / 2)
```

This ensures the `ColorRect` and `RectangleShape2D` cover exactly the same region, centered on the `StaticBody2D` node position.

### Redesigned Interior Wall Layout

The fixed `FactoryLevel.tscn` uses 18 interior wall segments (6 column + 12 row):

**Column walls** (vertical dividers at x=780 and x=1550):
- Each column has 3 segments with 80px doorways at y=700 and y=1300
- `ColA_Top/ColB_Top`: y=64→660, height=596, center_y=362 → `offset_top=-298, offset_bottom=298`
- `ColA_Mid/ColB_Mid`: y=740→1260, height=520, center_y=1000 → `offset_top=-260, offset_bottom=260`
- `ColA_Bot/ColB_Bot`: y=1340→2064, height=724, center_y=1702 → `offset_top=-362, offset_bottom=362`

**Row walls** (horizontal dividers at y=700 and y=1300):
- Each row is split into 3 sections (Left/Center/Right) by the column walls
- Each section has a 120px doorway in the middle
- The column wall intersection doorways were missing in the original fix — added in the second fix
- All 12 row segments use symmetric offsets matching their `RectangleShape2D` sizes

### Bug 3: Row Wall Segments Must Stop Before Column Walls

The key insight is that row wall segments must leave gaps at column walls to allow passage:

```
Left column section (x=64 to x=780):
  L1: x=80 to x=364   (within-section doorway: x=364 to x=484 = 120px)
  L2: x=484 to x=720  (column-wall doorway: x=720 to x=840 = 120px total through col wall)

Column A wall: x=768 to x=792  (24px physical wall, always present)

Center column section (x=780 to x=1550):
  C1: x=840 to x=1104  (column-wall doorway: x=720 to x=840 = 120px total through col wall)
  (within-section doorway: x=1104 to x=1225 = 121px)
  C2: x=1225 to x=1489  (column-wall doorway: x=1489 to x=1610 = 121px total through col wall)
```

**Rule**: Each row segment adjacent to a column wall must stop at `column_x ± 60px` (60px clearance on each side), creating a ~120px passable zone centered on the column wall.

---

## Verification

After both fixes, all 18 interior wall segments have matching geometry and correct doorway gaps:

```
Geometry match (ColorRect == CollisionShape2D):
✓ ColA_Top:  ColorRect=24×596,  Shape=24×596
✓ ColA_Mid:  ColorRect=24×520,  Shape=24×520
✓ ColA_Bot:  ColorRect=24×724,  Shape=24×724
✓ ColB_Top:  ColorRect=24×596,  Shape=24×596
✓ ColB_Mid:  ColorRect=24×520,  Shape=24×520
✓ ColB_Bot:  ColorRect=24×724,  Shape=24×724
✓ RowTop_L1: ColorRect=284×24,  Shape=284×24   x=80–364
✓ RowTop_L2: ColorRect=236×24,  Shape=236×24   x=484–720   (fixed: was 284)
✓ RowTop_C1: ColorRect=264×24,  Shape=264×24   x=840–1104  (fixed: was 312)
✓ RowTop_C2: ColorRect=264×24,  Shape=264×24   x=1225–1489 (fixed: was 312)
✓ RowTop_R1: ColorRect=334×24,  Shape=334×24   x=1610–1944 (fixed: was 382)
✓ RowTop_R2: ColorRect=382×24,  Shape=382×24   x=2065–2447
✓ RowMid_L1: ColorRect=284×24,  Shape=284×24   x=80–364
✓ RowMid_L2: ColorRect=236×24,  Shape=236×24   x=484–720   (fixed: was 284)
✓ RowMid_C1: ColorRect=264×24,  Shape=264×24   x=840–1104  (fixed: was 312)
✓ RowMid_C2: ColorRect=264×24,  Shape=264×24   x=1225–1489 (fixed: was 312)
✓ RowMid_R1: ColorRect=334×24,  Shape=334×24   x=1610–1944 (fixed: was 382)
✓ RowMid_R2: ColorRect=382×24,  Shape=382×24   x=2065–2447

Doorway gaps (all passages are open):
✓ ColA top doorway:   y=660–740 = 80px  (at y=700)
✓ ColA mid doorway:   y=1260–1340 = 80px (at y=1300)
✓ ColB top doorway:   y=660–740 = 80px  (at y=700)
✓ ColB mid doorway:   y=1260–1340 = 80px (at y=1300)
✓ RowTop_L doorway:   x=364–484 = 120px  (within left column)
✓ RowTop ColA door:   x=720–840 = 120px  (between left and center)
✓ RowTop_C doorway:   x=1104–1225 = 121px (within center column)
✓ RowTop ColB door:   x=1489–1610 = 121px (between center and right)
✓ RowTop_R doorway:   x=1944–2065 = 121px (within right column)
(same pattern for RowMid)
```

---

## Proposed Solution for Future Maps

See [Wall Validation Checklist](../../map-wall-validation-checklist.md) for a step-by-step guide to prevent this class of bug when adding new maps.

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1037
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1038
- Godot `RectangleShape2D` documentation: https://docs.godotengine.org/en/stable/classes/class_rectangleshape2d.html
- Godot `ColorRect` documentation: https://docs.godotengine.org/en/stable/classes/class_colorrect.html
