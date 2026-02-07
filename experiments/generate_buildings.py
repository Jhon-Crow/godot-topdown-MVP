#!/usr/bin/env python3
"""Generate CityLevel.tscn building wall segments with doorways and shooting holes.

Each building is converted from a solid block to 4 wall segments (16px thick)
with a doorway (60px gap for large, 50px for small buildings) on one side
and 2 shooting slits (20px gaps) on the opposite side.

Door placement rotates around buildings to add variety.
"""

WALL_THICKNESS = 16  # px
DOOR_GAP = 60  # px - large enough for player/enemies
SLIT_GAP = 20  # px - shooting holes (too small to walk through)

# Large building: 300x300
# Small building: 200x200

# Building definitions: (name, center_x, center_y, size, door_side)
# door_side: 'bottom', 'top', 'left', 'right' (rotated for variety)
BUILDINGS = [
    # Row A (y=800) - 6 large buildings
    ("BuildingA1", 800, 800, 300, "bottom"),
    ("BuildingA2", 1600, 800, 300, "left"),
    ("BuildingA3", 2400, 800, 300, "bottom"),
    ("BuildingA4", 3200, 800, 300, "right"),
    ("BuildingA5", 4000, 800, 300, "bottom"),
    ("BuildingA6", 4800, 800, 300, "left"),
    # Row B (y=1800) - mixed sizes
    ("BuildingB1", 1200, 1800, 300, "top"),
    ("BuildingB2", 2000, 1800, 300, "right"),
    ("BuildingB3", 2800, 1800, 200, "bottom"),
    ("BuildingB4", 3600, 1800, 300, "left"),
    ("BuildingB5", 4400, 1800, 300, "top"),
    ("BuildingB6", 5200, 1800, 300, "right"),
    # Row C (y=2800)
    ("BuildingC1", 800, 2800, 300, "right"),
    ("BuildingC2", 1600, 2800, 200, "top"),
    ("BuildingC3", 2400, 2800, 300, "left"),
    ("BuildingC4", 3200, 2800, 300, "bottom"),
    ("BuildingC5", 4000, 2800, 200, "right"),
    ("BuildingC6", 4800, 2800, 300, "top"),
    # Row D (y=3800)
    ("BuildingD1", 1200, 3800, 300, "bottom"),
    ("BuildingD2", 2000, 3800, 300, "left"),
    ("BuildingD3", 2800, 3800, 300, "top"),
    ("BuildingD4", 3600, 3800, 200, "right"),
    ("BuildingD5", 4400, 3800, 300, "bottom"),
    ("BuildingD6", 5200, 3800, 300, "left"),
    # Row E (y=4600)
    ("BuildingE1", 800, 4600, 200, "top"),
    ("BuildingE2", 1600, 4600, 300, "right"),
    ("BuildingE3", 3200, 4600, 300, "left"),
    ("BuildingE4", 4800, 4600, 300, "bottom"),
]

# Colors
WALL_COLOR = "Color(0.35, 0.3, 0.26, 1)"  # Slightly lighter than old solid blocks
FLOOR_COLOR = "Color(0.22, 0.2, 0.18, 1)"  # Darker floor inside buildings


def gen_wall_segment(parent_path: str, name: str, pos_x: float, pos_y: float,
                     width: float, height: float, sub_id: str) -> str:
    """Generate a single wall segment node (StaticBody2D with collision, visual, occluder)."""
    hw = width / 2
    hh = height / 2
    return f"""
[node name="{name}" type="StaticBody2D" parent="{parent_path}"]
position = Vector2({pos_x}, {pos_y})
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="{parent_path}/{name}"]
offset_left = {-hw}
offset_top = {-hh}
offset_right = {hw}
offset_bottom = {hh}
color = {WALL_COLOR}

[node name="CollisionShape2D" type="CollisionShape2D" parent="{parent_path}/{name}"]
shape = SubResource("{sub_id}")

[node name="LightOccluder2D" type="LightOccluder2D" parent="{parent_path}/{name}"]
occluder = SubResource("Occluder_{sub_id}")
"""


