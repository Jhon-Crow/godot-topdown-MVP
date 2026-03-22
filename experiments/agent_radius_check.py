#!/usr/bin/env python3
"""Check waypoints against agent radius (24px) clearance from all obstacles"""

AGENT_RADIUS = 24  # from NavigationPolygon agent_radius

# All obstacles with their bounds
obstacles = [
    # Outer walls
    ("WallTop",    1264,   48, 1232,  16),
    ("WallBottom", 1264, 2080, 1232,  16),
    ("WallLeft",     48, 1064,   16, 1032),
    ("WallRight",  2480, 1064,   16, 1032),
    
    # Interior walls
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
    
    # Corner fills
    ("Room2_CornerBL",      512, 1000,   12,  12),
    ("Room2_CornerBR",      912, 1000,   12,  12),
    ("Corridor_CornerTR",  1364,  700,   12,  12),
    ("Corridor_CornerBR",  1364, 1012,   12,  12),
    ("MainHall_CornerTL",  1000, 1388,   12,  12),
    ("MainHall_CornerTR",  1400, 1388,   12,  12),
    ("StorageRoom_CornerTR",500, 1600,   12,  12),
    
    # Cover
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

def min_distance_to_obstacle(px, py, obstacles):
    """Find minimum distance from point to any obstacle boundary"""
    min_dist = float('inf')
    closest = None
    for (n, cx, cy, hw, hh) in obstacles:
        x1, x2, y1, y2 = cx-hw, cx+hw, cy-hh, cy+hh
        # Distance from point to rectangle
        dx = max(x1 - px, 0, px - x2)
        dy = max(y1 - py, 0, py - y2)
        dist = (dx**2 + dy**2)**0.5
        if dist < min_dist:
            min_dist = dist
            closest = (n, x1, x2, y1, y2)
    return min_dist, closest

print(f"=== WAYPOINT AGENT RADIUS CHECK (radius={AGENT_RADIUS}px) ===\n")
print(f"Waypoints must be >= {AGENT_RADIUS}px from any obstacle for agent to reach them.\n")

problems = []
for name, x, y in waypoints:
    dist, closest = min_distance_to_obstacle(x, y, obstacles)
    if dist < AGENT_RADIUS:
        status = f"TOO CLOSE! dist={dist:.1f}px to {closest[0]} (x={closest[1]}-{closest[2]}, y={closest[3]}-{closest[4]})"
        problems.append((name, x, y, dist, closest))
    else:
        status = f"OK (min dist={dist:.1f}px to {closest[0]})"
    print(f"  {name}: ({x},{y}) -> {status}")

print(f"\n{len(problems)} problem(s) found:")
for name, x, y, dist, closest in problems:
    print(f"  {name} at ({x},{y}): only {dist:.1f}px from {closest[0]}")
    print(f"    Obstacle: x={closest[1]}-{closest[2]}, y={closest[3]}-{closest[4]}")

# Also check P10 specifically
print("\n=== P10 DETAIL: (82,1630) ===")
print("  WallLeft: x=32-64. Distance from x=82: 82-64 = 18px  <-- LESS THAN 24!")
print("  WallTop (outer): y=32-64. Not relevant here.")
print("  StorageRoom_WallTop: x=100-500, y=1588-1612.")
print("    dx = max(100-82, 0, 82-500) = max(18,0,-418) = 18")
print("    dy = max(1588-1630, 0, 1630-1612) = max(-42,0,18) = 18")
print("    dist = sqrt(18^2+18^2) = sqrt(648) = 25.5px  >=24 OK")
print("  But WallLeft at x=32-64:")
print("    dx = max(32-82, 0, 82-64) = max(-50, 0, 18) = 18")
print("    dy = max(32-1630, 0, 1630-2096) = max(-1598, 0, -466) = 0  (inside y range)")
print("    dist = sqrt(18^2 + 0^2) = 18px  <-- TOO CLOSE TO OUTER WALL!")

print("\n=== P11 DETAIL: (512,1650) ===")
print("  StorageRoom_CornerTR: x=488-512, y=1588-1612.")
print("    dx = max(488-512, 0, 512-512) = max(-24, 0, 0) = 0")
print("    dy = max(1588-1650, 0, 1650-1612) = max(-62, 0, 38) = 38")
print("    dist = 38px >= 24 OK")
print("  StorageRoom_WallRight: x=500-524, y=1700-1900.")
print("    dx = max(500-512, 0, 512-524) = max(-12, 0, -12) = 0 (inside x range)")
print("    dy = max(1700-1650, 0, 1650-1900) = max(50, 0, -250) = 50")
print("    dist = 50px >= 24 OK")
print("  WallRight (outer): x=2464-2496. Very far.")
print("  P11 at (512,1650) is OK.")

print("\n=== P0 ISSUE ===")
print("  P0 at (512,132): Is this a real passage?")
print("  Room1_WallRight: x=500-524, y=200-600. P0 at y=132 is above (y<200).")
print("  WallTop (outer): y=32-64. Distance from y=132: 132-64=68px OK.")
print("  This point is in the upper-right CORNER of Office 1.")
print("  From the game perspective: there IS a gap at x=500-524, y=64-200 (between outer wall and Room1_WallRight).")
print("  This gap connects the upper-right of Office1 with... the open area at y=64-200, x=524-964?")
print("  Actually at y=132, x=512: this is between x=500-524 (in the wall gap strip). Left is Office1. Right is the open area x=524-964.")
print("  But this 'passage' leads to the open area just below the top wall - not a standard room passage.")
print("  Could be valid if enemies use it to navigate Office1 from the top.")
