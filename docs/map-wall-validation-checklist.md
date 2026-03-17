# Map Wall Validation Checklist

This checklist must be followed when adding a new map to the game to prevent invisible walls and passable visual walls.

**Background**: Issue #1037 revealed that hand-authored `.tscn` files can have mismatched `ColorRect` (visual) and `RectangleShape2D` (physics collision) on wall `StaticBody2D` nodes. The `CollisionShape2D` is always **centered** on the node position, but `ColorRect` offsets can be asymmetric — this mismatch creates "invisible walls" (collision without visuals) and "passable walls" (visuals without collision).

---

## Rule: Visual and Collision Must Be Symmetric and Matching

For every wall `StaticBody2D` node, the following invariant **must hold**:

### Horizontal wall segment (width × 24):
```
ColorRect.offset_left  = -(width / 2)
ColorRect.offset_right = +(width / 2)
ColorRect.offset_top   = -12
ColorRect.offset_bottom = +12

RectangleShape2D.size = Vector2(width, 24)
```

### Vertical wall segment (24 × height):
```
ColorRect.offset_left  = -12
ColorRect.offset_right = +12
ColorRect.offset_top   = -(height / 2)
ColorRect.offset_bottom = +(height / 2)

RectangleShape2D.size = Vector2(24, height)
```

**Key**: Use **even numbers** for `width` and `height` to avoid fractional half-extents. If you have an odd size (e.g., 313), round to the nearest even number (312).

---

## Checklist

### Before Creating the Map

- [ ] Plan wall layout on paper/diagram with exact pixel coordinates
- [ ] For each wall segment, calculate: `center = (start + end) / 2`, `size = end - start`
- [ ] Verify all sizes are even numbers

### For Each Wall Segment in the TSCN File

- [ ] `StaticBody2D` position is at the **center** of the wall segment
- [ ] `ColorRect` has **symmetric** offsets: `offset_left = -(size/2)`, `offset_right = +(size/2)` (or top/bottom for vertical)
- [ ] `RectangleShape2D.size` matches `(offset_right - offset_left) × (offset_bottom - offset_top)`
- [ ] `LightOccluder2D` polygon matches the shape dimensions (half-extents in the polygon)
- [ ] Wall covers intended range: `node_position - size/2` to `node_position + size/2`

### Doorways and Gaps

- [ ] Doorways between rooms are deliberately left uncovered (no wall segment)
- [ ] No wall segments overlap each other (which can cause double-blocking)
- [ ] No unintended gaps between adjacent wall segments (which allow pass-through)

### After Creating the Map

- [ ] Open the map in Godot editor and enable **Debug > Visible Collision Shapes** (`F5` then check the debug menu)
- [ ] Verify green collision outlines exactly align with the visible wall colors
- [ ] Walk through every room boundary and doorway in a test playthrough
- [ ] Check all four outer walls (top, bottom, left, right) cannot be escaped through

### Script Verification

Run this verification script against your new `.tscn` file:

```python
import re

def verify_walls(tscn_path, parent_path="Environment/InteriorWalls"):
    with open(tscn_path) as f:
        content = f.read()

    shapes = {}
    for m in re.finditer(
        r'\[sub_resource type="RectangleShape2D" id="([^"]+)"\]\nsize = Vector2\(([^,]+), ([^)]+)\)',
        content
    ):
        shapes[m.group(1)] = (float(m.group(2)), float(m.group(3)))

    node_data = {}
    current_node = None
    for line in content.split('\n'):
        m = re.match(
            rf'\[node name="([^"]+)" type="StaticBody2D" parent="{re.escape(parent_path)}"\]',
            line
        )
        if m:
            current_node = m.group(1)
            node_data[current_node] = {}

        any_node = re.match(r'\[node name=', line)
        if any_node and current_node:
            p = re.search(r'parent="([^"]+)"', line)
            if p and not p.group(1).startswith(parent_path):
                current_node = None

        if current_node:
            for key, pattern in [
                ('left', r'offset_left = ([^\n]+)'),
                ('right', r'offset_right = ([^\n]+)'),
                ('top', r'offset_top = ([^\n]+)'),
                ('bottom', r'offset_bottom = ([^\n]+)'),
            ]:
                om = re.match(pattern, line)
                if om: node_data[current_node][key] = float(om.group(1))
            sm = re.match(r'shape = SubResource\("([^"]+)"\)', line)
            if sm: node_data[current_node]['shape'] = sm.group(1)

    errors = []
    for name, data in node_data.items():
        if 'shape' not in data or 'left' not in data:
            continue
        sw, sh = shapes.get(data['shape'], (0, 0))
        rw = data.get('right', 0) - data.get('left', 0)
        rh = data.get('bottom', 0) - data.get('top', 0)
        if abs(rw - sw) > 0.01 or abs(rh - sh) > 0.01:
            errors.append(f"{name}: ColorRect={rw}×{rh}, Shape={sw}×{sh}")
            print(f"❌ {name}: visual={rw}×{rh} but collision={sw}×{sh}")
        else:
            print(f"✓ {name}: {rw}×{rh}")

    if errors:
        print(f"\n{len(errors)} ERRORS found!")
    else:
        print("\nAll wall segments OK ✓")

verify_walls("scenes/levels/YourNewLevel.tscn")
```

---

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Asymmetric `ColorRect` offsets (e.g., both negative) | Invisible walls or passable walls | Use symmetric offsets: `left=-half`, `right=+half` |
| `ColorRect` size ≠ `RectangleShape2D` size | Collision and visual don't match | Recalculate one from the other |
| Odd-number wall size | Fractional half-extents cause 1px mismatch | Round size to nearest even number |
| Node position not at wall center | Wall appears offset from expected location | Set position to `(start + end) / 2` |
| Missing wall segment (gap) | Player/bullet can pass between rooms | Add wall segment to close gap |
| Wall segment extends into another room | Blocks doorway | Recalculate segment boundaries precisely |