def gen_floor(parent_path: str, half_size: float) -> str:
    """Generate floor inside building."""
    inner = half_size - WALL_THICKNESS
    return f"""
[node name="Floor" type="ColorRect" parent="{parent_path}"]
offset_left = {-inner}
offset_top = {-inner}
offset_right = {inner}
offset_bottom = {inner}
color = {FLOOR_COLOR}
"""


def generate_building(name: str, cx: int, cy: int, size: int, door_side: str):
    """Generate a building with walls, doorway, and shooting slits.

    Returns (sub_resources: str, nodes: str)
    """
    half = size / 2
    wt = WALL_THICKNESS
    hwt = wt / 2  # half wall thickness
    door_gap = DOOR_GAP if size >= 300 else 50
    slit_gap = SLIT_GAP

    parent = f"Environment/Buildings/{name}"
    subs = []
    nodes = []

    # Building container node (Node2D at building center)
    nodes.append(f"""
[node name="{name}" type="Node2D" parent="Environment/Buildings"]
position = Vector2({cx}, {cy})
""")

    # Floor
    nodes.append(gen_floor(parent, half))

    # For each side, determine if it has a door, slits, or is solid
    # Opposite to door side gets slits; other two sides are solid
    opposite = {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
    slit_side = opposite[door_side]

    sides = {
        "top":    {"axis": "h", "pos_y": -half + hwt, "pos_x": 0, "length": size, "thickness": wt},
        "bottom": {"axis": "h", "pos_y":  half - hwt, "pos_x": 0, "length": size, "thickness": wt},
        "left":   {"axis": "v", "pos_x": -half + hwt, "pos_y": 0, "length": size, "thickness": wt},
        "right":  {"axis": "v", "pos_x":  half - hwt, "pos_y": 0, "length": size, "thickness": wt},
    }

    for side_name, info in sides.items():
        is_door = (side_name == door_side)
        is_slit = (side_name == slit_side)

        if not is_door and not is_slit:
            # Solid wall
            if info["axis"] == "h":
                w, h = info["length"], info["thickness"]
                px, py = info["pos_x"], info["pos_y"]
            else:
                w, h = info["thickness"], info["length"]
                px, py = info["pos_x"], info["pos_y"]

            sid = f"Shape_{name}_{side_name}"
            subs.append(gen_sub_rect(sid, w, h))
            subs.append(gen_sub_occluder(f"Occluder_{sid}", w, h))
            nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}", px, py, w, h, sid))

        elif is_door:
            # Wall with door gap in center
            # Split into 2 segments with a gap in the middle
            if info["axis"] == "h":
                seg_len = (info["length"] - door_gap) / 2
                y = info["pos_y"]
                # Left segment
                x1 = -half + seg_len / 2
                sid1 = f"Shape_{name}_{side_name}_L"
                subs.append(gen_sub_rect(sid1, seg_len, wt))
                subs.append(gen_sub_occluder(f"Occluder_{sid1}", seg_len, wt))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_L", x1, y, seg_len, wt, sid1))
                # Right segment
                x2 = half - seg_len / 2
                sid2 = f"Shape_{name}_{side_name}_R"
                subs.append(gen_sub_rect(sid2, seg_len, wt))
                subs.append(gen_sub_occluder(f"Occluder_{sid2}", seg_len, wt))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_R", x2, y, seg_len, wt, sid2))
            else:
                seg_len = (info["length"] - door_gap) / 2
                x = info["pos_x"]
                # Top segment
                y1 = -half + seg_len / 2
                sid1 = f"Shape_{name}_{side_name}_T"
                subs.append(gen_sub_rect(sid1, wt, seg_len))
                subs.append(gen_sub_occluder(f"Occluder_{sid1}", wt, seg_len))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_T", x, y1, wt, seg_len, sid1))
                # Bottom segment
                y2 = half - seg_len / 2
                sid2 = f"Shape_{name}_{side_name}_B"
                subs.append(gen_sub_rect(sid2, wt, seg_len))
                subs.append(gen_sub_occluder(f"Occluder_{sid2}", wt, seg_len))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_B", x, y2, wt, seg_len, sid2))

        elif is_slit:
            # Wall with 2 small shooting slits
            # Split into 3 segments with 2 small gaps
            if info["axis"] == "h":
                total_len = info["length"]
                # 3 segments + 2 gaps of slit_gap
                seg_len = (total_len - 2 * slit_gap) / 3
                y = info["pos_y"]
                # Left segment
                x1 = -half + seg_len / 2
                sid1 = f"Shape_{name}_{side_name}_1"
                subs.append(gen_sub_rect(sid1, seg_len, wt))
                subs.append(gen_sub_occluder(f"Occluder_{sid1}", seg_len, wt))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_1", x1, y, seg_len, wt, sid1))
                # Center segment
                x2 = 0
                sid2 = f"Shape_{name}_{side_name}_2"
                subs.append(gen_sub_rect(sid2, seg_len, wt))
                subs.append(gen_sub_occluder(f"Occluder_{sid2}", seg_len, wt))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_2", x2, y, seg_len, wt, sid2))
                # Right segment
                x3 = half - seg_len / 2
                sid3 = f"Shape_{name}_{side_name}_3"
                subs.append(gen_sub_rect(sid3, seg_len, wt))
                subs.append(gen_sub_occluder(f"Occluder_{sid3}", seg_len, wt))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_3", x3, y, seg_len, wt, sid3))
            else:
                total_len = info["length"]
                seg_len = (total_len - 2 * slit_gap) / 3
                x = info["pos_x"]
                # Top segment
                y1 = -half + seg_len / 2
                sid1 = f"Shape_{name}_{side_name}_1"
                subs.append(gen_sub_rect(sid1, wt, seg_len))
                subs.append(gen_sub_occluder(f"Occluder_{sid1}", wt, seg_len))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_1", x, y1, wt, seg_len, sid1))
                # Center segment
                y2 = 0
                sid2 = f"Shape_{name}_{side_name}_2"
                subs.append(gen_sub_rect(sid2, wt, seg_len))
                subs.append(gen_sub_occluder(f"Occluder_{sid2}", wt, seg_len))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_2", x, y2, wt, seg_len, sid2))
                # Bottom segment
                y3 = half - seg_len / 2
                sid3 = f"Shape_{name}_{side_name}_3"
                subs.append(gen_sub_rect(sid3, wt, seg_len))
                subs.append(gen_sub_occluder(f"Occluder_{sid3}", wt, seg_len))
                nodes.append(gen_wall_segment(parent, f"Wall_{side_name.capitalize()}_3", x, y3, wt, seg_len, sid3))

    return "\n".join(subs), "\n".join(nodes)


