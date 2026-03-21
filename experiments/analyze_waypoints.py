#!/usr/bin/env python3
"""
Analyze waypoint positions vs wall geometry in BuildingLevel.tscn
"""

# Map bounds
MAP_X = (64, 2464)
MAP_Y = (64, 2064)

# Interior walls: (name, center_x, center_y, half_w, half_h)
walls = [
    ("Room1_WallBottom",   300,  700,  200, 12),   # Office1 bottom wall: x=100-500, y=688-712
    ("Room1_WallRight",    512,  400,   12, 200),   # Office1 right wall: x=500-524, y=200-600
    ("Room2_WallLeft",     512,  900,   12, 100),   # Office2 left wall: x=500-524, y=800-1000
    ("Room2_WallBottom",   712, 1012,  200,  12),   # Office2 bottom: x=512-912, y=1000-1024
    ("Room2_WallRight",    924,  800,   12, 200),   # Office2 right: x=912-936, y=600-1000
    ("Corridor_WallTop",  1164,  700,  200,  12),   # Corridor top: x=964-1364, y=688-712
    ("Corridor_WallBottom",1164,1012,  200,  12),   # Corridor bottom: x=964-1364, y=1000-1024
    ("Room3_WallLeft",    1376,  400,   12, 200),   # Conference left: x=1364-1388, y=200-600
    ("Room3_WallBottom",  1576,  612,  200,  12),   # Conference bottom: x=1376-1776, y=600-624
    ("Room4_WallLeft",    1376,  900,   12, 100),   # BreakRoom left: x=1364-1388, y=800-1000
    ("Room4_WallTop",     1576,  788,  200,  12),   # BreakRoom top: x=1376-1776, y=776-800
    ("Room5_WallTop",     1900, 1200,  200,  12),   # ServerRoom top: x=1700-2100, y=1188-1212
    ("Room5_WallLeft",    1688, 1500,   12, 200),   # ServerRoom left: x=1676-1700, y=1300-1700
    ("LobbyDivider_Left",  300, 1400,  100,  12),   # Lobby divider left: x=200-400, y=1388-1412
    ("LobbyDivider_Right", 600, 1400,  100,  12),   # Lobby divider right: x=500-700, y=1388-1412
    ("StorageRoom_WallTop",300, 1600,  200,  12),   # Storage top: x=100-500, y=1588-1612
    ("StorageRoom_WallRight",512,1800,  12, 100),   # Storage right: x=500-524, y=1700-1900
    ("MainHall_WallLeft",  900, 1600,   12, 200),   # MainHall left: x=888-912, y=1400-1800
    ("MainHall_WallRight",1500, 1600,   12, 200),   # MainHall right: x=1488-1512, y=1400-1800
    ("MainHall_WallTop",  1200, 1388,  200,  12),   # MainHall top: x=1000-1400, y=1376-1400
]

def wall_bounds(w):
    name, cx, cy, hw, hh = w
    return (cx-hw, cx+hw, cy-hh, cy+hh)

def point_in_wall(x, y):
    """Returns list of walls that contain point (x,y)"""
    in_walls = []
    for w in walls:
        x1, x2, y1, y2 = wall_bounds(w)
        if x1 <= x <= x2 and y1 <= y <= y2:
            in_walls.append(w[0])
    return in_walls

# Current passage waypoints
waypoints = [
    ("P1_Office1_to_Corridor",     512,  650),
    ("P2_Office2_to_Corridor",     950,  700),
    ("P3_Corridor_to_Conference", 1376,  500),
    ("P4_Corridor_to_BreakRoom",  1376,  900),
    ("P5_BreakRoom_to_ServerRoom",1688, 1194),
    ("P6_Lobby_Left",              140, 1400),
    ("P7_Lobby_Mid",               450, 1400),
    ("P8_Lobby_Right",             750, 1400),
    ("P9_Corridor_to_MainHall",    950, 1400),
    ("P10_Storage_Entrance_Left",  200, 1600),
    ("P11_Storage_Entrance_Right", 550, 1750),
    ("P12_ServerRoom_Lower",      1700, 1750),
]

