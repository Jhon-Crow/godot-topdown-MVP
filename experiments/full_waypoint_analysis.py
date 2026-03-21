#!/usr/bin/env python3
"""Full analysis of ALL obstacles vs passage waypoints"""

# All obstacles (name, center_x, center_y, half_w, half_h)
obstacles = [
    # Outer walls
    ("WallTop",    1264,   48, 1232,  16),  # y=32-64, x=32-2496
    ("WallBottom", 1264, 2080, 1232,  16),  # y=2064-2096
    ("WallLeft",     48, 1064,   16, 1032), # x=32-64
    ("WallRight",  2480, 1064,   16, 1032), # x=2464-2496
    
    # Interior walls
    ("Room1_WallBottom",   300,  700,  200, 12),
    ("Room1_WallRight",    512,  400,   12, 200),
    ("Room2_WallLeft",     512,  900,   12, 100),  # short_v
    ("Room2_WallBottom",   712, 1012,  200,  12),
    ("Room2_WallRight",    924,  800,   12, 200),
    ("Corridor_WallTop",  1164,  700,  200,  12),
    ("Corridor_WallBottom",1164,1012,  200,  12),
    ("Room3_WallLeft",    1376,  400,   12, 200),
    ("Room3_WallBottom",  1576,  612,  200,  12),
    ("Room4_WallLeft",    1376,  900,   12, 100),  # short_v
    ("Room4_WallTop",     1576,  788,  200,  12),
    ("Room5_WallTop",     1900, 1200,  200,  12),
    ("Room5_WallLeft",    1688, 1500,   12, 200),
    ("LobbyDivider_Left",  300, 1400,  100,  12),  # short_h
    ("LobbyDivider_Right", 600, 1400,  100,  12),  # short_h
    ("StorageRoom_WallTop",300, 1600,  200,  12),
    ("StorageRoom_WallRight",512,1800,  12, 100),  # short_v
    ("MainHall_WallLeft",  900, 1600,   12, 200),
    ("MainHall_WallRight",1500, 1600,   12, 200),
    ("MainHall_WallTop",  1200, 1388,  200,  12),
    
    # Corner fills (24x24, half=12x12)
    ("Room2_CornerBL",      512, 1000,   12,  12),
    ("Room2_CornerBR",      912, 1000,   12,  12),
    ("Corridor_CornerTR",  1364,  700,   12,  12),
    ("Corridor_CornerBR",  1364, 1012,   12,  12),
    ("MainHall_CornerTL",  1000, 1388,   12,  12),
    ("MainHall_CornerTR",  1400, 1388,   12,  12),
    ("StorageRoom_CornerTR",500, 1600,   12,  12),
    
    # Cover objects
    ("Desk1",   280,  250,  60, 24),  # cover_desk 120x48
    ("Desk2",   280,  450,  60, 24),
    ("Table1",  720,  850,  40, 40),  # cover_table 80x80
    ("Cabinet1",1000, 250,  24, 48),  # cover_cabinet 48x96
    ("Cabinet2",1100, 250,  24, 48),
    ("Desk3",  1600,  300,  60, 24),
    ("Desk4",  1900,  300,  60, 24),
    ("Table2", 1550,  950,  40, 40),
    ("Table3", 2000, 1500,  40, 40),
    ("Cabinet3",2300,1400,  24, 48),
    ("StorageCrate1",200,1750, 40, 40),
    ("StorageCrate2",350,1850, 40, 40),
    ("HallTable",1200,1650, 60, 24),
]

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

print("=== FULL OBSTACLE ANALYSIS ===\n")
print("Obstacle bounds:")
for (n, cx, cy, hw, hh) in obstacles:
    print(f"  {n}: x={cx-hw}..{cx+hw}, y={cy-hh}..{cy+hh}")

print("\n=== WAYPOINT STATUS ===\n")
all_ok = True
for name, x, y in waypoints:
    hits = []
    for (n, cx, cy, hw, hh) in obstacles:
        if (cx-hw) <= x <= (cx+hw) and (cy-hh) <= y <= (cy+hh):
            hits.append(f"{n}(x={cx-hw}..{cx+hw},y={cy-hh}..{cy+hh})")
    if hits:
        all_ok = False
        print(f"  *** PROBLEM: {name} ({x},{y}) is inside: {hits}")
    else:
        print(f"  OK: {name} ({x},{y})")

