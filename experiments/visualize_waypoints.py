#!/usr/bin/env python3
"""
Visualize passage waypoints on the Building map using matplotlib
"""
import matplotlib.pyplot as plt
import matplotlib.patches as patches

fig, ax = plt.subplots(1, 1, figsize=(20, 16))

# Map bounds
MAP_X = (64, 2464)
MAP_Y = (64, 2064)

ax.set_xlim(MAP_X[0]-50, MAP_X[1]+50)
ax.set_ylim(MAP_Y[1]+50, MAP_Y[0]-50)  # Flip Y axis (Godot: 0 at top)
ax.set_aspect('equal')
ax.grid(True, alpha=0.3)

# Outer walls (map boundary)
outer = patches.Rectangle((64, 64), 2400, 2000, linewidth=2, edgecolor='black', facecolor='#c8b89a', alpha=0.3)
ax.add_patch(outer)

# Interior walls: (name, center_x, center_y, half_w, half_h)
walls = [
    ("Room1_WallBottom",   300,  700,  200, 12),   # Office1 bottom: x=100-500, y=688-712
    ("Room1_WallRight",    512,  400,   12, 200),   # Office1 right: x=500-524, y=200-600
    ("Room2_WallLeft",     512,  900,   12, 100),   # Office2 left: x=500-524, y=800-1000
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

for (name, cx, cy, hw, hh) in walls:
    r = patches.Rectangle((cx-hw, cy-hh), 2*hw, 2*hh, 
                           linewidth=1, edgecolor='darkgray', facecolor='#555555', alpha=0.8)
    ax.add_patch(r)

# Room regions
rooms = [
    ("OFFICE 1",       80,    80, 420,  608, '#88cc88'),
    ("OFFICE 2",      524,   712, 388,  288, '#88cc88'),
    ("CORRIDOR",      524,   712, 840,  288, '#cccc88'),  # approx, between rooms
    ("CONFERENCE",   1388,    80, 1060, 520, '#8888cc'),
    ("BREAK ROOM",   1388,   800, 1060, 388, '#cc8888'),
    ("SERVER ROOM",  1700,  1212, 748,  836, '#cc88cc'),
    ("MAIN HALL",     912,  1400, 576,  648, '#ccaa88'),
    ("STORAGE",        80,  1612, 420,  436, '#88aacc'),
    ("LOBBY/OPEN",     80,  1024, 808,  376, '#aabb88'),
]

for (name, x, y, w, h, color) in rooms:
    r = patches.Rectangle((x, y), w, h, linewidth=1, edgecolor=color, 
                           facecolor=color, alpha=0.2)
    ax.add_patch(r)
    ax.text(x + w/2, y + h/2, name, ha='center', va='center', fontsize=8, 
            color='black', alpha=0.7)

# Current passage waypoints
waypoints = [
    ("P0_Office1_Upper", 512, 132),
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

for i, (name, x, y) in enumerate(waypoints):
    # Check if in wall
    in_wall = False
    for (wn, cx, cy, hw, hh) in walls:
        if (cx-hw) <= x <= (cx+hw) and (cy-hh) <= y <= (cy+hh):
            in_wall = True
            break
    color = 'red' if in_wall else 'lime'
    ax.plot(x, y, 'o', color=color, markersize=10, zorder=10)
    ax.annotate(name, (x, y), textcoords="offset points", xytext=(5, 5),
                fontsize=6, color='blue', zorder=11)

ax.set_title('Building Level - Passage Waypoints\n(Green=OK, Red=In Wall)\nY-axis: top=0, increases downward', 
             fontsize=12)
ax.set_xlabel('X coordinate')
ax.set_ylabel('Y coordinate')

plt.tight_layout()
plt.savefig('/tmp/gh-issue-solver-1774075424684/experiments/waypoint_map.png', dpi=100, bbox_inches='tight')
print("Saved to experiments/waypoint_map.png")

# Also print analysis
print("\n=== WAYPOINT POSITIONS ===")
for name, x, y in waypoints:
    in_walls = []
    for (wn, cx, cy, hw, hh) in walls:
        if (cx-hw) <= x <= (cx+hw) and (cy-hh) <= y <= (cy+hh):
            in_walls.append(f"{wn} (x={cx-hw}-{cx+hw}, y={cy-hh}-{cy+hh})")
    status = "INSIDE WALL: " + str(in_walls) if in_walls else "OK"
    print(f"  {name}: ({x}, {y}) -> {status}")

print("\n=== PASSAGE OPENINGS (gaps in walls) ===")
print("Office1 upper-right gap: x=500-524, y=64-200 (above Room1_WallRight)")
print("Office1->Corridor gap: x=500-964, y=688-712 (between Room1_WallBottom end and Corridor_WallTop)")
print("Office2 top gap: x=500-524, y=712-800 (between Office1's area and Room2_WallLeft start)")
print("Office2->Corridor gap: x=912-964, y=712-1000 (between Room2_WallRight and Corridor start)")
print("Corridor->Conference gap: x=1364-1388, y=624-688 (below Room3_WallBottom, above Corridor_WallTop)")
print("Corridor->BreakRoom gap: x=1364-1388, y=800-788 -- PROBLEM: Room4_WallLeft y=800-1000, Room4_WallTop y=776-800")
print("  => gap is at x=1364-1388, y=712-776 (between Corridor_WallTop y=688-712 and Room4_WallTop y=776-800)")
print("BreakRoom->ServerRoom gap: x=1676-1700, y=1212-1300 (below Room5_WallTop, above Room5_WallLeft top)")
print("Lobby left gap: x=64-200, y=1388-1412 (left of LobbyDivider_Left)")
print("Lobby mid gap: x=400-500, y=1388-1412 (between LobbyDivider_Left and LobbyDivider_Right)")
print("Lobby right gap: x=700-888, y=1388-1412 (right of LobbyDivider_Right)")
print("Storage left entrance: x=64-100, y=1588-1612 (left gap at StorageRoom_WallTop)")
print("Storage right entrance: x=500-524, y=1612-1700 (right gap, StorageRoom_WallRight starts y=1700)")
print("ServerRoom lower: anywhere inside x=1700-2448, y=1212-2048")
