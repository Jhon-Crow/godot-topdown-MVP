# Case Study: Issue #1567 — Fix Sewer Map (Black Spot + Visual Details)

## Summary

After PR #1503 was merged, the sewer map (Канализация / SewerLevel) still had a visual defect: a black void area visible in the exit room section of the map. A previous fix (commit `4cccb19c` in PR #1503 review) incorrectly painted the top-room alcove area (X=288–550, Y=450–1362) which was not the problem area. The actual black spot was in the passage between Room A and Room B (the exit room approach area: X=1424–1600, Y=1538–2050). Additionally, the issue requested purely visual detailing of the map without adding new obstacles or enemies.

---

## Problem Description

### Primary Issue: Black Spot in Exit Room
- **Location:** Between Room A (X=950–1424) and Room B / exit room (X=1600–2100)
- **Coordinates:** X=1424–1600, Y=1538–2050 (176×512 pixels)
- **Visual symptom:** Dark background color (0.04, 0.06, 0.05) visible as a black void in the passage area between the two main side rooms
- **Root cause:** When Room A and Room B were added to the map (commit `9813c12a`), `FloorRightBend` was reduced from covering Y=1538–2200 to only Y=2050–2200. The area X=1424–1600, Y=1538–2050 was left uncovered by any floor tile, showing the background through.

### Secondary Issue: Prior Incorrect Fix
- Commit `4cccb19c` added `FloorTopRoomAlcove` (X=288–550, Y=450–1362) in response to the PR comment screenshot
- The owner (Jhon-Crow) confirmed via issue #1567 that this painted the WRONG spot
- The actual problem (exit room passage area) remained unfixed

### Tertiary Issue: Visual Detailing
- The sewer map lacked visual variety — all floors used the same flat dark color
- No drain grates, wall markings, floor stains, or pipe-along-wall details existed
- The issue requested visual enrichment without adding new gameplay elements

---

## Timeline / Sequence of Events

| Commit / PR | What Happened |
|-------------|---------------|
| `238a2caf` | Redesigned sewer level — top room added |
| `9813c12a` | Added Room A and Room B — FloorRightBend reduced from Y=1538 to Y=2050, **black spot gap introduced** |
| `e594f718` | PR #1503 initial commit — added ExitRoomMachineGunner, moved enemies |
| `99bc030c` | PR #1503 review feedback — added WallTopRoom_Bottom, changed enemy behaviors |
| `4cccb19c` | PR #1503 final fix — painted **wrong area** (top alcove) instead of exit room passage |
| `f7860317` | PR #1503 merged |
| Issue #1567 | Owner filed issue: wrong spot was painted, exit room still has black spot |

---

## Root Cause Analysis

### Map Geometry

The sewer level map uses `ColorRect` nodes as flat-colored floor tiles. The `Background` ColorRect fills the entire canvas (2200×3200) with the darkest color, and individual floor tiles overlay it with slightly lighter colors.

The critical geometry:

```
Exit Room (Room B): X=1600–2100, Y=1362–2100
  ├── FloorRightBranch: X=288–2100, Y=1362–1538 (top strip of Room B)
  └── FloorRoomB: X=1600–2100, Y=1538–2100 (main body)

Room A: X=950–1424, Y=1538–2050
  └── FloorRoomA: X=950–1424, Y=1538–2050

Bend (passage between rooms): X=1424–1600, Y=2050–2200
  └── FloorRightBend: X=1424–1600, Y=2050–2200

GAP (uncovered): X=1424–1600, Y=1538–2050 ← BLACK SPOT
  └── (nothing — background shows through)
```

### Why It Was Not Noticed Earlier

The gap at X=1424–1600, Y=1538–2050 is not navigable (the nav polygon jumps from Room A's boundary at X=1424 directly to the bend at Y=2200). However, since it is surrounded by room walls and is visible to the camera when the player is in Room A or approaching Room B, it appears as a conspicuous black void.

The player path to Room B goes: main corridor → right fork corridor → Room A → bend (bottom) → Room B, so the player does walk near this area.

---

## Solution

### 1. Fix the Black Spot

Added a new `FloorExitRoomPassage` ColorRect node to fill the gap:

```gdscript
[node name="FloorExitRoomPassage" type="ColorRect" parent="Environment"]
offset_left = 1424.0
offset_top = 1538.0
offset_right = 1600.0
offset_bottom = 2050.0
color = Color(0.12, 0.14, 0.12, 1)
```

This fills the 176×512 pixel area between Room A and Room B with the same floor color used throughout the map.

### 2. Visual Detailing

Added a `Decor` node group under `Environment` containing purely visual `ColorRect` elements:

- **Drain grates:** Small dark squares simulating floor drains at regular intervals in the main corridor (Y=900, 1600, 2000, 2400, 2800), Room A, Room B, and top room
- **Floor stains:** Slightly darker rectangular patches suggesting water stains or marks on corridor floors and in rooms
- **Wall markings:** Thin vertical strips along the left and right walls of the main corridor simulating maintenance marks or damage
- **Pipes along walls:** Small vertical colored rectangles simulating pipes running along the left wall
- **Floor variant (top room):** A subtle floor color variation in the top room

All decor elements are non-interactive (no collision, no scripts) and purely cosmetic.

---

## Related Issues and PRs

- **Issue #1438:** Original Sewer level implementation
- **Issue #1498:** Sewer map enemy layout update (PR #1503)
  - Comment #4133407772: Owner requested black spot fix + armored→force field replacement
  - Commit `4cccb19c`: Incorrectly patched top alcove instead of exit room passage
- **PR #1503:** Update Sewer map enemy layout (MERGED)
- **Issue #1567:** This issue — fix the remaining black spot + add visual details

---

## Key Lessons

1. **Screenshot ambiguity:** When a screenshot shows a black area, confirm the exact coordinates (X/Y range) before applying a fix. The top alcove image was misidentified as the top alcove area, but the owner meant the exit room passage.

2. **Floor tile coverage gaps:** When modifying room geometry, always audit every floor tile's coverage to ensure no gaps between `offset_bottom` of one tile and `offset_top` of the next.

3. **Navigation polygon ≠ visual coverage:** Non-navigable areas between rooms are still visually exposed. Walls should be drawn to cover structural gaps between rooms.

4. **Godot ColorRect for backgrounds:** The `ColorRect`-based map system requires careful manual coverage management. Each new room addition must ensure no gaps in floor tile coverage between adjacent areas.

---

## Files Changed

- `scenes/levels/SewerLevel.tscn`
  - Added `FloorExitRoomPassage` ColorRect (the fix)
  - Added `Decor` node group with 21 visual detail elements
