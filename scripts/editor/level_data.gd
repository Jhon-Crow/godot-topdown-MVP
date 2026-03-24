class_name LevelData
extends RefCounted
## Data model for custom levels created in the level editor.
##
## Stores all elements of a custom level: walls, enemies, cover objects,
## player spawn point, and metadata. Supports JSON serialization for
## export/import and sharing between players.

## Current format version for forward compatibility.
const FORMAT_VERSION: int = 1

## Grid cell size in pixels (matches Hotline Miami 2 tile size x2).
const CELL_SIZE: int = 32

## Level metadata.
var level_name: String = "Untitled"
var author: String = "Player"
var description: String = ""
var map_width: int = 2400
var map_height: int = 2000

## Player spawn position.
var player_spawn: Vector2 = Vector2(200, 200)

## Wall segments: Array of dictionaries with position, size, and type.
## Each wall: {"x": float, "y": float, "w": float, "h": float}
var walls: Array[Dictionary] = []

## Enemy placements: Array of dictionaries with position and config.
## Each enemy: {"x": float, "y": float, "weapon": String, "patrol": bool}
var enemies: Array[Dictionary] = []

## Cover objects: Array of dictionaries with position, size, and type.
## Each cover: {"x": float, "y": float, "w": float, "h": float, "type": String}
## Types: "desk", "crate", "barrel", "table"
var cover_objects: Array[Dictionary] = []

## Floor color (used for background).
var floor_color: Color = Color(0.25, 0.25, 0.28, 1.0)

## Wall color.
var wall_color: Color = Color(0.35, 0.35, 0.4, 1.0)


## Convert the level data to a JSON-compatible dictionary.
func to_dict() -> Dictionary:
	var result: Dictionary = {
		"format_version": FORMAT_VERSION,
		"level_name": level_name,
		"author": author,
		"description": description,
		"map_width": map_width,
		"map_height": map_height,
		"player_spawn": {"x": player_spawn.x, "y": player_spawn.y},
		"floor_color": _color_to_dict(floor_color),
		"wall_color": _color_to_dict(wall_color),
		"walls": walls.duplicate(true),
		"enemies": enemies.duplicate(true),
		"cover_objects": cover_objects.duplicate(true),
	}
	return result


## Load level data from a JSON-compatible dictionary.
## Returns true if the data was loaded successfully.
func from_dict(data: Dictionary) -> bool:
	if not data.has("format_version"):
		return false

	var version: int = data.get("format_version", 0)
	if version < 1 or version > FORMAT_VERSION:
		return false

	level_name = data.get("level_name", "Untitled")
	author = data.get("author", "Player")
	description = data.get("description", "")
	map_width = data.get("map_width", 2400)
	map_height = data.get("map_height", 2000)

	var spawn_data: Dictionary = data.get("player_spawn", {"x": 200, "y": 200})
	player_spawn = Vector2(spawn_data.get("x", 200), spawn_data.get("y", 200))

	var fc: Dictionary = data.get("floor_color", {})
	floor_color = _dict_to_color(fc, Color(0.25, 0.25, 0.28, 1.0))

	var wc: Dictionary = data.get("wall_color", {})
	wall_color = _dict_to_color(wc, Color(0.35, 0.35, 0.4, 1.0))

	walls.clear()
	for w in data.get("walls", []):
		walls.append(w)

	enemies.clear()
	for e in data.get("enemies", []):
		enemies.append(e)

	cover_objects.clear()
	for c in data.get("cover_objects", []):
		cover_objects.append(c)

	return true


## Serialize this level to a JSON string.
func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Load level data from a JSON string.
## Returns true if parsing and loading succeeded.
func from_json(json_string: String) -> bool:
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		return false
	var data = json.data
	if not data is Dictionary:
		return false
	return from_dict(data)


## Snap a position to the grid.
static func snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		snapped(pos.x, CELL_SIZE),
		snapped(pos.y, CELL_SIZE)
	)


## Helper to convert a Color to a dictionary.
func _color_to_dict(c: Color) -> Dictionary:
	return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}


## Helper to convert a dictionary to a Color with a fallback.
func _dict_to_color(d: Dictionary, fallback: Color) -> Color:
	if d.is_empty():
		return fallback
	return Color(
		d.get("r", fallback.r),
		d.get("g", fallback.g),
		d.get("b", fallback.b),
		d.get("a", fallback.a)
	)
