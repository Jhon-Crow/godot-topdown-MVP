# Case Study: Issue #1267 — Fix Passage Waypoints on Building Map

## Overview

**Issue:** [#1267 — fix точки перехода на карте Здание](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1267)
**Fixed in:** [PR #1268](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1268)
**File affected:** `scenes/levels/BuildingLevel.tscn`
**Node path:** `Environment/PassageWaypoints`

---

## Problem Description

Several `passage_waypoints` markers in `BuildingLevel.tscn` were either:
- Placed **inside interior walls** (impassable collision geometry)
- Placed in **wrong room regions** (not at the actual passages they name)
- **Missing** at actual passage openings

The issue reporter identified this through in-game observation:
- Enemies navigating through passage waypoints would try to reach positions inside walls, causing pathfinding failures
- One waypoint was completely missing at the upper-right passage of Office 1

---

## Map Geometry Reference

### Map Bounds
- Total floor area: x=64–2464, y=64–2064
- Outer walls: 32px thick

### Room Regions (approximate interior bounds)
| Room | X range | Y range |
|------|---------|---------|
| Office 1 | 64–500 | 64–688 |
| Office 2 | 524–912 | 712–1000 |
| Corridor | 964–1364 | 712–1000 |
| Conference Room | 1388–2464 | 64–600 |
| Break Room | 1388–2464 | 800–1188 |
| Server Room | 1700–2464 | 1212–2064 |
| Main Hall | 912–1488 | 1400–2064 |
| Storage | 64–500 | 1612–2064 |
| Lobby/Lower | 64–888 | 1024–1388 |

### Key Interior Wall Bounds
| Wall node | X range | Y range |
|-----------|---------|---------|
| Room1_WallBottom | 100–500 | 688–712 |
| Room1_WallRight | 500–524 | 200–600 |
| Room2_WallLeft | 500–524 | 800–1000 |
| Room2_WallBottom | 512–912 | 1000–1024 |
| Room2_WallRight | 912–936 | 600–1000 |
| Corridor_WallTop | 964–1364 | 688–712 |
| Corridor_WallBottom | 964–1364 | 1000–1024 |
| Room3_WallLeft | 1364–1388 | 200–600 |
| Room3_WallBottom | 1376–1776 | 600–624 |
| Room4_WallLeft | 1364–1388 | 800–1000 |
| Room4_WallTop | 1376–1776 | 776–800 |
| Room5_WallTop | 1700–2100 | 1188–1212 |
| Room5_WallLeft | 1676–1700 | 1300–1700 |
| StorageRoom_WallTop | 100–500 | 1588–1612 |
| StorageRoom_WallRight | 500–524 | 1700–1900 |
| MainHall_WallLeft | 888–912 | 1400–1800 |
| MainHall_WallRight | 1488–1512 | 1400–1800 |
| MainHall_WallTop | 1000–1400 | 1376–1400 |

---

## Root Cause Analysis

### Timeline/Sequence of Events

The `PassageWaypoints` group in `BuildingLevel.tscn` was added as part of the level's AI navigation infrastructure. When the level geometry was defined, the waypoints were positioned without precise verification against the wall collision shapes.

The walls are `StaticBody2D` nodes with `RectangleShape2D` collision shapes. Each wall's actual collision footprint is: **center ± half-size**. The waypoints were placed at visually approximated positions that did not account for the exact half-sizes of the walls.

### Specific Bugs Found

| Waypoint | Old Position | Problem | New Position |
|----------|-------------|---------|-------------|
| P2_Office2_to_Corridor | (950, 700) | In the wrong area — x=950 is east of Office2 (x max=912), y=700 is above Office2 (y min=712). Not at the passage. | (716, 756) |
| P3_Corridor_to_Conference | (1376, 500) | **Inside Room3_WallLeft** (x=1364–1388, y=200–600). x=1376 AND y=500 both inside wall bounds. | (1340, 650) |
| P4_Corridor_to_BreakRoom | (1376, 900) | **Inside Room4_WallLeft** (x=1364–1388, y=800–1000). x=1376 AND y=900 both inside wall bounds. | (1340, 744) |
| P5_BreakRoom_to_ServerRoom | (1688, 1194) | In transition zone but functionally inaccessible — y=1194 is inside the BreakRoom-ServerRoom gap. The clear passage is at y=1212–1300. | (1688, 1256) |
| P10_Storage_Entrance_Left | (200, 1600) | **Inside StorageRoom_WallTop** (x=100–500, y=1588–1612). y=1600 is exactly in the wall center. | (82, 1630) |
| P11_Storage_Entrance_Right | (550, 1750) | Wrong room — x=550 is outside the Storage room (x max=500) and outside StorageRoom_WallRight. | (512, 1650) |
| P12_ServerRoom_Lower | (1700, 1750) | x=1700 is the exact edge of Room5_WallLeft right boundary (x=1676–1700). | (1750, 1750) |
| P0_Office1_Upper_to_Corridor | *(missing)* | The upper-right passage of Office1 (x=500–524, y=64–200) had no waypoint. Room1_WallRight covers y=200–600, leaving an opening y=64–200. | (512, 132) |

### Passage Openings (Reference)

**Office1 right side has TWO passages:**
1. Upper: x=500–524, y=64–200 (between map top wall and Room1_WallRight top) → covered by new P0
2. Lower: x=500–524, y=600–688 (between Room1_WallRight bottom and Room1_WallBottom) → covered by P1

**Corridor ↔ Conference Room:**
- Room3_WallLeft covers y=200–600 at x=1364–1388
- Opening below the wall: y=624–712 at x=1364–1388 (technically only 64px of clear space before Corridor_WallTop starts at y=688)
- Best waypoint: in Corridor near the opening (x<1364, y≈650)

**Corridor ↔ Break Room:**
- Room4_WallLeft covers y=800–1000 at x=1364–1388
- Room4_WallTop covers y=776–800 at x=1376–1776
- Gap: x=1364–1388, y=712–776 (64px tall)
- Best waypoint: in Corridor near the opening (x<1364, y≈744)

**Storage room entrances:**
- Left entrance: x=64–100 (36px gap left of StorageRoom_WallTop) → P10 at (82, 1630)
- Right entrance: x=500–524 at y=1612–1700 (between StorageRoom_WallTop right end and StorageRoom_WallRight top) → P11 at (512, 1650)

---

## Fix Applied

**File:** `scenes/levels/BuildingLevel.tscn`

Added 1 new waypoint (P0) and corrected positions of 7 existing waypoints in the `Environment/PassageWaypoints` node. All 13 waypoints were verified to be:
- Outside all interior wall collision shapes
- Within map bounds (x=64–2464, y=64–2064)
- At or near actual passage openings

### Verification Method

Programmatic check: extracted all wall bounds from the scene file (center ± half-size from `RectangleShape2D` definitions) and verified each waypoint coordinate against all wall rectangles.

---

## Screenshots

Original screenshots from the issue report are in `./screenshots/`:
- `img1.png` — P5_BreakRoom_to_ServerRoom visible near wall in ServerRoom area
- `img2.png` — P10/P11 Storage waypoints misplaced
- `img3.png` — Full map view showing multiple misplaced waypoints
- `img4.png` — Office2 area showing P1 and P2 misplacement
- `img5.png` — Office1 area with arrow showing missing waypoint location
