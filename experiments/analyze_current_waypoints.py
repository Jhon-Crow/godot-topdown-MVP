#!/usr/bin/env python3
"""Analyze current waypoint positions against wall geometry"""

# Interior walls: (name, center_x, center_y, half_w, half_h)
walls = [
    ("Room1_WallBottom",   300,  700,  200, 12),
    ("Room1_WallRight",    512,  400,   12, 200),
    ("Room2_WallLeft",     512,  900,   12, 100),
    ("Room2_WallBottom",   712, 1012,  200,  12),
    ("Room2_WallRight",    924,  800,   12, 200),
    ("Corridor_WallTop",  1164,  700,  200,  12),
    ("Corridor_WallBottom",1164,1012,  200,  12),
    ("Room3_WallLeft",    1376,  400,   12, 200),
    ("Room3_WallBottom",  1576,  612,  200,  12),
    ("Room4_WallLeft",    1376,  900,   12, 100),
    ("Room4_WallTop",     1576,  788,  200,  12),
    ("Room5_WallTop",     1900, 1200,  200,  12),
    ("Room5_WallLeft",    1688, 1500,   12, 200),
    ("LobbyDivider_Left",  300, 1400,  100,  12),
    ("LobbyDivider_Right", 600, 1400,  100,  12),
    ("StorageRoom_WallTop",300, 1600,  200,  12),
    ("StorageRoom_WallRight",512,1800,  12, 100),
    ("MainHall_WallLeft",  900, 1600,   12, 200),
    ("MainHall_WallRight",1500, 1600,   12, 200),
    ("MainHall_WallTop",  1200, 1388,  200,  12),
]

# Current passage waypoints
waypoints = [
    ("P0_Office1_Upper_to_Corridor", 512, 132),
    ("P1_Office1_to_Corridor", 512, 650),
    ("P2_Office2_to_Corridor", 716, 756),
    ("P3_Corridor_to_Conference", 1340, 650),
    ("P4_Corridor_to_BreakRoom", 1340, 744),
    ("P5_BreakRoom_to_ServerRoom", 1688, 1256),
    ("P6_Lobby_Left", 140, 1400),
    ("P7_Lobby_Mid", 450, 1400),
    ("P8_Lobby_Right", 750, 1400),
    ("P9_Corridor_to_MainHall", 950, 1400),
    ("P10_Storage_Entrance_Left", 82, 1630),
    ("P11_Storage_Entrance_Right", 512, 1650),
    ("P12_ServerRoom_Lower", 1750, 1750),
]

print("=== WALL BOUNDS ===")
for (n, cx, cy, hw, hh) in walls:
    print(f"  {n}: x={cx-hw}..{cx+hw}, y={cy-hh}..{cy+hh}")

print("\n=== WAYPOINT ANALYSIS ===")
for name, x, y in waypoints:
    in_walls = []
    for (wn, cx, cy, hw, hh) in walls:
        if (cx-hw) <= x <= (cx+hw) and (cy-hh) <= y <= (cy+hh):
            in_walls.append(f"{wn}")
    status = "INSIDE WALL(S): " + ", ".join(in_walls) if in_walls else "OK"
    print(f"  {name}: ({x}, {y}) -> {status}")

print("\n=== PASSAGE OPENING ANALYSIS ===")
print("Map: x=64-2464, y=64-2064")
print()
print("P0 Office1_Upper: (512, 132)")
print("  Room1_WallRight: x=500-524, y=200-600. Gap above (y<200): x=500-524, y=64-200 ✓")
print("  P0 at (512, 132) is in this gap. CORRECT.")
print()
print("P1 Office1_to_Corridor: (512, 650)")
print("  Room1_WallBottom: x=100-500, y=688-712. Room1_WallRight: x=500-524, y=200-600.")
print("  Gap between Office1 bottom wall and map edge: x=500-524, y=600-688")
print("  P1 at (512, 650) is at x=512 (between 500-524), y=650 (between 600-688). CORRECT.")
print()
print("P2 Office2_to_Corridor: (716, 756)")
print("  Office2: x=524-912, y=712-1000. Room2_WallLeft: x=500-524, y=800-1000.")
print("  P2 at (716, 756) is inside Office2 room. The PASSAGE from Office1 area to Office2 is at x=500-524, y=712-800.")
print("  This seems to be inside Office 2 but NOT at the passage entrance.")
print("  The passage between open corridor area (x=524-964) and Office2 is not a single doorway.")
print("  Office2 is open on top (y<712 is the wall boundary from Room1_WallBottom at y=688-712).")
print("  Wait: Office2 label says x=524-912, y=712-1000. Open top means passage at y=712 line.")
print("  The doorway from corridor to Office2 appears to be at the gap between walls.")
print()
print("P3 Corridor_to_Conference: (1340, 650)")
print("  Corridor: x=964-1364 (Corridor_WallTop at x=964-1364, y=688-712)")
print("  Room3_WallLeft: x=1364-1388, y=200-600. Room3_WallBottom: x=1376-1776, y=600-624.")
print("  Passage Conference<->Corridor: gap at x=1364-1388, y=624-688 (12x64 opening)")
print("  P3 at (1340, 650) is at x=1340 (inside Corridor area), y=650. OK but maybe should be AT the gap.")
print()
print("P4 Corridor_to_BreakRoom: (1340, 744)")
print("  Room4_WallLeft: x=1364-1388, y=800-1000. Room4_WallTop: x=1376-1776, y=776-800.")
print("  Corridor_WallTop at y=688-712. The passage BreakRoom<->Corridor:")
print("  Gap at x=1364-1388, y=712-776 (between Corridor_WallTop bottom y=712 and Room4_WallTop top y=776)")
print("  P4 at (1340, 744) is at x=1340 (just left of gap), y=744 (in y=712-776 range). Plausible.")
print()
print("P5 BreakRoom_to_ServerRoom: (1688, 1256)")
print("  Room5_WallLeft: x=1676-1700, y=1300-1700. Room5_WallTop: x=1700-2100, y=1188-1212.")
print("  Gap between ServerRoom top and left wall: x=1676-1700, y=1212-1300")
print("  P5 at (1688, 1256) is x=1688 (in 1676-1700), y=1256 (in 1212-1300). CORRECT.")
print()
print("P10 Storage_Entrance_Left: (82, 1630)")
print("  StorageRoom_WallTop: x=100-500, y=1588-1612.")
print("  Left gap: x=64-100, y=1588-1612. P10 at (82, 1630) -> x=82 is in 64-100 ✓, y=1630 is BELOW wall (y>1612). Slightly off.")
print("  Actually y=1630 is fine (just below the wall, which is correct for inside storage side).")
print()
print("P11 Storage_Entrance_Right: (512, 1650)")
print("  StorageRoom_WallRight: x=500-524, y=1700-1900.")
print("  Right gap: x=500-524, y=1612-1700 (between WallTop bottom and WallRight top).")
print("  P11 at (512, 1650) -> x=512 in 500-524 ✓, y=1650 in 1612-1700 ✓. CORRECT.")