print()
if all_ok:
    print("ALL waypoints are clear of all obstacles!")
    
print("\n=== PASSAGE ANALYSIS ===\n")
print("Based on wall geometry, here are the actual passage openings:")
print()
print("P0 Office1 UPPER passage (512,132):")
print("  Room1_WallRight: x=500-524, y=200-600. Above it (y=64-200): gap exists.")
print("  WallTop at y=32-64. So passage at x=500-524, y=64-200.")
print("  P0 at (512,132) is in this gap. BUT: Is there actually a passage here?")
print("  Office1 upper-right corner: why would there be a passage at the very top?")
print("  The outer WallTop is at y=32-64. So x=512, y=132 is INSIDE the map but in the upper-right of Office1.")
print("  This is NOT a passage to anywhere - it's just inside Office1 corner.")
print("  Question: Is P0 supposed to be here?")
print()
print("P2 Office2 passage (716,756):")
print("  Table1 at x=680-760, y=810-890. P2 at y=756 is ABOVE table (y<810). Not in table.")
print("  But is (716,756) a meaningful passage point?")
print("  Office2 is open at the TOP (no wall at y=712 boundary except Room2_WallLeft partial).")
print("  The real Office2 entrance from corridor area: at the gap in Room2_WallLeft.")
print("  Room2_WallLeft: x=500-524, y=800-1000. Gap at y=712-800 at x=500-524.")
print("  P2 at (716,756) is NOT at this gap - it's 200px to the right, inside the room.")
print("  Should P2 be at the entrance gap? e.g., (512,756) or in the open area near top of Office2?")
print()
print("P3 Corridor_to_Conference (1340,650):")
print("  Corridor_CornerTR: x=1352-1376, y=688-712. P3 at x=1340, y=650.")  
print("  x=1340 < 1352 so not in corner fill. y=650 < 688.")
print("  This is in the area ABOVE Corridor_WallTop (which starts y=688) and BELOW Room3_WallBottom (ends y=624).")
print("  i.e., y=624-688 gap area. x=1340 is in Corridor (x<1364).")
print("  But wait: Is this passage actually at x>1364 (between rooms)?")
print("  The Conference room starts at x=1388. The wall Room3_WallLeft covers x=1364-1388, y=200-600.")
print("  Gap for Conference<->Corridor: x=1364-1388 at y=624-688 (below Room3_WallBottom, above Corridor_WallTop)")
print("  P3 at (1340,650) is in the CORRIDOR, not at/in the gap. It's 24px left of the gap (x=1364).")
print()
print("P10 Storage_Entrance_Left (82,1630):")
print("  StorageRoom_WallTop: x=100-500, y=1588-1612.")
print("  Left gap: x=64-100, y=1588-1612. P10 at x=82 is in this x range.")
print("  But y=1630 is BELOW the wall (wall ends at y=1612).")
print("  So P10 is below the Storage WallTop left gap, not IN the gap.")
print("  WallLeft (outer) at x=32-64. So at x=82, y=1630: inside Storage room (x=64-100, y=1612-2064).")
print("  This is fine - it's just inside the left entrance area of Storage.")
print()
print("P11 Storage_Entrance_Right (512,1650):")
print("  StorageRoom_CornerTR at (500,1600): x=488-512, y=1588-1612. P11 at x=512, y=1650.")
print("  y=1650 > 1612 so NOT in corner fill. x=512 is at corner fill right edge (512).")
print("  StorageRoom_WallRight: x=500-524, y=1700-1900. P11 at y=1650 < 1700. Not in WallRight.")
print("  P11 at (512,1650) seems OK but it's right at x=512 which is the right boundary of Storage.")
print("  The right entrance to Storage is at x=500-524, y=1612-1700.")
print("  P11 at (512,1650) is inside this entrance gap. CORRECT.")