print("=== WAYPOINT ANALYSIS ===\n")
for name, x, y in waypoints:
    in_walls = point_in_wall(x, y)
    status = "INSIDE WALL(S): " + ", ".join(in_walls) if in_walls else "OK"
    print(f"{name}: ({x}, {y}) -> {status}")

print("\n=== WALL BOUNDS ===\n")
for w in walls:
    x1, x2, y1, y2 = wall_bounds(w)
    print(f"{w[0]}: x={x1}-{x2}, y={y1}-{y2}")

print("\n=== ROOM REGIONS (approximate passable) ===")
print("Office1:       x=64-500,   y=64-688")
print("Office2:       x=524-912,  y=712-1000")
print("Corridor:      x=964-1364, y=712-1000")
print("Conference:    x=1388-2464,y=64-600")
print("BreakRoom:     x=1388-2464,y=800-1188")
print("ServerRoom:    x=1700-2464,y=1212-2064")
print("MainHall:      x=912-1488, y=1400-2064")
print("Storage:       x=64-500,   y=1612-2064")
print("Lobby/Lower:   x=64-888,   y=1024-1388 (open area)")

print("\n=== PASSAGE OPENINGS ===")
print("Office1->corridor area: gap at x=524-964, y=688-712 (between Room1_WallBottom right end x=500 and Corridor_WallTop left end x=964)")
print("  But Room1_WallRight ends at y=600. So the passage from Office1 down is at x=500-524 gap going y=600-688 down")
print("  Actually, Office1 right wall (Room1_WallRight) covers y=200-600 at x=500-524. Gap at x=500-524, y=600-688")
print("  Then the opening between Office1 and Corridor region: x=524-964, y=688-712 is pure wall area? No—Corridor_WallTop is x=964-1364, Room1_WallBottom is x=100-500. So gap between x=500 and x=964.")
print("  The passage strip at y=688-712 has NO wall from x=500 to x=964.")
print()
print("Office2->Corridor: Room2_WallRight covers y=600-1000 at x=912-936. Corridor_WallTop covers y=688-712 at x=964-1364.")
print("  Gap in Corridor_WallTop-Room2_WallRight: at x=936-964? That's a 28px gap (narrow)")
print("  The main opening to Office2 is via the doorway where Room2_WallLeft at x=500-524, y=800-1000 has a gap above (y=712-800)")
print()
print("Conference<->Corridor: Room3_WallLeft covers x=1364-1388, y=200-600. Gap at y=600-712? (below Conference bottom)")
print("  Room3_WallBottom covers y=600-624, x=1376-1776. The corridor top wall covers y=688-712, x=964-1364.")
print("  The opening from Corridor to Conference is at x=1364-1388, y=600-688 (gap between Room3_WallBottom bottom and Corridor_WallTop)")
print("  But that's only 64px wide (x=1364-1388) and in the wall corner...")
print("  Actually: Room3_WallLeft runs y=200-600. Below that (y=600+) the x=1364-1388 strip is open until the map boundary allows passage.")
print("  Wait: Room3_WallBottom is at y=600-624, covering x=1376-1776. Room3_WallLeft is x=1364-1388, y=200-600.")
print("  So at x=1364-1376 (12px), y=600-624 there's no wall. That's a tiny gap. The real passage is at x<1364 or...")
print("  Hmm, the Conference room is x=1388-2464. Corridor is x=964-1364. The wall between them is Room3_WallLeft at x=1364-1388.")
print("  Opening in Room3_WallLeft: only at y=600-712 (below the wall segment y=200-600, above Corridor_WallTop?)") 
print("  But Room3_WallBottom covers y=600-624 at x=1376-1776 (which is inside Conference). So the opening from Corridor->Conference:")
print("  is at x=1364-1388, y=624-712? That's a 12px wide x 88px tall opening (very narrow 12px)")
print("  OR the passage is wider - perhaps the walls don't form complete enclosure and the gap is bigger.")

