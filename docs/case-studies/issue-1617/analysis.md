# Case Study: Issue #1617 — Room name must match room visual

## Problem Statement

**Issue:** `update рогалик` — room names are not connected to their visuals.
All rooms in the roguelike mode look grey with grey walls regardless of their type
(Labyrinth, Building, Beach, Docks, City, Sewer).

**Request (Russian):** *"сейчас название комнаты никак не связано с её визуалом.
сделай чтоб название соответствовало визуалу (сейчас все комнаты серые со стенами)"*

Translation: *"Right now the room name is not connected to the visual. Make the name
match the visual (currently all rooms are grey with walls)."*

## Root Cause Analysis

In `scripts/levels/roguelike_level.gd`:

1. A `ROOM_FLOOR_COLORS` dictionary already exists mapping each `RoomType` to a
   distinct floor tint (added in a previous issue).
2. However, `_create_wall()` uses the single constant `WALL_COLOR = Color(0.3, 0.3, 0.35)`
   for **every** wall in every room, regardless of type.
3. Because walls dominate the visual impression of a room, all rooms look identical
   (grey) despite having different names in the HUD (`_get_room_progress_text`).

```gdscript
# Before the fix — hardcoded single grey for all walls:
func _create_wall(parent: Node, rect: Rect2) -> void:
    ...
    visual.color = WALL_COLOR   # always the same grey
```

## Solution

### Approach chosen: per-type wall colour via instance variable

Adding 84 optional `color` parameters to every `_create_wall` call site would be
error-prone. Instead, a single `_current_wall_color` instance variable is set once
in `_build_room()` and consumed by every `_create_wall()` call.

```gdscript
## Wall tint per room type — Issue #1617
const ROOM_WALL_COLORS: Dictionary = {
    RoomType.LABYRINTH: Color(0.28, 0.30, 0.38, 1.0),  # Blue-grey stone
    RoomType.BUILDING:  Color(0.38, 0.30, 0.28, 1.0),  # Warm brick-red
    RoomType.BEACH:     Color(0.52, 0.46, 0.32, 1.0),  # Sandy tan
    RoomType.DOCKS:     Color(0.26, 0.32, 0.36, 1.0),  # Steel-blue metal
    RoomType.CITY:      Color(0.34, 0.34, 0.34, 1.0),  # Concrete grey
    RoomType.SEWER:     Color(0.22, 0.28, 0.22, 1.0),  # Mossy green
}

var _current_wall_color: Color = WALL_COLOR

func _build_room(parent: Node) -> void:
    # Set wall colour for this room type BEFORE any _create_wall calls.
    _current_wall_color = ROOM_WALL_COLORS.get(_room_type, WALL_COLOR)
    ...

func _create_wall(parent: Node, rect: Rect2) -> void:
    ...
    visual.color = _current_wall_color  # Now uses per-type colour
```

### Colour rationale

| Room Type | Colour | Why |
|-----------|--------|-----|
| Labyrinth | Blue-grey stone `(0.28, 0.30, 0.38)` | Cold dungeon stone corridors |
| Building  | Warm brick-red `(0.38, 0.30, 0.28)` | Interior brick/plaster walls |
| Beach     | Sandy tan `(0.52, 0.46, 0.32)` | Concrete/sand barriers outdoors |
| Docks     | Steel-blue `(0.26, 0.32, 0.36)` | Metal shipping containers |
| City      | Concrete grey `(0.34, 0.34, 0.34)` | Urban concrete cover |
| Sewer     | Mossy green `(0.22, 0.28, 0.22)` | Damp mossy underground pipes |

### Files changed

| File | Change |
|------|--------|
| `scripts/levels/roguelike_level.gd` | Added `ROOM_WALL_COLORS` const, `_current_wall_color` var, set in `_build_room`, used in `_create_wall` |
| `tests/unit/test_roguelike_level.gd` | Added 5 unit tests covering wall colour coverage and uniqueness |

## Related Patterns in the Codebase

- `ROOM_FLOOR_COLORS` (same file, line 74) — the same pattern for floor tints.
  This fix mirrors that design for wall colours.
- `DOOR_COLOR_*` constants — door colours already differentiated by map_room_type.

## Prior Art / Known Solutions

Binding of Isaac (the inspiration for this roguelike mode) uses distinct room
tilesets per room type. Since this project uses programmatic `ColorRect` walls
instead of tilesets, colour differentiation is the equivalent approach.

Godot's `CanvasItem.modulate` could also apply tints globally, but per-object
`color` on `ColorRect` is simpler and more targeted.