def gen_sub_rect(sid: str, w: float, h: float) -> str:
    return f'[sub_resource type="RectangleShape2D" id="{sid}"]\nsize = Vector2({w}, {h})\n'


def gen_sub_occluder(sid: str, w: float, h: float) -> str:
    hw = w / 2
    hh = h / 2
    return f'[sub_resource type="OccluderPolygon2D" id="{sid}"]\npolygon = PackedVector2Array({-hw}, {-hh}, {hw}, {-hh}, {hw}, {hh}, {-hw}, {hh})\n'


def main():
    all_subs = []
    all_nodes = []

    for b in BUILDINGS:
        subs, nodes = generate_building(*b)
        all_subs.append(subs)
        all_nodes.append(nodes)

    # Write sub_resources
    with open("/tmp/gh-issue-solver-1770476728419/experiments/building_sub_resources.txt", "w") as f:
        f.write("\n".join(all_subs))

    # Write nodes
    with open("/tmp/gh-issue-solver-1770476728419/experiments/building_nodes.txt", "w") as f:
        f.write("\n".join(all_nodes))

    print(f"Generated {len(BUILDINGS)} buildings")
    print(f"Sub-resources: {sum(s.count('[sub_resource') for s in all_subs)}")
    print(f"Nodes: {sum(n.count('[node name=') for n in all_nodes)}")


if __name__ == "__main__":
    main()
