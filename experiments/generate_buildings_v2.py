#!/usr/bin/env python3
"""Generate CityLevel.tscn with enterable buildings.

Each building has 4 wall segments (16px thick) with:
- A doorway (60px gap for large buildings, 50px for small) on one side
- 2 shooting slits (20px gaps, too small to walk through) on the opposite side
- 2 solid walls on the other sides

Optimizes by sharing sub-resources with identical dimensions.
"""

WALL_THICKNESS = 16
DOOR_GAP_LARGE = 60
DOOR_GAP_SMALL = 50
SLIT_GAP = 20

# Building definitions: (name, cx, cy, size, door_side)
BUILDINGS = [
    # Row A (y=800)
    ("BuildingA1", 800, 800, 300, "bottom"),
    ("BuildingA2", 1600, 800, 300, "left"),
    ("BuildingA3", 2400, 800, 300, "bottom"),
    ("BuildingA4", 3200, 800, 300, "right"),
    ("BuildingA5", 4000, 800, 300, "bottom"),
    ("BuildingA6", 4800, 800, 300, "left"),
    # Row B (y=1800)
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

WALL_COLOR = "Color(0.35, 0.3, 0.26, 1)"
FLOOR_COLOR = "Color(0.22, 0.2, 0.18, 1)"

def get_unique_shapes():
    """Pre-compute the set of unique (width, height) rectangles needed."""
    shapes = set()
    for _, _, _, size, door_side in BUILDINGS:
        wt = WALL_THICKNESS
        half = size / 2
        door_gap = DOOR_GAP_LARGE if size >= 300 else DOOR_GAP_SMALL
        opposite = {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
        slit_side = opposite[door_side]

        for side in ["top", "bottom", "left", "right"]:
            is_h = side in ("top", "bottom")
            is_door = (side == door_side)
            is_slit = (side == slit_side)

            if not is_door and not is_slit:
                # Solid wall
                if is_h:
                    shapes.add((size, wt))
                else:
                    shapes.add((wt, size))
            elif is_door:
                # 2 segments
                if is_h:
                    seg = (size - door_gap) / 2
                    shapes.add((seg, wt))
                else:
                    seg = (size - door_gap) / 2
                    shapes.add((wt, seg))
            elif is_slit:
                # 3 segments
                if is_h:
                    seg = (size - 2 * SLIT_GAP) / 3
                    shapes.add((seg, wt))
                else:
                    seg = (size - 2 * SLIT_GAP) / 3
                    shapes.add((wt, seg))

    return sorted(shapes)


def shape_id(w, h):
    """Generate a deterministic ID for a shape."""
    return f"Rect_{w:.0f}x{h:.0f}"


def occluder_id(w, h):
    return f"Occ_{w:.0f}x{h:.0f}"


def gen_sub_resources(shapes):
    """Generate shared sub-resources for all unique shapes."""
    lines = []
    for w, h in shapes:
        sid = shape_id(w, h)
        lines.append(f'[sub_resource type="RectangleShape2D" id="{sid}"]')
        lines.append(f'size = Vector2({w:.1f}, {h:.1f})')
        lines.append('')

        oid = occluder_id(w, h)
        hw, hh = w / 2, h / 2
        lines.append(f'[sub_resource type="OccluderPolygon2D" id="{oid}"]')
        lines.append(f'polygon = PackedVector2Array({-hw:.1f}, {-hh:.1f}, {hw:.1f}, {-hh:.1f}, {hw:.1f}, {hh:.1f}, {-hw:.1f}, {hh:.1f})')
        lines.append('')
    return '\n'.join(lines)


def gen_wall(parent, name, px, py, w, h):
    hw, hh = w / 2, h / 2
    sid = shape_id(w, h)
    oid = occluder_id(w, h)
    return f"""[node name="{name}" type="StaticBody2D" parent="{parent}"]
position = Vector2({px:.1f}, {py:.1f})
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="{parent}/{name}"]
offset_left = {-hw:.1f}
offset_top = {-hh:.1f}
offset_right = {hw:.1f}
offset_bottom = {hh:.1f}
color = {WALL_COLOR}

[node name="CollisionShape2D" type="CollisionShape2D" parent="{parent}/{name}"]
shape = SubResource("{sid}")

[node name="LightOccluder2D" type="LightOccluder2D" parent="{parent}/{name}"]
occluder = SubResource("{oid}")
"""


def gen_building(name, cx, cy, size, door_side):
    half = size / 2
    wt = WALL_THICKNESS
    hwt = wt / 2
    door_gap = DOOR_GAP_LARGE if size >= 300 else DOOR_GAP_SMALL
    opposite = {"top": "bottom", "bottom": "top", "left": "right", "right": "left"}
    slit_side = opposite[door_side]

    parent = f"Environment/Buildings/{name}"
    nodes = []

    # Container
    nodes.append(f'[node name="{name}" type="Node2D" parent="Environment/Buildings"]')
    nodes.append(f'position = Vector2({cx}, {cy})')
    nodes.append('')

    # Floor
    inner = half - wt
    nodes.append(f'[node name="Floor" type="ColorRect" parent="{parent}"]')
    nodes.append(f'offset_left = {-inner:.1f}')
    nodes.append(f'offset_top = {-inner:.1f}')
    nodes.append(f'offset_right = {inner:.1f}')
    nodes.append(f'offset_bottom = {inner:.1f}')
    nodes.append(f'color = {FLOOR_COLOR}')
    nodes.append('')

    for side in ["top", "bottom", "left", "right"]:
        is_h = side in ("top", "bottom")
        is_door = (side == door_side)
        is_slit = (side == slit_side)
        cap = side.capitalize()

        if is_h:
            wall_y = -half + hwt if side == "top" else half - hwt
        else:
            wall_x = -half + hwt if side == "left" else half - hwt

        if not is_door and not is_slit:
            if is_h:
                nodes.append(gen_wall(parent, f"Wall{cap}", 0, wall_y, size, wt))
            else:
                nodes.append(gen_wall(parent, f"Wall{cap}", wall_x, 0, wt, size))

        elif is_door:
            if is_h:
                seg = (size - door_gap) / 2
                x1 = -half + seg / 2
                x2 = half - seg / 2
                nodes.append(gen_wall(parent, f"Wall{cap}L", x1, wall_y, seg, wt))
                nodes.append(gen_wall(parent, f"Wall{cap}R", x2, wall_y, seg, wt))
            else:
                seg = (size - door_gap) / 2
                y1 = -half + seg / 2
                y2 = half - seg / 2
                nodes.append(gen_wall(parent, f"Wall{cap}T", wall_x, y1, wt, seg))
                nodes.append(gen_wall(parent, f"Wall{cap}B", wall_x, y2, wt, seg))

        elif is_slit:
            if is_h:
                seg = (size - 2 * SLIT_GAP) / 3
                x1 = -half + seg / 2
                x2 = 0
                x3 = half - seg / 2
                nodes.append(gen_wall(parent, f"Wall{cap}1", x1, wall_y, seg, wt))
                nodes.append(gen_wall(parent, f"Wall{cap}2", x2, wall_y, seg, wt))
                nodes.append(gen_wall(parent, f"Wall{cap}3", x3, wall_y, seg, wt))
            else:
                seg = (size - 2 * SLIT_GAP) / 3
                y1 = -half + seg / 2
                y2 = 0
                y3 = half - seg / 2
                nodes.append(gen_wall(parent, f"Wall{cap}1", wall_x, y1, wt, seg))
                nodes.append(gen_wall(parent, f"Wall{cap}2", wall_x, y2, wt, seg))
                nodes.append(gen_wall(parent, f"Wall{cap}3", wall_x, y3, wt, seg))

    return '\n'.join(nodes)


def main():
    shapes = get_unique_shapes()
    sub_resources = gen_sub_resources(shapes)
    building_nodes = '\n'.join(gen_building(*b) for b in BUILDINGS)

    with open("/tmp/gh-issue-solver-1770476728419/experiments/building_sub_resources.txt", "w") as f:
        f.write(sub_resources)

    with open("/tmp/gh-issue-solver-1770476728419/experiments/building_nodes.txt", "w") as f:
        f.write(building_nodes)

    print(f"Generated {len(BUILDINGS)} buildings")
    print(f"Unique shapes: {len(shapes)}")
    for w, h in shapes:
        print(f"  {w:.0f}x{h:.0f}")


if __name__ == "__main__":
    main()
