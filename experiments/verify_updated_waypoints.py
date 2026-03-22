#!/usr/bin/env python3
"""Verify updated waypoint positions"""

AGENT_RADIUS = 24

obstacles = [
    ("WallTop",    1264,   48, 1232,  16),
    ("WallBottom", 1264, 2080, 1232,  16),
    ("WallLeft",     48, 1064,   16, 1032),
    ("WallRight",  2480, 1064,   16, 1032),
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
    ("Room2_CornerBL",      512, 1000,   12,  12),
    ("Room2_CornerBR",      912, 1000,   12,  12),
    ("Corridor_CornerTR",  1364,  700,   12,  12),
    ("Corridor_CornerBR",  1364, 1012,   12,  12),
    ("MainHall_CornerTL",  1000, 1388,   12,  12),
    ("MainHall_CornerTR",  1400, 1388,   12,  12),
    ("StorageRoom_CornerTR",500, 1600,   12,  12),
    ("Desk1",   280,  250,  60, 24),
    ("Desk2",   280,  450,  60, 24),
    ("Table1",  720,  850,  40, 40),
    ("Cabinet1",1000, 250,  24, 48),
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

# UPDATED waypoints
waypoints = [
    ("P0_Office1_Upper_to_Corridor", 512, 132),
    ("P1_Office1_to_Corridor", 512, 650),
    ("P2_Office2_to_Corridor", 700, 740),      # CHANGED from (716, 756)
    ("P3_Corridor_to_Conference", 1376, 656),  # CHANGED from (1340, 650)
    ("P4_Corridor_to_BreakRoom", 1340, 744),
    ("P5_BreakRoom_to_ServerRoom", 1688, 1256),
    ("P6_Lobby_Left", 140, 1400),
    ("P7_Lobby_Mid", 450, 1400),
    ("P8_Lobby_Right", 750, 1400),
    ("P9_Corridor_to_MainHall", 950, 1400),
    ("P10_Storage_Entrance_Left", 200, 1680),  # CHANGED from (82, 1630)
    ("P11_Storage_Entrance_Right", 512, 1650),
    ("P12_ServerRoom_Lower", 1750, 1750),
]

def min_dist_to_obstacles(px, py):
    min_dist = float('inf')
    closest = None
    for (n, cx, cy, hw, hh) in obstacles:
        x1, x2, y1, y2 = cx-hw, cx+hw, cy-hh, cy+hh
        dx = max(x1 - px, 0, px - x2)
        dy = max(y1 - py, 0, py - y2)
        dist = (dx**2 + dy**2)**0.5
        if dist < min_dist:
            min_dist = dist
            closest = (n, x1, x2, y1, y2, dx, dy)
    return min_dist, closest

def in_any_obstacle(px, py):
    for (n, cx, cy, hw, hh) in obstacles:
        x1, x2, y1, y2 = cx-hw, cx+hw, cy-hh, cy+hh
        if x1 <= px <= x2 and y1 <= py <= y2:
            return n
    return None

print("=== UPDATED WAYPOINT VERIFICATION ===\n")
problems = []
for name, x, y in waypoints:
    in_obs = in_any_obstacle(x, y)
    dist, closest = min_dist_to_obstacles(x, y)
    
    if in_obs:
        status = f"ERROR: INSIDE {in_obs}!"
        problems.append(name)
    elif dist < AGENT_RADIUS:
        status = f"WARNING: only {dist:.1f}px from {closest[0]} (need {AGENT_RADIUS}px)"
        problems.append(name)
    else:
        status = f"OK (min dist={dist:.1f}px to {closest[0]})"
    print(f"  {name}: ({x},{y}) -> {status}")

print(f"\n{'PASS: All waypoints OK!' if not problems else 'FAIL: Problems with: ' + str(problems)}")

print("\n=== KEY PASSAGE POSITIONS ===")
print("\nP2 Office2_to_Corridor (700, 740):")
print("  Office2 interior: x=524-912, y=712-1000")
print("  Top entrance to Office2: y≈712, open from x=524 to x=912")
print("  P2 at (700, 740): 28px below top boundary, centered in office, near entrance. GOOD.")

print("\nP3 Corridor_to_Conference (1376, 656):")
print("  Room3_WallLeft: x=1364-1388, y=200-600 (Conference left wall)")
print("  Room3_WallBottom: x=1376-1776, y=600-624 (Conference bottom wall)")
print("  Corridor_WallTop: x=964-1364, y=688-712 (Corridor top wall)")
print("  Gap: x=1364-1388, y=624-688. P3 at x=1376 (in gap), y=656 (in gap).")
print("  This is AT the passage between Corridor and Conference Room. CORRECT.")

print("\nP10 Storage_Entrance_Left (200, 1680):")
print("  Storage interior: x=64-500, y=1612-2064")
print("  P10 at (200, 1680): 136px from outer wall, 68px below WallTop.")
print("  StorageCrate1 at x=160-240, y=1710-1790: distance=30px from P10. OK.")
print("  This is inside Storage room, accessible by 24px radius agent. CORRECT.")
